import 'dart:convert';

import 'package:dio/dio.dart';

import '../core/logger/app_logger.dart';
import '../models/message.dart';
import 'common/input_sanitizer.dart';

/// 流式响应数据块
class ChatChunk {
  /// 回复内容增量
  final String content;

  /// 思考/推理内容增量（reasoner 模型）
  final String reasoningContent;

  /// 流是否结束
  final bool isFinished;

  const ChatChunk({
    this.content = '',
    this.reasoningContent = '',
    this.isFinished = false,
  });
}

/// AI 服务抽象基类
///
/// 所有 AI 服务实现必须继承此类并实现 [chat] 和 [convertMessages] 方法
abstract class AiService {
  final InputSanitizer _sanitizer = InputSanitizer();

  String get serviceName;

  /// 服务唯一标识
  String get serviceId;

  /// 获取 API Key
  String get apiKey;

  /// 设置 API Key
  set apiKey(String value);

  /// 获取模型名称（可选，支持的服务实现）
  String? get model => null;

  /// 设置模型名称（可选，支持的服务实现）
  set model(String? value) {}

  /// 将消息列表转换为该服务所需的 API 格式
  ///
  /// 每个服务子类必须实现此方法来定义自己的消息格式转换逻辑。
  /// 这样新增 AI 服务时只需要修改自己的文件，而不需要动核心转换器。
  ///
  /// 返回值通常是 `List<Map<String, dynamic>>` 或其他服务特定的格式。
  /// 具体返回类型由各子类决定。
  Future<dynamic> convertMessages(List<Message> messages);

  /// 发送聊天请求（非流式）
  ///
  /// [messages] - 消息列表
  ///
  /// 返回助手回复的文本
  ///
  /// 抛出 [AiException] 表示请求失败
  Future<String> chat(List<Message> messages);

  /// 流式聊天请求
  ///
  /// 默认实现回退到非流式 [chat]，子类可覆写以支持真正的 SSE 流式输出
  Stream<ChatChunk> chatStream(List<Message> messages) async* {
    final reply = await chat(messages);
    yield ChatChunk(content: reply, isFinished: true);
  }

  /// 取消正在进行的流式请求（子类可覆写）
  void cancelStream() {}

  // ── 通用 SSE 解析 ──

  /// 解析 OpenAI 兼容的 SSE 流（DeepSeek / 豆包 / 通义 / 混元 / HuggingFace）
  ///
  /// 格式: `data: {"choices":[{"delta":{"content":"..."}}]}\n`
  Stream<ChatChunk> parseOpenAiSseStream(Stream<List<int>> byteStream) async* {
    String buffer = '';

    await for (final chunk in byteStream) {
      buffer += utf8.decode(chunk, allowMalformed: true);

      while (buffer.contains('\n')) {
        final newlineIdx = buffer.indexOf('\n');
        final line = buffer.substring(0, newlineIdx).trim();
        buffer = buffer.substring(newlineIdx + 1);

        if (line.isEmpty) continue;
        if (!line.startsWith('data: ')) continue;

        final dataStr = line.substring(6).trim();
        if (dataStr == '[DONE]') {
          yield const ChatChunk(isFinished: true);
          return;
        }

        try {
          final data = jsonDecode(dataStr) as Map<String, dynamic>;
          final choices = data['choices'] as List?;
          if (choices == null || choices.isEmpty) continue;

          final choice = choices.first as Map<String, dynamic>;
          final delta = choice['delta'] as Map<String, dynamic>?;
          if (delta == null) continue;

          final reasoning = delta['reasoning_content'] as String? ?? '';
          final content = delta['content'] as String? ?? '';
          final finishReason = choice['finish_reason'];

          final sanitizedContent = _sanitizer.sanitizeSseContent(content);
          final sanitizedReasoning = _sanitizer.sanitizeSseContent(reasoning);

          if (sanitizedReasoning.isNotEmpty ||
              sanitizedContent.isNotEmpty ||
              finishReason == 'stop') {
            yield ChatChunk(
              reasoningContent: sanitizedReasoning,
              content: sanitizedContent,
              isFinished: finishReason == 'stop',
            );
          }
        } catch (_) {
          // 跳过格式错误的 chunk
        }
      }
    }

    // 流结束但没收到 [DONE]
    yield const ChatChunk(isFinished: true);
  }

