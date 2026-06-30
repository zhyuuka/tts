import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart' as record_pkg;
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_recognition_error.dart';

import 'speech_channel_interceptor.dart';
import 'cloud_speech_provider.dart';
import 'sherpa_onnx_speech_service.dart';
import 'settings_service.dart';
import 'secure_storage_service.dart';
import 'common/device_info.dart';

enum SpeechState { notInitialized, ready, listening, processing, error }

enum SpeechMode { auto, local, localSherpa, cloud }

class SpeechRecognitionService extends ChangeNotifier {
  final stt.SpeechToText _speech = stt.SpeechToText();
  final SpeechChannelInterceptor _interceptor =
      SpeechChannelInterceptor.instance;
  // 为什么延迟初始化：AudioRecorder 构造时会访问 platform channel，
  // 在测试环境（无 binding）会崩溃。延迟到真正录音时才创建，避免单元测试失败。
  record_pkg.AudioRecorder? _recorderInstance;
  record_pkg.AudioRecorder get _recorder =>
      _recorderInstance ??= record_pkg.AudioRecorder();

  SpeechState _state = SpeechState.notInitialized;
  String _recognizedText = '';
  String _interimText = '';
  String _errorMessage = '';
  String _currentLocaleId = 'zh_CN';
  List<stt.LocaleName> _locales = [];
  bool _isAvailable = false;
  double _soundLevel = 0;
  double _confidence = 0;
  DateTime? _lastSoundLevelNotify;
  final bool _debugLogging = false;

  // ── 云端模式 ──
  SpeechMode _mode = SpeechMode.auto;
  CloudSpeechProviderType _cloudProviderType =
      CloudSpeechProviderType.openaiWhisper;
  CloudSpeechProvider? _cloudProvider;
  bool _isRecording = false;
  String? _audioFilePath;
  CloudSpeechState _cloudState = CloudSpeechState.idle;

  // ── SherpaONNX 离线模式（延迟初始化，避免测试环境崩溃） ──
  SherpaOnnxSpeechService? _sherpaService;
  bool _sherpaInitialized = false;
  bool _sherpaInitFailed = false;

  // ── 缓存云端 API Key 状态，避免每次切换都读安全存储 ──
  bool? _cachedHasCloudKey;

  SherpaOnnxSpeechService get _sherpaServiceInstance {
    _sherpaService ??= SherpaOnnxSpeechService();
    return _sherpaService!;
  }

  // ── 文字防护缓存：final 结果一旦到达就锁定，不受后续状态变化影响 ──
  String? _lockedText;
  bool _finalResultReceived = false;

  // ── UI 刷新计数器（仅调试用，不参加 Selector 比较）───
  int _uiGeneration = 0;
  int get uiGeneration => _uiGeneration;

  @override
  void notifyListeners() {
    _uiGeneration++;
    super.notifyListeners();
  }

  SpeechState get state => _state;
  String get recognizedText => _recognizedText;
  String get interimText => _interimText;
  String get errorMessage => _errorMessage;
  String get currentLocaleId => _currentLocaleId;
  List<stt.LocaleName> get locales => _locales;
  bool get isAvailable => _isAvailable;
  bool get isListening => _state == SpeechState.listening || _isRecording;
  double get soundLevel => _soundLevel;
  double get confidence => _confidence;

  SpeechMode get mode => _mode;
  bool get isCloudMode => _mode == SpeechMode.cloud;
  bool get isSherpaMode => _mode == SpeechMode.localSherpa;
  CloudSpeechState get cloudState => _cloudState;
  CloudSpeechProviderType get cloudProviderType => _cloudProviderType;
  bool get isCloudReady =>
      _cloudProvider != null && SettingsService.instance.isCloudSpeechEnabled();
  bool get isSherpaReady => _sherpaService?.isModelLoaded ?? false;

  // ── 自动切换标记（用于 UI 显示提示）───
  bool _hasAutoSwitched = false;
  bool get hasAutoSwitched => _hasAutoSwitched;

  /// 重置自动切换标记（在用户手动切换模式时调用）
  void resetAutoSwitchFlag() {
    if (_hasAutoSwitched) {
      _hasAutoSwitched = false;
      notifyListeners();
    }
  }

