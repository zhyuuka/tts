import '../../core/logger/app_logger.dart';

/// Agent 意图检测结果
///
/// 为什么单独成类：意图检测逻辑与 UI 跳转分离，
/// 便于单元测试和未来扩展（如 NLP 意图识别）。
class AgentIntent {
  /// 是否是显式命令（/agent 或 @agent）
  final bool isExplicitCommand;

  /// 是否是关键词匹配
  final bool isKeywordMatch;

  /// 提取出的任务目标（传给 AgentScreen 预填）
  final String taskGoal;

  const AgentIntent({
    required this.isExplicitCommand,
    required this.isKeywordMatch,
    required this.taskGoal,
  });

  /// 是否命中任意 Agent 意图
  bool get hasIntent => isExplicitCommand || isKeywordMatch;

  /// 无意图
  static const AgentIntent none = AgentIntent(
    isExplicitCommand: false,
    isKeywordMatch: false,
    taskGoal: '',
  );
}

/// 聊天内 Agent 意图识别
///
/// 职责：检测用户消息是否包含操控手机的意图，触发跳转 AgentScreen。
///
/// 为什么这样做（对应方案 4.4.2）：
/// 1. 显式命令 /agent、@agent → 直接触发，无需确认
/// 2. 关键词触发 → 提示用户"是否用 Agent 执行"，避免误触发
/// 3. 不做主动 NLP 意图识别 → 避免额外 LLM 成本和误判
///
/// 关键词设计原则（保守，避免误触发）：
/// - "帮我打开" + 常见 App 名 → 明确的操控意图
/// - "自动操作/点击/滑动" → 明确的自动化意图
/// - "操控手机/帮我操作手机" → 明确的操控意图
class AgentIntentDetector {
  AgentIntentDetector._();

  /// 显式命令前缀
  static final _commandPrefixes = [
    RegExp(r'^/agent\s+(.+)', caseSensitive: false),
    RegExp(r'^@agent\s+(.+)', caseSensitive: false),
  ];

  /// 关键词模式（保守匹配，降低误触发率）
  ///
  /// 为什么用组合词而非单关键词：
  /// "打开"单独太宽泛（"打开灯"不是手机操控），
  /// 组合"帮我打开+App名"才能确定操控意图。
  static final _keywordPatterns = [
    // "帮我打开" + 常见 App 名
    RegExp(r'帮我打开.*(微信|支付宝|QQ|抖音|淘宝|京东|设置|相机|电话|短信|地图|音乐|视频|浏览器)'),
    // 自动化操作
    RegExp(r'自动(操作|点击|滑动|输入)'),
    // 明确操控意图
    RegExp(r'(操控|控制|操作)手机'),
    RegExp(r'帮我(操作|操控)手机'),
  ];

  /// 检测文本是否包含 Agent 意图
  ///
  /// 返回 [AgentIntent]，无意图时返回 [AgentIntent.none]。
  /// 为什么是静态方法：纯逻辑无状态，便于调用和测试。
  static AgentIntent detect(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return AgentIntent.none;

    // 1. 检查显式命令 /agent、@agent
    for (final pattern in _commandPrefixes) {
      final match = pattern.firstMatch(trimmed);
      if (match != null) {
        final goal = match.group(1)?.trim() ?? '';
        if (goal.isNotEmpty) {
          AppLogger.d('[AgentIntent] 命中显式命令: $goal');
          return AgentIntent(
            isExplicitCommand: true,
            isKeywordMatch: false,
            taskGoal: goal,
          );
        }
      }
    }

    // 2. 检查关键词
    for (final pattern in _keywordPatterns) {
      if (pattern.hasMatch(trimmed)) {
        AppLogger.d('[AgentIntent] 命中关键词: $trimmed');
        return AgentIntent(
          isExplicitCommand: false,
          isKeywordMatch: true,
          taskGoal: trimmed,
        );
      }
    }

    return AgentIntent.none;
  }
}
