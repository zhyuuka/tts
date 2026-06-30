import '../../services/ai_service.dart';
import 'chat_error.dart';
import '../logger/app_logger.dart';

class AppErrorHandler {
  static String userFriendlyMessage(Object error) {
    if (error is ChatError) {
      return error.userMessage;
    }

    if (error is AiException) {
      return _mapAiException(error);
    }

    final msg = error.toString();

    if (msg.contains('SocketException') || msg.contains('Connection refused')) {
      return '网络连接失败，请检查网络设置';
    }

    if (msg.contains('HandshakeException') ||
        msg.contains('CERTIFICATE_VERIFY_FAILED')) {
      return 'SSL 证书验证失败，请检查网络环境';
    }

    if (msg.contains('TimeoutException') || msg.contains('timed out')) {
      return '请求超时，请稍后重试';
    }

    if (msg.contains('401') || msg.contains('Unauthorized')) {
      return 'API Key 无效或已过期，请在设置中更新';
    }

    if (msg.contains('403') || msg.contains('Forbidden')) {
      return '访问被拒绝，请检查 API Key 权限';
    }

    if (msg.contains('429') || msg.contains('Too Many Requests')) {
      return '请求过于频繁，请稍后重试';
    }

    if (msg.contains('500') || msg.contains('Internal Server Error')) {
      return 'AI 服务暂时不可用，请稍后重试';
    }

    if (msg.contains('502') || msg.contains('Bad Gateway')) {
      return 'AI 服务网关错误，请稍后重试';
    }

    if (msg.contains('503') || msg.contains('Service Unavailable')) {
      return 'AI 服务暂时不可用，请稍后重试';
    }

    if (msg.contains('免费额度') || msg.contains('quota')) {
      return '免费额度已用尽，请点击设置切换其他 AI 服务';
    }

    if (msg.contains('rate_limit') || msg.contains('rate limit')) {
      return '请求频率超限，请稍后重试';
    }

    return '操作失败，请稍后重试';
  }

  static String _mapAiException(AiException e) {
    final msg = e.message;

    if (msg.contains('免费额度') || msg.contains('quota')) {
      return '免费额度已用尽，请点击设置切换其他 AI 服务';
    }

    if (msg.contains('rate_limit') || msg.contains('Rate limit')) {
      return '请求频率超限，请稍后重试';
    }

    if (msg.contains('context_length') || msg.contains('token limit')) {
      return '对话内容过长，请开启新话题或缩短消息';
    }

    return msg;
  }

  static bool canRetry(Object error) {
    if (error is ChatError) {
      return error.canRetry;
    }

    final msg = error.toString();

    if (msg.contains('401') || msg.contains('403')) {
      return false;
    }

    if (msg.contains('429')) {
      return true;
    }

    if (msg.contains('SocketException') || msg.contains('TimeoutException')) {
      return true;
    }

    if (msg.contains('500') || msg.contains('502') || msg.contains('503')) {
      return true;
    }

    return false;
  }

  static void log(Object error, [StackTrace? stackTrace, String? context]) {
    final prefix = context != null ? '[$context] ' : '';

    if (error is ChatError) {
      AppLogger.e('$prefix${error.technicalDetails}');
    } else if (error is AiException) {
      AppLogger.e('${prefix}AI异常: ${error.message}');
    } else {
      AppLogger.e('$prefix错误: $error');
    }

    if (stackTrace != null) {
      AppLogger.d('堆栈: $stackTrace');
    }
  }
}