  String get displayText {
    if (_lockedText != null && _lockedText!.isNotEmpty) return _lockedText!;
    if (_mode == SpeechMode.localSherpa && _sherpaService != null) {
      final sherpaText = _sherpaServiceInstance.displayText;
      if (sherpaText.isNotEmpty) return sherpaText;
    }
    if (_interimText.isNotEmpty) return _interimText;
    return _recognizedText;
  }

  bool _isInitializing = false;
  bool _interceptedResultReceived = false;

  Future<bool> initialize() async {
    if (_isInitializing) return _isAvailable;
    if (_state == SpeechState.listening) return true;

    _isInitializing = true;

    // ── 自动模式：根据设备兼容性选择最佳模式 ──
    if (_mode == SpeechMode.auto) {
      _log('自动模式：开始设备兼容性检测');
      final resolvedMode = await _resolveAutoMode();
      if (resolvedMode != null) {
        _mode = resolvedMode;
        _log('自动模式已解析为: ${resolvedMode.name}');
      } else {
        // 无法确定模式，降级到本地模式
        _mode = SpeechMode.local;
        _log('自动模式无法确定，降级到本地模式');
      }
    }

    // SherpaONNX/云端模式不需要 STT 引擎，跳过初始化避免启动时浪费时间
    if (_mode != SpeechMode.local) {
      _isAvailable = true;
      _state = SpeechState.ready;
      _errorMessage = '';
      _isInitializing = false;
      _log('非本地模式，跳过 STT 引擎初始化');
      notifyListeners();
      return true;
    }

    try {
      _isAvailable = await _speech.initialize(
        onError: _onError,
        onStatus: _onStatus,
        debugLogging: kDebugMode,
      );

      if (_isAvailable) {
        _locales = await _speech.locales();
        final hasZh = _locales.any((l) => l.localeId == 'zh_CN');
        if (hasZh) {
          _currentLocaleId = 'zh_CN';
        } else {
          final sysLocale = await _speech.systemLocale();
          _currentLocaleId = sysLocale?.localeId ?? 'en_US';
        }
        _state = SpeechState.ready;
        _errorMessage = '';
      } else {
        _state = SpeechState.error;
        _errorMessage = '当前设备不支持语音识别';
      }
    } catch (e) {
      _isAvailable = false;
      _state = SpeechState.error;
      _errorMessage = '初始化失败: 请检查麦克风权限是否已授予';
      _log('initialize 异常: $e');
    }
    _isInitializing = false;
    notifyListeners();
    return _isAvailable;
  }

  Future<void> startListening() async {
    if (_state == SpeechState.listening || _isRecording) return;

    // ── 华为/荣耀设备检测：原生 STT 会崩溃，必须提前拦截 ──
    if (_mode == SpeechMode.local && DeviceInfo.isHuaweiOrHonor) {
      _log('检测到华为/荣耀设备，跳过本地STT（避免 FakeRecognitionService 崩溃）');
      final hasCloudKey = await _hasCloudApiKey();
      if (hasCloudKey) {
        _mode = SpeechMode.cloud;
        _hasAutoSwitched = true;
        _log('自动切换到云端模式');
      } else {
        _state = SpeechState.error;
        _errorMessage =
            '当前设备不支持本地语音识别（厂商限制）。'
            '请切换到云端模式（需先配置 API Key），或使用其他品牌手机。';
        notifyListeners();
        return;
      }
    }

    // ── Windows SAPI 本地识别效果差，有 API Key 时推荐云端 ──
    if (_mode == SpeechMode.local &&
        Platform.isWindows &&
        await _hasCloudApiKey()) {
      _log('Windows 平台：有云端API Key，建议使用云端模式（SAPI本地识别效果有限）');
    }

    if (!_isAvailable || _state == SpeechState.error) {
      final ok = await initialize();
      if (!ok) return;
    }

    _recognizedText = '';
    _interimText = '';
    _errorMessage = '';
    _soundLevel = 0;
    _confidence = 0;
    _interceptedResultReceived = false;
    _lockedText = null;
    _finalResultReceived = false;
    notifyListeners();

    if (_mode == SpeechMode.cloud) {
      await _startCloudListening();
    } else if (_mode == SpeechMode.localSherpa) {
      await _startSherpaListening();
    } else {
      await _startLocalListening();
    }
  }

