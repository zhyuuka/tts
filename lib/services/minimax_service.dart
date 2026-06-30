import 'openai_compatible_service.dart';

class MinimaxService extends OpenAiCompatibleService {
  MinimaxService({required super.apiKey, super.model})
    : super(
        serviceBaseUrl: 'https://api.minimax.chat/v1',
        serviceDefaultModel: 'minimax-m2.7',
      );

  @override
  String get serviceName => 'MiniMax';

  @override
  String get serviceId => 'minimax';
}
