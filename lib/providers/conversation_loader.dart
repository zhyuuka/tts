import '../core/logger/app_logger.dart';
import '../models/conversation.dart';
import '../models/message.dart';
import '../services/settings_service.dart';
import '../services/storage_service.dart';
import 'conversation_provider.dart';
import 'memory_provider.dart';

/// 会话加载器（从 ChatProvider 抽出的 helper）
///
/// 做什么：负责"启动时加载会话列表 + 切换会话时加载消息 + 分页加载更多消息"。
/// 为什么这样做：ChatProvider 是 Facade，会话加载逻辑（~220 行）与发送流程、
/// AI 服务切换混在一起认知负担重。抽出后 ChatProvider 仅转发调用，逻辑独立可测。
///
/// 设计说明（遵循 ChatSendOrchestrator 的 helper 模式）：
/// - 不继承 ChangeNotifier，通过 [onNotify] 回调通知调用方触发 UI 更新
/// - _messages 是共享状态（发送/加载/切换都读写），留 ChatProvider，
///   通过 [getMessages]/[setMessages] 回调读写
/// - _hasMoreMessages / _loadedMessageCount / _isLoadingMoreMessages 仅会话加载用，
///   移到本类内部管理（ChatProvider 通过 getter 转发）
class ConversationLoader {
  ConversationLoader({
    required this.conversationProvider,
    required this.memoryProvider,
    required this.settingsService,
    required this.storageService,
    required this.getMessages,
    required this.setMessages,
    required this.onNotify,
  });

  // ── 依赖 ──
  final ConversationProvider conversationProvider;
  final MemoryProvider memoryProvider;
  final SettingsService settingsService;
  final StorageService storageService;

  // ── 共享状态回调（_messages 留 ChatProvider，发送流程也要读写）──

  /// 读取当前消息列表（_messages 留 ChatProvider）
  final List<Message> Function() getMessages;

  /// 替换整个消息列表（切换会话/加载更多时用）
  final void Function(List<Message> messages) setMessages;

  /// 通知 UI 更新（通常传入 ChatProvider.notifyListeners）
  final void Function() onNotify;

  // ── 自持状态（仅会话加载用，从 ChatProvider 移入）──

  /// 是否正在加载更多消息（loadMoreMessages 用，防止重复触发）
  bool _isLoadingMoreMessages = false;

  /// 是否还有更多历史消息可加载（分页用）
  bool _hasMoreMessages = true;

  /// 当前已加载的消息数（分页计算用）
  int _loadedMessageCount = 0;

  // ── 暴露给 ChatProvider 的 getter（Facade 转发用）──
  bool get isLoadingMoreMessages => _isLoadingMoreMessages;
  bool get hasMoreMessages => _hasMoreMessages;
  int get loadedMessageCount => _loadedMessageCount;

  // ── 便捷 getter（避免每次都通过回调判断 _settingsReady）──
  bool get _storageReady => storageService.isInitialized;
  bool get _settingsReady => settingsService.isInitialized;

  /// 启动时加载或初始化会话列表
  ///
  /// 做什么：从存储加载会话列表，若无会话则创建默认会话，否则恢复上次会话。
  /// 为什么这样做：App 启动时需恢复用户上次会话状态，包括会话列表、当前会话、消息。
  Future<void> loadOrInitConversations() async {
    if (!_storageReady) {
      AppLogger.d('[ConversationLoader] 存储未就绪，跳过加载会话');
      setMessages([]);
      onNotify();
      return;
    }

    AppLogger.d(
      '[ConversationLoader] 开始加载会话列表, 存储路径: ${storageService.rootPath}',
    );
    conversationProvider.loadFromStorage();
    AppLogger.d(
      '[ConversationLoader] 加载到 ${conversationProvider.conversations.length} 个会话',
    );

    if (conversationProvider.conversations.isEmpty) {
      AppLogger.d('[ConversationLoader] 无会话，创建默认会话');
      await createAndSwitchDefault('新的对话');
      return;
    }

    // 优先使用 preloadConversationId，其次 lastConversationId
    String? targetId;
    if (_settingsReady) {
      targetId = settingsService.getPreloadConversationId();
    }
    if (targetId == null || targetId.isEmpty) {
      if (_settingsReady) {
        targetId = settingsService.getLastConversationId();
      }
    }

    Conversation? targetConv;
    if (targetId != null && targetId.isNotEmpty) {
      targetConv = conversationProvider.conversations
          .where((c) => c.id == targetId)
          .firstOrNull;
    }

    if (targetConv != null) {
      conversationProvider.switchTo(targetConv.id);
      AppLogger.i('[ConversationLoader] 使用会话: ${targetConv.name}');
    } else {
      // 空安全：用 firstOrNull 兜底，避免 .first 在异常空集合时崩溃
      final firstConv = conversationProvider.conversations.firstOrNull;
      if (firstConv != null) {
        conversationProvider.switchTo(firstConv.id);
        AppLogger.i('[ConversationLoader] 使用第一个会话');
      } else {
        await createAndSwitchDefault('新的对话');
        return;
      }
    }

    // 初始化当前会话的 MemLocal 记忆会话
    final currentConvId = conversationProvider.currentConversationId;
    if (currentConvId != null) {
      // 按需加载当前会话的 base64（头像/壁纸）
      await conversationProvider.loadCurrentAppearanceAsync(currentConvId);
      await memoryProvider.initSession(currentConvId);
    }

    final preloadCount = _settingsReady
        ? settingsService.getPreloadMessageCount()
        : 50;

    // 空安全：缓存 currentConversation，避免 ! 断言崩溃
    final currentConv = conversationProvider.currentConversation;
    if (currentConv == null) {
      await createAndSwitchDefault('新的对话');
      return;
    }
    await _loadMessagesForCurrent(currentConv.id, preloadCount);
  }

