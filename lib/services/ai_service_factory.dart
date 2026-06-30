import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'ai_service.dart';
import 'deepseek_service.dart';
import 'doubao_service.dart';
import 'tongyi_service.dart';
import 'hunyuan_service.dart';
import 'gemini_service.dart';
import 'huggingface_service.dart';
import 'guiji_service.dart';
import 'custom_model_service.dart';
import 'openai_service.dart';
import 'zhipu_service.dart';
import 'moonshot_service.dart';
import 'minimax_service.dart';
import 'stepfun_service.dart';
import 'baichuan_service.dart';
import 'spark_service.dart';
import 'yi_service.dart';
import 'ernie_service.dart';

class AiServiceFactory {
  static const List<String> supportedServices = [
    'openai',
    'deepseek',
    'guiji',
    'zhipu',
    'moonshot',
    'doubao',
    'tongyi',
    'hunyuan',
    'minimax',
    'stepfun',
    'baichuan',
    'spark',
    'yi',
    'ernie',
    'gemini',
    'huggingface',
  ];

  static Map<String, String> _envCache = {};
  static bool _envLoaded = false;

  static Future<void> loadEnv() async {
    try {
      await dotenv.load(fileName: '.env');
      _envCache = Map<String, String>.from(dotenv.env);
      _envLoaded = true;
    } catch (e) {
      debugPrint('AiServiceFactory: .env 加载失败: $e');
      _envCache = {};
      _envLoaded = false;
    }
  }

  static String? getApiKeyFromEnv(String serviceId) {
    if (!_envLoaded) return null;
    final envKeyMap = {
      'openai': 'OPENAI_API_KEY',
      'deepseek': 'DEEPSEEK_API_KEY',
      'guiji': 'GUIJI_API_KEY',
      'zhipu': 'ZHIPU_API_KEY',
      'moonshot': 'MOONSHOT_API_KEY',
      'doubao': 'DOUBAO_API_KEY',
      'tongyi': 'TONGYI_API_KEY',
      'hunyuan': 'HUNYUAN_API_KEY',
      'minimax': 'MINIMAX_API_KEY',
      'stepfun': 'STEPFUN_API_KEY',
      'baichuan': 'BAICHUAN_API_KEY',
      'spark': 'SPARK_API_KEY',
      'yi': 'YI_API_KEY',
      'ernie': 'ERNIE_API_KEY',
      'gemini': 'GEMINI_API_KEY',
      'huggingface': 'HUGGINGFACE_API_KEY',
    };
    return _envCache[envKeyMap[serviceId]];
  }

  /// 获取指定服务商的 baseUrl
  /// 用于验证模型 ID 时发送测试请求
  static String getBaseUrl(String serviceId) {
    const baseUrls = {
      'openai': 'https://api.openai.com/v1',
      'deepseek': 'https://api.deepseek.com',
      'zhipu': 'https://open.bigmodel.cn/api/paas/v4',
      'yi': 'https://api.lingyiwanwu.com/v1',
      'tongyi': 'https://dashscope.aliyuncs.com/compatible-mode/v1',
      'stepfun': 'https://api.stepfun.com/v1',
      'spark': 'https://spark-api-open.xf-yun.com/v1',
      'moonshot': 'https://api.moonshot.cn/v1',
      'minimax': 'https://api.minimax.chat/v1',
      'hunyuan': 'https://hunyuan.tencentcloudapi.com/v1',
      'doubao': 'https://ark.cn-beijing.volces.com/api/v3',
      'baichuan': 'https://api.baichuan-ai.com/v1',
    };
    return baseUrls[serviceId] ?? '';
  }

  static AiService createService(
    String serviceId, {
    String? apiKey,
    String? baseUrl,
    String? model,
  }) {
    final key = apiKey ?? getApiKeyFromEnv(serviceId) ?? '';

    switch (serviceId) {
      case 'openai':
        return OpenAiService(apiKey: key, model: model);
      case 'deepseek':
        return DeepSeekService(apiKey: key);
      case 'guiji':
        return GuijiService(apiKey: key);
      case 'zhipu':
        return ZhipuService(apiKey: key, model: model);
      case 'moonshot':
        return MoonshotService(apiKey: key, model: model);
      case 'doubao':
        return DoubaoService(apiKey: key);
      case 'tongyi':
        return TongyiService(apiKey: key);
      case 'hunyuan':
        return HunyuanService(apiKey: key);
      case 'minimax':
        return MinimaxService(apiKey: key, model: model);
      case 'stepfun':
        return StepfunService(apiKey: key, model: model);
      case 'baichuan':
        return BaichuanService(apiKey: key, model: model);
      case 'spark':
        return SparkService(apiKey: key, model: model);
      case 'yi':
        return YiService(apiKey: key, model: model);
      case 'ernie':
        return ErnieService(apiKey: key, model: model);
      case 'gemini':
        return GeminiService(apiKey: key);
      case 'huggingface':
        return HuggingFaceService(apiKey: key);
      case 'custom':
        return CustomModelService(
          apiKey: key,
          baseUrl: baseUrl ?? '',
          model: model ?? '',
        );
      default:
        throw ArgumentError('不支持的 AI 服务: $serviceId');
    }
  }

