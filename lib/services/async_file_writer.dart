import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import '../core/logger/app_logger.dart';

class _WriteTask {
  final String filePath;
  final String content;
  final bool flush;
  final bool verify;
  final Completer<bool> completer;

  _WriteTask({
    required this.filePath,
    required this.content,
    this.flush = true,
    this.verify = false,
  }) : completer = Completer<bool>();
}

class AsyncFileWriter {
  static AsyncFileWriter? _instance;
  static AsyncFileWriter get instance => _instance ??= AsyncFileWriter._();

  AsyncFileWriter._();

  final Map<String, List<_WriteTask>> _queues = {};
  final Map<String, bool> _processing = {};
  bool _disposed = false;

  int _totalWrites = 0;
  int _failedWrites = 0;
  Duration _totalWriteTime = Duration.zero;

  int get totalWrites => _totalWrites;
  int get failedWrites => _failedWrites;
  Duration get totalWriteTime => _totalWriteTime;
  double get avgWriteMs =>
      _totalWrites > 0 ? _totalWriteTime.inMilliseconds / _totalWrites : 0;

  Future<bool> write({
    required String filePath,
    required String content,
    bool flush = true,
    bool verify = false,
  }) {
    if (_disposed) {
      AppLogger.w('[AsyncFileWriter] 已关闭，拒绝写入: $filePath');
      return Future.value(false);
    }

    final task = _WriteTask(
      filePath: filePath,
      content: content,
      flush: flush,
      verify: verify,
    );

    _queues.putIfAbsent(filePath, () => []).add(task);

    if (!(_processing[filePath] ?? false)) {
      _processQueue(filePath);
    }

    return task.completer.future;
  }

  Future<bool> writeJson({
    required String filePath,
    required Object data,
    bool flush = true,
    bool verify = false,
  }) {
    return write(
      filePath: filePath,
      content: jsonEncode(data),
      flush: flush,
      verify: verify,
    );
  }

  Future<void> flushAll() async {
    if (_disposed) return;

    final pendingFutures = <Future<bool>>[];
    for (final queue in _queues.entries) {
      for (final task in queue.value) {
        if (!task.completer.isCompleted) {
          pendingFutures.add(task.completer.future);
        }
      }
    }

    if (pendingFutures.isNotEmpty) {
      await Future.wait(pendingFutures);
    }
  }

  /// 仅供 app 退出时调用，app 运行期间不可 dispose。
  ///
  /// 原因：dispose 后 _instance = null，再次访问会重建实例，
  /// 丢失待写入队列状态和写入统计。当前架构无任何代码调用此方法
  ///（StorageLifecycleObserver 只调 flushAll，不 dispose 单例）。
  void dispose() {
    _disposed = true;

    // 修复 P0 hang：先完成所有待写入任务的 completer，再清空队列
    // 为什么这样做：原代码直接 _queues.clear() 丢弃待写入任务，但这些任务的
    // completer 从未被 complete，await 它们的调用方会永远 hang。
    // 正在 Isolate 中执行的任务（_processing 为 true 的那个）会由 _executeWrite
    // 完成时自动 complete，无需在此处理；这里只处理队列中尚未开始的任务。
    for (final queue in _queues.values) {
      for (final task in queue) {
        if (!task.completer.isCompleted) {
          task.completer.complete(false);
        }
      }
    }

    _queues.clear();
    _processing.clear();
    _instance = null;
    AppLogger.i(
      '[AsyncFileWriter] 已关闭 (总写入: $_totalWrites, 失败: $_failedWrites, 平均耗时: ${avgWriteMs.toStringAsFixed(1)}ms)',
    );
  }

  void _processQueue(String filePath) {
    final queue = _queues[filePath];
    if (queue == null || queue.isEmpty) {
      _processing[filePath] = false;
      return;
    }

    _processing[filePath] = true;

    final task = queue.removeAt(0);
    _executeWrite(task).then((_) {
      _processQueue(filePath);
    });
  }

  Future<void> _executeWrite(_WriteTask task) async {
    final sw = Stopwatch()..start();

    try {
      final filePath = task.filePath;
      final content = task.content;
      final flush = task.flush;
      final verify = task.verify;

      final result = await Isolate.run(() async {
        try {
          final file = File(filePath);
          final dir = file.parent;
          if (!dir.existsSync()) {
            dir.createSync(recursive: true);
          }

          file.writeAsStringSync(content, flush: flush);

          if (verify) {
            final readBack = file.readAsStringSync();
            if (readBack != content) {
              return false;
            }
          }

          return true;
        } catch (e) {
          return false;
        }
      });

      sw.stop();
      _totalWrites++;
      _totalWriteTime += sw.elapsed;

      if (!result) {
        _failedWrites++;
        AppLogger.e('[AsyncFileWriter] 写入验证失败: ${task.filePath}');
      }

      if (sw.elapsedMilliseconds > 10) {
        AppLogger.w(
          '[AsyncFileWriter] 慢写入警告: ${task.filePath} 耗时 ${sw.elapsedMilliseconds}ms',
        );
      }

      task.completer.complete(result);
    } catch (e) {
      sw.stop();
      _totalWrites++;
      _failedWrites++;
      _totalWriteTime += sw.elapsed;

      AppLogger.e('[AsyncFileWriter] Isolate 写入异常: ${task.filePath}', e);
      task.completer.complete(false);
    }
  }
}
