/// 业务错误类型系统
///
/// 使用 sealed class 确保所有可能的错误都被处理，
/// 编译器会强制检查所有子类型。
sealed class ChatError {
  const ChatError();

  /// 用户友好的错误消息
  String get userMessage;

  /// 技术细节（用于日志，不应显示给用户）
  String get technicalDetails;

  /// 错误代码（用于追踪和国际化）
  String get errorCode;

  /// 是否可以重试
  bool get canRetry;

  @override
  String toString() => 'ChatError[$errorCode]: $userMessage';
}

/// ── 网络相关错误 ──

/// 网络连接失败
final class NetworkError extends ChatError {
  final String message;
  final int? statusCode;

  const NetworkError({this.message = '网络连接失败，请检查网络设置', this.statusCode});

  @override
  String get userMessage => message;

  @override
  String get technicalDetails =>
      'Network Error: $message${statusCode != null ? ' (Status: $statusCode)' : ''}';

  @override
  String get errorCode => 'NETWORK_ERROR';

  @override
  bool get canRetry => true;
}

/// 请求超时
final class TimeoutError extends ChatError {
  final Duration timeout;
  final String? endpoint;

  const TimeoutError({
    this.timeout = const Duration(seconds: 30),
    this.endpoint,
  });

  @override
  String get userMessage => '请求超时，请稍后重试';

  @override
  String get technicalDetails =>
      'Request timed out after ${timeout.inSeconds}s${endpoint != null ? ' ($endpoint)' : ''}';

  @override
  String get errorCode => 'TIMEOUT_ERROR';

  @override
  bool get canRetry => true;
}

/// ── API 相关错误 ──

/// API 密钥无效或未配置
final class ApiKeyError extends ChatError {
  final String? serviceId;
  final ApiKeyErrorType errorType;

  const ApiKeyError({this.serviceId, this.errorType = ApiKeyErrorType.missing});

  @override
  String get userMessage {
    switch (errorType) {
      case ApiKeyErrorType.missing:
        return 'API Key 未配置，请在设置中配置';
      case ApiKeyErrorType.invalid:
        return 'API Key 无效，请检查是否正确';
      case ApiKeyErrorType.expired:
        return 'API Key 已过期，请更新';
      case ApiKeyErrorType.quotaExceeded:
        return 'API 配额已用尽，请升级套餐或更换 Key';
    }
  }

  @override
  String get technicalDetails =>
      'API Key Error for service $serviceId: ${errorType.name}';

  @override
  String get errorCode => 'API_KEY_ERROR';

  @override
  bool get canRetry => false;
}

enum ApiKeyErrorType {
  missing, // 未配置
  invalid, // 无效
  expired, // 过期
  quotaExceeded, // 配额用尽
}

/// 频率限制（Rate Limit）
final class RateLimitError extends ChatError {
  final int retryAfterSeconds;
  final String? limitType; // 'global', 'per_minute', 'per_day'

  const RateLimitError({this.retryAfterSeconds = 60, this.limitType});

  @override
  String get userMessage => '请求过于频繁，请 $retryAfterSeconds 秒后重试';

  @override
  String get technicalDetails =>
      'Rate Limit Exceeded (${limitType ?? 'unknown'}): Retry after ${retryAfterSeconds}s';

  @override
  String get errorCode => 'RATE_LIMIT_ERROR';

  @override
  bool get canRetry => true;
}

/// AI 服务返回的业务错误
final class AiServiceError extends ChatError {
  final String message;
  final String? serviceId;
  final AiServiceErrorCode code;

  const AiServiceError({
    required this.message,
    this.serviceId,
    this.code = AiServiceErrorCode.unknown,
  });

  @override
  String get userMessage => message;

  @override
  String get technicalDetails =>
      'AI Service Error [$code] from $serviceId: $message';

  @override
  String get errorCode => 'AI_SERVICE_ERROR';

  @override
  bool get canRetry => code == AiServiceErrorCode.serverError;
}

enum AiServiceErrorCode {
  unknown,
  invalidResponse, // 响应格式无效
  contentFilter, // 内容被过滤
  contextTooLong, // 上下文过长
  serverError, // 服务端错误
  modelNotFound, // 模型不存在
}

/// ── 数据解析错误 ──

/// JSON/数据解析失败
final class ParseError extends ChatError {
  final String rawContent;
  final String expectedFormat;

