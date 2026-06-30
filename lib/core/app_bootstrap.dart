import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../providers/agent_provider.dart';
import '../providers/chat_provider.dart';
import '../services/agent/accessibility_bridge.dart';
import '../services/agent/agent_operation_logger.dart';
import '../services/agent/agent_safety_guard.dart';
import '../services/agent/agent_tool_registry.dart';
import '../services/ai_service_factory.dart';
import '../services/common/debug_mode_service.dart';
import '../services/hive_integrity_checker.dart';
import '../services/memu_service.dart';
import '../services/memory_semantic_scorer.dart';
import '../services/memlocal_service.dart';
import '../services/ncnn_tts_service.dart';
import '../services/vision/ocr_service.dart';
import '../services/search/search_service.dart';
import '../services/settings_service.dart';
import '../services/storage_service.dart';
import 'logger/app_logger.dart';

/// 应用启动编排器
///
/// 为什么这样做：原 main.dart 是 193 行的瀑布式初始化，步骤间顺序依赖
/// 隐式且敏感（如 StorageService 必须在 SettingsService 之后、ChatProvider
/// 必须在所有服务之后）。本类把初始化拆成分阶段方法，让依赖关系通过
/// 方法签名显式表达——后续阶段只能接收已就绪的依赖，编译器即可检查顺序，
/// 消除"初始化顺序敏感"的隐式契约。
///
/// 设计原则：
/// - 每个阶段方法只接收已就绪的依赖作为参数，返回本阶段创建的依赖
/// - 阶段间顺序由 run() 串联，外部无需关心
/// - 行为与原 main.dart 完全一致（日志、降级、错误处理范围不变）
class AppBootstrap {
  AppBootstrap();

  /// 调试日志服务（单例，所有阶段共用）
  /// 为什么复用：DebugModeService 是单例，持有字段避免重复 instance 调用，
  /// 行为一致。合并自原 DebugService（启动日志）+ DebugModeService（调试日志）。
  final DebugModeService _debug = DebugModeService.instance;

  /// 完整启动流程：按阶段初始化所有依赖，返回 runApp 所需的依赖
  ///
  /// 为什么用一个 run() 串联：调用方（main）只需一行即可完成全部初始化，
  /// 各阶段内部的顺序依赖由本类保证，外部无需关心。
  Future<BootstrapResult> run() async {
    await initCore();
    final storageLayer = await initStorageLayer();
    final services = await initServices(storageLayer.settings);
    final chatProvider = await initChatProvider(
      settings: storageLayer.settings,
      storage: storageLayer.storage,
      search: services.search,
      memu: services.memu,
      memLocal: services.memLocal,
    );
    // Agent 初始化（在 ChatProvider 之后、TTS 预热之前）
    // 为什么这样安排：Agent 依赖 AiServiceFactory（已就绪），
    // 但不依赖 ChatProvider，独立初始化即可
    final agentProvider = initAgent();
    // TTS 预热异步执行，不阻塞启动
    _warmUpTts(storageLayer.settings);
    _debug.info('Init', '=== 初始化完成，启动应用 ===');
    return BootstrapResult(
      settings: storageLayer.settings,
      storage: storageLayer.storage,
      chatProvider: chatProvider,
      ocr: services.ocr,
      agentProvider: agentProvider,
    );
  }

  // ── 阶段 1：基础设施 ──

  /// 阶段 1：基础设施（绑定引擎、日志、错误兜底、Hive）
  ///
  /// 为什么单独成阶段：这些是所有后续阶段的底层依赖，必须最先就绪。
  /// Hive 失败不阻断（由后续阶段的 init 重试兜底），保持原行为。
  Future<void> initCore() async {
    WidgetsFlutterBinding.ensureInitialized();

    AppLogger.init();
    AppLogger.i('应用启动...');

    FlutterError.onError = (details) {
      _debug.error('Flutter', '${details.exception}');
      _debug.error('Flutter', '${details.stack}');
    };

    try {
      _debug.info('Init', '开始初始化 Hive...');
      await Hive.initFlutter();
      _debug.info('Init', 'Hive 初始化成功');
    } catch (e) {
      _debug.error('Init', 'Hive 初始化失败: $e');
    }
  }

  // ── 阶段 2：存储层 ──