  Future<void> _startLocalListening() async {
    _activateInterceptor();
    try {
      await _speech.listen(
        onResult: _onResult,
        listenFor: const Duration(seconds: 60),
        pauseFor: const Duration(seconds: 3),
        listenOptions: stt.SpeechListenOptions(
          partialResults: true,
          cancelOnError: true,
          listenMode: stt.ListenMode.confirmation,
        ),
        localeId: _currentLocaleId,
        onSoundLevelChange: _onSoundLevel,
      );
    } catch (e) {
      final msg = e.toString();
      _log('startListening 异常: $msg');

      if (msg.contains('SecurityException') ||
          msg.contains('FakeRecognitionService') ||
          msg.contains('Not allowed to bind') ||
          msg.contains('vassistant')) {
        _log('检测到华为/厂商语音助手劫持，自动切换到云端模式');
        _deactivateInterceptor();
        _mode = SpeechMode.cloud;
        notifyListeners();
        await _startCloudListening();
        return;
      }

      _state = SpeechState.error;
      if (msg.contains('permission') || msg.contains('Permission')) {
        _errorMessage = '麦克风权限被拒绝，请在系统设置中允许录音权限';
      } else if (msg.contains('network') || msg.contains('Network')) {
        _errorMessage = '网络错误，请检查连接后重试';
      } else {
        _errorMessage = '语音识别启动失败（厂商兼容性问题），可尝试切换到云端模式';
      }
      notifyListeners();
    }
  }

  Future<void> _startCloudListening() async {
    final hasApiKey = await _hasCloudApiKey();
    if (!hasApiKey) {
      _state = SpeechState.error;
      _errorMessage =
          '本地语音不可用（厂商限制），且未配置云端 API Key。请在设置中配置 OpenAI 或通义密钥后使用云端模式。';
      _log('云端模式无 API Key，无法启动');
      notifyListeners();
      return;
    }

    _log('开始云端录音模式');
    _isRecording = true;
    _cloudState = CloudSpeechState.recording;
    _state = SpeechState.listening;
    notifyListeners();

    try {
      final dir = await getTemporaryDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      _audioFilePath = '${dir.path}/speech_$timestamp.m4a';

      await _recorder.start(
        record_pkg.RecordConfig(
          encoder: record_pkg.AudioEncoder.aacLc,
          bitRate: 128000,
          sampleRate: 16000,
          numChannels: 1,
        ),
        path: _audioFilePath!,
      );

      _log('录音已启动: $_audioFilePath');
    } catch (e) {
      _isRecording = false;
      _cloudState = CloudSpeechState.idle;
      _state = SpeechState.error;
      _errorMessage = '录音启动失败: $e';
      notifyListeners();
    }
  }

  Future<void> _startSherpaListening() async {
    if (_sherpaInitFailed) {
      _state = SpeechState.error;
      _errorMessage = _sherpaServiceInstance.errorMessage;
      notifyListeners();
      return;
    }

    if (!_sherpaInitialized) {
      _state = SpeechState.processing;
      _errorMessage = '';
      notifyListeners();

      try {
        final ok = await _sherpaServiceInstance.initialize();
        if (!ok) {
          _sherpaInitFailed = true;
          _state = SpeechState.error;
          _errorMessage = _sherpaServiceInstance.errorMessage;
          notifyListeners();
          return;
        }
        _sherpaInitialized = true;
      } catch (e) {
        _log('SherpaONNX 初始化异常: $e');
        _sherpaInitFailed = true;
        _state = SpeechState.error;
        _errorMessage = 'SherpaONNX 引擎不可用: $e';
        notifyListeners();
        return;
      }
    }

    _sherpaServiceInstance.addListener(_onSherpaStateChanged);
    await _sherpaServiceInstance.startListening();
    _state = SpeechState.listening;
    _log('SherpaONNX 识别已启动');
    notifyListeners();
  }

