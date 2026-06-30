import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;
import 'package:path_provider/path_provider.dart';

import '../../core/logger/app_logger.dart';

/// 调试日志条目
///
/// 做什么：承载一条调试日志的所有信息（分类/消息/时间/附加数据/级别）。
/// 为什么这样做：统一日志结构，便于格式化输出和过滤。
class DebugLogEntry {
  final String category;
  final String message;
  final DateTime timestamp;
  final Map<String, dynamic>? data;
  // 日志级别（INFO/WARN/ERROR），为什么加：合并自 DebugService，
  // 启动日志和崩溃日志需要区分级别，不受 enabled 开关控制
  final String level;

  const DebugLogEntry({
    required this.category,
    required this.message,
    required this.timestamp,
    this.data,
    this.level = 'INFO',
  });

  String format() {
    final time = timestamp.toIso8601String().substring(11, 23);
    var line = '[$time][$level][$category] $message';
    if (data != null && data!.isNotEmpty) {
      line += '\n  ${const JsonEncoder.withIndent('  ').convert(data)}';
    }
    return line;
  }
}

/// 统一调试服务（合并自原 DebugService + DebugModeService）
///
/// 做什么：提供应用全生命周期的调试日志记录、请求日志、记忆注入日志、
/// 搜索上下文日志、文件导出、诊断摘要等功能。
///
/// 为什么合并：原 DebugService（启动日志）与 DebugModeService（调试日志）
/// 职责重叠，都是内存缓冲 + 格式化 + 导出。合并后减少代码重复，统一日志入口。
///
/// 日志记录分两类：
/// 1. **启动/崩溃日志**（logAlways/info/warn/error）：无条件记录，enabled=false 也记录。
///    为什么这样做：启动阶段 enabled 还未配置，但崩溃日志必须保留用于诊断。
/// 2. **调试日志**（log/logRequest/logMemoryInjection 等）：受 enabled 开关控制。
///    为什么这样做：开发者主动记录的详细日志，仅在调试模式开启时记录，避免性能影响。
class DebugModeService {
  static DebugModeService? _instance;
  static DebugModeService get instance => _instance ??= DebugModeService._();

  DebugModeService._();

  bool _enabled = false;
  bool _logRequests = false;
  bool _logMemoryInjection = false;
  bool _logSearchContext = false;

  /// 是否已 dispose。
  /// 为什么这样做：dispose 后再调用写入类方法应快速失败，避免静默丢失日志。
  /// getter（enabled/logs 等）不加保护，保留诊断能力。
  bool _disposed = false;

  final List<DebugLogEntry> _logs = [];
  static const int _maxLogs = 1000;

  final List<Map<String, dynamic>> _requestLog = [];
  static const int _maxRequestLog = 100;

  bool get enabled => _enabled;
  bool get isLogRequests => _logRequests;
  bool get isLogMemoryInjection => _logMemoryInjection;
  bool get isLogSearchContext => _logSearchContext;
  List<DebugLogEntry> get logs => List.unmodifiable(_logs);
  List<Map<String, dynamic>> get requestLog => List.unmodifiable(_requestLog);

  // ── 兼容 DebugService 接口的 getter ──
  // 为什么保留：app_bootstrap.dart 等调用方使用 logCount/allLogs/enabled 接口

  /// 日志条数（兼容 DebugService 接口）
  int get logCount => _logs.length;

  /// 所有日志的格式化字符串列表（兼容 DebugService 接口）
  List<String> get allLogs => _logs.map((e) => e.format()).toList();

  void configure({
    bool? enabled,
    bool? logRequests,
    bool? logMemoryInjection,
    bool? logSearchContext,
  }) {
    if (_disposed) return;
    if (enabled != null) _enabled = enabled;
    if (logRequests != null) _logRequests = logRequests;
    if (logMemoryInjection != null) _logMemoryInjection = logMemoryInjection;
    if (logSearchContext != null) _logSearchContext = logSearchContext;

    AppLogger.i(
      '[DebugMode] 配置更新: enabled=$_enabled, requests=$_logRequests, memory=$_logMemoryInjection, search=$_logSearchContext',
    );
  }

