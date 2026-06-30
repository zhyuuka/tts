import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'secure_storage_service.dart';
import 'settings/ai_settings_repository.dart';
import 'settings/agent_settings_repository.dart';
import 'settings/appearance_settings_repository.dart';
import 'settings/changelog_settings_repository.dart';
import 'settings/ocr_settings_repository.dart';
import 'settings/search_settings_repository.dart';
import 'settings/speech_settings_repository.dart';
import 'settings/tts_settings_repository.dart';

// 重新导出 CustomModelConfig（已移至 ai_settings_repository.dart）
// 为什么这样做：多个文件通过 settings_service.dart 导入 CustomModelConfig，
// export 保持向后兼容，调用方零改动。
export 'settings/ai_settings_repository.dart' show CustomModelConfig;

/// 带重试和错误处理的健壮设置服务（Facade 模式阶段 2）
///
/// 做什么：本类是设置系统的统一门面（Facade），所有具体逻辑已抽到 8 个 Repository：
/// - AiSettingsRepository：API Key、模型、参数、自定义模型、语义评分
/// - SearchSettingsRepository：联网搜索开关、引擎、API Key
/// - AppearanceSettingsRepository：头像、壁纸、动画、主题、OCR 开关
/// - SpeechSettingsRepository：云端语音识别、STT 模式
/// - TtsSettingsRepository：NCNN TTS 本地语音播报
/// - AgentSettingsRepository：Agent 视觉 fallback、黑白名单、知情同意
/// - ChangelogSettingsRepository：更新日志显示模式
/// - OcrSettingsRepository：OCR 密钥（阶段 1 已抽出）
///
/// 为什么这样做：原 SettingsService 是 God Class（1700+ 行），认知负担重、
/// 测试困难、容易引入回归。拆分后各 Repository 职责单一，SettingsService 仅保留：
/// 1. 基础设施（Hive Box 初始化、_safeWrite/_safeRead 重试逻辑）
/// 2. 会话状态（lastConvId、preload、isLoading、draftInput 等不属于 7 子域的）
/// 3. 8 个 Repository 实例的初始化
/// 4. 所有 getter/setter 的 Facade 转发（调用方零改动）
///
/// API Key 现在使用 flutter_secure_storage 安全存储（硬件加密），
/// 其他设置继续使用 Hive（本地数据库）。
class SettingsService extends ChangeNotifier {
  static SettingsService? _instance;
  static SettingsService get instance {
    _instance ??= SettingsService();
    return _instance!;
  }

  // Hive Box（用于非敏感设置）
  Box<dynamic>? _box;
  bool _initialized = false;
  static const String _boxName = 'settings';
  static const String _healthCheckKey = '_health_check';

  // 安全存储实例（用于 API Key 等敏感信息）
  // 注意：secure storage 初始化状态由各 Repository 自行管理（Repository 有自己的 _secureStorageInitialized）
  final SecureStorageService _secureStorage = SecureStorageService();

  // API Key 缓存
  final Map<String, String?> _apiKeyCache = {};

  // ── 8 个 Repository 实例 ──
  // 为什么用 late final：依赖 _box/_apiKeyCache 等实例字段，需在构造函数后初始化。
  // 为什么通过回调注入而非直接传 _box：Box 在 init() 后才可用，回调保证每次访问最新值。
  late final OcrSettingsRepository _ocrSettings = OcrSettingsRepository(
    boxGetter: () => _box,
    secureStorage: _secureStorage,
    apiKeyCache: _apiKeyCache,
    safeWrite: _safeWrite,
    notifyListeners: notifyListeners,
  );

  late final AiSettingsRepository _aiSettings = AiSettingsRepository(
    secureStorage: _secureStorage,
    apiKeyCache: _apiKeyCache,
    safeWrite: _safeWrite,
    safeRead: _safeRead,
    notifyListeners: notifyListeners,
  );

  late final SearchSettingsRepository _searchSettings =
      SearchSettingsRepository(
        secureStorage: _secureStorage,
        apiKeyCache: _apiKeyCache,
        safeWrite: _safeWrite,
        safeRead: _safeRead,
        notifyListeners: notifyListeners,
      );

