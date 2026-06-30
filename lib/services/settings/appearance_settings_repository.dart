import 'package:hive_flutter/hive_flutter.dart';

/// 外观配置仓库（Facade 模式阶段 2：外观子域）
///
/// 做什么：把 SettingsService 中外观相关的配置（助手名、头像、壁纸、模糊、
/// 动画、主题、字体、气泡、OCR 开关、隐私提示）抽到独立类。
/// 为什么这样做：SettingsService 是 God Class，外观子域有 ~50 个方法 + ~30 个常量键，
/// 是第二大子域，抽出后 SettingsService 保留同名 getter/setter 作为 Facade 转发。
class AppearanceSettingsRepository {
  // ── 依赖（通过构造函数注入）──
  final Box<dynamic>? Function() _boxGetter;
  final Future<bool> Function(
    Future<dynamic> Function(Box<dynamic> box) operation,
  )
  _safeWrite;
  final T Function<T>(T Function(Box<dynamic> box) operation, T defaultValue)
  _safeRead;

  AppearanceSettingsRepository({
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
  static const String _assistantNameKey = 'assistant_name';
  static const String _avatarBase64Key = 'avatar_base64';
  static const String _wallpaperBase64Key = 'wallpaper_base64';
  static const String _wallpaperEnabledKey = 'wallpaper_enabled';
  static const String _blurEnabledKey = 'blur_enabled';
  static const String _blurSigmaKey = 'blur_sigma';
  static const String _avatarEnabledKey = 'avatar_enabled';
  static const String _uiAnimationSpeedKey = 'ui_animation_speed';
  static const String _uiTransitionStyleKey = 'ui_transition_style';
  static const String _animationIntensityKey = 'animation_intensity';
  static const String _eyeCareModeEnabledKey = 'eye_care_mode_enabled';
  static const String _animationsDisabledKey = 'animations_disabled';
  static const String _chatBubbleWidthPercentKey = 'chat_bubble_width_percent';
  static const String _fontSizeScaleKey = 'font_size_scale';
  static const String _chatBubbleBackgroundEnabledKey =
      'chat_bubble_background_enabled';
  static const String _inputBoxTransparentKey = 'input_box_transparent';
  static const String _compactUiEnabledKey = 'compact_ui_enabled';
  static const String _lightThemeEnabledKey = 'light_theme_enabled';
  static const String _themeSeedKey = 'theme_seed';
  static const String _appBarTransparentKey = 'app_bar_transparent';
  static const String _messageButtonsAlwaysVisibleKey =
      'message_buttons_always_visible';
  static const String _messageDetailsEnabledKey = 'message_details_enabled';
  static const String _wallpaperFitKey = 'wallpaper_fit';
  static const String _avatarFitKey = 'avatar_fit';
  static const String _iconThemeIdKey = 'icon_theme_id';
  static const String _ocrLocalEnabledKey = 'ocr_local_enabled';
  static const String _ocrCloudEnabledKey = 'ocr_cloud_enabled';
  static const String _ocrAutoEnabledKey = 'ocr_auto_enabled';
  static const String _ocrCloudEngineKey = 'ocr_cloud_engine';
  static const String _cloudOcrPrivacyShownKey = 'cloud_ocr_privacy_shown';

  // ── Assistant Name ──

  String getAssistantName() {
    return _safeRead<String>(
      (box) => (box.get(_assistantNameKey) as String?) ?? '杏铃',
      '杏铃',
    );
  }

  Future<bool> setAssistantName(String name) async {
    return await _safeWrite((box) => box.put(_assistantNameKey, name));
  }

  // ── Avatar ──

  bool isAvatarEnabled() {
    return _safeRead<bool>(
      (box) => (box.get(_avatarEnabledKey) as bool?) ?? false,
      false,
    );
  }

  Future<void> setAvatarEnabled(bool enabled) async {
    await _safeWrite((box) => box.put(_avatarEnabledKey, enabled));
  }

  String? getAvatarBase64() {
    return _safeRead<String?>(
      (box) => box.get(_avatarBase64Key) as String?,
      null,
    );
  }

  Future<void> setAvatarBase64(String? base64) async {
    await _safeWrite((box) async {
      if (base64 == null || base64.isEmpty) {
        await box.delete(_avatarBase64Key);
      } else {
        await box.put(_avatarBase64Key, base64);
      }
      return true;
    });
  }

  // ── Wallpaper ──

  bool isWallpaperEnabled() {
    return _safeRead<bool>(
      (box) => (box.get(_wallpaperEnabledKey) as bool?) ?? false,
      false,
    );
  }

  Future<void> setWallpaperEnabled(bool enabled) async {
    await _safeWrite((box) => box.put(_wallpaperEnabledKey, enabled));
  }

  String? getWallpaperBase64() {
    return _safeRead<String?>(
      (box) => box.get(_wallpaperBase64Key) as String?,
      null,
    );
  }

  Future<void> setWallpaperBase64(String? base64) async {
    await _safeWrite((box) async {
      if (base64 == null || base64.isEmpty) {
        await box.delete(_wallpaperBase64Key);
      } else {
        await box.put(_wallpaperBase64Key, base64);
      }
      return true;
    });
  }

  // ── Blur ──

  bool isBlurEnabled() {
    return _safeRead<bool>(
      (box) => (box.get(_blurEnabledKey) as bool?) ?? false,
      false,
    );
  }

  Future<void> setBlurEnabled(bool enabled) async {
    await _safeWrite((box) => box.put(_blurEnabledKey, enabled));
  }

  double getBlurSigma() {
    return _safeRead<double>(
      (box) => (box.get(_blurSigmaKey) as double?) ?? 10.0,
      10.0,
    );
  }

  Future<void> setBlurSigma(double sigma) async {
    final clamped = sigma.clamp(0.0, 30.0);
    await _safeWrite((box) => box.put(_blurSigmaKey, clamped));
  }

  // ── UI 动画设置 ──

  int getUiAnimationSpeed() {
    return _safeRead<int>(
      (box) => (box.get(_uiAnimationSpeedKey) as int?) ?? 1,
      1,
    );
  }

  Future<bool> setUiAnimationSpeed(int speed) async {
    return await _safeWrite(
      (box) => box.put(_uiAnimationSpeedKey, speed.clamp(0, 3)),
    );
  }

  int getUiTransitionStyle() {
    return _safeRead<int>(
      (box) => (box.get(_uiTransitionStyleKey) as int?) ?? 0,
      0,
    );
  }

  Future<bool> setUiTransitionStyle(int style) async {
    return await _safeWrite(
      (box) => box.put(_uiTransitionStyleKey, style.clamp(0, 4)),
    );
  }

  // ── 动画强度 ──

  int getAnimationIntensity() {
    return _safeRead<int>(
      (box) => (box.get(_animationIntensityKey) as int?) ?? 1,
      1,
    );
  }

  Future<bool> setAnimationIntensity(int intensity) async {
    return await _safeWrite(
      (box) => box.put(_animationIntensityKey, intensity.clamp(0, 2)),
    );
  }

  // ── 护眼模式 ──

  bool isEyeCareModeEnabled() {
    return _safeRead<bool>(
      (box) => (box.get(_eyeCareModeEnabledKey) as bool?) ?? false,
      false,
    );
  }

  Future<bool> setEyeCareModeEnabled(bool enabled) async {
    return await _safeWrite((box) => box.put(_eyeCareModeEnabledKey, enabled));
  }

  // ── 关闭所有动画 ──

  bool isAnimationsDisabled() {
    return _safeRead<bool>(
      (box) => (box.get(_animationsDisabledKey) as bool?) ?? false,
      false,
    );
  }

  Future<bool> setAnimationsDisabled(bool disabled) async {
    return await _safeWrite((box) => box.put(_animationsDisabledKey, disabled));
  }

  // ── 对话气泡宽度 ──

  int getChatBubbleWidthPercent() {
    return _safeRead<int>(
      (box) => (box.get(_chatBubbleWidthPercentKey) as int?) ?? 70,
      70,
    );
  }

  Future<bool> setChatBubbleWidthPercent(int percent) async {
    return await _safeWrite(
      (box) => box.put(_chatBubbleWidthPercentKey, percent.clamp(50, 90)),
    );
  }

  // ── 字体大小缩放 ──

  double getFontSizeScale() {
    return _safeRead<double>(
      (box) => (box.get(_fontSizeScaleKey) as double?) ?? 1.0,
      1.0,
    );
  }

  Future<bool> setFontSizeScale(double scale) async {
    return await _safeWrite(
      (box) => box.put(_fontSizeScaleKey, scale.clamp(0.8, 1.5)),
    );
  }

  // ── 消息气泡背景 ──

  bool isChatBubbleBackgroundEnabled() {
    return _safeRead<bool>(
      (box) => (box.get(_chatBubbleBackgroundEnabledKey) as bool?) ?? true,
      true,
    );
  }

  Future<bool> setChatBubbleBackgroundEnabled(bool enabled) async {
    return await _safeWrite(
      (box) => box.put(_chatBubbleBackgroundEnabledKey, enabled),
    );
  }

  // ── 输入框透明 ──

  bool isInputBoxTransparent() {
    return _safeRead<bool>(
      (box) => (box.get(_inputBoxTransparentKey) as bool?) ?? false,
      false,
    );
  }

  Future<bool> setInputBoxTransparent(bool transparent) async {
    return await _safeWrite(
      (box) => box.put(_inputBoxTransparentKey, transparent),
    );
  }

  // ── 紧凑UI ──

  bool isCompactUiEnabled() {
    return _safeRead<bool>(
      (box) => (box.get(_compactUiEnabledKey) as bool?) ?? false,
      false,
    );
  }

  Future<bool> setCompactUiEnabled(bool enabled) async {
    return await _safeWrite((box) => box.put(_compactUiEnabledKey, enabled));
  }

  // ── 亮色主题 ──

  bool isLightThemeEnabled() {
    return _safeRead<bool>(
      (box) => (box.get(_lightThemeEnabledKey) as bool?) ?? false,
      false,
    );
  }

  Future<bool> setLightThemeEnabled(bool enabled) async {
    return await _safeWrite((box) => box.put(_lightThemeEnabledKey, enabled));
  }

  String getThemeSeed() {
    return _safeRead<String>(
      (box) => box.get(_themeSeedKey) as String? ?? 'deepPurple',
      'deepPurple',
    );
  }

  Future<bool> setThemeSeed(String seed) async {
    return await _safeWrite((box) => box.put(_themeSeedKey, seed));
  }

  // ── 图标主题 ──

  String getIconThemeId() {
    return _safeRead<String>(
      (box) => box.get(_iconThemeIdKey) as String? ?? 'material',
      'material',
    );
  }

  Future<bool> setIconThemeId(String id) async {
    return await _safeWrite((box) => box.put(_iconThemeIdKey, id));
  }

  // ── AppBar透明 ──

  bool isAppBarTransparent() {
    return _safeRead<bool>(
      (box) => (box.get(_appBarTransparentKey) as bool?) ?? false,
      false,
    );
  }

  Future<bool> setAppBarTransparent(bool transparent) async {
    return await _safeWrite(
      (box) => box.put(_appBarTransparentKey, transparent),
    );
  }

  // ── 消息按钮常驻显示 ──

  bool isMessageButtonsAlwaysVisible() {
    return _safeRead<bool>(
      (box) => (box.get(_messageButtonsAlwaysVisibleKey) as bool?) ?? false,
      false,
    );
  }

  Future<bool> setMessageButtonsAlwaysVisible(bool visible) async {
    return await _safeWrite(
      (box) => box.put(_messageButtonsAlwaysVisibleKey, visible),
    );
  }

  // ── 消息详情显示 ──

  bool isMessageDetailsEnabled() {
    return _safeRead<bool>(
      (box) => (box.get(_messageDetailsEnabledKey) as bool?) ?? false,
      false,
    );
  }

  Future<bool> setMessageDetailsEnabled(bool enabled) async {
    return await _safeWrite(
      (box) => box.put(_messageDetailsEnabledKey, enabled),
    );
  }

  // ── 壁纸 Fit 模式 ──

  String getWallpaperFit() {
    return _safeRead<String>(
      (box) => (box.get(_wallpaperFitKey) as String?) ?? 'cover',
      'cover',
    );
  }

  Future<bool> setWallpaperFit(String fit) async {
    return await _safeWrite((box) => box.put(_wallpaperFitKey, fit));
  }

  // ── 头像 Fit 模式 ──

  String getAvatarFit() {
    return _safeRead<String>(
      (box) => (box.get(_avatarFitKey) as String?) ?? 'cover',
      'cover',
    );
  }

  Future<bool> setAvatarFit(String fit) async {
    return await _safeWrite((box) => box.put(_avatarFitKey, fit));
  }

  // ── OCR 开关设置 ──

  bool isOcrLocalEnabled() {
    return _boxGetter()?.get(_ocrLocalEnabledKey, defaultValue: true) ?? true;
  }

  Future<bool> setOcrLocalEnabled(bool enabled) async {
    return await _safeWrite((box) => box.put(_ocrLocalEnabledKey, enabled));
  }

  bool isOcrCloudEnabled() {
    return _boxGetter()?.get(_ocrCloudEnabledKey, defaultValue: false) ?? false;
  }

  Future<bool> setOcrCloudEnabled(bool enabled) async {
    return await _safeWrite((box) => box.put(_ocrCloudEnabledKey, enabled));
  }

  bool isOcrAutoEnabled() {
    return _boxGetter()?.get(_ocrAutoEnabledKey, defaultValue: true) ?? true;
  }

  Future<bool> setOcrAutoEnabled(bool enabled) async {
    return await _safeWrite((box) => box.put(_ocrAutoEnabledKey, enabled));
  }

  String getOcrCloudEngine() {
    return _boxGetter()?.get(_ocrCloudEngineKey, defaultValue: 'baidu') ??
        'baidu';
  }

  Future<bool> setOcrCloudEngine(String engine) async {
    return await _safeWrite((box) => box.put(_ocrCloudEngineKey, engine));
  }

  // ── 云端 OCR 隐私提示 ──

  bool isCloudOcrPrivacyShown() {
    return _safeRead<bool>(
      (box) => (box.get(_cloudOcrPrivacyShownKey) as bool?) ?? false,
      false,
    );
  }

  Future<bool> setCloudOcrPrivacyShown(bool shown) async {
    return await _safeWrite((box) => box.put(_cloudOcrPrivacyShownKey, shown));
  }
}
