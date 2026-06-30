import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../core/logger/app_logger.dart';

/// 安全存储服务 - 用于存储 API Key 等敏感信息
///
/// 使用 flutter_secure_storage 实现：
/// - iOS: Keychain
/// - Android: Keystore / EncryptedSharedPreferences
/// - Linux: libsecret
/// - macOS: Keychain
/// - Windows: DPAPI
///
/// 特性：
/// - 硬件级加密（设备绑定）
/// - 自动解锁（用户无需输入密码）
/// - 应用卸载后数据自动清除
/// - 注意：备份/恢复时需要重新配置 API Key
class SecureStorageService {
  static final SecureStorageService _instance =
      SecureStorageService._internal();
  static SecureStorageService get instance => _instance;
  factory SecureStorageService() => _instance;
  SecureStorageService._internal();

  final FlutterSecureStorage _storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  bool _initialized = false;

  /// 初始化安全存储（检查是否可用）
  Future<bool> init() async {
    if (_initialized) return true;

    try {
      // 测试读写
      await _storage.write(key: '_test_key', value: 'test');
      final value = await _storage.read(key: '_test_key');
      if (value == 'test') {
        await _storage.delete(key: '_test_key');
        _initialized = true;
        AppLogger.i('安全存储初始化成功 (使用硬件加密)');
        return true;
      }
      return false;
    } catch (e) {
      AppLogger.e('安全存储初始化失败', e);
      return false;
    }
  }

  /// 检查是否已初始化
  bool get isInitialized => _initialized;

  // ── API Key 操作 ──

  /// 获取指定服务的 API Key
  ///
  /// [serviceId] - 服务标识符，如 'deepseek', 'gemini' 等
  Future<String?> getApiKey(String serviceId) async {
    if (!_initialized) {
      AppLogger.w('安全存储未初始化，尝试读取 API Key: $serviceId');
      await init();
    }

    try {
      final key = _buildApiKeyKey(serviceId);
      final value = await _storage.read(key: key);

      if (value != null && value.isNotEmpty) {
        AppLogger.d('读取 API Key 成功: $serviceId (长度: ${_maskValue(value)})');
      } else {
        AppLogger.d('API Key 未找到: $serviceId');
      }

      return value;
    } catch (e) {
      AppLogger.e('读取 API Key 失败: $serviceId', e);
      return null;
    }
  }

  /// 设置指定服务的 API Key
  ///
  /// [serviceId] - 服务标识符
  /// [apiKey] - API Key 值（不应为空）
  Future<bool> setApiKey(String serviceId, String apiKey) async {
    if (!_initialized) {
      await init();
    }

    if (apiKey.isEmpty) {
      AppLogger.w('尝试设置空的 API Key: $serviceId');
      return false;
    }

    try {
      final key = _buildApiKeyKey(serviceId);
      await _storage.write(key: key, value: apiKey);

      AppLogger.i('保存 API Key 成功: $serviceId (长度: ${_maskValue(apiKey)})');
      return true;
    } catch (e) {
      AppLogger.e('保存 API Key 失败: $serviceId', e);
      return false;
    }
  }

  /// 删除指定服务的 API Key
  Future<bool> deleteApiKey(String serviceId) async {
    try {
      final key = _buildApiKeyKey(serviceId);
      await _storage.delete(key: key);

      AppLogger.i('删除 API Key 成功: $serviceId');
      return true;
    } catch (e) {
      AppLogger.e('删除 API Key 失败: $serviceId', e);
      return false;
    }
  }

  /// 检查是否有指定服务的 API Key
  Future<bool> hasApiKey(String serviceId) async {
    final apiKey = await getApiKey(serviceId);
    return apiKey != null && apiKey.isNotEmpty;
  }

  // ── 批量操作 ──

  /// 获取所有已存储的 API Key 的服务 ID 列表
  Future<List<String>> getAllApiKeys() async {
    try {
      final allData = await _storage.readAll();
      final apiKeys = <String>[];

      allData.forEach((key, value) {
        if (key.startsWith('api_key_') && value.isNotEmpty) {
          // 提取服务 ID：api_key_deepseek -> deepseek
          final serviceId = key.substring(8); // 'api_key_'.length == 8
          apiKeys.add(serviceId);
        }
      });

      AppLogger.d('已存储 ${apiKeys.length} 个 API Key: ${apiKeys.join(', ')}');
      return apiKeys;
    } catch (e) {
      AppLogger.e('获取所有 API Key 失败', e);
      return [];
    }
  }

