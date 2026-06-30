import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../secure_storage_service.dart';

/// OCR 密钥配置仓库（Facade 模式阶段 1）
///
/// 做什么：把 SettingsService 中 OCR 密钥相关的读写、迁移逻辑抽到独立类。
/// 为什么这样做：SettingsService 是 God Class（1364 行），近百个配置项集中在一个文件。
/// 抽出 OCR 密钥组后，SettingsService 保留同名 getter/setter 作为 Facade 转发，
/// 调用方零改动，出错可立即回退（删除本文件 + 恢复 SettingsService 方法）。
///
/// 设计说明：
/// - 状态仍归 SettingsService 管理（_apiKeyCache、_secureStorage 通过引用共享）
/// - 本类只负责"逻辑分离"，不持有独立状态
/// - 通过回调访问 SettingsService 的 _safeWrite 和 notifyListeners，避免代码重复
class OcrSettingsRepository {
  // ── 依赖（通过构造函数注入）──
  /// 获取 Hive Box 的回调（Box 可能未初始化，故返回 nullable）
  final Box<dynamic>? Function() _boxGetter;

  /// 安全存储服务（单例，与 SettingsService 共享）
  final SecureStorageService _secureStorage;

  /// API Key 缓存（与 SettingsService 共享同一引用，修改会同步反映）
  final Map<String, String?> _apiKeyCache;

  /// 安全写入回调（转发到 SettingsService._safeWrite，含重试机制）
  final Future<bool> Function(
    Future<dynamic> Function(Box<dynamic> box) operation,
  )
  _safeWrite;

  /// 通知监听器回调（转发到 SettingsService.notifyListeners）
  final VoidCallback _notifyListeners;

  /// 本地安全存储初始化标记（独立于 SettingsService，因为本类自己调用 init）
  bool _secureStorageInitialized = false;

  OcrSettingsRepository({
    required Box<dynamic>? Function() boxGetter,
    required SecureStorageService secureStorage,
    required Map<String, String?> apiKeyCache,
    required Future<bool> Function(
      Future<dynamic> Function(Box<dynamic> box) operation,
    )
    safeWrite,
    required VoidCallback notifyListeners,
  }) : _boxGetter = boxGetter,
       _secureStorage = secureStorage,
       _apiKeyCache = apiKeyCache,
       _safeWrite = safeWrite,
       _notifyListeners = notifyListeners;

  // ── OCR 密钥的 Hive 旧 key（迁移用，迁移后这些 key 会被删除）──
  // ignore: avoid_hardcoded_credentials 以下为存储 key 名称，非真实凭证
  static const String _ocrBaiduApiKeyKey = 'ocr_baidu_api_key';
  // ignore: avoid_hardcoded_credentials
  static const String _ocrBaiduSecretKeyKey = 'ocr_baidu_secret_key';
  // ignore: avoid_hardcoded_credentials
  static const String _ocrTencentSecretIdKey = 'ocr_tencent_secret_id';
  // ignore: avoid_hardcoded_credentials
  static const String _ocrTencentSecretKeyKey = 'ocr_tencent_secret_key';
  static const String _ocrAliyunAppCodeKey = 'ocr_aliyun_app_code';

  // ── OCR 密钥的 secure storage serviceId（密钥迁移到安全存储后使用）──
  // 实际存储 key 为 api_key_<serviceId>（由 SecureStorageService 拼接）
  // ignore: avoid_hardcoded_credentials
  static const String _ocrBaiduApiKeyServiceId = 'ocr_baidu_api_key';
  // ignore: avoid_hardcoded_credentials
  static const String _ocrBaiduSecretKeyServiceId = 'ocr_baidu_secret_key';
  // ignore: avoid_hardcoded_credentials
  static const String _ocrTencentSecretIdServiceId = 'ocr_tencent_secret_id';
  // ignore: avoid_hardcoded_credentials
  static const String _ocrTencentSecretKeyServiceId = 'ocr_tencent_secret_key';
  static const String _ocrAliyunAppCodeServiceId = 'ocr_aliyun_app_code';

