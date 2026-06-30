import 'package:dio/dio.dart';

import '../models/message.dart';
import 'ai_service.dart';
import 'openai_compatible_service.dart';

class DeepSeekService extends OpenAiCompatibleService {
  DeepSeekService({required super.apiKey, super.model})
    : super(
        serviceBaseUrl: 'https://api.deepseek.com',
        serviceDefaultModel: 'deepseek-v4-pro',
        usePlainTextMessages: true,
      );

  @override
  String get serviceName => 'DeepSeek';

  @override
  String get serviceId => 'deepseek';

  bool get isReasonerModel => model.contains('reasoner');

  @override
  Future<String> chat(List<Message> messages) async {
    try {
      final apiMessages = await convertMessages(messages);
      final response = await dio.post(
        '/chat/completions',
        data: {
          ...buildGenerationConfig(),
          'messages': apiMessages,
          'stream': false,
        },
        options: Options(
          headers: {
            'Content-Type': 'application/json',
            'Authorization': buildAuthHeader(),
          },
        ),
      );

      if (response.statusCode == 200) {
        final data = response.data;

        if (data.containsKey('error')) {
          final error = data['error'] as Map<String, dynamic>;
          throw AiException(
            message: error['message']?.toString() ?? 'API 返回错误',
            service: serviceName,
          );
        }

        final choices = data['choices'] as List?;
        if (choices == null || choices.isEmpty) {
          throw AiException(message: 'API 未返回任何回复', service: serviceName);
        }

        final message = choices.first['message'] as Map<String, dynamic>?;
        if (message == null) {
          throw AiException(message: '回复消息格式错误', service: serviceName);
        }

        final reasoning = message['reasoning_content'] as String? ?? '';
        final content = message['content'] as String? ?? '';
        return content.isNotEmpty ? content : reasoning;
      } else {
        throw AiException(
          message: '请求失败',
          service: serviceName,
          code: response.statusCode?.toString(),
        );
      }
    } on DioException catch (e) {
      throw handleDioError(e);
    } catch (e) {
      if (e is AiException) rethrow;
      throw AiException(message: '未知错误: $e', service: serviceName);
    }
  }
}
