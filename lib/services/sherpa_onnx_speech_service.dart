import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart' as record_pkg;
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

/// Sherpa 语音识别服务状态
enum SherpaState {
  notInitialized,
  loadingModel,
  ready,
  recording,
  recognizing,
  done,
  error,
}

/// 基于 sherpa_onnx 的离线语音识别服务
/// 替代 vosk_flutter，支持全平台（含鸿蒙）
class SherpaOnnxSpeechService extends ChangeNotifier {
  SherpaState _state = SherpaState.notInitialized;
  String _recognizedText = '';
  String _partialText = '';
  String _errorMessage = '';
  double _confidence = 0;
  bool _isRecording = false;
  bool _finalResultReceived = false;
  String? _pcmFilePath;
  bool _bindingsInitialized = false;

  sherpa.OnlineRecognizer? _recognizer;
  sherpa.OnlineStream? _stream;
  final record_pkg.AudioRecorder _recorder = record_pkg.AudioRecorder();

  static const int _sampleRate = 16000;
  Timer? _recognizeTimer;
  int _lastProcessedPosition = 0;

  SherpaState get state => _state;
  String get recognizedText => _recognizedText;
  String get partialText => _partialText;
  String get errorMessage => _errorMessage;
  double get confidence => _confidence;
  bool get isRecording => _isRecording;
  bool get isModelLoaded => _recognizer != null;

  /// 显示文本：优先最终结果，其次中间结果
  String get displayText {
    if (_recognizedText.isNotEmpty) return _recognizedText;
    if (_partialText.isNotEmpty) return _partialText;
    return '';
  }

  /// 初始化 sherpa_onnx 原生绑定（只需调用一次）
  void _ensureBindingsInitialized() {
    if (_bindingsInitialized) return;
    try {
      sherpa.initBindings();
      _bindingsInitialized = true;
      _log('sherpa_onnx 原生绑定初始化成功');
    } catch (e) {
      _log('sherpa_onnx 原生绑定初始化失败: $e');
      rethrow;
    }
  }

  /// 初始化模型和识别器
  Future<bool> initialize() async {
    if (_state == SherpaState.loadingModel) return false;
    if (_recognizer != null) {
      _state = SherpaState.ready;
      notifyListeners();
      return true;
    }

    _state = SherpaState.loadingModel;
    _errorMessage = '';
    notifyListeners();

    try {
      _ensureBindingsInitialized();

      final modelDir = await _getOrDownloadModel();
      _log('模型目录: $modelDir');

      _recognizer = _createRecognizer(modelDir);
      _log('识别器创建成功');

      _state = SherpaState.ready;
      notifyListeners();
      return true;
    } catch (e) {
      _log('初始化失败: $e');
      _state = SherpaState.error;
      _errorMessage = 'SherpaONNX 模型加载失败: $e';
      notifyListeners();
      return false;
    }
  }

  /// 创建在线识别器（使用 Zipformer 中文流式模型）
  sherpa.OnlineRecognizer _createRecognizer(String modelDir) {
    final tokensFile = '$modelDir/tokens.txt';
    final encoderFile = '$modelDir/encoder-epoch-99-avg-1.onnx';
    final decoderFile = '$modelDir/decoder-epoch-99-avg-1.onnx';
    final joinerFile = '$modelDir/joiner-epoch-99-avg-1.onnx';

    if (!File(tokensFile).existsSync()) {
      throw Exception('tokens.txt 不存在，请确认模型文件完整');
    }

    final config = sherpa.OnlineRecognizerConfig(
      model: sherpa.OnlineModelConfig(
        transducer: sherpa.OnlineTransducerModelConfig(
          encoder: encoderFile,
          decoder: decoderFile,
          joiner: joinerFile,
        ),
        tokens: tokensFile,
        numThreads: 2,
        provider: 'cpu',
        debug: false,
        modelType: 'zipformer2',
      ),
      feat: const sherpa.FeatureConfig(sampleRate: _sampleRate, featureDim: 80),
      enableEndpoint: true,
      rule1MinTrailingSilence: 2.4,
      rule2MinTrailingSilence: 1.0,
      rule3MinUtteranceLength: 20,
    );

    return sherpa.OnlineRecognizer(config);
  }

