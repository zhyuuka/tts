import 'dart:convert';

import 'package:hive_flutter/hive_flutter.dart';

/// Agent 配置仓库（Facade 模式阶段 2：Agent 子域）
///
/// 做什么：把 SettingsService 中 Agent 相关配置（视觉 fallback、黑白名单、
/// 银行保护、知情同意）抽到独立类。
/// 为什么这样做：Agent 子域虽然方法不多但逻辑独立，且是新增功能，
/// 抽出后便于后续 Agent 功能扩展时集中修改，不影响其他子域。
class AgentSettingsRepository {
  // ── 依赖（通过构造函数注入）──
  final Future<bool> Function(
    Future<dynamic> Function(Box<dynamic> box) operation,
  )
  _safeWrite;
  final T Function<T>(T Function(Box<dynamic> box) operation, T defaultValue)
  _safeRead;

  AgentSettingsRepository({
    required Future<bool> Function(
      Future<dynamic> Function(Box<dynamic> box) operation,
    )
    safeWrite,
    required T Function<T>(
      T Function(Box<dynamic> box) operation,
      T defaultValue,
    )
    safeRead,
  }) : _safeWrite = safeWrite,
       _safeRead = safeRead;

  // ── 常量键 ──
  static const String _agentVisionEnabledKey = 'agent_vision_enabled';
  static const String _agentVisionServiceIdKey = 'agent_vision_service_id';
  static const String _agentVisionModelKey = 'agent_vision_model';
  static const String _agentBlacklistKey = 'agent_blacklist';
  static const String _agentWhitelistKey = 'agent_whitelist';
  static const String _agentBankProtectionKey = 'agent_bank_protection';
  static const String _agentConsentAcceptedKey = 'agent_consent_accepted';

  // ── Agent 视觉 fallback 配置 ──
  //
  // 做什么：Agent 无障碍树读不到屏幕时，用视觉模型（VLM）描述截图。
  // 为什么复用现有服务商：用户已配置 gemini/tongyi 等 API Key，
  // 视觉模型与文本模型同属一个账号，无需重复配 Key。

  bool isAgentVisionEnabled() {
    return _safeRead<bool>(
      (box) => (box.get(_agentVisionEnabledKey) as bool?) ?? false,
      false,
    );
  }

  Future<bool> setAgentVisionEnabled(bool enabled) async {
    return await _safeWrite((box) => box.put(_agentVisionEnabledKey, enabled));
  }

  String getAgentVisionServiceId() {
    return _safeRead<String>(
      (box) => (box.get(_agentVisionServiceIdKey) as String?) ?? '',
      '',
    );
  }

  Future<bool> setAgentVisionServiceId(String serviceId) async {
    return await _safeWrite(
      (box) => box.put(_agentVisionServiceIdKey, serviceId),
    );
  }

  /// 视觉模型名（如 'qwen-vl-max'），由用户填写
  String getAgentVisionModel() {
    return _safeRead<String>(
      (box) => (box.get(_agentVisionModelKey) as String?) ?? '',
      '',
    );
  }

  Future<bool> setAgentVisionModel(String model) async {
    return await _safeWrite((box) => box.put(_agentVisionModelKey, model));
  }

  // ── Agent 安全配置（黑白名单）──

  /// 获取用户自定义黑名单（包名列表）
  /// 为什么用 JSON 数组：Set 无法直接存 Hive，序列化为 JSON 字符串
  List<String> getAgentBlacklist() {
    final jsonStr = _safeRead<String>(
      (box) => (box.get(_agentBlacklistKey) as String?) ?? '',
      '',
    );
    if (jsonStr.isEmpty) return const [];
    try {
      return (jsonDecode(jsonStr) as List).cast<String>();
    } catch (_) {
      return const [];
    }
  }

  Future<bool> setAgentBlacklist(List<String> packages) async {
    return await _safeWrite(
      (box) => box.put(_agentBlacklistKey, jsonEncode(packages)),
    );
  }

  /// 获取用户自定义白名单（包名列表）
  List<String> getAgentWhitelist() {
    final jsonStr = _safeRead<String>(
      (box) => (box.get(_agentWhitelistKey) as String?) ?? '',
      '',
    );
    if (jsonStr.isEmpty) return const [];
    try {
      return (jsonDecode(jsonStr) as List).cast<String>();
    } catch (_) {
      return const [];
    }
  }

  Future<bool> setAgentWhitelist(List<String> packages) async {
    return await _safeWrite(
      (box) => box.put(_agentWhitelistKey, jsonEncode(packages)),
    );
  }

  /// 银行 App 保护开关（默认开启）
  bool isAgentBankProtectionEnabled() {
    return _safeRead<bool>(
      (box) => (box.get(_agentBankProtectionKey) as bool?) ?? true,
      true,
    );
  }

  Future<bool> setAgentBankProtectionEnabled(bool enabled) async {
    return await _safeWrite((box) => box.put(_agentBankProtectionKey, enabled));
  }

  // ── Agent 知情同意 ──

  /// 用户是否已同意 Agent 功能须知
  bool isAgentConsentAccepted() {
    return _safeRead<bool>(
      (box) => (box.get(_agentConsentAcceptedKey) as bool?) ?? false,
      false,
    );
  }

  /// 设置知情同意状态
  Future<bool> setAgentConsentAccepted(bool accepted) async {
    return await _safeWrite(
      (box) => box.put(_agentConsentAcceptedKey, accepted),
    );
  }
}