  void _onSherpaStateChanged() {
    final sherpaText = _sherpaServiceInstance.displayText;
    if (sherpaText.isNotEmpty) {
      _lockedText = sherpaText;
      _recognizedText = sherpaText;
      _confidence = _sherpaServiceInstance.confidence;
    }
    if (_sherpaServiceInstance.state == SherpaState.error) {
      _errorMessage = 'SherpaONNX 识别错误: ${_sherpaServiceInstance.errorMessage}';
    }
    notifyListeners();
  }

  Future<void> stopListening() async {
    if (!_isRecording && _state != SpeechState.listening) return;

    if (_mode == SpeechMode.cloud && _isRecording) {
      await _stopCloudListening();
    } else if (_mode == SpeechMode.localSherpa) {
      await _stopSherpaListening();
    } else {
      await _stopLocalListening();
    }
  }

  Future<void> _stopLocalListening() async {
    _deactivateInterceptor();
    await _speech.stop();
    _state = SpeechState.ready;
    notifyListeners();
  }

  Future<void> _stopSherpaListening() async {
    _sherpaServiceInstance.removeListener(_onSherpaStateChanged);
    await _sherpaServiceInstance.stopListening();

    final sherpaText = _sherpaServiceInstance.recognizedText;
    if (sherpaText.isNotEmpty) {
      _recognizedText = sherpaText;
      _lockedText = sherpaText;
      _confidence = _sherpaServiceInstance.confidence;
      _log('SherpaONNX 最终结果: "$sherpaText"');
    }

    _state = SpeechState.ready;
    notifyListeners();
  }

  Future<void> _stopCloudListening() async {
    _log('停止云端录音，准备上传...');
    _isRecording = false;
    _cloudState = CloudSpeechState.uploading;
    _state = SpeechState.processing;
    notifyListeners();

    try {
      final path = await _recorder.stop();
      _log('录音已停止，文件: $path');

      if (path == null || !File(path).existsSync()) {
        throw Exception('录音文件不存在');
      }

      _cloudState = CloudSpeechState.recognizing;
      notifyListeners();

      final provider = _getCloudProvider();
      final result = await provider.recognize(
        File(path),
        language: _currentLocaleId,
      );

      if (result.hasError) {
        throw Exception(result.errorMessage);
      }

      _recognizedText = result.text;
      _confidence = result.confidence;
      _log('云端识别完成: "${result.text}"');

      _cleanupAudioFile();
    } catch (e) {
      _state = SpeechState.error;
      _errorMessage = '云端识别失败: $e';
      _log('云端识别异常: $e');
    } finally {
      _cloudState = _state == SpeechState.error
          ? CloudSpeechState.error
          : CloudSpeechState.done;
      if (_state != SpeechState.error) {
        _state = SpeechState.ready;
      }
      notifyListeners();
    }
  }

  void _cleanupAudioFile() {
    if (_audioFilePath != null) {
      final file = File(_audioFilePath!);
      if (file.existsSync()) file.delete();
      _audioFilePath = null;
    }
  }

  Future<void> cancelListening() async {
    _log(
      'cancelListening 被调用 (finalResultReceived: $_finalResultReceived, lockedText: $_lockedText)',
    );

    if (_isRecording) {
      await _recorder.stop();
      _isRecording = false;
      _cleanupAudioFile();
    }
    if (_mode == SpeechMode.localSherpa &&
        _sherpaService != null &&
        _sherpaServiceInstance.isRecording) {
      _sherpaServiceInstance.removeListener(_onSherpaStateChanged);
      await _sherpaServiceInstance.cancelListening();
    }
    if (_state == SpeechState.listening) {
      _deactivateInterceptor();
      await _speech.cancel();
    }
    _cloudState = CloudSpeechState.idle;

    // 关键修复：如果已收到 final 结果，保持状态让 UI 显示文字
    if (_finalResultReceived &&
        _lockedText != null &&
        _lockedText!.isNotEmpty) {
      _log('cancelListening: 保留锁定文字 "$_lockedText"，状态设为 ready');
      _state = SpeechState.ready;
    } else if (_recognizedText.isEmpty && _interimText.isEmpty) {
      _state = SpeechState.ready;
    } else {
      // 有中间结果但没 final，也保留（用户可能还在看）
      _state = SpeechState.ready;
    }

    // 强制多次通知确保 UI 更新
    notifyListeners();
    await Future.delayed(const Duration(milliseconds: 50));
    notifyListeners();
  }