  /// 获取模型目录，如果不存在则提示下载
  Future<String> _getOrDownloadModel() async {
    final appDir = await getApplicationDocumentsDirectory();
    final modelDir = Directory('${appDir.path}/sherpa_models/zipformer-zh');

    if (await modelDir.exists()) {
      final hasTokens = await File('${modelDir.path}/tokens.txt').exists();
      if (hasTokens) {
        _log('使用本地缓存模型: ${modelDir.path}');
        return modelDir.path;
      }
    }

    await modelDir.create(recursive: true);

    throw Exception(
      'SherpaONNX 中文语音模型未找到\n\n'
      '请按以下步骤操作：\n'
      '1. 点击下方「下载模型」按钮\n'
      '2. 下载完成后解压到以下文件夹：\n'
      '   ${modelDir.path}\n\n'
      '模型大小约 80MB，只需下载一次',
    );
  }

  /// 获取模型目录路径（供 UI 使用）
  static String getModelDirectoryPath() {
    if (Platform.isWindows) {
      return '${Platform.environment['USERPROFILE'] ?? ''}\\Documents\\sherpa_models\\zipformer-zh';
    }
    return '/sherpa_models/zipformer-zh';
  }

  /// 开始录音和识别
  Future<void> startListening() async {
    if (_isRecording || _state == SherpaState.recording) return;

    if (_recognizer == null) {
      final ok = await initialize();
      if (!ok) return;
    }

    _recognizedText = '';
    _partialText = '';
    _errorMessage = '';
    _confidence = 0;
    _finalResultReceived = false;
    _lastProcessedPosition = 0;
    notifyListeners();

    _log('开始录音...');
    _isRecording = true;
    _state = SherpaState.recording;

    try {
      _stream = _recognizer!.createStream();

      final dir = await getTemporaryDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      _pcmFilePath = '${dir.path}/sherpa_pcm_$timestamp.pcm';

      await _recorder.start(
        record_pkg.RecordConfig(
          encoder: record_pkg.AudioEncoder.pcm16bits,
          sampleRate: _sampleRate,
          numChannels: 1,
        ),
        path: _pcmFilePath!,
      );

      _startRecognitionLoop();
      notifyListeners();
    } catch (e) {
      _isRecording = false;
      _state = SherpaState.error;
      _errorMessage = '录音启动失败: $e';
      _log('录音失败: $e');
      notifyListeners();
    }
  }

  /// 启动定时识别循环
  void _startRecognitionLoop() {
    _recognizeTimer?.cancel();
    _recognizeTimer = Timer.periodic(
      const Duration(milliseconds: 100),
      (_) => _processAudio(),
    );
  }

  /// 处理音频数据：读取 PCM → 送入识别器 → 获取结果
  Future<void> _processAudio() async {
    if (!_isRecording ||
        _recognizer == null ||
        _stream == null ||
        _pcmFilePath == null)
      return;

    try {
      final file = File(_pcmFilePath!);
      if (!await file.exists()) return;

      final fileSize = await file.length();
      if (fileSize <= _lastProcessedPosition) return;

      final bytesToProcess = fileSize - _lastProcessedPosition;
      if (bytesToProcess < 3200) return;

      final raf = await file.open(mode: FileMode.read);
      try {
        await raf.setPosition(_lastProcessedPosition);
        final chunk = await raf.read(bytesToProcess);
        _lastProcessedPosition += chunk.length;

        if (chunk.isEmpty) return;

        final samples = _bytesToInt16Samples(chunk);
        _stream!.acceptWaveform(samples: samples, sampleRate: _sampleRate);

        while (_recognizer!.isReady(_stream!)) {
          _recognizer!.decode(_stream!);
        }

        final isEndpoint = _recognizer!.isEndpoint(_stream!);
        final result = _recognizer!.getResult(_stream!);
        final text = result.text;

        if (isEndpoint && text.isNotEmpty) {
          _recognizedText = text;
          _partialText = '';
          _finalResultReceived = true;
          _confidence = 1.0;
          _log('最终结果: "$text"');
          _recognizer!.reset(_stream!);
        } else if (text.isNotEmpty && !_finalResultReceived) {
          _partialText = text;
        }

        notifyListeners();
      } finally {
        await raf.close();
      }
    } catch (e) {
      _log('音频处理异常: $e');
    }
  }

