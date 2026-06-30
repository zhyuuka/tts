import 'package:flutter/material.dart';

import '../core/logger/app_logger.dart';
import '../models/attachment.dart';
import '../models/conversation.dart';
import '../models/message.dart';
import '../services/ai_service.dart';
import '../services/chat_token_service.dart';
import '../services/memlocal_service.dart';
import '../services/memu_service.dart';
import '../services/search/search_service.dart';
import '../services/settings_service.dart';
import '../services/storage_service.dart';
import 'ai_service_switcher.dart';
import 'backup_provider.dart';
import 'chat_send_orchestrator.dart';
import 'conversation_loader.dart';
import 'conversation_provider.dart';
import 'memory_provider.dart';
import 'search_provider.dart';

/// 聊天应用核心 Provider（Facade 模式阶段 3）
///
/// 做什么：本类是聊天功能的统一门面，所有具体逻辑已抽到 3 个 helper：
/// - [ConversationLoader]：启动加载会话、切换会话加载消息、分页加载更多
/// - [AiServiceSwitcher]：切换 AI 服务商、加载对应会话、应用高级参数
/// - [ChatSendOrchestrator]：发送消息全流程（流式响应、持久化、记忆写入）
/// - [ChatTokenService]：Token 估算
///
/// 为什么这样做：原 ChatProvider 是 God Class（685 行），发送/加载/切换/Token 估算
/// 全部混在一起。拆分后 ChatProvider 仅保留：
/// 1. 5 个 Provider + 2 个 Service 的持有与生命周期管理
/// 2. 共享状态（_messages, _currentAiService, _isInitializing）
/// 3. 会话操作的薄包装（创建/切换/重命名/删除 + 外观加载协调）
/// 4. 所有方法的 Facade 转发（调用方零改动）
///
/// 设计说明：
/// - _messages 是共享状态，留本类（3 个 helper 通过回调读写）
/// - _currentAiService 留本类（_sendOrchestrator 读，_aiSwitcher 读写）
/// - _hasMoreMessages/_loadedMessageCount/_isLoadingMoreMessages 移到 ConversationLoader
class ChatProvider extends ChangeNotifier {
  final StorageService _storageService;
  final SettingsService _settingsService;
  final ConversationProvider _conversationProvider;
  final MemoryProvider _memoryProvider;
  final SearchProvider _searchProvider;
  final BackupProvider _backupProvider;
  AiService _currentAiService;

  // P2 #14: Token 估算从 ChatProvider 抽出，减少 God Class 体积。
  late final ChatTokenService _tokenService;

  // 发送流程编排器：从 ChatProvider 抽出 sendMessage 全流程（~400 行），
  // 遵循 ChatStreamingController 的 helper 模式（独立类 + 回调）。
  late final ChatSendOrchestrator _sendOrchestrator;

  // 批次 3 T5: 会话加载器（启动加载/切换加载/分页加载更多）
  // _hasMoreMessages/_loadedMessageCount/_isLoadingMoreMessages 移到本类内部管理
  late final ConversationLoader _conversationLoader;

  // 批次 3 T5: AI 服务切换器（切换服务商 + 加载会话 + 应用高级参数）
  late final AiServiceSwitcher _aiSwitcher;

  // ── 共享状态（留本类，3 个 helper 通过回调读写）──
  List<Message> _messages = [];
  bool _isInitializing = true;

