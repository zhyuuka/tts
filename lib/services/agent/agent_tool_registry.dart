import '../../core/logger/app_logger.dart';
import '../../models/agent/agent_action.dart';
import 'accessibility_bridge.dart';

/// 工具执行结果
class ToolResult {
  final bool success;
  final String? error;
  final Map<String, dynamic> observation;

  /// 给 LLM 的观察文本（执行后 LLM 据此判断下一步）
  /// 为什么单独字段：LLM 需要自然语言描述的结果，而非原始 Map
  final String observationText;

  const ToolResult({
    required this.success,
    this.error,
    this.observation = const {},
    this.observationText = '',
  });

  const ToolResult.ok(this.observationText, {Map<String, dynamic>? data})
    : success = true,
      error = null,
      observation = data ?? const {};

  const ToolResult.fail(this.error)
    : success = false,
      observation = const {},
      observationText = '';
}

/// Agent 工具抽象
///
/// 为什么这样做：每个工具封装为独立类，便于：
/// 1. 单元测试每个工具
/// 2. 新增工具只需实现接口并注册
/// 3. 自动生成 LLM function calling 定义
abstract class AgentTool {
  /// 工具对应的动作类型
  AgentActionType get actionType;

  /// 工具名称（LLM function calling 用）
  String get name => actionType.wireName;

  /// 工具描述（LLM 据此判断何时调用）
  String get description;

  /// 参数 JSON Schema（LLM function calling 用）
  /// 为什么返回 Map：直接生成 OpenAI 兼容的 parameters 格式
  Map<String, dynamic> get parametersSchema;

  /// 执行工具
  Future<ToolResult> execute(Map<String, dynamic> args);
}

/// Agent 工具注册表
///
/// 职责：管理所有工具，分发执行，生成 LLM function calling 定义。
/// 为什么单独成类：
/// 1. 工具集中管理，避免散落在 AgentService
/// 2. 可扩展：新增工具只需注册，不改 AgentService
/// 3. 自动生成 function calling 定义，避免手写
class AgentToolRegistry {
  AgentToolRegistry(this._bridge);

  final AccessibilityBridge _bridge;

  /// 已注册的工具（按动作类型索引）
  /// 为什么延迟初始化：工具依赖 bridge，构造时 bridge 已就绪
  late final Map<AgentActionType, AgentTool> _tools = _buildTools();

  Map<AgentActionType, AgentTool> _buildTools() => {
    AgentActionType.tap: TapTool(_bridge),
    AgentActionType.doubleTap: DoubleTapTool(_bridge),
    AgentActionType.longPress: LongPressTool(_bridge),
    AgentActionType.swipe: SwipeTool(_bridge),
    AgentActionType.inputText: InputTextTool(_bridge),
    AgentActionType.clearInput: ClearInputTool(_bridge),
    AgentActionType.pressBack: PressBackTool(_bridge),
    AgentActionType.pressHome: PressHomeTool(_bridge),
    AgentActionType.pressRecents: PressRecentsTool(_bridge),
    AgentActionType.launchApp: LaunchAppTool(_bridge),
    AgentActionType.getForegroundApp: GetForegroundAppTool(_bridge),
    AgentActionType.readNotifications: ReadNotificationsTool(_bridge),
  };

  /// 执行决策对应的工具
  ///
  /// [decision] LLM 决策（含动作类型和参数）
  /// 返回执行结果，不抛异常
  Future<ToolResult> execute(AgentDecision decision) async {
    // 终止类动作不执行工具
    if (decision.action == AgentActionType.done ||
        decision.action == AgentActionType.failed ||
        decision.action == AgentActionType.askUser) {
      return ToolResult.ok(decision.summary ?? decision.thought);
    }

    final tool = _tools[decision.action];
    if (tool == null) {
      return ToolResult.fail('未注册的工具: ${decision.action.wireName}');
    }

    try {
      return await tool.execute(decision.args);
    } catch (e) {
      AppLogger.e('[ToolRegistry] ${decision.action.wireName} 执行异常', e);
      return ToolResult.fail('执行异常: $e');
    }
  }