  // ── OCR 密钥迁移标记（Hive 中存，标记是否已完成 Hive→secure storage 迁移）──
  static const String _ocrKeysMigratedKey = 'ocr_keys_migrated_to_secure';

  // ── 公开方法 ──

  /// 加载所有 OCR 密钥到缓存。
  /// 做什么：启动时调用一次，把 OCR 密钥从 secure storage 读到内存缓存。
  /// 为什么这样做：getter 是同步的，必须先把密钥加载到缓存才能同步返回。
  /// 包含从 Hive 到 secure storage 的一次性迁移：
  /// 旧版本密钥存在 Hive（明文），这里读到后写入 secure storage 并删除 Hive 旧值。
  Future<void> loadOcrKeys() async {
    final box = _boxGetter();
    final migrated =
        box?.get(_ocrKeysMigratedKey, defaultValue: false) ?? false;

    if (!migrated) {
      await _migrateOcrKeysFromHive();
      await _safeWrite((b) => b.put(_ocrKeysMigratedKey, true));
    }

    _apiKeyCache[_ocrBaiduApiKeyServiceId] = await _getApiKeyFromSecureStorage(
      _ocrBaiduApiKeyServiceId,
    );
    _apiKeyCache[_ocrBaiduSecretKeyServiceId] =
        await _getApiKeyFromSecureStorage(_ocrBaiduSecretKeyServiceId);
    _apiKeyCache[_ocrTencentSecretIdServiceId] =
        await _getApiKeyFromSecureStorage(_ocrTencentSecretIdServiceId);
    _apiKeyCache[_ocrTencentSecretKeyServiceId] =
        await _getApiKeyFromSecureStorage(_ocrTencentSecretKeyServiceId);
    _apiKeyCache[_ocrAliyunAppCodeServiceId] =
        await _getApiKeyFromSecureStorage(_ocrAliyunAppCodeServiceId);
  }

  /// 一次性迁移：把 Hive 中的 OCR 密钥旧值迁移到 secure storage，然后删除 Hive 旧值。
  /// 做什么：读取 Hive 中的明文密钥，写入 secure storage，再删除 Hive 旧值。
  /// 为什么这样做：升级后用户的已有配置不会丢失，且明文不再留在 Hive（修复安全问题 #11）。
  Future<void> _migrateOcrKeysFromHive() async {
    final box = _boxGetter();
    final baiduApi =
        (box?.get(_ocrBaiduApiKeyKey, defaultValue: '') as String?) ?? '';
    final baiduSecret =
        (box?.get(_ocrBaiduSecretKeyKey, defaultValue: '') as String?) ?? '';
    final tencentId =
        (box?.get(_ocrTencentSecretIdKey, defaultValue: '') as String?) ?? '';
    final tencentSecret =
        (box?.get(_ocrTencentSecretKeyKey, defaultValue: '') as String?) ?? '';
    final aliyunCode =
        (box?.get(_ocrAliyunAppCodeKey, defaultValue: '') as String?) ?? '';

    if (baiduApi.isNotEmpty) {
      await _setOcrKeyToSecureStorage(_ocrBaiduApiKeyServiceId, baiduApi);
    }
    if (baiduSecret.isNotEmpty) {
      await _setOcrKeyToSecureStorage(_ocrBaiduSecretKeyServiceId, baiduSecret);
    }
    if (tencentId.isNotEmpty) {
      await _setOcrKeyToSecureStorage(_ocrTencentSecretIdServiceId, tencentId);
    }
    if (tencentSecret.isNotEmpty) {
      await _setOcrKeyToSecureStorage(
        _ocrTencentSecretKeyServiceId,
        tencentSecret,
      );
    }
    if (aliyunCode.isNotEmpty) {
      await _setOcrKeyToSecureStorage(_ocrAliyunAppCodeServiceId, aliyunCode);
    }

    // 删除 Hive 中的明文旧值
    await _safeWrite((b) async {
      await b.delete(_ocrBaiduApiKeyKey);
      await b.delete(_ocrBaiduSecretKeyKey);
      await b.delete(_ocrTencentSecretIdKey);
      await b.delete(_ocrTencentSecretKeyKey);
      await b.delete(_ocrAliyunAppCodeKey);
    });
  }

