import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import '../../core/logger/app_logger.dart';
import '../../models/agent/agent_action.dart';
import '../../models/agent/agent_step.dart';
import '../../models/agent/agent_task.dart';
import '../../models/agent/ui_node.dart';
import '../../models/attachment.dart';
import '../../models/message.dart';
import '../ai_service.dart';
import 'accessibility_bridge.dart';
import 'agent_operation_logger.dart';
import 'agent_safety_guard.dart';
import 'agent_tool_registry.dart';

/// Agent 执行配置
///
/// 为什么单独成类：配置项集中管理，便于测试和未来扩展
class AgentConfig {
  /// 最大步数（防止无限循环）
  final int maxSteps;

  /// 单步超时
  final Duration stepTimeout;

  /// 行动后观察延迟（等待 UI 刷新）
  final Duration observeDelay;

  /// 连续失败上限（达到则自动停止）
  final int maxConsecutiveFailures;

  /// 重复操作上限（达到则判定循环，自动停止）
  final int maxRepeats;

  /// 是否启用 VLM 视觉 fallback
  final bool visionFallbackEnabled;

  const AgentConfig({
    this.maxSteps = 30,
    this.stepTimeout = const Duration(seconds: 30),
    this.observeDelay = const Duration(milliseconds: 500),
    this.maxConsecutiveFailures = 3,
    this.maxRepeats = 5,
    this.visionFallbackEnabled = false,
  });

  static const AgentConfig defaultConfig = AgentConfig();
}

/// Agent 编排服务
///
/// 职责：执行"感知→思考→安全检查→行动→观察"循环，完成用户目标。
/// 为什么单独成类：
/// 1. 编排逻辑与 UI 状态分离（Provider 管状态，Service 管逻辑）
/// 2. 可独立测试（注入 mock 的 bridge/llm/guard）
/// 3. 可扩展（新增感知方式、新增工具不影响循环结构）
///
/// 设计原则：
/// - 所有错误通过 Stream 上报，不抛异常
/// - 紧急停止通过标志位 + 流取消实现
/// - LLM 输出容错解析（JSON 不稳定时重试）
class AgentService {
  AgentService({
    required this.bridge,
    required this.tools,
    required this.guard,
    required this.logger,
    this.config = AgentConfig.defaultConfig,
  });

  final AccessibilityBridge bridge;
  final AgentToolRegistry tools;
  final AgentSafetyGuard guard;
  final AgentOperationLogger logger;
  final AgentConfig config;

  /// 视觉 fallback 运行时开关
  ///
  /// 为什么可变且独立于 config：config 在构造时固定，而此开关需在任务开始时
  /// 由 Provider 根据用户是否配置了视觉服务动态设置（用户配了视觉服务才启用）。
  bool visionFallbackEnabled = false;

  /// 紧急停止标志
  /// 为什么用 volatile 语义：循环每步检查此标志
  bool _stopRequested = false;

  /// 最近一次 _think 失败的具体原因
  /// 为什么这样做：UI 需要显示具体失败原因（调用异常 vs 解析失败），
  /// 否则用户只看到"连续 N 次 LLM 调用失败"无法定位问题
  String? _lastThinkError;

  /// 当前 LLM 流式订阅（用于紧急停止时取消）
  StreamSubscription<ChatChunk>? _llmSub;

  /// 请求紧急停止
  ///
  /// 为什么这样做：
  /// 1. 设置标志，循环下次检查时退出
  /// 2. 取消 LLM 流式响应（复用 AiService.cancelStream）
  /// 3. 通知原生取消正在执行的手势
  void requestStop() {
    _stopRequested = true;
    _llmSub?.cancel();
    bridge.emergencyStopNative();
  }

