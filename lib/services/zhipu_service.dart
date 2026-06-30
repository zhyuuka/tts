import 'openai_compatible_service.dart';

class ZhipuService extends OpenAiCompatibleService {
  ZhipuService({required super.apiKey, super.model})
    : super(
        serviceBaseUrl: 'https://open.bigmodel.cn/api/paas/v4',
        serviceDefaultModel: 'glm-5v-turbo',
      );

  @override
  String get serviceName => '智谱AI';

  @override
  String get serviceId => 'zhipu';
}
