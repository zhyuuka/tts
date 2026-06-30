import 'attachment.dart';

/// 消息零件基类
///
/// 为什么这样做：AI 回复不再只是纯文本，可能包含思考、工具调用、
/// 搜索结果、文件引用、建议追问等多种信息，零件化后可以统一序列化、
/// 统一渲染，也便于后续扩展新类型。
///
/// 为什么要有 id：流式渲染时需要通过 id 做 diff，相同 id 的零件
/// 只更新内容而不重建 widget，避免抖动。
sealed class MessagePart {
  /// 零件唯一标识，用于流式 diff
  String get id;

  /// 零件类型，用于序列化和渲染分发
  String get type;

  Map<String, dynamic> toJson();
}

/// 文本/Markdown 内容（当前 content 的零件化形式）
class TextPart extends MessagePart {
  @override
  final String id;
  @override
  final String type = 'text';
  final String text;

  TextPart({required this.id, required this.text});

  factory TextPart.fromJson(Map<String, dynamic> json) => TextPart(
    id: json['id'] as String? ?? '',
    text: json['text'] as String? ?? '',
  );

  @override
  Map<String, dynamic> toJson() => {'id': id, 'type': type, 'text': text};

  TextPart copyWith({String? id, String? text}) =>
      TextPart(id: id ?? this.id, text: text ?? this.text);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TextPart && other.id == id && other.text == text;

  @override
  int get hashCode => Object.hash(id, text);
}

/// 思考过程（替代现有的 reasoningContent）
class ReasoningPart extends MessagePart {
  @override
  final String id;
  @override
  final String type = 'reasoning';
  final String reasoning;
  final bool isCollapsed;

  ReasoningPart({
    required this.id,
    required this.reasoning,
    this.isCollapsed = true,
  });

  factory ReasoningPart.fromJson(Map<String, dynamic> json) => ReasoningPart(
    id: json['id'] as String? ?? '',
    reasoning: json['reasoning'] as String? ?? '',
    isCollapsed: json['is_collapsed'] as bool? ?? true,
  );

  @override
  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type,
    'reasoning': reasoning,
    'is_collapsed': isCollapsed,
  };

  ReasoningPart copyWith({String? id, String? reasoning, bool? isCollapsed}) =>
      ReasoningPart(
        id: id ?? this.id,
        reasoning: reasoning ?? this.reasoning,
        isCollapsed: isCollapsed ?? this.isCollapsed,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ReasoningPart &&
          other.id == id &&
          other.reasoning == reasoning &&
          other.isCollapsed == isCollapsed;

  @override
  int get hashCode => Object.hash(id, reasoning, isCollapsed);
}

/// 工具调用状态/结果
///
/// result 可以是 Map（结构化结果）或 String（大文本如搜索摘要），
/// 序列化时统一存为 JSON 兼容类型。
class ToolCallPart extends MessagePart {
  @override
  final String id;
  @override
  final String type = 'tool_call';
  final String toolName;
  final String displayText;
  final String status; // 'running' | 'success' | 'error'
  final Object? result; // Map<String, dynamic> 或 String
  final String? error;

  ToolCallPart({
    required this.id,
    required this.toolName,
    required this.displayText,
    this.status = 'running',
    this.result,
    this.error,
  });

  factory ToolCallPart.fromJson(Map<String, dynamic> json) => ToolCallPart(
    id: json['id'] as String? ?? '',
    toolName: json['tool_name'] as String? ?? '',
    displayText: json['display_text'] as String? ?? '',
    status: json['status'] as String? ?? 'running',
    result: json['result'], // 保留原始类型
    error: json['error'] as String?,
  );

  @override
  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type,
    'tool_name': toolName,
    'display_text': displayText,
    'status': status,
    if (result != null) 'result': result,
    if (error != null) 'error': error,
  };

  ToolCallPart copyWith({
    String? id,
    String? toolName,
    String? displayText,
    String? status,
    Object? result,
    String? error,
  }) => ToolCallPart(
    id: id ?? this.id,
    toolName: toolName ?? this.toolName,
    displayText: displayText ?? this.displayText,
    status: status ?? this.status,
    result: result ?? this.result,
    error: error ?? this.error,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ToolCallPart &&
          other.id == id &&
          other.toolName == toolName &&
          other.displayText == displayText &&
          other.status == status &&
          other.result == result &&
          other.error == error;

  @override
  int get hashCode =>
      Object.hash(id, toolName, displayText, status, result, error);
}

/// 搜索来源（替代现有的 searchSources）
///
/// 注意：现有 SearchSource 类（message.dart）只有 title + url。
/// 新的 SearchSourceItem 增加了 id、snippet、favicon 字段。
/// 迁移策略：SourcePart.sources 使用 SearchSourceItem；
/// 旧 SearchSource 在读取时自动转换为 SearchSourceItem（id 用 url 代替）。
class SourcePart extends MessagePart {
  @override
  final String id;
  @override
  final String type = 'source';
  final String query;
  final List<SearchSourceItem> sources;