  static AiServiceInfo getServiceInfo(String serviceId) {
    switch (serviceId) {
      case 'openai':
        return AiServiceInfo(
          id: 'openai',
          name: 'OpenAI',
          description: 'GPT-5.5 Instant / GPT-Realtime',
          freeQuota: '按量付费',
          registerUrl: 'https://platform.openai.com/',
          apiKeyUrl: 'https://platform.openai.com/api-keys',
          iconAsset: 'assets/ai_icons/openai.png',
          models: [
            AiModelInfo(
              id: 'gpt-5.5-instant',
              displayName: 'GPT-5.5 Instant',
              contextLength: 1048576,
            ),
            AiModelInfo(
              id: 'gpt-realtime-2',
              displayName: 'GPT-Realtime-2',
              contextLength: 1048576,
            ),
            AiModelInfo(
              id: 'gpt-realtime-translate',
              displayName: 'GPT-Realtime-Translate',
              contextLength: 1048576,
            ),
            AiModelInfo(
              id: 'gpt-realtime-whisper',
              displayName: 'GPT-Realtime-Whisper',
              contextLength: 1048576,
            ),
            AiModelInfo(
              id: 'gpt-5.5-cyber',
              displayName: 'GPT-5.5-Cyber',
              contextLength: 1048576,
            ),
          ],
        );
      case 'deepseek':
        return AiServiceInfo(
          id: 'deepseek',
          name: 'DeepSeek',
          description: '深度求索 AI',
          freeQuota: '便宜好用',
          registerUrl: 'https://platform.deepseek.com/',
          apiKeyUrl: 'https://platform.deepseek.com/',
          iconAsset: 'assets/ai_icons/deepseek.png',
          models: [
            AiModelInfo(
              id: 'deepseek-v4-pro',
              displayName: 'DeepSeek V4 Pro',
              contextLength: 131072,
            ),
            AiModelInfo(
              id: 'deepseek-v4-flash',
              displayName: 'DeepSeek V4 Flash',
              contextLength: 131072,
            ),
            AiModelInfo(
              id: 'deepseek-multimodal',
              displayName: '多模态模型',
              contextLength: 131072,
            ),
          ],
        );
      case 'guiji':
        return AiServiceInfo(
          id: 'guiji',
          name: '硅基流动',
          description: '硅基流动 AI 平台聚合',
          freeQuota: '无限制免费',
          registerUrl: 'https://guiji.ai/',
          apiKeyUrl: 'https://guiji.ai/',
          iconAsset: 'assets/ai_icons/guiji.png',
          models: [
            AiModelInfo(
              id: 'deepseek-ai/DeepSeek-V4-Pro',
              displayName: 'DeepSeek V4 Pro',
              contextLength: 131072,
            ),
            AiModelInfo(
              id: 'moonshot-ai/kimi-k2.6',
              displayName: 'Kimi K2.6',
              contextLength: 131072,
            ),
            AiModelInfo(
              id: 'THUDM/glm-5.1',
              displayName: 'GLM-5.1',
              contextLength: 131072,
            ),
          ],
        );
      case 'zhipu':
        return AiServiceInfo(
          id: 'zhipu',
          name: '智谱AI',
          description: 'GLM-5 大模型',
          freeQuota: '免费额度',
          registerUrl: 'https://open.bigmodel.cn/',
          apiKeyUrl: 'https://open.bigmodel.cn/usercenter/apikeys',
          iconAsset: 'assets/ai_icons/zhipu.png',
          models: [
            AiModelInfo(
              id: 'glm-5v-turbo',
              displayName: 'GLM-5V-Turbo',
              contextLength: 128000,
            ),
            AiModelInfo(
              id: 'glm-5.1',
              displayName: 'GLM-5.1',
              contextLength: 128000,
            ),
          ],
        );
      case 'moonshot':
        return AiServiceInfo(
          id: 'moonshot',
          name: 'Kimi',
          description: '月之暗面 Kimi',
          freeQuota: '免费额度',
          registerUrl: 'https://platform.moonshot.cn/',
          apiKeyUrl: 'https://platform.moonshot.cn/console/api-keys',
          iconAsset: 'assets/ai_icons/moonshot.png',
          models: [
            AiModelInfo(
              id: 'kimi-k2.6',
              displayName: 'Kimi K2.6',
              contextLength: 131072,
            ),
          ],
        );
      case 'doubao':
        return AiServiceInfo(
          id: 'doubao',
          name: '豆包 AI',
          description: '火山引擎豆包',
          freeQuota: '200万 token',
          registerUrl: 'https://console.volcengine.com/ark',
          apiKeyUrl: 'https://console.volcengine.com/ark',
          iconAsset: 'assets/ai_icons/doubao.png',
          models: [
            AiModelInfo(
              id: 'doubao-seed-2.0-lite',
              displayName: 'Doubao-Seed-2.0-lite',
              contextLength: 131072,
            ),
          ],
        );
      case 'tongyi':
        return AiServiceInfo(
          id: 'tongyi',
          name: '通义千问',
          description: '阿里云通义千问',
          freeQuota: '500万 token/月',
          registerUrl: 'https://bailian.console.aliyun.com/',
          apiKeyUrl: 'https://bailian.console.aliyun.com/',
          iconAsset: 'assets/ai_icons/tongyi.png',
          models: [
            AiModelInfo(
              id: 'qwen3.5',
              displayName: 'Qwen3.5',
              contextLength: 131072,
            ),
            AiModelInfo(
              id: 'qwen3-learning',
              displayName: 'Qwen3-Learning',
              contextLength: 131072,
            ),
          ],
        );
      case 'hunyuan':
        return AiServiceInfo(
          id: 'hunyuan',
          name: '混元 AI',
          description: '腾讯云混元',
          freeQuota: '10万 token/天',
          registerUrl: 'https://cloud.tencent.com/product/hunyuan',
          apiKeyUrl: 'https://cloud.tencent.com/product/hunyuan',
          iconAsset: 'assets/ai_icons/hunyuan.png',
          models: [
            AiModelInfo(
              id: 'hunyuan-hy3-preview',
              displayName: '混元Hy3 preview',
              contextLength: 131072,
            ),
          ],
        );
      case 'minimax':
        return AiServiceInfo(
          id: 'minimax',
          name: 'MiniMax',
          description: 'MiniMax 大模型',
          freeQuota: '免费额度',
          registerUrl: 'https://platform.minimaxi.com/',
          apiKeyUrl: 'https://platform.minimaxi.com/',
          iconAsset: 'assets/ai_icons/minimax.png',
          models: [
            AiModelInfo(
              id: 'minimax-m2.7',
              displayName: 'MiniMax-M2.7',
              contextLength: 131072,
            ),
          ],
        );
      case 'stepfun':
        return AiServiceInfo(
          id: 'stepfun',
          name: '阶跃星辰',
          description: 'Step 系列大模型',
          freeQuota: '免费额度',
          registerUrl: 'https://platform.stepfun.com/',
          apiKeyUrl: 'https://platform.stepfun.com/',
          iconAsset: 'assets/ai_icons/stepfun.png',
          models: [
            AiModelInfo(
              id: 'stepaudio-2.5-realtime',
              displayName: 'StepAudio 2.5 Realtime',
              contextLength: 131072,
            ),
          ],
        );
      case 'baichuan':
        return AiServiceInfo(
          id: 'baichuan',
          name: '百川智能',
          description: 'Baichuan 大模型',
          freeQuota: '免费额度',
          registerUrl: 'https://platform.baichuan-ai.com/',
          apiKeyUrl: 'https://platform.baichuan-ai.com/',
          iconAsset: 'assets/ai_icons/baichuan.png',
          models: [
            AiModelInfo(
              id: 'Baichuan4',
              displayName: 'Baichuan4',
              contextLength: 131072,
            ),
            AiModelInfo(
              id: 'Baichuan3-Turbo',
              displayName: 'Baichuan3 Turbo',
              contextLength: 131072,
            ),
            AiModelInfo(
              id: 'Baichuan3-Turbo-128k',
              displayName: 'Baichuan3 Turbo 128K',
              contextLength: 131072,
            ),
          ],
        );
      case 'spark':
        return AiServiceInfo(
          id: 'spark',
          name: '讯飞星火',
          description: 'Spark 大模型',
          freeQuota: '200万 token免费',
          registerUrl: 'https://xinghuo.xfyun.cn/',
          apiKeyUrl: 'https://xinghuo.xfyun.cn/',
          iconAsset: 'assets/ai_icons/spark.png',
          models: [
            AiModelInfo(
              id: 'spark-x2-flash',
              displayName: '星火X2-Flash',
              contextLength: 32768,
            ),
          ],
        );
      case 'yi':
        return AiServiceInfo(
          id: 'yi',
          name: '零一万物',
          description: 'Yi 系列大模型',
          freeQuota: '免费额度',
          registerUrl: 'https://platform.lingyiwanwu.com/',
          apiKeyUrl: 'https://platform.lingyiwanwu.com/',
          iconAsset: 'assets/ai_icons/yi.png',
          models: [
            AiModelInfo(
              id: 'yi-lightning',
              displayName: 'Yi Lightning',
              contextLength: 16384,
            ),
            AiModelInfo(
              id: 'yi-large',
              displayName: 'Yi Large',
              contextLength: 32768,
            ),
            AiModelInfo(
              id: 'yi-medium',
              displayName: 'Yi Medium',
              contextLength: 16384,
            ),
            AiModelInfo(
              id: 'yi-vision',
              displayName: 'Yi Vision',
              contextLength: 16384,
            ),
          ],
        );
      case 'ernie':
        return AiServiceInfo(
          id: 'ernie',
          name: '文心一言',
          description: '百度 ERNIE 大模型',
          freeQuota: '免费额度',
          registerUrl: 'https://console.bce.baidu.com/qianfan/',
          apiKeyUrl: 'https://console.bce.baidu.com/qianfan/',
          iconAsset: 'assets/ai_icons/ernie.png',
          models: [
            AiModelInfo(
              id: 'ernie-5.1',
              displayName: '文心大模型5.1',
              contextLength: 131072,
            ),
          ],
        );
      case 'gemini':
        return AiServiceInfo(
          id: 'gemini',
          name: 'Gemini',
          description: 'Google Gemini',
          freeQuota: '60万 token/月',
          registerUrl: 'https://ai.google.dev/',
          apiKeyUrl: 'https://ai.google.dev/',
          iconAsset: 'assets/ai_icons/gemini.png',
          models: [
            AiModelInfo(
              id: 'gemini-3.1',
              displayName: 'Gemini 3.1',
              contextLength: 1048576,
            ),
            AiModelInfo(
              id: 'gemini-3.1-flash-lite',
              displayName: 'Gemini 3.1 Flash-Lite',
              contextLength: 1048576,
            ),
          ],
        );
      case 'huggingface':
        return AiServiceInfo(
          id: 'huggingface',
          name: 'Hugging Face',
          description: '开源模型托管',
          freeQuota: '100万 token/月',
          registerUrl: 'https://huggingface.co/',
          apiKeyUrl: 'https://huggingface.co/',
          iconAsset: 'assets/ai_icons/huggingface.png',
          models: [
            AiModelInfo(
              id: 'littlamb',
              displayName: 'LittleLamb',
              contextLength: 131072,
            ),
            AiModelInfo(
              id: 'nanowhale',
              displayName: 'nanowhale',
              contextLength: 131072,
            ),
            AiModelInfo(
              id: 'sage-32b',
              displayName: 'SAGE-32B',
              contextLength: 131072,
            ),
          ],
        );
      case 'custom':
        return AiServiceInfo(
          id: 'custom',
          name: '自定义模型',
          description: '用户自定义的AI模型',
          freeQuota: '取决于模型提供商',
          registerUrl: '',
        );
      default:
        throw ArgumentError('不支持的 AI 服务: $serviceId');
    }
  }

  static List<AiServiceInfo> getAllServiceInfo() {
    return supportedServices.map(getServiceInfo).toList();
  }
}

class AiModelInfo {
  final String id;
  final String displayName;
  final int contextLength;

  const AiModelInfo({
    required this.id,
    required this.displayName,
    required this.contextLength,
  });
}

class AiServiceInfo {
  final String id;
  final String name;
  final String description;
  final String freeQuota;
  final String registerUrl;
  final String? apiKeyUrl;
  final List<AiModelInfo> models;
  final String iconAsset;

  AiServiceInfo({
    required this.id,
    required this.name,
    required this.description,
    required this.freeQuota,
    required this.registerUrl,
    this.apiKeyUrl,
    this.models = const [],
    this.iconAsset = '',
  });
}
