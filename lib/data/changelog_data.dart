// 开源版：原 import '../theme/app_icon_themes.dart' 改为指向本库内的精简版 AppIcons。
// 为什么这样做：开源后端库不包含 lib/theme/（依赖 Flutter Material 的 IconData），
// 改用本库 lib/core/constants/app_icons.dart 中纯字符串常量版本，零 Flutter UI 依赖。
import '../core/constants/app_icons.dart';

class ChangelogSection {
  final String title;
  final String icon;
  final List<String> items;

  const ChangelogSection({
    required this.title,
    required this.icon,
    required this.items,
  });
}

class ChangelogEntry {
  final String version;
  final String date;
  final List<ChangelogSection> professionalSections;
  final List<ChangelogSection> normalSections;
  final List<String> tags;

  const ChangelogEntry({
    required this.version,
    required this.date,
    required this.professionalSections,
    required this.normalSections,
    required this.tags,
  });

  List<ChangelogSection> sectionsForMode(bool isProfessional) {
    return isProfessional ? professionalSections : normalSections;
  }

  bool matchesQuery(String query) {
    final q = query.toLowerCase();
    if (version.toLowerCase().contains(q)) return true;
    if (date.contains(q)) return true;
    if (tags.any((t) => t.toLowerCase().contains(q))) return true;
    for (final s in professionalSections) {
      if (s.title.toLowerCase().contains(q)) return true;
      if (s.items.any((i) => i.toLowerCase().contains(q))) return true;
    }
    for (final s in normalSections) {
      if (s.title.toLowerCase().contains(q)) return true;
      if (s.items.any((i) => i.toLowerCase().contains(q))) return true;
    }
    return false;
  }

  String get fullSearchableText {
    final buffer = StringBuffer();
    buffer.writeln(version);
    buffer.writeln(date);
    buffer.writeAll(tags, ' ');
    for (final s in professionalSections) {
      buffer.writeln(s.title);
      buffer.writeAll(s.items, ' ');
    }
    for (final s in normalSections) {
      buffer.writeln(s.title);
      buffer.writeAll(s.items, ' ');
    }
    return buffer.toString();
  }
}

