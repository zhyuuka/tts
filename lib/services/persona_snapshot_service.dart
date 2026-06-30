import 'dart:convert';
import 'dart:io';

import 'package:hive/hive.dart';
import 'package:path_provider/path_provider.dart';

import '../core/logger/app_logger.dart';
import 'memu_service.dart';

/// 人格快照 - 记录某一时刻的完整人格状态
class PersonaSnapshot {
  final String id;
  final String conversationId;
  final String conversationName;

  /// systemPrompt 原文
  final String systemPrompt;

  /// 人格相关的长期记忆片段
  final List<MemoryFragment> personaMemories;

  /// 快照创建时间
  final DateTime createdAt;

  /// 快照触发原因
  final String triggerReason;

  /// 快照来源标记：auto(自动) / manual(手动) / pre_change(变更前)
  final String source;

  PersonaSnapshot({
    required this.id,
    required this.conversationId,
    required this.conversationName,
    required this.systemPrompt,
    required this.personaMemories,
    required this.createdAt,
    required this.triggerReason,
    this.source = 'auto',
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'conversationId': conversationId,
    'conversationName': conversationName,
    'systemPrompt': systemPrompt,
    'personaMemories': personaMemories.map((m) => m.toJson()).toList(),
    'createdAt': createdAt.toIso8601String(),
    'triggerReason': triggerReason,
    'source': source,
  };

  factory PersonaSnapshot.fromJson(Map<String, dynamic> json) {
    return PersonaSnapshot(
      id: json['id'] as String? ?? '',
      conversationId: json['conversationId'] as String? ?? '',
      conversationName: json['conversationName'] as String? ?? '',
      systemPrompt: json['systemPrompt'] as String? ?? '',
      personaMemories:
          (json['personaMemories'] as List<dynamic>?)
              ?.map((m) => MemoryFragment.fromJson(m as Map<String, dynamic>))
              .toList() ??
          [],
      createdAt: json['createdAt'] != null
          ? DateTime.tryParse(json['createdAt'].toString()) ?? DateTime.now()
          : DateTime.now(),
      triggerReason: json['triggerReason'] as String? ?? '',
      source: json['source'] as String? ?? 'auto',
    );
  }

  /// 快照是否包含有效的人格信息
  bool get hasPersona => systemPrompt.isNotEmpty || personaMemories.isNotEmpty;
}

/// 人格快照服务 - 定期和事件驱动的人格状态快照
///
/// 核心职责：
/// 1. 在关键事件（systemPrompt变更、长期记忆写入）时自动创建快照
/// 2. 定期创建人格快照（防止未捕获的变更）
/// 3. 管理快照的生命周期（保留上限、过期清理）
/// 4. 提供快照查询接口供恢复服务使用
class PersonaSnapshotService {
  static PersonaSnapshotService? _instance;
  static PersonaSnapshotService get instance =>
      _instance ??= PersonaSnapshotService._();

  PersonaSnapshotService._();

  static const String _snapshotBoxName = 'persona_snapshots';
  static const int _maxSnapshotsPerConversation = 20;
  static const int _maxTotalSnapshots = 200;
  static const Duration _autoSnapshotInterval = Duration(hours: 6);
  static const Duration _memoryChangeSnapshotInterval = Duration(minutes: 30);

  Box? _snapshotBox;
  bool _initialized = false;

  /// 上一次各会话自动快照的时间（按会话独立计时）。
  /// 为什么改为 Map：原全局字段导致会话 A 快照后 6 小时内切到会话 B，
  /// 会话 B 的快照被跳过。按会话独立计时解决跨会话遗漏。
  final Map<String, DateTime> _lastAutoSnapshotTime = {};

  /// 上一次各会话的记忆内容 hash（用于检测记忆变化触发快照）。
  final Map<String, int> _lastKnownMemoryHash = {};

  /// 上一次各会话的systemPrompt快照（用于检测变更）
  final Map<String, String> _lastKnownPrompts = {};

  bool get isInitialized => _initialized;

