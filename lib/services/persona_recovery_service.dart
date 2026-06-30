import '../core/logger/app_logger.dart';
import 'memu_service.dart';
import 'persona_snapshot_service.dart';

/// 恢复检测结果
class RecoveryCheckResult {
  final String conversationId;
  final bool needsRecovery;
  final RecoveryIssueType issueType;
  final String description;
  final PersonaSnapshot? bestSnapshot;

  RecoveryCheckResult({
    required this.conversationId,
    required this.needsRecovery,
    this.issueType = RecoveryIssueType.none,
    this.description = '',
    this.bestSnapshot,
  });
}

/// 恢复问题类型
enum RecoveryIssueType {
  none,
  promptLost, // systemPrompt丢失
  promptDegraded, // systemPrompt被严重缩短/改变
  memoriesLost, // 人格相关记忆丢失
  memoriesCorrupted, // 记忆数据损坏
  snapshotAvailable, // 有可用快照但当前状态未知
}

/// 恢复操作结果
class RecoveryResult {
  final bool success;
  final String conversationId;
  final String? restoredPrompt;
  final int restoredMemoryCount;
  final String message;

  RecoveryResult({
    required this.success,
    required this.conversationId,
    this.restoredPrompt,
    this.restoredMemoryCount = 0,
    this.message = '',
  });
}

/// 人格恢复服务 - 检测人格丢失并从快照恢复
///
/// 核心职责：
/// 1. 启动时检测人格完整性
/// 2. 对比当前状态与最新快照，发现异常
/// 3. 提供自动/手动恢复能力
/// 4. 恢复前创建安全快照（防止恢复操作本身导致数据丢失）
class PersonaRecoveryService {
  static PersonaRecoveryService? _instance;
  static PersonaRecoveryService get instance =>
      _instance ??= PersonaRecoveryService._();

  PersonaRecoveryService._();

  bool _initialized = false;
  MemUService? _memuService;

  /// 恢复历史记录（防止重复恢复）
  final List<Map<String, dynamic>> _recoveryLog = [];

  bool get isInitialized => _initialized;

  /// 注入MemUService依赖
  void configure({MemUService? memuService}) {
    _memuService = memuService;
  }

  Future<bool> init() async {
    _initialized = true;
    AppLogger.i('[PersonaRecovery] 初始化成功');
    return true;
  }

  /// 检测指定会话的人格完整性
  ///
  /// 对比当前状态与最新快照，判断是否需要恢复
  Future<RecoveryCheckResult> checkPersonaIntegrity({
    required String conversationId,
    required String currentPrompt,
    required List<MemoryFragment> currentPersonaMemories,
  }) async {
    final snapshotService = PersonaSnapshotService.instance;
    final latestSnapshot = snapshotService.getLatestSnapshot(conversationId);

    // 没有快照，无法判断是否丢失
    if (latestSnapshot == null) {
      return RecoveryCheckResult(
        conversationId: conversationId,
        needsRecovery: false,
        issueType: RecoveryIssueType.none,
        description: '无历史快照，无法判断人格是否丢失',
      );
    }

    // 检查1: systemPrompt丢失
    if (currentPrompt.isEmpty && latestSnapshot.systemPrompt.isNotEmpty) {
      AppLogger.w('[PersonaRecovery] 检测到systemPrompt丢失: $conversationId');
      return RecoveryCheckResult(
        conversationId: conversationId,
        needsRecovery: true,
        issueType: RecoveryIssueType.promptLost,
        description:
            'systemPrompt从 "${_truncate(latestSnapshot.systemPrompt, 50)}" 变为空',
        bestSnapshot: latestSnapshot,
      );
    }

    // 检查2: systemPrompt严重退化（长度骤减超过70%）
    if (currentPrompt.isNotEmpty &&
        latestSnapshot.systemPrompt.isNotEmpty &&
        currentPrompt.length < latestSnapshot.systemPrompt.length * 0.3) {
      AppLogger.w(
        '[PersonaRecovery] 检测到systemPrompt严重退化: $conversationId '
        '(${latestSnapshot.systemPrompt.length} -> ${currentPrompt.length} 字符)',
      );
      return RecoveryCheckResult(
        conversationId: conversationId,
        needsRecovery: true,
        issueType: RecoveryIssueType.promptDegraded,
        description:
            'systemPrompt长度从 ${latestSnapshot.systemPrompt.length} 骤减到 ${currentPrompt.length} 字符',
        bestSnapshot: latestSnapshot,
      );
    }

    // 检查3: 人格相关记忆大量丢失
    final currentIds = currentPersonaMemories.map((m) => m.id).toSet();
    final snapshotIds = latestSnapshot.personaMemories.map((m) => m.id).toSet();
    final lostCount = snapshotIds
        .where((id) => !currentIds.contains(id))
        .length;

    if (lostCount > 0 &&
        lostCount >= latestSnapshot.personaMemories.length * 0.5) {
      AppLogger.w(
        '[PersonaRecovery] 检测到人格记忆大量丢失: $conversationId '
        '($lostCount/${latestSnapshot.personaMemories.length} 条)',
      );
      return RecoveryCheckResult(
        conversationId: conversationId,
        needsRecovery: true,
        issueType: RecoveryIssueType.memoriesLost,
        description:
            '$lostCount/${latestSnapshot.personaMemories.length} 条人格记忆丢失',
        bestSnapshot: latestSnapshot,
      );
    }

    return RecoveryCheckResult(
      conversationId: conversationId,
      needsRecovery: false,
      issueType: RecoveryIssueType.none,
      description: '人格状态正常',
    );
  }