const List<ChangelogEntry> changelogHistory = [
  // 做什么：批次 4 后端开源准备记录（T6：services/ 目录按子域建子目录）。
  // 为什么放最前：changelogHistory 按时间倒序排列（最新在最前），1.909 > 1.908。
  ChangelogEntry(
    version: '1.909',
    date: '2026-06-27 02:30:00',
    professionalSections: [
      ChangelogSection(
        title: '后端开源准备 · 批次 4：services/ 目录按子域建子目录（小批次重构）',
        icon: AppIcons.autoFixHigh,
        items: [
          '修改文件：lib/services/vision/ocr_service.dart（从 services/ 根目录移入，1 文件）、lib/services/search/search_service.dart（从 services/ 根目录移入，1 文件）、lib/services/common/debug_mode_service.dart、lib/services/common/dev_mode_service.dart、lib/services/common/input_sanitizer.dart、lib/services/common/url_validator.dart、lib/services/common/performance_monitor.dart、lib/services/common/device_info.dart（6 个文件从 services/ 根目录移入）；56 个引用方修改 import 语句（lib/core/app_bootstrap.dart、lib/providers/chat_provider.dart、lib/providers/search_provider.dart、lib/providers/memory_provider.dart、lib/providers/chat_send_orchestrator.dart、lib/screens/ 下 42 个文件、test/ 下 5 个文件）；2 个文件修复同目录引用（lib/services/ai_service.dart 的 input_sanitizer、lib/services/speech_recognition_service.dart 的 device_info）；lib/providers/conversation_provider.dart（修复 invalid_return_type_for_catch_error warning）、lib/screens/widgets/input_area/model_selector_sheet.dart（删除未使用字段 aiDir）、lib/services/ncnn_tts_service.dart（删除未使用字段 _modelDir 及赋值）；BACKEND_OVERVIEW.md（更新目录树 + 项目数据总览 + 第九章新增批次 4 复查记录）',
          '具体改动：1) T6 拆分小批次重构（用户决策推荐方案）：本轮只移动 3 个低风险子域，vision/（视觉子域，1 文件）+ search/（搜索子域，1 文件）+ common/（通用工具子域，6 文件），共 8 个文件。services/ 根目录从 53 个文件降到 45 个，新增 3 个子目录；2) 引用方修改策略：vision/ 8 处 + search/ 6 处用 Edit 工具逐个修改，common/ 56 处用 PowerShell 正则批量替换（精确匹配 import 语句，不影响 changelog_data.dart 中的历史标签字符串字面量）；3) 文件内部相对 import 修改：search_service.dart 1 处（../core/ → ../../core/）+ common/ 5 个文件（debug_mode/dev_mode/input_sanitizer/url_validator/performance_monitor 各 1 处 ../core/ 或 ../screens/ → ../../core/ 或 ../../screens/，device_info 无内部依赖）；4) 修复 2 处同目录引用遗漏（ai_service.dart 的 import "input_sanitizer.dart" 和 speech_recognition_service.dart 的 import "device_info.dart"，PowerShell 正则未匹配因路径中无 services/ 前缀）；5) 备份策略：执行前用 PowerShell Copy-Item 备份 lib/services/ 到 .backup/services_20260627_022012/（67 个文件快照），git 未跟踪 lib/ 无版本保护；6) 修复 3 个跨批次遗留 warning：conversation_provider:62 invalid_return_type_for_catch_error 改用 async IIFE + try-catch 避免 catchError 类型陷阱（catchError 的 onError 签名要求返回 bool 与 Future<void> 不匹配）；model_selector_sheet:54 删除未使用字段 aiDir；ncnn_tts_service:48 删除未使用字段 _modelDir 及 L124 赋值（L127 直接用局部变量 dir，_modelDir 从未读取）',
          '影响范围：services/ 文件数不变（67 个），仅重新组织（根目录 53→45 + 新增 vision/1 + search/1 + common/6）；lib/ 总文件数不变（164 个）；dart analyze lib 0 error，0 warning（3 warning 已修复，原 13 issues 降到 10 issues 全 info 级）；flutter test test/unit/ 498 passed 全部通过无回归；遗留 services/ 根目录仍有 45 个文件平铺（AI 适配层 21 + 存储 7 + 记忆 8 + 语音 4 + TTS 1 + Token/聊天 3 + Facade 1），后续可继续按 ai/memory/storage/speech 子域拆分（高风险，需单独批次）',
        ],
      ),
    ],
    normalSections: [
      ChangelogSection(
        title: '后端代码整理第 4 批：服务文件夹分类整理',
        icon: AppIcons.autoFixHigh,
        items: [
          '修改文件：8 个服务文件移动到新建的 3 个子文件夹（视觉/搜索/通用工具），56 个引用文件更新导入路径',
          '具体改动：把原来混在服务文件夹根目录的 8 个文件按功能分类：OCR 识别放到"视觉"子文件夹，联网搜索放到"搜索"子文件夹，调试/开发者模式/输入消毒/URL 校验/性能监控/设备信息 6 个通用工具放到"通用工具"子文件夹。这样服务文件夹结构更清晰，每个子文件夹只放同类的文件',
          '影响范围：代码结构更清晰，方便开源后社区贡献者理解；用户使用无任何变化（所有功能照常工作）',
        ],
      ),
    ],
    tags: [
      '后端开源准备',
      '批次4',
      'T6',
      'services重构',
      '目录重组',
      'vision子域',
      'search子域',
      'common子域',
      '小批次重构',
      'PowerShell批量替换',
      'dart_analyze',
      '0error',
      'flutter_test',
      '498passed',
    ],
  ),
  // 做什么：批次 3 后端开源准备记录（T4+T5：God Class 系统性拆分）。
  // 为什么放最前：changelogHistory 按时间倒序排列（最新在最前），1.908 > 1.907。
  ChangelogEntry(
    version: '1.908',
    date: '2026-06-27 18:00:00',
    professionalSections: [
      ChangelogSection(
        title: '后端开源准备 · 批次 3：SettingsService + ChatProvider God Class 系统性拆分',
        icon: AppIcons.autoFixHigh,
        items: [
          '修改文件：lib/services/settings/ai_settings_repository.dart（新建，~420 行，API Key/模型/参数/自定义模型/语义评分）、lib/services/settings/search_settings_repository.dart（新建，~180 行，联网搜索配置）、lib/services/settings/appearance_settings_repository.dart（新建，~350 行，头像/壁纸/动画/主题/字体/气泡/OCR 开关）、lib/services/settings/speech_settings_repository.dart（新建，~60 行，云端语音/STT 模式）、lib/services/settings/tts_settings_repository.dart（新建，~90 行，NCNN TTS 7 个配置项）、lib/services/settings/agent_settings_repository.dart（新建，~110 行，Agent 视觉/黑白名单/银行保护/知情同意）、lib/services/settings/changelog_settings_repository.dart（新建，~70 行，更新日志显示模式）、lib/services/settings_service.dart（重写为 Facade，1700+→772 行）、lib/providers/conversation_loader.dart（新建，282 行，启动加载/切换加载/分页加载更多）、lib/providers/ai_service_switcher.dart（新建，256 行，切换服务商+加载会话+应用高级参数）、lib/providers/chat_provider.dart（重写为 Facade，685→403 行）；BACKEND_OVERVIEW.md（更新 4.4/4.11 节 + 设计亮点 + 项目数据总览 + 第九章新增批次 3 复查记录）',
          '具体改动：1) T4 SettingsService God Class 完整拆分：原 1700+ 行 God Class 抽出 7 个 Repository（+阶段 1 的 OcrSettingsRepository 共 8 个），SettingsService 保留 static const 默认值（外部 UI 通过 SettingsService.xxx 访问）+ 基础设施方法（init/_safeWrite/_safeRead/close）+ 会话状态方法 + 8 个 Repository 实例初始化 + Facade 转发；CustomModelConfig 从 settings_service.dart 迁移到 ai_settings_repository.dart 并通过 export 语句重新导出保持向后兼容；依赖注入采用回调模式（boxGetter/safeWrite/safeRead/notifyListeners），Box 在 init() 后才可用，回调保证每次访问最新值；2) T5 ChatProvider 继续拆分：原计划抽出的 _buildAiMessages/_injectSearchContext 早已在 P2 #14 移到 ChatSendOrchestrator，重新评估后抽出 ConversationLoader（会话加载/切换/分页，_hasMoreMessages/_loadedMessageCount/_isLoadingMoreMessages 移到本类内部管理）+ AiServiceSwitcher（AI 服务切换/加载/参数）；共享状态 _messages/_currentAiService 留 ChatProvider，3 个 helper 通过回调读写；初始化顺序 _conversationLoader → _sendOrchestrator → _aiSwitcher 避免 tear-off LateInitializationError',
          '影响范围：SettingsService 从 1700+ 行降到 772 行（-55%），ChatProvider 从 685 行降到 403 行（-41%），lib/ 总行数从 45796 降到 45430（-366，拆分时移除重复代码和冗余注释）；新增 9 个文件（7 Repository + 2 helper）；调用方零改动（Facade 转发保持 API 兼容）；dart analyze lib 0 error，3 warning 全部是既有问题（conversation_provider invalid_return_type / model_selector_sheet aiDir / ncnn_tts_service _modelDir）',
        ],
      ),
    ],
    normalSections: [
      ChangelogSection(
        title: '后端代码整理第 3 批：拆分两个超大文件，让代码更清晰',
        icon: AppIcons.autoFixHigh,
        items: [
          '修改文件：设置服务（拆成 8 个小模块）、聊天核心（拆出 2 个助手模块）、后端架构文档',
          '具体改动：1) 设置服务原来是一个 1700 多行的超大文件，所有设置项都堆在一起，现在按功能拆成 8 个小模块（AI 设置/搜索设置/外观设置/语音设置/TTS 设置/Agent 设置/更新日志设置/OCR 密钥），每个模块只管自己的设置项，主文件只负责转发，调用方代码不用改；2) 聊天核心原来 685 行，把"会话加载"和"AI 服务切换"两个独立功能拆成单独模块，主文件降到 403 行；3) 拆分时修复了初始化顺序问题（避免引用未初始化的变量报错）',
          '影响范围：代码更易维护、更易测试、新人更容易理解；用户使用无任何变化（所有功能照常工作）',
        ],
      ),
    ],
    tags: [
      '后端开源准备',
      '批次3',
      'T4',
      'T5',
      'SettingsService拆分',
      'ChatProvider拆分',
      'Facade模式',
      '8个Repository',
      'ConversationLoader',
      'AiServiceSwitcher',
      'GodClass拆分',
      '回调注入',
      'dart_analyze',
      '0error',
    ],
  ),
  // 做什么：批次 2 后端开源准备记录（T8+T9）。
  // 为什么放最前：changelogHistory 按时间倒序排列（最新在最前），1.907 > 1.906。
  ChangelogEntry(
    version: '1.907',
    date: '2026-06-27 16:00:00',
    professionalSections: [
      ChangelogSection(
        title: '后端开源准备 · 批次 2：记忆语义评分可配置化 + 调试服务合并',
        icon: AppIcons.autoFixHigh,
        items: [
          '修改文件：lib/services/settings_service.dart（新增 memoryScorerServiceId/Model 配置项）、lib/services/memory_semantic_scorer.dart（重构：attachSettings + 每次评分前从 settings 刷新配置）、lib/core/app_bootstrap.dart（initServices 阶段调用 attachSettings）、lib/screens/memory_dashboard_screen.dart（总览 Tab 顶部新增"语义评分配置"卡片：显示当前服务+一键复用当前聊天 AI+手动选择 12 家服务商）、lib/services/debug_mode_service.dart（合并 DebugService 的 log/info/warn/error/exportLogsToFile/getDiagnosticSummary/clear 等功能，DebugLogEntry 新增 level 字段，添加 logAlways 无条件记录方法）、lib/services/debug_service.dart（已删除，合并到 debug_mode_service.dart）；BACKEND_OVERVIEW.md（更新 4.38 节合并说明 + services/ 61→60 + lib/ 156→155 + 行数 45522→45796 + 调试服务 3→2 + 调试日志上限统一 1000 + 修正 T3 遗留的 settings/ 13→17、widgets/ 20+→25 + 第九章新增 2026-06-27 复查记录）',
          '具体改动：1) T8 记忆语义评分可配置化：原 MemorySemanticScorer 硬编码豆包 API 且 configure() 全代码库无人调用，导致 isConfigured 永远为 false 永远走正则 fallback；新增 SettingsService.getMemoryScorerServiceId/setMemoryScorerServiceId/getMemoryScorerModel/setMemoryScorerModel 4 个方法（含 _memoryScorerServiceIdKey/_memoryScorerModelKey 2 个常量键，默认值 doubao 兼容历史）；MemorySemanticScorer 新增 attachSettings(settings) 注入方法 + _refreshConfigFromSettings() 在每次 score() 前异步刷新配置（优先从缓存读 API Key，缓存为空回退 secure storage）；app_bootstrap.dart 在 MemUService.init() 之前调用 attachSettings 确保首次评分配置就绪；memory_dashboard_screen 总览 Tab 顶部新增 _buildScorerConfigCard 卡片（ListTile 显示当前服务+一键复用当前聊天 AI 按钮+手动选择服务商入口），_showScorerServicePicker 底部弹窗列出 12 家内置服务商（用 ListTile+选中图标替代已废弃的 RadioListTile）；2) T9 调试服务合并：原 DebugService（启动日志 500 条缓冲）与 DebugModeService（调试日志 1000 条）职责重叠，合并到 DebugModeService；DebugLogEntry 新增 level 字段（INFO/WARN/ERROR），format() 输出 [time][level][category] message；新增 logAlways(category, message, level) 无条件记录方法（不检查 _disposed 和 _enabled，崩溃日志必须保留）+ info/warn/error 三个便捷方法 + logCount/allLogs 兼容 getter + exportLogsToFile() 导出到 logs/debug_<timestamp>.log + getDiagnosticSummary() 诊断摘要 + clear() 别名；原 log() 方法仍受 enabled 控制（开发者主动记录的调试日志）；app_bootstrap.dart 改 import 为 debug_mode_service.dart，_debug 字段类型改为 DebugModeService.instance；删除 debug_service.dart 文件',
          '影响范围：T8 让记忆语义评分不再强依赖豆包，用户配置任意 AI 服务商（含 OpenAI/DeepSeek/通义等 12 家）均可复用做语义评分，未配置时仍正确 fallback 到正则；T9 消除调试服务职责重叠，统一日志入口，DebugModeService 同时承担启动日志（无条件）和调试日志（受控），减少 1 个文件 1 个单例。dart analyze lib 0 error（13 info 全是既有问题），flutter test test/unit/ 498 passed 无回归',
        ],
      ),
    ],
    normalSections: [
      ChangelogSection(
        title: '后端代码整理第 2 批：记忆评分不再强依赖豆包 + 合并重复的调试服务',
        icon: AppIcons.autoFixHigh,
        items: [
          '修改文件：设置服务、记忆评分器、启动流程、记忆仪表板、调试服务（已合并）、后端架构文档',
          '具体改动：1) 修复记忆语义评分永远走正则 fallback 的问题——原代码硬编码豆包 API 但从没调用配置方法，导致即使用户配了其他 AI 服务商也无法用 LLM 做语义评分；现在可在记忆仪表板顶部选择任意已配置的 AI 服务商做评分服务，支持"一键复用当前聊天 AI"或手动选择 12 家内置服务商；2) 合并重复的调试服务——原 DebugService（启动日志）和 DebugModeService（调试日志）职责重叠，合并为一个 DebugModeService，启动日志无条件记录（崩溃日志必须保留），调试日志受开关控制，删除了原 DebugService 文件',
          '影响范围：记忆评分更智能（可复用任意 AI 服务商）、调试系统更清晰（一个服务统一管理）',
        ],
      ),
    ],
    tags: [
      '后端开源准备',
      '批次2',
      'T8',
      'T9',
      '记忆语义评分',
      '可配置化',
      'MemorySemanticScorer',
      'attachSettings',
      'DebugService合并',
      'DebugModeService',
      'logAlways',
      '启动日志',
      '调试日志',
      'dart_analyze',
      'flutter_test',
      '498用例',
    ],
  ),
  ChangelogEntry(
    version: '1.906',
    date: '2026-06-26 16:00:00',
    professionalSections: [
      ChangelogSection(
        title: '后端开源准备 · 批次 1：文档严谨性 + 代码可维护性 + Agent 配置门槛降低',
        icon: AppIcons.autoFixHigh,
        items: [
          '修改文件：BACKEND_OVERVIEW.md、BACKEND_OPEN_SOURCE_RELAY_2026-06-26.md、lib/services/storage_service.dart、lib/screens/settings/agent_settings_page.dart、lib/data/changelog_data.dart；删除 lib/screens/dashboard/、lib/screens/profile/、lib/screens/shared/（3 个空目录）',
          '具体改动：1) T1 修正 BACKEND_OVERVIEW.md 8 处数字错误（lib/ 157→156、1636.9KB→45522行、services/ 54→61、screens/ 36→61），新增第九章"复查记录"说明 LS 工具不可靠问题；2) T2 经用户确认删除 lib/screens/ 下 dashboard/profile/shared 3 个空目录（实测 Get-ChildItem Count=0）；3) T3 补全 BACKEND_OVERVIEW.md 第 4.26 节 screens/ 完整 61 文件清单（顶层 11 + agent 1 + controllers 4 + coordinators 1 + handlers 1 + managers 1 + settings 17 + widgets 25[顶层 15 + input_area/ 10]）；4) T7 给 storage_service.dart 三个同步 IO 方法标注 @Deprecated（getConversations L374、getMessages L806、saveMessagesSync L858），注解文案"使用 getXXXAsync 替代，避免阻塞 UI 线程"，IDE 自动显示删除线；5) T10 在 agent_settings_page.dart 新增"视觉模型"配置卡片（SwitchListTile 开关 + "使用当前聊天 AI" 快捷按钮），调用 SettingsService 的 isAgentVisionEnabled/setAgentVisionServiceId/setAgentVisionModel 等方法，一键复用当前 AI 服务+模型作为 Agent 视觉 fallback',
          '影响范围：开源文档数字全部与实测一致（dart analyze lib 0 error，flutter analyze 无新增 warning）；3 个空目录清理提升代码库整洁度；@Deprecated 警示后续迁移到 async API；Agent VLM 配置从需手填服务ID+模型名两步降为一键复用，配置门槛显著降低',
        ],
      ),
    ],
    normalSections: [
      ChangelogSection(
        title: '后端代码整理第 1 批：修复文档错误 + 清理空目录 + 完善 Agent 配置',
        icon: AppIcons.autoFixHigh,
        items: [
          '修改文件：后端架构介绍文档、接力任务文档、存储服务、Agent 设置页、更新日志；清理 3 个空文件夹',
          '具体改动：1) 修正后端架构介绍里 8 处数字错误（文件数、规模单位从 KB 改成行数），并加了"复查记录"说明；2) 经你同意删除了 screens 下 3 个空文件夹（dashboard/profile/shared，原本 LS 工具误显示有文件但实际是空的）；3) 补全了 screens 下完整 61 个文件清单；4) 给存储服务里 3 个旧的同步读取方法加了"已废弃"标记，IDE 会自动画删除线提醒迁移到异步版本；5) Agent 视觉模型配置加了"使用当前聊天 AI"快捷按钮——以前要手动填服务 ID 和模型名两步，现在一键复用',
          '影响范围：后端开源文档更严谨；代码库更整洁；Agent 视觉 fallback 配置从手动两步变一键',
        ],
      ),
    ],
    tags: [
      '后端开源准备',
      '批次1',
      '文档修正',
      'BACKEND_OVERVIEW',
      '空目录清理',
      '@Deprecated',
      '同步IO',
      'AgentVLM',
      '视觉模型',
      '一键配置',
      'dart_analyze',
      'flutter_test',
    ],
  ),
  ChangelogEntry(
    version: '1.905',
    date: '2026-06-20 20:00:00',
    professionalSections: [
      ChangelogSection(
        title: '去除初次启动引导界面',
        icon: AppIcons.rocketLaunch,
        items: [
          '修改文件：lib/main.dart、lib/services/settings_service.dart、lib/screens/onboarding_screen.dart（已删除）',
          '具体改动：1) main.dart 移除 OnboardingScreen 判断（if (!settingsService.isOnboardingComplete()) return OnboardingScreen()）和 import 导入，App 启动初始化完成后直接进入 ChatScreen；2) settings_service.dart 移除 _onboardingCompleteKey 常量、isOnboardingComplete() 方法、setOnboardingComplete() 方法；3) 删除 onboarding_screen.dart 文件（7 页功能介绍引导界面，纯展示无初始化逻辑）',
          '影响范围：App 首次启动不再显示引导界面，直接进入聊天页。dart analyze 0 error',
        ],
      ),
    ],
    normalSections: [
      ChangelogSection(
        title: '去除了首次打开 App 时的引导界面',
        icon: AppIcons.rocketLaunch,
        items: [
          '修改文件：启动流程、设置服务、引导界面文件（已删除）',
          '具体改动：去除了首次打开 App 时显示的功能介绍引导页面（之前会展示"欢迎使用杏铃"、AI服务、记忆、OCR、搜索、个性化、开始体验等 7 页介绍），现在打开 App 直接进入聊天界面',
          '影响范围：首次使用体验更简洁，不再需要滑过引导页',
        ],
      ),
    ],
    tags: [
      '引导界面',
      'OnboardingScreen',
      '初次启动',
      'main.dart',
      'settings_service',
      '删除文件',
    ],
  ),
  ChangelogEntry(
    version: '1.904',
    date: '2026-06-20 20:30:00',
    professionalSections: [
      ChangelogSection(
        title: 'Agent Phase 7 收尾：12 项遗留问题修复 + 文档完善',
        icon: AppIcons.smartToyOutlined,
        items: [
          '修改文件：lib/providers/agent_provider.dart、lib/core/app_bootstrap.dart、lib/screens/agent/agent_screen.dart、lib/screens/coordinators/chat_input_coordinator.dart、lib/screens/settings/agent_settings_page.dart、lib/services/agent/agent_operation_logger.dart、lib/models/agent/agent_event.dart、lib/providers/chat_provider.dart、android/app/src/main/kotlin/com/xingling/chat/agent/AgentForegroundService.kt、android/app/src/main/kotlin/com/xingling/chat/agent/AgentEventSink.kt、android/app/src/main/kotlin/com/xingling/chat/agent/XinglingAgentAccessibilityService.kt、test/unit/agent_tool_registry_test.dart（新增）、PROJECT_AI_GUIDE.md、ANDROID_AGENT_PROPOSAL.md',
          '具体改动：1) T1+T5 安全配置恢复+日志清理：AgentProvider.init() 签名改为接收 SettingsService，在 init 中调用 guard.loadFromSettings(settings) 恢复黑白名单/银行保护开关，调用 logger.cleanupExpired() 清理 30 天前日志；initAgent() 改为异步并在 App 启动时调用 init(settings)，移除 agent_screen.dart 重复的 init() 调用；2) T2 通知栏紧急停止联动：Kotlin ACTION_EMERGENCY_STOP 单独处理调用 AgentEventSink.emitEmergencyStop()，新增 emitEmergencyStop() 方法；Dart agent_event.dart 新增 emergencyStop 事件类型和 EmergencyStopEvent 类，_handleEvent 收到后调用 emergencyStop() 停止 AI 操控循环；3) T3 Agent 结果改用 addAssistantMessage：ChatProvider 新增 addAssistantMessage 方法直接插入 role=assistant 消息并持久化（不触发 AI 回复），ChatInputCoordinator._navigateToAgent 改用 addAssistantMessage 替代 sendMessage；4) T4 stopped 状态可回填：isFinished 加入 AgentTaskState.stopped，_returnResultToChat 改用 switch 处理 done/error/stopped 三种状态；5) T6 截图 hardwareBuffer 修复：takeScreenshot onSuccess 用 finally 块确保 hardwareBuffer.close()，新增 android.hardware.HardwareBuffer import；6) T7 知情同意重置：AgentSettingsPage _buildAboutCard 新增"重新查看功能须知"按钮，_showResetConsentDialog 调用 setAgentConsentAccepted(false)；7) T8 清空/删除日志：OperationLogger 新增 clearAll() 和 deleteTask(taskId) 方法，AgentLogListPage AppBar 新增"清空全部"按钮+_showClearAllDialog，_LogListTile 用 Dismissible 包裹支持滑动删除单个任务（含二次确认）；8) T9 进度指示：AgentProvider 新增 maxSteps getter 透传 _service.config.maxSteps，_buildStepsList 任务运行中时顶部显示"执行中 · 第 N 步 / 30"进度条；9) T10 文档：PROJECT_AI_GUIDE.md 新增第 17 章 Agent 功能（架构循环/Dart+原生文件位置/安全机制/配置项/测试文件/初始化流程）；10) T11 单元测试：新增 agent_tool_registry_test.dart 19 用例（toFunctionDefinitions 格式/终止动作处理/参数缺失校验），全部通过；11) T12 决策点确认：用户逐个确认 D2=30步/D3=系统设置+安装器+银行类/D5=30天/D6=不保存截图/D8=预留接口，更新 ANDROID_AGENT_PROPOSAL.md 第 11 章标记为已确认',
          '影响范围：Agent 安全配置在 App 重启后正确恢复（修复 P0 安全漏洞）；通知栏紧急停止真正生效（修复 P0）；Agent 结果不再被误识别为用户消息（修复 P0）；中途停止的任务结果可回填聊天；截图不再泄漏 native 资源；知情同意可重置；日志可清空/删除单条；任务执行有进度指示；文档完整；工具注册表有测试保障。dart analyze lib 0 error，flutter test 77/77 通过（原 58 + 新增 19）',
        ],
      ),
    ],
    normalSections: [
      ChangelogSection(
        title: 'Agent 修复多个重要问题，功能更安全更好用',
        icon: AppIcons.smartToyOutlined,
        items: [
          '修改文件：Agent 核心逻辑、通知栏、聊天回填、截图、设置页、日志管理、文档、测试',
          '具体改动：1) 修复安全配置丢失问题——以前重启 App 后 Agent 的黑白名单和银行保护开关会丢失，现在重启后自动恢复；2) 修复通知栏紧急停止无效问题——以前点通知栏"紧急停止"只消失通知，AI 还在后台操控手机，现在会真正停止 AI；3) 修复 Agent 结果显示错误——以前 Agent 任务结果发到聊天会显示成"你说的"并触发 AI 回复，现在正确显示为助手消息；4) 中途停止的任务现在也能把已执行的结果发到聊天；5) 修复截图内存泄漏——截图功能的系统资源现在会正确释放；6) 新增"重新查看功能须知"按钮——同意后想重新看须知可以重置；7) 日志管理增强——可以一键清空全部日志，也可以滑动删除单条任务日志；8) 任务执行时显示进度——能看到"执行中 · 第 N 步 / 30"；9) 完善了开发者文档；10) 新增 19 个工具注册表测试用例',
          '影响范围：Agent 更安全（配置不丢失、紧急停止有效）、更准确（结果正确显示）、更省内存（截图不泄漏）、更好用（日志可管理、有进度指示）',
        ],
      ),
    ],
    tags: [
      'Agent',
      'Phase7',
      '收尾修复',
      'SafetyGuard',
      'loadFromSettings',
      'cleanupExpired',
      '紧急停止',
      'emergencyStop',
      'addAssistantMessage',
      'stopped回填',
      'hardwareBuffer',
      '知情同意重置',
      '日志清空删除',
      '进度指示',
      'AgentToolRegistry测试',
      '文档完善',
      '决策点确认',
      'dart_analyze',
      'flutter_test',
      '77用例',
    ],
  ),
  ChangelogEntry(
    version: '1.904',
    date: '2026-06-20 19:20:00',
    professionalSections: [
      ChangelogSection(
        title: 'Agent Phase 7 单元测试 + Bug 修复',
        icon: AppIcons.smartToyOutlined,
        items: [
          '修改文件：test/unit/agent_safety_guard_test.dart（新增）、test/unit/agent_intent_detector_test.dart（新增）、test/unit/agent_operation_logger_test.dart（新增）、lib/services/agent/agent_operation_logger.dart、lib/services/agent/agent_safety_guard.dart、lib/screens/settings/agent_settings_page.dart',
          '具体改动：1) SafetyGuard 单元测试 30+ 用例：precheckGoal 风险分级（正常/支付/密码/删除/发送）、checkAction 各种动作（点击/输入/启动App/导航）、黑白名单管理（系统默认/银行保护/用户自定义/白名单限制）、输入文本脱敏、截图脱敏检查（null/密码框/屏幕异常）；2) IntentDetector 单元测试 19 用例：/agent @agent 显式命令（大小写/无目标/前缀文字）、关键词匹配（帮我打开+App名/自动操作/操控手机）、不应命中场景（空字符串/普通聊天/打开灯/自动播放）；3) OperationLogger 单元测试 9 用例：init 创建目录、logTaskStart+logTaskEnd 写入、logStep 记录、密码脱敏验证、readIndex 历史列表、readTaskLog 空列表、多任务索引排序；4) Bug 修复：readTaskLog 未调用 init() 导致 _logDir 为 null 时崩溃（添加 await init()）、_updateIndex 在 logTaskEnd 时用空 goal 覆盖原有目标（保留 existingGoal/existingCreatedAt）、银行黑名单在管理页可见但 removeBlacklist 无效（新增 displayableBlacklist 不含银行黑名单）、setState after await 缺 mounted 检查（添加 if(mounted)）',
          '影响范围：Agent 安全逻辑有测试保障（58 用例全通过）；修复 4 个潜在 bug（1 个崩溃 + 1 个数据丢失 + 1 个 UX 困惑 + 1 个 lint error）。dart analyze 0 error，flutter test 58/58 通过',
        ],
      ),
    ],
    normalSections: [
      ChangelogSection(
        title: 'Agent 安全测试 + 修复几个隐藏问题',
        icon: AppIcons.smartToyOutlined,
        items: [
          '修改文件：Agent 安全守卫测试、意图检测测试、操作日志测试、操作日志服务、安全守卫服务、Agent 设置页',
          '具体改动：1) 给 Agent 的安全核心功能写了 58 个测试用例，全部通过——包括风险分级（什么操作需要确认/拒绝）、黑白名单、密码脱敏、截图隐私检查、意图识别等；2) 修复了一个崩溃问题：查看不存在的任务日志时会崩溃，现在不会了；3) 修复了操作日志列表中任务目标显示为空的问题；4) 修复了银行黑名单 App 在管理页面显示删除按钮但删不掉的问题——银行黑名单现在由开关统一控制，不在列表中逐个管理',
          '影响范围：Agent 功能更稳定，安全逻辑有测试保障',
        ],
      ),
    ],
    tags: [
      'Agent',
      'Phase7',
      '单元测试',
      'SafetyGuard',
      'IntentDetector',
      'OperationLogger',
      'Bug修复',
      'readTaskLog',
      '_updateIndex',
      'displayableBlacklist',
      'mounted检查',
      'flutter_test',
      '58用例',
    ],
  ),
  ChangelogEntry(
    version: '1.903',
    date: '2026-06-20 18:30:00',
    professionalSections: [
      ChangelogSection(
        title: 'Agent Phase 4 收尾 + Phase 6 安全机制完善',
        icon: AppIcons.smartToyOutlined,
        items: [
          '修改文件：lib/screens/agent/agent_screen.dart、lib/screens/coordinators/chat_input_coordinator.dart、lib/screens/settings/agent_settings_page.dart（新增）、lib/screens/settings_dialog.dart、lib/services/settings_service.dart、lib/services/agent/agent_safety_guard.dart',
          '具体改动：1) Phase 4 任务结果回填聊天：AgentScreen 任务完成后 AppBar 显示"发送到聊天"按钮（仅从聊天跳转来时），点击 Navigator.pop 回传结果字符串，ChatInputCoordinator._navigateToAgent 改为 async + await push 接收返回值，自动调用 chatProvider.sendMessage 发送到聊天，无需手动复制；2) Phase 6 Agent 设置页（新增 agent_settings_page.dart）：权限管理（无障碍/通知监听状态+跳转授权）、安全配置（银行保护开关+App 黑白名单管理页，支持添加/移除包名，系统默认黑名单标记不可移除）、操作日志查看（历史任务列表→详情页，展示每步操作的思考/动作/结果）、开始任务入口、功能说明；3) 知情同意持久化：SettingsService 新增 agent_consent_accepted key + isAgentConsentAccepted/setAgentConsentAccepted 方法，AgentScreen 从持久化存储读取同意状态，同意后写入存储，重启不再重复弹框；4) SafetyGuard 新增公开 API：userWhitelist/userBlacklist 只读 getter、isDefaultBlocked 方法，供设置页区分系统默认和用户自定义条目；5) settings_dialog.dart Agent 入口从直接跳转 AgentScreen 改为跳转 AgentSettingsPage，移除未使用的 AgentScreen 导入',
          '影响范围：Agent 任务结果可自动回填聊天（Phase 4 完成）；Agent 有了独立设置页，用户可管理黑白名单、查看操作日志、配置安全选项（Phase 6 核心完成）；知情同意不再每次重启弹框。dart analyze 0 error，无新增 warning',
        ],
      ),
    ],
    normalSections: [
      ChangelogSection(
        title: 'Agent 任务结果自动发到聊天 + Agent 设置页上线',
        icon: AppIcons.smartToyOutlined,
        items: [
          '修改文件：Agent 任务页面、聊天输入、Agent 设置页（新增）、设置入口',
          '具体改动：1) 在聊天里用 Agent 执行任务后，结果会自动发送到聊天对话里，不用手动复制粘贴了——任务完成后点右上角"发送到聊天"按钮即可；2) 新增了 Agent 设置页：在设置里点"Agent 设置"可以管理权限（查看无障碍服务是否开启）、安全配置（开关银行 App 保护、添加/移除 App 黑白名单）、查看操作日志（历史任务列表和每一步操作详情）；3) 修复了每次重启 App 第一次用 Agent 都会弹"功能须知"的问题——现在同意一次以后就不再弹了',
          '影响范围：Agent 任务结果可以方便地分享到聊天；Agent 有了完整的安全管理界面；知情同意体验优化',
        ],
      ),
    ],
    tags: [
      'Agent',
      'Phase4',
      'Phase6',
      'AgentSettingsPage',
      '任务结果回填',
      '黑白名单管理',
      '操作日志',
      '知情同意持久化',
      'AgentSafetyGuard',
      'ChatInputCoordinator',
      'Navigator.pop',
      'chatProvider.sendMessage',
      'SettingsService',
      'Android',
    ],
  ),
  ChangelogEntry(
    version: '1.902',
    date: '2026-06-20 16:20:00',
    professionalSections: [
      ChangelogSection(
        title: 'Agent 前端修复：高危确认对话框 + AI 服务选择器 + 主题色适配',
        icon: AppIcons.smartToyOutlined,
        items: [
          '修改文件：lib/screens/agent/agent_screen.dart',
          '具体改动：1) 修复高危确认对话框缺失（功能缺陷）：Provider 进入 awaitingConfirm 状态时，build 里检测并 addPostFrameCallback 弹出确认框，用户确认/拒绝调用 resolveConfirm，用 _isConfirmDialogShowing 标志位防重复弹出；2) 修复崩溃 Bug：_showSafetyConfirmDialog 无 mounted 检查，postFrameCallback 可能晚于页面 dispose 执行导致 showDialog 用已 unmount 的 context 崩溃，方法入口和 await 后均加 if(!mounted) return；3) 修复 AI 服务选择器：DropdownButtonFormField items 改用 getAllServiceInfo() 显示服务友好名称而非 id，用 didChangeDependencies 在首次 build 前同步读取 SettingsService.getAiServiceId() 作为默认值（修复 initialValue 首帧为 null 导致偏好不显示），_startTask 里 setAiServiceId 保存用户选择；4) 硬编码颜色改用 colorScheme：Colors.grey→onSurfaceVariant、Colors.red→error、Colors.blue→primary，步骤卡片字号改用 textTheme.titleSmall/bodyMedium/bodySmall，适配深色模式',
          '影响范围：Agent 页面高危确认流程（之前会卡死）、AI 服务选择体验（之前显示 id 且不记住选择）、深色模式可读性。dart analyze 0 error',
        ],
      ),
    ],
    normalSections: [
      ChangelogSection(
        title: 'Agent 页面修复：危险操作确认 + AI 服务选择 + 深色模式适配',
        icon: AppIcons.smartToyOutlined,
        items: [
          '修改文件：Agent 任务页面',
          '具体改动：1) 修复了一个严重问题：AI 遇到危险操作（如支付、删除）需要你确认时，之前页面不会弹出确认框导致任务卡死，现在会正常弹出"确认执行"对话框让你选择；2) 修复了一个闪退问题：如果在确认框弹出前退出页面会崩溃，现在已修复；3) AI 服务下拉框现在显示中文名称（如"DeepSeek"）而不是英文 ID，而且会记住你上次选择的服务，下次进入自动选中；4) 修复了深色模式下部分文字看不清的问题，所有颜色改用系统主题色自动适配',
          '影响范围：Agent 任务页面使用体验，深色模式可读性',
        ],
      ),
    ],
    tags: [
      'Agent',
      'AgentScreen',
      '确认对话框',
      'resolveConfirm',
      'AI服务选择器',
      'didChangeDependencies',
      'colorScheme',
      '深色模式',
      'mounted检查',
      '崩溃修复',
      '前端修复',
    ],
  ),
  ChangelogEntry(
    version: '1.901',
    date: '2026-06-20 15:30:00',
    professionalSections: [
      ChangelogSection(
        title: 'Agent 功能路由入口 + 聊天内意图触发（Phase 3 收尾 + Phase 4）',
        icon: AppIcons.smartToyOutlined,
        items: [
          '修改文件：lib/screens/settings_dialog.dart、lib/services/agent/agent_intent_detector.dart、lib/screens/coordinators/chat_input_coordinator.dart',
          '具体改动：1) settings_dialog.dart 的 _getAllSections 新增 "Agent 手机操控" 分区，用 Platform.isAndroid 条件包裹，非 Android 平台不显示入口，含 navigate 项跳转 AgentScreen，解决 Agent 功能页面已实现但无路由入口的阻塞问题；2) 新增 agent_intent_detector.dart：支持 /agent、@agent 显式命令（直接触发）+ 保守关键词匹配（"帮我打开+App名"、"自动操作/点击/滑动"、"操控手机"等，弹确认对话框），关键词用组合词而非单关键词避免误触发；3) ChatInputCoordinator.sendMessage 集成意图检测：仅 Android 平台（AccessibilityBridge.instance.isSupported）生效，显式命令直接跳转 AgentScreen 并预填任务不发送消息，关键词命中弹确认对话框用户取消则正常发送；4) 修复附件丢失 Bug：两个 Agent 跳转分支 return 前调用 fileController.getAttachmentsAndClear() 清理附件，避免附件静默丢失和 UI 状态不一致；5) 修复 use_build_context_synchronously lint：await _showAgentConfirmDialog 后加 context.mounted 检查',
          '影响范围：Agent 功能可达性（设置页入口）、聊天内 Agent 触发。dart analyze lib 维持 0 error，无新增警告',
        ],
      ),
    ],
    normalSections: [
      ChangelogSection(
        title: 'Agent 功能现在可以进入了 + 聊天里直接用 Agent',
        icon: AppIcons.smartToyOutlined,
        items: [
          '修改文件：设置页、聊天输入',
          '具体改动：1) 之前 Agent 功能页面做好了但找不到入口，现在在设置页新增了 "Agent 手机操控" 入口，点击就能进入 Agent 任务页面；2) 在聊天里可以直接触发 Agent 了：输入 "/agent 打开微信" 会直接跳转到 Agent 执行任务，输入 "帮我打开微信"、"自动点击" 等关键词会弹出提示问你是否用 Agent 执行（选"正常聊天"则忽略）；3) 这些功能只在安卓手机上出现，其他平台不受影响',
          '影响范围：Agent 功能现在可以从设置页和聊天两个地方进入了',
        ],
      ),
    ],
    tags: [
      'Agent',
      'AgentIntentDetector',
      'AgentScreen',
      'settings_dialog',
      'chat_input_coordinator',
      '路由入口',
      '意图识别',
      'Phase3',
      'Phase4',
      'Android',
      'AccessibilityBridge',
    ],
  ),
  ChangelogEntry(
    version: '2.320',
    date: '2026-06-19 17:10:00',
    professionalSections: [
      ChangelogSection(
        title: '修复语音识别测试 + 搜索引擎 API Key 安全存储迁移',
        icon: AppIcons.autoFixHigh,
        items: [
          '修改文件：lib/services/speech_recognition_service.dart、test/unit/speech_recognition_test.dart、lib/services/settings_service.dart、lib/screens/settings/search_engine_page.dart',
          '具体改动：1) 语音识别测试修复（68个失败→全部通过）：AudioRecorder 从构造时初始化改为延迟初始化（getter 模式），避免测试环境无 platform channel binding 导致崩溃；dispose() 增加判空保护；测试 setUp 增加 TestWidgetsFlutterBinding.ensureInitialized()；新增 @visibleForTesting setCachedHasCloudKeyForTesting 方法让测试模拟 API Key 配置状态；修正 5 处 SpeechMode 断言（local→auto，反映真实初始值）；修正 2 处错误码输入（permission denied→permission_not_granted，network error→network_error，匹配源码 switch case）；2) 搜索引擎 API Key 安全迁移：getSearchApiKey/setSearchApiKey 从 Hive 明文存储改为 flutter_secure_storage 硬件加密存储，与其他 AI API Key 安全标准统一；新增 loadSearchApiKey() 在启动时预加载到缓存并自动从 Hive 迁移旧值（迁移后删除明文）；init() 中加入 loadSearchApiKey() 调用；search_engine_page onChanged 改为块函数避免 unawaited_futures 警告',
          '影响范围：语音识别单元测试（68个失败→470个全部通过）、搜索引擎 API Key 存储安全（明文→硬件加密）。dart analyze lib 维持 0 error，无新增警告',
        ],
      ),
    ],
    normalSections: [
      ChangelogSection(
        title: '修复语音识别测试 + 搜索引擎密钥安全升级',
        icon: AppIcons.autoFixHigh,
        items: [
          '修改文件：语音识别服务、语音识别测试、设置服务、搜索引擎设置页',
          '具体改动：1) 修复了 68 个语音识别测试失败的问题。原因是测试环境缺少必要的初始化，导致语音录音组件一启动就崩溃。现在改为按需创建录音组件，测试不再崩溃；同时修正了测试中几个与实际代码不匹配的断言；2) 把搜索引擎的 API Key 从普通存储（可被轻易读取）迁移到了硬件加密存储，和其他 AI 服务的密钥一样安全。已有用户的旧密钥会自动迁移过来，无需手动操作',
          '影响范围：语音识别功能测试、搜索引擎密钥安全。测试全部通过，密钥更安全',
        ],
      ),
    ],
    tags: [
      'Flutter',
      'Dart',
      '测试修复',
      'AudioRecorder',
      '延迟初始化',
      'TestWidgetsFlutterBinding',
      'visibleForTesting',
      'SpeechMode',
      'flutter_secure_storage',
      'SecureStorageService',
      '搜索引擎',
      'API Key',
      '安全存储',
      'Hive迁移',
      'speech_recognition_service.dart',
      'settings_service.dart',
      'search_engine_page.dart',
    ],
  ),
  ChangelogEntry(
    version: '2.310',
    date: '2026-06-19 18:25:00',
    professionalSections: [
      ChangelogSection(
        title: '完全修复动画系统：统一接入主题 + 消除性能卡顿',
        icon: AppIcons.animationOutlined,
        items: [
          '修改文件：lib/theme/app_theme.dart、lib/screens/system_status_screen.dart、lib/screens/widgets/chat_drawer.dart、lib/screens/widgets/chat_app_bar.dart、lib/screens/widgets/cached_avatar.dart、lib/screens/widgets/cached_wallpaper.dart、lib/screens/settings/animation_page.dart、lib/screens/chat_screen.dart、lib/screens/onboarding_screen.dart、lib/screens/settings/icon_theme_page.dart、lib/screens/widgets/input_area/voice_wave_indicator.dart、lib/screens/widgets/input_area/voice_mode_selector.dart、lib/screens/widgets/input_area/voice_controls.dart、lib/screens/widgets/chat_body.dart、lib/screens/widgets/input_area/model_selector_sheet.dart、lib/screens/widgets/chat_input_area.dart、lib/screens/changelog_screen.dart、lib/screens/settings/model_page.dart、lib/screens/settings/ai_service_page.dart',
          '具体改动：1) 扩展 AppAnimationTheme 新增 imageFadeDuration/scrollDuration/stepSwitchDuration 三个预设；2) P0 性能修复：system_status_screen 光标动画从"每530ms触发整页setState"改为 WidgetSpan+FadeTransition 局部刷新，chat_drawer/chat_app_bar 的 base64Decode 改用 CachedAvatar 缓存 ImageProvider 并用 Selector2 精确订阅避免流式输出时重复解码，animation_page 的 Opacity 改为 FadeTransition+RepaintBoundary，chat_screen 用 Selector 精确订阅 ChatProvider 避免流式输出时整页重建；3) 硬编码动画接入主题：onboarding_screen(4处)、cached_wallpaper、cached_avatar、icon_theme_page、voice_wave_indicator、voice_mode_selector、voice_controls、chat_body、model_selector_sheet、chat_input_area、changelog_screen 共 20+ 处硬编码 duration/curve 改为从 AppAnimationTheme 读取；4) 路由统一：system_status_screen(4处)、chat_drawer、model_page、ai_service_page 的 MaterialPageRoute 改为 AppPageRouteUtils 接入动画主题；5) 修复 OnboardingAnimatedBuilder 设计缺陷（接收 animation 参数却未使用，Transform.scale 改为 AnimatedScale）',
          '影响范围：所有动画相关组件。修复后所有动画都响应用户的动画设置（速度/强度/护眼/禁用），消除了"有些动画不受设置更改而变化"的问题，同时解决了动画卡顿（光标闪烁整页重建、流式输出头像重复解码、AppBar高频重建等）',
        ],
      ),
    ],
    normalSections: [
      ChangelogSection(
        title: '完全修复动画问题：所有动画现在都听设置的话了',
        icon: AppIcons.animationOutlined,
        items: [
          '修改文件：动画系统、系统状态页、聊天页、引导页、设置页、语音组件等 19 个文件',
          '具体改动：之前有些动画不听设置的话（比如引导页、语音按钮、图片加载、页面切换等），现在全部接入了统一的动画设置系统。你在设置里调整动画速度、强度、护眼模式或关闭动画，所有动画都会跟着变。同时修复了几个导致卡顿的问题：系统状态页的光标闪烁不再每半秒刷新整个页面、聊天页头像不再每次都重新解码、流式输出时不再频繁重建整个页面',
          '影响范围：所有带动画的界面。动画现在更流畅，设置里的动画选项真正生效',
        ],
      ),
    ],
    tags: [
      '动画系统',
      '性能优化',
      'AppAnimationTheme',
      'FadeTransition',
      'CachedAvatar',
      'Selector',
      'AppPageRouteUtils',
      'base64Decode',
      'RepaintBoundary',
      'system_status_screen',
      'chat_screen',
      'onboarding_screen',
      'MaterialPageRoute',
    ],
  ),
  ChangelogEntry(
    version: '2.300',
    date: '2026-06-19 07:21:50',
    professionalSections: [
      ChangelogSection(
        title: '修复 Agent 截图功能 Kotlin 编译错误，恢复 APK 构建',
        icon: AppIcons.autoFixHigh,
        items: [
          '修改文件：android/app/src/main/kotlin/com/xingling/chat/agent/XinglingAgentAccessibilityService.kt',
          '具体改动：修复 takeScreenshot 方法调用错误。原代码 takeScreenshot(callback, null) 不匹配父类 AccessibilityService.takeScreenshot(displayId, executor, callback) 签名，且 onSuccess 参数误用 Bitmap 而非 ScreenshotResult。改为 super.takeScreenshot(Display.DEFAULT_DISPLAY, mainExecutor, callback) 显式调用父类，onSuccess 中用 Bitmap.wrapHardwareBuffer(hardwareBuffer, colorSpace) 将 ScreenshotResult 转为 Bitmap，并增加 try-catch 异常处理和 bitmap.recycle() 资源释放',
          '影响范围：Agent 截图功能（VLM fallback）、APK 构建。修复后 flutter build apk --release 成功生成 67.0MB 安装包',
        ],
      ),
    ],
    normalSections: [
      ChangelogSection(
        title: '修复无法打包安装包的问题',
        icon: AppIcons.autoFixHigh,
        items: [
          '修改文件：AI 助手的 Android 原生代码文件',
          '具体改动：修复了 AI 助手截图功能的代码错误，这个错误导致整个安装包无法打包。现在截图功能改用正确的 Android 系统 API，并增加了错误保护和内存清理',
          '影响范围：AI 助手截图功能、安装包打包。现在可以正常打包安装包了',
        ],
      ),
    ],
    tags: [
      'Kotlin',
      'Android',
      'AccessibilityService',
      'takeScreenshot',
      'ScreenshotResult',
      'Bitmap',
      'APK构建',
      'XinglingAgentAccessibilityService.kt',
    ],
  ),
  ChangelogEntry(
    version: '2.290',
    date: '2026-06-19 06:33:39',
    professionalSections: [
      ChangelogSection(
        title: '架构重构：DI 模块化 + ChatProvider 拆分 + 双轨记忆职责理清',
        icon: AppIcons.autoFixHigh,
        items: [
          '修改文件：lib/core/app_bootstrap.dart（新增）、lib/main.dart、lib/providers/chat_send_orchestrator.dart（新增）、lib/providers/chat_provider.dart、lib/providers/memory_provider.dart、lib/services/memlocal_service.dart',
          '具体改动：1) DI 重构：新建 AppBootstrap 类，将 main.dart 瀑布流初始化拆为 5 个分阶段方法（initCore/initStorageLayer/initServices/initChatProvider/_warmUpTts），依赖关系通过方法签名显式表达，编译器可检查顺序；2) ChatProvider 拆分：新建 ChatSendOrchestrator 抽出发送流程（~400 行），ChatProvider 从 1183→664 行 Facade 化，遵循 ChatStreamingController helper 模式（独立类 + onNotify 回调），_messages 共享状态通过回调读写；3) 双轨记忆理清：MemoryProvider.getMemoryContext 从"短路"改为"合并"（MemLocal 会话内原文 + MemU 跨会话语义），MemLocal 移除片段提取逻辑（~200 行删除，职责归 MemU），getRelevantContext 改为基于消息原文检索',
          '影响范围：应用启动流程、聊天发送流程、记忆检索流程。DI 顺序敏感问题解决，ChatProvider 职责减轻，MemU 跨会话语义记忆被真正使用，片段不再双写',
        ],
      ),
    ],
    normalSections: [
      ChangelogSection(
        title: '软件内部架构优化，提升稳定性和可维护性',
        icon: AppIcons.autoFixHigh,
        items: [
          '修改文件：启动流程、聊天核心、记忆系统等多个内部文件',
          '具体改动：优化了软件内部的三块核心逻辑：1) 启动流程：把原来一长串的初始化步骤拆成几个独立阶段，每步的依赖关系更清晰，不容易出错；2) 聊天核心：把负责发送消息的大块代码拆分成独立的发送管理器，让聊天主逻辑更轻量；3) 记忆系统：理清了两套记忆系统的分工，会话内的消息原文和跨会话的语义记忆现在各司其职，不再重复存储',
          '影响范围：软件启动、聊天发送、记忆检索。整体更稳定，后续维护更方便',
        ],
      ),
    ],
    tags: [
      'Flutter',
      'Dart',
      'DI',
      'AppBootstrap',
      'ChatProvider',
      'ChatSendOrchestrator',
      'Facade模式',
      'MemU',
      'MemLocal',
      'MemoryProvider',
      '记忆系统',
      '架构重构',
      'app_bootstrap.dart',
      'chat_provider.dart',
      'chat_send_orchestrator.dart',
      'memory_provider.dart',
      'memlocal_service.dart',
    ],
  ),
  ChangelogEntry(
    version: '2.280',
    date: '2026-06-19 06:30:31',
    professionalSections: [
      ChangelogSection(
        title: '统一底部弹窗样式，符合系统主题',
        icon: AppIcons.palette,
        items: [
          '修改文件：main.dart、lib/screens/widgets/app_snack_bar.dart（新增）、lib/screens/chat_screen.dart、lib/services/dev_mode_service.dart 等 21 个文件',
          '具体改动：1) 在 main.dart 的 ThemeData 添加 snackBarTheme 配置，背景色用 colorScheme.inverseSurface、文字色用 onInverseSurface，解决弹窗太白的问题；2) 新建 AppSnackBar 工具类，提供 showSuccess/showError/showWarning/showInfo 四种类型，每种带对应 ThemedIcon 图标（复用项目图标主题系统，跟随用户选择的图标主题），背景色统一走主题不硬编码；3) 替换全项目 21 个文件中所有 ScaffoldMessenger.showSnackBar 调用为 AppSnackBar 工具类调用，移除硬编码的 Colors.red/green/orange[700]',
          '影响范围：全项目底部提示弹窗。所有报错/成功/警告/普通提示弹窗现在统一使用主题色，跟随用户选择的种子色和深浅色模式，不再出现刺眼白色背景；通过图标形状区分提示类型',
        ],
      ),
    ],
    normalSections: [
      ChangelogSection(
        title: '修复底部提示弹窗太白的问题，现在跟随主题颜色',
        icon: AppIcons.autoFixHigh,
        items: [
          '修改文件：主程序配置、新建提示弹窗工具、聊天界面等 21 个文件',
          '具体改动：修复了底部弹出的提示信息（比如报错、成功提示）背景太白、和软件主题不搭的问题。现在所有提示弹窗都会自动跟随你选择的主题颜色，深色模式下也协调。同时在提示文字前加了小图标，一眼就能看出是成功（勾）、报错（感叹号）、警告（警告标志）还是普通信息（i）',
          '影响范围：软件里所有底部弹出的提示信息。现在提示弹窗颜色和软件主题统一，看起来更协调',
        ],
      ),
    ],
    tags: [
      'Flutter',
      'SnackBar',
      'Theme',
      'ColorScheme',
      'Material 3',
      'AppSnackBar',
      'ThemedIcon',
      'UI统一',
      'main.dart',
      '主题适配',
    ],
  ),
  ChangelogEntry(
    version: '2.270',
    date: '2026-06-19 05:48:18',
    professionalSections: [
      ChangelogSection(
        title: '修复 Android 构建 ABI 配置冲突错误（#32 APK 体积优化）',
        icon: AppIcons.errorOutline,
        items: [
          '修改文件：android/app/build.gradle.kts、android/gradle.properties',
          '具体改动：1) 移除 app/build.gradle.kts 中的 splits.abi 配置块（原按 ABI 拆分独立 APK），保留 defaultConfig 中 ndk.abiFilters=arm64-v8a；2) 在 gradle.properties 添加 disable-abi-filtering=true，禁用 Flutter Gradle Plugin 默认向所有 buildType 注入 armeabi-v7a,arm64-v8a,x86_64 三个 abiFilters 的行为。根本原因：Flutter Plugin 在未设置 split-per-abi 属性时（FlutterPlugin.kt 第145-180行 else 分支）会默认注入三个 abiFilters，与手动配置的 splits.abi 冲突，触发 AGP "Conflicting configuration : armeabi-v7a,arm64-v8a,x86_64 in ndk abiFilters cannot be present when splits abi filters are set" 检查报错',
          '影响范围：Android release/debug 构建配置。修复后生成单个仅含 arm64-v8a 的 APK，APK 体积减小。gradlew help 验证 BUILD SUCCESSFUL，原 Conflicting configuration 错误消失',
        ],
      ),
    ],
    normalSections: [
      ChangelogSection(
        title: '修复打包安卓安装包时报错"ABI配置冲突"',
        icon: AppIcons.autoFixHigh,
        items: [
          '修改文件：安卓构建配置文件（build.gradle.kts、gradle.properties）',
          '具体改动：修复了打包安卓安装包时报错"ABI配置冲突"的问题。原因是 Flutter 默认会自动添加三种手机架构（arm64主流手机/arm32老设备/x86模拟器），但我们只想要 arm64 一种来减小安装包体积，两边配置打架导致报错。现在关掉了 Flutter 的自动添加，只保留我们手动指定的 arm64，打包不再报错',
          '影响范围：安卓打包。修复后可以正常打包，生成的安装包只支持主流 arm64 手机，体积更小',
        ],
      ),
    ],
    tags: [
      'Flutter',
      'Android',
      'Gradle',
      'ABI',
      'build.gradle.kts',
      'gradle.properties',
      'APK体积优化',
      '构建修复',
    ],
  ),
  ChangelogEntry(
    version: '2.260',
    date: '2026-06-18 18:34:39',
    professionalSections: [
      ChangelogSection(
        title: '新增 PROJECT_AI_GUIDE.md 项目评审指南',
        icon: AppIcons.descriptionOutlined,
        items: [
          '修改文件：PROJECT_AI_GUIDE.md（新建）',
          '具体改动：基于对 lib/main.dart、pubspec.yaml、lib/services/ai_service.dart、lib/services/ai_service_factory.dart、lib/providers/chat_provider.dart、lib/services/storage_service.dart、lib/services/secure_storage_service.dart、lib/services/settings_service.dart、lib/core/logger/app_logger.dart、lib/core/errors/app_error_handler.dart、lib/theme/app_themes.dart 等核心代码的实际阅读，生成一份面向新开发者的专业全面项目介绍文档。文档涵盖项目总览、技术栈与依赖、启动初始化流程、架构分层、状态管理、数据模型、AI 服务层（16 家厂商）、记忆系统（MemLocal/MemU）、OCR/语音/TTS、网络搜索、数据持久化与安全存储、UI 与主题、日志与错误处理、性能优化策略及新开发者评审要点，并附带常用验证命令与核心文件链接',
          '影响范围：仅新增文档文件，未修改任何 Dart 代码或业务逻辑。为后续评审、维护提供一份不依赖过期 README/MD 的权威代码级指南',
        ],
      ),
    ],
    normalSections: [
      ChangelogSection(
        title: '新增项目评审说明文档',
        icon: AppIcons.descriptionOutlined,
        items: [
          '修改文件：PROJECT_AI_GUIDE.md（新增）',
          '具体改动：通过直接阅读项目里的核心代码（不写代码，只看代码），整理出一份给新开发者看的“项目说明书”。里面写了这个App是做什么的、用了哪些技术、怎么启动、有哪些功能（聊天、记忆、OCR、语音、搜索等）、数据怎么保存、API Key怎么保护、界面主题怎么换，以及如果新开发者要接手应该注意哪些问题',
          '影响范围：只增加了一份文档，没有改任何程序代码。以后新开发者可以先看这份文档，快速了解整个项目，不会被旧的过期说明误导',
        ],
      ),
    ],
    tags: ['Flutter', 'Dart', '文档', 'PROJECT_AI_GUIDE.md', '代码理解', '评审指南'],
  ),
  ChangelogEntry(
    version: '2.250',
    date: '2026-06-18 13:58:17',
    professionalSections: [
      ChangelogSection(
        title: '全局动画卡顿性能优化（4处修复）',
        icon: AppIcons.boltOutlined,
        items: [
          '修改文件：lib/screens/widgets/chat_body.dart、lib/screens/chat_screen.dart、lib/screens/onboarding_screen.dart',
          '具体改动：1) chat_body.dart RepaintBoundary key 从 msg_\${index}_\${content.hashCode} 改为 msg_\${message.id}，用稳定标识符避免消息编辑后 key 变化导致重绘隔离失效；2) chat_body.dart 移除两处 AnimatedOpacity(opacity: 1.0) 无效果动画组件（固定不透明度1.0动画无意义），改为直接 Padding 减少 rebuild 开销；3) chat_screen.dart 附件流监听从空 setState(() {}) 改为 StreamBuilder 局部刷新 ChatBody，避免附件变化时整个 ChatScreen rebuild（原实现触发消息列表+输入栏+壁纸层全部重建）；4) onboarding_screen.dart 自定义 AnimatedBuilder 类重命名为 OnboardingAnimatedBuilder，避免遮蔽 Flutter 框架同名类导致类型解析隐患',
          '影响范围：聊天页消息列表滚动、流式输出、附件添加/删除、引导页动画。dart analyze lib 0 error，flutter analyze 修改文件无新增 error/warning',
        ],
      ),
    ],
    normalSections: [
      ChangelogSection(
        title: '修复多处动画卡顿问题',
        icon: AppIcons.boltOutlined,
        items: [
          '修改文件：聊天消息列表、聊天主屏幕、引导页',
          '具体改动：1) 修复消息列表的"重绘隔离"失效问题——原来用消息内容作为标识，消息一变标识就变导致隔离失效，改为用消息唯一ID作为标识；2) 删除两个没有实际效果的动画组件（固定不透明度1.0的淡入动画，看起来和没动画一样但白白消耗性能）；3) 修复添加/删除附件时整个聊天屏幕重新绘制的问题——原来改个附件整个屏幕（包括消息列表、输入栏、壁纸）都要重新画一遍，现在只更新需要变化的部分；4) 修复引导页自定义组件名和系统组件重名的问题，避免潜在冲突',
          '影响范围：聊天时滚动更流畅、AI回复时更顺滑、添加图片或文件时不再卡顿、引导页动画更稳定',
        ],
      ),
    ],
    tags: [
      'Flutter',
      'Dart',
      '性能优化',
      '动画卡顿',
      'RepaintBoundary',
      'StreamBuilder',
      'chat_body.dart',
      'chat_screen.dart',
      'onboarding_screen.dart',
    ],
  ),
  ChangelogEntry(
    version: '2.240',
    date: '2026-06-18 12:41:06',
    professionalSections: [
      ChangelogSection(
        title: '阶段一+二：PROJECT_ONBOARDING.md 文档与代码实际状态对齐',
        icon: AppIcons.shieldOutlined,
        items: [
          '修改文件：PROJECT_ONBOARDING.md',
          '具体改动：基于代码核查修复11处文档与实际不符描述+#17/#24/#29三处仅补文档标记+末尾说明更新，共18处修改。P1 #9 getConversationsMetadata描述修正（第127行+第387行接力记录）；P2 #14 ChatProvider行数1115→1036；P2 #15 SettingsService行数1481→1364；P2 #20 子Provider double dispose已修复；P2 #21 Token估算CJK 1.0+其他0.25；P2 #22 流式rebuild 100ms+8字符；P2 #23 大对象常驻内存已修复；P2 #27 测试文件19个；P2 #28 test/integration/目录；P2 #30 pubspec.yaml:19；P2 #32 678个PNG；#17 Sync/Async已处理；#24 MemoryVectorSearch已处理；#29 性能基准测试已处理；测试目录结构16单元+3集成+1helper；验证命令flutter test test/integration/',
          '影响范围：仅文档，不动代码。修正后PROJECT_ONBOARDING.md与代码实际状态完全一致，后续维护时不再被错误描述误导',
        ],
      ),
    ],
    normalSections: [
      ChangelogSection(
        title: '修正项目说明文档',
        icon: AppIcons.shieldOutlined,
        items: [
          '修改文件：项目说明文档（PROJECT_ONBOARDING.md）',
          '具体改动：把项目说明文档里和实际代码对不上的描述全部改正过来。比如文档说某个文件有1115行实际只有1036行、文档说有16个测试文件实际有19个、文档说图片资源有XXX个实际有678个。一共修正了11处这样的描述错误，另外补上3处"已处理"标记，最后更新了文档末尾的日期和完成情况说明',
          '影响范围：只是改文档，没动任何代码。改完后文档和代码完全对得上，以后AI或者人来看项目时不会被错误信息误导',
        ],
      ),
    ],
    tags: ['Flutter', 'Dart', '文档修正', 'PROJECT_ONBOARDING.md', '代码核查'],
  ),
  ChangelogEntry(
    version: '2.230',
    date: '2026-06-18 01:45:12',
    professionalSections: [
      ChangelogSection(
        title: 'P2 #14：ChatProvider God Class 保守拆分',
        icon: AppIcons.shieldOutlined,
        items: [
          '修改文件：lib/providers/chat_streaming_controller.dart（新建）、lib/services/chat_token_service.dart（新建）、lib/services/message_persistence_helper.dart（新建）、lib/providers/chat_provider.dart',
          '具体改动：从 ChatProvider（原1067行）抽出3个辅助类：ChatStreamingController（流式状态管理+100ms/8字符节流notify，通过onNotify回调绑定notifyListeners）、ChatTokenService（包装TokenEstimator+SettingsService，无状态）、MessagePersistenceHelper（封装saveMessagesWithRetry+hasSaveError信号）。删除7个流式状态字段（_isStreaming/_streamingContent/_streamingReasoning/_isCancelled/_streamNotifyTimer/_streamNotifyPending/_lastNotifiedStreamLength）、_tokenEstimator、_saveFailed，删除_saveMessagesWithRetry/_throttledStreamNotify/_cancelStreamNotify三个方法。公开API不变，UI层无需改动',
          '影响范围：ChatProvider降至约960行，职责更清晰。流式输出、Token估算、消息保存行为完全不变。chat_provider_test 18个测试全部通过，flutter test test/unit/ 353 passed/68 failed（与上次完全一致）',
        ],
      ),
    ],
    normalSections: [
      ChangelogSection(
        title: '代码整理：拆分臃肿的核心模块',
        icon: AppIcons.shieldOutlined,
        items: [
          '修改文件：聊天核心模块',
          '具体改动：把负责聊天功能的核心模块（之前1000多行代码堆在一个文件里）拆分成三个独立的小模块，分别管理"AI回复的实时显示"、"Token数量计算"、"消息保存"。就像把一个装满各种工具的大工具箱分成三个专用小工具箱，找东西更方便，改一个不会碰坏另一个',
          '影响范围：聊天功能完全不变，只是代码更清晰、更好维护。AI对话、流式显示、Token显示、消息保存都和以前一样',
        ],
      ),
    ],
    tags: [
      'Flutter',
      'Dart',
      'P2修复',
      '架构优化',
      'God Class拆分',
      'chat_provider.dart',
      'chat_streaming_controller.dart',
      'chat_token_service.dart',
      'message_persistence_helper.dart',
    ],
  ),
  ChangelogEntry(
    version: '2.220',
    date: '2026-06-17 22:07:06',
    professionalSections: [
      ChangelogSection(
        title: 'P2 批次1：代码清理与防御性改进',
        icon: AppIcons.shieldOutlined,
        items: [
          '修改文件：lib/core/service_locator.dart（删除）、lib/services/debug_mode_service.dart、lib/services/async_file_writer.dart、lib/services/batch_write_scheduler.dart、lib/providers/chat_provider.dart、lib/providers/conversation_provider.dart、lib/providers/memory_provider.dart、lib/providers/search_provider.dart、lib/providers/backup_provider.dart',
          '具体改动：#16 删除无引用的 ServiceLocator 死代码（含测试文件）；#18 为三个单例 dispose() 加中文文档注释（防未来误用，不改逻辑）；#19 stopGeneration() 末尾补 _cancelStreamNotify()，消除 50ms 窗口期内多余 notifyListeners；#20 为 4 个子 Provider（Conversation/Memory/Search/Backup）加 _disposed 守卫防 double dispose，SearchProvider 额外取消 _cancelToken',
          '影响范围：无行为变化，纯防御性改动。消除死代码认知负担，预防未来 double dispose 崩溃',
        ],
      ),
      ChangelogSection(
        title: 'P2 批次2：性能与估算优化',
        icon: AppIcons.boltOutlined,
        items: [
          '修改文件：lib/providers/chat_provider.dart、lib/services/token_estimator.dart、test/unit/token_estimator_test.dart、lib/services/memlocal_service.dart、lib/services/persona_snapshot_service.dart',
          '具体改动：#22 流式输出节流从 50ms/无阈值改为 100ms/8字符双阈值，长文本场景减少约80% notifyListeners；#21 Token 估算修正 rune>0x7F 过宽判断（代码符号误判为CJK），CJK系数 1.5→1.0，修正测试期望值与实际常量一致；#25 MemLocal 降级回复改为分类编号展示+200字符截断；#26 人格快照改为按会话独立计时+记忆内容hash双触发（6h定期/30min记忆变更）',
          '影响范围：流式输出更流畅、Token估算更准确（消除token_estimator_test既有失败）、离线降级回复更可读、人格快照不再跨会话遗漏',
        ],
      ),
      ChangelogSection(
        title: 'P2 批次3：存储层 Sync/Async 迁移与 base64 按需加载',
        icon: AppIcons.storageOutlined,
        items: [
          '修改文件：lib/services/storage_service.dart、lib/providers/conversation_provider.dart、lib/providers/chat_provider.dart、lib/providers/backup_provider.dart、lib/screens/import_chat_screen.dart',
          '具体改动：#17 迁移4处外部 sync 调用为 async（clearMessages/getMessages/saveMessages/createConversation），新增 getConversationsAsync 方法，sync 版本保留供内部兼容逻辑使用；#23 新增 getConversationsMetadata（剥离base64）和 getConversationAppearanceAsync（按需加载），ConversationProvider 改用 metadata 版本，3个会话切换入口（switchConversation/_loadConversationsForService/_loadOrInitConversations）和 delete 方法加按需加载 base64',
          '影响范围：会话列表内存从60MB降至<1MB（30个会话各2MB壁纸场景），主线程减少同步文件读取阻塞。getConversations保持不变，updateConversationAppearanceAsync等写入路径不受影响',
        ],
      ),
    ],
    normalSections: [
      ChangelogSection(
        title: '代码清理和防护升级',
        icon: AppIcons.shieldOutlined,
        items: [
          '修改文件：核心服务、聊天提供器',
          '具体改动：删除了没用到的依赖注入框架代码，给几个关键服务加了防误用说明，给停止生成功能补了一个小修复让响应更及时，给四个子模块加了防重复销毁保护',
          '影响范围：不影响现有功能，只是让代码更安全、更不容易出问题',
        ],
      ),
      ChangelogSection(
        title: '性能和估算优化',
        icon: AppIcons.boltOutlined,
        items: [
          '修改文件：聊天提供器、Token估算、离线回复、人格快照',
          '具体改动：让AI回复时的界面刷新更流畅（减少不必要的刷新），修正了Token数量估算（之前把代码符号误当中文计算导致高估），改进了离线模式的回复格式让信息更清晰，人格快照现在每个对话独立计时不再互相影响',
          '影响范围：AI对话更流畅、Token显示更准确、离线模式更实用、人格备份更可靠',
        ],
      ),
      ChangelogSection(
        title: '存储优化：大幅降低内存占用',
        icon: AppIcons.storageOutlined,
        items: [
          '修改文件：存储服务、会话管理、备份恢复、导入界面',
          '具体改动：把同步文件读取改为异步避免卡顿，会话列表不再一次性加载所有对话的头像和壁纸图片数据（之前30个对话可能占60MB内存），改为切换到某个对话时才加载它的图片',
          '影响范围：内存占用大幅降低（从60MB降到不到1MB），切换对话时图片会有短暂加载（先显示默认图再显示自定义图），其他功能不受影响',
        ],
      ),
    ],
    tags: [
      'Flutter',
      'Dart',
      'P2修复',
      '性能优化',
      '内存优化',
      'base64按需加载',
      'Sync/Async迁移',
      'Token估算',
      '人格快照',
      '流式输出优化',
      'chat_provider.dart',
      'storage_service.dart',
      'conversation_provider.dart',
      'token_estimator.dart',
      'persona_snapshot_service.dart',
    ],
  ),
  ChangelogEntry(
    version: '2.210',
    date: '2026-06-17 20:02:41',
    professionalSections: [
      ChangelogSection(
        title: 'OCR 密钥安全存储迁移',
        icon: AppIcons.shieldOutlined,
        items: [
          '修改文件：lib/services/settings_service.dart、lib/main.dart',
          '具体改动：将百度/腾讯/阿里 OCR 的 5 个密钥（baiduApiKey、baiduSecretKey、tencentSecretId、tencentSecretKey、aliyunAppCode）从 Hive 明文存储迁移到 flutter_secure_storage（硬件加密）。getter 保持同步签名（从 _apiKeyCache 读取），新增 loadOcrKeys() 在启动时加载到缓存。含一次性迁移逻辑：首次启动时检查 Hive 旧值，迁移到 secure storage 后删除明文。setter 空值时删除（用户清空配置）',
          '影响范围：OCR 云端识别功能。升级后已有 OCR 配置自动迁移，用户无感知。恢复备份后需重新配置 OCR 密钥（与 AI API Key 行为一致）',
        ],
      ),
    ],
    normalSections: [
      ChangelogSection(
        title: 'OCR 密码安全保护升级',
        icon: AppIcons.shieldOutlined,
        items: [
          '修改文件：设置服务、应用入口',
          '具体改动：把云端文字识别（OCR）的密码从普通存储搬到了更安全的加密存储里，就像把密码从抽屉搬到了保险箱',
          '影响范围：使用百度、腾讯、阿里云端文字识别的用户。升级后原来的配置会自动转移，不需要重新填写。但如果从备份恢复，需要重新设置 OCR 密码',
        ],
      ),
    ],
    tags: [
      'Flutter',
      'Dart',
      '安全',
      'OCR',
      'flutter_secure_storage',
      'settings_service.dart',
      'main.dart',
      '密钥迁移',
    ],
  ),
  ChangelogEntry(
    version: '2.200',
    date: '2026-06-17 18:25:00',
    professionalSections: [
      ChangelogSection(
        title: '存储层与流式响应 P0 竞态修复',
        icon: AppIcons.shieldOutlined,
        items: [
          '修复 batch_write_scheduler.dart：schedule 方法原先对同一文件覆盖写入时，旧任务的 completer 被 complete(true) 虚假成功，但其 content 已被新任务覆盖丢弃。现在旧任务的 completer 链接到新任务的真实写入结果（unawaited + then + catchError），新任务成功则旧任务完成 true，失败则完成 false',
          '修复 async_file_writer.dart：dispose() 原先直接 _queues.clear() 丢弃待写入任务，但其 completer 从未被 complete，await 它们的调用方永远 hang。现在 dispose() 先遍历所有队列中的待写入任务 complete(false) 它们的 completer，然后再 clear',
          '修复 chat_provider.dart：_streamAiResponse 两层竞态。第一层：_buildAiMessages 期间（搜索可能 10s）用户点停止时 cancelStream() 因 cancelToken 为 null 无效，随后 chatStream 创建新 cancelToken 发起新请求——现在开头检查 _isCancelled 直接返回。第二层：await for break 后底层 Dio stream 可能不响应订阅取消继续运行到 5 分钟超时——现在 break 后显式调用 cancelStream() 通过 CancelToken 真正中断',
          '影响范围：解决 P0 问题 #1（BatchWriteScheduler 虚假成功）、#2（AsyncFileWriter dispose hang）、#4（流式响应未 cancel）。BatchWriteScheduler.schedule 返回值语义变化：旧任务 Future 现在反映最终文件状态而非自身 content 写入状态',
        ],
      ),
    ],
    normalSections: [
      ChangelogSection(
        title: '存储和流式响应问题修复',
        icon: AppIcons.shieldOutlined,
        items: [
          '修复了聊天记录快速保存时可能误报"保存成功"的问题：现在保存结果会反映真实写入状态，避免数据丢失风险',
          '修复了应用关闭时可能卡住无法退出的问题：现在关闭时会正确通知所有等待中的保存任务结束',
          '修复了对话过程中点击停止按钮后，后台网络请求仍在继续运行的问题：现在停止时会立即中断底层请求，避免浪费流量和电量',
          '修复了联网搜索期间点击停止无效的问题：现在搜索阶段点停止也能正确取消后续的 AI 请求',
        ],
      ),
    ],
    tags: [
      'Flutter',
      'Dart',
      '存储层',
      '流式响应',
      'batch_write_scheduler.dart',
      'async_file_writer.dart',
      'chat_provider.dart',
      'CancelToken',
      '竞态修复',
    ],
  ),
  ChangelogEntry(
    version: '2.190',
    date: '2026-06-17 18:11:20',
    professionalSections: [
      ChangelogSection(
        title: '联网搜索取消机制修复',
        icon: AppIcons.shieldOutlined,
        items: [
          '修复 search_provider.dart：performWebSearchRaw 原先不使用内部 _cancelToken，导致 cancelSearch() 无法取消其发起的搜索请求。现在当外部未传 cancelToken 时，自动创建并使用内部 _cancelToken，使 cancelSearch() 能正确取消请求',
          '修复 chat_provider.dart：_injectSearchContext 联网搜索超时原先仅用 Future.timeout 忽略结果，底层 Dio 请求仍在后台运行浪费资源。现在超时回调中调用 _searchProvider.cancelSearch() 主动取消底层请求',
          '影响范围：同时解决 P0 问题 #5（SearchProvider CancelToken 未使用）和 P1 问题 #10 的搜索部分（搜索超时不 cancel Dio）',
        ],
      ),
    ],
    normalSections: [
      ChangelogSection(
        title: '联网搜索取消问题修复',
        icon: AppIcons.shieldOutlined,
        items: [
          '修复了联网搜索无法被取消的问题：现在取消搜索时能真正停止后台请求',
          '修复了联网搜索超时后请求仍在后台继续运行的问题：现在超时会立即停止后台请求，避免浪费流量和电量',
        ],
      ),
    ],
    tags: [
      'Flutter',
      'Dart',
      '联网搜索',
      'search_provider.dart',
      'chat_provider.dart',
      'Dio',
      'CancelToken',
    ],
  ),
  ChangelogEntry(
    version: '2.180',
    date: '2026-06-17 00:00:00',
    professionalSections: [
      ChangelogSection(
        title: '模型 ID 添加与同步完整实现',
        icon: AppIcons.shieldOutlined,
        items: [
          '新增 settings_service.dart：getCustomModelIdsForService/addCustomModelIdForService/removeCustomModelIdForService 方法，按服务商存储用户手动添加的模型 ID 列表（JSON 数组持久化）',
          '新增 ai_service_factory.dart：getBaseUrl 静态方法，返回各内置服务商的 baseUrl，用于验证模型 ID 时发送测试请求',
          '修复 model_selector_sheet.dart：_confirmAddModel 原先只调用 onSwitchModel 切换模型，没有持久化保存，导致下次打开不显示。改为先验证模型 ID 有效性，验证通过后调用 addCustomModelIdForService 保存到 SettingsService，并刷新 _customModelIdsForService 列表立即显示',
          '新增 model_selector_sheet.dart：_validateModelId 方法，通过发送 max_tokens=1 的测试请求验证模型 ID 是否有效。验证中显示 loading 指示器，验证失败显示错误提示并保留输入框',
          '修复 model_selector_sheet.dart：_buildServiceGroup 原先只显示内置 models，现在也显示用户添加的自定义模型 ID（_customModelIdsForService）',
          '改造 model_selector_sheet.dart：_buildAddCustomServiceTile 从原位展开输入框改为跳转到现有的 CustomModelPage，符合用户预期',
          '修复 model_page.dart：_buildModelList 原先只显示内置 models，现在也显示用户添加的自定义模型 ID。新增 _buildCustomModelItem 方法，支持点击切换和删除',
          '修复 model_page.dart：_buildCustomModelItem 点击切换时调用 switchAiService(forceRefresh: true) 确保服务实例用新模型重建',
          '修复 model_selector_sheet.dart：avoid_context_across_async 错误（await 后先检查 mounted 再使用 context）；unchecked_use_of_nullable_value 错误（getApiKeyForService 返回值用 ?? "" 处理 null）',
        ],
      ),
    ],
    normalSections: [
      ChangelogSection(
        title: '模型 ID 添加和显示问题修复',
        icon: AppIcons.shieldOutlined,
        items: [
          '修复了在模型选择面板添加模型 ID 后不显示的问题：现在添加后会立即显示在列表中，并保存到设置里',
          '添加模型 ID 时会先验证是否有效：发送一个测试请求，验证通过才保存，避免添加无效模型',
          '修复了设置 > 模型版本页面看不到自定义模型 ID 的问题：现在会显示用户添加的模型，可以点击切换和删除',
          '自定义服务区域的"添加自定义服务"按钮改为跳转到现有的添加服务商界面，操作更方便',
        ],
      ),
    ],
    tags: [
      'Flutter',
      'Dart',
      '模型管理',
      'settings_service.dart',
      'model_selector_sheet.dart',
      'model_page.dart',
      'ai_service_factory.dart',
    ],
  ),
  ChangelogEntry(
    version: '2.170',
    date: '2026-06-17 00:00:00',
    professionalSections: [
      ChangelogSection(
        title: '修复 API Key 保存后不生效的问题',
        icon: AppIcons.shieldOutlined,
        items: [
          '修复 chat_provider.dart：switchAiService 原先当 serviceId 相同时直接 return，导致用户在 API Key 页面保存新 key 后，_currentAiService 仍持有旧的（空）API Key，对话时返回 401 错误。新增 forceRefresh 参数，为 true 时即使 serviceId 相同也会重建服务实例',
          '修复 api_key_page.dart：_saveApiKey 调用 switchAiService 时传入 forceRefresh: true，确保新保存的 API Key 立即生效',
          '优化 chat_provider.dart：forceRefresh 场景下跳过 _loadConversationsForService，避免更新 API Key 时不必要的会话重新加载',
        ],
      ),
    ],
    normalSections: [
      ChangelogSection(
        title: '修复配置 API Key 后无法对话的问题',
        icon: AppIcons.shieldOutlined,
        items: [
          '修复了一个问题：在设置里配置了 API Key 后，对话时仍然提示"API Key 无效"。原因是保存 key 后没有重新加载 AI 服务，现在保存后会立即生效',
        ],
      ),
    ],
    tags: [
      'Flutter',
      'Dart',
      'API Key',
      'chat_provider.dart',
      'api_key_page.dart',
    ],
  ),
  ChangelogEntry(
    version: '2.160',
    date: '2026-06-17 00:00:00',
    professionalSections: [
      ChangelogSection(
        title: '服务商选择与模型选择架构重构',
        icon: AppIcons.shieldOutlined,
        items: [
          '新增 settings_service.dart：CustomModelConfig 类和 getCustomModels/setCustomModels/addCustomModel/removeCustomModel 方法，支持存储多个自定义模型（name + baseUrl），以 JSON 数组持久化到 Hive',
          '重构 ai_service_page.dart：从"显示模型表格"改为"只显示和选择服务商"的平铺列表。标题从"选择模型"改为"选择服务商"。内置服务商和自定义服务商分区显示，选中状态基于 SettingsService.getAiServiceId 与 model_selector_sheet 同步',
          '重构 ai_service_page.dart：_deleteCustomService 改为调用 SettingsService.removeCustomModel 删除持久化数据，修复 avoid_context_across_async 错误（在 await 前获取 settings）',
          '重构 model_selector_sheet.dart：_loadCustomModels 改为从 SettingsService.getCustomModels() 读取多自定义模型列表，与 ai_service_page 共享同一数据源，保证两处同步',
          '新增 model_selector_sheet.dart：_confirmAddCustomService 方法，点击"添加自定义服务"后原位展开两个输入框（模型 ID + Base URL），确认后调用 SettingsService.addCustomModel 保存并同步到 ai_service_page',
          '修复 model_selector_sheet.dart：import 路径错误（4 个 ../ 改为 3 个 ../），导致 uri_does_not_exist 编译错误',
        ],
      ),
    ],
    normalSections: [
      ChangelogSection(
        title: '服务商选择和模型选择分离',
        icon: AppIcons.shieldOutlined,
        items: [
          '设置里的"选择模型"改为"选择服务商"，现在只显示和选择服务商（如 OpenAI、DeepSeek），不再显示具体模型',
          '修复了在模型选择面板添加模型 ID 后不显示的问题：现在添加的模型会立即显示在列表中',
          '修复了模型选择面板和设置页数据不同步的问题：现在两处共享同一数据源，添加/删除自定义模型会同步更新',
          '模型选择面板新增"添加自定义服务"功能：点击后原位展开输入框，可输入模型 ID 和 Base URL，确认后自动添加并切换',
          '支持添加多个自定义模型，不再限制只能一个',
        ],
      ),
    ],
    tags: [
      'Flutter',
      'Dart',
      '架构重构',
      '服务商选择',
      'settings_service.dart',
      'ai_service_page.dart',
      'model_selector_sheet.dart',
    ],
  ),
  ChangelogEntry(
    version: '2.150',
    date: '2026-06-17 00:00:00',
    professionalSections: [
      ChangelogSection(
        title: '模型选择器优化',
        icon: AppIcons.shieldOutlined,
        items: [
          '删除 model_selector_sheet.dart 的 Auto Mode 开关功能（_autoMode 字段、_buildAutoModeToggle 方法、build 中的调用全部移除）',
          '修复 ai_service_page.dart：_loadData 中 _customModels 原先硬编码了两个示例模型（mimo-v2.5-pro 和 glm-4.7-flash），导致删除后重新进入页面又会恢复。改为从 SettingsService.getCustomModelName() 读取真实配置',
          '修复 ai_service_page.dart：_deleteCustomModel 原先只从内存列表移除，未清除持久化配置。改为调用 setCustomModelName("") 和 setCustomModelBaseUrl("") 真正清除',
          '修复 model_selector_sheet.dart：_buildGroupedList 原先只在 _customModels 不为空时才显示"自定义服务"区域，导致未配置时完全看不到。改为始终显示该区域，未配置时显示空状态提示',
          '新增 model_selector_sheet.dart：_buildAddModelTile 改为支持原位展开输入框。点击"添加模型"按钮后，原位变成一个长条输入框，用户可手动输入模型 ID，支持回车确认、点击确认按钮、取消按钮三种操作',
          '新增 model_selector_sheet.dart：_addingModelFor Map 和 _addModelControllers Map 用于跟踪每个服务商的输入状态，dispose 时清理控制器避免内存泄漏',
        ],
      ),
    ],
    normalSections: [
      ChangelogSection(
        title: '模型选择界面改进',
        icon: AppIcons.shieldOutlined,
        items: [
          '删除了模型选择面板里的 Auto Mode 开关',
          '修复了设置页里自定义模型的问题：之前会默认显示两个不存在的模型，删除后重新进入又会出现。现在只显示你真正配置的模型',
          '修复了模型选择面板里看不到"自定义服务"区域的问题：现在即使没配置自定义模型，也会显示这个区域',
          '改进了"添加模型"功能：点击后会在原位变成一个输入框，你可以直接输入模型 ID（比如 gpt-4o-mini），按回车或点确认即可切换',
        ],
      ),
    ],
    tags: [
      'Flutter',
      'Dart',
      'UI',
      '模型选择器',
      'model_selector_sheet.dart',
      'ai_service_page.dart',
    ],
  ),
  ChangelogEntry(
    version: '2.140',
    date: '2026-06-17 00:00:00',
    professionalSections: [
      ChangelogSection(
        title: '记忆系统核心 Bug 修复 - 记忆不再丢失',
        icon: AppIcons.shieldOutlined,
        items: [
          '修复 chat_provider.dart：createConversation/switchConversation/_loadOrInitConversations/_createAndSwitchDefault 四处会话切换点均未调用 _memoryProvider.initSession()，导致 MemLocal 记忆会话从未初始化，_sessions Map 永远为空，所有记忆保存和检索被 if(session!=null) 静默跳过 —— 这是"记忆必须主动提起才能记起"的根本原因',
          '修复 chat_provider.dart：_cleanupAfterSend 原先传入全量 _messages 给 addConversationMemory，配合 MemU 内部 _clearOldShortTermMemories 会先删除该会话所有短期记忆再重建，导致短期记忆无法累积。新增 _extractLatestExchange 方法只提取本次 user+assistant 对话轮次写入',
          '修复 memu_service.dart：_getRelevantMemories 的 minScore 从 0.05 降到 0.01，避免字面 TF-IDF 匹配差异导致召回率过低',
          '修复 memu_service.dart：_extractKeywords 原先只保留词频>1 的词，导致单次出现的关键词被丢弃。改为按词频降序取前 10 个，单次出现的词也能作为关键词',
          '修复 memu_service.dart：_calculateRelevanceScore 时间衰减周期从 1 周(168小时)延长到 4 周(672小时)，避免短期记忆在几天内被大幅降权',
          '修复 chat_provider.dart：_buildAiMessages 新增 performAutoSnapshot 调用，每次发送消息时自动检测并备份人格快照（内部有 6 小时间隔限制），解决人格快照定期备份机制从未启用的问题',
          '修复 chat_provider.dart：deleteConversation 删除会话后未清理 MemLocal session 缓存，也未为新切换到的会话调用 initSession。新增 _memoryProvider.removeSession(id) 清理 + initSession(newConvId) 初始化',
          '修复 chat_provider.dart：_loadConversationsForService（切换 AI 服务时加载会话）4 处 switchTo 调用均未调用 initSession，导致切换 AI 服务后记忆系统失效',
          '修复 memu_service.dart：_getRelevantMemories 原先硬性过滤 conversationId 导致所有记忆只检索当前会话，跨会话记忆完全无法召回。改为短期记忆只查当前会话，长期记忆/关键信息/主题跨会话检索，符合 MemU 作为"跨会话语义记忆"的设计职责',
          '修复 memory_provider.dart：buildEnhancedPrompt 消息顺序从 [记忆]→[人格]→[历史] 调整为 [人格]→[记忆]→[历史]，确保 AI 首先确立身份和行为准则，避免记忆内容淡化人格设定',
          '新增 memory_provider.dart：removeSession 方法，用于删除会话时清理 MemLocal session 缓存',
        ],
      ),
    ],
    normalSections: [
      ChangelogSection(
        title: '修复记忆系统 - AI 现在能真正记住之前聊过的内容',
        icon: AppIcons.shieldOutlined,
        items: [
          '修复了一个严重问题：记忆系统的启动开关从来没被打开过，导致大部分记忆功能完全瘫痪。现在记忆系统能正常工作了',
          '修复了短期记忆被反复清除的问题，现在记忆能正常累积，不会每次发消息都丢失之前的记忆',
          '优化了记忆检索，降低了匹配门槛，不需要精确用词也能找到相关记忆',
          '延长了记忆的有效期，从 1 周延长到 4 周，记忆不会太快被遗忘',
          '人格设定现在会自动定期备份，防止人格丢失后无法恢复',
          '修复了删除会话后记忆系统可能失效的问题，删除会话现在会正确清理并切换到新会话',
          '修复了切换 AI 服务后记忆系统失效的问题',
          '修复了跨会话记忆无法召回的问题，现在长期记忆可以在不同对话之间共享（比如你在会话A告诉AI你的名字，切换到会话B它也能记得）',
          '调整了人格设定和记忆的顺序，确保 AI 先记住自己是谁，再参考记忆内容',
        ],
      ),
    ],
    tags: [
      'Flutter',
      'Dart',
      '记忆系统',
      'MemLocal',
      'MemU',
      '人格快照',
      'chat_provider.dart',
      'memory_provider.dart',
      'memu_service.dart',
    ],
  ),
  ChangelogEntry(
    version: '2.130',
    date: '2026-06-07 00:00:00',
    professionalSections: [
      ChangelogSection(
        title: '人格保护与记忆中断挽回系统',
        icon: AppIcons.shieldOutlined,
        items: [
          '新增 persona_snapshot_service.dart：PersonaSnapshotService 单例，基于 Hive Box persona_snapshots 存储人格快照，支持自动/手动/变更前/恢复前/修复前 5 种快照来源，每会话保留20个快照上限，全局200个上限，支持导出/导入快照文件',
          '新增 persona_recovery_service.dart：PersonaRecoveryService 单例，检测5种人格问题类型（promptLost/promptDegraded/memoriesLost/memoriesCorrupted/snapshotAvailable），支持自动恢复和手动恢复，恢复前自动创建安全快照，记忆去重防止重复恢复',
          '新增 persona_recovery_screen.dart：3 Tab 界面（完整性检测/快照列表/操作），支持一键检测所有会话人格完整性、查看快照详情、从指定快照恢复、手动创建快照、导出快照文件',
          '修改 memory_provider.dart：集成 PersonaSnapshotService 和 PersonaRecoveryService，新增 snapshotBeforePromptChange/checkPromptChangeAndSnapshot/performAutoSnapshot/checkPersonaIntegrity/recoverPersona 方法，MemU 初始化成功后自动初始化人格保护系统',
          '修改 chat_provider.dart：setConversationPrompt 在变更前自动创建人格快照，防止误操作导致人格丢失',
          '修改 hive_integrity_checker.dart：repairBox 修复 memu_memory Box 前自动创建快照备份即将删除的条目，防止修复操作导致人格记忆丢失',
          '修改 chat_drawer.dart：侧边栏新增"人格保护"入口，跳转到 PersonaRecoveryScreen',
        ],
      ),
    ],
    normalSections: [
      ChangelogSection(
        title: 'AI人格不会消失了！新增人格保护系统',
        icon: AppIcons.shieldOutlined,
        items: [
          'AI的人格设定现在有自动备份了，每次修改人格前都会自动保存一份快照',
          '如果系统出bug导致人格消失，可以从历史快照一键恢复',
          '新增"人格保护"页面，可以查看所有备份、检测人格是否完整、手动恢复',
          '修复数据库时也会先备份再修复，不会再因为修复操作丢失记忆',
          '快照支持导出到文件，即使最坏情况也能从文件恢复',
        ],
      ),
    ],
    tags: [
      'Flutter',
      'Dart',
      'Hive',
      '人格保护',
      '记忆恢复',
      'persona_snapshot_service.dart',
      'persona_recovery_service.dart',
      'persona_recovery_screen.dart',
      'memory_provider.dart',
      'chat_provider.dart',
      'hive_integrity_checker.dart',
      'chat_drawer.dart',
    ],
  ),
  ChangelogEntry(
    version: '2.120',
    date: '2026-06-05 00:00:00',
    professionalSections: [
      ChangelogSection(
        title: '全局 Emoji 替换为 SVG 图标主题系统',
        icon: AppIcons.palette,
        items: [
          'onboarding_screen.dart：新增 FeatureItem 类，features 字段从 List<String> 改为 List<FeatureItem>，29 处 emoji 前缀替换为 ThemedIcon + AppIcons 常量',
          'changelog_data.dart：89 处 icon 字段从 emoji 字符串替换为 AppIcons 常量（如 AppIcons.mic、AppIcons.settings 等），新增 app_icon_themes.dart 导入',
          'changelog_screen.dart：section icon 渲染从 Text(emoji) 改为 ThemedIcon(iconName)，_ModeCard icon 从 Text 改为 ThemedIcon，2 处错误消息移除 emoji 前缀',
          'custom_model_page.dart：5 处成功/失败消息移除 emoji 前缀，3 处帮助项标题移除 emoji 前缀',
          'memory_test_screen.dart：3 处测试报告消息移除 emoji 前缀，5 处颜色检测逻辑从 emoji 匹配改为关键词匹配',
          'system_status_screen.dart：3 种 Unicode 符号(⚠✓✗)替换为 ASCII 等价字符(!+X)',
          'voice_mode_selector.dart：2 处提示文本移除 emoji 前缀',
          'chat_provider.dart、memory_provider.dart：各 1 处错误消息移除 emoji 前缀',
          'memory_test_service.dart：约 50 处 emoji 从日志/报告消息中移除',
          'chat_export_service.dart：4 处 emoji 从导出格式中移除（用户/助手角色标识、思考过程标签）',
          'vosk_speech_service.dart：2 处数字 emoji(1️⃣2️⃣)替换为 ASCII 数字(1. 2.)',
          'speech_recognition_service.dart：2 处锁定标识 emoji 移除',
          'secure_storage_service.dart、settings_service.dart：共 4 处日志消息 emoji 移除',
          'main.dart：1 处启动日志 emoji 移除',
          '修复 changelog_data.dart BOM 字符导致的编译错误',
        ],
      ),
    ],
    normalSections: [
      ChangelogSection(
        title: '所有表情符号换成统一图标',
        icon: AppIcons.palette,
        items: [
          '引导页的功能介绍不再用 emoji 了，改成了可以跟着图标主题切换的矢量图标，换主题时图标也会跟着变',
          '更新日志页面的分类图标也换成了矢量图标，不再因为设备不同显示不一样的 emoji',
          '设置页面、记忆测试页面、系统状态页面的 emoji 都换成了纯文字或图标',
          '所有 AI 服务、语音识别、导出功能中的 emoji 也都清理干净了',
          '修复了一个文件编码问题，之前可能导致编译报错',
        ],
      ),
    ],
    tags: [
      'Flutter',
      'Dart',
      'ThemedIcon',
      'AppIcons',
      '图标主题',
      'onboarding_screen.dart',
      'changelog_data.dart',
      'changelog_screen.dart',
      'custom_model_page.dart',
      'memory_test_screen.dart',
      'system_status_screen.dart',
      'voice_mode_selector.dart',
      'chat_provider.dart',
      'memory_provider.dart',
      'memory_test_service.dart',
      'chat_export_service.dart',
      'speech_recognition_service.dart',
      'secure_storage_service.dart',
      'settings_service.dart',
      'main.dart',
    ],
  ),
  ChangelogEntry(
    version: '2.110',
    date: '2026-05-31 23:50:00',
    professionalSections: [
      ChangelogSection(
        title: '弹簧曲线动画系统升级',
        icon: AppIcons.bolt,
        items: [
          'AppCurves 新增 4 条弹簧曲线：springEnter(Cubic(0.175,0.885,0.32,1.275)明显过冲)、springExit(快速离场)、springMicro(Cubic(0.34,1.56,0.64,1)微交互弹性)、springPanel(Cubic(0.22,1.2,0.36,1)面板弹性)',
          'AppAnimationTheme 曲线升级：enterCurve→springEnter，exitCurve→springExit，microCurve→springMicro，新增 panelCurve→springPanel；护眼模式下仍使用原始曲线避免过冲',
          'AppAnimationTheme 时长微调：enterDuration 280→300ms，exitDuration 220→250ms，microDuration 160→180ms，panelDuration 380→400ms，pageDuration 340→380ms，messageEnterDuration 300→350ms，inputExpandDuration 240→280ms，switchDuration 180→200ms，sliderDuration 120→140ms',
          '所有 AppAnim 组件统一使用弹簧曲线：bubble/inputArea→springEnter，menuItem→springMicro，dialog→springPanel，chip→springEnter',
          'AppTransitions 5 种过渡风格全部升级使用弹簧曲线，style 2/4 使用 panelCurve 获得更明显的弹性效果',
          'AppPageRouteUtils.pushSubPage() 的 forwardDuration 从 pageDuration 改为 panelDuration',
          '动画设置页过渡效果描述更新，体现弹簧动画特性',
        ],
      ),
    ],
    normalSections: [
      ChangelogSection(
        title: '动画更丝滑了！弹簧效果上线',
        icon: AppIcons.autoAwesome,
        items: [
          '消息气泡弹出来了！新消息出现时会有自然的弹性回弹效果，像弹簧一样轻轻弹到位',
          '对话框弹窗更有弹性了，打开时会有轻微的弹弹弹感觉，不再生硬地出现',
          '页面切换更流畅了，所有过渡动画都换上了弹簧曲线，类似 iPhone 的弹性效果',
          '输入区域展开也更自然了，不再是干巴巴地出现',
          '菜单项和附件标签也有弹性了，所有组件统一使用弹簧曲线',
          '护眼模式下不会有过冲效果，保持温和舒适的视觉体验',
        ],
      ),
    ],
    tags: [
      'Flutter',
      'Dart',
      '动画',
      '弹簧曲线',
      'app_theme.dart',
      'app_anim.dart',
      'app_transitions.dart',
      'app_page_route.dart',
      'animation_page.dart',
    ],
  ),
  ChangelogEntry(
    version: '2.100',
    date: '2026-05-31 23:30:00',
    professionalSections: [
      ChangelogSection(
        title: 'sherpa_onnx 替换 vosk_flutter 语音识别引擎',
        icon: AppIcons.mic,
        items: [
          '移除 vosk_flutter 依赖，新增 sherpa_onnx: ^1.13.2 依赖（支持 Android/iOS/Windows/macOS/Linux/鸿蒙）',
          '新建 sherpa_onnx_speech_service.dart：SherpaOnnxSpeechService 类，使用 OnlineRecognizer + OnlineStream 流式识别',
          'SpeechRecognitionService 全面适配：SpeechMode.localVosk → localSherpa，VoskSpeechService → SherpaOnnxSpeechService',
          '初始化流程：先调用 sherpa.initBindings() 加载原生库，再加载 Zipformer 中文流式模型',
          'API 修正：OnlineRecognizerConfig(model: ..., feat: ...)、stream.acceptWaveform(samples:, sampleRate:)、getResult().text、stream.free()/recognizer.free()',
          '模型配置：Zipformer2 transducer (encoder/decoder/joiner ONNX + tokens.txt)，modelType: zipformer2',
          '删除旧的 vosk_speech_service.dart 文件',
          '更新 5 个语音 UI 文件中所有 vosk → sherpa 引用',
          '更新 voice_status_area.dart：修复构造函数名 _VoskModelMissingWidget → _SherpaModelMissingWidget',
          '更新模型下载链接为 GitHub k2-fsa/sherpa-onnx releases',
          '修复 ai_service_page.dart：BuildContext 跨 async gap 安全问题、unnecessary_underscores、unused_element_parameter',
          '修复 model_selector_sheet.dart：unnecessary_underscores',
          'flutter analyze 零错误零警告通过',
        ],
      ),
    ],
    normalSections: [
      ChangelogSection(
        title: '语音识别引擎大升级',
        icon: AppIcons.autoAwesome,
        items: [
          '把语音识别引擎从 vosk 换成了 sherpa_onnx，支持更多设备',
          '现在包括鸿蒙系统在内的所有安卓设备都能用离线语音识别了',
          '电脑端（Windows）也能用离线识别了',
          '新的引擎更稳定，不会在某些手机上崩溃',
          '修复了设置页面的一些小问题',
          '所有代码检查全部通过，没有错误和警告',
        ],
      ),
    ],
    tags: [
      'Flutter',
      'Dart',
      'sherpa_onnx',
      'vosk_flutter',
      'STT',
      'SpeechRecognition',
      'Zipformer',
      'OnlineRecognizer',
      'HarmonyOS',
      'Android',
      'Windows',
      'sherpa_onnx_speech_service.dart',
      'speech_recognition_service.dart',
      'voice_status_area.dart',
      'voice_input_panel.dart',
      'ai_service_page.dart',
      'model_selector_sheet.dart',
    ],
  ),
  ChangelogEntry(
    version: '2.090',
    date: '2026-05-31 22:00:00',
    professionalSections: [
      ChangelogSection(
        title: 'DevModeLabel 组件标签覆盖',
        icon: AppIcons.settings,
        items: [
          '为 18 个 Widget 文件的 build() 方法添加 DevModeLabel 包装',
          'lib/screens/widgets/ 下 10 个文件：ChatDrawer、ChatBody、ChatAppBar、ChatMarkdown、StreamingCursor、CachedAvatar、CachedWallpaper、ImageOcrEditorDialog、ImageEditorDialog、PrivacyPromptDialog',
          'lib/screens/widgets/input_area/ 下 8 个文件：AttachmentMenu、ConversationSettingsDialog、TokenInfoDialog、VoiceModeSelector、VoiceWaveIndicator、VoiceStatusArea、VoiceRecognizedText、VoiceControls',
          '所有文件添加 dev_mode_service.dart 的 import',
          'StreamingCursor 和 CachedWallpaper 重构了条件返回为单返回结构以适配包装',
        ],
      ),
    ],
    normalSections: [
      ChangelogSection(
        title: '开发模式标签覆盖更多组件',
        icon: AppIcons.autoAwesome,
        items: [
          '给 18 个界面组件加上了开发模式标签，方便调试时识别是哪个组件',
          '包括聊天侧边栏、聊天主体、顶栏、Markdown渲染、光标动画、头像、壁纸等',
          '还包括语音相关的8个组件：附件菜单、对话设置、Token信息、语音模式选择等',
        ],
      ),
    ],
    tags: [
      'Flutter',
      'Dart',
      'DevModeLabel',
      'dev_mode_service.dart',
      'chat_drawer.dart',
      'chat_body.dart',
      'chat_app_bar.dart',
      'chat_markdown.dart',
      'streaming_cursor.dart',
      'cached_avatar.dart',
      'cached_wallpaper.dart',
      'image_ocr_editor_dialog.dart',
      'image_editor_dialog.dart',
      'privacy_prompt_dialog.dart',
      'attachment_menu.dart',
      'conversation_settings_dialog.dart',
      'token_info_dialog.dart',
      'voice_mode_selector.dart',
      'voice_wave_indicator.dart',
      'voice_status_area.dart',
      'voice_recognized_text.dart',
      'voice_controls.dart',
    ],
  ),
  ChangelogEntry(
    version: '2.080',
    date: '2026-05-22 16:30:00',
    professionalSections: [
      ChangelogSection(
        title: '自定义模型功能完全重写',
        icon: AppIcons.settings,
        items: [
          'CustomModelPage 完全重写：参考 Trae CN 自定义模型配置界面设计',
          '新增 API 格式选择：支持 OpenAI Chat Completions 和 Anthropic Messages 两种协议',
          '新增 API 密钥输入框（关键修复）：之前缺少此字段导致自定义模型完全无法使用',
          '新增完整 URL 开关：支持填写完整地址或基础地址（自动补全路径）',
          '新增多模态开关：控制是否显示图片上传按钮',
          '新增模型展示名称配置：可自定义模型在列表中的显示名称',
          '新增上下文窗口配置：可设置最大输出 Token 数',
          '新增连接测试功能：保存前可验证 API 地址和密钥是否有效',
          '新增使用说明对话框：包含常见服务商地址示例和注意事项',
          'API 密钥安全存储：使用 SecureStorageService 安全存储，启动时自动加载',
          '表单验证增强：必填项检查、实时字符计数、错误提示优化',
        ],
      ),
    ],
    normalSections: [
      ChangelogSection(
        title: '自定义模型终于能用了！',
        icon: AppIcons.autoAwesome,
        items: [
          '修复了自定义模型功能完全不能用的问题',
          '之前只能填地址和模型名，最关键的 API 密钥没地方填',
          '现在参考 Trae 的设计，重新做了整个配置页面',
          '支持 OpenAI 和 Anthropic 两种格式',
          '可以测试连接是否成功再保存',
          '有详细的使用说明和常见服务商地址示例',
          '密钥会安全保存在手机里，不用担心泄露',
        ],
      ),
    ],
    tags: [
      'Flutter',
      'Dart',
      'CustomModel',
      'CustomModelPage',
      'TraeCN',
      'OpenAI',
      'Anthropic',
      'API Key',
      'SecureStorage',
      'Dio',
      'ConnectionTest',
      'custom_model_page.dart',
      'secure_storage_service.dart',
    ],
  ),
  ChangelogEntry(
    version: '2.070',
    date: '2026-05-22 14:30:00',
    professionalSections: [
      ChangelogSection(
        title: 'STT 全平台自适应方案',
        icon: AppIcons.mic,
        items: [
          'SpeechMode 枚举新增 auto 模式，默认使用自动检测',
          'SpeechRecognitionService 新增 _resolveAutoMode() 方法：根据设备兼容性自动选择最佳语音识别模式',
          '设备检测逻辑：华为/荣耀设备优先云端（避免 FakeRecognitionService 崩溃），Windows 平台推荐云端（SAPI 效果有限），其他 Android 设备使用本地识别',
          '新增 hasAutoSwitched 状态标记和 resetAutoSwitchFlag() 方法，UI 可显示自动切换提示',
          'SettingsService 新增 getSttMode()/setSttMode() 方法，支持 STT 模式偏好持久化（auto/local/cloud）',
          'VoiceInputPanel 新增设备兼容性提示：华为/荣耀设备显示警告，自动模式显示状态指示',
          'VoiceInputPanel 新增 _buildAutoSwitchWarning() 组件：当系统自动切换模式时显示友好的提示信息',
          '用户手动切换模式时自动重置 hasAutoSwitched 标记，避免持续显示提示',
          'initialize() 方法增强：auto 模式下启动时自动执行设备兼容性检测并解析最佳模式',
          '支持用户偏好覆盖：即使设置 auto 模式，如果用户之前手动选择过 local/cloud，会优先尊重用户选择（但仍进行设备兼容性检查）',
        ],
      ),
    ],
    normalSections: [
      ChangelogSection(
        title: '语音识别全适配',
        icon: AppIcons.mic,
        items: [
          '语音输入现在可以自动适配所有安卓设备了',
          '华为/荣耀手机会自动切换到云端模式，不会崩溃',
          '电脑端如果有云端密钥也会推荐用云端识别',
          '其他手机正常使用系统自带的语音识别',
          '新增"自动"模式，让软件自己选择最佳方式',
          '如果你手动选了某个模式，软件会记住你的选择',
          '当软件自动切换模式时会显示提示告诉你原因',
        ],
      ),
    ],
    tags: [
      'Flutter',
      'Dart',
      'STT',
      'SpeechRecognitionService',
      'SpeechMode',
      'DeviceInfo',
      'Huawei',
      'Honor',
      'EMUI',
      'HarmonyOS',
      'AutoMode',
      'DeviceCompatibility',
      'SettingsService',
      'VoiceInputPanel',
      'speech_recognition_service.dart',
      'settings_service.dart',
      'voice_input_panel.dart',
      'device_info.dart',
    ],
  ),
  ChangelogEntry(
    version: '2.060',
    date: '2026-05-15',
    professionalSections: [
      ChangelogSection(
        title: '头像/壁纸双入口数据统一',
        icon: AppIcons.link,
        items: [
          '修复消息气泡头像 (chat_body.dart) 只读取全局设置、忽略会话级头像的问题',
          'chat_body.dart 两处 MessageBubble 调用现在优先使用 currentConversation.avatarBase64，回退到全局 settings.getAvatarBase64()',
          '修复 search_app_bar.dart AppBar 头像只读全局设置的问题，改用 Selector2<SettingsService, ChatProvider> 同时监听两个数据源',
          '修复 chat_app_bar.dart 同样的问题，改用 Consumer2<SettingsService, ChatProvider>',
          '修复 chat_screen.dart 壁纸透明度判断只检查全局壁纸、忽略会话级壁纸的问题',
          'chat_screen.dart 现在同时检查 conv.wallpaperBase64 和 global wallpaperBase64 任一有值即启用透明模式',
          'ConversationSettingsDialog 新增「同时设为全局默认」复选框（头像和壁纸各一个）',
          '勾选后保存时同步写入 SettingsService 全局设置，实现一次设置到处生效',
          'ConversationSettingsDialog 代码重构：拆分 _buildAvatarSection() 和 _buildWallpaperSection() 独立方法',
          '全面排查确认：主题/图标/助手名称/系统提示词等其他设置无重复入口问题',
        ],
      ),
    ],
    normalSections: [
      ChangelogSection(
        title: '设置统一修复',
        icon: AppIcons.link,
        items: [
          '修复了换头像和壁纸功能在两个地方设置后不同步的问题',
          '主界面对话设置里改了头像/壁纸，现在消息气泡和顶栏都会立即更新',
          '对话设置里新增「设为全局默认」选项，可以一次性应用到所有对话',
          '之前在对话设置里改的只有当前对话生效，其他地方还是旧的',
        ],
      ),
    ],
    tags: [
      'Flutter',
      'Dart',
      'AvatarSync',
      'WallpaperSync',
      'ChatBody',
      'SearchAppBar',
      'ChatAppBar',
      'ChatScreen',
      'ConversationSettingsDialog',
      'Selector2',
      'Consumer2',
      'PerConversationSettings',
      'GlobalSettings',
      'chat_body.dart',
      'search_app_bar.dart',
      'chat_app_bar.dart',
      'conversation_settings_dialog.dart',
    ],
  ),
  ChangelogEntry(
    version: '2.050',
    date: '2026-05-15',
    professionalSections: [
      ChangelogSection(
        title: '系统状态双模式终端',
        icon: AppIcons.memory,
        items: [
          'SystemStatusScreen 新增 TerminalMode 枚举 (status / diagnose) 双模式',
          'Drawer 抽屉菜单拆分为两个独立入口：「系统状态」和「全面检测」',
          '系统状态模式：静态展示当前运行信息（保留 v2.040 终端风格）',
          '全面检测模式：进入后自动逐项运行 9 大模块诊断，实时滚动输出结果',
          '诊断引擎 _runDiagnosis() 异步顺序执行所有检测，每项输出 PASS/FAIL/WARN',
          '9 项检测内容：(1)网络连通性 (2)AI服务配置 (3)API密钥有效性 (4)联网搜索服务 (5)语音识别 (6)数据库存储 (7)记忆系统 (8)安全存储 (9)对话数据完整性',
          '诊断汇总区显示健康评分 (0-100分) + 通过/警告/失败数量 + 等级标签(优秀/良好/一般/需关注)',
          '标题栏新增模式切换按钮，点击可在 STATUS/DIAGNOSE 模式间无缝切换 (pushReplacement)',
          '诊断过程有闪烁光标动画指示正在检测，完成后显示 \$ 提示符',
          '使用 Dio 进行真实的 HTTP 连通性测试（百度/Google 双重验证）',
          '记忆系统检测包含类型分布统计 (短期/长期/主题/关键)',
          'ChatDrawer 新增「全面检测」ListTile 带副标题说明',
        ],
      ),
    ],
    normalSections: [
      ChangelogSection(
        title: '系统状态大升级',
        icon: AppIcons.memory,
        items: [
          '系统状态页面现在有两种模式了',
          '「系统状态」查看当前运行信息，像之前一样',
          '「全面检测」会自动检查每个功能模块是否正常工作',
          '检测时会一行行显示检查进度，最后给出健康评分',
          '两种模式可以随时在顶部按钮切换',
        ],
      ),
    ],
    tags: [
      'Flutter',
      'Dart',
      'TerminalUI',
      'DiagnosticEngine',
      'SystemStatusScreen',
      'TerminalMode',
      'ChatDrawer',
      'Dio',
      'AsyncDiagnosis',
      'HealthScore',
      'system_status_screen.dart',
      'chat_drawer.dart',
    ],
  ),
  ChangelogEntry(
    version: '2.040',
    date: '2026-05-15',
    professionalSections: [
      ChangelogSection(
        title: '系统状态终端化重设计',
        icon: AppIcons.memory,
        items: [
          'SystemStatusScreen 从卡片式 UI 完全重写为黑色终端/CMD 风格界面',
          '纯黑背景 (#0D1117) + GitHub Dark 配色方案 (蓝/绿/黄/红)',
          'Consolas 等宽字体，SelectableText.rich 支持文本选择复制',
          '顶部标题栏：macOS 风格红黄绿三色圆点 + 终端路径 + 版本号',
          '底部闪烁光标：AnimationController 530ms 周期反转动画',
          '信息分区使用 Unicode 制表符边框 (╔╠╚║│) 构建终端视觉效果',
          '9 大信息模块：系统信息、AI引擎、对话管理、记忆系统、联网搜索、功能开关、安全防护、数据流水线',
          '新增展示项：上下文 Token 数、最大上下文、搜索引擎配置、预加载策略、Hive 加密存储详情',
          '数据流水线用 [█] 进度条替代 LinearProgressIndicator，ASCII 字符风格',
          '功能开关显示 ●ON / ○OFF / ▶ACTIVE 三态，颜色编码状态',
          '完全移除 Card/_StatusCard/_InfoRow/_MiniStat/_InteractiveToggle 等旧组件',
        ],
      ),
    ],
    normalSections: [
      ChangelogSection(
        title: '系统状态页面全新设计',
        icon: AppIcons.memory,
        items: [
          '系统状态页面改成了黑色终端风格，像电脑的命令行窗口一样',
          '所有信息用文字和符号整齐排列，一目了然',
          '有闪烁的光标效果，看起来更像真实的终端',
          '可以长按复制里面的文字内容',
          '展示了更多有用的系统信息，比如 AI 模型名、Token 数量等',
        ],
      ),
    ],
    tags: [
      'Flutter',
      'Dart',
      'TerminalUI',
      'SystemStatusScreen',
      'Consolas',
      'GitHubDark',
      'AnimationController',
      'SelectableText',
      'TextSpan',
      'system_status_screen.dart',
    ],
  ),
  ChangelogEntry(
    version: '2.030',
    date: '2026-05-15',
    professionalSections: [
      ChangelogSection(
        title: '华为设备语音识别崩溃修复',
        icon: AppIcons.settings,
        items: [
          '修复华为/荣耀/EMUI 设备上语音识别 SecurityException 导致的 app 崩溃（FATAL EXCEPTION）',
          '_startLocalListening() 错误捕获从 on Exception catch(e) 改为 catch(e)，覆盖 Error 和 Exception 所有类型',
          'Android 原生抛出的 PlatformException(SecurityException) 继承自 Error 而非 Exception，原代码无法捕获导致崩溃',
          '新增 vassistant 关键词匹配，更精确识别华为语音助手劫持',
          '错误信息提示优化：明确标注"厂商兼容性问题"，引导用户切换云端模式',
          'DeviceInfo 华为检测关键词扩展：增加 hw/kirin/harmony 匹配',
        ],
      ),
    ],
    normalSections: [
      ChangelogSection(
        title: '崩溃修复',
        icon: AppIcons.settings,
        items: [
          '修复了华为手机使用语音输入时应用闪退的问题',
          '原因是华为系统拦截了默认语音识别服务，导致安全异常',
          '现在遇到这种情况会自动切换到云端模式，不会崩溃',
        ],
      ),
    ],
    tags: [
      'Flutter',
      'Dart',
      'Android',
      'EMUI',
      'SecurityException',
      'SpeechRecognitionService',
      'DeviceInfo',
      'speech_to_text',
      'vassistant',
      'FakeRecognitionService',
    ],
  ),
  ChangelogEntry(
    version: '2.020',
    date: '2026-05-15',
    professionalSections: [
      ChangelogSection(
        title: '服务商官网入口',
        icon: AppIcons.language,
        items: [
          'AiServicePage 服务列表每个服务商卡片新增 open_in_new 图标按钮，点击跳转 registerUrl 官网',
          'ModelSelectorSheet 底部弹窗同样为每个服务添加官网入口按钮',
          '利用 AiServiceInfo 已有的 registerUrl 字段，无需修改数据模型',
          '使用 url_launcher LaunchMode.externalApplication 在外部浏览器打开',
          '自定义模型(custom)因无官网地址，不显示入口按钮',
        ],
      ),
      ChangelogSection(
        title: 'Bug 修复',
        icon: AppIcons.settings,
        items: [
          '修复 voice_input_panel.dart CloudSpeechState 未定义错误：添加 cloud_speech_provider.dart 导入',
          '修复 cloud_speech_provider.dart 行142 Expected to find \')\' 错误：拆分复杂三元表达式为 if 语句块',
          '修复 cloud_speech_provider.dart SecureStorageService/SettingsService 未定义：添加缺失导入',
          '修复 speech_recognition_service.dart SettingsService.instance/SecureStorageService.instance 未定义：为 SettingsService 添加延迟初始化 instance getter，为 SecureStorageService 添加 instance getter',
          '修复 voice_input_panel.dart spinnerLabel 不必要的非空断言 warning',
          '清理 cloud_speech_provider.dart 未使用的 import（dart:typed_data, record）',
        ],
      ),
    ],
    normalSections: [
      ChangelogSection(
        title: '服务商官网入口',
        icon: AppIcons.language,
        items: [
          '设置中的AI服务列表和聊天界面的快速切换面板，每个服务商旁边多了个网站图标',
          '点击可以直接打开对应AI服务商的官方网站',
          '方便查看API文档、获取密钥或了解服务详情',
        ],
      ),
      ChangelogSection(
        title: '问题修复',
        icon: AppIcons.settings,
        items: ['修复了语音输入面板的编译错误', '修复了云端语音识别服务的多个编译错误', '修复了代码中的一些警告提示'],
      ),
    ],
    tags: [
      'Flutter',
      'Dart',
      'AiServiceInfo',
      'AiServicePage',
      'ModelSelectorSheet',
      'url_launcher',
      'voice_input_panel.dart',
      'cloud_speech_provider.dart',
      'speech_recognition_service.dart',
      'SecureStorageService',
      'SettingsService',
      'CloudSpeechState',
    ],
  ),
  ChangelogEntry(
    version: '2.010',
    date: '2026-05-15',
    professionalSections: [
      ChangelogSection(
        title: '搜索来源展示',
        icon: AppIcons.search,
        items: [
          'Message 模型新增 SearchSource 类和 searchQuery/searchSources 字段，支持结构化搜索元数据存储',
          'SearchService 新增 searchRaw() 方法，返回 List<SearchResult> 结构化搜索结果',
          'SearchProvider 新增 performWebSearchRaw() 方法，返回原始搜索结果列表',
          'ChatProvider._injectSearchContext() 改用 performWebSearchRaw 获取结构化结果，同时生成上下文文本和保存搜索元数据',
          'ChatProvider 新增 _pendingSearchQuery/_pendingSearchSources 状态，在 _finalizeResponse 中附加到 AI 回复消息',
          'MessageBubble 新增 _buildSearchSources() 搜索来源展示组件：地球图标 + 搜索关键词标题 + 链接列表',
          'MessageBubble 新增 _buildSearchSourceItem() 单条搜索结果项：链接图标 + 标题（可点击）+ URL 副标题',
          'MessageBubble 新增 _launchUrl() 方法，点击搜索链接使用 url_launcher 在外部浏览器打开',
          '搜索来源区域位于思考过程下方、回复内容上方，半透明背景卡片样式',
        ],
      ),
    ],
    normalSections: [
      ChangelogSection(
        title: '搜索来源展示',
        icon: AppIcons.search,
        items: [
          'AI 联网搜索后，会在回复上方显示搜索来源链接',
          '显示搜索关键词和搜索到的网页标题、网址',
          '点击链接可以在浏览器中打开对应网页',
          '方便查看 AI 回答参考了哪些网页信息',
        ],
      ),
    ],
    tags: [
      'Flutter',
      'Dart',
      'SearchSource',
      'SearchService',
      'SearchProvider',
      'ChatProvider',
      'MessageBubble',
      'url_launcher',
      'message.dart',
      'search_service.dart',
      'chat_provider.dart',
      'message_bubble.dart',
    ],
  ),
  ChangelogEntry(
    version: '2.000',
    date: '2026-05-10',
    professionalSections: [
      ChangelogSection(
        title: '语音输入面板',
        icon: AppIcons.mic,
        items: [
          '新增 VoiceInputPanel 独立语音输入底部面板组件',
          '声波指示器：中央麦克风图标 + 三层涟漪动画环随音量实时变化',
          '识别文本区：实时显示 SpeechRecognitionService.displayText',
          '控制按钮区：取消/录音停止/确认三按钮操作流程',
          '修复语音输入按钮点不动问题（GestureDetector 与 IconButton 手势冲突）',
          '移除 GestureDetector 包裹，改为纯 IconButton 点击切换录音状态',
        ],
      ),
      ChangelogSection(
        title: '多主题色彩系统',
        icon: AppIcons.palette,
        items: [
          '新增 AppThemes 定义 12 种主题色彩方案（深紫、石墨灰、海洋蓝、翡翠绿、暖阳橙、樱花粉、烈焰红、靛蓝、天青、琥珀金、青柠、胡桃棕）',
          '新增 ThemePage 主题选择页面（3 列网格布局 + 选中高亮 + 阴影动效）',
          'SettingsService 新增 getThemeSeed/setThemeSeed 持久化存储',
          'main.dart ColorScheme.fromSeed 种子色移入 ListenableBuilder 内部动态生成',
          '设置对话框"外观与个性化"分区新增"主题色彩"入口',
          '主题色彩独立于亮色/暗色模式，亮暗开关保留在界面样式页面',
          '修复主题切换不生效：seedColor 计算从 ListenableBuilder 外部移入内部',
        ],
      ),
      ChangelogSection(
        title: '会话个性化',
        icon: AppIcons.person,
        items: [
          'Conversation 模型新增 avatarBase64 和 wallpaperBase64 字段',
          'ConversationSettingsDialog 新增头像选择器和会话壁纸选择器',
          'ChatDrawer 会话列表支持显示自定义头像',
          'ChatScreen 壁纸层支持会话级壁纸（优先于全局壁纸）',
          'StorageService/ConversationProvider/ChatProvider 新增 updateAppearance 链路',
        ],
      ),
      ChangelogSection(
        title: '模型选择器增强',
        icon: AppIcons.settings,
        items: [
          'ModelSelectorSheet 当前选中服务新增设置按钮',
          '点击设置按钮直接跳转 ModelPage（模型型号 + 高级参数）',
        ],
      ),
      ChangelogSection(
        title: '上下文信息优化',
        icon: AppIcons.dataUsage,
        items: ['TokenInfoDialog 移除"模型限制"行和进度条，避免与永久记忆定位冲突'],
      ),
      ChangelogSection(
        title: 'Bug 修复',
        icon: AppIcons.settings,
        items: [
          '修复 DeepSeek 服务跨文件访问私有成员，父类新增 dio/buildGenerationConfig 公共访问器',
          '修复 cancelToken 重复定义错误',
          '修复系统状态页 getServiceInfo 重复调用',
          '修复 _InteractiveToggle activeHighlight 时滑块位置不正确',
          '修复系统状态页图标和文字过小导致模糊',
          '修复语音识别弃用警告（SpeechListenOptions）',
          '移除 6 个未使用的 import 警告',
        ],
      ),
    ],
    normalSections: [
      ChangelogSection(
        title: '语音输入升级',
        icon: AppIcons.mic,
        items: [
          '点击麦克风按钮弹出独立语音输入面板',
          '实时显示识别文字和录音状态动画',
          '支持确认或取消操作',
          '修复了之前点不动的问题',
        ],
      ),
      ChangelogSection(
        title: '更多主题',
        icon: AppIcons.palette,
        items: [
          '新增 12 种主题色彩可选',
          '包括灰色系、蓝色系、绿色系、暖色系等多种风格',
          '在设置的外观与个性化中自由切换',
          '主题色彩独立于亮色/暗色模式',
          '修复了切换主题不生效的问题',
        ],
      ),
      ChangelogSection(
        title: '会话个性化',
        icon: AppIcons.person,
        items: ['每个对话可以设置专属头像', '每个对话可以设置专属壁纸', '侧边栏会话列表显示自定义头像'],
      ),
      ChangelogSection(
        title: '快捷设置',
        icon: AppIcons.settings,
        items: ['选择 AI 服务时，当前服务旁新增设置按钮', '点击可直接修改模型型号和高级参数'],
      ),
      ChangelogSection(
        title: '界面优化',
        icon: AppIcons.dataUsage,
        items: ['上下文信息弹窗移除了模型限制显示', '更符合永久记忆软件的定位', '修复了多处界面模糊和显示问题'],
      ),
    ],
    tags: [
      'VoiceInputPanel',
      'SpeechRecognitionService',
      'AppThemes',
      'ThemePage',
      'SettingsService',
      'ColorScheme',
      'Conversation',
      'avatarBase64',
      'wallpaperBase64',
      'ConversationSettingsDialog',
      'ModelSelectorSheet',
      'TokenInfoDialog',
      'OpenAiCompatibleService',
      'chat_input_area',
      'main.dart',
    ],
  ),
  ChangelogEntry(
    version: '1.9.0',
    date: '2026-05-10',
    professionalSections: [
      ChangelogSection(
        title: '会话个性化',
        icon: AppIcons.person,
        items: [
          'Conversation 模型新增 avatarBase64 和 wallpaperBase64 字段',
          'ConversationSettingsDialog 新增头像选择器（CircleAvatar + ImagePicker）',
          'ConversationSettingsDialog 新增会话壁纸选择器（预览 + 更换/移除）',
          'ChatDrawer 会话列表支持显示自定义头像',
          'ChatScreen 壁纸层支持会话级壁纸（优先于全局壁纸）',
          'StorageService 新增 updateConversationAppearanceAsync 方法',
          'ConversationProvider 新增 updateAppearance 方法',
          'ChatProvider 新增 updateConversationAppearance 方法',
        ],
      ),
      ChangelogSection(
        title: '模型选择器增强',
        icon: AppIcons.settings,
        items: [
          'ModelSelectorSheet 当前选中服务新增设置按钮（Icons.settings_outlined）',
          '点击设置按钮直接跳转 ModelPage（模型型号 + 高级参数）',
        ],
      ),
      ChangelogSection(
        title: '上下文信息优化',
        icon: AppIcons.dataUsage,
        items: [
          'TokenInfoDialog 移除"模型限制"行和进度条，避免与永久记忆定位冲突',
          'TokenInfoDialog 移除 maxTokens 参数',
          'ChatInputArea 调用 TokenInfoDialog.show 时不再传递 maxTokens',
        ],
      ),
    ],
    normalSections: [
      ChangelogSection(
        title: '会话个性化',
        icon: AppIcons.person,
        items: ['每个对话现在可以设置专属头像', '每个对话可以设置专属壁纸（优先于全局壁纸）', '侧边栏会话列表会显示自定义头像'],
      ),
      ChangelogSection(
        title: '快捷设置',
        icon: AppIcons.settings,
        items: ['选择 AI 服务时，当前服务旁新增设置按钮', '点击可直接修改模型型号和高级参数'],
      ),
      ChangelogSection(
        title: '界面优化',
        icon: AppIcons.dataUsage,
        items: ['上下文信息弹窗移除了模型限制显示', '更符合永久记忆软件的定位'],
      ),
    ],
    tags: [
      'Conversation',
      'avatarBase64',
      'wallpaperBase64',
      'ConversationSettingsDialog',
      'ChatDrawer',
      'ChatScreen',
      'ModelSelectorSheet',
      'ModelPage',
      'TokenInfoDialog',
      'StorageService',
      'ConversationProvider',
      'ChatProvider',
    ],
  ),
  ChangelogEntry(
    version: '1.8.0',
    date: '2026-05-10',
    professionalSections: [
      ChangelogSection(
        title: 'AI 模型全面更新',
        icon: AppIcons.rocketLaunch,
        items: [
          'OpenAI：更新至 GPT-5.5 Instant、GPT-Realtime-2/Translate/Whisper、GPT-5.5-Cyber',
          'DeepSeek：更新至 V4 Pro、V4 Flash、多模态模型',
          '硅基流动：更新至 DeepSeek V4 Pro、Kimi K2.6、GLM-5.1',
          '智谱AI：更新至 GLM-5V-Turbo、GLM-5.1',
          'Kimi：更新至 Kimi K2.6',
          '豆包AI：更新至 Doubao-Seed-2.0-lite',
          '通义千问：更新至 Qwen3.5、Qwen3-Learning',
          '混元AI：更新至混元Hy3 preview',
          'MiniMax：更新至 MiniMax-M2.7',
          '阶跃星辰：更新至 StepAudio 2.5 Realtime',
          '讯飞星火：更新至星火X2-Flash',
          '文心一言：更新至文心大模型5.1',
          'Gemini：更新至 Gemini 3.1、Gemini 3.1 Flash-Lite',
          'Hugging Face：新增 LittleLamb、nanowhale、SAGE-32B',
          '所有服务默认模型同步更新',
        ],
      ),
      ChangelogSection(
        title: '品牌图标集成',
        icon: AppIcons.palette,
        items: [
          'AiServiceInfo 新增 iconAsset 字段，每个服务配置品牌图标路径',
          '模型选择器：从 Material Icons 替换为真实品牌 PNG 图标',
          '服务选择页：左侧显示品牌 Logo + 右侧勾选标记',
          'API Key 页：服务名称前显示品牌图标',
          '设置引导页：删除硬编码 switch，改用 AiServiceFactory 获取完整信息',
          '聊天输入区：服务标签从通用图标改为品牌 Logo',
          '系统状态页：_InfoRow 支持 iconAsset，AI 大脑卡片显示品牌图标',
        ],
      ),
      ChangelogSection(
        title: 'Bug 修复',
        icon: AppIcons.settings,
        items: [
          '修复语音输入按钮点不动：移除 GestureDetector 包裹，消除手势冲突',
          '修复 DeepSeek 服务跨文件访问私有成员 _dio/_buildGenerationConfig，父类新增公共访问器',
          '修复语音识别弃用警告：partialResults/cancelOnError/listenMode 改用 SpeechListenOptions',
          '修复 cancelToken 重复定义错误',
          '修复系统状态页 getServiceInfo 重复调用',
          '修复 _FlowStep completed 状态文字颜色对比度问题',
          '修复 _InteractiveToggle activeHighlight 时滑块位置不正确',
          '修复系统状态页图标和文字过小导致模糊',
          '修复 getApiKeyForService 重复调用',
          '移除 model_page.dart 未使用的 chatProvider 变量',
          '移除 deepseek_service.dart 未使用的 message_payload_converter 导入',
          '简化 openai_compatible_service.dart cancelToken getter/setter 为公共字段',
        ],
      ),
    ],
    normalSections: [
      ChangelogSection(
        title: 'AI 模型大升级',
        icon: AppIcons.rocketLaunch,
        items: [
          '所有 AI 服务更新到 2026 年 5 月最新模型',
          'OpenAI 新增 GPT-5.5 系列和实时语音模型',
          'DeepSeek 升级到 V4 版本',
          '智谱AI 升级到 GLM-5 系列',
          'Kimi 升级到 K2.6',
          'Gemini 升级到 3.1 版本',
          '文心一言升级到 5.1 版本',
        ],
      ),
      ChangelogSection(
        title: '品牌图标',
        icon: AppIcons.palette,
        items: [
          '每个 AI 服务现在显示自己的品牌图标',
          '模型选择器、服务选择页、设置引导页都换上了真实 Logo',
          '聊天输入区显示当前 AI 的品牌图标',
          '系统状态页也显示品牌图标',
        ],
      ),
      ChangelogSection(
        title: '问题修复',
        icon: AppIcons.settings,
        items: [
          '修复语音输入按钮点不动的问题',
          '修复系统状态页面显示模糊的问题',
          '修复系统状态页面开关显示不正确的问题',
          '修复一些代码错误和警告',
        ],
      ),
    ],
    tags: [
      'OpenAI',
      'DeepSeek',
      '智谱AI',
      'Kimi',
      '豆包',
      '通义千问',
      '混元',
      'MiniMax',
      '阶跃星辰',
      '讯飞星火',
      '文心一言',
      'Gemini',
      'HuggingFace',
      'AiServiceInfo',
      'iconAsset',
      'SpeechRecognitionService',
      'OpenAiCompatibleService',
      'SystemStatusScreen',
    ],
  ),
  ChangelogEntry(
    version: '1.902',
    date: '2026-05-03',
    professionalSections: [
      ChangelogSection(
        title: '架构重构',
        icon: AppIcons.settings,
        items: [
          'ChatProvider Token估算逻辑提取为独立TokenEstimator服务：estimateTokens/estimateContextTokens/maxContextTokens，ChatProvider委托调用',
          '创建ServiceLocator轻量级依赖注入框架：registerFactory/registerSingleton/registerLazySingleton/override机制，支持测试时替换服务实例，Disposable生命周期管理',
          'InputSanitizer处理顺序修复：ANSI转义序列正则移至控制字符正则之前，确保\\x1B[31m完整序列被移除而非残留[31m',
        ],
      ),
      ChangelogSection(
        title: '单元测试',
        icon: AppIcons.scienceOutlined,
        items: [
          '新增storage_service_test.dart：StorageService初始化/会话CRUD/消息CRUD/服务切换数据隔离/异步操作/边界条件（30个用例）',
          '新增token_estimator_test.dart：TokenEstimator估算/上下文累加/各服务maxContextTokens（14个用例）',
          '新增service_locator_test.dart：ServiceLocator工厂/单例/懒加载/override/锁定/生命周期（14个用例）',
          '更新input_sanitizer_test.dart：ANSI转义序列测试期望值匹配修复后的行为',
        ],
      ),
    ],
    normalSections: [
      ChangelogSection(
        title: '优化改进',
        icon: AppIcons.folderOpen,
        items: [
          '聊天功能拆分：Token估算功能独立出来，代码更清晰',
          '依赖管理优化：新增统一的服务管理器，方便测试和替换',
          '输入安全修复：修复了ANSI转义序列清理不完整的问题',
        ],
      ),
      ChangelogSection(
        title: '问题修复',
        icon: AppIcons.close,
        items: ['修复了特殊控制字符清理不完整导致可能残留乱码的问题'],
      ),
    ],
    tags: [
      'Flutter',
      'Dart',
      'token_estimator.dart',
      'service_locator.dart',
      'input_sanitizer.dart',
      'chat_provider.dart',
      'storage_service_test.dart',
      'token_estimator_test.dart',
      'service_locator_test.dart',
      '架构重构',
      '依赖注入',
    ],
  ),
  ChangelogEntry(
    version: '1.901',
    date: '2026-05-03',
    professionalSections: [
      ChangelogSection(
        title: '单元测试',
        icon: AppIcons.scienceOutlined,
        items: [
          '新增8个单元测试文件覆盖核心模块：models_test, input_sanitizer_test, error_handling_test, ai_service_factory_test, memory_vector_search_test, memory_conflict_resolver_test, chat_export_service_test, memory_semantic_scorer_test, chat_provider_test, search_ocr_test, sse_parser_test',
          '测试覆盖：Conversation/Message/Attachment模型序列化、InputSanitizer输入清理、ChatError密封类层次、Result<T>类型、AiServiceFactory工厂模式、MemoryVectorSearch向量索引搜索、MemoryConflictResolver冲突检测解决、ChatExportService格式化、MemorySemanticScorer语义评分、ChatProvider Token估算、SearchService/OcrService降级、SSE流式解析',
          '修复测试环境Hive初始化：chat_provider_test添加Hive.init(testDir)解决SettingsService初始化失败',
          '修正测试断言匹配实际行为：ANSI转义序列处理顺序、UnknownError.canRetry=true、冲突检测实体匹配和Jaccard阈值、语义评分最低内容长度',
        ],
      ),
      ChangelogSection(
        title: 'Bug修复',
        icon: AppIcons.close,
        items: [
          '修复chat_input_area.dart异步间隙使用BuildContext的lint警告：await后添加context.mounted检查',
        ],
      ),
    ],
    normalSections: [
      ChangelogSection(
        title: '新功能',
        icon: AppIcons.autoAwesome,
        items: [
          '添加了自动测试：软件的核心功能现在有自动测试保护，减少出错可能',
          '测试覆盖聊天记忆、输入安全、错误处理、AI服务切换等关键功能',
        ],
      ),
      ChangelogSection(
        title: '问题修复',
        icon: AppIcons.close,
        items: ['修复了切换AI模型时可能出现的安全隐患'],
      ),
    ],
    tags: [
      'Flutter',
      'Dart',
      'flutter_test',
      'Hive',
      'chat_provider_test.dart',
      'input_sanitizer_test.dart',
      'error_handling_test.dart',
      'ai_service_factory_test.dart',
      'memory_vector_search_test.dart',
      'memory_conflict_resolver_test.dart',
      'chat_export_service_test.dart',
      'memory_semantic_scorer_test.dart',
      'chat_input_area.dart',
      '单元测试',
    ],
  ),
  ChangelogEntry(
    version: '1.900',
    date: '2026-05-02',
    professionalSections: [
      ChangelogSection(
        title: '新功能',
        icon: AppIcons.autoAwesome,
        items: [
          '更新日志搜索：支持按日期、版本号、关键词、标签搜索更新内容',
          'AI搜索开关：启用后使用AI语义搜索更新内容，含token消耗提醒弹窗',
          '模式选择弹窗：专业版/普通人版双模式查看更新内容，含不再提醒选项',
          '自动折叠：所有更新内容默认收起，仅显示版本号和日期，点击展开',
          '技术标签：每个更新底部显示圆角标签，内容为技术栈和涉及文件',
          '条目分隔：更新内容之间有间距和横线分隔',
        ],
      ),
      ChangelogSection(
        title: '架构重构',
        icon: AppIcons.settings,
        items: [
          'ChatProvider.sendMessage()拆分为10个子方法：_sanitizeInput, _saveUserMessage, _buildAiMessages, _injectSearchContext, _streamAiResponse, _handleCancelledStream, _finalizeResponse, _generateFallbackOrError, _cleanupAfterSend, _StreamResult数据类',
          'Message模型新增id字段：基于时间戳+角色+内容哈希自动生成，==和hashCode基于id',
          'Conversation模型重写为不可变：所有字段final，新增copyWith()方法',
          'AppErrorHandler统一错误处理层：userFriendlyMessage()/canRetry()/log()，映射AiException/ChatError/网络错误/HTTP状态码',
          'settings_dialog.dart拆分：从2514行拆为812行+12个独立页面文件（settings/目录）',
          'ChatInputArea对话框提取：AttachmentMenu, ConversationSettingsDialog, TokenInfoDialog, ModelSelectorSheet',
        ],
      ),
      ChangelogSection(
        title: 'Bug修复',
        icon: AppIcons.close,
        items: [
          '修复联网搜索失效：_injectSearchContext()改用直接SettingsService检查替代SearchProvider状态判断',
          '修复导出路径不可访问：Android改用getExternalStorageDirectory()/XinglingChat，iOS使用ApplicationDocuments目录',
        ],
      ),
    ],
    normalSections: [
      ChangelogSection(
        title: '新功能',
        icon: AppIcons.autoAwesome,
        items: [
          '更新日志搜索：可以搜索日期、版本号、关键词来查找更新内容',
          'AI智能搜索：可以用AI来更智能地搜索更新内容',
          '双模式查看：可以选择"专业版"或"简单版"来查看更新内容',
          '自动折叠：更新内容默认收起，只显示版本号和日期，点击展开查看',
          '技术标签：每个更新底部显示相关技术标签',
        ],
      ),
      ChangelogSection(
        title: '优化改进',
        icon: AppIcons.folderOpen,
        items: [
          '聊天更稳定：优化了消息发送的内部流程',
          '错误提示更友好：出错了会显示更容易理解的提示信息',
          '设置界面更清晰：设置选项重新整理，更好找',
          '对话信息更安全：优化了对话数据的存储方式',
        ],
      ),
      ChangelogSection(
        title: '问题修复',
        icon: AppIcons.close,
        items: ['修复了联网搜索不工作的问题', '修复了导出备份文件在安卓上找不到的问题'],
      ),
    ],
    tags: [
      'Flutter',
      'Dart',
      'chat_provider.dart',
      'chat_input_area.dart',
      'app_error_handler.dart',
      'message.dart',
      'conversation.dart',
      'settings_dialog.dart',
      'changelog_screen.dart',
      'changelog_data.dart',
      'settings_service.dart',
      'chat_export_service.dart',
      'storage_service.dart',
      'Provider',
      '不可变模型',
      'SSE流式解析',
      'Dio',
    ],
  ),
  ChangelogEntry(
    version: '1.7.0',
    date: '2026-05-02',
    professionalSections: [
      ChangelogSection(
        title: '新功能',
        icon: AppIcons.autoAwesome,
        items: [
          '输入框全面重构：暗黑风格圆角矩形，响应式双行/单行布局',
          '加号附件按钮：底部菜单选择图片/文件/链接三种附件方式',
          '联网搜索开关：地球图标蓝色高亮切换，状态同步到会话设置',
          '对话设置按钮：齿轮菜单，支持新话题和对话设置弹窗',
          '对话设置弹窗：可修改会话名称、AI自动命名开关、系统提示词',
          'Token/上下文按钮：显示 ↑+数字 格式，点击查看详细上下文信息',
          '上下文信息弹窗：当前输入Token、上下文Token、总计、模型限制、进度条',
          '模型选择按钮：显示当前AI服务名称，点击弹出服务列表选择',
          '模型选择面板：支持8种AI服务切换，显示名称/描述/免费额度',
          '发送/停止按钮：圆形按钮，发送中变红色停止图标，点击可中断生成',
          '图片选择功能：从相册选择图片，自动OCR识别',
          '添加链接功能：输入URL链接插入到输入框',
        ],
      ),
      ChangelogSection(
        title: '改进',
        icon: AppIcons.folderOpen,
        items: [
          '停止生成功能：支持中断AI流式生成，保存已生成的部分内容',
          'Token估算系统：CJK字符1.5x + 其他字符0.25x近似估算',
          '响应式布局：宽屏(>600dp)单行布局，窄屏双行布局',
          '紧凑模式适配：所有按钮和文字尺寸根据紧凑模式缩放',
        ],
      ),
    ],
    normalSections: [
      ChangelogSection(
        title: '新功能',
        icon: AppIcons.autoAwesome,
        items: [
          '输入框重新设计：更好看更方便的聊天输入框',
          '附件按钮：可以发送图片、文件和链接',
          '搜索开关：可以开启AI联网搜索',
          '对话设置：可以修改对话名称和提示词',
          'Token信息：可以查看当前对话的使用量',
          '模型切换：可以快速切换不同的AI',
          '发送/停止按钮：可以发送消息或停止AI回复',
          '图片选择：可以从相册选图片',
          '链接插入：可以输入网页链接',
        ],
      ),
      ChangelogSection(
        title: '改进',
        icon: AppIcons.folderOpen,
        items: ['可以中途停止AI回复', '可以查看对话的Token使用量', '界面会根据屏幕大小自动调整布局'],
      ),
    ],
    tags: [
      'Flutter',
      'Dart',
      'chat_input_area.dart',
      'chat_provider.dart',
      'ChatFileController',
      'image_picker',
      'Token估算',
      '响应式布局',
    ],
  ),
  ChangelogEntry(
    version: '1.6.0',
    date: '2026-05-02',
    professionalSections: [
      ChangelogSection(
        title: '新功能',
        icon: AppIcons.autoAwesome,
        items: [
          '设置界面全面重构：8个分区重组为7个卡片分组',
          'AI 服务与模型合并：AI服务、API设置、对话设置三合一',
          '动画设置平铺化：子页面内容直接展示，分段按钮+200ms过渡动画',
          '界面样式平铺化：滑块实时预览当前值，9个开关一目了然',
          '外观与个性化入口：头像/壁纸带缩略图预览和状态摘要',
          '联网搜索内联化：搜索引擎下拉选择+条件字段直接展示',
          '数据与性能平铺化：预加载策略+消息条数+会话选择',
          'OCR 设置摘要：右侧显示当前引擎（如"本地 ML Kit"或"云端百度OCR"）',
        ],
      ),
      ChangelogSection(
        title: '改进',
        icon: AppIcons.folderOpen,
        items: [
          'API Key 增加编辑模式切换：非编辑状态显示遮罩+状态图标，点击编辑按钮进入编辑',
          '服务选择器改为内联单选列表：服务名+免费额度，选中态高亮',
          '视觉层次优化：13sp/w600 主题色分区标题、24px outlineVariant 分割线',
          '行高分级：紧凑行48px、标准行56px、预览行72px',
          '导航项摘要文字：右侧显示当前值而非仅箭头',
          '搜索系统完整保留：支持标题+副标题匹配，空分区自动隐藏',
          '条件渲染全部保留：自定义服务→Base URL、搜索开启→引擎配置等',
        ],
      ),
    ],
    normalSections: [
      ChangelogSection(
        title: '新功能',
        icon: AppIcons.autoAwesome,
        items: [
          '设置界面重新整理：更清晰更好找',
          'AI相关设置合并：相关设置放在一起了',
          '动画设置更直观：直接看到效果',
          '外观设置更方便：滑块可以实时预览',
          '搜索设置不用跳转：直接在页面上配置',
        ],
      ),
      ChangelogSection(
        title: '改进',
        icon: AppIcons.folderOpen,
        items: [
          'API Key更安全：默认隐藏显示，点击才编辑',
          'AI服务选择更直观：列表选择，高亮当前',
          '设置项右侧显示当前值：不用点进去就能看到',
        ],
      ),
    ],
    tags: [
      'Flutter',
      'Dart',
      'settings_dialog.dart',
      'Provider',
      'Hive',
      'UI重构',
    ],
  ),
  ChangelogEntry(
    version: '1.5.0',
    date: '2026-05-01',
    professionalSections: [
      ChangelogSection(
        title: '新功能',
        icon: AppIcons.autoAwesome,
        items: [
          'Markdown 富文本渲染：AI 回复支持标题、粗体、斜体、链接、列表等格式',
          '代码块语法高亮：支持多种编程语言着色，暗色/亮色主题自动适配',
          '代码块一键复制：点击代码块右上角"复制"按钮即可复制代码',
          'GFM 扩展：支持 GitHub 风格的表格、任务列表、删除线',
          '消息折叠：AI 回复超过 5000 字符自动折叠，点击"展开全文"查看',
          '键盘快捷键 Enter 发送消息 / Shift+Enter 换行',
          '全局快捷键 Ctrl+N 新建会话 / Ctrl+Shift+F 聚焦输入框',
          '错误提示重试按钮：AI 请求失败时可一键重试',
          '错误提示关闭按钮：手动关闭错误提示',
          '更新日志页面：查看软件版本更新记录',
        ],
      ),
      ChangelogSection(
        title: '架构优化',
        icon: AppIcons.settings,
        items: [
          'ConversationProvider 改为 ChatProvider 内部组件，消除会话状态双写',
          '删除 MessageProvider 半成品代码（309 行），统一使用 ChatProvider',
          '删除 ChatRepository 死代码，减少维护负担',
          '会话状态单一来源，根除切换黑屏类 bug',
        ],
      ),
      ChangelogSection(
        title: 'Bug 修复',
        icon: AppIcons.close,
        items: [
          '修复会话切换黑屏：Navigator.pop 在 Drawer 上下文中误弹路由',
          '修复豆包/通义/HuggingFace 附件处理：使用 convertMessages() 替代 messages.map()',
          '修复 DeepSeek SSE 解析：复用基类 parseOpenAiSseStream，支持 InputSanitizer',
          '修复硅基流动/自定义模型：从模拟实现改为真实 API 调用',
          '修复 refreshConversations 后 _currentConversation 不同步',
        ],
      ),
    ],
    normalSections: [
      ChangelogSection(
        title: '新功能',
        icon: AppIcons.autoAwesome,
        items: [
          'AI回复支持富文本：标题、粗体、列表等格式',
          '代码块有颜色：不同代码有不同颜色',
          '代码块可复制：一键复制代码',
          '长消息自动折叠：太长的回复会自动收起',
          '键盘快捷键：Enter发送，Shift+Enter换行',
          '错误提示可重试：出错了可以一键重试',
          '更新日志页面：可以查看更新记录',
        ],
      ),
      ChangelogSection(
        title: '优化改进',
        icon: AppIcons.folderOpen,
        items: ['聊天更稳定：修复了切换对话时黑屏的问题', '更多AI支持：修复了多个AI服务的兼容问题'],
      ),
    ],
    tags: [
      'Flutter',
      'Dart',
      'flutter_markdown',
      'highlight',
      'ChatProvider',
      'ConversationProvider',
      'Provider架构',
      'SSE',
    ],
  ),
  ChangelogEntry(
    version: '1.6.0',
    date: '2026-05-10',
    professionalSections: [
      ChangelogSection(
        title: '关键 Bug 修复',
        icon: AppIcons.close,
        items: [
          '修复 _finalizeResponse() 逻辑错误：_streamingContent 在 isFallbackResponse 判断前被清空，导致回退判断永远为 true',
          '修复 API Key 明文泄露：GuijiService/CustomModelService 的 toJson() 不再暴露密钥明文',
          '修复 Gemini API Key URL 暴露：改用 x-goog-api-key Header 传递，避免日志泄露',
          '修复 StorageService 会话缓存失效问题：添加 30 秒 TTL 缓存有效期',
          '修复 MessageBubble._animatedIds 内存泄漏：添加 500 条上限自动淘汰机制',
        ],
      ),
      ChangelogSection(
        title: '逻辑修复',
        icon: AppIcons.settings,
        items: [
          '修复 _isSummarizing 永不为 true：在 _autoRenameConversation 执行期间正确设置状态标志',
          '修复 BackupProvider 哈希跨运行不一致：使用 FNV-1a 确定性哈希替代 Dart hashCode',
          '修复 SearchProvider 超时不取消后台搜索：改用 CancelToken + timeout 实现可取消搜索',
        ],
      ),
      ChangelogSection(
        title: '性能优化',
        icon: AppIcons.bolt,
        items: [
          'SpeechRecognitionService 音量变化通知节流：200ms 间隔限制，避免高频 UI 重建',
          'SearchService 全搜索引擎支持 CancelToken：DuckDuckGo/SearXNG/Bing/Google 均可取消',
        ],
      ),
    ],
    normalSections: [
      ChangelogSection(
        title: '安全修复',
        icon: AppIcons.lockOutline,
        items: ['AI密钥不再泄露：修复了导出和日志中可能暴露密钥的问题', 'Gemini密钥更安全：密钥不再出现在网址中'],
      ),
      ChangelogSection(
        title: '稳定性提升',
        icon: AppIcons.bolt,
        items: [
          'AI回复更准确：修复了回复判断逻辑错误',
          '搜索可取消：搜索超时会自动停止，不再浪费流量',
          '语音输入更流畅：减少了不必要的界面刷新',
          '内存更省：修复了消息气泡长期使用后内存持续增长的问题',
          '备份更可靠：跨设备导入时去重更准确',
          '会话列表更及时：修复了切换后偶尔显示旧数据的问题',
        ],
      ),
    ],
    tags: [
      'Flutter',
      'Dart',
      'ChatProvider',
      'GeminiService',
      'GuijiService',
      'SearchProvider',
      'BackupProvider',
      'SpeechRecognitionService',
      'StorageService',
      'MessageBubble',
      'FNV-1a',
      'CancelToken',
    ],
  ),
  ChangelogEntry(
    version: '1.7.0',
    date: '2026-05-10',
    professionalSections: [
      ChangelogSection(
        title: '新 AI 服务',
        icon: AppIcons.autoAwesome,
        items: [
          '新增 OpenAI 服务：支持 GPT-4o / GPT-4o-mini，128K 上下文',
          '新增智谱AI服务：支持 GLM-4-Flash / GLM-4，128K 上下文',
          '新增月之暗面 Kimi 服务：支持 moonshot-v1-8k/32k/128k，超长上下文',
          '新增 MiniMax 服务：支持 MiniMax-Text-01，131K 上下文',
          '新增阶跃星辰服务：支持 Step-2-16k，131K 上下文',
        ],
      ),
      ChangelogSection(
        title: '架构优化',
        icon: AppIcons.settings,
        items: [
          '创建 OpenAiCompatibleService 基类：5个新服务共用基类，每个服务仅需 ~15 行代码',
          'AiServiceFactory 重构：使用 Map 替代硬编码 switch 管理环境变量映射',
          'TokenEstimator 更新：新增 5 个服务的上下文窗口限制配置',
          'SecureStorageService 扩展更新：新增 5 个服务的 API Key 存储支持',
        ],
      ),
    ],
    normalSections: [
      ChangelogSection(
        title: '更多 AI 可选',
        icon: AppIcons.smartToy,
        items: [
          '新增 OpenAI：全球最强AI，GPT-4o 系列',
          '新增智谱AI：国产GLM-4大模型',
          '新增 Kimi：超长上下文，适合读长文',
          '新增 MiniMax：国产大模型新选择',
          '新增阶跃星辰：Step系列大模型',
        ],
      ),
      ChangelogSection(
        title: '优化改进',
        icon: AppIcons.folderOpen,
        items: ['AI服务架构升级：新增服务更简单，代码更精简', '现在支持 12 种 AI 服务 + 自定义模型'],
      ),
    ],
    tags: [
      'Flutter',
      'Dart',
      'OpenAI',
      '智谱AI',
      'Kimi',
      'MiniMax',
      '阶跃星辰',
      'OpenAiCompatibleService',
      'AiServiceFactory',
      'TokenEstimator',
    ],
  ),
  ChangelogEntry(
    version: '1.8.0',
    date: '2026-05-10',
    professionalSections: [
      ChangelogSection(
        title: '新增 AI 服务',
        icon: AppIcons.autoAwesome,
        items: [
          '新增百川智能服务：Baichuan4 / Baichuan3-Turbo，131K 上下文',
          '新增讯飞星火服务：Spark 4.0 Ultra / 3.5 Max，32K 上下文',
          '新增零一万物服务：Yi Lightning / Yi Large，32K 上下文',
          '新增文心一言服务：ERNIE 4.0 / 3.5 / Speed 128K，百度千帆平台',
        ],
      ),
      ChangelogSection(
        title: '高级参数配置',
        icon: AppIcons.settings,
        items: [
          '新增 AI 高级设置页面：Temperature / MaxTokens / TopP / FrequencyPenalty / PresencePenalty',
          'OpenAiCompatibleService 支持 5 个高级生成参数',
          '高级参数持久化到 SettingsService，重启后保留',
          'ChatProvider 切换服务时自动应用高级参数',
          '高级参数实时生效，无需重启',
        ],
      ),
      ChangelogSection(
        title: '模型选择增强',
        icon: AppIcons.expandMore,
        items: [
          'AiServiceFactory 新增 AiModelInfo 模型元数据（id/displayName/contextLength）',
          '所有 16 个服务均配置可用模型列表',
          'ModelPage 重构为动态模型选择，显示模型名称、ID、上下文长度',
          '模型选择页底部新增高级参数入口',
        ],
      ),
    ],
    normalSections: [
      ChangelogSection(
        title: '更多 AI 可选',
        icon: AppIcons.smartToy,
        items: [
          '新增百川智能：国产 Baichuan 大模型',
          '新增讯飞星火：科大讯飞 Spark 系列',
          '新增零一万物：Yi 系列大模型',
          '新增文心一言：百度 ERNIE 系列',
          '现在支持 16 种 AI 服务 + 自定义模型',
        ],
      ),
      ChangelogSection(
        title: 'AI 高级设置',
        icon: AppIcons.settings,
        items: [
          '温度调节：控制回复的随机性',
          '最大Token：控制回复长度',
          'Top P：控制候选词范围',
          '频率惩罚：减少重复用词',
          '存在惩罚：鼓励讨论新话题',
          '一键恢复默认值',
        ],
      ),
      ChangelogSection(
        title: '模型选择升级',
        icon: AppIcons.expandMore,
        items: ['每个服务现在可以选择不同的模型版本', '显示模型上下文长度（8K/32K/128K/1M）', '切换模型即时生效'],
      ),
    ],
    tags: [
      'Flutter',
      'Dart',
      '百川智能',
      '讯飞星火',
      '零一万物',
      '文心一言',
      'Temperature',
      'MaxTokens',
      'TopP',
      'FrequencyPenalty',
      'PresencePenalty',
      'AiModelInfo',
      'AiAdvancedSettingsPage',
    ],
  ),
];
