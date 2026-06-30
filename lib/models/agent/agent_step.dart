import 'agent_action.dart';

/// Agent 执行步骤状态
///
/// 为什么用枚举：步骤状态有限且明确，枚举比字符串更安全。
/// 状态机：idle → running → (awaitingConfirm → running)* → done/error/stopped
enum AgentStepState {
  /// 思考中（LLM 推理）
  think,

  /// 执行动作中
  act,

  /// 等待用户确认（高危操作）
  awaitingConfirm,

  /// 已完成（单步）
  stepDone,

  /// 任务完成
  done,

  /// 任务失败
  error,

  /// 用户停止
  stopped,

  /// 用户拒绝确认
  rejected,

  /// 达到最大步数
  maxStepsReached,
}

/// Agent 执行步骤（一次感知-思考-行动的记录）
///
/// 为什么单独成类：UI 层需要展示每一步的思考过程和动作，
/// 用强类型对象便于 ListView 渲染和日志持久化。
class AgentStep {
  /// 步骤序号（从 0 开始）
  final int index;

  /// 步骤状态
  final AgentStepState state;

  /// LLM 的思考内容（state == think 时有值）
  final String? thought;

  /// 本步的决策（state == act/awaitingConfirm 时有值）
  final AgentDecision? decision;

  /// 动作执行结果（state == stepDone 时有值）
  /// 为什么用 bool：成功/失败足够，错误详情走 error 字段
  final bool? success;

  /// 错误信息（state == error 时有值）
  final String? error;

  /// 任务总结（state == done 时有值）
  final String? summary;

  /// 时间戳
  final DateTime timestamp;

  const AgentStep({
    required this.index,
    required this.state,
    this.thought,
    this.decision,
    this.success,
    this.error,
    this.summary,
    required this.timestamp,
  });

  // ── 工厂构造：便于 Provider 创建不同状态的步骤 ──

  factory AgentStep.think(int index, String thought) => AgentStep(
    index: index,
    state: AgentStepState.think,
    thought: thought,
    timestamp: DateTime.now(),
  );

  factory AgentStep.act(int index, AgentDecision decision) => AgentStep(
    index: index,
    state: AgentStepState.act,
    decision: decision,
    timestamp: DateTime.now(),
  );

  factory AgentStep.awaitConfirm(int index, AgentDecision decision) =>
      AgentStep(
        index: index,
        state: AgentStepState.awaitingConfirm,
        decision: decision,
        timestamp: DateTime.now(),
      );

  factory AgentStep.stepDone(int index, bool success, {String? error}) =>
      AgentStep(
        index: index,
        state: AgentStepState.stepDone,
        success: success,
        error: error,
        timestamp: DateTime.now(),
      );

  factory AgentStep.done(String summary) => AgentStep(
    index: -1,
    state: AgentStepState.done,
    summary: summary,
    timestamp: DateTime.now(),
  );

  factory AgentStep.error(String message) => AgentStep(
    index: -1,
    state: AgentStepState.error,
    error: message,
    timestamp: DateTime.now(),
  );

  factory AgentStep.stopped() => AgentStep(
    index: -1,
    state: AgentStepState.stopped,
    timestamp: DateTime.now(),
  );

  factory AgentStep.rejected() => AgentStep(
    index: -1,
    state: AgentStepState.rejected,
    timestamp: DateTime.now(),
  );

  factory AgentStep.maxStepsReached() => AgentStep(
    index: -1,
    state: AgentStepState.maxStepsReached,
    timestamp: DateTime.now(),
  );

  /// 转为 JSON（用于操作日志持久化）
  Map<String, dynamic> toJson() => {
    'index': index,
    'state': state.name,
    'thought': thought,
    'action': decision?.action.wireName,
    'args': decision?.args,
    'success': success,
    'error': error,
    'summary': summary,
    'timestamp': timestamp.toIso8601String(),
  };
}
