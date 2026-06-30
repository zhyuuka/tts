import 'dart:async';

import 'package:flutter/material.dart';

import '../core/logger/app_logger.dart';
import '../models/message.dart';
import '../services/common/debug_mode_service.dart';
import '../services/memlocal_service.dart';
import '../services/memu_service.dart';
import '../services/common/performance_monitor.dart';
import '../services/persona_recovery_service.dart';
import '../services/persona_snapshot_service.dart';
import '../services/token_estimator.dart';

class MemoryProvider extends ChangeNotifier {
  final MemUService _memuService;
  final MemLocalService _memLocalService;
  final Map<String, MemLocalSession> _sessions = {};

  final PersonaSnapshotService _snapshotService =
      PersonaSnapshotService.instance;
  final PersonaRecoveryService _recoveryService =
      PersonaRecoveryService.instance;

  String? _error;
  bool _isMemUReady = false;
  bool _isMemLocalReady = false;
  bool _isSnapshotReady = false;
  bool _isRecoveryReady = false;
  bool _disposed = false;

  MemoryProvider({
    required MemUService memuService,
    required MemLocalService memLocalService,
  }) : _memuService = memuService,
       _memLocalService = memLocalService {
    _memuService.addInitListener(_onMemUInitChanged);
    _memLocalService.addInitListener(_onMemLocalInitChanged);
  }

  String? get error => _error;
  bool get isMemUReady => _isMemUReady;
  bool get isMemLocalReady => _isMemLocalReady;
  bool get isReady => _isMemUReady || _isMemLocalReady;
  bool get isPersonaProtectionReady => _isSnapshotReady && _isRecoveryReady;
  MemUService get memuService => _memuService;
  MemLocalService get memLocalService => _memLocalService;
  PersonaSnapshotService get snapshotService => _snapshotService;
  PersonaRecoveryService get recoveryService => _recoveryService;

  void _onMemUInitChanged(bool success, String? error) {
    _isMemUReady = success;
    if (!success) {
      AppLogger.e('[MemoryProvider] MemU初始化失败: $error');
      _error = '记忆系统初始化失败，部分功能可能受限';
    } else {
      AppLogger.i('[MemoryProvider] MemU初始化成功');
      if (_memuService.pendingWritesCount > 0) {
        AppLogger.d(
          '[MemoryProvider] 发现 ${_memuService.pendingWritesCount} 条待写记忆，开始恢复...',
        );
        _memuService.retryPendingWrites();
      }
      // 初始化人格保护系统
      _initPersonaProtection();
    }
    notifyListeners();
  }

  Future<void> _initPersonaProtection() async {
    try {
      if (!_isSnapshotReady) {
        _isSnapshotReady = await _snapshotService.init();
        AppLogger.i(
          '[MemoryProvider] 人格快照服务初始化: ${_isSnapshotReady ? "成功" : "失败"}',
        );
      }
      if (!_isRecoveryReady) {
        _recoveryService.configure(memuService: _memuService);
        _isRecoveryReady = await _recoveryService.init();
        AppLogger.i(
          '[MemoryProvider] 人格恢复服务初始化: ${_isRecoveryReady ? "成功" : "失败"}',
        );
      }
    } catch (e) {
      AppLogger.e('[MemoryProvider] 人格保护系统初始化异常: $e');
    }
  }

  void _onMemLocalInitChanged(bool success, String? error) {
    _isMemLocalReady = success;
    if (!success) {
      AppLogger.e('[MemoryProvider] MemLocal初始化失败: $error');
      _error = '${_error ?? ''} 本地记忆系统未就绪';
    } else {
      AppLogger.i('[MemoryProvider] MemLocal初始化成功');
    }
    notifyListeners();
  }