  ChatProvider({
    required StorageService storageService,
    required SettingsService settingsService,
    required SearchService searchService,
    required MemUService memuService,
    required MemLocalService memLocalService,
    required AiService initialAiService,
  }) : _storageService = storageService,
       _settingsService = settingsService,
       _conversationProvider = ConversationProvider(
         storageService: storageService,
         settingsService: settingsService,
       ),
       _memoryProvider = MemoryProvider(
         memuService: memuService,
         memLocalService: memLocalService,
       ),
       _searchProvider = SearchProvider(
         settingsService: settingsService,
         searchService: searchService,
       ),
       _backupProvider = BackupProvider(storageService: storageService),
       _currentAiService = initialAiService {
    _tokenService = ChatTokenService(settingsService);

    // 批次 3 T5: 会话加载器先初始化（_aiSwitcher 依赖它）
    _conversationLoader = ConversationLoader(
      conversationProvider: _conversationProvider,
      memoryProvider: _memoryProvider,
      settingsService: settingsService,
      storageService: storageService,
      getMessages: () => _messages,
      setMessages: (msgs) => _messages = msgs,
      onNotify: notifyListeners,
    );

    // P2 #14: 发送流程抽到 ChatSendOrchestrator（必须在 _aiSwitcher 之前初始化，
    // 因为 _aiSwitcher 的 onCancelStreaming 是 _sendOrchestrator.cancelStreamingAndReset
    // 的 tear-off，求值时需访问已初始化的 _sendOrchestrator）。
    // _messages / _currentAiService 留在本类（共享状态），通过回调读写。
    // onUpdateServiceSettings 绑定到本类的 updateServiceSettings（转发到 _aiSwitcher，
    // 运行时才调用，届时 _aiSwitcher 已初始化）。
    // onRenameConversation 绑定到本类的 renameConversation（自动命名用）。
    _sendOrchestrator = ChatSendOrchestrator(
      conversationProvider: _conversationProvider,
      memoryProvider: _memoryProvider,
      searchProvider: _searchProvider,
      settingsService: settingsService,
      storageService: storageService,
      getMessages: () => _messages,
      addMessage: (msg) => _messages.add(msg),
      onNotify: notifyListeners,
      getCurrentAiService: () => _currentAiService,
      onUpdateServiceSettings: updateServiceSettings,
      onRenameConversation: renameConversation,
    );

    // 批次 3 T5: AI 服务切换器（依赖 _conversationLoader + _sendOrchestrator）
    _aiSwitcher = AiServiceSwitcher(
      conversationProvider: _conversationProvider,
      memoryProvider: _memoryProvider,
      settingsService: settingsService,
      storageService: storageService,
      conversationLoader: _conversationLoader,
      getCurrentAiService: () => _currentAiService,
      setCurrentAiService: (service) => _currentAiService = service,
      setMessages: (msgs) => _messages = msgs,
      onNotify: notifyListeners,
      onCancelStreaming: _sendOrchestrator.cancelStreamingAndReset,
    );
  }

  ConversationProvider get conversationProvider => _conversationProvider;
  MemoryProvider get memoryProvider => _memoryProvider;
  SearchProvider get searchProvider => _searchProvider;
  BackupProvider get backupProvider => _backupProvider;

  @override
  void dispose() {
    _sendOrchestrator.dispose();
    _conversationProvider.dispose();
    _memoryProvider.dispose();
    _searchProvider.dispose();
    _backupProvider.dispose();
    super.dispose();
  }

  Future<void> init() async {
    _isInitializing = true;
    notifyListeners();
    await _conversationLoader.loadOrInitConversations();
    _isInitializing = false;
    notifyListeners();
  }

  // ── Getters（会话委托给 _conversationProvider，发送状态委托给 _sendOrchestrator，
  //    分页状态委托给 _conversationLoader）──

  List<Conversation> get conversations => _conversationProvider.conversations;
  Conversation? get currentConversation =>
      _conversationProvider.currentConversation;
  String? get currentConversationId =>
      _conversationProvider.currentConversationId;
  List<Message> get messages => _messages;
  AiService get currentAiService => _currentAiService;
  StorageService get storageService => _storageService;
  MemUService get memuService => _memoryProvider.memuService;
  bool get isInitializing => _isInitializing;

  // 分页状态转发给 _conversationLoader
  bool get isLoadingMoreMessages => _conversationLoader.isLoadingMoreMessages;
  bool get hasMoreMessages => _conversationLoader.hasMoreMessages;

  // 发送状态转发给 _sendOrchestrator
  bool get isLoading => _sendOrchestrator.isLoading;
  bool get isSummarizing => _sendOrchestrator.isSummarizing;
  String? get error => _sendOrchestrator.error;