  // ── 模式切换 ──

  Future<bool> _hasCloudApiKey() async {
    _cachedHasCloudKey ??= await SecureStorageService.instance.hasApiKey(
      'cloud_speech',
    );
    return _cachedHasCloudKey!;
  }

  /// 自动模式解析：根据设备兼容性和配置选择最佳模式
  Future<SpeechMode?> _resolveAutoMode() async {
    try {
      // 1. 检查用户是否有保存的模式偏好
      final preferredMode = SettingsService.instance.getSttMode();
      if (preferredMode != 'auto') {
        // 用户有明确偏好，转换为对应的 SpeechMode
        switch (preferredMode) {
          case 'local':
            // 即使偏好本地模式，也要检查设备兼容性
            if (DeviceInfo.isHuaweiOrHonor) {
              _log('用户偏好本地模式，但检测到华为/荣耀设备');
              final hasCloudKey = await _hasCloudApiKey();
              if (hasCloudKey) {
                _hasAutoSwitched = true;
                return SpeechMode.cloud;
              }
              // 无云端 Key，返回 null 让调用方降级处理
              return null;
            }
            return SpeechMode.local;
          case 'cloud':
            final hasCloudKey = await _hasCloudApiKey();
            if (hasCloudKey) return SpeechMode.cloud;
            _log('用户偏好云端模式，但未配置 API Key');
            return null;
          default:
            break;
        }
      }

      // 2. 华为/荣耀设备：优先使用云端（如果可用）
      if (DeviceInfo.isHuaweiOrHonor) {
        _log('自动模式：检测到华为/荣耀设备');
        final hasCloudKey = await _hasCloudApiKey();
        if (hasCloudKey) {
          _hasAutoSwitched = true;
          return SpeechMode.cloud;
        }
        _log('华为/荣耀设备无云端 API Key，尝试本地模式（可能不稳定）');
        return SpeechMode.local;
      }

      // 3. Windows 平台：如果有云端 Key，推荐云端
      if (Platform.isWindows) {
        final hasCloudKey = await _hasCloudApiKey();
        if (hasCloudKey) {
          _log('Windows 平台：有云端 API Key，使用云端模式');
          return SpeechMode.cloud;
        }
        _log('Windows 平台：无云端 API Key，使用本地 SAPI');
        return SpeechMode.local;
      }

      // 4. 默认：使用本地模式（大多数 Android 设备都支持）
      _log('自动模式：使用默认本地模式');
      return SpeechMode.local;
    } catch (e) {
      _log('自动模式解析异常: $e');
      return null;
    }
  }

  void invalidateCloudKeyCache() {
    _cachedHasCloudKey = null;
  }

  /// @visibleForTesting
  /// 做什么：注入云端 API Key 是否已配置的缓存状态。
  /// 为什么这样做：测试环境无法访问 SecureStorageService，
  /// 通过此方法让测试模拟"已配置/未配置 API Key"的场景。
  @visibleForTesting
  void setCachedHasCloudKeyForTesting(bool hasKey) {
    _cachedHasCloudKey = hasKey;
  }

  Future<void> setMode(SpeechMode newMode) async {
    if (_mode == newMode) return;

    if (newMode == SpeechMode.cloud) {
      final hasApiKey = await _hasCloudApiKey();
      if (!hasApiKey) {
        _log('切换云端模式失败：未配置 API Key');
        return;
      }
    }

    // 用户手动切换模式，重置自动切换标记
    resetAutoSwitchFlag();

    _mode = newMode;
    _log('切换语音模式: ${newMode.name}');
    notifyListeners();
  }

  void toggleMode() {
    if (_mode == SpeechMode.local) {
      setMode(SpeechMode.localSherpa);
    } else if (_mode == SpeechMode.localSherpa) {
      setMode(SpeechMode.cloud);
    } else {
      setMode(SpeechMode.local);
    }
  }

