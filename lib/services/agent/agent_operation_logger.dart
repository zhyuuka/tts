import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../../core/logger/app_logger.dart';
import '../../models/agent/agent_action.dart';
import '../../models/agent/agent_step.dart';
import '../../models/agent/agent_task.dart';
import 'agent_safety_guard.dart';

/// Agent 操作日志持久化
///
/// 职责：将每个任务的每一步操作记录到文件，便于审计。
/// 为什么单独成类：
/// 1. Agent 操控手机属于敏感操作，必须可审计
/// 2. 独立于 AppLogger（AppLogger 是运行时日志，不持久化操作语义）
/// 3. 操作内容需独立脱敏（如输入的密码），AppLogger 通用脱敏不够
///
/// 存储结构：
/// `xingling_data/agent_logs/`
///   ├── `<taskId>.json`   # 单个任务的完整日志
///   └── `index.json`      # 任务索引（最近 100 条）
class AgentOperationLogger {
  AgentOperationLogger(this._safetyGuard);

  final AgentSafetyGuard _safetyGuard;

  /// 日志保留天数（超过自动清理）
  static const int retentionDays = 30;

  /// 索引文件最大条目数
  static const int maxIndexEntries = 100;

  Directory? _logDir;

  /// 初始化日志目录
  /// 为什么这样做：延迟初始化，避免启动时 IO
  Future<void> init() async {
    if (_logDir != null) return;
    try {
      final docDir = await getApplicationDocumentsDirectory();
      _logDir = Directory('${docDir.path}/xingling_data/agent_logs');
      if (!_logDir!.existsSync()) {
        await _logDir!.create(recursive: true);
      }
      AppLogger.i('[AgentLogger] 日志目录: ${_logDir!.path}');
    } catch (e) {
      AppLogger.e('[AgentLogger] 初始化失败', e);
    }
  }

  /// 记录任务开始
  Future<void> logTaskStart(AgentTask task) async {
    await init();
    final file = _taskFile(task.id);
    final entry = {
      'event': 'task_start',
      'timestamp': DateTime.now().toIso8601String(),
      'task': task.toJson(),
    };
    await _appendLine(file, entry);
    await _updateIndex(task, started: true);
  }

  /// 记录单步操作
  ///
  /// [decision] LLM 决策（含思考、动作、参数）
  /// [success] 执行是否成功
  /// [error] 失败原因（成功时为 null）
  Future<void> logStep(
    String taskId,
    int stepIndex,
    AgentDecision decision,
    bool success, {
    String? error,
  }) async {
    final file = _taskFile(taskId);

    // 脱敏处理：输入文本可能含密码
    final sanitizedArgs = _sanitizeArgs(decision);

    final entry = {
      'event': 'step',
      'timestamp': DateTime.now().toIso8601String(),
      'step': stepIndex,
      'thought': decision.thought,
      'action': decision.action.wireName,
      'args': sanitizedArgs,
      'success': success,
      'error': error,
    };
    await _appendLine(file, entry);
  }

  /// 记录任务结束
  Future<void> logTaskEnd(
    String taskId, {
    required AgentTaskState state,
    String? summary,
    String? error,
  }) async {
    final file = _taskFile(taskId);
    final entry = {
      'event': 'task_end',
      'timestamp': DateTime.now().toIso8601String(),
      'state': state.name,
      'summary': summary,
      'error': error,
    };
    await _appendLine(file, entry);
    await _updateIndex(
      AgentTask(
        id: taskId,
        goal: '',
        aiServiceId: '',
        createdAt: DateTime.now(),
        state: state,
        finishedAt: DateTime.now(),
        summary: summary,
        error: error,
      ),
      started: false,
    );
  }

  /// 读取任务日志（用于 UI 展示）
  Future<List<AgentStep>> readTaskLog(String taskId) async {
    await init();
    final file = _taskFile(taskId);
    if (!file.existsSync()) return const [];

    try {
      final lines = file.readAsLinesSync();
      final steps = <AgentStep>[];
      for (final line in lines) {
        if (line.trim().isEmpty) continue;
        try {
          final map = jsonDecode(line) as Map<String, dynamic>;
          if (map['event'] == 'step') {
            steps.add(_parseStepFromLog(map));
          }
        } catch (_) {
          // 跳过格式错误的行
        }
      }
      return steps;
    } catch (e) {
      AppLogger.e('[AgentLogger] 读取日志失败: $taskId', e);
      return const [];
    }
  }

  /// 读取任务索引（用于历史列表）
  Future<List<Map<String, dynamic>>> readIndex() async {
    await init();
    final indexFile = File('${_logDir!.path}/index.json');
    if (!indexFile.existsSync()) return const [];

    try {
      final content = indexFile.readAsStringSync();
      final list = jsonDecode(content) as List;
      return list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } catch (e) {
      AppLogger.e('[AgentLogger] 读取索引失败', e);
      return const [];
    }
  }

  /// 清理过期日志（超过 retentionDays 天）
  /// 为什么这样做：避免日志无限增长占用存储
  Future<void> cleanupExpired() async {
    await init();
    final cutoff = DateTime.now().subtract(Duration(days: retentionDays));
    try {
      final files = _logDir!.listSync();
      for (final entity in files) {
        if (entity is! File) continue;
        final stat = entity.statSync();
        if (stat.modified.isBefore(cutoff)) {
          await entity.delete();
        }
      }
      AppLogger.i('[AgentLogger] 过期日志清理完成');
    } catch (e) {
      AppLogger.e('[AgentLogger] 清理失败', e);
    }
  }