  Future<bool> init() async {
    try {
      _snapshotBox = await Hive.openBox(_snapshotBoxName);
      _initialized = true;
      AppLogger.i('[PersonaSnapshot] 初始化成功');
      return true;
    } catch (e) {
      AppLogger.e('[PersonaSnapshot] 初始化失败: $e');
      return false;
    }
  }

  /// 创建快照
  Future<PersonaSnapshot?> createSnapshot({
    required String conversationId,
    required String conversationName,
    required String systemPrompt,
    required List<MemoryFragment> personaMemories,
    required String triggerReason,
    String source = 'auto',
  }) async {
    if (!_initialized || _snapshotBox == null) return null;

    try {
      final snapshot = PersonaSnapshot(
        id: 'snap_${conversationId}_${DateTime.now().millisecondsSinceEpoch}',
        conversationId: conversationId,
        conversationName: conversationName,
        systemPrompt: systemPrompt,
        personaMemories: personaMemories,
        createdAt: DateTime.now(),
        triggerReason: triggerReason,
        source: source,
      );

      await _snapshotBox!.put(snapshot.id, snapshot.toJson());

      // 更新已知prompt缓存
      _lastKnownPrompts[conversationId] = systemPrompt;

      // 清理过多快照
      await _cleanupOldSnapshots(conversationId);

      AppLogger.i(
        '[PersonaSnapshot] 快照已创建: ${snapshot.id} '
        '(原因: $triggerReason, 来源: $source, '
        '记忆数: ${personaMemories.length})',
      );

      return snapshot;
    } catch (e) {
      AppLogger.e('[PersonaSnapshot] 创建快照失败: $e');
      return null;
    }
  }

  /// 在systemPrompt变更前创建快照
  Future<PersonaSnapshot?> snapshotBeforePromptChange({
    required String conversationId,
    required String conversationName,
    required String oldSystemPrompt,
    required List<MemoryFragment> personaMemories,
  }) async {
    return createSnapshot(
      conversationId: conversationId,
      conversationName: conversationName,
      systemPrompt: oldSystemPrompt,
      personaMemories: personaMemories,
      triggerReason: 'systemPrompt变更前',
      source: 'pre_change',
    );
  }

  /// 检测并响应systemPrompt变更
  Future<void> checkPromptChange({
    required String conversationId,
    required String conversationName,
    required String currentPrompt,
    required List<MemoryFragment> personaMemories,
  }) async {
    final lastPrompt = _lastKnownPrompts[conversationId];
    if (lastPrompt != null && lastPrompt != currentPrompt) {
      AppLogger.i('[PersonaSnapshot] 检测到systemPrompt变更: $conversationId');
      await createSnapshot(
        conversationId: conversationId,
        conversationName: conversationName,
        systemPrompt: currentPrompt,
        personaMemories: personaMemories,
        triggerReason: 'systemPrompt变更',
        source: 'auto',
      );
    }
    _lastKnownPrompts[conversationId] = currentPrompt;
  }

  /// 定期自动快照（由外部调用，每次发消息时触发）。
  /// 双触发机制：
  ///   1. 超过 6 小时定期快照（或首次快照）
  ///   2. 记忆内容变化且距上次 ≥ 30 分钟
  /// 为什么这样做：原全局计时导致跨会话遗漏 + 只检测 prompt 变化不检测记忆变化。
  Future<void> performAutoSnapshot({
    required String conversationId,
    required String conversationName,
    required String systemPrompt,
    required List<MemoryFragment> personaMemories,
  }) async {
    final now = DateTime.now();
    final lastTime = _lastAutoSnapshotTime[conversationId];

    // 计算当前记忆内容 hash，用于检测 personaMemories 是否变化。
    // 为什么用 hash：O(n) 拼接 + hashCode，成本极低，无需存储原始内容。
    final memoryHash = personaMemories.map((m) => m.content).join('|').hashCode;
    final lastHash = _lastKnownMemoryHash[conversationId];

    bool shouldSnapshot = false;
    String triggerReason;

    // 触发条件 1：超过 6 小时定期快照（或首次快照）
    if (lastTime == null || now.difference(lastTime) >= _autoSnapshotInterval) {
      shouldSnapshot = true;
      triggerReason = lastTime == null ? '首次快照' : '定期自动快照';
    } else {
      triggerReason = '';
    }

    // 触发条件 2：记忆内容变化且距上次 ≥ 30 分钟（防抖避免频繁快照）
    if (lastHash != null && lastHash != memoryHash && lastTime != null) {
      if (now.difference(lastTime) >= _memoryChangeSnapshotInterval) {
        shouldSnapshot = true;
        triggerReason = '记忆变更快照';
      }
    }

    if (!shouldSnapshot) return;

    await createSnapshot(
      conversationId: conversationId,
      conversationName: conversationName,
      systemPrompt: systemPrompt,
      personaMemories: personaMemories,
      triggerReason: triggerReason,
      source: 'auto',
    );
    _lastAutoSnapshotTime[conversationId] = now;
    _lastKnownMemoryHash[conversationId] = memoryHash;
  }

