import 'openai_compatible_service.dart';

class MoonshotService extends OpenAiCompatibleService {
  MoonshotService({required super.apiKey, super.model})
    : super(
        serviceBaseUrl: 'https://api.moonshot.cn/v1',
        serviceDefaultModel: 'kimi-k2.6',
      );

  @override
  String get serviceName => 'Kimi';

  @override
  String get serviceId => 'moonshot';
}