  void setCloudProvider(CloudSpeechProviderType type) {
    _cloudProviderType = type;
    _cloudProvider = null;
    notifyListeners();
  }

  CloudSpeechProvider _getCloudProvider() {
    if (_cloudProvider == null || _cloudProvider!.type != _cloudProviderType) {
      _cloudProvider = CloudSpeechProvider.create(_cloudProviderType);
    }
    return _cloudProvider!;
  }

  // ── 原有方法保持兼容 ──

  void setLocale(String localeId) {
    if (_locales.any((l) => l.localeId == localeId)) {
      _currentLocaleId = localeId;
      notifyListeners();
    }
  }

  void clearText() {
    _recognizedText = '';
    _interimText = '';
    _lockedText = null;
    _finalResultReceived = false;
    if (_mode == SpeechMode.localSherpa && _sherpaService != null) {
      _sherpaServiceInstance.clearText();
    }
    notifyListeners();
  }

  void clearError() {
    if (_state == SpeechState.error) {
      _state = SpeechState.ready;
      _errorMessage = '';
      _cloudState = CloudSpeechState.idle;
      // 重置 SherpaONNX 失败状态，允许用户下载模型后重试
      if (_mode == SpeechMode.localSherpa && _sherpaInitFailed) {
        _sherpaInitFailed = false;
        _log('clearError: 重置 SherpaONNX 初始化状态，允许重新尝试');
      }
      notifyListeners();
    }
  }

  /// 手动重试 SherpaONNX 初始化（用户下载模型后调用）
  Future<bool> retrySherpaInit() async {
    if (_mode != SpeechMode.localSherpa) return false;

    _log('retrySherpaInit: 用户手动重试 SherpaONNX 初始化');
    _sherpaInitFailed = false;
    _sherpaInitialized = false;
    _errorMessage = '';
    notifyListeners();

    if (_sherpaService != null) {
      final ok = await _sherpaServiceInstance.initialize();
      if (ok) {
        _sherpaInitialized = true;
        _state = SpeechState.ready;
        notifyListeners();
      } else {
        _sherpaInitFailed = true;
        _state = SpeechState.error;
        _errorMessage = _sherpaServiceInstance.errorMessage;
        notifyListeners();
      }
      return ok;
    }
    return false;
  }

  // ========== 拦截器回调 ==========

  void _onInterceptedRecognized(String words, bool isFinal) {
    _interceptedResultReceived = true;
    _log('【拦截器】识别结果: "$words" (final: $isFinal)');
    _interimText = '';
    if (isFinal) {
      _recognizedText = words;
      _lockedText = words;
      _finalResultReceived = true;
      _confidence = 1.0;
      _log('文字已锁定: "$words"');
    } else {
      _interimText = words;
    }
    notifyListeners();
  }

  void _onInterceptedError(String errorMsg) {
    _log('【拦截器】错误: $errorMsg');
    _onError(SpeechRecognitionError(errorMsg, false));
  }

  void _onInterceptedStatus(String status) {
    _log('【拦截器】状态: $status');
    _onStatus(status);
  }

  void _activateInterceptor() {
    _interceptor.activate(
      onRecognized: _onInterceptedRecognized,
      onError: _onInterceptedError,
      onStatus: _onInterceptedStatus,
    );
  }

  void _deactivateInterceptor() {
    _interceptor.deactivate();
  }

  // ========== 插件原始回调 ==========

  void _onResult(SpeechRecognitionResult result) {
    if (_interceptedResultReceived) {
      _log('_onResult 被拦截器跳过');
      return;
    }
    try {
      _interimText = '';
      final words = result.recognizedWords;
      if (result.finalResult) {
        _recognizedText = words;
        _lockedText = words;
        _finalResultReceived = true;
        _confidence = result.confidence;
        _log('最终识别结果: "$words" (${result.confidence.toStringAsFixed(2)}) 已锁定');
      } else {
        _interimText = words;
        _log('中间识别结果: "$words"');
      }
      notifyListeners();
    } catch (e) {
      _log('_onResult 处理异常: $e');
    }
  }

