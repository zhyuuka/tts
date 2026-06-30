import 'chat_error.dart';

/// 错误处理工具类
///
/// 提供统一的错误捕获、转换和展示逻辑
class ErrorHelper {
  ErrorHelper._();

  /// 将任意异常转换为 ChatError
  static ChatError fromException(Object exception, [StackTrace? stackTrace]) {
    if (exception is ChatError) return exception;

    // 网络相关异常
    final message = exception.toString().toLowerCase();
    if (message.contains('socketexception') ||
        message.contains('network') ||
        message.contains('connection')) {
      return const NetworkError();
    }

    if (message.contains('timeout') || message.contains('deadline')) {
      return const TimeoutError();
    }

    // HTTP 状态码
    if (message.contains('401') || message.contains('unauthorized')) {
      return const ApiKeyError(errorType: ApiKeyErrorType.invalid);
    }

    if (message.contains('403') || message.contains('forbidden')) {
      return const ApiKeyError(errorType: ApiKeyErrorType.quotaExceeded);
    }

    if (message.contains('429') || message.contains('too many requests')) {
      return const RateLimitError();
    }

    if (message.contains('500') ||
        message.contains('502') ||
        message.contains('503')) {
      return const AiServiceError(
        message: '服务器暂时不可用，请稍后重试',
        code: AiServiceErrorCode.serverError,
      );
    }

    // 格式解析异常
    if (message.contains('formatexception') ||
        message.contains('json') ||
        message.contains('parse')) {
      return ParseError(rawContent: exception.toString());
    }

    // 文件操作异常
    if (message.contains('file') || message.contains('path')) {
      if (message.contains('permission')) {
        return const FileOperationError(
          fileName: 'unknown',
          operation: FileOperation.read,
          errorType: FileErrorType.accessDenied,
        );
      }
      if (message.contains('not found')) {
        return const FileOperationError(
          fileName: 'unknown',
          operation: FileOperation.pick,
          errorType: FileErrorType.notFound,
        );
      }
    }

    // 默认返回未知错误
    return UnknownError(originalError: exception, stackTrace: stackTrace);
  }

  /// 获取用户友好的错误消息（带重试提示）
  static String getUserMessage(ChatError error) {
    final baseMessage = error.userMessage;
    if (error.canRetry) {
      return '$baseMessage（可重试）';
    }
    return baseMessage;
  }

  /// 判断是否应该显示"重试"按钮
  static bool shouldShowRetryButton(ChatError error) => error.canRetry;

  /// 判断是否应该显示"联系开发者"选项
  static bool shouldShowContactSupport(ChatError error) {
    return !error.canRetry &&
        error is! UserCancelledError &&
        error is! ApiKeyError;
  }
}

/// 错误处理器回调类型
typedef ErrorHandler = void Function(ChatError error);

/// Result 类型 - 用于包装可能失败的操作
///
/// 使用示例：
/// ```dart
/// Future<Result<Message>> sendMessage(...) async {
///   try {
///     final response = await api.call();
///     return Success(response);
///   } catch (e) {
///     return Failure(ErrorHelper.fromException(e));
///   }
/// }
/// ```
sealed class Result<T> {
  const Result();

  bool get isSuccess => this is Success<T>;
  bool get isFailure => this is Failure<T>;

  T? get data => switch (this) {
    Success(:final value) => value,
    _ => null,
  };

  ChatError? get error => switch (this) {
    Failure(:final chatError) => chatError,
    _ => null,
  };

  /// 执行成功时的操作
  Result<T> onSuccess(void Function(T value) action) {
    if (this is Success<T>) {
      action((this as Success<T>).value);
    }
    return this;
  }

  /// 执行失败时的操作
  Result<T> onFailure(void Function(ChatError error) action) {
    if (this is Failure<T>) {
      action((this as Failure<T>).chatError);
    }
    return this;
  }

  /// 转换数据
  Result<R> map<R>(R Function(T) mapper) => switch (this) {
    Success(:final value) => Success(mapper(value)),
    Failure(:final chatError) => Failure(chatError),
  };
}

final class Success<T> extends Result<T> {
  final T value;
  const Success(this.value);
}

final class Failure<T> extends Result<T> {
  final ChatError chatError;
  const Failure(this.chatError);
}
