/// Agent 动作类型枚举
///
/// 为什么这样做：用枚举集中定义所有动作类型，便于：
/// 1. 工具注册表按类型分发
/// 2. 安全守卫按类型分级
/// 3. LLM function calling 定义生成
enum AgentActionType {
  tap('tap'),
  doubleTap('doubleTap'),
  longPress('longPress'),
  swipe('swipe'),
  inputText('inputText'),
  clearInput('clearInput'),
  pressBack('pressBack'),
  pressHome('pressHome'),
  pressRecents('pressRecents'),
  launchApp('launchApp'),
  getForegroundApp('getForegroundApp'),
  readNotifications('readNotifications'),
  done('done'),
  failed('failed'),
  askUser('askUser');

  final String wireName;
  const AgentActionType(this.wireName);

  /// 从原生/LLM 返回的字符串解析为枚举
  /// 为什么这样做：容错解析，未知动作返回 null 由调用方处理
  static AgentActionType? fromWire(String? name) {
    if (name == null) return null;
    for (final v in AgentActionType.values) {
      if (v.wireName == name) return v;
    }
    return null;
  }
}

/// Agent 决策（LLM 输出解析后的结构）
///
/// 为什么单独成类：LLM 输出是 JSON，解析为强类型对象后，
/// 安全守卫和工具注册表才能基于类型做判断，避免到处解析 Map。
class AgentDecision {
  /// LLM 的思考过程（展示给用户，便于理解 AI 为什么这样做）
  final String thought;

  /// 要执行的动作类型
  final AgentActionType action;

  /// 动作参数（如 tap 的 x/y，inputText 的 text）
  /// 为什么用 Map：不同动作参数不同，统一用 Map 便于序列化
  final Map<String, dynamic> args;

  /// 任务总结（仅 done/failed 时有值）
  final String? summary;

  const AgentDecision({
    required this.thought,
    required this.action,
    required this.args,
    this.summary,
  });

  /// 从 LLM 返回的 JSON 解析
  /// 为什么这样做：LLM 输出不稳定，必须容错解析
  factory AgentDecision.fromJson(Map<String, dynamic> json) {
    final actionType =
        AgentActionType.fromWire(json['action'] as String?) ??
        AgentActionType.failed;
    return AgentDecision(
      thought: (json['thought'] as String?) ?? '',
      action: actionType,
      args: (json['args'] as Map<String, dynamic>?) ?? {},
      summary: json['summary'] as String?,
    );
  }

  /// 动作签名（用于循环检测）
  /// 为什么这样做：连续相同签名表示重复操作，需自动停止
  String get signature => '${action.wireName}:${args.hashCode}';
}