  void _onSoundLevel(double level) {
    _soundLevel = level;
    final now = DateTime.now();
    if (_lastSoundLevelNotify == null ||
        now.difference(_lastSoundLevelNotify!).inMilliseconds > 200) {
      _lastSoundLevelNotify = now;
      notifyListeners();
    }
  }

  void _onStatus(String status) {
    _log('状态变化: $status');
    switch (status) {
      case 'listening':
        _state = SpeechState.listening;
        break;
      case 'notListening':
        if (_state == SpeechState.listening) {
          _state = SpeechState.ready;
        }
        break;
      case 'done':
        _state = SpeechState.ready;
        break;
      default:
        break;
    }
    notifyListeners();
  }

  void _onError(SpeechRecognitionError error) {
    if (error.errorMsg == 'no_error') return;

    final errorMsg = error.errorMsg;
    _log('语音识别错误: $errorMsg (permanent: ${error.permanent})');

    _state = SpeechState.error;
    switch (errorMsg) {
      case 'network_error':
        _errorMessage = '网络错误，请检查网络连接';
        break;
      case 'no_speech':
        _errorMessage = '未检测到语音，请重试';
        _state = SpeechState.ready;
        break;
      case 'permission_not_granted':
        _errorMessage = '麦克风权限未授予';
        break;
      case 'busy':
        _errorMessage = '语音识别正忙，请稍后重试';
        break;
      default:
        if (errorMsg.contains('Null') && errorMsg.contains('List')) {
          _errorMessage = '语音识别结果传输异常（已知兼容性问题）';
        } else {
          _errorMessage = '识别错误: $errorMsg';
        }
    }
    notifyListeners();
  }

  void _log(String message) {
    if (kDebugMode || _debugLogging) {
      debugPrint('[SpeechRecognition] $message');
    }
  }

  @override
  void dispose() {
    _deactivateInterceptor();
    // 只在真正创建过 recorder 实例时才停止，避免测试环境访问 platform channel
    if (_isRecording && _recorderInstance != null) {
      _recorder.stop();
      _cleanupAudioFile();
    }
    if (_sherpaService != null) {
      _sherpaServiceInstance.removeListener(_onSherpaStateChanged);
      _sherpaServiceInstance.dispose();
    }
    _speech.cancel();
    super.dispose();
  }

  // ========== @visibleForTesting 测试钩子 ==========

  void simulateState(SpeechState state) {
    _state = state;
    notifyListeners();
  }

  void simulateRecognizedText(String text) {
    _recognizedText = text;
    notifyListeners();
  }

  void simulateInterimText(String text) {
    _interimText = text;
    notifyListeners();
  }

  void simulateAvailable({bool available = true, List<String>? localeIds}) {
    _isAvailable = available;
    if (localeIds != null) {
      _locales = localeIds.map((id) => _MockLocaleName(id)).toList();
      if (localeIds.contains('zh_CN')) {
        _currentLocaleId = 'zh_CN';
      } else if (localeIds.isNotEmpty) {
        _currentLocaleId = localeIds.first;
      }
    }
    if (available && _state == SpeechState.notInitialized) {
      _state = SpeechState.ready;
    }
    notifyListeners();
  }

  void injectResult(SpeechRecognitionResult result) {
    _onResult(result);
  }

  void injectError(SpeechRecognitionError error) {
    _onError(error);
  }

  void injectStatus(String status) {
    _onStatus(status);
  }

  void injectSoundLevel(double level) {
    _onSoundLevel(level);
  }

  void simulateInterceptedResult(String words, {bool isFinal = true}) {
    _onInterceptedRecognized(words, isFinal);
  }

  void simulateCloudResult(String text, {double confidence = 1.0}) {
    _recognizedText = text;
    _confidence = confidence;
    _cloudState = CloudSpeechState.done;
    _state = SpeechState.ready;
    notifyListeners();
  }
}

class _MockLocaleName implements stt.LocaleName {
  final String _id;
  _MockLocaleName(this._id);

  @override
  String get localeId => _id;

  @override
  String get name => _id;

  @override
  String toString() => 'MockLocale($_id)';
}