  /// 获取指定会话的所有快照（按时间倒序）
  List<PersonaSnapshot> getSnapshotsForConversation(String conversationId) {
    if (!_initialized || _snapshotBox == null) return [];

    final snapshots = <PersonaSnapshot>[];
    for (final key in _snapshotBox!.keys) {
      final data = _snapshotBox!.get(key);
      if (data is Map<String, dynamic>) {
        final snap = PersonaSnapshot.fromJson(data);
        if (snap.conversationId == conversationId) {
          snapshots.add(snap);
        }
      }
    }

    snapshots.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return snapshots;
  }

  /// 获取指定会话的最新快照
  PersonaSnapshot? getLatestSnapshot(String conversationId) {
    final snapshots = getSnapshotsForConversation(conversationId);
    return snapshots.isNotEmpty ? snapshots.first : null;
  }

  /// 获取所有快照
  List<PersonaSnapshot> getAllSnapshots() {
    if (!_initialized || _snapshotBox == null) return [];

    final snapshots = <PersonaSnapshot>[];
    for (final key in _snapshotBox!.keys) {
      final data = _snapshotBox!.get(key);
      if (data is Map<String, dynamic>) {
        snapshots.add(PersonaSnapshot.fromJson(data));
      }
    }

    snapshots.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return snapshots;
  }

  /// 获取指定快照
  PersonaSnapshot? getSnapshot(String snapshotId) {
    if (!_initialized || _snapshotBox == null) return null;

    final data = _snapshotBox!.get(snapshotId);
    if (data is Map<String, dynamic>) {
      return PersonaSnapshot.fromJson(data);
    }
    return null;
  }

  /// 删除指定快照
  Future<void> deleteSnapshot(String snapshotId) async {
    if (!_initialized || _snapshotBox == null) return;
    await _snapshotBox!.delete(snapshotId);
  }

  /// 导出快照到文件（用于灾难恢复）
  Future<String?> exportSnapshotsToFile() async {
    if (!_initialized || _snapshotBox == null) return null;

    try {
      final appDir = await getApplicationDocumentsDirectory();
      final exportDir = Directory('${appDir.path}/persona_snapshots');
      if (!exportDir.existsSync()) {
        exportDir.createSync(recursive: true);
      }

      final allSnapshots = getAllSnapshots();
      final exportData = {
        'version': 1,
        'exportedAt': DateTime.now().toIso8601String(),
        'count': allSnapshots.length,
        'snapshots': allSnapshots.map((s) => s.toJson()).toList(),
      };

      final filePath =
          '${exportDir.path}/snapshots_${DateTime.now().millisecondsSinceEpoch}.json';
      File(filePath).writeAsStringSync(jsonEncode(exportData));

      AppLogger.i(
        '[PersonaSnapshot] 已导出 ${allSnapshots.length} 个快照到: $filePath',
      );
      return filePath;
    } catch (e) {
      AppLogger.e('[PersonaSnapshot] 导出快照失败: $e');
      return null;
    }
  }

