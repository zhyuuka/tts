import 'dart:async';

import 'package:hive/hive.dart';

import '../core/logger/app_logger.dart';
import 'memu_service.dart';
import 'persona_snapshot_service.dart';

class HiveIntegrityChecker {
  static HiveIntegrityChecker? _instance;
  static HiveIntegrityChecker get instance =>
      _instance ??= HiveIntegrityChecker._();

  HiveIntegrityChecker._();

  Timer? _periodicTimer;
  DateTime? _lastCheckTime;
  Duration _checkInterval = const Duration(minutes: 30);

  final Map<String, bool> _boxHealth = {};
  int _totalChecks = 0;
  int _failedChecks = 0;

  int get totalChecks => _totalChecks;
  int get failedChecks => _failedChecks;
  DateTime? get lastCheckTime => _lastCheckTime;
  Duration get checkInterval => _checkInterval;
  Map<String, bool> get boxHealth => Map.unmodifiable(_boxHealth);

  void configure({Duration? interval}) {
    if (interval != null) _checkInterval = interval;
  }

  void startPeriodicCheck() {
    _periodicTimer?.cancel();
    _periodicTimer = Timer.periodic(_checkInterval, (_) {
      runFullCheck();
    });
    AppLogger.i('[HiveIntegrity] 定期检查已启动，间隔: ${_checkInterval.inMinutes} 分钟');
  }

  void stopPeriodicCheck() {
    _periodicTimer?.cancel();
    _periodicTimer = null;
    AppLogger.i('[HiveIntegrity] 定期检查已停止');
  }

  static const List<String> _knownBoxNames = [
    'memu_memory',
    'memlocal_conversations',
    'memlocal_messages',
    'memlocal_fragments',
    'memlocal_wal',
  ];

  Future<Map<String, HiveCheckResult>> runFullCheck() async {
    final results = <String, HiveCheckResult>{};
    _lastCheckTime = DateTime.now();

    final boxNames = _knownBoxNames
        .where((name) => Hive.isBoxOpen(name))
        .toList();
    AppLogger.i('[HiveIntegrity] 开始完整性检查，共 ${boxNames.length} 个 Box (已打开)');

    for (final name in boxNames) {
      try {
        final result = await _checkBox(name);
        results[name] = result;
        _boxHealth[name] = result.isHealthy;
        _totalChecks++;

        if (!result.isHealthy) {
          _failedChecks++;
          AppLogger.w(
            '[HiveIntegrity] Box "$name" 不健康: ${result.issues.join(", ")}',
          );
        }
      } catch (e) {
        results[name] = HiveCheckResult(
          boxName: name,
          isHealthy: false,
          issues: ['检查异常: $e'],
          entryCount: 0,
          corruptEntries: 0,
        );
        _boxHealth[name] = false;
        _totalChecks++;
        _failedChecks++;
        AppLogger.e('[HiveIntegrity] Box "$name" 检查异常: $e');
      }
    }

    final healthyCount = results.values.where((r) => r.isHealthy).length;
    AppLogger.i(
      '[HiveIntegrity] 检查完成: $healthyCount/${results.length} 个 Box 健康',
    );

    return results;
  }

  Future<HiveCheckResult> _checkBox(String boxName) async {
    final issues = <String>[];
    int corruptEntries = 0;

    Box? box;
    try {
      box = Hive.box(boxName);
    } catch (e) {
      try {
        box = await Hive.openBox(boxName);
      } catch (openError) {
        return HiveCheckResult(
          boxName: boxName,
          isHealthy: false,
          issues: ['无法打开 Box: $openError'],
          entryCount: 0,
          corruptEntries: 0,
        );
      }
    }

    if (!box.isOpen) {
      return HiveCheckResult(
        boxName: boxName,
        isHealthy: false,
        issues: ['Box 未打开'],
        entryCount: 0,
        corruptEntries: 0,
      );
    }

    final entryCount = box.length;

    for (final key in box.keys) {
      try {
        final value = box.get(key);
        if (value == null) continue;

        if (value is Map) {
          _validateMapEntry(key, value, issues);
        } else if (value is String) {
          if (value.isEmpty && key.toString().startsWith('conv_')) {
            issues.add('空字符串值: key=$key');
            corruptEntries++;
          }
        }
      } catch (e) {
        issues.add('读取异常: key=$key, error=$e');
        corruptEntries++;
      }
    }

    if (box.length > 1000) {
      issues.add('Box 条目数过多 (${box.length})，建议清理');
    }

    return HiveCheckResult(
      boxName: boxName,
      isHealthy: issues.isEmpty,
      issues: issues,
      entryCount: entryCount,
      corruptEntries: corruptEntries,
    );
  }