  /// P1 #7: 消息保存是否曾失败（只读）。供 UI 未来可选展示提示，不触发 rebuild。
  bool get hasSaveError => _sendOrchestrator.hasSaveError;

  bool get isStreaming => _sendOrchestrator.isStreaming;
  String get streamingContent => _sendOrchestrator.streamingContent;
  String get streamingReasoning => _sendOrchestrator.streamingReasoning;
  bool get streamingHasReasoning => _sendOrchestrator.streamingHasReasoning;

  bool get _storageReady => _storageService.isInitialized;

  // ── 会话操作（委托给 _conversationProvider + _conversationLoader）──

  /// 直接添加一条 AI 助手消息（不触发 AI 回复）
  ///
  /// 做什么：在当前会话插入一条 role='assistant' 的消息并持久化。
  /// 为什么这样做：Agent 任务结果应显示为助手消息，而非用户消息。
  /// 用 sendMessage 会保存为 role='user' 并触发 AI 回复，语义错误且产生额外 AI 调用。
  /// 此方法直接插入助手消息，不触发 AI 调用。
  void addAssistantMessage(String content) {
    final message = Message(
      role: 'assistant',
      content: content,
      timestamp: DateTime.now(),
    );
    _messages = [..._messages, message];
    // 持久化到数据库
    if (_storageReady && currentConversation != null) {
      _storageService.saveMessagesSync(currentConversation!.id, _messages);
    }
    notifyListeners();
  }

  Future<void> createConversation(String name) async {
    await _conversationLoader.createAndSwitchDefault(name);
    AppLogger.i('[ChatProvider] createConversation 成功: $name');
  }

  Future<void> switchConversation(String id) async {
    if (_conversationProvider.currentConversationId == id) {
      AppLogger.d('[ChatProvider] switchConversation: 相同会话，跳过 $id');
      return;
    }

    AppLogger.i(
      '[ChatProvider] switchConversation: 从 ${_conversationProvider.currentConversationId} 切换到 $id',
    );

    // 切换前取消正在进行的流式响应（流状态在 _sendOrchestrator）
    _sendOrchestrator.cancelStreamingAndReset();

    _conversationProvider.switchTo(id);

    // 按需加载当前会话的 base64（头像/壁纸）。
    // 为什么这样做：switchTo 使用 metadata 版本（无 base64），
    // 需单独加载当前会话的 base64 供 UI 渲染。异步加载，短暂显示默认图。
    await _conversationProvider.loadCurrentAppearanceAsync(id);

    // 切换会话时初始化 MemLocal 记忆会话，确保记忆系统能保存和检索
    await _memoryProvider.initSession(id);

    if (_storageReady) {
      await _conversationLoader.loadMessagesOnSwitch(id);
    } else {
      _messages = [];
      _conversationLoader.resetPagingState();
      AppLogger.d('[ChatProvider] switchConversation: 存储未就绪');
    }
    notifyListeners();
  }

  void refreshConversations() {
    _conversationProvider.refreshConversations();
    notifyListeners();
    AppLogger.i(
      '[ChatProvider] 已刷新会话列表，共 ${_conversationProvider.conversations.length} 个会话',
    );
  }

  Future<bool> renameConversation(String id, String newName) async {
    final ok = await _conversationProvider.rename(id, newName);
    if (ok) notifyListeners();
    return ok;
  }

  Future<bool> setConversationPrompt(String id, String prompt) async {
    // 在变更前创建人格快照
    final conv = _conversationProvider.conversations
        .where((c) => c.id == id)
        .firstOrNull;
    if (conv != null && conv.systemPrompt != prompt) {
      await _memoryProvider.snapshotBeforePromptChange(
        conversationId: id,
        conversationName: conv.name,
        oldSystemPrompt: conv.systemPrompt,
      );
    }

    final ok = await _conversationProvider.setPrompt(id, prompt);
    if (ok) notifyListeners();
    return ok;
  }

