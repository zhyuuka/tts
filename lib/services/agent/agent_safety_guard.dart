import '../../core/logger/app_logger.dart';
import '../../models/agent/agent_action.dart';
import '../../models/agent/ui_node.dart';
import '../settings_service.dart';

/// 操作风险等级
///
/// 为什么这样做：不同风险等级对应不同处理方式，
/// 高危必须用户确认，极高危需二次确认。
enum AgentRiskLevel {
  /// 极高危：支付/转账/输入密码 → 强制二次确认
  critical,

  /// 高危：删除/发送/发布/系统设置 → 强制确认
  high,

  /// 中危：启动 App/输入文本/点击未知按钮 → 仅记录日志
  medium,

  /// 低危：读屏/截图/返回/Home → 仅记录日志
  low,
}

/// 安全检查结果
class SafetyResult {
  /// 是否允许执行
  final bool allowed;

  /// 是否需要用户确认
  final bool requiresConfirm;

  /// 是否需要二次确认（极高危）
  final bool requiresDoubleConfirm;

  /// 拒绝/确认原因
  final String? reason;

  /// 风险等级
  final AgentRiskLevel riskLevel;

  const SafetyResult({
    required this.allowed,
    this.requiresConfirm = false,
    this.requiresDoubleConfirm = false,
    this.reason,
    this.riskLevel = AgentRiskLevel.low,
  });

  const SafetyResult.allow(AgentRiskLevel level)
    : allowed = true,
      requiresConfirm = false,
      requiresDoubleConfirm = false,
      reason = null,
      riskLevel = level;

  const SafetyResult.confirm(AgentRiskLevel level, this.reason)
    : allowed = true,
      requiresConfirm = true,
      requiresDoubleConfirm = level == AgentRiskLevel.critical,
      riskLevel = level;

  const SafetyResult.reject(this.reason)
    : allowed = false,
      requiresConfirm = false,
      requiresDoubleConfirm = false,
      riskLevel = AgentRiskLevel.critical;
}

/// Agent 安全守卫
///
/// 职责：对所有 Agent 操作进行安全检查，决定是否允许/需确认/拒绝。
/// 为什么单独成类：
/// 1. 安全逻辑集中管理，便于审计和测试
/// 2. 规则可配置（黑白名单、关键词），不硬编码在 AgentService
/// 3. 所有操作必经守卫，无绕过路径
///
/// 安全机制（对应方案第 5 章）：
/// - 操作 4 级风险分级
/// - 高危关键词检测
/// - App 黑白名单
/// - 输入文本敏感词检测
class AgentSafetyGuard {
  AgentSafetyGuard();

  // ── 高危关键词（用于目标预检和动作检查）──

  /// 极高危关键词（支付类）
  static final _criticalPatterns = [
    RegExp(r'支付宝|微信支付|付款|转账|红包|余额宝|银行卡', caseSensitive: false),
    RegExp(r'密码|验证码|支付密码|交易密码', caseSensitive: false),
  ];

  /// 高危关键词（删除/发送/系统类）
  static final _highRiskPatterns = [
    RegExp(r'删除|清空|卸载|格式化|移除', caseSensitive: false),
    RegExp(r'发送|分享|发布|提交|确认订单', caseSensitive: false),
    RegExp(r'设置|权限|开发者选项|USB调试|root', caseSensitive: false),
  ];

  // ── App 黑白名单 ──

  /// 默认黑名单（不可移除）：系统设置、安装器、权限管理
  /// 为什么硬编码：这些 App 操控会导致系统安全问题
  static const _blockedPackages = {
    'com.android.settings',
    'com.android.packageinstaller',
    'com.miui.securitycenter',
    'com.huawei.systemmanager',
    'com.coloros.safecenter',
    'com.iqoo.secure',
  };

  /// 默认银行类 App 黑名单（用户可解锁）
  /// 为什么默认禁止：银行 App 操控风险极高
  static const _bankPackages = {
    'com.icbc', // 工商银行
    'com.chinamworld.main', // 建设银行
    'com.bankcomm.Bankcomm', // 交通银行
    'com.cgbchina.xing', // 广发银行
    'cmb.pb', // 招商银行
    'com.yitong', // 邮储银行
    'cn.com.spdb.mobilebank', // 浦发银行
    'com.bigjpg', // 农业银行
  };