  /// 清空全部日志
  /// 做什么：删除日志目录下所有文件并重建索引。
  /// 为什么这样做：用户可能想释放存储空间或清除历史记录。
  Future<void> clearAll() async {
    await init();
    try {
      final dir = _logDir!;
      if (dir.existsSync()) {
        // 删除整个目录后重建，比逐个删除更彻底
        await dir.delete(recursive: true);
        await dir.create(recursive: true);
      }
      AppLogger.i('[AgentLogger] 已清空全部日志');
    } catch (e) {
      AppLogger.e('[AgentLogger] 清空日志失败', e);
    }
  }

  /// 删除单个任务日志
  /// 做什么：删除指定 taskId 的日志文件，并从索引中移除该条目。
  /// 为什么这样做：用户可能想删除特定任务的历史记录，而非全部清空。
  Future<void> deleteTask(String taskId) async {
    await init();
    try {
      final file = _taskFile(taskId);
      if (file.existsSync()) {
        await file.delete();
      }
      // 从索引中移除该条目
      final index = await readIndex();
      index.removeWhere((e) => e['id'] == taskId);
      final indexFile = File('${_logDir!.path}/index.json');
      await indexFile.writeAsString(jsonEncode(index));
      AppLogger.i('[AgentLogger] 已删除任务日志: $taskId');
    } catch (e) {
      AppLogger.e('[AgentLogger] 删除任务日志失败', e);
    }
  }

  // ── 内部工具 ──

  File _taskFile(String taskId) {
    final dir = _logDir!;
    return File('${dir.path}/$taskId.json');
  }

  /// 追加一行 JSON 到文件
  /// 为什么用行追加而非整体重写：避免大文件全量读写，性能更好
  Future<void> _appendLine(File file, Map<String, dynamic> entry) async {
    try {
      final sink = file.openWrite(mode: FileMode.writeOnlyAppend);
      sink.writeln(jsonEncode(entry));
      await sink.flush();
      await sink.close();
    } catch (e) {
      AppLogger.e('[AgentLogger] 写入失败', e);
    }
  }

  /// 更新索引文件
  ///
  /// 为什么保留原有 goal 和 createdAt：logTaskEnd 传入的 AgentTask
  /// goal 为空、createdAt 为当前时间，直接覆盖会丢失任务开始时写入的信息。
  Future<void> _updateIndex(AgentTask task, {required bool started}) async {
    try {
      final indexFile = File('${_logDir!.path}/index.json');
      List<Map<String, dynamic>> entries = [];
      if (indexFile.existsSync()) {
        final content = indexFile.readAsStringSync();
        if (content.isNotEmpty) {
          final list = jsonDecode(content) as List;
          entries = list
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList();
        }
      }

      // 保留原有条目的 goal 和 createdAt（logTaskEnd 传入空 goal 会覆盖）
      String? existingGoal;
      String? existingCreatedAt;
      for (final e in entries) {
        if (e['id'] == task.id) {
          existingGoal = e['goal'] as String?;
          existingCreatedAt = e['createdAt'] as String?;
          break;
        }
      }

      // 移除同 ID 旧条目
      entries.removeWhere((e) => e['id'] == task.id);

      // 添加新条目到头部
      entries.insert(0, {
        'id': task.id,
        'goal': task.goal.isNotEmpty ? task.goal : (existingGoal ?? ''),
        'state': task.state.name,
        'createdAt': started
            ? task.createdAt.toIso8601String()
            : (existingCreatedAt ?? task.createdAt.toIso8601String()),
        'finishedAt': task.finishedAt?.toIso8601String(),
        'summary': task.summary,
      });

      // 限制条目数
      if (entries.length > maxIndexEntries) {
        entries = entries.sublist(0, maxIndexEntries);
      }

      await indexFile.writeAsString(jsonEncode(entries));
    } catch (e) {
      AppLogger.e('[AgentLogger] 更新索引失败', e);
    }
  }

  /// 脱敏动作参数（用于日志）
  /// 为什么这样做：inputText 的 text 可能是密码，必须遮蔽
  Map<String, dynamic> _sanitizeArgs(AgentDecision decision) {
    final args = Map<String, dynamic>.from(decision.args);
    if (decision.action == AgentActionType.inputText) {
      final text = (args['text'] as String?) ?? '';
      args['text'] = _safetyGuard.redactForLog(text);
    }
    return args;
  }

  AgentStep _parseStepFromLog(Map<String, dynamic> map) {
    final actionType =
        AgentActionType.fromWire(map['action'] as String?) ??
        AgentActionType.failed;
    return AgentStep(
      index: (map['step'] as num?)?.toInt() ?? 0,
      state: AgentStepState.stepDone,
      thought: map['thought'] as String?,
      decision: AgentDecision(
        thought: (map['thought'] as String?) ?? '',
        action: actionType,
        args: const {},
      ),
      success: (map['success'] as bool?) ?? false,
      error: map['error'] as String?,
      timestamp:
          DateTime.tryParse(map['timestamp'] as String? ?? '') ??
          DateTime.now(),
    );
  }
}