  late final AppearanceSettingsRepository _appearanceSettings =
      AppearanceSettingsRepository(
        boxGetter: () => _box,
        safeWrite: _safeWrite,
        safeRead: _safeRead,
      );

  late final SpeechSettingsRepository _speechSettings =
      SpeechSettingsRepository(
        boxGetter: () => _box,
        safeWrite: _safeWrite,
        safeRead: _safeRead,
      );

  late final TtsSettingsRepository _ttsSettings = TtsSettingsRepository(
    boxGetter: () => _box,
    safeWrite: _safeWrite,
  );

  late final AgentSettingsRepository _agentSettings = AgentSettingsRepository(
    safeWrite: _safeWrite,
    safeRead: _safeRead,
  );

  late final ChangelogSettingsRepository _changelogSettings =
      ChangelogSettingsRepository(safeWrite: _safeWrite, safeRead: _safeRead);

  // 重试配置
  static const int _maxRetries = 3;
  static const Duration _retryDelay = Duration(milliseconds: 200);

  // ── 保留在主类的常量键（会话状态/基础设施，不属于 7 子域）──
  static const String _lastConvIdKey = 'last_conversation_id';
  static const String _customStoragePathKey = 'custom_storage_path';
  static const String _preloadMessageCountKey = 'preload_message_count';
  static const String _preloadConversationIdKey = 'preload_conversation_id';
  static const String _isLoadingKey = 'is_loading';
  static const String _draftInputTextKey = 'draft_input_text';
  static const String _setupCompletedKey = 'setup_completed';

  // ── 默认值（保留 static const 供外部通过 SettingsService.xxx 访问）──
  // 注意：各 Repository 内部也有自己的默认值副本，两者必须保持一致。
  // 为什么保留两份：Repository 内部逻辑需要默认值，外部 UI 通过 SettingsService.xxx 访问。
  static const String defaultModel = 'deepseek-chat';
  static const double minFontSizeScale = 0.8;
  static const double maxFontSizeScale = 1.5;
  static const double defaultFontSizeScale = 1.0;
  static const String defaultAssistantName = '杏铃';
  static const double defaultBlurSigma = 10.0;
  static const double minBlurSigma = 0.0;
  static const double maxBlurSigma = 30.0;
  static const String defaultAiServiceId = 'doubao';
  static const String defaultSearchEngine = 'duckduckgo';
  static const int defaultUiAnimationSpeed = 1;
  static const int defaultUiTransitionStyle = 0;
  static const int defaultAnimationIntensity = 1;
  static const bool defaultEyeCareModeEnabled = false;
  static const bool defaultAnimationsDisabled = false;
  static const int minChatBubbleWidthPct = 50;
  static const int maxChatBubbleWidthPct = 90;
  static const int defaultChatBubbleWidthPercent = 70;
  static const bool defaultAiAutoTitleEnabled = true;
  static const bool defaultChatBubbleBackgroundEnabled = true;
  static const bool defaultInputBoxTransparent = false;
  static const bool defaultCompactUiEnabled = false;
  static const bool defaultLightThemeEnabled = false;
  static const bool defaultAppBarTransparent = false;
  static const bool defaultMessageButtonsAlwaysVisible = false;
  static const int defaultPreloadMessageCount = 50;
  static const bool defaultMessageDetailsEnabled = false;
  static const int minPreloadMessageCount = 10;
  static const int maxPreloadMessageCount = 200;

  // NCNN TTS 默认值（tts_settings_page.dart 通过 SettingsService.xxx 访问）
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

  /// 是否已成功初始化
  bool get isInitialized => _initialized;