  /// 写入单个 OCR 密钥到 secure storage。
  /// 做什么：空值时删除（用户清空配置），非空时写入。
  /// 为什么这样做：保证清空配置时 secure storage 中不留残余数据。
  Future<bool> _setOcrKeyToSecureStorage(String serviceId, String value) async {
    if (!_secureStorageInitialized) {
      await _secureStorage.init();
      _secureStorageInitialized = true;
    }
    try {
      if (value.isEmpty) {
        await _secureStorage.deleteApiKey(serviceId);
        return true;
      }
      return await _secureStorage.setApiKey(serviceId, value);
    } catch (e) {
      debugPrint('保存 OCR 密钥失败: $serviceId, $e');
      return false;
    }
  }

  /// 从 secure storage 读取单个密钥（异步）。
  /// 做什么：读取前确保 secure storage 已初始化。
  /// 为什么这样做：避免未初始化时读取失败。
  Future<String?> _getApiKeyFromSecureStorage(String serviceId) async {
    if (!_secureStorageInitialized) {
      debugPrint('安全存储未初始化，尝试同步读取 OCR 密钥: $serviceId');
      await _secureStorage.init();
      _secureStorageInitialized = true;
    }

    try {
      return await _secureStorage.getApiKey(serviceId);
    } catch (e) {
      debugPrint('读取 OCR 密钥失败: $serviceId, $e');
      return null;
    }
  }

  // ── 5 个 OCR 密钥的 getter/setter ──
  //
  // getter 同步从 _apiKeyCache 读取（启动时 loadOcrKeys 已加载）。
  // setter 异步写入 secure storage 并更新缓存，成功后通知监听器。

  String getOcrBaiduApiKey() {
    return _apiKeyCache[_ocrBaiduApiKeyServiceId] ?? '';
  }

  Future<bool> setOcrBaiduApiKey(String key) async {
    final ok = await _setOcrKeyToSecureStorage(_ocrBaiduApiKeyServiceId, key);
    if (ok) {
      _apiKeyCache[_ocrBaiduApiKeyServiceId] = key;
      _notifyListeners();
    }
    return ok;
  }

  String getOcrBaiduSecretKey() {
    return _apiKeyCache[_ocrBaiduSecretKeyServiceId] ?? '';
  }

  Future<bool> setOcrBaiduSecretKey(String key) async {
    final ok = await _setOcrKeyToSecureStorage(
      _ocrBaiduSecretKeyServiceId,
      key,
    );
    if (ok) {
      _apiKeyCache[_ocrBaiduSecretKeyServiceId] = key;
      _notifyListeners();
    }
    return ok;
  }

  String getOcrTencentSecretId() {
    return _apiKeyCache[_ocrTencentSecretIdServiceId] ?? '';
  }

  Future<bool> setOcrTencentSecretId(String id) async {
    final ok = await _setOcrKeyToSecureStorage(
      _ocrTencentSecretIdServiceId,
      id,
    );
    if (ok) {
      _apiKeyCache[_ocrTencentSecretIdServiceId] = id;
      _notifyListeners();
    }
    return ok;
  }

  String getOcrTencentSecretKey() {
    return _apiKeyCache[_ocrTencentSecretKeyServiceId] ?? '';
  }

  Future<bool> setOcrTencentSecretKey(String key) async {
    final ok = await _setOcrKeyToSecureStorage(
      _ocrTencentSecretKeyServiceId,
      key,
    );
    if (ok) {
      _apiKeyCache[_ocrTencentSecretKeyServiceId] = key;
      _notifyListeners();
    }
    return ok;
  }

  String getOcrAliyunAppCode() {
    return _apiKeyCache[_ocrAliyunAppCodeServiceId] ?? '';
  }

  Future<bool> setOcrAliyunAppCode(String code) async {
    final ok = await _setOcrKeyToSecureStorage(
      _ocrAliyunAppCodeServiceId,
      code,
    );
    if (ok) {
      _apiKeyCache[_ocrAliyunAppCodeServiceId] = code;
      _notifyListeners();
    }
    return ok;
  }
}