  /// 生成 OpenAI 兼容的 function calling 定义
  ///
  /// 为什么这样做：复用现有 AiService 的 function calling 能力，
  /// 让 LLM 知道有哪些工具可用及如何调用。
  List<Map<String, dynamic>> toFunctionDefinitions() {
    return _tools.values.map((tool) {
      return {
        'type': 'function',
        'function': {
          'name': tool.name,
          'description': tool.description,
          'parameters': tool.parametersSchema,
        },
      };
    }).toList();
  }
}

// ── 具体工具实现 ──

class TapTool extends AgentTool {
  TapTool(this._bridge);
  final AccessibilityBridge _bridge;

  @override
  AgentActionType get actionType => AgentActionType.tap;

  @override
  String get description => '点击屏幕指定坐标。args: x (int), y (int)';

  @override
  Map<String, dynamic> get parametersSchema => {
    'type': 'object',
    'properties': {
      'x': {'type': 'integer', 'description': 'x 坐标'},
      'y': {'type': 'integer', 'description': 'y 坐标'},
    },
    'required': ['x', 'y'],
  };

  @override
  Future<ToolResult> execute(Map<String, dynamic> args) async {
    final x = (args['x'] as num?)?.toInt();
    final y = (args['y'] as num?)?.toInt();
    if (x == null || y == null) {
      return const ToolResult.fail('参数 x/y 缺失');
    }
    final res = await _bridge.tap(x, y);
    if (res.success) {
      return ToolResult.ok('已点击 ($x, $y)');
    }
    return ToolResult.fail(res.error ?? '点击失败');
  }
}

class DoubleTapTool extends AgentTool {
  DoubleTapTool(this._bridge);
  final AccessibilityBridge _bridge;

  @override
  AgentActionType get actionType => AgentActionType.doubleTap;

  @override
  String get description => '双击屏幕指定坐标。args: x (int), y (int)';

  @override
  Map<String, dynamic> get parametersSchema => {
    'type': 'object',
    'properties': {
      'x': {'type': 'integer'},
      'y': {'type': 'integer'},
    },
    'required': ['x', 'y'],
  };

  @override
  Future<ToolResult> execute(Map<String, dynamic> args) async {
    final x = (args['x'] as num?)?.toInt();
    final y = (args['y'] as num?)?.toInt();
    if (x == null || y == null) {
      return const ToolResult.fail('参数 x/y 缺失');
    }
    final res = await _bridge.doubleTap(x, y);
    return res.success
        ? ToolResult.ok('已双击 ($x, $y)')
        : ToolResult.fail(res.error ?? '双击失败');
  }
}

class LongPressTool extends AgentTool {
  LongPressTool(this._bridge);
  final AccessibilityBridge _bridge;

  @override
  AgentActionType get actionType => AgentActionType.longPress;

  @override
  String get description => '长按屏幕指定坐标。args: x, y, durationMs (可选, 默认1000)';

  @override
  Map<String, dynamic> get parametersSchema => {
    'type': 'object',
    'properties': {
      'x': {'type': 'integer'},
      'y': {'type': 'integer'},
      'durationMs': {'type': 'integer', 'description': '持续时间，默认 1000'},
    },
    'required': ['x', 'y'],
  };

  @override
  Future<ToolResult> execute(Map<String, dynamic> args) async {
    final x = (args['x'] as num?)?.toInt();
    final y = (args['y'] as num?)?.toInt();
    if (x == null || y == null) {
      return const ToolResult.fail('参数 x/y 缺失');
    }
    final duration = (args['durationMs'] as num?)?.toInt() ?? 1000;
    final res = await _bridge.longPress(x, y, durationMs: duration);
    return res.success
        ? ToolResult.ok('已长按 ($x, $y) ${duration}ms')
        : ToolResult.fail(res.error ?? '长按失败');
  }
}