  /// 用户自定义白名单（空表示全部允许，除黑名单外）
  final Set<String> _userWhitelist = {};

  /// 用户自定义黑名单（追加到默认黑名单）
  final Set<String> _userBlacklist = {};

  /// 是否启用银行 App 保护（默认启用）
  bool bankProtectionEnabled = true;

  /// 设置服务引用（用于黑白名单持久化）
  /// 为什么可选：SafetyGuard 可独立于 SettingsService 使用（如单元测试）
  SettingsService? _settings;

  // ── 持久化 ──

  /// 绑定设置服务并从持久化存储加载配置
  ///
  /// 做什么：从 SettingsService 读取黑白名单和银行保护开关，恢复到内存。
  /// 为什么这样做：SafetyGuard 内存状态重启丢失，需从持久化存储恢复。
  /// 为什么在 AgentProvider.init 调用：此时 SettingsService 已初始化。
  Future<void> loadFromSettings(SettingsService settings) async {
    _settings = settings;
    _userBlacklist
      ..clear()
      ..addAll(settings.getAgentBlacklist());
    _userWhitelist
      ..clear()
      ..addAll(settings.getAgentWhitelist());
    bankProtectionEnabled = settings.isAgentBankProtectionEnabled();
  }

  // ── 配置 API ──

  /// 添加用户白名单（自动持久化）
  void addWhitelist(String package) {
    _userWhitelist.add(package);
    _settings?.setAgentWhitelist(_userWhitelist.toList());
  }

  /// 移除用户白名单（自动持久化）
  void removeWhitelist(String package) {
    _userWhitelist.remove(package);
    _settings?.setAgentWhitelist(_userWhitelist.toList());
  }

  /// 添加用户黑名单（自动持久化）
  void addBlacklist(String package) {
    _userBlacklist.add(package);
    _settings?.setAgentBlacklist(_userBlacklist.toList());
  }

  /// 移除用户黑名单（自动持久化）
  void removeBlacklist(String package) {
    _userBlacklist.remove(package);
    _settings?.setAgentBlacklist(_userBlacklist.toList());
  }

  /// 设置银行保护开关（自动持久化）
  Future<void> setBankProtectionEnabled(bool enabled) async {
    bankProtectionEnabled = enabled;
    await _settings?.setAgentBankProtectionEnabled(enabled);
  }

  /// 获取完整黑名单（默认 + 用户 + 银行）
  Set<String> get effectiveBlacklist {
    final set = <String>{..._blockedPackages, ..._userBlacklist};
    if (bankProtectionEnabled) {
      set.addAll(_bankPackages);
    }
    return set;
  }

  /// 用于设置页展示的黑名单（系统默认 + 用户自定义，不含银行黑名单）
  /// 为什么不含银行黑名单：银行黑名单由 bankProtectionEnabled 开关统一控制，
  /// 不应逐个管理，否则用户点删除按钮却删不掉（因包名不在 _userBlacklist 中）
  Set<String> get displayableBlacklist => {
    ..._blockedPackages,
    ..._userBlacklist,
  };

  /// 用户自定义白名单（只读视图）
  /// 为什么公开：设置页需要展示和管理用户白名单
  Set<String> get userWhitelist => Set.unmodifiable(_userWhitelist);

  /// 用户自定义黑名单（只读视图）
  /// 为什么公开：设置页需要展示和管理用户黑名单
  Set<String> get userBlacklist => Set.unmodifiable(_userBlacklist);

  /// 检查包名是否在系统默认黑名单中（不可移除）
  /// 为什么公开：设置页需要区分"系统默认"和"用户添加"的条目
  bool isDefaultBlocked(String package) => _blockedPackages.contains(package);

  // ── 检查 API ──