  /// 执行任务
  ///
  /// [goal] 用户目标
  /// [llm] 用于思考的 AI 服务
  /// [vlm] 用于视觉 fallback 的 AI 服务（可为 null）
  /// [taskId] 任务 ID（用于日志）
  /// [onConfirm] 高危操作确认回调，返回 true 表示用户同意
  ///
  /// 返回步骤流，UI 层订阅展示进度。
  Stream<AgentStep> executeTask({
    required String goal,
    required AiService llm,
    required AiService? vlm,
    required String taskId,
    required Future<bool> Function(AgentDecision, String reason) onConfirm,
  }) async* {
    _stopRequested = false;

    // 1. 前置安全检查
    final precheck = guard.precheckGoal(goal);
    if (!precheck.allowed) {
      yield AgentStep.error(precheck.reason ?? '目标被安全守卫拒绝');
      await logger.logTaskEnd(
        taskId,
        state: AgentTaskState.error,
        error: precheck.reason,
      );
      return;
    }

    // 2. 构建对话历史
    final history = <Message>[];
    history.add(Message(role: 'system', content: _buildSystemPrompt(goal)));

    // 3. 循环状态
    int consecutiveFailures = 0;
    String? lastActionSignature;
    int repeatCount = 0;

    // 4. 进入循环
    for (var step = 0; step < config.maxSteps; step++) {
      // 检查紧急停止
      if (_stopRequested) {
        yield AgentStep.stopped();
        await logger.logTaskEnd(taskId, state: AgentTaskState.stopped);
        return;
      }

      // ── 感知 ──
      final perception = await _perceive(vlm);
      history.add(perception);

      // ── 思考 ──
      final thinkResult = await _think(llm, history);
      if (thinkResult == null) {
        // LLM 调用失败
        consecutiveFailures++;
        if (consecutiveFailures >= config.maxConsecutiveFailures) {
          // 为什么包含 _lastThinkError：让用户看到具体失败原因（调用异常 vs 解析失败）
          final detail = _lastThinkError ?? '未知原因';
          yield AgentStep.error(
            '连续 $consecutiveFailures 次 LLM 调用失败\n\n原因：$detail',
          );
          await logger.logTaskEnd(
            taskId,
            state: AgentTaskState.error,
            error: 'LLM 连续失败：$detail',
          );
          return;
        }
        continue;
      }

      yield AgentStep.think(step, thinkResult.thought);

      // 检查紧急停止（思考期间用户可能点了停止）
      if (_stopRequested) {
        yield AgentStep.stopped();
        await logger.logTaskEnd(taskId, state: AgentTaskState.stopped);
        return;
      }

      // ── 终止判断 ──
      if (thinkResult.action == AgentActionType.done) {
        yield AgentStep.done(thinkResult.summary ?? '任务完成');
        await logger.logTaskEnd(
          taskId,
          state: AgentTaskState.done,
          summary: thinkResult.summary,
        );
        return;
      }
      if (thinkResult.action == AgentActionType.failed) {
        yield AgentStep.error(thinkResult.summary ?? '任务失败');
        await logger.logTaskEnd(
          taskId,
          state: AgentTaskState.error,
          error: thinkResult.summary,
        );
        return;
      }
      if (thinkResult.action == AgentActionType.askUser) {
        // LLM 需要询问用户，通过 onConfirm 回调（复用确认机制）
        final approved = await onConfirm(
          thinkResult,
          thinkResult.summary ?? thinkResult.thought,
        );
        if (!approved) {
          yield AgentStep.rejected();
          await logger.logTaskEnd(taskId, state: AgentTaskState.stopped);
          return;
        }
        history.add(
          Message(
            role: 'assistant',
            content: '用户已确认: ${thinkResult.summary ?? thinkResult.thought}',
          ),
        );
        continue;
      }

      // ── 安全检查 ──
      final safety = guard.checkAction(thinkResult);
      if (!safety.allowed) {
        yield AgentStep.error(safety.reason ?? '操作被安全守卫拒绝');
        history.add(
          Message(role: 'user', content: '系统提示：操作被拒绝 - ${safety.reason}'),
        );
        consecutiveFailures++;
        if (consecutiveFailures >= config.maxConsecutiveFailures) {
          yield AgentStep.error('连续 $consecutiveFailures 次操作被拒绝');
          await logger.logTaskEnd(
            taskId,
            state: AgentTaskState.error,
            error: '连续被拒绝',
          );
          return;
        }
        continue;
      }

      if (safety.requiresConfirm) {
        yield AgentStep.awaitConfirm(step, thinkResult);
        final approved = await onConfirm(thinkResult, safety.reason ?? '需要确认');
        if (!approved) {
          yield AgentStep.rejected();
          history.add(Message(role: 'user', content: '用户拒绝了此操作'));
          continue;
        }
      }

      // ── 循环检测 ──
      final signature = thinkResult.signature;
      if (signature == lastActionSignature) {
        repeatCount++;
        if (repeatCount >= config.maxRepeats) {
          yield AgentStep.error('检测到循环操作（连续 $repeatCount 次相同动作）');
          await logger.logTaskEnd(
            taskId,
            state: AgentTaskState.error,
            error: '循环操作',
          );
          return;
        }
      } else {
        repeatCount = 0;
        lastActionSignature = signature;
      }

      // ── 行动 ──
      yield AgentStep.act(step, thinkResult);
      final result = await tools
          .execute(thinkResult)
          .timeout(
            config.stepTimeout,
            onTimeout: () {
              return const ToolResult.fail('单步超时');
            },
          );

      yield AgentStep.stepDone(step, result.success, error: result.error);

      // 记录日志
      await logger.logStep(
        taskId,
        step,
        thinkResult,
        result.success,
        error: result.error,
      );

      // ── 失败计数 ──
      if (result.success) {
        consecutiveFailures = 0;
      } else {
        consecutiveFailures++;
        if (consecutiveFailures >= config.maxConsecutiveFailures) {
          yield AgentStep.error('连续 $consecutiveFailures 步失败');
          await logger.logTaskEnd(
            taskId,
            state: AgentTaskState.error,
            error: '连续失败',
          );
          return;
        }
      }

      // ── 观察 ──
      history.add(
        Message(role: 'user', content: '操作结果: ${result.observationText}'),
      );

      await Future.delayed(config.observeDelay);
    }

    // 达到最大步数
    yield AgentStep.maxStepsReached();
    await logger.logTaskEnd(
      taskId,
      state: AgentTaskState.error,
      error: '达到最大步数',
    );
  }

