import 'openai_compatible_service.dart';

class HuggingFaceService extends OpenAiCompatibleService {
  HuggingFaceService({required super.apiKey, super.model})
    : super(
        serviceBaseUrl:
            'https://api-inference.huggingface.co/models/littlamb/v1',
        serviceDefaultModel: 'littlamb',
      );

  @override
  String get serviceName => 'Hugging Face';

  @override
  String get serviceId => 'huggingface';
}