  Future<MemLocalSession?> initSession(String conversationId) async {
    if (_sessions.containsKey(conversationId)) {
      return _sessions[conversationId]!;
    }

    try {
      final session = await _memLocalService.initSession(conversationId);
      _sessions[conversationId] = session;
      AppLogger.i('[MemoryProvider] MemLocal会话初始化成功: $conversationId');
      return session;
    } catch (e) {
      AppLogger.e('[MemoryProvider] MemLocal会话初始化失败: $e');
      return null;
    }
  }

  MemLocalSession? getSession(String conversationId) {
    return _sessions[conversationId];
  }

  /// 移除指定会话的 MemLocal session 缓存
  /// 在删除会话时调用，避免内存泄漏和误用已删除会话的缓存
  void removeSession(String conversationId) {
    _sessions.remove(conversationId);
  }

  Future<List<Message>> getMemoryContext(
    String conversationId,
    String query,
  ) async {
    // 为什么这样做：原逻辑是"短路"——MemLocal 命中就不查 MemU，
    // 导致 MemU 的跨会话语义记忆很少被触发。改为"合并"：
    // MemLocal 提供会话内原文片段，MemU 提供跨会话语义记忆，两者互补。
    final result = <Message>[];
    final dbg = DebugModeService.instance;

    // 1. 查 MemLocal（会话内原文片段）
    final session = getSession(conversationId);
    if (session != null && _isMemLocalReady) {
      try {
        final relevantContext = await session.getRelevantContext(
          query,
          limit: 5,
        );
        if (relevantContext.isNotEmpty) {
          final memoryText = relevantContext.join('\n---\n');
          dbg.logMemoryInjection(
            conversationId: conversationId,
            memoryCount: relevantContext.length,
            memorySummaries: relevantContext
                .map((s) => s.length > 50 ? '${s.substring(0, 50)}...' : s)
                .toList(),
            source: 'MemLocal',
          );
          result.add(
            Message(
              role: 'system',
              content: '以下是相关的对话记忆，请参考这些上下文：\n$memoryText',
            ),
          );
        }
      } catch (e) {
        AppLogger.e('[MemoryProvider] 获取MemLocal记忆上下文失败(非致命): $e');
      }
    }

    // 2. 查 MemU（跨会话语义记忆，不再因 MemLocal 命中而短路）
    if (_isMemUReady) {
      try {
        final memuContext = await _memuService.getMemoryContext(
          conversationId,
          query,
        );
        if (memuContext.isNotEmpty) {
          dbg.logMemoryInjection(
            conversationId: conversationId,
            memoryCount: memuContext.length,
            memorySummaries: memuContext
                .map(
                  (m) => m.content.substring(0, m.content.length.clamp(0, 50)),
                )
                .toList(),
            source: 'MemU',
          );
          result.addAll(memuContext);
        }
      } catch (e) {
        AppLogger.e('[MemoryProvider] 获取MemU记忆上下文失败: $e');
      }
    }

    return result;
  }

  static const int _reservedSystemTokens = 2048;
  static const double _contextUsageRatio = 0.85;

  final TokenEstimator _tokenEstimator = TokenEstimator();