  /// 加载指定会话的消息（含分页预加载逻辑）
  ///
  /// 做什么：读取会话全部消息，若超过 preloadCount 则只加载最近 preloadCount 条。
  /// 为什么这样做：超长会话一次性加载会卡 UI，分页预加载保证启动速度。
  Future<void> _loadMessagesForCurrent(
    String conversationId,
    int preloadCount,
  ) async {
    final allMessages = await storageService.getMessagesAsync(conversationId);
    if (allMessages.length > preloadCount) {
      setMessages(allMessages.sublist(allMessages.length - preloadCount));
      _loadedMessageCount = preloadCount;
      _hasMoreMessages = true;
    } else {
      setMessages(allMessages);
      _loadedMessageCount = allMessages.length;
      _hasMoreMessages = false;
    }
    AppLogger.d(
      '[ConversationLoader] 加载到 ${getMessages().length} 条消息 (总共 ${allMessages.length} 条)',
    );
    onNotify();
  }

  /// 分页加载更多历史消息
  ///
  /// 做什么：用户上滑到顶部时，向前加载 preloadCount 条更早的消息。
  /// 为什么这样做：长会话分页加载，避免一次性加载全部消息卡 UI。
  Future<void> loadMoreMessages() async {
    if (_isLoadingMoreMessages ||
        !_hasMoreMessages ||
        conversationProvider.currentConversation == null) {
      return;
    }

    _isLoadingMoreMessages = true;
    onNotify();

    try {
      // 空安全：缓存 currentConversation，避免 ! 断言崩溃（await 后可能变 null）
      final currentConv = conversationProvider.currentConversation;
      if (currentConv == null) {
        _hasMoreMessages = false;
        return;
      }
      final preloadCount = _settingsReady
          ? settingsService.getPreloadMessageCount()
          : 50;

      final allMessages = await storageService.getMessagesAsync(currentConv.id);
      final messages = getMessages();
      final currentCount = messages.length;
      final totalCount = allMessages.length;

      if (currentCount >= totalCount) {
        _hasMoreMessages = false;
        return;
      }

      final newStartIndex = totalCount - currentCount - preloadCount;
      final startIndex = newStartIndex < 0 ? 0 : newStartIndex;

      final newMessages = allMessages.sublist(
        startIndex,
        totalCount - currentCount,
      );
      messages.insertAll(0, newMessages);
      _loadedMessageCount = messages.length;

      if (_loadedMessageCount >= totalCount) {
        _hasMoreMessages = false;
      }

      AppLogger.d(
        '[ConversationLoader] 加载更多消息: ${newMessages.length} 条, 总计 ${messages.length} 条',
      );
    } on Exception catch (e) {
      // N5: 只捕获 Exception，让 Error 向上传播
      AppLogger.e('[ConversationLoader] 加载更多消息失败: $e');
    } finally {
      _isLoadingMoreMessages = false;
      onNotify();
    }
  }

  /// 创建默认会话并切换到它
  ///
  /// 做什么：调用 ConversationProvider.createAndSwitch 创建新会话，清空消息状态。
  /// 为什么这样做：首次启动 / 无会话 / 异常恢复时需要一个默认会话。
  Future<void> createAndSwitchDefault(String name) async {
    await conversationProvider.createAndSwitch(name);
    setMessages([]);
    _hasMoreMessages = false;
    _loadedMessageCount = 0;
    // 初始化 MemLocal 记忆会话
    final convId = conversationProvider.currentConversationId;
    if (convId != null) {
      await memoryProvider.initSession(convId);
    }
    onNotify();
  }

  /// 切换会话时加载消息（供 ChatProvider.switchConversation 调用）
  ///
  /// 做什么：读取目标会话全部消息，按 preloadCount 分页预加载。
  /// 为什么这样做：switchConversation 需要重置分页状态并加载新会话消息。
  Future<void> loadMessagesOnSwitch(String conversationId) async {
    final preloadCount = _settingsReady
        ? settingsService.getPreloadMessageCount()
        : 50;

    final allMessages = await storageService.getMessagesAsync(conversationId);
    if (allMessages.length > preloadCount) {
      setMessages(allMessages.sublist(allMessages.length - preloadCount));
      _loadedMessageCount = preloadCount;
      _hasMoreMessages = true;
    } else {
      setMessages(allMessages);
      _loadedMessageCount = allMessages.length;
      _hasMoreMessages = false;
    }
    AppLogger.d(
      '[ConversationLoader] switchConversation($conversationId): 加载到 ${getMessages().length} 条消息 (总共 ${allMessages.length} 条)',
    );
  }

  /// 重置分页状态（切换会话/删除会话后调用）
  ///
  /// 做什么：清空 _hasMoreMessages 和 _loadedMessageCount。
  /// 为什么这样做：新会话无历史消息可分页，避免 loadMoreMessages 误触发。
  void resetPagingState() {
    _hasMoreMessages = false;
    _loadedMessageCount = 0;
  }
}