  /// 将 PCM 字节流转换为 Float32 采样（归一化到 [-1, 1]）
  Float32List _bytesToInt16Samples(Uint8List bytes) {
    final int16Count = bytes.length ~/ 2;
    final samples = Float32List(int16Count);
    final data = bytes.buffer.asByteData();
    for (var i = 0; i < int16Count; i++) {
      final int16 = data.getInt16(i * 2, Endian.little);
      samples[i] = int16 / 32768.0;
    }
    return samples;
  }

  /// 停止录音并获取最终结果
  Future<void> stopListening() async {
    if (!_isRecording) return;

    _log('停止录音...');
    _isRecording = false;
    _recognizeTimer?.cancel();

    try {
      await _recorder.stop();
      _log('录音已停止');

      if (_stream != null && _recognizer != null) {
        final result = _recognizer!.getResult(_stream!);
        final text = result.text;
        if (text.isNotEmpty) {
          _recognizedText = text;
          _partialText = '';
          _confidence = 1.0;
          _log('最终结果: "$text"');
        }
        _stream!.free();
        _stream = null;
      }

      if (_pcmFilePath != null) {
        final file = File(_pcmFilePath!);
        if (await file.exists()) {
          await file.delete();
        }
        _pcmFilePath = null;
      }
      _lastProcessedPosition = 0;

      _state = _recognizedText.isNotEmpty
          ? SherpaState.done
          : SherpaState.ready;
    } catch (e) {
      _log('停止录音异常: $e');
      _state = SherpaState.error;
      _errorMessage = '处理失败: $e';
    }

    notifyListeners();
  }

  /// 取消录音（丢弃结果）
  Future<void> cancelListening() async {
    if (!_isRecording) return;

    _isRecording = false;
    _recognizeTimer?.cancel();
    _lastProcessedPosition = 0;

    try {
      await _recorder.stop();
      if (_stream != null) {
        _stream!.free();
        _stream = null;
      }
      if (_pcmFilePath != null) {
        final file = File(_pcmFilePath!);
        if (await file.exists()) {
          await file.delete();
        }
        _pcmFilePath = null;
      }
    } catch (e) {
      _log('取消录音异常: $e');
    }

    _state = SherpaState.ready;
    notifyListeners();
  }

  /// 清除识别文本
  void clearText() {
    _recognizedText = '';
    _partialText = '';
    _confidence = 0;
    _finalResultReceived = false;
    notifyListeners();
  }

  /// 清除错误状态
  void clearError() {
    if (_state == SherpaState.error) {
      _state = _recognizer != null
          ? SherpaState.ready
          : SherpaState.notInitialized;
      _errorMessage = '';
      notifyListeners();
    }
  }

  void _log(String message) {
    if (kDebugMode) {
      debugPrint('[SherpaOnnx] $message');
    }
  }

  @override
  void dispose() {
    _recognizeTimer?.cancel();
    if (_isRecording) {
      _recorder.stop();
    }
    _stream?.free();
    _stream = null;
    _recognizer?.free();
    _recognizer = null;
    super.dispose();
  }

  /// 以下为测试辅助方法

  void simulateState(SherpaState state) {
    _state = state;
    notifyListeners();
  }

  void simulateRecognizedText(String text) {
    _recognizedText = text;
    notifyListeners();
  }

  void simulatePartialText(String text) {
    _partialText = text;
    notifyListeners();
  }

  void injectFinalResult(String text) {
    _recognizedText = text;
    _partialText = '';
    _finalResultReceived = true;
    _confidence = 1.0;
    _state = SherpaState.done;
    notifyListeners();
  }

  void injectPartialResult(String text) {
    if (!_finalResultReceived) {
      _partialText = text;
      notifyListeners();
    }
  }

  bool get isModelLoadedForTest => _recognizer != null;
}