  void _validateMapEntry(dynamic key, Map value, List<String> issues) {
    if (value.containsKey('id')) {
      final id = value['id'];
      if (id is! String || id.isEmpty) {
        issues.add('无效 ID: key=$key, id=$id');
      }
    }

    if (value.containsKey('createdAt')) {
      final createdAt = value['createdAt'];
      if (createdAt is String) {
        try {
          DateTime.parse(createdAt);
        } catch (_) {
          issues.add('无效时间格式: key=$key, createdAt=$createdAt');
        }
      }
    }

    if (value.containsKey('importance')) {
      final importance = value['importance'];
      if (importance is num) {
        if (importance < 0 || importance > 1) {
          issues.add('重要性评分越界: key=$key, importance=$importance');
        }
      }
    }
  }

  Future<bool> repairBox(String boxName) async {
    try {
      final box = Hive.box(boxName);
      if (!box.isOpen) return false;

      final keysToDelete = <dynamic>[];

      for (final key in box.keys) {
        try {
          final value = box.get(key);
          if (value == null) {
            keysToDelete.add(key);
            continue;
          }
        } catch (e) {
          keysToDelete.add(key);
          AppLogger.w('[HiveIntegrity] 标记损坏条目: key=$key');
        }
      }

      // 修复前：如果损坏的是记忆Box，先创建快照保护
      if (keysToDelete.isNotEmpty && boxName == 'memu_memory') {
        await _snapshotBeforeRepair(box, keysToDelete);
      }

      for (final key in keysToDelete) {
        await box.delete(key);
      }

      if (keysToDelete.isNotEmpty) {
        AppLogger.i(
          '[HiveIntegrity] 修复 Box "$boxName": 删除 ${keysToDelete.length} 个损坏条目',
        );
      }

      _boxHealth[boxName] = true;
      return true;
    } catch (e) {
      AppLogger.e('[HiveIntegrity] 修复 Box "$boxName" 失败: $e');
      return false;
    }
  }

  /// 修复前对即将删除的记忆条目创建快照
  Future<void> _snapshotBeforeRepair(
    Box box,
    List<dynamic> keysToDelete,
  ) async {
    try {
      final snapshotService = PersonaSnapshotService.instance;
      if (!snapshotService.isInitialized) return;

      final byConv = <String, List<Map<String, dynamic>>>{};
      for (final key in keysToDelete) {
        try {
          final value = box.get(key);
          if (value is Map<String, dynamic> &&
              value.containsKey('conversationId')) {
            final convId = value['conversationId'] as String? ?? '';
            if (convId.isNotEmpty) {
              byConv.putIfAbsent(convId, () => []).add(value);
            }
          }
        } catch (_) {
          // 无法读取的条目跳过
        }
      }

      for (final entry in byConv.entries) {
        await snapshotService.createSnapshot(
          conversationId: entry.key,
          conversationName: 'Hive修复前备份',
          systemPrompt: '',
          personaMemories: entry.value
              .map((m) {
                try {
                  return MemoryFragment.fromJson(m);
                } catch (_) {
                  return null;
                }
              })
              .whereType<MemoryFragment>()
              .toList(),
          triggerReason: 'Hive完整性修复前自动备份',
          source: 'pre_repair',
        );
      }

      if (byConv.isNotEmpty) {
        AppLogger.i('[HiveIntegrity] 已为 ${byConv.length} 个会话创建修复前快照');
      }
    } catch (e) {
      AppLogger.e('[HiveIntegrity] 创建修复前快照失败: $e');
    }
  }

  void dispose() {
    stopPeriodicCheck();
    _boxHealth.clear();
    _instance = null;
  }
}

class HiveCheckResult {
  final String boxName;
  final bool isHealthy;
  final List<String> issues;
  final int entryCount;
  final int corruptEntries;

  const HiveCheckResult({
    required this.boxName,
    required this.isHealthy,
    required this.issues,
    required this.entryCount,
    required this.corruptEntries,
  });

  @override
  String toString() {
    return 'HiveCheckResult(box: $boxName, healthy: $isHealthy, '
        'entries: $entryCount, corrupt: $corruptEntries, '
        'issues: ${issues.length})';
  }
}