class SwipeTool extends AgentTool {
  SwipeTool(this._bridge);
  final AccessibilityBridge _bridge;

  @override
  AgentActionType get actionType => AgentActionType.swipe;

  @override
  String get description => '从 (startX, startY) 滑动到 (endX, endY)。';

  @override
  Map<String, dynamic> get parametersSchema => {
    'type': 'object',
    'properties': {
      'startX': {'type': 'integer'},
      'startY': {'type': 'integer'},
      'endX': {'type': 'integer'},
      'endY': {'type': 'integer'},
      'durationMs': {'type': 'integer', 'description': '默认 300'},
    },
    'required': ['startX', 'startY', 'endX', 'endY'],
  };

  @override
  Future<ToolResult> execute(Map<String, dynamic> args) async {
    final sx = (args['startX'] as num?)?.toInt();
    final sy = (args['startY'] as num?)?.toInt();
    final ex = (args['endX'] as num?)?.toInt();
    final ey = (args['endY'] as num?)?.toInt();
    if (sx == null || sy == null || ex == null || ey == null) {
      return const ToolResult.fail('参数缺失');
    }
    final duration = (args['durationMs'] as num?)?.toInt() ?? 300;
    final res = await _bridge.swipe(sx, sy, ex, ey, durationMs: duration);
    return res.success
        ? ToolResult.ok('已滑动 ($sx,$sy)→($ex,$ey)')
        : ToolResult.fail(res.error ?? '滑动失败');
  }
}

class InputTextTool extends AgentTool {
  InputTextTool(this._bridge);
  final AccessibilityBridge _bridge;

  @override
  AgentActionType get actionType => AgentActionType.inputText;

  @override
  String get description => '在当前聚焦的输入框输入文本。args: text (string)';

  @override
  Map<String, dynamic> get parametersSchema => {
    'type': 'object',
    'properties': {
      'text': {'type': 'string', 'description': '要输入的文本'},
    },
    'required': ['text'],
  };

  @override
  Future<ToolResult> execute(Map<String, dynamic> args) async {
    final text = args['text'] as String?;
    if (text == null || text.isEmpty) {
      return const ToolResult.fail('参数 text 缺失或为空');
    }
    final res = await _bridge.inputText(text);
    return res.success
        ? ToolResult.ok('已输入文本（长度 ${text.length}）')
        : ToolResult.fail(res.error ?? '输入失败');
  }
}

class ClearInputTool extends AgentTool {
  ClearInputTool(this._bridge);
  final AccessibilityBridge _bridge;

  @override
  AgentActionType get actionType => AgentActionType.clearInput;

  @override
  String get description => '清空当前聚焦的输入框。';

  @override
  Map<String, dynamic> get parametersSchema => {
    'type': 'object',
    'properties': {},
  };

  @override
  Future<ToolResult> execute(Map<String, dynamic> args) async {
    final res = await _bridge.clearInput();
    return res.success
        ? const ToolResult.ok('已清空输入框')
        : ToolResult.fail(res.error ?? '清空失败');
  }
}

class PressBackTool extends AgentTool {
  PressBackTool(this._bridge);
  final AccessibilityBridge _bridge;

  @override
  AgentActionType get actionType => AgentActionType.pressBack;

  @override
  String get description => '按下返回键。';

  @override
  Map<String, dynamic> get parametersSchema => {
    'type': 'object',
    'properties': {},
  };

  @override
  Future<ToolResult> execute(Map<String, dynamic> args) async {
    final res = await _bridge.pressBack();
    return res.success
        ? const ToolResult.ok('已按返回键')
        : ToolResult.fail(res.error ?? '返回失败');
  }
}

class PressHomeTool extends AgentTool {
  PressHomeTool(this._bridge);
  final AccessibilityBridge _bridge;

  @override
  AgentActionType get actionType => AgentActionType.pressHome;

  @override
  String get description => '按下 Home 键回到桌面。';

