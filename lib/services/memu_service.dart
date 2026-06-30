import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:hive/hive.dart';
import 'package:path_provider/path_provider.dart';

import '../core/logger/app_logger.dart';
import '../models/message.dart';
import 'memory_conflict_resolver.dart';
import 'memory_semantic_scorer.dart';
import 'memory_vector_search.dart';

/// 记忆片段类型
enum MemoryType { shortTerm, longTerm, theme, keyInfo }

enum MemoryStatus { active, superseded, conflicted }

class MemoryFragment {
  final String id;
  final String conversationId;
  final MemoryType type;
  final String content;
  final List<String> keywords;
  final double importance;
  final DateTime createdAt;
  final DateTime lastAccessed;
  final MemoryStatus status;
  final String? supersededBy;
  final String? category;

  MemoryFragment({
    required this.id,
    required this.conversationId,
    required this.type,
    required this.content,
    required this.keywords,
    required this.importance,
    required this.createdAt,
    required this.lastAccessed,
    this.status = MemoryStatus.active,
    this.supersededBy,
    this.category,
  });

  MemoryFragment copyWith({
    MemoryStatus? status,
    String? supersededBy,
    String? category,
    double? importance,
    DateTime? lastAccessed,
    List<String>? keywords,
  }) {
    return MemoryFragment(
      id: id,
      conversationId: conversationId,
      type: type,
      content: content,
      keywords: keywords ?? this.keywords,
      importance: importance ?? this.importance,
      createdAt: createdAt,
      lastAccessed: lastAccessed ?? this.lastAccessed,
      status: status ?? this.status,
      supersededBy: supersededBy ?? this.supersededBy,
      category: category ?? this.category,
    );
  }