  /// 初始化，包含重试、损坏恢复和写入自检
  Future<bool> init() async {
    for (int attempt = 1; attempt <= _maxRetries; attempt++) {
      try {
        // 如果之前有 box，先关闭
        if (_box != null) {
          try {
            await _box!.close();
          } catch (_) {}
          _box = null;
        }

        _box = await Hive.openBox<dynamic>(_boxName);

        // 写入自检：验证 box 真正可写
        await _box!.put(_healthCheckKey, 'ok');
        final check = _box!.get(_healthCheckKey);
        await _box!.delete(_healthCheckKey);

        if (check != 'ok') {
          debugPrint('SettingsService 写入自检失败: 读回值异常');
          throw Exception('写入自检失败');
        }

        _initialized = true;
        debugPrint(
          'SettingsService 初始化成功 (attempt $attempt), box keys: ${_box!.keys.length}',
        );

        // 初始化安全存储（用于 API Key）
        // 返回值不存储：各 Repository 有自己的 _secureStorageInitialized 标记
        await _secureStorage.init();

        // 预加载当前服务的 API Key 到缓存
        try {
          final serviceId = getAiServiceId();
          final apiKey = await _aiSettings.getApiKeyFromSecureStorage(
            serviceId,
          );
          if (apiKey != null && apiKey.isNotEmpty) {
            _apiKeyCache[serviceId] = apiKey;
          }
        } catch (e) {
          debugPrint('SettingsService 预加载 API Key 失败: $e');
        }

        // 预加载搜索引擎 API Key 到缓存（并自动从 Hive 迁移旧值）
        try {
          await loadSearchApiKey();
        } catch (e) {
          debugPrint('SettingsService 预加载搜索引擎 API Key 失败: $e');
        }

        notifyListeners();
        return true;
      } catch (e) {
        debugPrint('SettingsService 初始化 attempt $attempt/$_maxRetries 失败: $e');
        _initialized = false;
        _box = null;
        if (attempt < _maxRetries) {
          await Future.delayed(_retryDelay * attempt);
          try {
            await Hive.deleteBoxFromDisk(_boxName);
          } catch (_) {}
        }
      }
    }
    return false;
  }

  /// 检查 box 是否可用
  bool get _boxReady {
    return _initialized && _box != null && _box!.isOpen;
  }

  /// 安全执行 Hive 写操作，自动重试，返回操作是否成功
  Future<bool> _safeWrite<T>(
    Future<T> Function(Box<dynamic> box) operation,
  ) async {
    if (!_boxReady) {
      debugPrint(
        'SettingsService _safeWrite: box 不可用 (_initialized=$_initialized, _box=${_box != null}, isOpen=${_box?.isOpen})',
      );
      // 尝试恢复
      await init();
      if (!_boxReady) return false;
    }
    for (int attempt = 1; attempt <= _maxRetries; attempt++) {
      try {
        await operation(_box!);
        notifyListeners();
        return true;
      } catch (e) {
        debugPrint('SettingsService 写入 attempt $attempt 失败: $e');
        if (attempt == _maxRetries) {
          await init();
          if (_boxReady) {
            try {
              await operation(_box!);
              notifyListeners();
              return true;
            } catch (e2) {
              debugPrint('SettingsService 恢复后写入仍失败: $e2');
            }
          }
        } else {
          await Future.delayed(_retryDelay);
        }
      }
    }
    return false;
  }

  /// 安全读取 Hive 操作
  T _safeRead<T>(T Function(Box<dynamic> box) operation, T defaultValue) {
    if (!_initialized || _box == null) return defaultValue;
    try {
      return operation(_box!);
    } catch (e) {
      debugPrint('SettingsService 读取失败: $e');
      return defaultValue;
    }
  }

  // ════════════════════════════════════════════════════════════════
  // Facade 转发方法（调用方零改动）
  // ════════════════════════════════════════════════════════════════

  // ── AI 子域（转发到 _aiSettings）──

  String? getApiKey() => _aiSettings.getApiKey();
  Future<String?> loadApiKey() => _aiSettings.loadApiKey();
  Future<bool> setApiKey(String apiKey) => _aiSettings.setApiKey(apiKey);
  bool hasApiKey() => _aiSettings.hasApiKey();
  Future<void> clearApiKey() => _aiSettings.clearApiKey();

  String? getApiKeyForService(String serviceId) =>
      _aiSettings.getApiKeyForService(serviceId);
  Future<String?> loadApiKeyForService(String serviceId) =>
      _aiSettings.loadApiKeyForService(serviceId);
  Future<bool> setApiKeyForService(String serviceId, String apiKey) =>
      _aiSettings.setApiKeyForService(serviceId, apiKey);

  String getModel() => _aiSettings.getModel();
  Future<void> setModel(String model) => _aiSettings.setModel(model);
  String getModelId() => _aiSettings.getModelId();
  Future<void> setModelId(String modelId) => _aiSettings.setModelId(modelId);