  /// 阶段 2：存储层（Settings + Storage + 旧数据迁移）
  ///
  /// 为什么 Settings 先于 Storage：StorageService.init 需要 customPath 和
  /// serviceId，二者都从 SettingsService 读取。这是原瀑布流最关键的顺序依赖之一，
  /// 现在通过方法内部顺序显式表达：先建 Settings，再用它建 Storage。
  Future<({SettingsService settings, StorageService storage})>
  initStorageLayer() async {
    final settingsService = SettingsService();
    final storageService = StorageService();

    final settingsOk = await settingsService.init();
    _debug.info('Init', 'SettingsService 初始化: ${settingsOk ? "成功" : "失败"}');

    final customPath = settingsService.getCustomStoragePath();
    _debug.info('Init', '自定义存储路径设置: ${customPath ?? "无（使用默认）"}');

    final serviceId = settingsService.getAiServiceId();
    _debug.info('Init', '从设置读取到的 AI 服务 ID: $serviceId');

    final storageOk = await storageService.init(
      customPath: customPath,
      serviceId: serviceId,
    );
    _debug.info('Init', 'StorageService 初始化: ${storageOk ? "成功" : "失败"}');
    _debug.info('Init', 'StorageService 实际使用路径: ${storageService.rootPath}');

    if (customPath != null &&
        customPath.isNotEmpty &&
        storageService.rootPath != customPath) {
      _debug.warn(
        'Init',
        '自定义路径 $customPath 不可用，已回退到: ${storageService.rootPath}',
      );
      await settingsService.setCustomStoragePath(null);
      _debug.info('Init', '已清除无效的自定义路径设置');
    }

    if (storageOk) {
      storageService.migrateLegacyData();
    }

    return (settings: settingsService, storage: storageService);
  }

  // ── 阶段 3：服务层 ──

  /// 阶段 3：服务层（搜索、记忆双轨、完整性检查、OCR、env）
  ///
  /// 为什么需要 settings：OCR 配置依赖 settingsService.loadOcrKeys() +
  /// 一系列 Getter。这是原瀑布流另一个顺序敏感点（注释明确"getter 才能
  /// 同步读到值"），现在通过参数显式表达：本方法只接收已就绪的 settings。
  Future<
    ({
      SearchService search,
      MemUService memu,
      MemLocalService memLocal,
      OcrServiceManager ocr,
    })
  >
  initServices(SettingsService settings) async {
    try {
      await AiServiceFactory.loadEnv();
      _debug.info('Init', '.env 加载成功');
    } catch (e) {
      _debug.warn('Init', '.env 加载失败: $e');
    }

    final searchService = SearchService();
    final memuService = MemUService();

    // 绑定 SettingsService 到记忆语义评分器
    // 为什么这样做：让 MemorySemanticScorer 在每次 score() 前从 settings
    // 读取用户配置的 scorer 服务商/模型/API Key，避免硬编码豆包；
    // 必须在 memuService.init() 之前调用，确保首次评分时配置已就绪
    MemorySemanticScorer.instance.attachSettings(settings);

    final memuOk = await memuService.init();
    _debug.info('Init', 'MemU 服务初始化: ${memuOk ? "成功" : "失败"}');

    final memLocalService = MemLocalService();
    final memLocalOk = await memLocalService.init();
    _debug.info('Init', 'MemLocal 服务初始化: ${memLocalOk ? "成功" : "失败"}');

    HiveIntegrityChecker.instance.configure(
      interval: const Duration(minutes: 30),
    );
    HiveIntegrityChecker.instance.startPeriodicCheck();
    _debug.info('Init', 'Hive 完整性检查已启动 (30分钟间隔)');

    final ocrServiceManager = OcrServiceManager();
    await ocrServiceManager.init();
    // 先把 OCR 密钥从安全存储加载到缓存（含从 Hive 的一次性迁移），
    // getter 才能同步读到值
    await settings.loadOcrKeys();
    ocrServiceManager.configure(
      localEnabled: settings.isOcrLocalEnabled(),
      cloudEnabled: settings.isOcrCloudEnabled(),
      autoOcr: settings.isOcrAutoEnabled(),
      cloudEngine: OcrEngine.values.firstWhere(
        (e) => e.id == settings.getOcrCloudEngine(),
        orElse: () => OcrEngine.baidu,
      ),
      baiduApiKey: settings.getOcrBaiduApiKey(),
      baiduSecretKey: settings.getOcrBaiduSecretKey(),
      tencentSecretId: settings.getOcrTencentSecretId(),
      tencentSecretKey: settings.getOcrTencentSecretKey(),
      aliyunAppCode: settings.getOcrAliyunAppCode(),
    );
    _debug.info('Init', 'OCR 服务初始化完成');

    return (
      search: searchService,
      memu: memuService,
      memLocal: memLocalService,
      ocr: ocrServiceManager,
    );
  }

  // ── 阶段 4：ChatProvider ──

