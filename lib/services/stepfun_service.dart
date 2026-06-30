import 'openai_compatible_service.dart';

class StepfunService extends OpenAiCompatibleService {
  StepfunService({required super.apiKey, super.model})
    : super(
        serviceBaseUrl: 'https://api.stepfun.com/v1',
        serviceDefaultModel: 'stepaudio-2.5-realtime',
      );

  @override
  String get serviceName => '阶跃星辰';

  @override
  String get serviceId => 'stepfun';
}