  double getTemperature() => _aiSettings.getTemperature();
  Future<void> setTemperature(double value) =>
      _aiSettings.setTemperature(value);
  int getMaxTokens() => _aiSettings.getMaxTokens();
  Future<void> setMaxTokens(int value) => _aiSettings.setMaxTokens(value);
  double getTopP() => _aiSettings.getTopP();
  Future<void> setTopP(double value) => _aiSettings.setTopP(value);
  double getFrequencyPenalty() => _aiSettings.getFrequencyPenalty();
  Future<void> setFrequencyPenalty(double value) =>
      _aiSettings.setFrequencyPenalty(value);
  double getPresencePenalty() => _aiSettings.getPresencePenalty();
  Future<void> setPresencePenalty(double value) =>
      _aiSettings.setPresencePenalty(value);

  String getAiServiceId() => _aiSettings.getAiServiceId();
  Future<bool> setAiServiceId(String serviceId) =>
      _aiSettings.setAiServiceId(serviceId);

  bool isLoadAllOnStart() => _aiSettings.isLoadAllOnStart();
  Future<void> setLoadAllOnStart(bool enabled) =>
      _aiSettings.setLoadAllOnStart(enabled);

  String getCustomModelBaseUrl() => _aiSettings.getCustomModelBaseUrl();
  Future<bool> setCustomModelBaseUrl(String baseUrl) =>
      _aiSettings.setCustomModelBaseUrl(baseUrl);
  String getCustomModelName() => _aiSettings.getCustomModelName();
  Future<bool> setCustomModelName(String modelName) =>
      _aiSettings.setCustomModelName(modelName);

  List<CustomModelConfig> getCustomModels() => _aiSettings.getCustomModels();
  Future<bool> setCustomModels(List<CustomModelConfig> models) =>
      _aiSettings.setCustomModels(models);
  Future<bool> addCustomModel(CustomModelConfig model) =>
      _aiSettings.addCustomModel(model);
  Future<bool> removeCustomModel(String name) =>
      _aiSettings.removeCustomModel(name);

  List<String> getCustomModelIdsForService(String serviceId) =>
      _aiSettings.getCustomModelIdsForService(serviceId);
  Future<bool> addCustomModelIdForService(String serviceId, String modelId) =>
      _aiSettings.addCustomModelIdForService(serviceId, modelId);
  Future<bool> removeCustomModelIdForService(
    String serviceId,
    String modelId,
  ) => _aiSettings.removeCustomModelIdForService(serviceId, modelId);

  bool isAiAutoTitleEnabled() => _aiSettings.isAiAutoTitleEnabled();
  Future<bool> setAiAutoTitleEnabled(bool enabled) =>
      _aiSettings.setAiAutoTitleEnabled(enabled);

  String getMemoryScorerServiceId() => _aiSettings.getMemoryScorerServiceId();
  Future<bool> setMemoryScorerServiceId(String serviceId) =>
      _aiSettings.setMemoryScorerServiceId(serviceId);
  String getMemoryScorerModel() => _aiSettings.getMemoryScorerModel();
  Future<bool> setMemoryScorerModel(String model) =>
      _aiSettings.setMemoryScorerModel(model);

  // ── 搜索子域（转发到 _searchSettings）──

  bool isSearchEnabled() => _searchSettings.isSearchEnabled();
  Future<void> setSearchEnabled(bool enabled) =>
      _searchSettings.setSearchEnabled(enabled);
  String getSearchEngine() => _searchSettings.getSearchEngine();
  Future<void> setSearchEngine(String engineId) =>
      _searchSettings.setSearchEngine(engineId);
  String getSearchEngineId() => _searchSettings.getSearchEngineId();
  Future<void> setSearchEngineId(String engineId) =>
      _searchSettings.setSearchEngineId(engineId);

  String getSearchApiKey() => _searchSettings.getSearchApiKey();
  Future<void> loadSearchApiKey() => _searchSettings.loadSearchApiKey();
  Future<void> setSearchApiKey(String key) =>
      _searchSettings.setSearchApiKey(key);

