import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/logger/app_logger.dart';
import '../../models/agent/agent_action.dart';
import '../../models/agent/agent_event.dart';
import '../../models/agent/agent_step.dart';
import '../../models/agent/agent_task.dart';
import '../../services/agent/accessibility_bridge.dart';
import '../../services/agent/agent_operation_logger.dart';
import '../../services/agent/agent_safety_guard.dart';
import '../../services/agent/agent_service.dart';
import '../../services/agent/agent_tool_registry.dart';
import '../../services/ai_service.dart';
import '../../services/ai_service_factory.dart';
import '../../services/settings_service.dart';

/// Agent Provider - 状态管理
///
/// 职责：连接 AgentService 与 UI，管理任务状态和步骤列表。
/// 为什么继承 ChangeNotifier：与项目现有 Provider 模式一致（ChatProvider 等）。
///
/// 状态机：
/// idle → running → (awaitingConfirm → running)* → done/error/stopped
class AgentProvider extends ChangeNotifier {
  AgentProvider({
    required this.bridge,
    required this.tools,
    required this.guard,
    required this.logger,
  }) : _service = AgentService(
         bridge: bridge,
         tools: tools,
         guard: guard,
         logger: logger,
       );

  final AccessibilityBridge bridge;
  final AgentToolRegistry tools;
  final AgentSafetyGuard guard;
  final AgentOperationLogger logger;
  final AgentService _service;

  /// SettingsService 引用，用于获取 API Key（与主界面聊天一致）
  /// 为什么需要：Agent 创建 AI 服务时必须从 SettingsService 获取 API Key，
  /// 而非依赖 .env 文件（项目实际通过 SettingsService 管理 API Key）
  SettingsService? _settings;

  // ── 状态 ──

  AgentTaskState _state = AgentTaskState.idle;
  AgentTaskState get state => _state;

  String? _currentGoal;
  String? get currentGoal => _currentGoal;

  String _currentTaskId = '';
  String get currentTaskId => _currentTaskId;

  final List<AgentStep> _steps = [];
  List<AgentStep> get steps => List.unmodifiable(_steps);

  /// 当前等待确认的决策（state == awaitingConfirm 时有值）
  AgentDecision? _pendingConfirm;
  AgentDecision? get pendingConfirm => _pendingConfirm;

  /// 确认提示原因
  String? _confirmReason;
  String? get confirmReason => _confirmReason;

  /// 最近一次任务总结
  String? _lastSummary;
  String? get lastSummary => _lastSummary;

  /// 最近一次错误
  String? _lastError;
  String? get lastError => _lastError;

  /// 最大步数（透传自 AgentService.config.maxSteps）
  /// 为什么这样做：UI 需要显示进度（当前步数/最大步数），避免硬编码
  int get maxSteps => _service.config.maxSteps;

  // ── 内部 ──

  StreamSubscription<AgentEvent>? _eventSub;
  StreamSubscription<AgentStep>? _taskSub;
  Completer<bool>? _confirmCompleter;

  /// 无障碍服务是否已启用
  bool _serviceEnabled = false;
  bool get serviceEnabled => _serviceEnabled;

  /// 通知监听是否已启用
  bool _notificationEnabled = false;
  bool get notificationEnabled => _notificationEnabled;

  // ── 初始化 ──

  /// 初始化：检查权限状态、订阅事件流、恢复安全配置、清理过期日志
  ///
  /// [settings] 用于恢复安全配置（黑白名单/银行保护开关）
  ///
  /// 为什么这样做：Provider 创建后由 AppBootstrap 调用，App 启动时完成初始化。
  /// 为什么在 init 调用 loadFromSettings：用户配置的安全规则在 App 重启后必须恢复，
  /// 否则配置丢失（SafetyGuard 内存状态重启后为空）。
  /// 为什么在 init 调用 cleanupExpired：App 启动时清理一次，避免日志无限增长。
  Future<void> init(SettingsService settings) async {
    _settings = settings;
    await refreshPermissionStatus();
    _eventSub = bridge.events.listen(_handleEvent);

    // 从持久化存储恢复安全配置（黑白名单/银行保护开关）
    // 为什么这样做：用户配置的安全规则在 App 重启后必须恢复，否则配置丢失
    await guard.loadFromSettings(settings);

    // 清理过期日志（超过 30 天）
    // 为什么在 init 调用：App 启动时清理一次，避免日志无限增长
    await logger.cleanupExpired();
  }

