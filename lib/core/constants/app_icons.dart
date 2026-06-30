// 做什么：开源版 AppIcons 精简常量类（仅字符串常量，无 Flutter 依赖）。
// 为什么这样做：原项目 lib/theme/app_icon_themes.dart 中的 AppIcons 类
// 混合了纯字符串常量与依赖 Flutter 的 _materialMap / IconData / ThemedIcon 等。
// 后端代码（如 changelog_data.dart）只需要字符串常量作为图标标识符，
// 不需要 Flutter Material。拆出此文件让后端库完全自包含、零 Flutter UI 依赖。
//
// 注意：本文件仅同步原项目 lib/theme/app_icon_themes.dart 中 AppIcons 类的
// static const String 字段。若原项目新增图标常量，需同步到此处。
// 原项目中依赖 _materialMap / iconData() / materialIcon / hasIcon() /
// assetPath() / ThemedIcon / IconThemeWrapper 等 Flutter 相关 API 的代码
// 不在后端开源范围内，故此处不提供。

/// 应用图标名称常量集合（纯字符串，无 Flutter 依赖）。
///
/// 这些字符串值对应 Material Icons 的名称（snake_case），
/// 在原完整项目中通过 [AppIcons._materialMap] 映射到 [IconData]，
/// 在前端 UI 层渲染。后端代码（如 changelog_data.dart）仅引用字符串
/// 作为图标标识符，用于序列化或跨层传递，不直接渲染。
class AppIcons {
  AppIcons._();

  // 导航类
  static const String menu = 'menu';
  static const String arrowBack = 'arrow_back';
  static const String arrowForward = 'arrow_forward';
  static const String arrowForwardIos = 'arrow_forward_ios';
  static const String arrowDownward = 'arrow_downward';
  static const String arrowDropDown = 'arrow_drop_down';
  static const String chevronRight = 'chevron_right';
  static const String keyboardArrowUp = 'keyboard_arrow_up';
  static const String expandLess = 'expand_less';
  static const String expandMore = 'expand_more';

  // 操作类
  static const String close = 'close';
  static const String clear = 'clear';
  static const String search = 'search';
  static const String searchOff = 'search_off';
  static const String settings = 'settings';
  static const String settingsOutlined = 'settings_outlined';
  static const String tune = 'tune';
  static const String send = 'send';
  static const String stop = 'stop';
  static const String copy = 'copy';
  static const String edit = 'edit';
  static const String editOutlined = 'edit_outlined';
  static const String refresh = 'refresh';
  static const String deleteOutline = 'delete_outline';
  static const String check = 'check';
  static const String checkCircle = 'check_circle';
  static const String checkCircleOutline = 'check_circle_outline';
  static const String radioButtonUnchecked = 'radio_button_unchecked';
  static const String done = 'done';
  static const String save = 'save';
  static const String saveOutlined = 'save_outlined';
  static const String share = 'share';
  static const String replay = 'replay';
  static const String restore = 'restore';
  static const String openInNew = 'open_in_new';

  // 聊天/消息类
  static const String chat = 'chat';
  static const String chatBubbleOutline = 'chat_bubble_outline';
  static const String messageOutlined = 'message_outlined';
  static const String addCommentOutlined = 'add_comment_outline';
  static const String addCircleOutline = 'add_circle_outline';

  // 输入/媒体类
  static const String mic = 'mic';
  static const String micNoneOutlined = 'mic_none_outlined';
  static const String attachFile = 'attach_file';
  static const String image = 'image';
  static const String imageOutlined = 'image_outlined';
  static const String imageNotSupported = 'image_not_supported';
  static const String brokenImageOutlined = 'broken_image_outlined';
  static const String pictureAsPdf = 'picture_as_pdf';
  static const String textSnippet = 'text_snippet';
  static const String link = 'link';
  static const String cameraAlt = 'camera_alt';

  // AI/智能类
  static const String smartToy = 'smart_toy';
  static const String smartToyOutlined = 'smart_toy_outlined';
  static const String autoAwesome = 'auto_awesome';
  static const String autoFixHigh = 'auto_fix_high';
  static const String autoStories = 'auto_stories';
  static const String psychology = 'psychology';
  static const String psychologyOutlined = 'psychology_outlined';
  static const String hub = 'hub';
  static const String memory = 'memory';

  // 设置/工具类
  static const String key = 'key';
  static const String category = 'category';
  static const String bolt = 'bolt';
  static const String boltOutlined = 'bolt_outlined';
  static const String scienceOutlined = 'science_outlined';
  static const String cleaningServices = 'cleaning_services';
  static const String documentScanner = 'document_scanner';
  static const String documentScannerOutlined = 'document_scanner_outlined';

  // 语言/搜索类
  static const String language = 'language';
  static const String languageOutlined = 'language_outlined';
  static const String travelExplore = 'travel_explore';

  // 安全类
  static const String shieldOutlined = 'shield_outlined';
  static const String security = 'security';
  static const String lockOutline = 'lock_outline';
  static const String storageOutlined = 'storage_outlined';

  // 外观/主题类
  static const String palette = 'palette';
  static const String paletteOutlined = 'palette_outlined';
  static const String wallpaper = 'wallpaper';
  static const String wallpaperOutlined = 'wallpaper_outlined';
  static const String face = 'face';
  static const String faceOutlined = 'face_outlined';
  static const String animationOutlined = 'animation_outlined';
  static const String nightlight = 'nightlight';
  static const String wbSunny = 'wb_sunny';
  static const String gradient = 'gradient';
  static const String water = 'water';
  static const String eco = 'eco';
  static const String localFlorist = 'local_florist';
  static const String localFireDepartment = 'local_fire_department';
  static const String cloud = 'cloud';
  static const String star = 'star';
  static const String spa = 'spa';
  static const String coffee = 'coffee';

  // 数据/文件类
  static const String textFields = 'text_fields';
  static const String dataUsage = 'data_usage';
  static const String preview = 'preview';
  static const String downloadOutlined = 'download_outlined';
  static const String uploadOutlined = 'upload_outlined';
  static const String cloudDownload = 'cloud_download';
  static const String cloudUpload = 'cloud_upload';
  static const String cloudUploadOutlined = 'cloud_upload_outlined';
  static const String cloudOffOutlined = 'cloud_off_outlined';
  static const String folderOpen = 'folder_open';
  static const String folderOutlined = 'folder_outlined';
  static const String folderSpecial = 'folder_special';
  static const String fileOpen = 'file_open';
  static const String description = 'description';
  static const String descriptionOutlined = 'description_outlined';

  // 状态/提示类
  static const String infoOutline = 'info_outline';
  static const String errorOutline = 'error_outline';
  static const String warningAmber = 'warning_amber';
  static const String warningAmberOutlined = 'warning_amber_outlined';
  static const String warningAmberRounded = 'warning_amber_rounded';
  static const String visibility = 'visibility';
  static const String visibilityOff = 'visibility_off';

  // 其他
  static const String person = 'person';
  static const String home = 'home';
  static const String rocketLaunch = 'rocket_launch';
  static const String newspaperOutlined = 'newspaper_outlined';
  static const String accountTreeOutlined = 'account_tree_outlined';
  static const String stream = 'stream';
  static const String sync = 'sync';
  static const String filterAlt = 'filter_alt';
  static const String compress = 'compress';
  static const String cropSquare = 'crop_square';
  static const String touchApp = 'touch_app';
  static const String timelapse = 'timelapse';
  static const String timer = 'timer';
  static const String playArrow = 'play_arrow';
  static const String skipNext = 'skip_next';
  static const String balance = 'balance';
  static const String dataObject = 'data_object';
}
