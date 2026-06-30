import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../secure_storage_service.dart';

/// AI 配置仓库（Facade 模式阶段 2：AI 子域）
///
/// 做什么：把 SettingsService 中 AI 相关的配置（API Key、模型、参数、自定义模型、
/// 语义评分服务）抽到独立类。
/// 为什么这样做：SettingsService 是 God Class，AI 子域是最大的一组（~40 个方法），
/// 抽出后 SettingsService 保留同名 getter/setter 作为 Facade 转发，调用方零改动。
///
/// 设计说明（与 OcrSettingsRepository 一致）：
/// - 状态仍归 SettingsService 管理（_apiKeyCache、_secureStorage 通过引用共享）
/// - 本类只负责"逻辑分离"，不持有独立状态
/// - 通过回调访问 SettingsService 的 _safeWrite/_safeRead 和 notifyListeners
class AiSettingsRepository {
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

  /// 安全存储初始化标记（独立于 SettingsService，因为本类自己调用 init）
  bool _secureStorageInitialized = false;

  AiSettingsRepository({
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
  static const String _modelKey = 'model';
  static const String _aiServiceIdKey = 'ai_service_id';
  static const String _loadAllOnStartKey = 'load_all_on_start';
  static const String _customModelBaseUrlKey = 'custom_model_base_url';
  static const String _customModelNameKey = 'custom_model_name';
  static const String _customModelsListKey = 'custom_models_list';
  static const String _aiAutoTitleEnabledKey = 'ai_auto_title_enabled';
  static const String _temperatureKey = 'ai_temperature';
  static const String _maxTokensKey = 'ai_max_tokens';
  static const String _topPKey = 'ai_top_p';
  static const String _frequencyPenaltyKey = 'ai_frequency_penalty';
  static const String _presencePenaltyKey = 'ai_presence_penalty';
  static const String _memoryScorerServiceIdKey = 'memory_scorer_service_id';
  static const String _memoryScorerModelKey = 'memory_scorer_model';

  // ── 默认值（与 SettingsService 保持一致）──
  static const String defaultModel = 'deepseek-chat';
  static const String defaultAiServiceId = 'doubao';

  // ── API Key (使用安全存储) ──

  /// 获取当前服务的 API Key（从缓存同步读取）
  String? getApiKey() {
    final serviceId = getAiServiceId();
    return _apiKeyCache[serviceId];
  }

  /// 异步加载 API Key 到缓存
  Future<String?> loadApiKey() async {
    final serviceId = getAiServiceId();
    final key = await getApiKeyFromSecureStorage(serviceId);
    _apiKeyCache[serviceId] = key;
    return key;
  }

  /// 设置当前服务的 API Key（保存到安全存储并更新缓存）
  Future<bool> setApiKey(String apiKey) async {
    final serviceId = getAiServiceId();
    final ok = await _setApiKeyToSecureStorage(serviceId, apiKey);
    if (ok) {
      _apiKeyCache[serviceId] = apiKey;
    }
    return ok;
  }

  bool hasApiKey() {
    final key = getApiKey();
    return key != null && key.isNotEmpty;
  }

  Future<void> clearApiKey() async {
    final serviceId = getAiServiceId();
    await _secureStorage.deleteApiKey(serviceId);
    _apiKeyCache.remove(serviceId);
    _notifyListeners();
  }

  // ── 多 AI 服务 API Key ──

  String? getApiKeyForService(String serviceId) {
    return _apiKeyCache[serviceId];
  }

  Future<String?> loadApiKeyForService(String serviceId) async {
    final key = await getApiKeyFromSecureStorage(serviceId);
    _apiKeyCache[serviceId] = key;
    return key;
  }

  Future<bool> setApiKeyForService(String serviceId, String apiKey) async {
    final ok = await _setApiKeyToSecureStorage(serviceId, apiKey);
    if (ok) {
      _apiKeyCache[serviceId] = apiKey;
      _notifyListeners();
    }
    return ok;
  }

  // ── 安全存储内部方法 ──

  /// 从安全存储异步读取 API Key（公开方法，供 SettingsService.init 预加载用）
  /// 为什么公开：SettingsService.init() 启动时需预加载当前服务的 API Key 到缓存，
  /// 此方法封装了 secure storage 初始化 + 读取 + 错误处理的逻辑。
  Future<String?> getApiKeyFromSecureStorage(String serviceId) async {
    if (!_secureStorageInitialized) {
      debugPrint('安全存储未初始化，尝试同步读取 API Key: $serviceId');
      await _secureStorage.init();
      _secureStorageInitialized = true;
    }
    try {
      return await _secureStorage.getApiKey(serviceId);
    } catch (e) {
      debugPrint('读取 API Key 失败: $serviceId, $e');
      return null;
    }
  }

  Future<bool> _setApiKeyToSecureStorage(
    String serviceId,
    String apiKey,
  ) async {
    if (!_secureStorageInitialized) {
      debugPrint('安全存储未初始化，尝试写入 API Key: $serviceId');
      await _secureStorage.init();
      _secureStorageInitialized = true;
    }
    final success = await _secureStorage.setApiKey(serviceId, apiKey);
    if (success) _notifyListeners();
    return success;
  }

  // ── Model ──

  String getModel() {
    return _safeRead<String>(
      (box) => (box.get(_modelKey) as String?) ?? defaultModel,
      defaultModel,
    );
  }

  Future<void> setModel(String model) async {
    await _safeWrite((box) => box.put(_modelKey, model));
  }

  // 别名方法，与 settings_dialog.dart 配合使用
  String getModelId() => getModel();
  Future<void> setModelId(String modelId) async => await setModel(modelId);

  double getTemperature() {
    return _safeRead<double>(
      (box) => (box.get(_temperatureKey) as num?)?.toDouble() ?? 0.7,
      0.7,
    );
  }

  Future<void> setTemperature(double value) async {
    await _safeWrite((box) => box.put(_temperatureKey, value.clamp(0, 2)));
  }

  int getMaxTokens() {
    return _safeRead<int>(
      (box) => (box.get(_maxTokensKey) as int?) ?? 4096,
      4096,
    );
  }

  Future<void> setMaxTokens(int value) async {
    await _safeWrite((box) => box.put(_maxTokensKey, value.clamp(1, 1048576)));
  }

  double getTopP() {
    return _safeRead<double>(
      (box) => (box.get(_topPKey) as num?)?.toDouble() ?? 1.0,
      1.0,
    );
  }

  Future<void> setTopP(double value) async {
    await _safeWrite((box) => box.put(_topPKey, value.clamp(0, 1)));
  }

  double getFrequencyPenalty() {
    return _safeRead<double>(
      (box) => (box.get(_frequencyPenaltyKey) as num?)?.toDouble() ?? 0,
      0,
    );
  }

  Future<void> setFrequencyPenalty(double value) async {
    await _safeWrite(
      (box) => box.put(_frequencyPenaltyKey, value.clamp(-2, 2)),
    );
  }

  double getPresencePenalty() {
    return _safeRead<double>(
      (box) => (box.get(_presencePenaltyKey) as num?)?.toDouble() ?? 0,
      0,
    );
  }

  Future<void> setPresencePenalty(double value) async {
    await _safeWrite((box) => box.put(_presencePenaltyKey, value.clamp(-2, 2)));
  }

  // ── AI Service Selection ──

  String getAiServiceId() {
    return _safeRead<String>(
      (box) => (box.get(_aiServiceIdKey) as String?) ?? defaultAiServiceId,
      defaultAiServiceId,
    );
  }

  Future<bool> setAiServiceId(String serviceId) async {
    return await _safeWrite((box) => box.put(_aiServiceIdKey, serviceId));
  }

  // ── Load All Conversations on Start ──

  bool isLoadAllOnStart() {
    return _safeRead<bool>(
      (box) => (box.get(_loadAllOnStartKey) as bool?) ?? false,
      false,
    );
  }

  Future<void> setLoadAllOnStart(bool enabled) async {
    await _safeWrite((box) => box.put(_loadAllOnStartKey, enabled));
  }

  // ── 自定义模型设置 ──

  String getCustomModelBaseUrl() {
    return _safeRead<String>(
      (box) => (box.get(_customModelBaseUrlKey) as String?) ?? '',
      '',
    );
  }

  Future<bool> setCustomModelBaseUrl(String baseUrl) async {
    return await _safeWrite((box) => box.put(_customModelBaseUrlKey, baseUrl));
  }

  String getCustomModelName() {
    return _safeRead<String>(
      (box) => (box.get(_customModelNameKey) as String?) ?? '',
      '',
    );
  }

  Future<bool> setCustomModelName(String modelName) async {
    return await _safeWrite((box) => box.put(_customModelNameKey, modelName));
  }

  // ── 多自定义模型列表 ──

  List<CustomModelConfig> getCustomModels() {
    final jsonStr = _safeRead<String>(
      (box) => (box.get(_customModelsListKey) as String?) ?? '',
      '',
    );
    if (jsonStr.isEmpty) return [];
    try {
      final list = jsonDecode(jsonStr) as List<dynamic>;
      return list
          .map((e) => CustomModelConfig.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<bool> setCustomModels(List<CustomModelConfig> models) async {
    final jsonStr = jsonEncode(models.map((m) => m.toJson()).toList());
    return await _safeWrite((box) => box.put(_customModelsListKey, jsonStr));
  }

  Future<bool> addCustomModel(CustomModelConfig model) async {
    final models = getCustomModels();
    models.removeWhere((m) => m.name == model.name);
    models.add(model);
    return await setCustomModels(models);
  }

  Future<bool> removeCustomModel(String name) async {
    final models = getCustomModels();
    models.removeWhere((m) => m.name == name);
    return await setCustomModels(models);
  }

  // ── 按服务商存储的自定义模型 ID 列表 ──

  List<String> getCustomModelIdsForService(String serviceId) {
    final key = 'custom_model_ids_$serviceId';
    final jsonStr = _safeRead<String>(
      (box) => (box.get(key) as String?) ?? '',
      '',
    );
    if (jsonStr.isEmpty) return [];
    try {
      final list = jsonDecode(jsonStr) as List<dynamic>;
      return list.map((e) => e as String).toList();
    } catch (_) {
      return [];
    }
  }

  Future<bool> addCustomModelIdForService(
    String serviceId,
    String modelId,
  ) async {
    final ids = getCustomModelIdsForService(serviceId);
    if (ids.contains(modelId)) return true;
    ids.add(modelId);
    final key = 'custom_model_ids_$serviceId';
    final jsonStr = jsonEncode(ids);
    return await _safeWrite((box) => box.put(key, jsonStr));
  }

  Future<bool> removeCustomModelIdForService(
    String serviceId,
    String modelId,
  ) async {
    final ids = getCustomModelIdsForService(serviceId);
    ids.removeWhere((id) => id == modelId);
    final key = 'custom_model_ids_$serviceId';
    final jsonStr = jsonEncode(ids);
    return await _safeWrite((box) => box.put(key, jsonStr));
  }

  // ── AI 自动命名会话 ──

  bool isAiAutoTitleEnabled() {
    return _safeRead<bool>(
      (box) => (box.get(_aiAutoTitleEnabledKey) as bool?) ?? true,
      true,
    );
  }

  Future<bool> setAiAutoTitleEnabled(bool enabled) async {
    return await _safeWrite((box) => box.put(_aiAutoTitleEnabledKey, enabled));
  }

  // ── 记忆语义评分配置 ──
  //
  // 做什么：MemU 记忆系统的语义评分服务复用任意已配置的 AI 服务商。
  // 为什么这样做：用户可能未配置豆包但配置了 DeepSeek/通义等，
  // 应允许复用任意已配置厂商做语义评分，避免完全 fallback 到正则。

  /// 语义评分服务商 ID（如 'doubao'、'deepseek'），留空时默认 'doubao'
  String getMemoryScorerServiceId() {
    final v = _safeRead<String>(
      (box) => (box.get(_memoryScorerServiceIdKey) as String?) ?? '',
      '',
    );
    return v.isEmpty ? 'doubao' : v;
  }

  Future<bool> setMemoryScorerServiceId(String serviceId) async {
    return await _safeWrite(
      (box) => box.put(_memoryScorerServiceIdKey, serviceId),
    );
  }

  /// 语义评分模型名（如 'ep-20241211143509-qn4v7'、'deepseek-chat'）
  String getMemoryScorerModel() {
    return _safeRead<String>(
      (box) => (box.get(_memoryScorerModelKey) as String?) ?? '',
      '',
    );
  }

  Future<bool> setMemoryScorerModel(String model) async {
    return await _safeWrite((box) => box.put(_memoryScorerModelKey, model));
  }
}

/// 自定义模型配置
/// 用于在 model_selector_sheet 和 ai_service_page 之间同步自定义模型数据
class CustomModelConfig {
  final String name;
  final String baseUrl;

  const CustomModelConfig({required this.name, required this.baseUrl});

  Map<String, dynamic> toJson() => {'name': name, 'baseUrl': baseUrl};

  factory CustomModelConfig.fromJson(Map<String, dynamic> json) {
    return CustomModelConfig(
      name: (json['name'] as String?) ?? '',
      baseUrl: (json['baseUrl'] as String?) ?? '',
    );
  }
}