  /// 批量检测所有会话的人格完整性
  Future<List<RecoveryCheckResult>> checkAllConversations({
    required List<Map<String, dynamic>> conversationStates,
  }) async {
    final results = <RecoveryCheckResult>[];

    for (final state in conversationStates) {
      final convId = state['conversationId'] as String? ?? '';
      if (convId.isEmpty) continue;
      final prompt = state['systemPrompt'] as String? ?? '';
      final memories =
          (state['personaMemories'] as List<dynamic>?)
              ?.cast<MemoryFragment>() ??
          [];

      results.add(
        await checkPersonaIntegrity(
          conversationId: convId,
          currentPrompt: prompt,
          currentPersonaMemories: memories,
        ),
      );
    }

    final needsRecovery = results.where((r) => r.needsRecovery).length;
    if (needsRecovery > 0) {
      AppLogger.w(
        '[PersonaRecovery] 批量检测完成: $needsRecovery/${results.length} 个会话需要恢复',
      );
    }

    return results;
  }

  /// 从快照恢复人格
  ///
  /// [snapshotId] 指定快照ID，为null则使用最新快照
  /// [restorePrompt] 是否恢复systemPrompt
  /// [restoreMemories] 是否恢复人格记忆
  Future<RecoveryResult> recoverFromSnapshot({
    required String conversationId,
    String? snapshotId,
    bool restorePrompt = true,
    bool restoreMemories = true,
  }) async {
    final snapshotService = PersonaSnapshotService.instance;
    final memuService = _memuService;

    // 获取快照
    final snapshot = snapshotId != null
        ? snapshotService.getSnapshot(snapshotId)
        : snapshotService.getLatestSnapshot(conversationId);

    if (snapshot == null) {
      return RecoveryResult(
        success: false,
        conversationId: conversationId,
        message: '未找到可用的快照',
      );
    }

    if (!snapshot.hasPersona) {
      return RecoveryResult(
        success: false,
        conversationId: conversationId,
        message: '快照中无人格数据',
      );
    }

    // 恢复前创建安全快照
    await _createPreRecoverySnapshot(conversationId, snapshot);

    int restoredMemoryCount = 0;

    // 恢复人格记忆到MemU
    if (restoreMemories &&
        snapshot.personaMemories.isNotEmpty &&
        memuService != null) {
      for (final memory in snapshot.personaMemories) {
        try {
          // 检查是否已存在相同内容的记忆
          if (!_memoryExists(memuService, memory.content)) {
            // 创建恢复的记忆，标记来源
            final recoveredMemory = MemoryFragment(
              id: 'recovered_${memory.id}_${DateTime.now().millisecondsSinceEpoch}',
              conversationId: conversationId,
              type: memory.type,
              content: memory.content,
              keywords: memory.keywords,
              importance: memory.importance,
              createdAt: memory.createdAt,
              lastAccessed: DateTime.now(),
              status: MemoryStatus.active,
              category: memory.category ?? '人格恢复',
            );
            await memuService.updateMemory(recoveredMemory);
            restoredMemoryCount++;
          }
        } catch (e) {
          AppLogger.e('[PersonaRecovery] 恢复记忆失败: ${memory.id}, $e');
        }
      }
    }

    // 记录恢复操作
    _recoveryLog.add({
      'conversationId': conversationId,
      'snapshotId': snapshot.id,
      'restoredPrompt': restorePrompt,
      'restoredMemoryCount': restoredMemoryCount,
      'timestamp': DateTime.now().toIso8601String(),
    });

    AppLogger.i(
      '[PersonaRecovery] 恢复完成: $conversationId, '
      'prompt=${restorePrompt ? "是" : "否"}, '
      '记忆数=$restoredMemoryCount',
    );

    final snapId = snapshot.id;
    return RecoveryResult(
      success: true,
      conversationId: conversationId,
      restoredPrompt: restorePrompt ? snapshot.systemPrompt : null,
      restoredMemoryCount: restoredMemoryCount,
      message:
          '成功从快照 ${snapId.length > 20 ? snapId.substring(0, 20) : snapId}... 恢复',
    );
  }

