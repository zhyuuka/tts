import 'attachment.dart';
import 'message_part.dart';

class SearchSource {
  final String title;
  final String url;

  const SearchSource({required this.title, required this.url});

  Map<String, dynamic> toJson() => {'title': title, 'url': url};

  factory SearchSource.fromJson(Map<String, dynamic> json) => SearchSource(
    title: json['title'] as String? ?? '',
    url: json['url'] as String? ?? '',
  );
}

class Message {
  final String id;
  final String role;
  final String content;
  final String? reasoningContent;
  final List<Attachment>? attachments;
  final DateTime? timestamp;
  final int? tokenCount;
  final int? wordCount;
  final bool isFallback;
  final String searchQuery;
  final List<SearchSource> searchSources;

  // ── 新结构化内容 ──
  final List<MessagePart>? parts;

  Message({
    String? id,
    required this.role,
    required this.content,
    this.reasoningContent,
    this.attachments,
    this.timestamp,
    this.tokenCount,
    this.wordCount,
    this.isFallback = false,
    this.searchQuery = '',
    this.searchSources = const [],
    this.parts,
  }) : id =
           id ??
           '${DateTime.now().microsecondsSinceEpoch}_${role}_${content.hashCode.toRadixString(36)}';

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{'id': id, 'role': role, 'content': content};
    if (reasoningContent != null && reasoningContent!.isNotEmpty) {
      json['reasoning_content'] = reasoningContent;
    }
    if (attachments != null && attachments!.isNotEmpty) {
      json['attachments'] = attachments!.map((a) => a.toJson()).toList();
    }
    if (timestamp != null) {
      json['timestamp'] = timestamp!.toIso8601String();
    }
    if (tokenCount != null) {
      json['token_count'] = tokenCount;
    }
    if (wordCount != null) {
      json['word_count'] = wordCount;
    }
    if (isFallback) {
      json['is_fallback'] = true;
    }
    if (searchQuery.isNotEmpty) {
      json['search_query'] = searchQuery;
    }
    if (searchSources.isNotEmpty) {
      json['search_sources'] = searchSources.map((s) => s.toJson()).toList();
    }
    if (parts != null && parts!.isNotEmpty) {
      json['parts'] = parts!.map((p) => p.toJson()).toList();
    }
    return json;
  }

  factory Message.fromJson(Map<String, dynamic> json) {
    final role = _getStringValue(json, ['role', 'type']);
    final content = _getStringValue(json, ['content', 'text', 'message']);

    final reasoningContent = _getStringValue(json, [
      'reasoning_content',
      'reasoning',
      'reasoningText',
      'thinking',
    ]);

    List<Attachment>? attachments;
    if (json['attachments'] != null) {
      // 空安全：用 as List? 兜底，类型不符时返回 null
      attachments = (json['attachments'] as List?)
          ?.map((a) => Attachment.fromJson(a as Map<String, dynamic>))
          .toList();
    }

    DateTime? timestamp;
    if (json['timestamp'] != null) {
      // 空安全：用 as String? 兜底，类型不符时 tryParse 返回 null
      timestamp = DateTime.tryParse(json['timestamp'] as String? ?? '');
    }

    int? tokenCount;
    if (json['token_count'] != null) {
      tokenCount = json['token_count'] as int?;
    }

    int? wordCount;
    if (json['word_count'] != null) {
      wordCount = json['word_count'] as int?;
    }

    List<SearchSource> searchSources = const [];
    if (json['search_sources'] != null) {
      // 空安全：用 as List? 兜底，类型不符时保持空列表
      searchSources =
          (json['search_sources'] as List?)
              ?.map((s) => SearchSource.fromJson(s as Map<String, dynamic>))
              .toList() ??
          const [];
    }

    // 读取新 parts 字段；为空时从旧字段自动生成
    List<MessagePart>? parts;
    if (json['parts'] != null) {
      parts = (json['parts'] as List?)
          ?.map((p) => messagePartFromJson(p as Map<String, dynamic>))
          .toList();
    }
    parts ??= _partsFromLegacyFields(
      content: content,
      reasoningContent: reasoningContent,
      searchQuery: json['search_query'] as String? ?? '',
      searchSources: searchSources,
      attachments: attachments,
    );

    return Message(
      id: json['id'] as String?,
      role: role ?? 'user',
      content: content ?? '',
      reasoningContent: reasoningContent,
      attachments: attachments,
      timestamp: timestamp,
      tokenCount: tokenCount,
      wordCount: wordCount,
      isFallback: json['is_fallback'] as bool? ?? false,
      searchQuery: json['search_query'] as String? ?? '',
      searchSources: searchSources,
      parts: parts,
    );
  }

  /// 从旧字段生成 parts（仅当 JSON 中没有 parts 时调用）
  ///
  /// 为什么这样做：保证旧版本保存的消息在新版本中也能走零件化渲染路径，
  /// 避免"旧消息走旧逻辑、新消息走新逻辑"的双轨维护成本。
  ///
  /// 注意：parts id 不依赖 msgId，因为 Message id 在构造函数中自动生成，
  /// 在 fromJson 执行时 msgId 可能还未确定。用简单类型标识作为 id。
  static List<MessagePart> _partsFromLegacyFields({
    required String? content,
    required String? reasoningContent,
    required String searchQuery,
    required List<SearchSource> searchSources,
    required List<Attachment>? attachments,
  }) {
    final parts = <MessagePart>[];

    // 1. 思考过程 → ReasoningPart
    if (reasoningContent != null && reasoningContent.isNotEmpty) {
      parts.add(ReasoningPart(id: 'reasoning', reasoning: reasoningContent));
    }

    // 2. 搜索来源 → SourcePart
    if (searchSources.isNotEmpty) {
      parts.add(
        SourcePart(
          id: 'source',
          query: searchQuery,
          sources: searchSources
              .map(
                (s) => SearchSourceItem(id: s.url, title: s.title, url: s.url),
              )
              .toList(),
        ),
      );
    }

    // 3. 附件 → FilePart
    if (attachments != null && attachments.isNotEmpty) {
      for (var i = 0; i < attachments.length; i++) {
        parts.add(FilePart.fromAttachment('file_$i', attachments[i]));
      }
    }

    // 4. 正文 → TextPart（始终放最后）
    if (content != null && content.isNotEmpty) {
      parts.add(TextPart(id: 'text', text: content));
    }

    return parts;
  }

  static String? _getStringValue(
    Map<String, dynamic> json,
    List<String> possibleKeys,
  ) {
    for (final key in possibleKeys) {
      final value = json[key];
      if (value != null && value is String && value.isNotEmpty) {
        return value;
      }
    }
    return null;
  }

  Message copyWith({
    String? id,
    String? role,
    String? content,
    String? reasoningContent,
    List<Attachment>? attachments,
    bool clearReasoning = false,
    DateTime? timestamp,
    int? tokenCount,
    int? wordCount,
    bool? isFallback,
    String? searchQuery,
    List<SearchSource>? searchSources,
    List<MessagePart>? parts,
  }) {
    return Message(
      id: id ?? this.id,
      role: role ?? this.role,
      content: content ?? this.content,
      reasoningContent: clearReasoning
          ? null
          : (reasoningContent ?? this.reasoningContent),
      attachments: attachments ?? this.attachments,
      timestamp: timestamp ?? this.timestamp,
      tokenCount: tokenCount ?? this.tokenCount,
      wordCount: wordCount ?? this.wordCount,
      isFallback: isFallback ?? this.isFallback,
      searchQuery: searchQuery ?? this.searchQuery,
      searchSources: searchSources ?? this.searchSources,
      parts: parts ?? this.parts,
    );
  }

  @override
  String toString() =>
      'Message(role: $role, content: ${content.length} chars, reasoning: ${reasoningContent?.length ?? 0} chars, attachments: ${attachments?.length ?? 0}, timestamp: $timestamp, tokens: $tokenCount, words: $wordCount)';

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Message && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;
}
