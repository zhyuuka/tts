import 'openai_compatible_service.dart';

class HunyuanService extends OpenAiCompatibleService {
  HunyuanService({required super.apiKey, super.model})
    : super(
        serviceBaseUrl: 'https://hunyuan.tencentcloudapi.com/v1',
        serviceDefaultModel: 'hunyuan-hy3-preview',
      );

  @override
  String get serviceName => '混元 AI';

  @override
  String get serviceId => 'hunyuan';
}