  const ParseError({required this.rawContent, this.expectedFormat = 'JSON'});

  @override
  String get userMessage => '数据解析失败，请重试';

  @override
  String get technicalDetails =>
      'Failed to parse $expectedFormat: ${rawContent.length > 100 ? '${rawContent.substring(0, 100)}...' : rawContent}';

  @override
  String get errorCode => 'PARSE_ERROR';

  @override
  bool get canRetry => true;
}

/// 流式响应解析中断
final class StreamParseError extends ChatError {
  final String partialContent;
  final StreamParseErrorType errorType;

  const StreamParseError({
    required this.partialContent,
    this.errorType = StreamParseErrorType.incompleteChunk,
  });

  @override
  String get userMessage => '响应接收不完整，部分内容可能丢失';

  @override
  String get technicalDetails =>
      'Stream Parse Error [${errorType.name}]: Received ${partialContent.length} chars';

  @override
  String get errorCode => 'STREAM_PARSE_ERROR';

  @override
  bool get canRetry => false;
}

enum StreamParseErrorType {
  incompleteChunk, // 不完整的 chunk
  invalidSSE, // SSE 格式错误
  connectionLost, // 连接断开
}

/// ── 存储相关错误 ──

/// 本地存储操作失败
final class StorageError extends ChatError {
  final String operation;
  final StorageErrorType errorType;
  final String? path;

  const StorageError({
    required this.operation,
    this.errorType = StorageErrorType.unknown,
    this.path,
  });

  @override
  String get userMessage {
    switch (errorType) {
      case StorageErrorType.notInitialized:
        return '存储服务未初始化';
      case StorageErrorType.permissionDenied:
        return '存储权限不足';
      case StorageErrorType.diskFull:
        return '存储空间不足';
      case StorageErrorType.corrupted:
        return '存储数据损坏';
      case StorageErrorType.notFound:
        return '数据未找到';
      case StorageErrorType.unknown:
        return '$operation 操作失败';
    }
  }

  @override
  String get technicalDetails =>
      'Storage Error [${errorType.name}] during $operation${path != null ? ' at $path' : ''}';

  @override
  String get errorCode => 'STORAGE_ERROR';

  @override
  bool get canRetry => errorType != StorageErrorType.permissionDenied;
}

enum StorageErrorType {
  notInitialized,
  permissionDenied,
  diskFull,
  corrupted,
  notFound,
  unknown,
}

/// ── 记忆系统错误 ──

/// MemU/MemLocal 服务错误
final class MemorySystemError extends ChatError {
  final String operation;
  final MemoryServiceType serviceType;
  final MemoryErrorType errorType;

  const MemorySystemError({
    required this.operation,
    this.serviceType = MemoryServiceType.memLocal,
    this.errorType = MemoryErrorType.initFailed,
  });

  @override
  String get userMessage {
    switch (errorType) {
      case MemoryErrorType.initFailed:
        return '记忆系统初始化失败';
      case MemoryErrorType.writeFailed:
        return '记忆写入失败';
      case MemoryErrorType.readFailed:
        return '记忆读取失败';
      case MemoryErrorType.searchFailed:
        return '记忆搜索失败';
      case MemoryErrorType.sessionNotFound:
        return '记忆会话未找到';
      case MemoryErrorType.quotaExceeded:
        return '记忆存储空间已满';
    }
  }

  @override
  String get technicalDetails =>
      'Memory System Error [${serviceType.name}/${errorType.name}]: Failed to $operation';

  @override
  String get errorCode => 'MEMORY_SYSTEM_ERROR';

  @override
  bool get canRetry => errorType != MemoryErrorType.initFailed;
}

enum MemoryServiceType { memU, memLocal }

enum MemoryErrorType {
  initFailed,
  writeFailed,
  readFailed,
  searchFailed,
  sessionNotFound,
  quotaExceeded,
}

/// ── 会话相关错误 ──

/// 会话操作失败
final class ConversationError extends ChatError {
  final String conversationId;
  final ConversationOperation operation;
  final ConversationErrorType errorType;

  const ConversationError({
    required this.conversationId,
    required this.operation,
    this.errorType = ConversationErrorType.notFound,
  });

