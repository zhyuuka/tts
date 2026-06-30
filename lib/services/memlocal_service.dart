import 'dart:async';
import 'dart:convert';

import 'package:hive/hive.dart';

import '../core/logger/app_logger.dart';

class MemLocalService {
  static const String _conversationsBox = 'memlocal_conversations';
  static const String _messagesBox = 'memlocal_messages';
  static const String _walBoxName = 'memlocal_wal';

  static const int _maxRetries = 3;
  static const Duration _retryDelay = Duration(milliseconds: 500);

  late Box _convBox;
  late Box _msgBox;
  late Box _walBox;

  bool _initialized = false;
  String? _lastError;

  final List<void Function(bool success, String? error)> _initListeners = [];

  bool get isInitialized => _initialized;
  String? get lastError => _lastError;

  void addInitListener(void Function(bool success, String? error) listener) {
    _initListeners.add(listener);
  }

  void removeInitListener(void Function(bool success, String? error) listener) {
    _initListeners.remove(listener);
  }

  void _notifyInitListeners(bool success, String? error) {
    for (final listener in _initListeners) {
      try {
        listener(success, error);
      } catch (e) {
        AppLogger.e('[MemLocal] 监听器异常: $e');
      }
    }
  }

  Future<bool> init({int maxRetries = _maxRetries}) async {
    for (int attempt = 1; attempt <= maxRetries; attempt++) {
      try {
        _convBox = await Hive.openBox(_conversationsBox);
        _msgBox = await Hive.openBox(_messagesBox);
        _walBox = await Hive.openBox(_walBoxName);

        _initialized = true;
        _lastError = null;

        AppLogger.d('[MemLocal] 初始化成功 (Hive模式, 尝试 $attempt/$maxRetries)');

        await _recoverPendingTransactions();

        _notifyInitListeners(true, null);
        return true;
      } catch (e) {
        _lastError = e.toString();
        AppLogger.e('[MemLocal] 初始化失败 (尝试 $attempt/$maxRetries): $e');

        if (attempt < maxRetries) {
          await Future.delayed(_retryDelay * attempt);
        } else {
          _initialized = false;
          _notifyInitListeners(false, e.toString());
          return false;
        }
      }
    }
    return false;
  }

  Future<MemLocalSession> initSession(String conversationId) async {
    if (!_initialized) {
      throw StateError('MemLocal未初始化');
    }

    final existingConv = _convBox.get(conversationId);

    if (existingConv == null) {
      await _convBox.put(conversationId, <String, dynamic>{
        'title': '新的对话',
        'createdAt': DateTime.now().toIso8601String(),
        'updatedAt': DateTime.now().toIso8601String(),
      });

      AppLogger.d('[MemLocal] 创建新会话记录: $conversationId');
    }

    return MemLocalSession._(this, conversationId);
  }

  Future<void> _executeWithWAL({
    required String operationType,
    required Map<String, dynamic> payload,
    required Future<void> Function() operation,
  }) async {
    final walId = 'wal_${DateTime.now().millisecondsSinceEpoch}';

    final Map<String, dynamic> walData = <String, dynamic>{
      'walId': walId,
      'timestamp': DateTime.now().toIso8601String(),
      'status': 'pending',
      'operationType': operationType,
      'payload': jsonEncode(payload),
      'retryCount': 0,
    };

    await _walBox.put(walId, walData);

    try {
      await operation();

      walData['status'] = 'completed';
      await _walBox.put(walId, walData);
      await _walBox.delete(walId);
    } catch (e) {
      AppLogger.e('[MemLocal-WAL] 操作异常: $e');

      walData['status'] = 'failed';
      walData['errorMessage'] = e.toString();
      final currentRetry = walData['retryCount'] as int? ?? 0;
      walData['retryCount'] = currentRetry + 1;
      await _walBox.put(walId, walData);

      rethrow;
    }
  }

  Future<void> _recoverPendingTransactions() async {
    final rawWals = _walBox.values.toList();
    final allWals =
        rawWals.where((w) {
          final status = w['status']?.toString();
          return status == 'pending' || status == 'failed';
        }).toList()..sort(
          (a, b) => DateTime.parse(
            b['timestamp'].toString(),
          ).compareTo(DateTime.parse(a['timestamp'].toString())),
        );

    if (allWals.isEmpty) return;

    AppLogger.d('[MemLocal] 发现 ${allWals.length} 个待恢复事务');

    for (final wal in allWals) {
      final retryCount = wal['retryCount'];
      final retries = retryCount is int
          ? retryCount
          : (int.tryParse(retryCount.toString()) ?? 0);
      if (retries >= _maxRetries) {
        continue;
      }

      try {
        final payloadStr = wal['payload'].toString();
        final payload = jsonDecode(payloadStr) as Map<String, dynamic>;

        final opType = wal['operationType'].toString();
        switch (opType) {
          case 'add_message':
            await _replayAddMessage(payload);
            break;
          case 'add_fragment':
            // 为什么这样做：片段存储已移除（职责归 MemU），旧 WAL 中的
            // add_fragment 记录直接删除，不重放。
            AppLogger.d('[MemLocal] 跳过已废弃的 add_fragment WAL 记录');
            break;
        }

        final walId = wal['walId'].toString();
        await _walBox.delete(walId);
      } catch (e) {
        AppLogger.e('[MemLocal] 恢复事务失败: $e');
        final currentRetry = wal['retryCount'];
        final retries = currentRetry is int
            ? currentRetry
            : (int.tryParse(currentRetry.toString()) ?? 0);
        wal['retryCount'] = retries + 1;
        final walId = wal['walId'].toString();
        await _walBox.put(walId, wal);
      }
    }
  }