  Future<bool> updateConversationAppearance(
    String id, {
    String? avatarBase64,
    String? wallpaperBase64,
  }) async {
    final ok = await _conversationProvider.updateAppearance(
      id,
      avatarBase64: avatarBase64,
      wallpaperBase64: wallpaperBase64,
    );
    if (ok) notifyListeners();
    return ok;
  }

  Future<bool> deleteConversation(String id) async {
    final ok = await _conversationProvider.delete(id);
    if (ok) {
      // 清理被删除会话的 MemLocal session 缓存
      _memoryProvider.removeSession(id);

      if (_conversationProvider.currentConversation != null) {
        final newConvId = _conversationProvider.currentConversation!.id;
        // 为切换到的新会话初始化 MemLocal session
        await _memoryProvider.initSession(newConvId);
        _messages = await _storageService.getMessagesAsync(newConvId);
      } else {
        _messages = [];
      }
      notifyListeners();
    }
    return ok;
  }

  // ── AI 服务设置（转发到 _aiSwitcher）──

  void updateServiceSettings() => _aiSwitcher.updateServiceSettings();

  /// 切换 AI 服务
  /// [forceRefresh] 为 true 时，即使 serviceId 相同也会重建服务实例
  /// 用于保存 API Key 后强制刷新当前服务，使新 key 立即生效
  Future<void> switchAiService(String serviceId, {bool forceRefresh = false}) =>
      _aiSwitcher.switchAiService(serviceId, forceRefresh: forceRefresh);

  // ── 消息加载（转发到 _conversationLoader）──

  Future<void> loadMoreMessages() => _conversationLoader.loadMoreMessages();

  // ── 发送消息（转发给 _sendOrchestrator）──
  // P2 #14: 发送流程（sendMessage + 10 个私有方法 + stopGeneration/retryLastMessage/clearError）
  // 已移至 ChatSendOrchestrator。ChatProvider 作为 Facade 转发调用。

  Future<void> sendMessage(String content, {List<Attachment>? attachments}) =>
      _sendOrchestrator.sendMessage(content, attachments: attachments);

  void stopGeneration() => _sendOrchestrator.stopGeneration();

  void clearError() => _sendOrchestrator.clearError();

  Future<void> retryLastMessage() => _sendOrchestrator.retryLastMessage();

  // ── Token 估算 ──
  // P2 #14: Token 估算逻辑已移至 ChatTokenService。

  int estimateContextTokens() {
    return _tokenService.estimateContextTokens(
      _messages,
      isStreaming: _sendOrchestrator.isStreaming,
      streamingContent: _sendOrchestrator.streamingContent,
      streamingReasoning: _sendOrchestrator.streamingReasoning,
    );
  }

  int estimateInputTokens(String text) =>
      _tokenService.estimateInputTokens(text);

  int get maxContextTokens => _tokenService.maxContextTokens;

  Future<void> toggleSearchEnabled() async {
    if (!_settingsService.isInitialized) return;
    final current = _settingsService.isSearchEnabled();
    await _settingsService.setSearchEnabled(!current);
    notifyListeners();
  }

  // ── 记忆系统 ──

  Future<void> summarizeManually() async {
    AppLogger.d('[ChatProvider] 手动总结功能已由MemU替代');
  }

  Future<void> clearMessages() async {
    // 空安全：缓存 currentConversation，避免 ! 断言崩溃
    final currentConv = _conversationProvider.currentConversation;
    if (currentConv == null) return;
    _messages.clear();
    if (_storageReady) {
      await _storageService.clearMessagesAsync(currentConv.id);
    }
    notifyListeners();
  }

  // ── 备份导入导出 ──

  Future<String?> exportBackup() => _backupProvider.exportBackup();

  Future<int?> importBackup(String filePath) async {
    final count = await _backupProvider.importBackup(filePath);
    if (count != null) {
      _conversationProvider.loadFromStorage();
      notifyListeners();
    }
    return count;
  }
}
