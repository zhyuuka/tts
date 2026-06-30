import 'package:hive/hive.dart';

import '../core/logger/app_logger.dart';
import 'memu_service.dart';

class MemoryConflictResolver {
  static MemoryConflictResolver? _instance;
  static MemoryConflictResolver get instance =>
      _instance ??= MemoryConflictResolver._();

  MemoryConflictResolver._();

  int _totalResolutions = 0;
  int _autoResolutions = 0;

  int get totalResolutions => _totalResolutions;
  int get autoResolutions => _autoResolutions;

  static const List<_ConflictPattern> _conflictPatterns = [
    _ConflictPattern(
      oldPattern: r'(?:养了|买了|有)\s*(\S+)',
      newPattern: r'(?:送走了|卖了|丢了|没了|不要了|去世了)\s*(\S+)',
      category: 'ownership',
    ),
    _ConflictPattern(
      oldPattern: r'(?:喜欢|爱|偏好)\s*(\S+)',
      newPattern: r'(?:不喜欢|讨厌|不再|不爱|反感)\s*(\S+)',
      category: 'preference',
    ),
    _ConflictPattern(
      oldPattern: r'(?:在|去|住)\s*(\S+)',
      newPattern: r'(?:搬|离开|去了|不在)\s*(\S+)',
      category: 'location',
    ),
    _ConflictPattern(
      oldPattern: r'(?:打算|计划|准备|要)\s*(\S+)',
      newPattern: r'(?:取消|不|放弃|推迟)\s*(\S+)',
      category: 'plan',
    ),
    _ConflictPattern(
      oldPattern: r'(?:做|从事|在)\s*(\S+)',
      newPattern: r'(?:辞职|离职|转行|换了|不在)\s*(\S+)',
      category: 'career',
    ),
  ];

  Future<List<MemoryFragment>> detectAndResolve(
    Box memoryBox,
    MemoryFragment newMemory,
  ) async {
    final conflicts = <MemoryFragment>[];

    if (!newMemory.isActive) return conflicts;

    for (final key in memoryBox.keys) {
      final data = memoryBox.get(key);
      if (data is! Map<String, dynamic>) continue;

      final existing = MemoryFragment.fromJson(data);
      if (!existing.isActive) continue;
      if (existing.id == newMemory.id) continue;

      final conflict = _checkConflict(existing, newMemory);
      if (conflict != null) {
        conflicts.add(existing);

        final updated = existing.copyWith(
          status: conflict.shouldSupersede
              ? MemoryStatus.superseded
              : MemoryStatus.conflicted,
          supersededBy: conflict.shouldSupersede ? newMemory.id : null,
        );

        await memoryBox.put(existing.id, updated.toJson());
        _totalResolutions++;

        if (conflict.shouldSupersede) {
          _autoResolutions++;
          AppLogger.i(
            '[ConflictResolver] 自动覆盖: "${existing.content.substring(0, existing.content.length.clamp(0, 40))}..." → 被新记忆覆盖',
          );
        } else {
          AppLogger.i(
            '[ConflictResolver] 标记冲突: "${existing.content.substring(0, existing.content.length.clamp(0, 40))}..." ↔ 新记忆可能矛盾',
          );
        }
      }
    }

    return conflicts;
  }

  _ConflictResult? _checkConflict(
    MemoryFragment existing,
    MemoryFragment newMemory,
  ) {
    final oldContent = existing.content.toLowerCase();
    final newContent = newMemory.content.toLowerCase();

    for (final pattern in _conflictPatterns) {
      final oldMatch = RegExp(pattern.oldPattern).firstMatch(oldContent);
      final newMatch = RegExp(pattern.newPattern).firstMatch(newContent);

      if (oldMatch != null && newMatch != null) {
        final oldEntity = oldMatch.group(1)?.toLowerCase() ?? '';
        final newEntity = newMatch.group(1)?.toLowerCase() ?? '';

        if (oldEntity.isNotEmpty &&
            newEntity.isNotEmpty &&
            _entitiesMatch(oldEntity, newEntity)) {
          return _ConflictResult(
            shouldSupersede: true,
            category: pattern.category,
            reason: '旧状态"${oldMatch.group(0)}"被新状态"${newMatch.group(0)}"覆盖',
          );
        }
      }
    }

    if (existing.category != null &&
        newMemory.category != null &&
        existing.category == newMemory.category &&
        existing.category != '其他' &&
        existing.category != '知识') {
      final keywordOverlap = _calculateKeywordOverlap(
        existing.keywords,
        newMemory.keywords,
      );
      if (keywordOverlap > 0.5 && newMemory.importance > existing.importance) {
        return _ConflictResult(
          shouldSupersede: false,
          category: existing.category ?? '未知',
          reason: '同类别记忆可能存在更新，标记为冲突待人工确认',
        );
      }
    }

    return null;
  }

  bool _entitiesMatch(String entity1, String entity2) {
    if (entity1 == entity2) return true;

    if (entity1.contains(entity2) || entity2.contains(entity1)) return true;

    if (entity1.length >= 2 && entity2.length >= 2) {
      if (entity1.substring(0, entity1.length - 1) ==
          entity2.substring(0, entity2.length - 1)) {
        return true;
      }
    }

    return false;
  }

  double _calculateKeywordOverlap(List<String> a, List<String> b) {
    if (a.isEmpty || b.isEmpty) return 0.0;

    final setA = a.toSet();
    final setB = b.toSet();
    final intersection = setA.intersection(setB).length;
    final union = setA.union(setB).length;

    return union > 0 ? intersection / union : 0.0;
  }

  Future<List<MemoryFragment>> getConflictedMemories(Box memoryBox) async {
    final conflicted = <MemoryFragment>[];

    for (final key in memoryBox.keys) {
      final data = memoryBox.get(key);
      if (data is Map<String, dynamic>) {
        final fragment = MemoryFragment.fromJson(data);
        if (fragment.isConflicted) {
          conflicted.add(fragment);
        }
      }
    }

    return conflicted;
  }

  Future<void> resolveConflict(
    Box memoryBox,
    String fragmentId, {
    bool keepNew = true,
    String? newMemoryId,
  }) async {
    final data = memoryBox.get(fragmentId);
    if (data is! Map<String, dynamic>) return;

    final fragment = MemoryFragment.fromJson(data);

    if (keepNew) {
      final updated = fragment.copyWith(
        status: MemoryStatus.superseded,
        supersededBy: newMemoryId,
      );
      await memoryBox.put(fragmentId, updated.toJson());
    } else {
      final updated = fragment.copyWith(status: MemoryStatus.active);
      await memoryBox.put(fragmentId, updated.toJson());
    }

    AppLogger.i('[ConflictResolver] 手动解决冲突: $fragmentId (keepNew=$keepNew)');
  }

  void dispose() {
    _instance = null;
    AppLogger.i(
      '[ConflictResolver] 已关闭 (总解决: $_totalResolutions, 自动: $_autoResolutions)',
    );
  }
}

class _ConflictPattern {
  final String oldPattern;
  final String newPattern;
  final String category;

  const _ConflictPattern({
    required this.oldPattern,
    required this.newPattern,
    required this.category,
  });
}

class _ConflictResult {
  final bool shouldSupersede;
  final String category;
  final String reason;

  const _ConflictResult({
    required this.shouldSupersede,
    required this.category,
    required this.reason,
  });
}