  bool get isActive => status == MemoryStatus.active;
  bool get isSuperseded => status == MemoryStatus.superseded;
  bool get isConflicted => status == MemoryStatus.conflicted;

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'conversationId': conversationId,
      'type': type.index,
      'content': content,
      'keywords': keywords,
      'importance': importance,
      'createdAt': createdAt.toIso8601String(),
      'lastAccessed': lastAccessed.toIso8601String(),
      'status': status.index,
      if (supersededBy != null) 'supersededBy': supersededBy,
      if (category != null) 'category': category,
    };
  }

  factory MemoryFragment.fromJson(Map<String, dynamic> json) {
    final typeIndex = json['type'] as int? ?? 0;
    final statusIndex = json['status'] as int? ?? 0;
    return MemoryFragment(
      id: json['id'] as String? ?? '',
      conversationId: json['conversationId'] as String? ?? '',
      type: typeIndex < MemoryType.values.length
          ? MemoryType.values[typeIndex]
          : MemoryType.shortTerm,
      content: json['content'] as String? ?? '',
      keywords:
          (json['keywords'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      importance: (json['importance'] as num?)?.toDouble() ?? 0.5,
      createdAt: json['createdAt'] != null
          ? DateTime.tryParse(json['createdAt'].toString()) ?? DateTime.now()
          : DateTime.now(),
      lastAccessed: json['lastAccessed'] != null
          ? DateTime.tryParse(json['lastAccessed'].toString()) ?? DateTime.now()
          : DateTime.now(),
      status: statusIndex < MemoryStatus.values.length
          ? MemoryStatus.values[statusIndex]
          : MemoryStatus.active,
      supersededBy: json['supersededBy'] as String?,
      category: json['category'] as String?,
    );
  }
}

/// MemU - 智能记忆管理系统
///
/// 提供分层记忆管理：
/// - 短期记忆：最近对话的上下文
/// - 长期记忆：关键信息的持久化存储
/// - 主题记忆：按主题分类的记忆片段
class MemUService {
  static const String _memuBoxName = 'memu_memory';
  static const int _shortTermMemorySize = 10;
  static const int _maxMemoryFragments = 100;
  static const int _maxMemoryPerConversation = 30;
  static const int _maxRetries = 3;
  static const Duration _retryDelay = Duration(milliseconds: 500);

  late Box _memoryBox;
  bool _initialized = false;
  String? _lastError;
  List<Map<String, dynamic>> _pendingWrites = [];
  final List<void Function(bool success, String? error)> _initListeners = [];
  List<MemoryFragment>? _fragmentCache;
  bool _cacheDirty = true;

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
        AppLogger.e('[MemU] 监听器异常: $e');
      }
    }
  }

  Future<bool> init({int maxRetries = _maxRetries}) async {
    for (int attempt = 1; attempt <= maxRetries; attempt++) {
      try {
        _memoryBox = await Hive.openBox(_memuBoxName);
        _initialized = true;
        _lastError = null;

        AppLogger.d('[MemU] 初始化成功 (尝试 $attempt/$maxRetries)');

        _pendingWrites = await _recoverPendingWrites();
        if (_pendingWrites.isNotEmpty) {
          AppLogger.d('[MemU] 恢复 ${_pendingWrites.length} 条待写入记忆');
          await _processPendingWrites();
        }

        _notifyInitListeners(true, null);
        return true;
      } catch (e) {
        _lastError = e.toString();
        AppLogger.e('[MemU] 初始化失败 (尝试 $attempt/$maxRetries): $e');

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

  Future<void> addConversationMemory(
    String conversationId,
    List<Message> messages, {
    int maxRetries = _maxRetries,
  }) async {
    if (!_initialized) {
      AppLogger.w('[MemU] 未初始化，将记忆加入待写队列');
      _addToPendingQueue(conversationId, messages);
      return;
    }

    for (int attempt = 1; attempt <= maxRetries; attempt++) {
      try {
        await _addConversationMemoryWithWAL(conversationId, messages);
        return;
      } catch (e) {
        AppLogger.e('[MemU] 添加对话记忆失败 (尝试 $attempt/$maxRetries): $e');

        if (attempt == maxRetries) {
          AppLogger.w('[MemU] 所有重试失败，保存到待写队列');
          _addToPendingQueue(conversationId, messages);
        } else {
          await Future.delayed(_retryDelay * attempt);
        }
      }
    }
  }

  Future<void> _addConversationMemoryWithWAL(
    String conversationId,
    List<Message> messages,
  ) async {
    final walId = 'wal_${DateTime.now().millisecondsSinceEpoch}';

    try {
      final walData = {
        'id': walId,
        'conversationId': conversationId,
        'messages': messages.map((m) => m.toJson()).toList(),
        'timestamp': DateTime.now().toIso8601String(),
        'status': 'pending',
      };

      await _memoryBox.put(walId, walData);
      AppLogger.d('[MemU-WAL] 写入预日志: $walId');

      await _clearOldShortTermMemories(conversationId);

      final keyInfo = _extractKeyInformation(messages);
      final regexScore = _calculateMessageImportance(messages);

      final content = messages.map((m) => m.content).join('\n');
      final semanticResult = await MemorySemanticScorer.instance.score(
        content: content,
        regexScore: regexScore,
        conversationId: conversationId,
      );

      final shortTermMemory = _createShortTermMemory(
        conversationId,
        messages,
        semanticScore: semanticResult.importance,
        semanticKeywords: semanticResult.semanticKeywords,
        category: semanticResult.category,
      );

      if (_shouldCreateLongTermMemory(messages) ||
          semanticResult.importance >= 0.7) {
        final longTermMemory = _createLongTermMemory(
          conversationId,
          messages,
          keyInfo,
          semanticScore: semanticResult.importance,
          semanticSummary: semanticResult.summary,
          semanticKeywords: semanticResult.semanticKeywords,
          category: semanticResult.category,
        );
        await _saveMemoryFragment(longTermMemory);

        if (semanticResult.hasConflictPotential) {
          await MemoryConflictResolver.instance.detectAndResolve(
            _memoryBox,
            longTermMemory,
          );
        }
      }

      await _saveMemoryFragment(shortTermMemory);
      await _cleanupExpiredMemories();

      MemoryVectorSearch.instance.markDirty();

      walData['status'] = 'completed';
      await _memoryBox.put(walId, walData);

      await _memoryBox.delete(walId);
      _cacheDirty = true;
      AppLogger.d('[MemU-WAL] 清理预日志: $walId');
    } catch (e) {
      AppLogger.e('[MemU-WAL] 操作异常，标记预日志为failed: $e');
      try {
        final walEntry = _memoryBox.get(walId);
        if (walEntry != null && walEntry is Map<String, dynamic>) {
          walEntry['status'] = 'failed';
          walEntry['error'] = e.toString();
          await _memoryBox.put(walId, walEntry);
        }
      } catch (logError) {
        AppLogger.e('[MemU-WAL] 更新预日志状态失败: $logError');
      }
      rethrow;
    }
  }

  void _addToPendingQueue(String conversationId, List<Message> messages) {
    _pendingWrites.add({
      'conversationId': conversationId,
      'messages': messages.map((m) => m.toJson()).toList(),
      'timestamp': DateTime.now().toIso8601String(),
      'retries': 0,
    });
    AppLogger.d('[MemU] 已加入待写队列，当前队列长度: ${_pendingWrites.length}');
  }

  Future<List<Map<String, dynamic>>> _recoverPendingWrites() async {
    if (!_initialized) return [];

    final recovered = <Map<String, dynamic>>[];

    try {
      for (final key in _memoryBox.keys) {
        final data = _memoryBox.get(key);
        if (data is Map<String, dynamic> &&
            key is String &&
            key.startsWith('wal_')) {
          final status = data['status'];
          if (status == 'pending' || status == 'failed') {
            recovered.add({
              'conversationId': data['conversationId'],
              'messages': data['messages'],
              'timestamp':
                  data['timestamp'] ?? DateTime.now().toIso8601String(),
              'retries': 0,
              'walId': key,
            });
            AppLogger.d('[MemU] 发现未完成的WAL记录: $key');
          } else if (status == 'completed') {
            await _memoryBox.delete(key);
          }
        }
      }

      final pendingFile = File(
        '${(await getApplicationDocumentsDirectory()).path}/$_memuBoxName/_pending.json',
      );
      if (pendingFile.existsSync()) {
        try {
          final content = pendingFile.readAsStringSync();
          final list = jsonDecode(content) as List<dynamic>;
          for (final item in list) {
            recovered.add(item as Map<String, dynamic>);
          }
          AppLogger.d('[MemU] 从文件恢复 ${list.length} 条待写记录');
        } catch (e) {
          AppLogger.e('[MemU] 读取待写文件失败: $e');
        }
      }
    } catch (e) {
      AppLogger.e('[MemU] 恢复待写记录失败: $e');
    }

    return recovered;
  }

  Future<void> _processPendingWrites() async {
    if (!_initialized || _pendingWrites.isEmpty) return;

    final toProcess = List<Map<String, dynamic>>.from(_pendingWrites);
    _pendingWrites.clear();

    int successCount = 0;
    int failCount = 0;

    for (final item in toProcess) {
      try {
        final convId = item['conversationId'] as String;
        final msgsJson = item['messages'] as List<dynamic>;
        final messages = msgsJson
            .map((m) => Message.fromJson(m as Map<String, dynamic>))
            .toList();

        await _addConversationMemoryWithWAL(convId, messages);

        if (item.containsKey('walId')) {
          await _memoryBox.delete(item['walId']);
        }

        successCount++;
        AppLogger.d('[MemU] 待写队列处理成功: $convId');
      } catch (e) {
        item['retries'] = (item['retries'] ?? 0) + 1;
        if ((item['retries'] as int) < 3) {
          _pendingWrites.add(item);
        }
        failCount++;
        AppLogger.e('[MemU] 待写队列处理失败: $e');
      }
    }

    if (_pendingWrites.isNotEmpty) {
      await _persistPendingWrites();
    }

    AppLogger.d(
      '[MemU] 待写队列处理完成: 成功=$successCount, 失败=$failCount, 剩余=${_pendingWrites.length}',
    );
  }

  Future<void> _persistPendingWrites() async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final dir = Directory('${appDir.path}/$_memuBoxName');
      if (!dir.existsSync()) {
        dir.createSync(recursive: true);
      }
      final file = File('${dir.path}/_pending.json');
      file.writeAsStringSync(jsonEncode(_pendingWrites));
      AppLogger.d('[MemU] 已持久化 ${_pendingWrites.length} 条待写记录到文件');
    } catch (e) {
      AppLogger.e('[MemU] 持久化待写记录失败: $e');
    }
  }

  Future<void> retryPendingWrites() async {
    if (!_initialized) {
      AppLogger.w('[MemU] 未初始化，无法重试');
      return;
    }
    AppLogger.d('[MemU] 开始重试 ${_pendingWrites.length} 条待写记忆...');
    await _processPendingWrites();
  }

  int get pendingWritesCount => _pendingWrites.length;

  /// 清理指定会话的旧短期记忆
  Future<void> _clearOldShortTermMemories(String conversationId) async {
    final keysToDelete = <dynamic>[];

    for (final key in _memoryBox.keys) {
      final data = _memoryBox.get(key);
      if (data is Map<String, dynamic>) {
        final fragment = MemoryFragment.fromJson(data);
        if (fragment.conversationId == conversationId &&
            fragment.type == MemoryType.shortTerm) {
          keysToDelete.add(key);
        }
      }
    }

    for (final key in keysToDelete) {
      await _memoryBox.delete(key);
    }
  }

  /// 获取相关记忆上下文
  Future<List<Message>> getMemoryContext(
    String conversationId,
    String currentQuery,
  ) async {
    if (!_initialized) return [];

    try {
      final memories = await _getRelevantMemories(conversationId, currentQuery);

      if (memories.isEmpty) return [];

      // 构建记忆上下文
      final memoryText = memories.map((m) => m.content).join('\n---\n');

      return [
        Message(role: 'system', content: '以下是相关的对话记忆，请参考这些上下文：\n$memoryText'),
      ];
    } catch (e) {
      AppLogger.e('[MemU] 获取记忆上下文失败: $e');
      return [];
    }
  }

  /// 提取关键信息
  List<String> _extractKeyInformation(List<Message> messages) {
    final keyInfo = <String>[];

    for (final message in messages) {
      if (message.role == 'user' || message.role == 'assistant') {
        final content = message.content.toLowerCase();

        // 提取姓名、地点、时间等关键信息
        if (content.contains('我叫') || content.contains('名字是')) {
          final nameMatch = RegExp(r'(我叫|名字是)[\s\S]{1,20}').firstMatch(content);
          if (nameMatch != null) {
            keyInfo.add('姓名信息: ${nameMatch.group(0)}');
          }
        }

        if (content.contains('住在') || content.contains('地址')) {
          final locationMatch = RegExp(
            r'(住在|地址)[\s\S]{1,30}',
          ).firstMatch(content);
          if (locationMatch != null) {
            keyInfo.add('位置信息: ${locationMatch.group(0)}');
          }
        }

        // 提取数字信息（年龄、数量等）
        final numberMatches = RegExp(r'\b\d+\b').allMatches(content);
        for (final match in numberMatches) {
          final context = content.substring(
            max(0, match.start - 10),
            min(content.length, match.end + 10),
          );
          keyInfo.add('数字信息: $context');
        }
      }
    }

    return keyInfo;
  }

  MemoryFragment _createShortTermMemory(
    String conversationId,
    List<Message> messages, {
    double semanticScore = 0.3,
    List<String> semanticKeywords = const [],
    String? category,
  }) {
    final recentMessages = messages.length > _shortTermMemorySize
        ? messages.sublist(messages.length - _shortTermMemorySize)
        : messages;

    final content = recentMessages
        .map((m) => '${m.role}: ${m.content}')
        .join('\n');

    final allKeywords = <String>[
      ..._extractKeywords(content),
      ...semanticKeywords,
    ];

    return MemoryFragment(
      id: 'short_${conversationId}_${DateTime.now().millisecondsSinceEpoch}',
      conversationId: conversationId,
      type: MemoryType.shortTerm,
      content: '最近对话:\n$content',
      keywords: allKeywords.toSet().take(15).toList(),
      importance: semanticScore,
      createdAt: DateTime.now(),
      lastAccessed: DateTime.now(),
      category: category,
    );
  }

  MemoryFragment _createLongTermMemory(
    String conversationId,
    List<Message> messages,
    List<String> keyInfo, {
    double semanticScore = 0.8,
    String semanticSummary = '',
    List<String> semanticKeywords = const [],
    String? category,
  }) {
    final summary = semanticSummary.isNotEmpty
        ? semanticSummary
        : _summarizeConversation(messages);

    final allKeywords = <String>[
      ..._extractKeywords(summary + keyInfo.join(' ')),
      ...semanticKeywords,
    ];

    return MemoryFragment(
      id: 'long_${conversationId}_${DateTime.now().millisecondsSinceEpoch}',
      conversationId: conversationId,
      type: MemoryType.longTerm,
      content: '对话摘要:\n$summary\n\n关键信息:\n${keyInfo.join("\n")}',
      keywords: allKeywords.toSet().take(15).toList(),
      importance: semanticScore,
      createdAt: DateTime.now(),
      lastAccessed: DateTime.now(),
      category: category,
    );
  }

  bool _shouldCreateLongTermMemory(List<Message> messages) {
    if (messages.length < 3) return false;

    final content = messages.map((m) => m.content).join(' ').toLowerCase();

    final personalInfoPatterns = [
      r'我叫|名字是|我是',
      r'住在|地址|家住',
      r'\d+岁|年龄|生日',
      r'喜欢|爱好|兴趣',
      r'工作|职业|公司',
      r'记住|重要|别忘',
      r'承诺|保证|一定',
      r'决定|计划|打算',
      r'家人|父母|孩子|配偶',
      r'健康|生病|医生|医院',
    ];

    int matchCount = 0;
    for (final pattern in personalInfoPatterns) {
      if (RegExp(pattern).hasMatch(content)) {
        matchCount++;
      }
    }

    final hasRichContent =
        messages.length > 8 || content.length > 200 || matchCount >= 2;

    final hasStrongSignal =
        matchCount >= 3 || content.contains('记住') || content.contains('重要');

    return hasStrongSignal || (hasRichContent && messages.length > 5);
  }

  double _calculateMessageImportance(List<Message> messages) {
    if (messages.isEmpty) return 0.0;

    double score = 0.0;
    final allContent = messages.map((m) => m.content).join(' ').toLowerCase();

    final importanceSignals = {
      '个人信息': [r'我叫|名字是', r'\d+岁|年龄', r'生日'],
      '位置信息': [r'住在|地址', r'城市|国家'],
      '偏好': [r'喜欢|爱', r'讨厌|不喜欢', r'习惯'],
      '重要事件': [r'决定|计划', r'承诺|保证', r'约定'],
      '关系网络': [r'家人|朋友|同事', r'父母|孩子|配偶'],
      '健康相关': [r'健康|生病', r'医生|医院', r'药'],
      '工作学习': [r'工作|公司', r'学校|学习', r'项目'],
      '情感表达': [r'开心|难过', r'担心|焦虑', r'希望|梦想'],
    };

    for (final entry in importanceSignals.entries) {
      for (final pattern in entry.value) {
        if (RegExp(pattern).hasMatch(allContent)) {
          score += 0.15;
          break;
        }
      }
    }

    score = score.clamp(0.0, 1.0);

    if (messages.length > 10) {
      score = (score * 1.2).clamp(0.0, 1.0);
    }

    if (allContent.length > 300) {
      score = (score * 1.1).clamp(0.0, 1.0);
    }

    return score;
  }

  /// 对话摘要
  String _summarizeConversation(List<Message> messages) {
    final userMessages = messages.where((m) => m.role == 'user').toList();

    if (userMessages.isEmpty) return '无用户消息';

    // 简单的摘要逻辑（实际应用中可以使用AI进行智能摘要）
    final topics = <String>[];

    for (final message in userMessages.take(3)) {
      final content = message.content.toLowerCase();
      if (content.contains('你好') || content.contains('hello')) {
        topics.add('问候');
      } else if (content.contains('问题') || content.contains('帮助')) {
        topics.add('寻求帮助');
      } else if (content.contains('谢谢') || content.contains('感谢')) {
        topics.add('表达感谢');
      } else {
        topics.add('其他话题');
      }
    }

    return '主要话题: ${topics.join(', ')}';
  }

  /// 提取关键词
  List<String> _extractKeywords(String text) {
    final words = text
        .toLowerCase()
        .replaceAll(RegExp(r'[^\w\s\u4e00-\u9fff]'), ' ')
        .split(RegExp(r'\s+'))
        .where((word) => word.length > 1)
        .toList();

    // 简单的词频统计
    final wordCount = <String, int>{};
    for (final word in words) {
      wordCount[word] = (wordCount[word] ?? 0) + 1;
    }

    // 按词频降序排序，取前 10 个
    // 之前只保留词频 > 1 的词，导致单次出现的关键词被丢弃，召回率过低
    final sortedEntries = wordCount.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return sortedEntries.take(10).map((entry) => entry.key).toList();
  }

  /// 保存记忆片段
  Future<void> _saveMemoryFragment(MemoryFragment fragment) async {
    await _memoryBox.put(fragment.id, fragment.toJson());
    _cacheDirty = true;
  }

  Future<List<MemoryFragment>> _getRelevantMemories(
    String conversationId,
    String query,
  ) async {
    List<MemoryFragment> allFragments;

    if (_cacheDirty || _fragmentCache == null) {
      allFragments = <MemoryFragment>[];
      for (final key in _memoryBox.keys) {
        final data = _memoryBox.get(key);
        if (data is Map<String, dynamic>) {
          final fragment = MemoryFragment.fromJson(data);
          if (fragment.isActive) {
            allFragments.add(fragment);
          }
        }
      }
      _fragmentCache = allFragments;
      _cacheDirty = false;
    } else {
      allFragments = _fragmentCache!;
    }

    // 跨会话检索策略：
    // - shortTerm（短期记忆）：只检索当前会话，避免其他会话的临时上下文干扰
    // - longTerm/keyInfo/theme（长期记忆/关键信息/主题）：跨会话检索，
    //   这是 MemU 作为"跨会话语义记忆"的核心职责
    //   之前所有类型都硬性过滤 conversationId，导致跨会话记忆完全无法召回
    final currentConvFragments = allFragments
        .where((f) => f.conversationId == conversationId)
        .toList();

    final crossConvFragments = allFragments
        .where(
          (f) =>
              f.conversationId != conversationId &&
              (f.type == MemoryType.longTerm ||
                  f.type == MemoryType.keyInfo ||
                  f.type == MemoryType.theme),
        )
        .toList();

    final searchableFragments = [
      ...currentConvFragments,
      ...crossConvFragments,
    ];

    if (searchableFragments.isEmpty) return [];

    final vectorResults = MemoryVectorSearch.instance.search(
      query,
      searchableFragments,
      topK: 5,
      minScore: 0.01, // 降低门槛，避免字面匹配差异导致召回率过低
    );

    final vectorScoreMap = <String, double>{};
    for (final (fragment, score) in vectorResults) {
      vectorScoreMap[fragment.id] = score;
    }

    searchableFragments.sort((a, b) {
      final aKeyword = _calculateRelevanceScore(a, query);
      final bKeyword = _calculateRelevanceScore(b, query);
      final aVector = vectorScoreMap[a.id] ?? 0.0;
      final bVector = vectorScoreMap[b.id] ?? 0.0;

      final aFinal = aKeyword * 0.4 + aVector * 0.6;
      final bFinal = bKeyword * 0.4 + bVector * 0.6;
      return bFinal.compareTo(aFinal);
    });

    return searchableFragments.take(3).toList();
  }

  /// 计算相关性分数
  double _calculateRelevanceScore(MemoryFragment fragment, String query) {
    double score = 0.0;

    // 关键词匹配
    final queryKeywords = _extractKeywords(query);
    for (final keyword in queryKeywords) {
      if (fragment.keywords.contains(keyword)) {
        score += 0.5;
      }
      if (fragment.content.toLowerCase().contains(keyword)) {
        score += 0.3;
      }
    }

    // 重要性加权
    score += fragment.importance * 0.2;

    // 时间衰减（越新的记忆分数越高）
    // 将衰减周期从 1 周（168 小时）延长到 4 周（672 小时），
    // 避免短期记忆在几天内就被大幅降权
    final hoursSinceAccess = DateTime.now()
        .difference(fragment.lastAccessed)
        .inHours;
    final timeDecay = max(0, 1 - hoursSinceAccess / 672); // 四周衰减
    score *= timeDecay;

    return score;
  }

  Future<void> _cleanupExpiredMemories() async {
    final allFragments = <MemoryFragment>[];

    for (final key in _memoryBox.keys) {
      final data = _memoryBox.get(key);
      if (data is Map<String, dynamic> && !key.toString().startsWith('wal_')) {
        allFragments.add(MemoryFragment.fromJson(data));
      }
    }

    final conversationGroups = <String, List<MemoryFragment>>{};
    for (final fragment in allFragments) {
      conversationGroups.putIfAbsent(fragment.conversationId, () => []);
      conversationGroups[fragment.conversationId]!.add(fragment);
    }

    for (final entry in conversationGroups.entries) {
      final convId = entry.key;
      final convMemories = entry.value;

      if (convMemories.length > _maxMemoryPerConversation) {
        convMemories.sort((a, b) {
          final aScore = _calculateCompositeScore(a);
          final bScore = _calculateCompositeScore(b);
          return bScore.compareTo(aScore);
        });

        final toRemove = convMemories.sublist(_maxMemoryPerConversation);
        for (final fragment in toRemove) {
          if (fragment.type != MemoryType.longTerm ||
              fragment.importance < 0.7) {
            await _memoryBox.delete(fragment.id);
            AppLogger.d('[MemU] 清理会话 $convId 的低价值记忆: ${fragment.id}');
          }
        }
      }
    }

    final remaining = <MemoryFragment>[];
    for (final key in _memoryBox.keys) {
      final data = _memoryBox.get(key);
      if (data is Map<String, dynamic> && !key.toString().startsWith('wal_')) {
        remaining.add(MemoryFragment.fromJson(data));
      }
    }

    if (remaining.length > _maxMemoryFragments) {
      remaining.sort((a, b) {
        final aScore = _calculateCompositeScore(a);
        final bScore = _calculateCompositeScore(b);
        return bScore.compareTo(aScore);
      });

      while (remaining.length > _maxMemoryFragments) {
        final leastImportant = remaining.removeLast();
        await _memoryBox.delete(leastImportant.id);
        AppLogger.d(
          '[MemU] 全局清理低价值记忆: ${leastImportant.id} (重要性: ${leastImportant.importance})',
        );
      }
    }

    _cacheDirty = true;
  }

  double _calculateCompositeScore(MemoryFragment fragment) {
    double score = fragment.importance * 0.5;

    if (fragment.type == MemoryType.longTerm) {
      score += 0.3;
    } else if (fragment.type == MemoryType.keyInfo) {
      score += 0.25;
    }

    final hoursSinceAccess = DateTime.now()
        .difference(fragment.lastAccessed)
        .inHours;
    final timeDecay = max(0, 1 - hoursSinceAccess / 720);
    score *= timeDecay;

    if (fragment.keywords.length >= 3) {
      score += 0.1;
    }

    return score;
  }

  /// 获取记忆统计信息
  Future<Map<String, dynamic>> getMemoryStats() async {
    if (!_initialized) return {};

    final allFragments = <MemoryFragment>[];

    for (final key in _memoryBox.keys) {
      final data = _memoryBox.get(key);
      if (data is Map<String, dynamic>) {
        allFragments.add(MemoryFragment.fromJson(data));
      }
    }

    return {
      'totalFragments': allFragments.length,
      'shortTermCount': allFragments
          .where((m) => m.type == MemoryType.shortTerm)
          .length,
      'longTermCount': allFragments
          .where((m) => m.type == MemoryType.longTerm)
          .length,
      'themeCount': allFragments
          .where((m) => m.type == MemoryType.theme)
          .length,
      'keyInfoCount': allFragments
          .where((m) => m.type == MemoryType.keyInfo)
          .length,
    };
  }

  List<MemoryFragment> getAllMemories() {
    if (!_initialized) return [];
    final fragments = <MemoryFragment>[];
    for (final key in _memoryBox.keys) {
      final data = _memoryBox.get(key);
      if (data is Map<String, dynamic> &&
          !key.toString().startsWith('wal_') &&
          !key.toString().startsWith('test_')) {
        fragments.add(MemoryFragment.fromJson(data));
      }
    }
    return fragments;
  }

  Future<void> deleteMemory(String fragmentId) async {
    if (!_initialized) return;
    await _memoryBox.delete(fragmentId);
    _cacheDirty = true;
    MemoryVectorSearch.instance.markDirty();
  }

  Future<void> updateMemory(MemoryFragment fragment) async {
    if (!_initialized) return;
    await _memoryBox.put(fragment.id, fragment.toJson());
    MemoryVectorSearch.instance.markDirty();
  }

  /// 清空所有记忆
  Future<void> clearAllMemories() async {
    if (!_initialized) return;

    await _memoryBox.clear();
    AppLogger.d('[MemU] 所有记忆已清空');
  }

  /// 关闭服务
  Future<void> close() async {
    if (_initialized) {
      await _memoryBox.close();
      _initialized = false;
    }
  }

  // ==========================================
  // 测试专用方法 - 带【测试标记】
  // ==========================================

  static const String _testMemoryPrefix = 'test_memory_';
  static const String _testConversationPrefix = 'test_conv_';
  int _testIdCounter = 0;
  int _testConvCounter = 0;

  /// 添加测试记忆（带测试标记）
  Future<void> addTestMemory({
    required String conversationId,
    required String content,
    MemoryType type = MemoryType.shortTerm,
    double importance = 0.5,
    List<String>? keywords,
  }) async {
    if (!_initialized) return;

    final testId =
        '$_testMemoryPrefix${DateTime.now().millisecondsSinceEpoch}_${_testIdCounter++}';
    final fragment = MemoryFragment(
      id: testId,
      conversationId: conversationId,
      type: type,
      content: content,
      keywords: keywords ?? _extractKeywords(content),
      importance: importance,
      createdAt: DateTime.now(),
      lastAccessed: DateTime.now(),
    );

    await _saveMemoryFragment(fragment);
    AppLogger.d('[MemU-Test] 添加测试记忆: $testId');
  }

  /// 提取测试记忆（带测试标记，只提取测试记忆）
  Future<List<MemoryFragment>> extractTestMemory(
    String conversationId,
    String query,
  ) async {
    if (!_initialized) return [];

    try {
      final allFragments = <MemoryFragment>[];

      for (final key in _memoryBox.keys) {
        final data = _memoryBox.get(key);
        if (data is Map<String, dynamic>) {
          final fragment = MemoryFragment.fromJson(data);
          // 只返回测试记忆且属于当前会话的
          if (fragment.id.startsWith(_testMemoryPrefix) &&
              fragment.conversationId == conversationId) {
            allFragments.add(fragment);
          }
        }
      }

      // 按相关性排序
      allFragments.sort((a, b) {
        final aScore = _calculateRelevanceScore(a, query);
        final bScore = _calculateRelevanceScore(b, query);
        return bScore.compareTo(aScore);
      });

      return allFragments;
    } catch (e) {
      AppLogger.e('[MemU-Test] 提取测试记忆失败: $e');
      return [];
    }
  }

  /// 清空所有测试记忆（不影响正常记忆）
  Future<void> clearAllTestMemory() async {
    if (!_initialized) return;

    final keysToDelete = <dynamic>[];

    for (final key in _memoryBox.keys) {
      if (key is String && key.startsWith(_testMemoryPrefix)) {
        keysToDelete.add(key);
      }
    }

    for (final key in keysToDelete) {
      await _memoryBox.delete(key);
    }

    AppLogger.d('[MemU-Test] 已清理 ${keysToDelete.length} 条测试记忆');
  }

  /// 创建临时测试会话（不影响正常会话）
  String createTempConversation() {
    return '$_testConversationPrefix${DateTime.now().millisecondsSinceEpoch}_${_testConvCounter++}';
  }

  /// 检查是否是测试记忆
  bool isTestMemory(MemoryFragment fragment) {
    return fragment.id.startsWith(_testMemoryPrefix);
  }

  /// 检查是否是测试会话
  bool isTestConversation(String conversationId) {
    return conversationId.startsWith(_testConversationPrefix);
  }

  /// 获取所有测试记忆
  Future<List<MemoryFragment>> getAllTestMemories() async {
    if (!_initialized) return [];

    final testFragments = <MemoryFragment>[];

    for (final key in _memoryBox.keys) {
      final data = _memoryBox.get(key);
      if (data is Map<String, dynamic>) {
        final fragment = MemoryFragment.fromJson(data);
        if (fragment.id.startsWith(_testMemoryPrefix)) {
          testFragments.add(fragment);
        }
      }
    }

    return testFragments;
  }
}