  /// 自动恢复：检测并恢复（仅恢复明确丢失的情况）
  ///
  /// 返回恢复结果列表，空列表表示无需恢复
  Future<List<RecoveryResult>> autoRecover({
    required List<Map<String, dynamic>> conversationStates,
  }) async {
    final checkResults = await checkAllConversations(
      conversationStates: conversationStates,
    );

    final recoveryResults = <RecoveryResult>[];

    for (final check in checkResults) {
      if (!check.needsRecovery) continue;

      // 仅自动恢复明确丢失的情况
      if (check.issueType == RecoveryIssueType.promptLost ||
          check.issueType == RecoveryIssueType.memoriesLost) {
        final result = await recoverFromSnapshot(
          conversationId: check.conversationId,
          restorePrompt: check.issueType == RecoveryIssueType.promptLost,
          restoreMemories: check.issueType == RecoveryIssueType.memoriesLost,
        );
        recoveryResults.add(result);
      }
      // promptDegraded 需要用户确认，不自动恢复
    }

    return recoveryResults;
  }

  /// 获取恢复历史
  List<Map<String, dynamic>> getRecoveryLog() {
    return List.unmodifiable(_recoveryLog);
  }

  /// 检测Hive Box损坏导致的人格丢失
  Future<List<RecoveryCheckResult>> detectCorruption({
    required List<String> conversationIds,
    required String Function(String) getPrompt,
  }) async {
    final results = <RecoveryCheckResult>[];
    final snapshotService = PersonaSnapshotService.instance;

    for (final convId in conversationIds) {
      try {
        final currentPrompt = getPrompt(convId);
        final snapshot = snapshotService.getLatestSnapshot(convId);

        if (snapshot != null &&
            snapshot.systemPrompt.isNotEmpty &&
            currentPrompt.isEmpty) {
          results.add(
            RecoveryCheckResult(
              conversationId: convId,
              needsRecovery: true,
              issueType: RecoveryIssueType.promptLost,
              description: 'Hive损坏检测: systemPrompt丢失',
              bestSnapshot: snapshot,
            ),
          );
        }
      } catch (e) {
        AppLogger.e('[PersonaRecovery] 损坏检测异常: $convId, $e');
        final snapshot = snapshotService.getLatestSnapshot(convId);
        if (snapshot != null && snapshot.hasPersona) {
          results.add(
            RecoveryCheckResult(
              conversationId: convId,
              needsRecovery: true,
              issueType: RecoveryIssueType.memoriesCorrupted,
              description: '读取异常: $e',
              bestSnapshot: snapshot,
            ),
          );
        }
      }
    }

    return results;
  }

  /// 恢复前创建安全快照
  Future<void> _createPreRecoverySnapshot(
    String conversationId,
    PersonaSnapshot sourceSnapshot,
  ) async {
    final snapshotService = PersonaSnapshotService.instance;
    final memuService = _memuService;

    // 获取当前MemU中该会话的所有记忆
    final convMemories = memuService != null
        ? memuService
              .getAllMemories()
              .where((m) => m.conversationId == conversationId && m.isActive)
              .toList()
        : <MemoryFragment>[];

    await snapshotService.createSnapshot(
      conversationId: conversationId,
      conversationName: sourceSnapshot.conversationName,
      systemPrompt: '', // 当前可能已丢失
      personaMemories: convMemories,
      triggerReason: '恢复操作前的安全快照',
      source: 'pre_recovery',
    );
  }

  /// 检查记忆是否已存在（按内容去重）
  bool _memoryExists(MemUService memuService, String content) {
    final all = memuService.getAllMemories();
    final contentTrimmed = content.trim();
    return all.any((m) => m.content.trim() == contentTrimmed);
  }

  String _truncate(String text, int maxLen) {
    if (text.length <= maxLen) return text;
    return '${text.substring(0, maxLen)}...';
  }

  Future<void> close() async {
    _initialized = false;
  }
}