  SourcePart({required this.id, required this.query, required this.sources});

  factory SourcePart.fromJson(Map<String, dynamic> json) => SourcePart(
    id: json['id'] as String? ?? '',
    query: json['query'] as String? ?? '',
    sources:
        (json['sources'] as List?)
            ?.map((s) => SearchSourceItem.fromJson(s as Map<String, dynamic>))
            .toList() ??
        [],
  );

  @override
  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type,
    'query': query,
    'sources': sources.map((s) => s.toJson()).toList(),
  };

  SourcePart copyWith({
    String? id,
    String? query,
    List<SearchSourceItem>? sources,
  }) => SourcePart(
    id: id ?? this.id,
    query: query ?? this.query,
    sources: sources ?? this.sources,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SourcePart &&
          other.id == id &&
          other.query == query &&
          _listEquals(other.sources, sources);

  @override
  int get hashCode => Object.hash(id, query, Object.hashAll(sources));
}

/// 搜索来源条目（替代现有 SearchSource）
class SearchSourceItem {
  final String id;
  final String title;
  final String url;
  final String? snippet;
  final String? favicon;

  SearchSourceItem({
    required this.id,
    required this.title,
    required this.url,
    this.snippet,
    this.favicon,
  });

  factory SearchSourceItem.fromJson(Map<String, dynamic> json) =>
      SearchSourceItem(
        id: json['id'] as String? ?? '',
        title: json['title'] as String? ?? '',
        url: json['url'] as String? ?? '',
        snippet: json['snippet'] as String?,
        favicon: json['favicon'] as String?,
      );

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'url': url,
    if (snippet != null) 'snippet': snippet,
    if (favicon != null) 'favicon': favicon,
  };

  SearchSourceItem copyWith({
    String? id,
    String? title,
    String? url,
    String? snippet,
    String? favicon,
  }) => SearchSourceItem(
    id: id ?? this.id,
    title: title ?? this.title,
    url: url ?? this.url,
    snippet: snippet ?? this.snippet,
    favicon: favicon ?? this.favicon,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SearchSourceItem &&
          other.id == id &&
          other.title == title &&
          other.url == url &&
          other.snippet == snippet &&
          other.favicon == favicon;

  @override
  int get hashCode => Object.hash(id, title, url, snippet, favicon);
}

/// 文件引用/预览
///
/// 注意：现有 Attachment 类（attachment.dart）用于用户上传的附件，
/// 字段为 type/name/path/dataBase64/mimeType/ocrText。
/// FilePart 用于 AI 回复中引用的文件（可能是用户上传的、也可能是 AI 生成的）。
/// 关系：FilePart 是 Attachment 的"引用视图"，通过 fileId 关联到实际文件。
/// 用户消息仍用 Attachment；AI 回复中的文件引用用 FilePart。
class FilePart extends MessagePart {
  @override
  final String id;
  @override
  final String type = 'file';
  final String fileId;
  final String name;
  final String mimeType;
  final String? localPath;
  final String? url;
  final int? size;
  final String? thumbnailBase64;

  FilePart({
    required this.id,
    required this.fileId,
    required this.name,
    required this.mimeType,
    this.localPath,
    this.url,
    this.size,
    this.thumbnailBase64,
  });

  /// 从现有 Attachment 转换（用于兼容旧消息）
  factory FilePart.fromAttachment(String partId, Attachment att) => FilePart(
    id: partId,
    fileId: att.path ?? att.name ?? partId,
    name: att.name ?? '未知文件',
    mimeType: att.mimeType ?? _inferMimeType(att.type),
    localPath: att.path,
  );

  static String _inferMimeType(String type) => switch (type) {
    'image' => 'image/*',
    'pdf' => 'application/pdf',
    'text' => 'text/plain',
    _ => 'application/octet-stream',
  };

  factory FilePart.fromJson(Map<String, dynamic> json) => FilePart(
    id: json['id'] as String? ?? '',
    fileId: json['file_id'] as String? ?? '',
    name: json['name'] as String? ?? '',
    mimeType: json['mime_type'] as String? ?? 'application/octet-stream',
    localPath: json['local_path'] as String?,
    url: json['url'] as String?,
    size: json['size'] as int?,
    thumbnailBase64: json['thumbnail_base64'] as String?,
  );