  @override
  Map<String, dynamic> get parametersSchema => {
    'type': 'object',
    'properties': {},
  };

  @override
  Future<ToolResult> execute(Map<String, dynamic> args) async {
    final res = await _bridge.pressHome();
    return res.success
        ? const ToolResult.ok('已按 Home 键')
        : ToolResult.fail(res.error ?? 'Home 失败');
  }
}

class PressRecentsTool extends AgentTool {
  PressRecentsTool(this._bridge);
  final AccessibilityBridge _bridge;

  @override
  AgentActionType get actionType => AgentActionType.pressRecents;

  @override
  String get description => '按下最近任务键。';

  @override
  Map<String, dynamic> get parametersSchema => {
    'type': 'object',
    'properties': {},
  };

  @override
  Future<ToolResult> execute(Map<String, dynamic> args) async {
    final res = await _bridge.pressRecents();
    return res.success
        ? const ToolResult.ok('已按最近任务键')
        : ToolResult.fail(res.error ?? '失败');
  }
}

class LaunchAppTool extends AgentTool {
  LaunchAppTool(this._bridge);
  final AccessibilityBridge _bridge;

  @override
  AgentActionType get actionType => AgentActionType.launchApp;

  @override
  String get description => '启动指定 App。args: packageName (string)';

  @override
  Map<String, dynamic> get parametersSchema => {
    'type': 'object',
    'properties': {
      'packageName': {'type': 'string', 'description': 'App 包名'},
    },
    'required': ['packageName'],
  };

  @override
  Future<ToolResult> execute(Map<String, dynamic> args) async {
    final pkg = args['packageName'] as String?;
    if (pkg == null || pkg.isEmpty) {
      return const ToolResult.fail('参数 packageName 缺失');
    }
    final res = await _bridge.launchApp(pkg);
    return res.success
        ? ToolResult.ok('已启动 App: $pkg')
        : ToolResult.fail(res.error ?? '启动失败');
  }
}

class GetForegroundAppTool extends AgentTool {
  GetForegroundAppTool(this._bridge);
  final AccessibilityBridge _bridge;

  @override
  AgentActionType get actionType => AgentActionType.getForegroundApp;

  @override
  String get description => '获取当前前台 App 的包名和 Activity。';

  @override
  Map<String, dynamic> get parametersSchema => {
    'type': 'object',
    'properties': {},
  };

  @override
  Future<ToolResult> execute(Map<String, dynamic> args) async {
    final res = await _bridge.getForegroundApp();
    if (res.success && res.data != null) {
      final data = res.data!;
      return ToolResult.ok(
        '前台 App: ${data.package} / ${data.activity}',
        data: {'package': data.package, 'activity': data.activity},
      );
    }
    return ToolResult.fail(res.error ?? '获取失败');
  }
}

class ReadNotificationsTool extends AgentTool {
  ReadNotificationsTool(this._bridge);
  final AccessibilityBridge _bridge;

  @override
  AgentActionType get actionType => AgentActionType.readNotifications;

  @override
  String get description => '读取最近的通知列表。args: limit (可选, 默认50)';

  @override
  Map<String, dynamic> get parametersSchema => {
    'type': 'object',
    'properties': {
      'limit': {'type': 'integer', 'description': '最大条数，默认 50'},
    },
  };

  @override
  Future<ToolResult> execute(Map<String, dynamic> args) async {
    final limit = (args['limit'] as num?)?.toInt() ?? 50;
    final res = await _bridge.readNotifications(limit: limit);
    if (res.success && res.data != null) {
      final list = res.data!;
      final text = list
          .map((n) {
            final title = n['title'] ?? '';
            final text = n['text'] ?? '';
            return '[$title] $text';
          })
          .join('\n');
      return ToolResult.ok(
        '共 ${list.length} 条通知:\n$text',
        data: {'count': list.length},
      );
    }
    return ToolResult.fail(res.error ?? '读取失败');
  }
}
