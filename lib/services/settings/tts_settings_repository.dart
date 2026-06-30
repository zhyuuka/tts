import 'package:hive_flutter/hive_flutter.dart';

/// TTS 配置仓库（Facade 模式阶段 2：TTS 子域）
///
/// 做什么：把 SettingsService 中 NCNN TTS（本地语音播报）相关配置抽到独立类。
/// 为什么这样做：TTS 配置项较多（7 个键 + 7 对 getter/setter + 9 个默认值常量），
/// 抽出后 SettingsService 保留同名 getter/setter 作为 Facade 转发，调用方零改动。
class TtsSettingsRepository {
  // ── 依赖（通过构造函数注入）──
  final Box<dynamic>? Function() _boxGetter;
  final Future<bool> Function(
    Future<dynamic> Function(Box<dynamic> box) operation,
  )
  _safeWrite;

  TtsSettingsRepository({
    required Box<dynamic>? Function() boxGetter,
    required Future<bool> Function(
      Future<dynamic> Function(Box<dynamic> box) operation,
    )
    safeWrite,
  }) : _boxGetter = boxGetter,
       _safeWrite = safeWrite;

  // ── 常量键 ──
  static const String _ttsEnabledKey = 'tts_enabled';
  static const String _ttsAutoPlayKey = 'tts_auto_play';
  static const String _ttsSpeakerIdKey = 'tts_speaker_id';
  static const String _ttsSpeedKey = 'tts_speed';
  static const String _ttsPitchKey = 'tts_pitch';
  static const String _ttsEnergyKey = 'tts_energy';
  static const String _ttsMaxCharsKey = 'tts_max_chars';

  // ── 默认值（与 SettingsService 保持一致，供外部通过 SettingsService.xxx 访问）──
  static const bool defaultTtsEnabled = false;
  static const bool defaultTtsAutoPlay = false;
  static const int defaultTtsSpeakerId = 0;
  static const double defaultTtsSpeed = 1.0;
  static const double minTtsSpeed = 0.5;
  static const double maxTtsSpeed = 2.0;
  static const double defaultTtsPitch = 0.0;
  static const double minTtsPitch = -12.0;
  static const double maxTtsPitch = 12.0;
  static const double defaultTtsEnergy = 1.0;
  static const double minTtsEnergy = 0.5;
  static const double maxTtsEnergy = 2.0;
  static const int defaultTtsMaxChars = 200;
  static const int minTtsMaxChars = 50;
  static const int maxTtsMaxChars = 500;

  // ── NCNN TTS（本地语音播报）──

  bool isTtsEnabled() {
    return _boxGetter()?.get(_ttsEnabledKey, defaultValue: defaultTtsEnabled) ??
        defaultTtsEnabled;
  }

  Future<bool> setTtsEnabled(bool enabled) async {
    return await _safeWrite((box) => box.put(_ttsEnabledKey, enabled));
  }

  bool isTtsAutoPlay() {
    return _boxGetter()?.get(
          _ttsAutoPlayKey,
          defaultValue: defaultTtsAutoPlay,
        ) ??
        defaultTtsAutoPlay;
  }

  Future<bool> setTtsAutoPlay(bool auto) async {
    return await _safeWrite((box) => box.put(_ttsAutoPlayKey, auto));
  }

  int getTtsSpeakerId() {
    return _boxGetter()?.get(
          _ttsSpeakerIdKey,
          defaultValue: defaultTtsSpeakerId,
        ) ??
        defaultTtsSpeakerId;
  }

  Future<bool> setTtsSpeakerId(int id) async {
    return await _safeWrite((box) => box.put(_ttsSpeakerIdKey, id));
  }

  double getTtsSpeed() {
    return _boxGetter()?.get(_ttsSpeedKey, defaultValue: defaultTtsSpeed) ??
        defaultTtsSpeed;
  }

  Future<bool> setTtsSpeed(double speed) async {
    final v = speed.clamp(minTtsSpeed, maxTtsSpeed);
    return await _safeWrite((box) => box.put(_ttsSpeedKey, v));
  }

  double getTtsPitch() {
    return _boxGetter()?.get(_ttsPitchKey, defaultValue: defaultTtsPitch) ??
        defaultTtsPitch;
  }

  Future<bool> setTtsPitch(double pitch) async {
    final v = pitch.clamp(minTtsPitch, maxTtsPitch);
    return await _safeWrite((box) => box.put(_ttsPitchKey, v));
  }

  double getTtsEnergy() {
    return _boxGetter()?.get(_ttsEnergyKey, defaultValue: defaultTtsEnergy) ??
        defaultTtsEnergy;
  }

  Future<bool> setTtsEnergy(double energy) async {
    final v = energy.clamp(minTtsEnergy, maxTtsEnergy);
    return await _safeWrite((box) => box.put(_ttsEnergyKey, v));
  }

  int getTtsMaxChars() {
    return _boxGetter()?.get(
          _ttsMaxCharsKey,
          defaultValue: defaultTtsMaxChars,
        ) ??
        defaultTtsMaxChars;
  }

  Future<bool> setTtsMaxChars(int max) async {
    final v = max.clamp(minTtsMaxChars, maxTtsMaxChars);
    return await _safeWrite((box) => box.put(_ttsMaxCharsKey, v));
  }
}