  /// 刷新权限状态
  Future<void> refreshPermissionStatus() async {
    _serviceEnabled = await bridge.isServiceEnabled();
    _notificationEnabled = await bridge.isNotificationListenerEnabled();
    notifyListeners();
  }

  // ── 任务执行 ──

  /// 启动任务
  ///
  /// [goal] 用户目标
  /// [aiServiceId] 用于思考的 AI 服务 ID
  /// [visionServiceId] 用于视觉 fallback 的 AI 服务 ID（可选）
  /// [visionModel] 视觉模型名（可选，如 'qwen-vl-max'）。
  ///   传了 visionServiceId 时应一并传视觉模型名，否则用服务商默认模型。
  Future<void> runTask({
    required String goal,
    required String aiServiceId,
    String? visionServiceId,
    String? visionModel,
  }) async {
    if (_state == AgentTaskState.running ||
        _state == AgentTaskState.awaitingConfirm) {
      AppLogger.w('[AgentProvider] 任务正在执行，拒绝重复启动');
      return;
    }

    // 检查权限
    if (!bridge.isSupported) {
      _setError('当前平台不支持 Agent 功能（仅 Android）');
      return;
    }
    if (!_serviceEnabled) {
      _setError('未开启无障碍服务，请先授权');
      return;
    }

    // 重置状态
    _currentGoal = goal;
    _currentTaskId = 'agent_${DateTime.now().millisecondsSinceEpoch}';
    _steps.clear();
    _pendingConfirm = null;
    _confirmReason = null;
    _lastSummary = null;
    _lastError = null;
    _state = AgentTaskState.running;
    notifyListeners();

    // 创建 AI 服务实例
    // 为什么从 _settings 获取 apiKey：项目通过 SettingsService 管理 API Key（非 .env 文件），
    // 与 ChatProvider.switchAiService 保持一致，否则 Agent 会因缺少 API Key 报 401
    String? apiKey;
    if (_settings != null) {
      apiKey = _settings!.getApiKeyForService(aiServiceId);
    }
    // fallback 到 .env（兼容旧配置方式）
    apiKey ??= AiServiceFactory.getApiKeyFromEnv(aiServiceId);

    final llm = AiServiceFactory.createService(
      aiServiceId,
      apiKey: apiKey ?? '',
    );
    AiService? vlm;
    if (visionServiceId != null) {
      // 为什么传 model：视觉服务复用现有服务商，但需指定视觉模型名
      // （如通义用 qwen-vl-max，Gemini 用 gemini-3.1），否则用文本默认模型无法识别图片
      String? vlmApiKey;
      if (_settings != null) {
        vlmApiKey = _settings!.getApiKeyForService(visionServiceId);
      }
      vlmApiKey ??= AiServiceFactory.getApiKeyFromEnv(visionServiceId);
      vlm = AiServiceFactory.createService(
        visionServiceId,
        apiKey: vlmApiKey ?? '',
        model: visionModel,
      );
    }
    // 根据是否配置视觉服务，设置 AgentService 的视觉 fallback 开关
    _service.visionFallbackEnabled = vlm != null;

    // 记录任务开始
    final task = AgentTask(
      id: _currentTaskId,
      goal: goal,
      aiServiceId: aiServiceId,
      visionServiceId: visionServiceId,
      createdAt: DateTime.now(),
    );
    await logger.logTaskStart(task);

    // 启动前台服务（常驻通知 + 紧急停止按钮）
    // 为什么这样做：Agent 运行期间用户可能切到其他 App，
    // 常驻通知让用户随时知道 Agent 在运行并可一键停止
    await bridge.startForegroundService(goal);

    // 订阅步骤流
    _taskSub = _service
        .executeTask(
          goal: goal,
          llm: llm,
          vlm: vlm,
          taskId: _currentTaskId,
          onConfirm: _onConfirmRequired,
        )
        .listen(
          _onStep,
          onDone: _onTaskDone,
          onError: (e) {
            AppLogger.e('[AgentProvider] 任务流错误', e);
            bridge.stopForegroundService();
            _setError('任务执行错误: $e');
          },
        );
  }

