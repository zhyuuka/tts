import 'openai_compatible_service.dart';

class GuijiService extends OpenAiCompatibleService {
  GuijiService({
    required super.apiKey,
    super.model,
    String baseUrl = 'https://api.siliconflow.cn/v1',
  }) : super(
         serviceBaseUrl: baseUrl,
         serviceDefaultModel: 'deepseek-ai/DeepSeek-V4-Pro',
       );

  @override
  String get serviceName => '硅基流动';

  @override
  String get serviceId => 'guiji';

  Map<String, dynamic> toJson() {
    return {
      'serviceId': serviceId,
      'apiKey': apiKey.isNotEmpty ? '••••••••' : '',
      'baseUrl': serviceBaseUrl,
    };
  }

  factory GuijiService.fromJson(Map<String, dynamic> json) {
    return GuijiService(
      apiKey: json['apiKey'] ?? '',
      baseUrl: json['baseUrl'] ?? 'https://api.siliconflow.cn/v1',
    );
  }
}