  /// 目标预检：检查用户输入的任务目标是否允许
  ///
  /// 为什么这样做：在任务开始前拦截明显高危的目标，
  /// 避免执行到一半才发现问题。
  SafetyResult precheckGoal(String goal) {
    // 1. 检查极高危关键词
    for (final pattern in _criticalPatterns) {
      if (pattern.hasMatch(goal)) {
        return SafetyResult.confirm(
          AgentRiskLevel.critical,
          '任务涉及支付/转账/密码等极高危操作，需要二次确认',
        );
      }
    }

    // 2. 检查高危关键词
    for (final pattern in _highRiskPatterns) {
      if (pattern.hasMatch(goal)) {
        return SafetyResult.confirm(
          AgentRiskLevel.high,
          '任务涉及删除/发送/系统设置等高危操作，需要确认',
        );
      }
    }

    return const SafetyResult.allow(AgentRiskLevel.low);
  }

  /// 动作检查：检查每一步操作是否需要确认
  ///
  /// 为什么这样做：即使目标预检通过，具体执行时仍可能遇到高危操作
  /// （如点击了"删除"按钮、在银行 App 内操作）。
  SafetyResult checkAction(AgentDecision decision) {
    switch (decision.action) {
      case AgentActionType.tap:
      case AgentActionType.doubleTap:
      case AgentActionType.longPress:
        // 点击操作：检查目标文本是否高危
        final targetText = (decision.args['targetText'] as String?) ?? '';
        return _checkTargetText(targetText);

      case AgentActionType.inputText:
        // 输入操作：检查文本是否含敏感词
        final text = (decision.args['text'] as String?) ?? '';
        return _checkInputText(text);

      case AgentActionType.launchApp:
        // 启动 App：检查包名是否在黑名单
        final pkg = (decision.args['packageName'] as String?) ?? '';
        return _checkPackage(pkg);

      case AgentActionType.swipe:
      case AgentActionType.clearInput:
      case AgentActionType.pressBack:
      case AgentActionType.pressHome:
      case AgentActionType.pressRecents:
        // 导航操作：低危
        return const SafetyResult.allow(AgentRiskLevel.low);

      case AgentActionType.getForegroundApp:
      case AgentActionType.readNotifications:
        // 只读操作：低危
        return const SafetyResult.allow(AgentRiskLevel.low);

      case AgentActionType.done:
      case AgentActionType.failed:
      case AgentActionType.askUser:
        // 终止/询问：无需检查
        return const SafetyResult.allow(AgentRiskLevel.low);
    }
  }

  /// 检查目标元素文本是否高危
  SafetyResult _checkTargetText(String text) {
    if (text.isEmpty) {
      return const SafetyResult.allow(AgentRiskLevel.medium);
    }
    for (final pattern in _criticalPatterns) {
      if (pattern.hasMatch(text)) {
        return SafetyResult.confirm(
          AgentRiskLevel.critical,
          '即将点击"$text"，涉及极高危操作，需要二次确认',
        );
      }
    }
    for (final pattern in _highRiskPatterns) {
      if (pattern.hasMatch(text)) {
        return SafetyResult.confirm(
          AgentRiskLevel.high,
          '即将点击"$text"，涉及高危操作，需要确认',
        );
      }
    }
    return const SafetyResult.allow(AgentRiskLevel.low);
  }

  /// 检查输入文本是否含敏感词
  SafetyResult _checkInputText(String text) {
    // 密码/验证码检测
    if (_criticalPatterns[1].hasMatch(text)) {
      AppLogger.w('[AgentSafety] 检测到输入文本含密码/验证码关键词');
      // 不拒绝，但标记为高危需确认（用户可能确实需要输入）
      return const SafetyResult.confirm(
        AgentRiskLevel.high,
        '即将输入含敏感信息的文本，需要确认',
      );
    }
    return const SafetyResult.allow(AgentRiskLevel.medium);
  }