  // ── 启动/崩溃日志（无条件记录，合并自 DebugService）──
  //
  // 做什么：提供 log/info/warn/error 方法，无论 enabled 是否开启都记录。
  // 为什么这样做：启动阶段 enabled 还未配置，但启动日志和崩溃日志必须保留，
  // 否则 release 模式下出问题无法诊断。debugPrint 同步输出到控制台便于开发期查看。

  /// 无条件记录日志（带级别）
  ///
  /// 做什么：把日志加入内存缓冲并输出到 debugPrint，不受 enabled 控制。
  /// 为什么这样做：启动日志/崩溃日志必须无条件保留，否则诊断失效。
  void logAlways(String category, String message, {String level = 'INFO'}) {
    // 不检查 _disposed：崩溃日志即使在 dispose 后也应尝试记录
    _addLog(category, message, level: level);
    debugPrint('[$level][$category] $message');
  }

  /// 记录 INFO 级日志（无条件）
  void info(String tag, String message) =>
      logAlways(tag, message, level: 'INFO');

  /// 记录 WARN 级日志（无条件）
  void warn(String tag, String message) =>
      logAlways(tag, message, level: 'WARN');

  /// 记录 ERROR 级日志（无条件）
  void error(String tag, String message) =>
      logAlways(tag, message, level: 'ERROR');

  // ── 调试日志（受 enabled 控制）──

  void logRequest({
    required String service,
    required String endpoint,
    required Map<String, dynamic> requestBody,
    int? statusCode,
    Map<String, dynamic>? responseBody,
    Duration? duration,
    String? error,
  }) {
    if (_disposed) return;
    if (!_logRequests) return;

    final entry = {
      'service': service,
      'endpoint': endpoint,
      'requestSize': jsonEncode(requestBody).length,
      'statusCode': statusCode,
      'responseSize': responseBody != null
          ? jsonEncode(responseBody).length
          : null,
      'durationMs': duration?.inMilliseconds,
      'error': error,
      'timestamp': DateTime.now().toIso8601String(),
    };

    _requestLog.add(entry);
    if (_requestLog.length > _maxRequestLog) {
      _requestLog.removeRange(0, _requestLog.length - _maxRequestLog);
    }

    _addLog(
      'request',
      '$service $endpoint → ${statusCode ?? "pending"}${duration != null ? " (${duration.inMilliseconds}ms)" : ""}',
      data: entry,
    );
  }

  void logMemoryInjection({
    required String conversationId,
    required int memoryCount,
    required List<String> memorySummaries,
    String? source,
  }) {
    if (_disposed) return;
    if (!_logMemoryInjection) return;

    _addLog(
      'memory',
      '注入 $memoryCount 条记忆到会话 $conversationId',
      data: {
        'conversationId': conversationId,
        'memoryCount': memoryCount,
        'summaries': memorySummaries.take(5).toList(),
        'source': source ?? 'unknown',
      },
    );
  }

  void logSearchContext({
    required String query,
    required String engine,
    required int resultCount,
    String? contextPreview,
  }) {
    if (_disposed) return;
    if (!_logSearchContext) return;

    _addLog(
      'search',
      '搜索 "$query" ($engine) → $resultCount 条结果',
      data: {
        'query': query,
        'engine': engine,
        'resultCount': resultCount,
        'preview': contextPreview?.substring(
          0,
          (contextPreview.length).clamp(0, 200),
        ),
      },
    );
  }

  void logStreamChunk({
    required String service,
    required int chunkIndex,
    required String content,
    String? reasoningContent,
  }) {
    if (_disposed) return;
    if (!_enabled) return;

    _addLog(
      'stream',
      '$service chunk#$chunkIndex: "${content.substring(0, content.length.clamp(0, 50))}"',
      data: {
        if (reasoningContent != null)
          'reasoning': reasoningContent.substring(
            0,
            reasoningContent.length.clamp(0, 100),
          ),
      },
    );
  }

  /// 记录调试日志（受 enabled 控制）
  ///
  /// 做什么：开发者主动记录的调试日志，仅在 enabled=true 时记录。
  /// 为什么受控：调试日志量大，release 模式下不应记录以避免性能影响。
  void log(String category, String message, {Map<String, dynamic>? data}) {
    if (_disposed) return;
    if (!_enabled) return;
    _addLog(category, message, data: data);
  }

