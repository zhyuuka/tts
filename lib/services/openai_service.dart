import 'openai_compatible_service.dart';

class OpenAiService extends OpenAiCompatibleService {
  OpenAiService({required super.apiKey, super.model})
    : super(
        serviceBaseUrl: 'https://api.openai.com/v1',
        serviceDefaultModel: 'gpt-5.5-instant',
      );

  @override
  String get serviceName => 'OpenAI';

  @override
  String get serviceId => 'openai';
}