  /// 检查 App 包名是否允许操控
  SafetyResult _checkPackage(String package) {
    if (package.isEmpty) {
      return const SafetyResult.reject('包名为空');
    }

    // 黑名单优先级最高
    if (effectiveBlacklist.contains(package)) {
      return SafetyResult.reject('App $package 在黑名单中，禁止操控');
    }

    // 白名单为空表示全部允许；非空时只允许白名单内
    if (_userWhitelist.isNotEmpty && !_userWhitelist.contains(package)) {
      return SafetyResult.reject('App $package 不在白名单中');
    }

    // 银行 App 默认需确认（即使不在黑名单，用户可能解锁了）
    if (bankProtectionEnabled && _bankPackages.contains(package)) {
      return SafetyResult.confirm(
        AgentRiskLevel.critical,
        '即将操控银行类 App，需要二次确认',
      );
    }

    return const SafetyResult.allow(AgentRiskLevel.medium);
  }

  /// 判断输入文本是否需要脱敏（用于日志记录）
  /// 为什么这样做：密码、验证码不应明文写入日志
  bool shouldRedactInputText(String text) {
    if (text.isEmpty) return false;
    return _criticalPatterns[1].hasMatch(text) || text.length <= 6; // 短文本可能是验证码
  }

  /// 脱敏输入文本（用于日志）
  /// 为什么这样做：日志可能被备份/分享，敏感信息必须遮蔽
  String redactForLog(String text) {
    if (!shouldRedactInputText(text)) return text;
    if (text.length <= 2) return '**';
    return '${text[0]}***${text[text.length - 1]}';
  }

  // ── 截图脱敏（上传 VLM 前调用）──

  /// 截图脱敏检查
  ///
  /// 做什么：上传截图到视觉模型前，检查屏幕上是否有密码框/验证码等敏感区域。
  /// 为什么安全失败（拒绝上传）而非模糊处理：
  /// 1. Phase 5 优先安全——宁可不用视觉 fallback 也不能泄露隐私
  /// 2. 模糊处理需引入图像处理依赖，留到 Phase 6 完善
  /// 3. VLM 是云端服务，截图一旦上传无法撤回
  ///
  /// [tree] 当前屏幕的无障碍树（用于检测敏感节点）。
  ///   为 null 时表示无法获取无障碍树，安全失败拒绝上传。
  RedactResult redactScreenshot(UiTree? tree) {
    // 无障碍树不可用 → 无法判断敏感区域 → 安全失败
    if (tree == null) {
      return const RedactResult.reject('无法获取无障碍树，拒绝上传截图');
    }

    // 遍历无障碍树查找敏感节点
    final sensitiveCount = _countSensitiveNodes(tree.roots);
    if (sensitiveCount > 0) {
      return RedactResult.reject('检测到 $sensitiveCount 个敏感区域（密码/验证码），拒绝上传截图');
    }

    // 屏幕尺寸校验（对应方案 5.3 坐标映射一致性）
    // 为什么这样做：截图尺寸与无障碍树 screenSize 不一致时，
    // 坐标映射可能错位，脱敏区域不准确，安全失败
    if (tree.screenWidth <= 0 || tree.screenHeight <= 0) {
      return const RedactResult.reject('屏幕尺寸异常，拒绝上传截图');
    }

    return const RedactResult.allow();
  }

  /// 递归统计无障碍树中的敏感节点数量
  ///
  /// 敏感节点定义（见 UiNode.isSensitive）：
  /// - isPassword=true（密码框）
  /// - 文本含"密码/验证码/token/password"等关键词
  int _countSensitiveNodes(List<UiNode> nodes) {
    var count = 0;
    for (final node in nodes) {
      if (node.visibleToUser && node.isSensitive) {
        count++;
      }
      count += _countSensitiveNodes(node.children);
    }
    return count;
  }
}

/// 截图脱敏检查结果
///
/// 为什么单独定义：脱敏是安全核心逻辑，结果需明确区分"允许上传"和"拒绝"。
/// 为什么放在顶层：Dart 不支持类嵌套定义，RedactResult 需作为顶层类。
class RedactResult {
  /// 是否允许上传截图到 VLM
  final bool allowed;

  /// 拒绝原因（allowed=false 时有值）
  final String? reason;

  const RedactResult.allow() : allowed = true, reason = null;
  const RedactResult.reject(this.reason) : allowed = false;
}