  void _addLog(
    String category,
    String message, {
    Map<String, dynamic>? data,
    String level = 'INFO',
  }) {
    _logs.add(
      DebugLogEntry(
        category: category,
        message: message,
        timestamp: DateTime.now(),
        data: data,
        level: level,
      ),
    );

    if (_logs.length > _maxLogs) {
      _logs.removeRange(0, _logs.length - _maxLogs);
    }
  }

  /// 导出日志为字符串（合并自 DebugModeService.exportLogs）
  String exportLogs() {
    return _logs.map((l) => l.format()).join('\n');
  }

  /// 导出日志到文件（合并自 DebugService.exportLogs）
  ///
  /// 做什么：把内存中的日志写入外部存储的 `logs/debug_<timestamp>.log` 文件。
  /// 为什么这样做：用户反馈问题时可提供日志文件，便于离线分析。
  /// 返回文件路径，失败返回 null。
  Future<String?> exportLogsToFile() async {
    try {
      final directory = await getExternalStorageDirectory();
      if (directory == null) return null;

      final logDir = Directory('${directory.path}/logs');
      if (!await logDir.exists()) {
        await logDir.create(recursive: true);
      }

      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final filePath = '${logDir.path}/debug_$timestamp.log';

      final buffer = StringBuffer();
      buffer.writeln('=== 杏铃调试日志 ===');
      buffer.writeln('导出时间: ${DateTime.now().toIso8601String()}');
      buffer.writeln('日志条数: ${_logs.length}');
      buffer.writeln('');

      for (final entry in _logs) {
        buffer.writeln(entry.format());
      }

      await File(filePath).writeAsString(buffer.toString());
      info('DebugMode', '日志已导出到: $filePath');
      return filePath;
    } catch (e) {
      debugPrint('导出日志失败: $e');
      return null;
    }
  }

  /// 获取关键诊断信息摘要（合并自 DebugService.getDiagnosticSummary）
  ///
  /// 做什么：汇总存储/设置/AI/消息/屏幕等关键状态 + 最近 10 条日志。
  /// 为什么这样做：用户反馈问题时一键复制诊断信息，无需手动收集。
  String getDiagnosticSummary({
    required bool storageReady,
    required bool settingsReady,
    required String? aiServiceId,
    required bool hasApiKey,
    required int messageCount,
    required String screenInfo,
  }) {
    return '--- 诊断摘要 ---\n'
        '时间: ${DateTime.now().toIso8601String()}\n'
        '存储服务: ${storageReady ? "正常" : "未初始化"}\n'
        '设置服务: ${settingsReady ? "正常" : "未初始化"}\n'
        'AI服务ID: ${aiServiceId ?? "未知"}\n'
        'API Key: ${hasApiKey ? "已配置" : "未配置"}\n'
        '消息数量: $messageCount\n'
        '屏幕信息: $screenInfo\n'
        '构建模式: ${kDebugMode ? "debug" : "release"}\n'
        '日志条数: ${_logs.length}\n'
        '--- 最近日志 ---\n'
        '${_logs.length > 10 ? _logs.sublist(_logs.length - 10).map((e) => e.format()).join('\n') : _logs.map((e) => e.format()).join('\n')}';
  }

  /// 清空所有日志（兼容 DebugService.clear 接口）
  void clear() {
    if (_disposed) return;
    _logs.clear();
    _requestLog.clear();
  }

  /// 清空所有日志（原 DebugModeService 接口，保留为 clear 的别名）
  void clearLogs() => clear();

  /// 仅供 app 退出时调用，app 运行期间不可 dispose。
  ///
  /// 原因：dispose 后 _instance = null，再次访问会重建实例，
  /// 丢失已收集的日志和统计。当前架构无任何代码调用此方法
  ///（StorageLifecycleObserver 只调 flushPendingWrites，不 dispose 单例）。
  /// 为什么加 _disposed 标志：与 AsyncFileWriter/BatchWriteScheduler 保持一致，
  /// dispose 后再调用写入类方法快速失败，避免静默丢失日志。
  void dispose() {
    _disposed = true;
    _enabled = false;
    _logs.clear();
    _requestLog.clear();
    _instance = null;
  }
}