  Future<void> _replayAddMessage(Map<String, dynamic> payload) async {
    final convId = payload['conversationId'].toString();
    final rawMessages = _msgBox.get(convId);
    final messages = rawMessages is List
        ? List<Map<String, dynamic>>.from(rawMessages)
        : <Map<String, dynamic>>[];

    messages.add(<String, dynamic>{
      'timestamp': payload['timestamp'],
      'role': payload['role'],
      'content': payload['content'],
    });

    await _msgBox.put(convId, messages);
  }

  Future<Map<String, dynamic>> getStats() async {
    if (!_initialized) return {};

    int totalMessages = 0;

    for (final key in _msgBox.keys) {
      final msgs = _msgBox.get(key);
      totalMessages += msgs is List ? msgs.length : 0;
    }

    int pendingWals = 0;
    for (final v in _walBox.values) {
      if (v['status']?.toString() == 'pending') pendingWals++;
    }

    return <String, dynamic>{
      'totalMessages': totalMessages,
      'totalConversations': _convBox.length,
      'pendingTransactions': pendingWals,
      'dbSize': 'Hive DB',
    };
  }

  Future<void> clearAllData() async {
    if (!_initialized) return;

    await _convBox.clear();
    await _msgBox.clear();
    await _walBox.clear();

    AppLogger.d('[MemLocal] 所有数据已清空');
  }

  void dispose() {
    if (_initialized) {
      _convBox.close();
      _msgBox.close();
      _walBox.close();
      _initialized = false;
      AppLogger.d('[MemLocal] 服务已关闭');
    }
  }
}

class MemLocalSession {
  final MemLocalService _service;
  final String conversationId;

  MemLocalSession._(this._service, this.conversationId);

  List<Map<String, dynamic>> _getConversationMessages() {
    final raw = _service._msgBox.get(conversationId);
    if (raw is! List) return <Map<String, dynamic>>[];
    return raw
        .map((e) => e is Map<String, dynamic> ? e : <String, dynamic>{})
        .toList()
      ..sort(
        (a, b) => DateTime.parse(
          (b['timestamp'] ?? '').toString(),
        ).compareTo(DateTime.parse((a['timestamp'] ?? '').toString())),
      );
  }

  Future<MemoryMessage> saveUserMessage({
    required String content,
    List<String>? attachments,
  }) async {
    final messageMap = <String, dynamic>{
      'timestamp': DateTime.now().toIso8601String(),
      'role': 'user',
      'content': content,
      'attachments': attachments,
      'isSummarized': false,
    };

    await _service._executeWithWAL(
      operationType: 'add_message',
      payload: <String, dynamic>{
        'conversationId': conversationId,
        ...messageMap,
      },
      operation: () async {
        final messages = _getConversationMessages();
        messages.insert(0, messageMap);

        await _service._msgBox.put(conversationId, messages);

        final convRaw = _service._convBox.get(conversationId);
        if (convRaw is Map) {
          convRaw['updatedAt'] = DateTime.now().toIso8601String();
          await _service._convBox.put(conversationId, convRaw);
        }

        AppLogger.d('[MemLocal-Session] 用户消息已保存: $conversationId');
      },
    );

    return MemoryMessage.fromMap(messageMap);
  }

  Future<MemoryMessage> saveAssistantMessage({
    required String content,
    String? reasoningContent,
  }) async {
    final messageMap = <String, dynamic>{
      'timestamp': DateTime.now().toIso8601String(),
      'role': 'assistant',
      'content': content,
      'reasoningContent': reasoningContent,
      'isSummarized': false,
    };

    await _service._executeWithWAL(
      operationType: 'add_message',
      payload: <String, dynamic>{
        'conversationId': conversationId,
        ...messageMap,
      },
      operation: () async {
        final messages = _getConversationMessages();
        messages.insert(0, messageMap);

        await _service._msgBox.put(conversationId, messages);

        final convRaw = _service._convBox.get(conversationId);
        if (convRaw is Map) {
          convRaw['updatedAt'] = DateTime.now().toIso8601String();
          await _service._convBox.put(conversationId, convRaw);
        }

        AppLogger.d('[MemLocal-Session] AI回复已保存: $conversationId');
      },
    );

    return MemoryMessage.fromMap(messageMap);
  }