  @override
  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type,
    'file_id': fileId,
    'name': name,
    'mime_type': mimeType,
    if (localPath != null) 'local_path': localPath,
    if (url != null) 'url': url,
    if (size != null) 'size': size,
    if (thumbnailBase64 != null) 'thumbnail_base64': thumbnailBase64,
  };

  FilePart copyWith({
    String? id,
    String? fileId,
    String? name,
    String? mimeType,
    String? localPath,
    String? url,
    int? size,
    String? thumbnailBase64,
  }) => FilePart(
    id: id ?? this.id,
    fileId: fileId ?? this.fileId,
    name: name ?? this.name,
    mimeType: mimeType ?? this.mimeType,
    localPath: localPath ?? this.localPath,
    url: url ?? this.url,
    size: size ?? this.size,
    thumbnailBase64: thumbnailBase64 ?? this.thumbnailBase64,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FilePart &&
          other.id == id &&
          other.fileId == fileId &&
          other.name == name &&
          other.mimeType == mimeType &&
          other.localPath == localPath &&
          other.url == url &&
          other.size == size &&
          other.thumbnailBase64 == thumbnailBase64;

  @override
  int get hashCode => Object.hash(
    id,
    fileId,
    name,
    mimeType,
    localPath,
    url,
    size,
    thumbnailBase64,
  );
}

/// 建议追问
///
/// 点击行为：点击后自动填入输入框并发送（调用 ChatProvider.sendMessage）。
class SuggestedQuestionPart extends MessagePart {
  @override
  final String id;
  @override
  final String type = 'suggested_questions';
  final List<String> questions;

  SuggestedQuestionPart({required this.id, required this.questions});

  factory SuggestedQuestionPart.fromJson(Map<String, dynamic> json) =>
      SuggestedQuestionPart(
        id: json['id'] as String? ?? '',
        questions: (json['questions'] as List?)?.cast<String>() ?? [],
      );

  @override
  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type,
    'questions': questions,
  };

  SuggestedQuestionPart copyWith({String? id, List<String>? questions}) =>
      SuggestedQuestionPart(
        id: id ?? this.id,
        questions: questions ?? this.questions,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SuggestedQuestionPart &&
          other.id == id &&
          _listEquals(other.questions, questions);

  @override
  int get hashCode => Object.hash(id, Object.hashAll(questions));
}

/// Artifact / 独立报告
class ArtifactPart extends MessagePart {
  @override
  final String id;
  @override
  final String type = 'artifact';
  final String artifactId;
  final String title;
  final String content;
  final String contentType; // 'markdown' | 'html' | 'mermaid' | 'code'
  final String? language;

  ArtifactPart({
    required this.id,
    required this.artifactId,
    required this.title,
    required this.content,
    this.contentType = 'markdown',
    this.language,
  });

  factory ArtifactPart.fromJson(Map<String, dynamic> json) => ArtifactPart(
    id: json['id'] as String? ?? '',
    artifactId: json['artifact_id'] as String? ?? '',
    title: json['title'] as String? ?? '',
    content: json['content'] as String? ?? '',
    contentType: json['content_type'] as String? ?? 'markdown',
    language: json['language'] as String?,
  );

  @override
  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type,
    'artifact_id': artifactId,
    'title': title,
    'content': content,
    'content_type': contentType,
    if (language != null) 'language': language,
  };

  ArtifactPart copyWith({
    String? id,
    String? artifactId,
    String? title,
    String? content,
    String? contentType,
    String? language,
  }) => ArtifactPart(
    id: id ?? this.id,
    artifactId: artifactId ?? this.artifactId,
    title: title ?? this.title,
    content: content ?? this.content,
    contentType: contentType ?? this.contentType,
    language: language ?? this.language,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ArtifactPart &&
          other.id == id &&
          other.artifactId == artifactId &&
          other.title == title &&
          other.content == content &&
          other.contentType == contentType &&
          other.language == language;

  @override
  int get hashCode =>
      Object.hash(id, artifactId, title, content, contentType, language);
}

/// 从 JSON 反序列化为具体零件
///
/// 未知类型降级为文本，保证不会因为一个零件损坏导致整条消息崩溃。
MessagePart messagePartFromJson(Map<String, dynamic> json) {
  final type = json['type'] as String? ?? 'text';
  return switch (type) {
    'text' => TextPart.fromJson(json),
    'reasoning' => ReasoningPart.fromJson(json),
    'tool_call' => ToolCallPart.fromJson(json),
    'source' => SourcePart.fromJson(json),
    'file' => FilePart.fromJson(json),
    'suggested_questions' => SuggestedQuestionPart.fromJson(json),
    'artifact' => ArtifactPart.fromJson(json),
    _ => TextPart.fromJson(json),
  };
}

/// 辅助函数：比较两个列表的元素是否一一相等
bool _listEquals<T>(List<T>? a, List<T>? b) {
  if (a == null) return b == null;
  if (b == null || a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
