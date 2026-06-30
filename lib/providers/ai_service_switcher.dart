import '../core/logger/app_logger.dart';
import '../models/message.dart';
import '../services/ai_service.dart';
import '../services/ai_service_factory.dart';
import '../services/custom_model_service.dart';
import '../services/ernie_service.dart';
import '../services/gemini_service.dart';
import '../services/openai_compatible_service.dart';
import '../services/settings_service.dart';
import '../services/storage_service.dart';
import 'conversation_loader.dart';
import 'conversation_provider.dart';
import 'memory_provider.dart';

/// AI 服务切换器（从 ChatProvider 抽出的 helper）
///
/// 做什么：负责"切换 AI 服务商 + 加载对应会话列表 + 应用高级参数到服务实例"。
/// 为什么这样做：ChatProvider 是 Facade，AI 服务切换逻辑（~160 行）与会话操作、
/// 发送流程混在一起。抽出后 ChatProvider 仅转发调用，逻辑独立可测。
///
/// 设计说明（遵循 ChatSendOrchestrator 的 helper 模式）：
/// - 不继承 ChangeNotifier，通过 [onNotify] 回调通知调用方触发 UI 更新
/// - _currentAiService 是共享状态（发送流程也要读），留 ChatProvider，
///   通过 [getCurrentAiService]/[setCurrentAiService] 回调读写
/// - _messages 是共享状态，留 ChatProvider，通过 [setMessages] 回调写
/// - 切换服务前需取消流式响应，通过 [onCancelStreaming] 回调触发
/// - 加载会话时若无会话需创建默认会话，依赖 [conversationLoader]
class AiServiceSwitcher {
  AiServiceSwitcher({
    required this.conversationProvider,
    required this.memoryProvider,
    required this.settingsService,
    required this.storageService,
    required this.conversationLoader,
    required this.getCurrentAiService,
    required this.setCurrentAiService,
    required this.setMessages,
    required this.onNotify,
    required this.onCancelStreaming,
  });

  // ── 依赖 ──
  final ConversationProvider conversationProvider;
  final MemoryProvider memoryProvider;
  final SettingsService settingsService;
  final StorageService storageService;

  /// 会话加载器引用（_loadConversationsForService 无会话时调用 createAndSwitchDefault）
  final ConversationLoader conversationLoader;

  // ── 共享状态回调（_currentAiService / _messages 留 ChatProvider）──

  /// 读取当前 AI 服务实例（_currentAiService 留 ChatProvider）
  final AiService Function() getCurrentAiService;

  /// 替换当前 AI 服务实例（switchAiService 创建新服务后调用）
  final void Function(AiService service) setCurrentAiService;

  /// 替换整个消息列表（_loadConversationsForService 加载会话消息后调用）
  final void Function(List<Message> messages) setMessages;

  /// 通知 UI 更新（通常传入 ChatProvider.notifyListeners）
  final void Function() onNotify;

  /// 取消正在进行的流式响应（switchAiService 前调用，避免流状态错乱）
  final void Function() onCancelStreaming;

  // ── 便捷 getter ──
  bool get _storageReady => storageService.isInitialized;
  bool get _settingsReady => settingsService.isInitialized;

  /// 更新当前服务的设置（应用高级参数 + 自定义模型配置）
  ///
  /// 做什么：从 SettingsService 读取参数，应用到当前 AiService 实例。
  /// 为什么这样做：用户在设置页修改参数后需调用此方法使新参数生效。
  void updateServiceSettings() {
    if (!_settingsReady) return;
    final service = getCurrentAiService();
    applyAdvancedSettings(service);

    if (service is CustomModelService) {
      service.model = settingsService.getCustomModelName();
      service.apiKey = settingsService.getApiKeyForService('custom') ?? '';
    }

    onNotify();
  }

