import 'openai_compatible_service.dart';

class YiService extends OpenAiCompatibleService {
  YiService({required super.apiKey, super.model})
    : super(
        serviceBaseUrl: 'https://api.lingyiwanwu.com/v1',
        serviceDefaultModel: 'yi-lightning',
      );

  @override
  String get serviceName => '零一万物';

  @override
  String get serviceId => 'yi';
}