  Future<List<String>> getRelevantContext(String query, {int limit = 5}) async {
    // 为什么这样做：原实现基于片段检索，但片段提取逻辑与 MemU 重叠。
    // 改为基于消息原文检索，MemLocal 专注"会话内原文"，MemU 专注"跨会话语义"。
    final messages = _getConversationMessages();
    if (messages.isEmpty) return [];

    final lowerQuery = query.toLowerCase();

    final scored = messages.map((m) {
      double score = 0.0;
      final content = m['content'].toString().toLowerCase();

      // 查询词直接包含加分
      if (lowerQuery.isNotEmpty && content.contains(lowerQuery)) {
        score += 2.0;
      }

      // 查询词分词后命中加分（简单分词：按空格）
      if (lowerQuery.isNotEmpty) {
        for (final word in lowerQuery.split(RegExp(r'\s+'))) {
          if (word.length > 1 && content.contains(word)) {
            score += 0.5;
          }
        }
      }

      // 时间衰减（最近的消息更相关，720 小时 ≈ 30 天）
      final timestamp = m['timestamp']?.toString() ?? '';
      final hoursOld = timestamp.isNotEmpty
          ? DateTime.now().difference(DateTime.parse(timestamp)).inHours
          : 0;
      final timeDecay = (1 - hoursOld / 720).clamp(0.0, 1.0);
      score *= timeDecay;

      return MapEntry(m, score);
    }).toList()..sort((a, b) => b.value.compareTo(a.value));

    // 只返回得分 > 0 的消息，格式为 "role: content"
    return scored
        .where((e) => e.value > 0)
        .take(limit)
        .map((e) => '${e.key['role']}: ${e.key['content']}')
        .toList();
  }

  Future<List<MemoryMessage>> searchMessages(
    String query, {
    int limit = 20,
  }) async {
    final lowerQuery = query.toLowerCase();

    final messages = _getConversationMessages();
    return messages
        .where(
          (m) => m['content'].toString().toLowerCase().contains(lowerQuery),
        )
        .take(limit)
        .map((m) => MemoryMessage.fromMap(m))
        .toList();
  }

  Future<List<MemoryMessage>> getRecentMessages({required int count}) async {
    final messages = _getConversationMessages();
    return messages.take(count).map((m) => MemoryMessage.fromMap(m)).toList();
  }

  Future<String?> generateFallbackResponse(String userQuery) async {
    try {
      final relevantContext = await getRelevantContext(userQuery, limit: 3);

      if (relevantContext.isEmpty) return null;

      // 改进：分类编号展示 + 截断过长片段，提升可读性。
      // 为什么这样做：原代码直接 join 全文，长片段导致回复过长且无结构，
      // 用户难以快速定位相关内容。单条上限 200 字符防溢出。
      final buffer = StringBuffer();
      buffer.writeln('[离线模式]');
      buffer.writeln();
      buffer.writeln('无法连接 AI 服务，以下是可能与您问题相关的历史记录：');
      buffer.writeln();

      for (var i = 0; i < relevantContext.length; i++) {
        final raw = relevantContext[i];
        // 截断过长片段（单条上限 200 字符）
        final snippet = raw.length > 200 ? '${raw.substring(0, 200)}…' : raw;
        buffer.writeln('【记录 ${i + 1}】');
        buffer.writeln(snippet);
        buffer.writeln();
      }

      buffer.writeln('等网络恢复后可获取更详细回复。');
      return buffer.toString();
    } catch (e) {
      AppLogger.e('[MemLocal-Session] 生成降级回复失败: $e');
      return null;
    }
  }
}

enum MessageRole { user, assistant, system }

enum FragmentType { shortTerm, longTerm, keyInfo, theme }

class MemoryMessage {
  final DateTime timestamp;
  final MessageRole role;
  final String content;
  final List<String>? attachments;
  final bool? isSummarized;
  final String? reasoningContent;

  MemoryMessage({
    required this.timestamp,
    required this.role,
    required this.content,
    this.attachments,
    this.isSummarized,
    this.reasoningContent,
  });

  factory MemoryMessage.fromMap(Map<String, dynamic> map) {
    return MemoryMessage(
      timestamp: DateTime.parse(map['timestamp'].toString()),
      role: MessageRole.values.firstWhere(
        (r) => r.name == map['role'].toString(),
        orElse: () => MessageRole.user,
      ),
      content: map['content'].toString(),
      attachments: (() {
        final raw = map['attachments'];
        if (raw == null) return null;
        if (raw is! List) return null;
        return raw.where((e) => e != null).cast<String>().toList();
      })(),
      isSummarized: map['isSummarized'] as bool?,
      reasoningContent: map['reasoningContent'] as String?,
    );
  }
}