  /// 从文件导入快照
  Future<int> importSnapshotsFromFile(String filePath) async {
    try {
      final file = File(filePath);
      if (!file.existsSync()) return 0;

      final content = file.readAsStringSync();
      final data = jsonDecode(content) as Map<String, dynamic>;
      final snapshotList = data['snapshots'] as List<dynamic>? ?? [];

      int imported = 0;
      for (final item in snapshotList) {
        final snap = PersonaSnapshot.fromJson(item as Map<String, dynamic>);
        if (snap.id.isNotEmpty) {
          await _snapshotBox!.put(snap.id, snap.toJson());
          imported++;
        }
      }

      AppLogger.i('[PersonaSnapshot] 从文件导入 $imported 个快照');
      return imported;
    } catch (e) {
      AppLogger.e('[PersonaSnapshot] 导入快照失败: $e');
      return 0;
    }
  }

  /// 清理过多的快照
  Future<void> _cleanupOldSnapshots(String conversationId) async {
    if (_snapshotBox == null) return;

    final snapshots = getSnapshotsForConversation(conversationId);
    if (snapshots.length <= _maxSnapshotsPerConversation) return;

    // 保留 pre_change 类型的快照优先级最高
    final preChangeSnaps = snapshots
        .where((s) => s.source == 'pre_change')
        .toList();
    final otherSnaps = snapshots
        .where((s) => s.source != 'pre_change')
        .toList();

    // pre_change快照全部保留（但不超过上限的一半）
    final maxPreChange = (_maxSnapshotsPerConversation / 2).ceil();
    final keptPreChange = preChangeSnaps.take(maxPreChange).toList();

    // 其他快照保留剩余名额
    final remainingSlots = _maxSnapshotsPerConversation - keptPreChange.length;
    final keptOther = otherSnaps.take(remainingSlots).toList();

    final keptIds = {...keptPreChange, ...keptOther}.map((s) => s.id).toSet();

    for (final snap in snapshots) {
      if (!keptIds.contains(snap.id)) {
        await _snapshotBox!.delete(snap.id);
      }
    }
  }

  /// 全局快照数量清理
  Future<void> cleanupGlobalSnapshots() async {
    if (_snapshotBox == null) return;

    final allSnapshots = getAllSnapshots();
    if (allSnapshots.length <= _maxTotalSnapshots) return;

    // 按会话分组，每个会话至少保留1个最新快照
    final byConv = <String, List<PersonaSnapshot>>{};
    for (final snap in allSnapshots) {
      byConv.putIfAbsent(snap.conversationId, () => []).add(snap);
    }

    // 每个会话保留最新1个
    final mustKeep = <String>{};
    for (final snaps in byConv.values) {
      snaps.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      mustKeep.add(snaps.first.id);
    }

    // 从剩余快照中按时间排序，保留到上限
    final removable =
        allSnapshots.where((s) => !mustKeep.contains(s.id)).toList()
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

    final canKeepCount = _maxTotalSnapshots - mustKeep.length;
    final toDelete = removable.skip(canKeepCount);

    for (final snap in toDelete) {
      await _snapshotBox!.delete(snap.id);
    }

    AppLogger.d(
      '[PersonaSnapshot] 全局清理: 保留 ${mustKeep.length + canKeepCount}, '
      '删除 ${toDelete.length}',
    );
  }

  /// 获取快照统计信息
  Map<String, dynamic> getStats() {
    if (!_initialized || _snapshotBox == null) {
      return {'initialized': false};
    }

    final all = getAllSnapshots();
    final bySource = <String, int>{};
    final byConv = <String, int>{};

    for (final snap in all) {
      bySource[snap.source] = (bySource[snap.source] ?? 0) + 1;
      byConv[snap.conversationId] = (byConv[snap.conversationId] ?? 0) + 1;
    }

    return {
      'initialized': true,
      'totalSnapshots': all.length,
      'bySource': bySource,
      'byConversation': byConv.length,
      'oldestSnapshot': all.isNotEmpty
          ? all.last.createdAt.toIso8601String()
          : null,
      'newestSnapshot': all.isNotEmpty
          ? all.first.createdAt.toIso8601String()
          : null,
    };
  }

  Future<void> close() async {
    if (_initialized && _snapshotBox != null) {
      await _snapshotBox!.close();
      _initialized = false;
    }
  }
}
