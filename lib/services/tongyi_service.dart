import 'openai_compatible_service.dart';

class TongyiService extends OpenAiCompatibleService {
  TongyiService({required super.apiKey, super.model})
    : super(
        serviceBaseUrl: 'https://dashscope.aliyuncs.com/compatible-mode/v1',
        serviceDefaultModel: 'qwen3.5',
      );

  @override
  String get serviceName => '通义千问';

  @override
  String get serviceId => 'tongyi';
}
