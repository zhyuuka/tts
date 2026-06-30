import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../secure_storage_service.dart';

/// 搜索配置仓库（Facade 模式阶段 2：搜索子域）
///
/// 做什么：把 SettingsService 中联网搜索相关的配置（开关、引擎、API Key、
/// Google Cx、SearXNG 地址、隐私提示）抽到独立类。
/// 为什么这样做：SettingsService 是 God Class，搜索子域有 8 个方法 + 6 个常量键，
/// 抽出后 SettingsService 保留同名 getter/setter 作为 Facade 转发，调用方零改动。
class SearchSettingsRepository {
  // ── 依赖（通过构造函数注入）──
  final SecureStorageService _secureStorage;
  final Map<String, String?> _apiKeyCache;
  final Future<bool> Function(
    Future<dynamic> Function(Box<dynamic> box) operation,
  )
  _safeWrite;
  final T Function<T>(T Function(Box<dynamic> box) operation, T defaultValue)
  _safeRead;
  final VoidCallback _notifyListeners;

  /// 安全存储初始化标记
  bool _secureStorageInitialized = false;

  SearchSettingsRepository({
    required SecureStorageService secureStorage,
    required Map<String, String?> apiKeyCache,
    required Future<bool> Function(
      Future<dynamic> Function(Box<dynamic> box) operation,
    )
    safeWrite,
    required T Function<T>(
      T Function(Box<dynamic> box) operation,
      T defaultValue,
    )
    safeRead,
    required VoidCallback notifyListeners,
  }) : _secureStorage = secureStorage,
       _apiKeyCache = apiKeyCache,
       _safeWrite = safeWrite,
       _safeRead = safeRead,
       _notifyListeners = notifyListeners;

  // ── 常量键 ──
  static const String _searchEnabledKey = 'search_enabled';
  static const String _searchEngineKey = 'search_engine';
  static const String _searchApiKeyKey = 'search_api_key';
  static const String _googleCxKey = 'google_search_engine_id';
  static const String _searxngUrlKey = 'searxng_instance_url';
  static const String _searchPrivacyShownKey = 'search_privacy_shown';

  // ── 默认值 ──
  static const String defaultSearchEngine = 'duckduckgo';

  // ── 联网搜索 ──

  bool isSearchEnabled() {
    return _safeRead<bool>(
      (box) => (box.get(_searchEnabledKey) as bool?) ?? true,
      true,
    );
  }

  Future<void> setSearchEnabled(bool enabled) async {
    await _safeWrite((box) => box.put(_searchEnabledKey, enabled));
  }

  String getSearchEngine() {
    return _safeRead<String>(
      (box) => (box.get(_searchEngineKey) as String?) ?? defaultSearchEngine,
      defaultSearchEngine,
    );
  }

  Future<void> setSearchEngine(String engineId) async {
    await _safeWrite((box) => box.put(_searchEngineKey, engineId));
  }

  // 别名方法，与 settings_dialog.dart 配合使用
  String getSearchEngineId() => getSearchEngine();
  Future<void> setSearchEngineId(String engineId) async =>
      await setSearchEngine(engineId);

  /// 搜索引擎 API Key（Bing 和 Google 共用此字段）
  ///
  /// 为什么改用 SecureStorage：搜索引擎 API Key 是敏感信息，
  /// 原先明文存在 Hive 中可被导出读取，与其他 API Key 安全标准不一致。
  /// 现统一使用 flutter_secure_storage 硬件加密存储。
  String getSearchApiKey() {
    return _apiKeyCache['search_api_key'] ?? '';
  }

  /// 异步加载搜索引擎 API Key 到缓存（启动时调用）
  /// 做什么：从 SecureStorage 读取 search API Key 并写入 _apiKeyCache。
  /// 为什么这样做：getSearchApiKey 是同步方法供 UI 使用，
  /// SecureStorage 是异步的，需在启动时预加载到缓存。
  /// 迁移逻辑：如果 SecureStorage 没有但 Hive 有旧值，自动迁移并删除旧值。
  Future<void> loadSearchApiKey() async {
    try {
      final key = await _getApiKeyFromSecureStorage('search_api_key');
      if (key != null && key.isNotEmpty) {
        _apiKeyCache['search_api_key'] = key;
        return;
      }

      // 迁移：SecureStorage 没有，检查 Hive 是否有旧值
      final legacyKey = _safeRead<String>(
        (box) => (box.get(_searchApiKeyKey) as String?) ?? '',
        '',
      );
      if (legacyKey.isNotEmpty) {
        final ok = await _setApiKeyToSecureStorage('search_api_key', legacyKey);
        if (ok) {
          _apiKeyCache['search_api_key'] = legacyKey;
          await _safeWrite((box) => box.delete(_searchApiKeyKey));
          debugPrint('SearchSettingsRepository: 搜索引擎 API Key 已从 Hive 迁移到安全存储');
        }
      }
    } catch (e) {
      debugPrint('SearchSettingsRepository: 加载搜索引擎 API Key 失败: $e');
    }
  }

  Future<void> setSearchApiKey(String key) async {
    final ok = await _setApiKeyToSecureStorage('search_api_key', key);
    if (ok) {
      _apiKeyCache['search_api_key'] = key;
      _notifyListeners();
    }
  }

  String getGoogleSearchEngineId() {
    return _safeRead<String>(
      (box) => (box.get(_googleCxKey) as String?) ?? '',
      '',
    );
  }

  Future<void> setGoogleSearchEngineId(String cx) async {
    await _safeWrite((box) => box.put(_googleCxKey, cx));
  }

  String getSearXngUrl() {
    return _safeRead<String>(
      (box) => (box.get(_searxngUrlKey) as String?) ?? '',
      '',
    );
  }

  Future<void> setSearXngUrl(String url) async {
    await _safeWrite((box) => box.put(_searxngUrlKey, url));
  }

  // ── 搜索隐私提示状态 ──

  bool isSearchPrivacyShown() {
    return _safeRead<bool>(
      (box) => (box.get(_searchPrivacyShownKey) as bool?) ?? false,
      false,
    );
  }

  Future<bool> setSearchPrivacyShown(bool shown) async {
    return await _safeWrite((box) => box.put(_searchPrivacyShownKey, shown));
  }

  // ── 安全存储内部方法 ──

  Future<String?> _getApiKeyFromSecureStorage(String serviceId) async {
    if (!_secureStorageInitialized) {
      await _secureStorage.init();
      _secureStorageInitialized = true;
    }
    try {
      return await _secureStorage.getApiKey(serviceId);
    } catch (e) {
      debugPrint('读取搜索 API Key 失败: $serviceId, $e');
      return null;
    }
  }

  Future<bool> _setApiKeyToSecureStorage(
    String serviceId,
    String apiKey,
  ) async {
    if (!_secureStorageInitialized) {
      await _secureStorage.init();
      _secureStorageInitialized = true;
    }
    final success = await _secureStorage.setApiKey(serviceId, apiKey);
    if (success) _notifyListeners();
    return success;
  }
}