  String getGoogleSearchEngineId() => _searchSettings.getGoogleSearchEngineId();
  Future<void> setGoogleSearchEngineId(String cx) =>
      _searchSettings.setGoogleSearchEngineId(cx);
  String getSearXngUrl() => _searchSettings.getSearXngUrl();
  Future<void> setSearXngUrl(String url) => _searchSettings.setSearXngUrl(url);

  bool isSearchPrivacyShown() => _searchSettings.isSearchPrivacyShown();
  Future<bool> setSearchPrivacyShown(bool shown) =>
      _searchSettings.setSearchPrivacyShown(shown);

  // ── 外观子域（转发到 _appearanceSettings）──

  String getAssistantName() => _appearanceSettings.getAssistantName();
  Future<bool> setAssistantName(String name) =>
      _appearanceSettings.setAssistantName(name);

  bool isAvatarEnabled() => _appearanceSettings.isAvatarEnabled();
  Future<void> setAvatarEnabled(bool enabled) =>
      _appearanceSettings.setAvatarEnabled(enabled);
  String? getAvatarBase64() => _appearanceSettings.getAvatarBase64();
  Future<void> setAvatarBase64(String? base64) =>
      _appearanceSettings.setAvatarBase64(base64);

  bool isWallpaperEnabled() => _appearanceSettings.isWallpaperEnabled();
  Future<void> setWallpaperEnabled(bool enabled) =>
      _appearanceSettings.setWallpaperEnabled(enabled);
  String? getWallpaperBase64() => _appearanceSettings.getWallpaperBase64();
  Future<void> setWallpaperBase64(String? base64) =>
      _appearanceSettings.setWallpaperBase64(base64);

  bool isBlurEnabled() => _appearanceSettings.isBlurEnabled();
  Future<void> setBlurEnabled(bool enabled) =>
      _appearanceSettings.setBlurEnabled(enabled);
  double getBlurSigma() => _appearanceSettings.getBlurSigma();
  Future<void> setBlurSigma(double sigma) =>
      _appearanceSettings.setBlurSigma(sigma);

  int getUiAnimationSpeed() => _appearanceSettings.getUiAnimationSpeed();
  Future<bool> setUiAnimationSpeed(int speed) =>
      _appearanceSettings.setUiAnimationSpeed(speed);
  int getUiTransitionStyle() => _appearanceSettings.getUiTransitionStyle();
  Future<bool> setUiTransitionStyle(int style) =>
      _appearanceSettings.setUiTransitionStyle(style);

  int getAnimationIntensity() => _appearanceSettings.getAnimationIntensity();
  Future<bool> setAnimationIntensity(int intensity) =>
      _appearanceSettings.setAnimationIntensity(intensity);

  bool isEyeCareModeEnabled() => _appearanceSettings.isEyeCareModeEnabled();
  Future<bool> setEyeCareModeEnabled(bool enabled) =>
      _appearanceSettings.setEyeCareModeEnabled(enabled);

  bool isAnimationsDisabled() => _appearanceSettings.isAnimationsDisabled();
  Future<bool> setAnimationsDisabled(bool disabled) =>
      _appearanceSettings.setAnimationsDisabled(disabled);

  int getChatBubbleWidthPercent() =>
      _appearanceSettings.getChatBubbleWidthPercent();
  Future<bool> setChatBubbleWidthPercent(int percent) =>
      _appearanceSettings.setChatBubbleWidthPercent(percent);

  double getFontSizeScale() => _appearanceSettings.getFontSizeScale();
  Future<bool> setFontSizeScale(double scale) =>
      _appearanceSettings.setFontSizeScale(scale);

  bool isChatBubbleBackgroundEnabled() =>
      _appearanceSettings.isChatBubbleBackgroundEnabled();
  Future<bool> setChatBubbleBackgroundEnabled(bool enabled) =>
      _appearanceSettings.setChatBubbleBackgroundEnabled(enabled);

  bool isInputBoxTransparent() => _appearanceSettings.isInputBoxTransparent();
  Future<bool> setInputBoxTransparent(bool transparent) =>
      _appearanceSettings.setInputBoxTransparent(transparent);

  bool isCompactUiEnabled() => _appearanceSettings.isCompactUiEnabled();
  Future<bool> setCompactUiEnabled(bool enabled) =>
      _appearanceSettings.setCompactUiEnabled(enabled);

