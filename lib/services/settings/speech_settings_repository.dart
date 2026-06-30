import 'package:hive_flutter/hive_flutter.dart';

/// 语音识别配置仓库（Facade 模式阶段 2：语音识别子域）
///
/// 做什么：把 SettingsService 中云端语音识别和 STT 模式相关配置抽到独立类。
/// 为什么这样做：SettingsService 是 God Class，语音识别子域虽然方法不多但逻辑独立，
/// 抽出后 SettingsService 保留同名 getter/setter 作为 Facade 转发。
class SpeechSettingsRepository {
  // ── 依赖（通过构造函数注入）──
  final Future<bool> Function(
    Future<dynamic> Function(Box<dynamic> box) operation,
  )
  _safeWrite;

  final T Function<T>(T Function(Box<dynamic> box) operation, T defaultValue)
  _safeRead;
  final Box<dynamic>? Function() _boxGetter;

  SpeechSettingsRepository({
    required Box<dynamic>? Function() boxGetter,
    required Future<bool> Function(
      Future<dynamic> Function(Box<dynamic> box) operation,
    )
    safeWrite,
    required T Function<T>(
      T Function(Box<dynamic> box) operation,
      T defaultValue,
    )
    safeRead,
  }) : _boxGetter = boxGetter,
       _safeWrite = safeWrite,
       _safeRead = safeRead;

  // ── 常量键 ──
  static const String _cloudSpeechEnabledKey = 'cloud_speech_enabled';
  static const String _cloudSpeechProviderKey = 'cloud_speech_provider';
  static const String _cloudSpeechBaseUrlKey = 'cloud_speech_base_url';
  static const String _sttModeKey = 'stt_mode';

  // ── 云端语音识别 ──

  bool isCloudSpeechEnabled() {
    return _boxGetter()?.get(_cloudSpeechEnabledKey, defaultValue: false) ??
        false;
  }

  Future<bool> setCloudSpeechEnabled(bool enabled) async {
    return await _safeWrite((box) => box.put(_cloudSpeechEnabledKey, enabled));
  }

  String getCloudSpeechProvider() {
    return _boxGetter()?.get(
          _cloudSpeechProviderKey,
          defaultValue: 'openaiWhisper',
        ) ??
        'openaiWhisper';
  }

  Future<bool> setCloudSpeechProvider(String provider) async {
    return await _safeWrite(
      (box) => box.put(_cloudSpeechProviderKey, provider),
    );
  }

  String getCloudSpeechBaseUrl() {
    return _boxGetter()?.get(_cloudSpeechBaseUrlKey, defaultValue: '') ?? '';
  }

  Future<bool> setCloudSpeechBaseUrl(String url) async {
    return await _safeWrite((box) => box.put(_cloudSpeechBaseUrlKey, url));
  }

  // ── STT 模式偏好 ──

  /// 获取 STT 模式偏好
  /// 返回值: 'auto' (自动检测), 'local' (强制本地), 'cloud' (强制云端)
  String getSttMode() {
    return _safeRead<String>(
      (box) => (box.get(_sttModeKey) as String?) ?? 'auto',
      'auto',
    );
  }

  /// 设置 STT 模式偏好
  Future<bool> setSttMode(String mode) async {
    // 验证模式值
    if (!['auto', 'local', 'cloud'].contains(mode)) {
      return false;
    }
    return await _safeWrite((box) => box.put(_sttModeKey, mode));
  }
}