  /// 切换 AI 服务
  ///
  /// 做什么：根据 serviceId 创建新的 AiService 实例并替换当前服务，
  /// 然后加载对应服务的会话列表。
  /// [forceRefresh] 为 true 时，即使 serviceId 相同也会重建服务实例，
  /// 用于保存 API Key 后强制刷新当前服务，使新 key 立即生效。
  Future<void> switchAiService(
    String serviceId, {
    bool forceRefresh = false,
  }) async {
    AppLogger.d(
      '[AiServiceSwitcher] switchAiService 被调用，目标服务: $serviceId, forceRefresh: $forceRefresh',
    );
    AppLogger.d(
      '[AiServiceSwitcher] 当前服务: ${getCurrentAiService().serviceId} (${getCurrentAiService().serviceName})',
    );

    // 服务相同且不强制刷新时，跳过重建
    // 但保存 API Key 后需要 forceRefresh=true 才能用新 key 重建服务实例
    if (!forceRefresh && getCurrentAiService().serviceId == serviceId) {
      AppLogger.d('[AiServiceSwitcher] 服务相同，无需切换');
      return;
    }

    // 切换前取消正在进行的流式响应（流状态在 _sendOrchestrator）
    onCancelStreaming();

    String? apiKey;
    String? baseUrl;
    String? model;

    if (_settingsReady) {
      apiKey = settingsService.getApiKeyForService(serviceId);
      if (serviceId == 'custom') {
        baseUrl = settingsService.getCustomModelBaseUrl();
        model = settingsService.getCustomModelName();
      }
    }
    if (apiKey == null || apiKey.isEmpty) {
      apiKey = AiServiceFactory.getApiKeyFromEnv(serviceId);
    }

    // 仅记录 API Key 的配置状态（已配置/未配置），不记录真实 key 值
    // ignore: avoid_logging_sensitive_data
    AppLogger.d(
      '[AiServiceSwitcher] 创建新服务: $serviceId, API Key: ${apiKey != null && apiKey.isNotEmpty ? "已配置" : "未配置"}',
    );

    final newService = AiServiceFactory.createService(
      serviceId,
      apiKey: apiKey ?? '',
      baseUrl: baseUrl,
      model: model,
    );

    AppLogger.i(
      '[AiServiceSwitcher] 新服务创建成功: ${newService.serviceId} (${newService.serviceName})',
    );

    setCurrentAiService(newService);
    applyAdvancedSettings(newService);
    AppLogger.d(
      '[AiServiceSwitcher] _currentAiService 已更新为: ${getCurrentAiService().serviceId}',
    );

    // 仅在真正切换服务商时重新加载会话列表
    // forceRefresh 场景（如更新 API Key）serviceId 不变，无需重新加载会话
    if (!forceRefresh && _storageReady) {
      try {
        storageService.switchService(serviceId);
        await loadConversationsForService(serviceId);
      } on Exception catch (e) {
        // N5: 只捕获 Exception，让 Error 向上传播
        AppLogger.e('[AiServiceSwitcher] switchService 异常: $e');
      }
    }

    AppLogger.d('[AiServiceSwitcher] 调用 notifyListeners()');
    onNotify();
  }

  /// 切换服务后加载该服务的会话列表
  ///
  /// 做什么：从存储加载会话列表，若无会话则创建默认会话，否则恢复 lastConversationId。
  /// 为什么这样做：每个 AI 服务商有独立的会话列表，切换后需加载对应会话。
  Future<void> loadConversationsForService(String serviceId) async {
    conversationProvider.loadFromStorage();

    AppLogger.i(
      '[AiServiceSwitcher] 切换服务 $serviceId，加载到 ${conversationProvider.conversations.length} 个会话',
    );

    if (conversationProvider.conversations.isEmpty) {
      await conversationLoader.createAndSwitchDefault('新的对话');
      return;
    }

    // 空安全：先缓存第一个会话 id，避免 .first 在异常空集合时崩溃
    final firstId = conversationProvider.conversations.firstOrNull?.id;
    if (firstId == null) {
      await conversationLoader.createAndSwitchDefault('新的对话');
      return;
    }
    String? lastId;
    if (_settingsReady) {
      lastId = settingsService.getLastConversationId();
    }
    if (lastId != null && lastId.isNotEmpty) {
      final found = conversationProvider.conversations
          .where((c) => c.id == lastId)
          .firstOrNull;
      if (found != null) {
        conversationProvider.switchTo(found.id);
      } else {
        conversationProvider.switchTo(firstId);
      }
    } else {
      conversationProvider.switchTo(firstId);
    }
    // 为切换后的当前会话初始化 MemLocal session
    final currentConvId = conversationProvider.currentConversationId;
    if (currentConvId != null) {
      // 按需加载当前会话的 base64（头像/壁纸）
      await conversationProvider.loadCurrentAppearanceAsync(currentConvId);
      await memoryProvider.initSession(currentConvId);
    }
    // 空安全：缓存 currentConversation，避免 ! 强制非空断言崩溃
    final currentConv = conversationProvider.currentConversation;
    if (currentConv == null) {
      await conversationLoader.createAndSwitchDefault('新的对话');
      return;
    }
    final messages = await storageService.getMessagesAsync(currentConv.id);
    setMessages(messages);
    AppLogger.d('[AiServiceSwitcher] 加载到 ${messages.length} 条消息');
  }

  /// 应用高级参数到 AI 服务实例
  ///
  /// 做什么：从 SettingsService 读取 model/temperature/maxTokens 等参数，
  /// 根据 AiService 子类型设置对应字段。
  /// 为什么这样做：不同 AiService 子类支持的参数不同，需按类型分支设置。
  // N9: 该方法的目的就是把高级设置应用到传入的 service 对象上，修改参数是设计意图
  // ignore: avoid_parameter_mutation
  void applyAdvancedSettings(AiService service) {
    if (!_settingsReady) return;
    final modelId = settingsService.getModel();
    if (modelId.isNotEmpty) service.model = modelId;

    if (service is OpenAiCompatibleService) {
      service.temperature = settingsService.getTemperature();
      service.maxTokens = settingsService.getMaxTokens();
      service.topP = settingsService.getTopP();
      service.frequencyPenalty = settingsService.getFrequencyPenalty();
      service.presencePenalty = settingsService.getPresencePenalty();
    } else if (service is GeminiService) {
      service.temperature = settingsService.getTemperature();
      service.maxTokens = settingsService.getMaxTokens();
      service.topP = settingsService.getTopP();
    } else if (service is ErnieService) {
      service.temperature = settingsService.getTemperature();
      service.maxTokens = settingsService.getMaxTokens();
      service.topP = settingsService.getTopP();
    }
  }
}