  bool isLightThemeEnabled() => _appearanceSettings.isLightThemeEnabled();
  Future<bool> setLightThemeEnabled(bool enabled) =>
      _appearanceSettings.setLightThemeEnabled(enabled);
  String getThemeSeed() => _appearanceSettings.getThemeSeed();
  Future<bool> setThemeSeed(String seed) =>
      _appearanceSettings.setThemeSeed(seed);

  String getIconThemeId() => _appearanceSettings.getIconThemeId();
  Future<bool> setIconThemeId(String id) =>
      _appearanceSettings.setIconThemeId(id);

  bool isAppBarTransparent() => _appearanceSettings.isAppBarTransparent();
  Future<bool> setAppBarTransparent(bool transparent) =>
      _appearanceSettings.setAppBarTransparent(transparent);

  bool isMessageButtonsAlwaysVisible() =>
      _appearanceSettings.isMessageButtonsAlwaysVisible();
  Future<bool> setMessageButtonsAlwaysVisible(bool visible) =>
      _appearanceSettings.setMessageButtonsAlwaysVisible(visible);

  bool isMessageDetailsEnabled() =>
      _appearanceSettings.isMessageDetailsEnabled();
  Future<bool> setMessageDetailsEnabled(bool enabled) =>
      _appearanceSettings.setMessageDetailsEnabled(enabled);

  String getWallpaperFit() => _appearanceSettings.getWallpaperFit();
  Future<bool> setWallpaperFit(String fit) =>
      _appearanceSettings.setWallpaperFit(fit);
  String getAvatarFit() => _appearanceSettings.getAvatarFit();
  Future<bool> setAvatarFit(String fit) =>
      _appearanceSettings.setAvatarFit(fit);

  // OCR 开关（转发到 _appearanceSettings）
  bool isOcrLocalEnabled() => _appearanceSettings.isOcrLocalEnabled();
  Future<bool> setOcrLocalEnabled(bool enabled) =>
      _appearanceSettings.setOcrLocalEnabled(enabled);
  bool isOcrCloudEnabled() => _appearanceSettings.isOcrCloudEnabled();
  Future<bool> setOcrCloudEnabled(bool enabled) =>
      _appearanceSettings.setOcrCloudEnabled(enabled);
  bool isOcrAutoEnabled() => _appearanceSettings.isOcrAutoEnabled();
  Future<bool> setOcrAutoEnabled(bool enabled) =>
      _appearanceSettings.setOcrAutoEnabled(enabled);
  String getOcrCloudEngine() => _appearanceSettings.getOcrCloudEngine();
  Future<bool> setOcrCloudEngine(String engine) =>
      _appearanceSettings.setOcrCloudEngine(engine);

  bool isCloudOcrPrivacyShown() => _appearanceSettings.isCloudOcrPrivacyShown();
  Future<bool> setCloudOcrPrivacyShown(bool shown) =>
      _appearanceSettings.setCloudOcrPrivacyShown(shown);

  // ── 语音识别子域（转发到 _speechSettings）──

  bool isCloudSpeechEnabled() => _speechSettings.isCloudSpeechEnabled();
  Future<bool> setCloudSpeechEnabled(bool enabled) =>
      _speechSettings.setCloudSpeechEnabled(enabled);
  String getCloudSpeechProvider() => _speechSettings.getCloudSpeechProvider();
  Future<bool> setCloudSpeechProvider(String provider) =>
      _speechSettings.setCloudSpeechProvider(provider);
  String getCloudSpeechBaseUrl() => _speechSettings.getCloudSpeechBaseUrl();
  Future<bool> setCloudSpeechBaseUrl(String url) =>
      _speechSettings.setCloudSpeechBaseUrl(url);

  String getSttMode() => _speechSettings.getSttMode();
  Future<bool> setSttMode(String mode) => _speechSettings.setSttMode(mode);

  // ── TTS 子域（转发到 _ttsSettings）──