  // ── 感知 ──

  /// 感知当前屏幕状态，返回给 LLM 的描述
  ///
  /// 策略（对应方案 6.3）：
  /// 1. 优先用无障碍树（快、便宜）
  /// 2. 无障碍树为空/节点<5 时 fallback 到 VLM（若启用）
  /// 3. VLM fallback 前必须脱敏检查（安全核心，见方案 5.3）
  Future<Message> _perceive(AiService? vlm) async {
    final uiTreeResult = await bridge.captureUiTree();
    UiTree? tree;
    if (uiTreeResult.success) {
      tree = uiTreeResult.data;
      if (tree != null && !tree.needsVisionFallback) {
        return Message(
          role: 'user',
          content: '当前屏幕 UI 树:\n${_uiTreeToText(tree)}',
        );
      }
    }

    // VLM fallback：无障碍树不可用或节点太少时，用视觉模型描述截图
    if (!visionFallbackEnabled || vlm == null) {
      // 未启用视觉 fallback，降级返回 UI 树文本或感知失败
      return Message(
        role: 'user',
        content: tree != null
            ? '当前屏幕 UI 树:\n${_uiTreeToText(tree)}'
            : '当前屏幕: 感知失败（无障碍树不可用，未启用视觉 fallback）',
      );
    }

    final screenshot = await bridge.takeScreenshot();
    if (!screenshot.success || screenshot.data == null) {
      return Message(
        role: 'user',
        content: tree != null
            ? '当前屏幕 UI 树（不完整）:\n${_uiTreeToText(tree)}'
            : '当前屏幕: 感知失败（截图不可用）',
      );
    }

    // 截图脱敏检查（上传 VLM 前必须脱敏）
    // 为什么这样做：VLM 是云端服务，截图可能含密码/验证码，上传前必须检查
    final redact = guard.redactScreenshot(tree);
    if (!redact.allowed) {
      AppLogger.w('[AgentService] 截图脱敏拒绝: ${redact.reason}');
      return Message(
        role: 'user',
        content: tree != null
            ? '当前屏幕 UI 树（视觉描述因敏感信息被禁用）:\n${_uiTreeToText(tree)}'
            : '当前屏幕: 视觉描述被禁用（${redact.reason}）',
      );
    }

    try {
      final description = await _describeWithVlm(vlm, screenshot.data!);
      return Message(role: 'user', content: '当前屏幕（视觉描述）:\n$description');
    } catch (e) {
      AppLogger.e('[AgentService] VLM 描述失败', e);
      return Message(
        role: 'user',
        content: tree != null
            ? '当前屏幕 UI 树（视觉描述失败）:\n${_uiTreeToText(tree)}'
            : '当前屏幕: 视觉描述失败',
      );
    }
  }

  /// 将 UI 树转为 LLM 可读的文本
  /// 为什么这样做：LLM 理解文本比理解原始 JSON 更准确
  String _uiTreeToText(UiTree tree) {
    final buffer = StringBuffer();
    buffer.writeln('屏幕: ${tree.screenWidth}x${tree.screenHeight}');
    buffer.writeln('前台 App: ${tree.packageName}');

    void walk(UiNode node, int indent) {
      if (!node.visibleToUser) return;
      final pad = '  ' * indent;
      final parts = <String>[];
      if (node.text.isNotEmpty) parts.add('text="${node.text}"');
      if (node.contentDescription.isNotEmpty) {
        parts.add('desc="${node.contentDescription}"');
      }
      if (node.id != null) parts.add('id=${node.id}');
      if (node.clickable) parts.add('clickable');
      if (node.isPassword) parts.add('password');
      if (node.bounds.length == 4) {
        final (cx, cy) = node.center;
        parts.add('center=($cx,$cy)');
      }
      if (parts.isNotEmpty) {
        buffer.writeln(
          '$pad- ${node.className ?? "node"}: ${parts.join(", ")}',
        );
      }
      for (final child in node.children) {
        walk(child, indent + 1);
      }
    }

    for (final root in tree.roots) {
      walk(root, 0);
    }
    return buffer.toString();
  }