  /// 阶段 4：ChatProvider 创建（含降级回退）
  ///
  /// 为什么单独成阶段：ChatProvider 依赖前面所有服务，且创建失败有降级
  /// 回退（DeepSeek 空 Key）。把这段逻辑独立出来，降级路径更清晰，
  /// 也便于后续拆分 ChatProvider 时定位初始化入口。
  Future<ChatProvider> initChatProvider({
    required SettingsService settings,
    required StorageService storage,
    required SearchService search,
    required MemUService memu,
    required MemLocalService memLocal,
  }) async {
    try {
      final serviceId = settings.getAiServiceId();
      _debug.info('Init', '创建 Provider 前读取的 AI 服务 ID: $serviceId');

      String? apiKey = await settings.loadApiKeyForService(serviceId);
      if (apiKey == null || apiKey.isEmpty) {
        apiKey = AiServiceFactory.getApiKeyFromEnv(serviceId);
      }
      _debug.info(
        'Init',
        'AI服务: $serviceId, API Key: ${apiKey != null && apiKey.isNotEmpty ? "已配置" : "未配置"}',
      );

      final aiService = AiServiceFactory.createService(
        serviceId,
        apiKey: apiKey ?? '',
      );

      _debug.info(
        'Init',
        '创建的 AI 服务实例: ${aiService.serviceId} (${aiService.serviceName})',
      );

      final chatProvider = ChatProvider(
        storageService: storage,
        settingsService: settings,
        searchService: search,
        memuService: memu,
        memLocalService: memLocal,
        initialAiService: aiService,
      );
      await chatProvider.init();

      _debug.info('Init', 'ChatProvider 创建并初始化成功');
      return chatProvider;
    } catch (e) {
      _debug.error('Init', '创建 ChatProvider 失败: $e，使用 DeepSeek 回退');
      final fallback = AiServiceFactory.createService('deepseek', apiKey: '');

      final chatProvider = ChatProvider(
        storageService: storage,
        settingsService: settings,
        searchService: search,
        memuService: memu,
        memLocalService: memLocal,
        initialAiService: fallback,
      );
      await chatProvider.init();
      return chatProvider;
    }
  }

  // ── 阶段 5：TTS 预热 ──

  /// TTS 预热（异步，不阻塞启动）
  ///
  /// 为什么独立方法：TTS 预热是"尽力而为"的可选初始化，失败不影响应用
  /// 启动。独立出来便于阅读，也明确它不返回任何后续需要的依赖。
  void _warmUpTts(SettingsService settings) {
    // 启动 NCNN TTS 事件监听
    NcnnTtsService.instance.startEventListener();
    // 若用户已启用 TTS，预初始化引擎（异步，不阻塞启动）
    if (settings.isTtsEnabled()) {
      NcnnTtsService.instance.ensureInitialized(settings).then((ok) {
        _debug.info('Init', 'NCNN TTS 预初始化: ${ok ? "成功" : "失败（模型可能未配置）"}');
      });
    }
  }

  // ── 阶段 6：Agent ──

  /// 阶段 6：Agent 功能初始化
  ///
  /// 为什么单独成阶段：Agent 是独立功能域，依赖 AiServiceFactory（阶段 3 就绪），
  /// 不依赖 ChatProvider。独立初始化便于：
  /// 1. 非 Android 平台优雅降级（bridge.isSupported 返回 false）
  /// 2. Agent 故障不影响主聊天功能
  /// 3. 未来扩展（如桌面端 Agent）有明确入口
  ///
  /// 为什么同步初始化：AgentProvider 构造轻量（仅创建对象），
  /// 真正的权限检查、事件订阅、安全配置恢复在 AgentScreen 首次显示时延迟进行。
  /// 为什么不在启动时调用 init：init 中的 refreshPermissionStatus 调用
  /// MethodChannel，在启动阶段可能抛异常阻断整个 App 启动流程。
  AgentProvider initAgent() {
    final bridge = AccessibilityBridge.instance;
    final guard = AgentSafetyGuard();
    final logger = AgentOperationLogger(guard);
    final tools = AgentToolRegistry(bridge);

    final provider = AgentProvider(
      bridge: bridge,
      tools: tools,
      guard: guard,
      logger: logger,
    );

    _debug.info(
      'Init',
      'Agent 初始化完成 (平台支持: ${bridge.isSupported ? "Android" : "非 Android，已降级"})',
    );
    return provider;
  }
}

/// 启动结果：runApp 所需的全部依赖
///
/// 为什么用 class 而非 record：字段固定且语义明确，class 提供更好的
/// 命名构造与文档提示，调用方解构更清晰。
class BootstrapResult {
  const BootstrapResult({
    required this.settings,
    required this.storage,
    required this.chatProvider,
    required this.ocr,
    required this.agentProvider,
  });

  final SettingsService settings;
  final StorageService storage;
  final ChatProvider chatProvider;
  final OcrServiceManager ocr;
  final AgentProvider agentProvider;
}