  bool isTtsEnabled() => _ttsSettings.isTtsEnabled();
  Future<bool> setTtsEnabled(bool enabled) =>
      _ttsSettings.setTtsEnabled(enabled);
  bool isTtsAutoPlay() => _ttsSettings.isTtsAutoPlay();
  Future<bool> setTtsAutoPlay(bool auto) => _ttsSettings.setTtsAutoPlay(auto);
  int getTtsSpeakerId() => _ttsSettings.getTtsSpeakerId();
  Future<bool> setTtsSpeakerId(int id) => _ttsSettings.setTtsSpeakerId(id);
  double getTtsSpeed() => _ttsSettings.getTtsSpeed();
  Future<bool> setTtsSpeed(double speed) => _ttsSettings.setTtsSpeed(speed);
  double getTtsPitch() => _ttsSettings.getTtsPitch();
  Future<bool> setTtsPitch(double pitch) => _ttsSettings.setTtsPitch(pitch);
  double getTtsEnergy() => _ttsSettings.getTtsEnergy();
  Future<bool> setTtsEnergy(double energy) => _ttsSettings.setTtsEnergy(energy);
  int getTtsMaxChars() => _ttsSettings.getTtsMaxChars();
  Future<bool> setTtsMaxChars(int max) => _ttsSettings.setTtsMaxChars(max);

  // ── Agent 子域（转发到 _agentSettings）──

  bool isAgentVisionEnabled() => _agentSettings.isAgentVisionEnabled();
  Future<bool> setAgentVisionEnabled(bool enabled) =>
      _agentSettings.setAgentVisionEnabled(enabled);
  String getAgentVisionServiceId() => _agentSettings.getAgentVisionServiceId();
  Future<bool> setAgentVisionServiceId(String serviceId) =>
      _agentSettings.setAgentVisionServiceId(serviceId);
  String getAgentVisionModel() => _agentSettings.getAgentVisionModel();
  Future<bool> setAgentVisionModel(String model) =>
      _agentSettings.setAgentVisionModel(model);

  List<String> getAgentBlacklist() => _agentSettings.getAgentBlacklist();
  Future<bool> setAgentBlacklist(List<String> packages) =>
      _agentSettings.setAgentBlacklist(packages);
  List<String> getAgentWhitelist() => _agentSettings.getAgentWhitelist();
  Future<bool> setAgentWhitelist(List<String> packages) =>
      _agentSettings.setAgentWhitelist(packages);
  bool isAgentBankProtectionEnabled() =>
      _agentSettings.isAgentBankProtectionEnabled();
  Future<bool> setAgentBankProtectionEnabled(bool enabled) =>
      _agentSettings.setAgentBankProtectionEnabled(enabled);

  bool isAgentConsentAccepted() => _agentSettings.isAgentConsentAccepted();
  Future<bool> setAgentConsentAccepted(bool accepted) =>
      _agentSettings.setAgentConsentAccepted(accepted);

  // ── 更新日志子域（转发到 _changelogSettings）──

  String getChangelogMode() => _changelogSettings.getChangelogMode();
  Future<bool> setChangelogMode(String mode) =>
      _changelogSettings.setChangelogMode(mode);
  bool isChangelogDontRemindMode() =>
      _changelogSettings.isChangelogDontRemindMode();
  Future<bool> setChangelogDontRemindMode(bool dontRemind) =>
      _changelogSettings.setChangelogDontRemindMode(dontRemind);
  bool isChangelogAiSearchEnabled() =>
      _changelogSettings.isChangelogAiSearchEnabled();
  Future<bool> setChangelogAiSearchEnabled(bool enabled) =>
      _changelogSettings.setChangelogAiSearchEnabled(enabled);
  bool isChangelogDontRemindAiSearch() =>
      _changelogSettings.isChangelogDontRemindAiSearch();
  Future<bool> setChangelogDontRemindAiSearch(bool dontRemind) =>
      _changelogSettings.setChangelogDontRemindAiSearch(dontRemind);

  // ── OCR 密钥子域（转发到 _ocrSettings，阶段 1 已抽出）──

  Future<void> loadOcrKeys() async {
    await _ocrSettings.loadOcrKeys();
  }

  String getOcrBaiduApiKey() => _ocrSettings.getOcrBaiduApiKey();
  Future<bool> setOcrBaiduApiKey(String key) =>
      _ocrSettings.setOcrBaiduApiKey(key);

  String getOcrBaiduSecretKey() => _ocrSettings.getOcrBaiduSecretKey();
  Future<bool> setOcrBaiduSecretKey(String key) =>
      _ocrSettings.setOcrBaiduSecretKey(key);