  /// 清除所有 API Key（谨慎使用！）
  Future<bool> clearAllApiKeys() async {
    try {
      final allData = await _storage.readAll();
      final keysToDelete = <String>[];

      allData.forEach((key, _) {
        if (key.startsWith('api_key_')) {
          keysToDelete.add(key);
        }
      });

      for (final key in keysToDelete) {
        await _storage.delete(key: key);
      }

      AppLogger.w('已清除 ${keysToDelete.length} 个 API Key');
      return true;
    } catch (e) {
      AppLogger.e('清除 API Key 失败', e);
      return false;
    }
  }

  // ── 通用键值对操作（可选）──

  /// 读取任意安全值
  Future<String?> read(String key) async {
    if (!_initialized) await init();
    try {
      return await _storage.read(key: key);
    } catch (e) {
      AppLogger.e('读取安全值失败: $key', e);
      return null;
    }
  }

  /// 写入任意安全值
  Future<bool> write(String key, String value) async {
    if (!_initialized) await init();
    try {
      await _storage.write(key: key, value: value);
      return true;
    } catch (e) {
      AppLogger.e('写入安全值失败: $key', e);
      return false;
    }
  }

  /// 删除任意安全值
  Future<bool> delete(String key) async {
    try {
      await _storage.delete(key: key);
      return true;
    } catch (e) {
      AppLogger.e('删除安全值失败: $key', e);
      return false;
    }
  }

  /// 检查是否存在某个键
  Future<bool> containsKey(String key) async {
    if (!_initialized) await init();
    try {
      return await _storage.containsKey(key: key);
    } catch (e) {
      AppLogger.e('检查键存在失败: $key', e);
      return false;
    }
  }

  // ── 辅助方法 ──

  String _buildApiKeyKey(String serviceId) => 'api_key_$serviceId';

  /// 遮蔽敏感信息用于日志输出
  static String _maskValue(String value) {
    if (value.isEmpty) return '(empty)';
    if (value.length <= 8) return '****';
    return '${value.substring(0, 4)}...${value.substring(value.length - 4)}';
  }

  /// 清除所有数据（仅用于测试或重置）
  Future<void> deleteAll() async {
    try {
      await _storage.deleteAll();
      AppLogger.w('已清除所有安全存储数据');
    } catch (e) {
      AppLogger.e('清除安全存储失败', e);
    }
  }
}

/// 扩展方法：便捷的 API Key 访问
extension SecureStorageApiKeys on SecureStorageService {
  Future<String?> get openai => getApiKey('openai');
  Future<bool> setOpenai(String key) => setApiKey('openai', key);

  Future<String?> get deepSeek => getApiKey('deepseek');
  Future<bool> setDeepSeek(String key) => setApiKey('deepseek', key);

  Future<String?> get guiji => getApiKey('guiji');
  Future<bool> setGuiji(String key) => setApiKey('guiji', key);

  Future<String?> get zhipu => getApiKey('zhipu');
  Future<bool> setZhipu(String key) => setApiKey('zhipu', key);

  Future<String?> get moonshot => getApiKey('moonshot');
  Future<bool> setMoonshot(String key) => setApiKey('moonshot', key);

  Future<String?> get gemini => getApiKey('gemini');
  Future<bool> setGemini(String key) => setApiKey('gemini', key);

  Future<String?> get doubao => getApiKey('doubao');
  Future<bool> setDoubao(String key) => setApiKey('doubao', key);

  Future<String?> get tongyi => getApiKey('tongyi');
  Future<bool> setTongyi(String key) => setApiKey('tongyi', key);

  Future<String?> get hunyuan => getApiKey('hunyuan');
  Future<bool> setHunyuan(String key) => setApiKey('hunyuan', key);

  Future<String?> get minimax => getApiKey('minimax');
  Future<bool> setMinimax(String key) => setApiKey('minimax', key);

  Future<String?> get stepfun => getApiKey('stepfun');
  Future<bool> setStepfun(String key) => setApiKey('stepfun', key);

  Future<String?> get baichuan => getApiKey('baichuan');
  Future<bool> setBaichuan(String key) => setApiKey('baichuan', key);

  Future<String?> get spark => getApiKey('spark');
  Future<bool> setSpark(String key) => setApiKey('spark', key);

  Future<String?> get yi => getApiKey('yi');
  Future<bool> setYi(String key) => setApiKey('yi', key);

  Future<String?> get ernie => getApiKey('ernie');
  Future<bool> setErnie(String key) => setApiKey('ernie', key);

  Future<String?> get customModel => getApiKey('custom');
  Future<bool> setCustomModel(String key) => setApiKey('custom', key);

  Future<String?> get huggingface => getApiKey('huggingface');
  Future<bool> setHuggingface(String token) => setApiKey('huggingface', token);

  // ── 云端语音识别 ──

  Future<String?> getCloudSpeechApiKey() async =>
      await getApiKey('cloud_speech');
  Future<bool> setCloudSpeechApiKey(String key) async =>
      await setApiKey('cloud_speech', key);
}
