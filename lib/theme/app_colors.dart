// 做什么：暗色主题色板常量集合（纯静态值，无 Flutter 依赖耦合）。
// 为什么这样做：与设计画布（design/preview.html）的 CSS 变量一一对应，
// 集中管理避免颜色散落各处，便于整体调色。风格参考 Trae Work 的暗色语言：
// 近黑底 + 紫罗兰主色 + 青绿状态色，弱边框、分层 surface。

import 'package:flutter/material.dart';

/// 暗色色板（Trae Work 风格）
///
/// 所有颜色均为不透明或半透明常量。surface 系列用于分层背景，
/// accent 用于主操作与高亮，teal 用于流式/在线状态，rose 用于停止/危险。
class AppColors {
  AppColors._();

  // ── 背景与表面 ──
  /// 主背景：近黑（带极弱蓝紫倾向）
  static const Color background = Color(0xFF0A0A0C);

  /// 侧边栏背景：略高于主背景
  static const Color sidebar = Color(0xFF0E0E11);

  /// 卡片/输入框表面
  static const Color surface = Color(0xFF131318);

  /// 表面第二层（悬浮、激活态）
  static const Color surface2 = Color(0xFF191920);

  /// 表面第三层（开关轨、禁用态）
  static const Color surface3 = Color(0xFF202029);

  // ── 边框 ──
  static const Color border = Color(0x14FFFFFF); // rgba(255,255,255,0.06)
  static const Color borderStrong = Color(0x1AFFFFFF); // rgba(255,255,255,0.10)

  // ── 文本 ──
  static const Color textPrimary = Color(0xFFECECEE);
  static const Color textSecondary = Color(0xFF9A9AA6);
  static const Color textTertiary = Color(0xFF5C5C68);

  // ── 主色：紫罗兰 ──
  static const Color accent = Color(0xFF8B7CFF);
  static const Color accent2 = Color(0xFFB4A0FF);
  static const Color accentSoft = Color(0x248B7CFF); // 0.14 alpha
  static const Color accentOn = Color(0xFF0A0A0C); // 主色按钮上的文字

  // ── 状态色 ──
  static const Color teal = Color(0xFF4ADE9D); // 在线 / 流式
  static const Color tealSoft = Color(0x1F4ADE9D);
  static const Color amber = Color(0xFFF5B454);
  static const Color rose = Color(0xFFFF7A8A); // 停止 / 危险

  // ── 用户/AI 头像底色 ──
  static const Color userAvatarBg = surface2;
  static const Color aiAvatarBg = Color(0x2A8B7CFF);

  // ── 派生渐变 ──
  static const LinearGradient accentGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [accent, accent2],
  );

  static const LinearGradient logoGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [accent, accent2],
  );

  /// 标识色：根据 serviceId 返回对应厂商主色（用于头像底色），未知则回退主色。
  /// 为什么这样做：让会话列表/AI 头像能直观区分服务商，复用品牌色更友好。
  static Color serviceColor(String serviceId) {
    return switch (serviceId) {
      'openai' => const Color(0xFF10A37F),
      'deepseek' => const Color(0xFF4D6BFE),
      'gemini' => const Color(0xFF34A853),
      'zhipu' => const Color(0xFF615CED),
      'moonshot' => const Color(0xFFFF6A00),
      'tongyi' => const Color(0xFF615CED),
      'doubao' => const Color(0xFF0052FF),
      'hunyuan' => const Color(0xFF0053E0),
      'minimax' => const Color(0xFFFF4D4F),
      'stepfun' => const Color(0xFF1A66FF),
      'baichuan' => const Color(0xFFFF7A45),
      'spark' => const Color(0xFFE63946),
      'yi' => const Color(0xFF3D5AFE),
      'ernie' => const Color(0xFF2932E1),
      'huggingface' => const Color(0xFFFFD21E),
      'guiji' => const Color(0xFF8B7CFF),
      _ => accent,
    };
  }
}
