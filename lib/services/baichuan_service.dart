import 'openai_compatible_service.dart';

class BaichuanService extends OpenAiCompatibleService {
  BaichuanService({required super.apiKey, super.model})
    : super(
        serviceBaseUrl: 'https://api.baichuan-ai.com/v1',
        serviceDefaultModel: 'Baichuan4',
      );

  @override
  String get serviceName => '百川智能';

  @override
  String get serviceId => 'baichuan';
}