  Future<List<Message>> buildEnhancedPrompt(
    String conversationId,
    String userInput,
    String? systemPrompt,
    List<Message> historyMessages, {
    String serviceId = 'doubao',
  }) async {
    final enhancedMessages = <Message>[];
    final perf = PerformanceMonitor.instance;
    perf.startSpan('send.buildPrompt');

    // 人格设定放在最前面，确保 AI 首先确立身份和行为准则
    // 之前记忆放在前面会导致 AI 更关注记忆而淡化人格设定
    if (systemPrompt != null && systemPrompt.isNotEmpty) {
      enhancedMessages.add(Message(role: 'system', content: systemPrompt));
    }

    final memoryContext = await getMemoryContext(conversationId, userInput);
    enhancedMessages.addAll(memoryContext);

    final systemTokenCount = _estimateMessagesTokens(enhancedMessages);
    final maxContextTokens = _tokenEstimator.maxContextTokens(serviceId);
    final availableForHistory =
        ((maxContextTokens * _contextUsageRatio).toInt() -
        systemTokenCount -
        _reservedSystemTokens);

    if (availableForHistory > 0 && historyMessages.isNotEmpty) {
      final trimmedHistory = _trimHistoryFromStart(
        historyMessages,
        availableForHistory,
      );
      enhancedMessages.addAll(trimmedHistory);

      if (trimmedHistory.length < historyMessages.length) {
        AppLogger.i(
          '[MemoryProvider] 历史消息已裁剪: ${historyMessages.length} → ${trimmedHistory.length} 条 '
          '(系统消息占 $systemTokenCount tokens, 可用 $availableForHistory tokens)',
        );
      }
    } else if (historyMessages.isNotEmpty) {
      final lastPair = _takeLastUserAssistantPair(historyMessages);
      enhancedMessages.addAll(lastPair);
      AppLogger.w('[MemoryProvider] 上下文空间不足，仅保留最后 ${lastPair.length} 条历史消息');
    }

    perf.endSpan('send.buildPrompt');
    return enhancedMessages;
  }

  int _estimateMessagesTokens(List<Message> messages) {
    final contents = <String>[];
    for (final msg in messages) {
      contents.add(msg.content);
      if (msg.reasoningContent != null) {
        contents.add(msg.reasoningContent!);
      }
    }
    return _tokenEstimator.estimateContextTokens(contents);
  }

  List<Message> _trimHistoryFromStart(List<Message> messages, int maxTokens) {
    var totalTokens = 0;
    for (var i = messages.length - 1; i >= 0; i--) {
      var msgTokens = _tokenEstimator.estimateTokens(messages[i].content);
      if (messages[i].reasoningContent != null) {
        msgTokens += _tokenEstimator.estimateTokens(
          messages[i].reasoningContent!,
        );
      }
      totalTokens += msgTokens;
      if (totalTokens > maxTokens) {
        final startIndex = i + 1;
        if (startIndex >= messages.length) {
          return [messages.last];
        }
        final trimmed = messages.sublist(startIndex);
        if (trimmed.isNotEmpty && trimmed.first.role == 'assistant') {
          if (trimmed.length > 1) {
            return trimmed.sublist(1);
          }
          return [messages.last];
        }
        return trimmed;
      }
    }
    return messages;
  }

  List<Message> _takeLastUserAssistantPair(List<Message> messages) {
    final result = <Message>[];
    for (var i = messages.length - 1; i >= 0 && result.length < 2; i--) {
      result.insert(0, messages[i]);
    }
    return result;
  }

  Future<void> saveUserMessage(
    String conversationId,
    String content, {
    List<String>? attachmentPaths,
  }) async {
    final session = getSession(conversationId);
    if (session != null && _isMemLocalReady) {
      try {
        await session.saveUserMessage(
          content: content,
          attachments: attachmentPaths ?? [],
        );
        AppLogger.i('[MemoryProvider] 用户消息已持久化到MemLocal DB');
      } catch (e) {
        AppLogger.e('[MemoryProvider] MemLocal本地保存失败(非致命): $e');
      }
    }
  }

  Future<void> saveAssistantMessage(
    String conversationId,
    String content,
  ) async {
    final session = getSession(conversationId);
    if (session != null && _isMemLocalReady) {
      try {
        unawaited(session.saveAssistantMessage(content: content));
      } catch (e) {
        AppLogger.e('[MemoryProvider] MemLocal保存助手消息失败(非致命): $e');
      }
    }
  }

  Future<String?> generateFallbackResponse(
    String conversationId,
    String userInput,
  ) async {
    final session = getSession(conversationId);
    if (session == null) return null;
    try {
      return await session.generateFallbackResponse(userInput);
    } catch (e) {
      AppLogger.e('[MemoryProvider] 生成降级回复失败: $e');
      return null;
    }
  }