  @override
  String get userMessage {
    switch (errorType) {
      case ConversationErrorType.notFound:
        return '会话不存在';
      case ConversationErrorType.alreadyExists:
        return '会话已存在';
      case ConversationErrorType.locked:
        return '会话正在使用中，无法操作';
      case ConversationErrorType.deleted:
        return '会话已被删除';
    }
  }

  @override
  String get technicalDetails =>
      'Conversation Error [${errorType.name}] during ${operation.name}: $conversationId';

  @override
  String get errorCode => 'CONVERSATION_ERROR';

  @override
  bool get canRetry => errorType == ConversationErrorType.locked;
}

enum ConversationOperation { create, delete, rename, switchTo }

enum ConversationErrorType { notFound, alreadyExists, locked, deleted }

/// ── 文件操作错误 ──

/// 文件选择/上传/下载错误
final class FileOperationError extends ChatError {
  final String fileName;
  final FileOperation operation;
  final FileErrorType errorType;

  const FileOperationError({
    required this.fileName,
    required this.operation,
    this.errorType = FileErrorType.accessDenied,
  });

  @override
  String get userMessage {
    switch (errorType) {
      case FileErrorType.accessDenied:
        return '文件访问被拒绝：$fileName';
      case FileErrorType.notFound:
        return '文件不存在：$fileName';
      case FileErrorType.tooLarge:
        return '文件过大：$fileName（最大支持 10MB）';
      case FileErrorType.unsupportedFormat:
        return '不支持的文件格式：$fileName';
      case FileErrorType.readFailed:
        return '文件读取失败：$fileName';
      case FileErrorType.writeFailed:
        return '文件写入失败：$fileName';
    }
  }

  @override
  String get technicalDetails =>
      'File Operation Error [${errorType.name}] during ${operation.name}: $fileName';

  @override
  String get errorCode => 'FILE_OPERATION_ERROR';

  @override
  bool get canRetry => true;
}

enum FileOperation { pick, upload, download, read, write }

enum FileErrorType {
  accessDenied,
  notFound,
  tooLarge,
  unsupportedFormat,
  readFailed,
  writeFailed,
}

/// ── OCR 相关错误 ──

/// OCR 识别错误
final class OcrError extends ChatError {
  final String? imagePath;
  final OcrEngineType engineType;
  final OcrErrorType errorType;

  const OcrError({
    this.imagePath,
    this.engineType = OcrEngineType.local,
    this.errorType = OcrErrorType.recognitionFailed,
  });

  @override
  String get userMessage {
    switch (errorType) {
      case OcrErrorType.recognitionFailed:
        return '文字识别失败，请检查图片清晰度';
      case OcrErrorType.noTextDetected:
        return '图片中未检测到文字';
      case OcrErrorType.imageTooLarge:
        return '图片过大，请压缩后重试';
      case OcrErrorType.engineNotAvailable:
        return '${engineType.name} 引擎不可用';
      case OcrErrorType.apiQuotaExceeded:
        return 'OCR API 配额已用尽';
      case OcrErrorType.networkError:
        return 'OCR 服务网络连接失败';
    }
  }

  @override
  String get technicalDetails =>
      'OCR Error [${engineType.name}/${errorType.name}]${imagePath != null ? ': $imagePath' : ''}';

  @override
  String get errorCode => 'OCR_ERROR';

  @override
  bool get canRetry => errorType != OcrErrorType.noTextDetected;
}

enum OcrEngineType { local, baidu, tencent, aliyun }

enum OcrErrorType {
  recognitionFailed,
  noTextDetected,
  imageTooLarge,
  engineNotAvailable,
  apiQuotaExceeded,
  networkError,
}

/// ── 通用错误 ──

/// 未预期的错误
final class UnknownError extends ChatError {
  final Object? originalError;
  final StackTrace? stackTrace;

  const UnknownError({this.originalError, this.stackTrace});

  @override
  String get userMessage => '发生未知错误，请联系开发者';

  @override
  String get technicalDetails => 'Unknown Error: $originalError\n$stackTrace';

  @override
  String get errorCode => 'UNKNOWN_ERROR';

  @override
  bool get canRetry => true;
}

/// 用户取消操作
class UserCancelledError extends ChatError {
  const UserCancelledError();

  @override
  String get userMessage => '操作已取消';

  @override
  String get technicalDetails => 'User cancelled the operation';

  @override
  String get errorCode => 'USER_CANCELLED';

  @override
  bool get canRetry => false;
}
