/// Agent 任务状态
///
/// 对应 Provider 暴露给 UI 的整体状态。
enum AgentTaskState {
  /// 空闲
  idle,

  /// 运行中
  running,

  /// 等待用户确认
  awaitingConfirm,

  /// 已完成
  done,

  /// 出错
  error,

  /// 已停止
  stopped,
}

/// Agent 任务（一次完整的"目标 → 执行 → 完成"）
///
/// 为什么单独成类：任务需要持久化到操作日志，且 UI 需要展示任务历史。
class AgentTask {
  /// 任务唯一 ID
  final String id;

  /// 用户输入的目标（如"打开微信发消息给妈妈"）
  final String goal;

  /// 使用的 LLM 服务 ID（用于思考）
  final String aiServiceId;

  /// 使用的 VLM 服务 ID（用于视觉 fallback，可为 null）
  final String? visionServiceId;

  /// 任务状态
  final AgentTaskState state;

  /// 创建时间
  final DateTime createdAt;

  /// 完成时间（state == done/error/stopped 时有值）
  final DateTime? finishedAt;

  /// 任务总结（state == done 时有值）
  final String? summary;

  /// 错误信息（state == error 时有值）
  final String? error;

  AgentTask({
    required this.id,
    required this.goal,
    required this.aiServiceId,
    this.visionServiceId,
    this.state = AgentTaskState.idle,
    required this.createdAt,
    this.finishedAt,
    this.summary,
    this.error,
  });

  /// 创建副本（用于状态变更时不可变更新）
  /// 为什么这样做：Provider 模式下状态变更应创建新对象，避免引用问题
  AgentTask copyWith({
    AgentTaskState? state,
    DateTime? finishedAt,
    String? summary,
    String? error,
  }) => AgentTask(
    id: id,
    goal: goal,
    aiServiceId: aiServiceId,
    visionServiceId: visionServiceId,
    state: state ?? this.state,
    createdAt: createdAt,
    finishedAt: finishedAt ?? this.finishedAt,
    summary: summary ?? this.summary,
    error: error ?? this.error,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'goal': goal,
    'aiServiceId': aiServiceId,
    'visionServiceId': visionServiceId,
    'state': state.name,
    'createdAt': createdAt.toIso8601String(),
    'finishedAt': finishedAt?.toIso8601String(),
    'summary': summary,
    'error': error,
  };
}