  Future<void> addConversationMemory(
    String conversationId,
    List<Message> messages,
  ) async {
    if (_isMemUReady) {
      try {
        await _memuService.addConversationMemory(conversationId, messages);
      } catch (e) {
        AppLogger.e('[MemoryProvider] MemU记忆写入失败(非致命): $e');
      }
    }
  }

  // ── 人格保护相关方法 ──

  /// 在systemPrompt变更前创建快照
  Future<void> snapshotBeforePromptChange({
    required String conversationId,
    required String conversationName,
    required String oldSystemPrompt,
  }) async {
    if (!_isSnapshotReady) return;

    final personaMemories = _getPersonaMemories(conversationId);
    await _snapshotService.snapshotBeforePromptChange(
      conversationId: conversationId,
      conversationName: conversationName,
      oldSystemPrompt: oldSystemPrompt,
      personaMemories: personaMemories,
    );
  }

  /// 检测systemPrompt变更并自动快照
  Future<void> checkPromptChangeAndSnapshot({
    required String conversationId,
    required String conversationName,
    required String currentPrompt,
  }) async {
    if (!_isSnapshotReady) return;

    final personaMemories = _getPersonaMemories(conversationId);
    await _snapshotService.checkPromptChange(
      conversationId: conversationId,
      conversationName: conversationName,
      currentPrompt: currentPrompt,
      personaMemories: personaMemories,
    );
  }

  /// 定期自动快照（由外部定时器调用）
  Future<void> performAutoSnapshot({
    required String conversationId,
    required String conversationName,
    required String systemPrompt,
  }) async {
    if (!_isSnapshotReady) return;

    final personaMemories = _getPersonaMemories(conversationId);
    await _snapshotService.performAutoSnapshot(
      conversationId: conversationId,
      conversationName: conversationName,
      systemPrompt: systemPrompt,
      personaMemories: personaMemories,
    );
  }

  /// 检测指定会话的人格完整性
  Future<RecoveryCheckResult> checkPersonaIntegrity({
    required String conversationId,
    required String currentPrompt,
  }) async {
    if (!_isRecoveryReady) {
      return RecoveryCheckResult(
        conversationId: conversationId,
        needsRecovery: false,
        description: '恢复服务未就绪',
      );
    }

    final personaMemories = _getPersonaMemories(conversationId);
    return _recoveryService.checkPersonaIntegrity(
      conversationId: conversationId,
      currentPrompt: currentPrompt,
      currentPersonaMemories: personaMemories,
    );
  }

  /// 从快照恢复人格
  Future<RecoveryResult> recoverPersona({
    required String conversationId,
    String? snapshotId,
    bool restorePrompt = true,
    bool restoreMemories = true,
  }) async {
    if (!_isRecoveryReady) {
      return RecoveryResult(
        success: false,
        conversationId: conversationId,
        message: '恢复服务未就绪',
      );
    }

    return _recoveryService.recoverFromSnapshot(
      conversationId: conversationId,
      snapshotId: snapshotId,
      restorePrompt: restorePrompt,
      restoreMemories: restoreMemories,
    );
  }

  /// 获取指定会话的人格相关记忆
  List<MemoryFragment> _getPersonaMemories(String conversationId) {
    if (!_isMemUReady) return [];

    final allMemories = _memuService.getAllMemories();
    return allMemories
        .where(
          (m) =>
              m.conversationId == conversationId &&
              m.isActive &&
              (m.type == MemoryType.longTerm || m.type == MemoryType.keyInfo),
        )
        .toList();
  }

  @override
  void dispose() {
    // 防御 double dispose：getter 公开导致外部可能拿到引用误调 dispose。
    // 为什么这样做：ChangeNotifier 重复 dispose 会抛 "used after disposed" 断言。
    if (_disposed) return;
    _disposed = true;
    _memuService.removeInitListener(_onMemUInitChanged);
    _memLocalService.removeInitListener(_onMemLocalInitChanged);
    super.dispose();
  }
}
