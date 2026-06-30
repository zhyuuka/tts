import 'openai_compatible_service.dart';

class DoubaoService extends OpenAiCompatibleService {
  DoubaoService({required super.apiKey, super.model})
    : super(
        serviceBaseUrl: 'https://ark.cn-beijing.volces.com/api/v3',
        serviceDefaultModel: 'doubao-seed-2.0-lite',
      );

  @override
  String get serviceName => '豆包 AI';

  @override
  String get serviceId => 'doubao';
}
