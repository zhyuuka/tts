/// Agent 原生事件类型
///
/// 对应 EventChannel 推送的事件，用于实时通知 Dart 侧原生状态变化。
enum AgentEventType {
  serviceStateChanged('onServiceStateChanged'),
  notificationPosted('onNotificationPosted'),
  notificationRemoved('onNotificationRemoved'),
  foregroundAppChanged('onForegroundAppChanged'),
  emergencyStop('onEmergencyStop'),
  unknown('unknown');

  final String wireName;
  const AgentEventType(this.wireName);

  static AgentEventType fromWire(String? name) {
    if (name == null) return AgentEventType.unknown;
    for (final v in AgentEventType.values) {
      if (v.wireName == name) return v;
    }
    return AgentEventType.unknown;
  }
}

/// Agent 原生事件（从原生侧推送到 Dart）
///
/// 为什么用 sealed 风格的类层次：不同事件字段不同，统一基类便于 Stream 消费。
abstract class AgentEvent {
  final AgentEventType type;
  final DateTime timestamp;

  const AgentEvent({required this.type, required this.timestamp});

  /// 从原生返回的 Map 解析为具体事件类型
  /// 为什么这样做：EventChannel 传 Map，需在 Dart 侧转为强类型
  factory AgentEvent.fromMap(Map<String, dynamic> map) {
    final type = AgentEventType.fromWire(map['event'] as String?);
    final ts =
        DateTime.tryParse(map['timestamp'] as String? ?? '') ?? DateTime.now();

    switch (type) {
      case AgentEventType.serviceStateChanged:
        return ServiceStateChangedEvent(
          enabled: (map['enabled'] as bool?) ?? false,
          timestamp: ts,
        );
      case AgentEventType.notificationPosted:
        return NotificationPostedEvent(
          packageName: (map['package'] as String?) ?? '',
          title: (map['title'] as String?) ?? '',
          text: (map['text'] as String?) ?? '',
          timestamp: ts,
        );
      case AgentEventType.notificationRemoved:
        return NotificationRemovedEvent(
          packageName: (map['package'] as String?) ?? '',
          timestamp: ts,
        );
      case AgentEventType.foregroundAppChanged:
        return ForegroundAppChangedEvent(
          packageName: (map['package'] as String?) ?? '',
          activity: (map['activity'] as String?) ?? '',
          timestamp: ts,
        );
      case AgentEventType.emergencyStop:
        return EmergencyStopEvent(timestamp: ts);
      case AgentEventType.unknown:
        return UnknownEvent(map: map, timestamp: ts);
    }
  }
}

/// 无障碍服务开关变化
class ServiceStateChangedEvent extends AgentEvent {
  final bool enabled;
  const ServiceStateChangedEvent({
    required this.enabled,
    required super.timestamp,
  }) : super(type: AgentEventType.serviceStateChanged);
}

/// 新通知到达
class NotificationPostedEvent extends AgentEvent {
  final String packageName;
  final String title;
  final String text;
  const NotificationPostedEvent({
    required this.packageName,
    required this.title,
    required this.text,
    required super.timestamp,
  }) : super(type: AgentEventType.notificationPosted);
}

/// 通知被移除
class NotificationRemovedEvent extends AgentEvent {
  final String packageName;
  const NotificationRemovedEvent({
    required this.packageName,
    required super.timestamp,
  }) : super(type: AgentEventType.notificationRemoved);
}

/// 前台 App 切换
class ForegroundAppChangedEvent extends AgentEvent {
  final String packageName;
  final String activity;
  const ForegroundAppChangedEvent({
    required this.packageName,
    required this.activity,
    required super.timestamp,
  }) : super(type: AgentEventType.foregroundAppChanged);
}

/// 紧急停止事件（用户点击通知栏"紧急停止"按钮触发）
/// 为什么单独成类：与普通停止不同，紧急停止来自原生通知栏，需立即停止 AI 操控循环
class EmergencyStopEvent extends AgentEvent {
  const EmergencyStopEvent({required super.timestamp})
    : super(type: AgentEventType.emergencyStop);
}

/// 未知事件（兜底，避免原生新增事件类型时 Dart 侧崩溃）
class UnknownEvent extends AgentEvent {
  final Map<String, dynamic> map;
  const UnknownEvent({required this.map, required super.timestamp})
    : super(type: AgentEventType.unknown);
}