  /// 用户确认/拒绝高危操作
  ///
  /// [approved] true 表示同意，false 表示拒绝
  void resolveConfirm(bool approved) {
    _confirmCompleter?.complete(approved);
    _confirmCompleter = null;
    _pendingConfirm = null;
    _confirmReason = null;
    if (_state == AgentTaskState.awaitingConfirm) {
      _state = AgentTaskState.running;
    }
    notifyListeners();
  }

  /// 紧急停止
  void emergencyStop() {
    _service.requestStop();
    _taskSub?.cancel();
    _taskSub = null;
    _confirmCompleter?.complete(false);
    _confirmCompleter = null;
    _pendingConfirm = null;
    // 紧急停止时移除常驻通知
    bridge.stopForegroundService();
    _state = AgentTaskState.stopped;
    notifyListeners();
  }

  /// 重置到空闲状态（任务结束后调用）
  void resetToIdle() {
    if (_state == AgentTaskState.running ||
        _state == AgentTaskState.awaitingConfirm) {
      return; // 任务进行中不允许重置
    }
    _state = AgentTaskState.idle;
    _currentGoal = null;
    _steps.clear();
    _pendingConfirm = null;
    _confirmReason = null;
    notifyListeners();
  }

  // ── 内部回调 ──

  void _onStep(AgentStep step) {
    _steps.add(step);
    switch (step.state) {
      case AgentStepState.think:
      case AgentStepState.act:
      case AgentStepState.stepDone:
        // 中间步骤，保持 running
        break;
      case AgentStepState.awaitingConfirm:
        _state = AgentTaskState.awaitingConfirm;
        _pendingConfirm = step.decision;
        _confirmReason = step.thought;
        break;
      case AgentStepState.done:
        _state = AgentTaskState.done;
        _lastSummary = step.summary;
        break;
      case AgentStepState.error:
        _state = AgentTaskState.error;
        _lastError = step.error;
        break;
      case AgentStepState.stopped:
        _state = AgentTaskState.stopped;
        break;
      case AgentStepState.rejected:
        // 用户拒绝单步，任务继续
        break;
      case AgentStepState.maxStepsReached:
        _state = AgentTaskState.error;
        _lastError = '达到最大步数限制';
        break;
    }
    notifyListeners();
  }

  void _onTaskDone() {
    _taskSub = null;
    // 任务结束，停止前台服务移除常驻通知
    bridge.stopForegroundService();
    if (_state == AgentTaskState.running) {
      // 流结束但状态未变更，兜底设为 done
      _state = AgentTaskState.done;
      notifyListeners();
    }
  }

  /// 高危操作确认回调（由 AgentService 调用）
  Future<bool> _onConfirmRequired(AgentDecision decision, String reason) async {
    _state = AgentTaskState.awaitingConfirm;
    _pendingConfirm = decision;
    _confirmReason = reason;
    notifyListeners();

    _confirmCompleter = Completer<bool>();
    return _confirmCompleter!.future;
  }

  void _handleEvent(AgentEvent event) {
    switch (event.type) {
      case AgentEventType.serviceStateChanged:
        final e = event as ServiceStateChangedEvent;
        _serviceEnabled = e.enabled;
        notifyListeners();
        break;
      case AgentEventType.foregroundAppChanged:
        // 前台 App 变化，可用于未来扩展（如自动暂停）
        break;
      case AgentEventType.notificationPosted:
      case AgentEventType.notificationRemoved:
        // 通知事件，可用于未来扩展
        break;
      case AgentEventType.emergencyStop:
        // 用户点击通知栏"紧急停止"按钮，立即停止 Agent 任务
        // 为什么这样做：原生侧只停止了前台服务，AI 操控循环仍在运行，
        // 必须在 Dart 侧调用 emergencyStop 停止任务流
        emergencyStop();
        break;
      case AgentEventType.unknown:
        break;
    }
  }

  void _setError(String message) {
    _state = AgentTaskState.error;
    _lastError = message;
    AppLogger.e('[AgentProvider] $message');
    notifyListeners();
  }

  @override
  void dispose() {
    _eventSub?.cancel();
    _taskSub?.cancel();
    _confirmCompleter?.complete(false);
    super.dispose();
  }
}
