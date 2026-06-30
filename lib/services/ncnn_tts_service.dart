import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import 'settings_service.dart';

/// NCNN TTS 播放状态
enum NcnnTtsState { idle, initializing, ready, synthesizing, playing, error }

/// NCNN TTS 事件
class NcnnTtsEvent {
  final String type;
  final double? progress;
  final bool? interrupted;
  final String? errorMessage;

  const NcnnTtsEvent({
    required this.type,
    this.progress,
    this.interrupted,
    this.errorMessage,
  });
}

/// 基于 NCNN 的本地 TTS 服务
///
/// 多软件协同架构：
/// - Flutter/Dart 层：模型文件管理（assets → 内部存储）、设置项、UI 通信
/// - Kotlin 层：MethodChannel 转发、AudioTrack 播放、WAV 导出
/// - C++/NCNN 层：文本前端（G2P）、神经网络前向推理
class NcnnTtsService extends ChangeNotifier {
  static const MethodChannel _channel = MethodChannel('xingling.chat/tts');
  static const EventChannel _eventChannel = EventChannel(
    'xingling.chat/tts_events',
  );

  static NcnnTtsService? _instance;
  static NcnnTtsService get instance {
    _instance ??= NcnnTtsService();
    return _instance!;
  }

  NcnnTtsState _state = NcnnTtsState.idle;
  String _errorMessage = '';
  double _progress = 0;
  bool _nativeReady = false;
  bool _initializing = false;
  StreamSubscription? _eventSub;

  NcnnTtsState get state => _state;
  String get errorMessage => _errorMessage;
  double get progress => _progress;
  bool get isReady => _nativeReady && _state != NcnnTtsState.error;
  bool get isPlaying => _state == NcnnTtsState.playing;
  bool get isSynthesizing => _state == NcnnTtsState.synthesizing;

  Stream<NcnnTtsEvent> get eventStream {
    return _eventChannel.receiveBroadcastStream().map((event) {
      final map = event as Map;
      final type = map['event'] as String? ?? '';
      return NcnnTtsEvent(
        type: type,
        progress: (map['value'] as num?)?.toDouble(),
        interrupted: map['interrupted'] as bool?,
        errorMessage: map['message'] as String?,
      );
    });
  }

  void startEventListener({void Function(NcnnTtsEvent)? onEvent}) {
    _eventSub?.cancel();
    _eventSub = eventStream.listen((event) {
      switch (event.type) {
        case 'onStarted':
          _state = NcnnTtsState.synthesizing;
          _progress = 0;
          break;
        case 'onProgress':
          _state = NcnnTtsState.playing;
          _progress = event.progress ?? 0;
          break;
        case 'onFinished':
          _state = NcnnTtsState.ready;
          _progress = 1;
          break;
        case 'onError':
          _state = NcnnTtsState.error;
          _errorMessage = event.errorMessage ?? '未知错误';
          break;
      }
      notifyListeners();
      onEvent?.call(event);
    });
  }

  @override
  void dispose() {
    _eventSub?.cancel();
    super.dispose();
  }

  Future<bool> ensureInitialized(SettingsService settings) async {
    if (_nativeReady) return true;
    if (_initializing) return false;
    _initializing = true;
    _state = NcnnTtsState.initializing;
    _errorMessage = '';
    notifyListeners();

    try {
      if (!Platform.isAndroid) {
        _errorMessage = 'NCNN TTS 仅支持 Android 平台';
        _state = NcnnTtsState.error;
        notifyListeners();
        return false;
      }

      final dir = await _copyAssetsToInternal();

      final ok = await _channel.invokeMethod<bool>('initTts', {
        'modelDir': dir,
        'paramName': 'vits.ncnn.param',
        'binName': 'vits.ncnn.bin',
        'phonemeName': 'phoneme.txt',
        'g2pName': 'g2p_dict.txt',
        'speakerId': settings.getTtsSpeakerId(),
        'speed': settings.getTtsSpeed(),
        'pitch': settings.getTtsPitch(),
        'energy': settings.getTtsEnergy(),
        'sampleRate': 22050,
        'maxChars': settings.getTtsMaxChars(),
      });

      _nativeReady = ok ?? false;
      if (_nativeReady) {
        _state = NcnnTtsState.ready;
      } else {
        _errorMessage = '模型加载失败，请检查模型文件是否完整';
        _state = NcnnTtsState.error;
      }
      notifyListeners();
      return _nativeReady;
    } catch (e) {
      _errorMessage = 'TTS 初始化失败: $e';
      _state = NcnnTtsState.error;
      notifyListeners();
      return false;
    } finally {
      _initializing = false;
    }
  }

  Future<bool> reinitialize(SettingsService settings) async {
    _nativeReady = false;
    return ensureInitialized(settings);
  }

  Future<bool> synthesize(String text) async {
    if (!_nativeReady) return false;
    if (text.trim().isEmpty) return false;
    try {
      final ok = await _channel.invokeMethod<bool>('synthesize', {
        'text': text,
      });
      return ok ?? false;
    } catch (e) {
      _errorMessage = '合成失败: $e';
      _state = NcnnTtsState.error;
      notifyListeners();
      return false;
    }
  }

  Future<void> stop() async {
    try {
      await _channel.invokeMethod<void>('stop');
      _state = NcnnTtsState.ready;
      _progress = 0;
      notifyListeners();
    } catch (_) {}
  }

  Future<String?> synthesizeToWav(String text, String outPath) async {
    if (!_nativeReady) return null;
    try {
      final result = await _channel.invokeMethod<String>('synthesizeToWav', {
        'text': text,
        'outPath': outPath,
      });
      return result;
    } catch (e) {
      _errorMessage = '导出 WAV 失败: $e';
      notifyListeners();
      return null;
    }
  }

  Future<bool> queryIsPlaying() async {
    try {
      final v = await _channel.invokeMethod<bool>('isPlaying');
      return v ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<String> _copyAssetsToInternal() async {
    final appDir = await getApplicationDocumentsDirectory();
    final ttsDir = Directory('${appDir.path}/tts_models');
    if (!ttsDir.existsSync()) {
      ttsDir.createSync(recursive: true);
    }

    const files = [
      'vits.ncnn.param',
      'vits.ncnn.bin',
      'phoneme.txt',
      'g2p_dict.txt',
    ];

    for (final name in files) {
      final target = File('${ttsDir.path}/$name');
      if (target.existsSync()) continue;
      try {
        final data = await rootBundle.load('assets/tts_models/$name');
        target.writeAsBytesSync(data.buffer.asUint8List());
      } catch (_) {
        // 模型文件可能未提供，忽略错误
      }
    }
    return ttsDir.path;
  }
}
