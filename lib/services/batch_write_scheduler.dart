import 'dart:async';

import '../core/logger/app_logger.dart';
import 'async_file_writer.dart';

class _PendingWrite {
  final String filePath;
  final String content;
  final bool flush;
  final bool verify;
  final Completer<bool> completer;

  _PendingWrite({
    required this.filePath,
    required this.content,
    required this.flush,
    required this.verify,
  }) : completer = Completer<bool>();
}

class BatchWriteScheduler {
  static BatchWriteScheduler? _instance;
  static BatchWriteScheduler get instance =>
      _instance ??= BatchWriteScheduler._();

  BatchWriteScheduler._();

  final Map<String, _PendingWrite> _pending = {};
  Timer? _flushTimer;
  bool _disposed = false;

  Duration _interval = const Duration(seconds: 5);
  int _threshold = 3;
  int _accumulatedCount = 0;

  int _batchedWrites = 0;
  int _directWrites = 0;
  int _flushCount = 0;

  Duration get interval => _interval;
  int get threshold => _threshold;
  int get batchedWrites => _batchedWrites;
  int get directWrites => _directWrites;
  int get flushCount => _flushCount;
  int get pendingCount => _pending.length;

  void configure({Duration? interval, int? threshold}) {
    if (interval != null) _interval = interval;
    if (threshold != null) _threshold = threshold;
    AppLogger.i(
      '[BatchScheduler] 配置更新: 间隔=${_interval.inSeconds}s, 阈值=$_threshold 条',
    );
  }

  Future<bool> schedule({
    required String filePath,
    required String content,
    bool flush = true,
    bool verify = false,
  }) {
    if (_disposed) {
      AppLogger.w('[BatchScheduler] 已关闭，拒绝调度: $filePath');
      return Future.value(false);
    }

    final existing = _pending[filePath];
    if (existing != null && !existing.completer.isCompleted) {
      _batchedWrites++;
      // 修复 P0 竞态：旧任务不再 complete(true) 虚假成功
      // 为什么这样做：原代码让旧任务收到 true，但其 content 已被新任务覆盖丢弃，
      // 调用方误以为自己的写入成功。正确做法是让旧任务的 completer 跟随新任务的真实写入结果：
      // 新任务成功 → 文件最终被更新（语义上旧任务也算成功）
      // 新任务失败 → 文件没更新，旧任务也算失败
      // 链接逻辑在下方 task 创建后执行（需要持有 task 引用）
    }

    final task = _PendingWrite(
      filePath: filePath,
      content: content,
      flush: flush,
      verify: verify,
    );

    // 若存在被合并的旧任务，将其 completer 链接到新任务的真实结果
    if (existing != null && !existing.completer.isCompleted) {
      // 用 unawaited 标记 fire-and-forget：这里只需在新任务完成时联动完成旧任务，
      // 不需要 await；catchError 防止联动逻辑异常被静默吞掉
      unawaited(
        task.completer.future
            .then((result) {
              if (!existing.completer.isCompleted) {
                existing.completer.complete(result);
              }
            })
            .catchError((Object e) {
              AppLogger.e('[BatchScheduler] 链接旧任务 completer 失败: $e');
              if (!existing.completer.isCompleted) {
                existing.completer.complete(false);
              }
            }),
      );
    }

    _pending[filePath] = task;
    _accumulatedCount++;

    if (_accumulatedCount >= _threshold) {
      _doFlush();
    } else {
      _ensureTimer();
    }

    return task.completer.future;
  }

  Future<bool> scheduleImmediate({
    required String filePath,
    required String content,
    bool flush = true,
    bool verify = false,
  }) {
    if (_disposed) {
      return Future.value(false);
    }

    _directWrites++;

    final existing = _pending.remove(filePath);
    if (existing != null && !existing.completer.isCompleted) {
      existing.completer.complete(true);
    }

    return AsyncFileWriter.instance.write(
      filePath: filePath,
      content: content,
      flush: flush,
      verify: verify,
    );
  }

  Future<void> flush() async {
    _flushTimer?.cancel();
    _flushTimer = null;
    await _doFlush();
  }

  Future<void> flushAndWait() async {
    await flush();
    await AsyncFileWriter.instance.flushAll();
  }

  /// 仅供 app 退出时调用，app 运行期间不可 dispose。
  ///
  /// 原因：dispose 后 _instance = null，再次访问会重建实例，
  /// 丢失待合并写入队列和批量统计。当前架构无任何代码调用此方法
  ///（StorageLifecycleObserver 只调 flush，不 dispose 单例）。
  void dispose() {
    _disposed = true;
    _flushTimer?.cancel();
    _flushTimer = null;

    for (final task in _pending.values) {
      if (!task.completer.isCompleted) {
        task.completer.complete(false);
      }
    }
    _pending.clear();
    _instance = null;

    AppLogger.i(
      '[BatchScheduler] 已关闭 (批量合并: $_batchedWrites, 直接写入: $_directWrites, flush次数: $_flushCount)',
    );
  }

  void _ensureTimer() {
    _flushTimer ??= Timer(_interval, () {
      _flushTimer = null;
      _doFlush();
    });
  }

  Future<void> _doFlush() async {
    if (_pending.isEmpty) return;

    _flushCount++;
    _accumulatedCount = 0;

    final tasks = Map<String, _PendingWrite>.from(_pending);
    _pending.clear();

    final futures = <Future<bool>>[];

    for (final entry in tasks.entries) {
      final task = entry.value;
      final writeFuture = AsyncFileWriter.instance.write(
        filePath: task.filePath,
        content: task.content,
        flush: task.flush,
        verify: task.verify,
      );

      writeFuture.then((result) {
        if (!task.completer.isCompleted) {
          task.completer.complete(result);
        }
      });

      futures.add(writeFuture);
    }

    await Future.wait(futures);
  }
}
