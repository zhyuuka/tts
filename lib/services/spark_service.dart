import 'openai_compatible_service.dart';

class SparkService extends OpenAiCompatibleService {
  SparkService({required super.apiKey, super.model})
    : super(
        serviceBaseUrl: 'https://spark-api-open.xf-yun.com/v1',
        serviceDefaultModel: 'spark-x2-flash',
      );

  @override
  String get serviceName => '讯飞星火';

  @override
  String get serviceId => 'spark';
}