  String getOcrTencentSecretId() => _ocrSettings.getOcrTencentSecretId();
  Future<bool> setOcrTencentSecretId(String id) =>
      _ocrSettings.setOcrTencentSecretId(id);

  String getOcrTencentSecretKey() => _ocrSettings.getOcrTencentSecretKey();
  Future<bool> setOcrTencentSecretKey(String key) =>
      _ocrSettings.setOcrTencentSecretKey(key);

  String getOcrAliyunAppCode() => _ocrSettings.getOcrAliyunAppCode();
  Future<bool> setOcrAliyunAppCode(String code) =>
      _ocrSettings.setOcrAliyunAppCode(code);

  // ════════════════════════════════════════════════════════════════
  // 保留在主类的方法（会话状态/基础设施，不属于 7 子域）
  // ════════════════════════════════════════════════════════════════

  // ── 上次活跃会话 ──

  String getLastConversationId() {
    return _safeRead<String>(
      (box) => (box.get(_lastConvIdKey) as String?) ?? '',
      '',
    );
  }

  Future<bool> setLastConversationId(String id) async {
    return await _safeWrite((box) => box.put(_lastConvIdKey, id));
  }

  // ── 自定义存储路径 ──

  String? getCustomStoragePath() {
    return _safeRead<String?>(
      (box) => box.get(_customStoragePathKey) as String?,
      null,
    );
  }

  Future<bool> setCustomStoragePath(String? path) async {
    if (path == null || path.isEmpty) {
      return await _safeWrite((box) async {
        await box.delete(_customStoragePathKey);
        return true;
      });
    }
    return await _safeWrite((box) => box.put(_customStoragePathKey, path));
  }

  // ── 引导设置 ──

  bool isSetupCompleted() {
    return _safeRead<bool>(
      (box) => (box.get(_setupCompletedKey) as bool?) ?? false,
      false,
    );
  }

  Future<bool> setSetupCompleted(bool completed) async {
    return await _safeWrite((box) => box.put(_setupCompletedKey, completed));
  }

  // ── 预加载消息条数 ──

  int getPreloadMessageCount() {
    return _safeRead<int>(
      (box) =>
          (box.get(_preloadMessageCountKey) as int?) ??
          defaultPreloadMessageCount,
      defaultPreloadMessageCount,
    );
  }

  Future<bool> setPreloadMessageCount(int count) async {
    final clampedCount = count.clamp(
      minPreloadMessageCount,
      maxPreloadMessageCount,
    );
    return await _safeWrite(
      (box) => box.put(_preloadMessageCountKey, clampedCount),
    );
  }

  // ── 预加载会话ID ──

  String? getPreloadConversationId() {
    return _safeRead<String?>(
      (box) => box.get(_preloadConversationIdKey) as String?,
      null,
    );
  }

  Future<bool> setPreloadConversationId(String? id) async {
    if (id == null || id.isEmpty) {
      return await _safeWrite((box) => box.delete(_preloadConversationIdKey));
    }
    return await _safeWrite((box) => box.put(_preloadConversationIdKey, id));
  }

  // ── 加载状态（用于启动动画）──

  bool isLoading() {
    return _safeRead<bool>(
      (box) => (box.get(_isLoadingKey) as bool?) ?? false,
      false,
    );
  }

  Future<bool> setLoading(bool loading) async {
    return await _safeWrite((box) => box.put(_isLoadingKey, loading));
  }

  // ── 输入框草稿持久化 ──

  String getDraftInputText() {
    return _safeRead<String>(
      (box) => (box.get(_draftInputTextKey) as String?) ?? '',
      '',
    );
  }

  Future<bool> setDraftInputText(String text) async {
    if (text.isEmpty) {
      return await _safeWrite((box) async {
        await box.delete(_draftInputTextKey);
        return true;
      });
    }
    return await _safeWrite((box) => box.put(_draftInputTextKey, text));
  }

  /// 关闭
  Future<void> close() async {
    if (_box != null && _box!.isOpen) {
      try {
        await _box!.close();
      } catch (e) {
        debugPrint('SettingsService 关闭 Box 失败: $e');
      }
    }
    _box = null;
    _initialized = false;
  }
}