  /// 解析 Gemini 格式的 SSE 流
  ///
  /// 格式: `data: {"candidates":[{"content":{"parts":[{"text":"..."}]}}]}\n`
  Stream<ChatChunk> parseGeminiSseStream(Stream<List<int>> byteStream) async* {
    String buffer = '';

    await for (final chunk in byteStream) {
      buffer += utf8.decode(chunk, allowMalformed: true);

      while (buffer.contains('\n')) {
        final newlineIdx = buffer.indexOf('\n');
        final line = buffer.substring(0, newlineIdx).trim();
        buffer = buffer.substring(newlineIdx + 1);

        if (line.isEmpty) continue;
        if (!line.startsWith('data: ')) continue;

        final dataStr = line.substring(6).trim();
        try {
          final data = jsonDecode(dataStr) as Map<String, dynamic>;
          final candidates = data['candidates'] as List?;
          if (candidates == null || candidates.isEmpty) continue;

          final content = candidates.first['content'] as Map<String, dynamic>?;
          if (content == null) continue;

          final parts = content['parts'] as List?;
          if (parts == null || parts.isEmpty) continue;

          final text = parts.first['text'] as String? ?? '';
          final sanitizedText = _sanitizer.sanitizeSseContent(text);
          if (sanitizedText.isNotEmpty) {
            yield ChatChunk(content: sanitizedText);
          }
        } catch (_) {
          // 跳过格式错误的 chunk
        }
      }
    }

    yield const ChatChunk(isFinished: true);
  }

  /// 构建 Dio 实例（可选）
  Dio buildDio({
    required String baseUrl,
    Duration connectTimeout = const Duration(seconds: 30),
    Duration receiveTimeout = const Duration(seconds: 120),
  }) {
    final dio = Dio();
    dio.options.baseUrl = baseUrl;
    dio.options.connectTimeout = connectTimeout;
    dio.options.receiveTimeout = receiveTimeout;
    dio.interceptors.add(_SseSecurityInterceptor());
    return dio;
  }

  /// 构建 Authorization Header
  String buildAuthHeader() => 'Bearer $apiKey';

  /// 处理 Dio 异常
  AiException handleDioError(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return AiException(message: '连接超时，请检查网络', service: serviceName);
      case DioExceptionType.connectionError:
        return AiException(message: '网络连接失败，请检查网络', service: serviceName);
      case DioExceptionType.badResponse:
        return _handleBadResponse(e);
      case DioExceptionType.cancel:
        return AiException(message: '请求已取消', service: serviceName);
      default:
        return AiException(message: '网络错误: ${e.message}', service: serviceName);
    }
  }

  AiException _handleBadResponse(DioException e) {
    final statusCode = e.response?.statusCode;
    final errorData = e.response?.data;
    String message = '请求失败';

    // 尝试从响应中提取错误信息
    if (errorData is Map) {
      // DeepSeek / OpenAI 格式
      if (errorData.containsKey('error')) {
        final error = errorData['error'];
        if (error is Map) {
          message = error['message'] ?? message;
          // 检查免费额度耗尽
          final errMsg = message.toLowerCase();
          if (errMsg.contains('quota') ||
              errMsg.contains('exceeded') ||
              errMsg.contains('limit')) {
            message = '免费额度已用完，请切换其他 AI 或升级套餐';
          }
        }
      }
      // 豆包格式
      else if (errorData.containsKey('code')) {
        message = errorData['message'] ?? message;
        if (errorData['code'] == 'QuotaExceeded') {
          message = '免费额度已用完，请切换其他 AI 或升级套餐';
        }
      }
      // 通义千问格式
      else if (errorData.containsKey('message')) {
        message = errorData['message'];
      }
    }

    // 根据 HTTP 状态码判断
    if (statusCode == 401) {
      message = 'API Key 无效';
    } else if (statusCode == 429) {
      message = '请求过于频繁，请稍后重试';
    } else if (statusCode != null && statusCode >= 500) {
      message = '服务器错误，请稍后重试';
    }

    return AiException(
      message: message,
      service: serviceName,
      code: statusCode?.toString(),
    );
  }
}

/// AI 异常类
class AiException implements Exception {
  final String message;
  final String? service;
  final String? code;

  AiException({required this.message, this.service, this.code});

  @override
  String toString() {
    final servicePart = service != null ? '[$service] ' : '';
    final codePart = code != null ? ' (code: $code)' : '';
    return '${servicePart}AiException: $message$codePart';
  }
}

class _SseSecurityInterceptor extends Interceptor {
  static const _allowedContentTypes = [
    'text/event-stream',
    'application/json',
    'text/plain',
    'application/octet-stream',
    'text/html',
  ];

  @override
  void onResponse(Response response, ResponseInterceptorHandler next) {
    final contentType = response.headers.value('content-type') ?? '';

    final isAllowed = _allowedContentTypes.any(
      (ct) => contentType.toLowerCase().contains(ct),
    );

    if (!isAllowed && contentType.isNotEmpty) {
      AppLogger.w(
        '[SseSecurity] 可疑 Content-Type: $contentType from ${response.requestOptions.uri}',
      );
    }

    next.next(response);
  }
}
