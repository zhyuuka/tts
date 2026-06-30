import '../../core/logger/app_logger.dart';

class PerfSpan {
  final String name;
  final DateTime startTime;
  DateTime? endTime;
  String? metadata;
  bool get isFinished => endTime != null;
  Duration get duration =>
      endTime != null ? endTime!.difference(startTime) : Duration.zero;

  PerfSpan({required this.name, required this.startTime});
}

class PerfRecord {
  final String name;
  final Duration duration;
  final DateTime timestamp;
  final String? metadata;

  const PerfRecord({
    required this.name,
    required this.duration,
    required this.timestamp,
    this.metadata,
  });

  double get durationMs => duration.inMicroseconds / 1000.0;

  @override
  String toString() =>
      '[$name] ${durationMs.toStringAsFixed(1)}ms${metadata != null ? " ($metadata)" : ""}';
}

class PerformanceMonitor {
  static PerformanceMonitor? _instance;
  static PerformanceMonitor get instance =>
      _instance ??= PerformanceMonitor._();

  PerformanceMonitor._();

  final Map<String, PerfSpan> _activeSpans = {};
  final List<PerfRecord> _history = [];
  static const int _maxHistory = 500;

  bool _enabled = false;

  bool get enabled => _enabled;
  int get activeSpanCount => _activeSpans.length;
  int get historyCount => _history.length;

  void enable() {
    _enabled = true;
    AppLogger.i('[PerfMonitor] 性能监控已启用');
  }

  void disable() {
    _enabled = false;
    AppLogger.i('[PerfMonitor] 性能监控已关闭');
  }

  PerfSpan startSpan(String name, {String? metadata}) {
    final span = PerfSpan(name: name, startTime: DateTime.now())
      ..metadata = metadata;

    if (_enabled) {
      _activeSpans[name] = span;
    }

    return span;
  }

  void endSpan(String name, {String? metadata}) {
    final span = _activeSpans.remove(name);
    if (span == null) return;

    span.endTime = DateTime.now();
    if (metadata != null) span.metadata = metadata;

    final record = PerfRecord(
      name: span.name,
      duration: span.duration,
      timestamp: span.startTime,
      metadata: span.metadata,
    );

    _history.add(record);
    if (_history.length > _maxHistory) {
      _history.removeRange(0, _history.length - _maxHistory);
    }

    if (_enabled && span.duration.inMilliseconds > 100) {
      AppLogger.w('[PerfMonitor] 慢操作: $record');
    }
  }

  Future<T> trace<T>(
    String name,
    Future<T> Function() fn, {
    String? metadata,
  }) async {
    startSpan(name, metadata: metadata);
    try {
      final result = await fn();
      endSpan(name);
      return result;
    } catch (e) {
      endSpan(name, metadata: 'ERROR: $e');
      rethrow;
    }
  }

  T traceSync<T>(String name, T Function() fn, {String? metadata}) {
    startSpan(name, metadata: metadata);
    try {
      final result = fn();
      endSpan(name);
      return result;
    } catch (e) {
      endSpan(name, metadata: 'ERROR: $e');
      rethrow;
    }
  }

  List<PerfRecord> getHistory({String? namePrefix, int? limit}) {
    var records = _history.toList().reversed.toList();

    if (namePrefix != null) {
      records = records.where((r) => r.name.startsWith(namePrefix)).toList();
    }

    if (limit != null) {
      records = records.take(limit).toList();
    }

    return records;
  }

  Map<String, dynamic> getStats({String? namePrefix}) {
    var records = _history.toList();
    if (namePrefix != null) {
      records = records.where((r) => r.name.startsWith(namePrefix)).toList();
    }

    if (records.isEmpty) {
      return {'count': 0, 'avgMs': 0.0, 'maxMs': 0.0, 'p95Ms': 0.0};
    }

    final durations = records.map((r) => r.duration.inMicroseconds).toList()
      ..sort();
    final total = durations.reduce((a, b) => a + b);
    final avg = total / durations.length;
    final p95Idx = (durations.length * 0.95).toInt().clamp(
      0,
      durations.length - 1,
    );

    return {
      'count': durations.length,
      'avgMs': avg / 1000.0,
      'maxMs': durations.last / 1000.0,
      'minMs': durations.first / 1000.0,
      'p95Ms': durations[p95Idx] / 1000.0,
    };
  }

  Map<String, Map<String, dynamic>> getGroupedStats() {
    final groups = <String, List<PerfRecord>>{};
    for (final record in _history) {
      final group = record.name.split('.').first;
      groups.putIfAbsent(group, () => []).add(record);
    }

    return groups.map((key, records) {
      final durations = records.map((r) => r.duration.inMicroseconds).toList()
        ..sort();
      final total = durations.reduce((a, b) => a + b);

      return MapEntry(key, {
        'count': durations.length,
        'avgMs': total / durations.length / 1000.0,
        'maxMs': durations.last / 1000.0,
      });
    });
  }

  void clearHistory() {
    _history.clear();
    _activeSpans.clear();
  }

  void dispose() {
    _enabled = false;
    _history.clear();
    _activeSpans.clear();
    _instance = null;
  }
}