  /// 用 VLM 描述截图
  ///
  /// 做什么：把截图作为图片附件发给视觉模型，让它描述屏幕内容。
  /// 为什么复用 Attachment+Message 机制：MessagePayloadConverter 已支持
  /// 将 image 附件转为 OpenAI（image_url base64）和 Gemini（inline_data）格式，
  /// 无需新建 VisionCapableService 抽象类，直接复用现有 AiService.chat。
  ///
  /// 前置条件：截图已通过 guard.redactScreenshot 脱敏检查（见 _perceive）。
  Future<String> _describeWithVlm(AiService vlm, Uint8List image) async {
    final attachment = Attachment(
      type: 'image',
      name: 'screenshot',
      dataBase64: base64Encode(image),
      mimeType: 'image/png',
    );
    final message = Message(
      role: 'user',
      content:
          '这是手机屏幕截图。请描述屏幕上所有可点击元素、文本内容和布局，'
          '重点说明按钮、输入框、列表项等可交互元素的位置和文字。'
          '用简洁的列表格式输出。',
      attachments: [attachment],
    );
    return await vlm.chat([message]);
  }

  // ── 思考 ──

  /// 调用 LLM 获取下一步决策
  ///
  /// 为什么这样做：LLM 输出 JSON 决策，容错解析
  Future<AgentDecision?> _think(AiService llm, List<Message> history) async {
    try {
      final reply = await llm.chat(history).timeout(config.stepTimeout);
      final decision = _parseDecision(reply);
      if (decision == null) {
        // 解析失败：LLM 返回了内容但不是 JSON 格式
        // 为什么记录预览：用户能看到 LLM 实际返回了什么，便于定位
        final preview = reply.length > 300
            ? '${reply.substring(0, 300)}...'
            : reply;
        _lastThinkError = 'LLM 返回内容无法解析为 JSON。返回内容预览：\n$preview';
        AppLogger.w('[AgentService] $_lastThinkError');
      }
      return decision;
    } catch (e) {
      // 调用异常：网络/超时/API 错误等
      _lastThinkError = 'LLM 调用异常：$e';
      AppLogger.e('[AgentService] LLM 调用失败', e);
      return null;
    }
  }

  /// 解析 LLM 输出为决策
  /// 为什么这样做：LLM 输出不稳定，需容错（提取 JSON、重试）
  AgentDecision? _parseDecision(String reply) {
    if (reply.isEmpty) return null;

    // 尝试直接解析
    try {
      final json = jsonDecode(reply) as Map<String, dynamic>;
      return AgentDecision.fromJson(json);
    } catch (_) {
      // 不是纯 JSON，尝试提取 ```json 代码块
    }

    // 提取 ```json ... ``` 块
    final jsonBlock = RegExp(r'```(?:json)?\s*([\s\S]*?)```').firstMatch(reply);
    if (jsonBlock != null) {
      try {
        final json =
            jsonDecode(jsonBlock.group(1)!.trim()) as Map<String, dynamic>;
        return AgentDecision.fromJson(json);
      } catch (_) {}
    }

    // 提取第一个 { ... } 块
    final braceMatch = RegExp(r'\{[\s\S]*\}').firstMatch(reply);
    if (braceMatch != null) {
      try {
        final json = jsonDecode(braceMatch.group(0)!) as Map<String, dynamic>;
        return AgentDecision.fromJson(json);
      } catch (_) {}
    }

    AppLogger.w(
      '[AgentService] 无法解析 LLM 输出为 JSON: ${reply.substring(0, reply.length > 200 ? 200 : reply.length)}',
    );
    return null;
  }

  // ── System Prompt ──

  /// 构建 system prompt
  /// 为什么这样做：明确告诉 LLM 输出格式和规则，提高 JSON 输出稳定性
  String _buildSystemPrompt(String goal) {
    return '''你是杏铃的安卓操控 Agent。你的任务是操控用户的手机完成目标。

目标：$goal

可用工具：
${tools.toFunctionDefinitions().map((t) => '- ${t['function']['name']}: ${t['function']['description']}').join('\n')}

规则：
1. 每次只执行一个动作
2. 动作前必须说明你的思考过程
3. 不确定时返回 ask_user 动作询问用户
4. 涉及支付/删除/发送等高危操作时，系统会要求用户确认
5. 任务完成返回 done，无法完成返回 failed

输出格式（严格 JSON，不要其他内容）：
{
  "thought": "你的思考过程",
  "action": "tap|swipe|inputText|launchApp|done|failed|askUser",
  "args": {"参数": "值"},
  "summary": "仅 done/failed/askUser 时填写总结"
}''';
  }
}
