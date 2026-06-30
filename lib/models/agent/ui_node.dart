/// UI 节点模型（无障碍树节点）
///
/// 对应原生 AccessibilityNodeInfo 的精简表示。
/// 为什么这样做：原生节点对象无法跨 MethodChannel 传递，
/// 转为纯数据结构后便于 Dart 侧消费和 LLM 理解。
class UiNode {
  /// 节点 ID（resourceId，如 "com.tencent.mm:id/chat_input"）
  /// 为什么可空：部分节点没有 resourceId（纯布局容器）
  final String? id;

  /// 类名（如 "android.widget.EditText"）
  /// 为什么保留：LLM 可根据类名判断节点类型（输入框/按钮/列表）
  final String? className;

  /// 节点文本
  final String text;

  /// 内容描述（contentDescription，用于无障碍朗读）
  final String contentDescription;

  /// 屏幕坐标 [left, top, right, bottom]
  /// 为什么用 List 不用自定义 Rect：减少模型类数量，序列化简单
  final List<int> bounds;

  /// 是否可点击
  final bool clickable;

  /// 是否可聚焦
  final bool focusable;

  /// 是否启用
  final bool enabled;

  /// 是否可见
  final bool visibleToUser;

  /// 是否密码框
  /// 为什么单独标记：密码框需要特殊处理（脱敏、强制 ACTION_SET_TEXT）
  final bool isPassword;

  /// 在树中的深度（根节点为 0）
  final int depth;

  /// 子节点
  final List<UiNode> children;

  const UiNode({
    this.id,
    this.className,
    required this.text,
    required this.contentDescription,
    required this.bounds,
    this.clickable = false,
    this.focusable = false,
    this.enabled = true,
    this.visibleToUser = true,
    this.isPassword = false,
    this.depth = 0,
    this.children = const [],
  });

  /// 从原生返回的 JSON 解析
  /// 为什么这样做：原生侧将 AccessibilityNodeInfo 树转为 JSON 传递
  factory UiNode.fromJson(Map<String, dynamic> json) {
    final boundsRaw = json['bounds'];
    return UiNode(
      id: json['id'] as String?,
      className: json['className'] as String?,
      text: (json['text'] as String?) ?? '',
      contentDescription: (json['contentDescription'] as String?) ?? '',
      bounds: boundsRaw is List
          ? boundsRaw.map((e) => (e as num).toInt()).toList()
          : const [0, 0, 0, 0],
      clickable: (json['clickable'] as bool?) ?? false,
      focusable: (json['focusable'] as bool?) ?? false,
      enabled: (json['enabled'] as bool?) ?? true,
      visibleToUser: (json['visibleToUser'] as bool?) ?? true,
      isPassword: (json['isPassword'] as bool?) ?? false,
      depth: (json['depth'] as num?)?.toInt() ?? 0,
      children:
          (json['children'] as List?)
              ?.map((e) => UiNode.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [],
    );
  }

  /// 节点中心点坐标（用于点击）
  /// 为什么这样做：LLM 决策点击时用中心点最自然
  (int, int) get center {
    if (bounds.length < 4) return (0, 0);
    return ((bounds[0] + bounds[2]) ~/ 2, (bounds[1] + bounds[3]) ~/ 2);
  }

  /// 是否包含敏感文本（用于截图脱敏判断）
  /// 为什么这样做：密码框和含"验证码/密码/token"的节点需要脱敏
  bool get isSensitive {
    if (isPassword) return true;
    final lower = text.toLowerCase();
    return lower.contains('密码') ||
        lower.contains('验证码') ||
        lower.contains('token') ||
        lower.contains('password') ||
        lower.contains('verification');
  }
}

/// UI 树（整个屏幕的节点集合 + 元信息）
class UiTree {
  /// 屏幕尺寸
  final int screenWidth;
  final int screenHeight;

  /// 当前前台 App 包名
  final String packageName;

  /// 根节点列表（通常只有一个，多窗口时有多个）
  final List<UiNode> roots;

  const UiTree({
    required this.screenWidth,
    required this.screenHeight,
    required this.packageName,
    required this.roots,
  });

  factory UiTree.fromJson(Map<String, dynamic> json) {
    final screenSize = json['screenSize'] as Map<String, dynamic>?;
    return UiTree(
      screenWidth: (screenSize?['width'] as num?)?.toInt() ?? 0,
      screenHeight: (screenSize?['height'] as num?)?.toInt() ?? 0,
      packageName: (json['package'] as String?) ?? '',
      roots:
          (json['nodes'] as List?)
              ?.map((e) => UiNode.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [],
    );
  }

  /// 可见节点总数（用于 fallback 判定）
  /// 为什么这样做：可见节点 < 5 时疑似自定义 Canvas，需 VLM fallback
  int get visibleNodeCount {
    int count = 0;
    void walk(UiNode node) {
      if (node.visibleToUser) count++;
      for (final child in node.children) {
        walk(child);
      }
    }

    for (final root in roots) {
      walk(root);
    }
    return count;
  }

  /// 是否需要 VLM fallback（按方案 6.3 规则）
  bool get needsVisionFallback {
    if (roots.isEmpty) return true;
    if (visibleNodeCount < 5) return true;
    return false;
  }
}
