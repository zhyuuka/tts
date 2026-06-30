import '../../core/logger/app_logger.dart';

class InputSanitizer {
  static const int maxMessageLength = 10000;
  static const int maxConversationNameLength = 100;
  static const int maxSystemPromptLength = 5000;

  static final RegExp _controlCharsRegex = RegExp(
    r'[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]',
  );

  static final RegExp _rtlOverrideRegex = RegExp(
    r'[\u202A-\u202E\u2066-\u2069\u200F\u200E]',
  );

  static final RegExp _nullByteRegex = RegExp(r'\x00');

  static final RegExp _ansiEscapeRegex = RegExp(r'\x1B\[[0-9;]*[A-Za-z]');

  SanitizeResult sanitizeMessage(String input) {
    if (input.isEmpty) {
      return SanitizeResult(cleaned: input, warnings: []);
    }

    final warnings = <String>[];
    var result = input;

    if (_nullByteRegex.hasMatch(result)) {
      result = result.replaceAll(_nullByteRegex, '');
      warnings.add('移除了空字节');
    }

    if (_ansiEscapeRegex.hasMatch(result)) {
      result = result.replaceAll(_ansiEscapeRegex, '');
      warnings.add('移除了ANSI转义序列');
    }

    if (_controlCharsRegex.hasMatch(result)) {
      result = result.replaceAll(_controlCharsRegex, '');
      warnings.add('移除了控制字符');
    }

    if (_rtlOverrideRegex.hasMatch(result)) {
      result = result.replaceAll(_rtlOverrideRegex, '');
      warnings.add('移除了Unicode方向控制字符');
    }

    result = _normalizeLineEndings(result);

    result = _normalizeWhitespace(result);

    if (result.length > maxMessageLength) {
      result = result.substring(0, maxMessageLength);
      warnings.add('消息已截断至$maxMessageLength字符');
    }

    if (warnings.isNotEmpty) {
      AppLogger.i('[InputSanitizer] 清理结果: ${warnings.join(", ")}');
    }

    return SanitizeResult(cleaned: result, warnings: warnings);
  }

  SanitizeResult sanitizeConversationName(String input) {
    if (input.isEmpty) {
      return SanitizeResult(cleaned: input, warnings: []);
    }

    final warnings = <String>[];
    var result = input;

    result = result.replaceAll(_nullByteRegex, '');
    result = result.replaceAll(_ansiEscapeRegex, '');
    result = result.replaceAll(_controlCharsRegex, '');
    result = result.replaceAll(_rtlOverrideRegex, '');
    result = result.replaceAll(RegExp(r'[\r\n]'), ' ');
    result = result.trim();

    if (result.length > maxConversationNameLength) {
      result = result.substring(0, maxConversationNameLength);
      warnings.add('名称已截断至$maxConversationNameLength字符');
    }

    return SanitizeResult(cleaned: result, warnings: warnings);
  }

  SanitizeResult sanitizeSystemPrompt(String input) {
    if (input.isEmpty) {
      return SanitizeResult(cleaned: input, warnings: []);
    }

    final warnings = <String>[];
    var result = input;

    result = result.replaceAll(_nullByteRegex, '');
    result = result.replaceAll(_ansiEscapeRegex, '');
    result = result.replaceAll(_controlCharsRegex, '');

    if (result.length > maxSystemPromptLength) {
      result = result.substring(0, maxSystemPromptLength);
      warnings.add('提示词已截断至$maxSystemPromptLength字符');
    }

    return SanitizeResult(cleaned: result, warnings: warnings);
  }

  String sanitizeSseContent(String content) {
    var result = content;

    result = result.replaceAll(_nullByteRegex, '');
    result = result.replaceAll(_ansiEscapeRegex, '');
    result = result.replaceAll(_controlCharsRegex, '');

    result = result.replaceAll(
      RegExp(r'<script[^>]*>.*?</script>', dotAll: true),
      '',
    );
    result = result.replaceAll(
      RegExp(r'<iframe[^>]*>.*?</iframe>', dotAll: true),
      '',
    );
    result = result.replaceAll(
      RegExp(r'javascript:', caseSensitive: false),
      '',
    );
    result = result.replaceAll(RegExp(r'on\w+\s*=', caseSensitive: false), '');

    return result;
  }

  bool containsSuspiciousPatterns(String input) {
    final suspiciousPatterns = [
      RegExp(r'ignore\s+(previous|all)\s+instructions', caseSensitive: false),
      RegExp(r'system\s*:\s*you\s+are', caseSensitive: false),
      RegExp(r'pretend\s+(you\s+are|to\s+be)', caseSensitive: false),
      RegExp(r'jailbreak', caseSensitive: false),
      RegExp(r'DAN\s+mode', caseSensitive: false),
    ];

    for (final pattern in suspiciousPatterns) {
      if (pattern.hasMatch(input)) {
        AppLogger.w('[InputSanitizer] 检测到可疑模式: ${pattern.pattern}');
        return true;
      }
    }

    return false;
  }

  /// 清理来自外部搜索结果（title/snippet）的不可信内容（P1 #13）。
  ///
  /// 为什么需要它：搜索结果来自互联网，直接拼入 System 消息会带来两类风险：
  /// 1. 提示词注入——结果里可能含"忽略以上指令"等操纵模型的文本；
  /// 2. XSS / 脚本标记——title/snippet 可能含 <script>、javascript: 等片段。
  ///
  /// 处理策略（保守、不破坏正常文本）：
  /// - 去除控制字符、空字节、ANSI 转义、Unicode 方向控制（复用既有正则）。
  /// - 去除 <script>/<iframe>/javascript:/onXxx= 等 HTML/脚本片段（复用 [sanitizeSseContent]）。
  /// - 对"提示词注入"模式做**中和**而非删除：把可疑关键词打上标记，
  ///   使其作为字面事实被引用，而非作为指令被执行。直接删除会丢失信息，
  ///   且攻击者可用变体绕过；打标更稳健，并配合外层分隔块文案双重防护。
  /// - 截断到 [maxLength]，防止单条结果过长。
  String sanitizeSearchContent(String input, {int maxLength = 500}) {
    if (input.isEmpty) return input;

    var result = input;
    result = result.replaceAll(_nullByteRegex, '');
    result = result.replaceAll(_ansiEscapeRegex, '');
    result = result.replaceAll(_controlCharsRegex, '');
    result = result.replaceAll(_rtlOverrideRegex, '');

    // 复用 SSE 内容清理逻辑（去 script/iframe/js:/onXxx=）
    result = sanitizeSseContent(result);

    // 中和提示词注入：把"ignore previous instructions"等模式标记为引用文本。
    // 例如 "ignore previous instructions" → "[引用文本: ignore previous instructions]"，
    // 模型会将其当作要描述的对象而非要执行的指令。这是纵深防御的一层，
    // _injectSearchContext 还会用分隔块 + 文案明确告诉模型这是不可信外部数据。
    for (final pattern in _promptInjectionPatterns) {
      result = result.replaceAllMapped(pattern, (m) {
        AppLogger.w('[InputSanitizer] 中和搜索结果中的注入模式: ${m.group(0)}');
        return '[引用文本: ${m.group(0)}]';
      });
    }

    // 单行折叠，避免注入内容借助换行伪装成新的 system/user 轮次
    result = result.replaceAll(RegExp(r'[\r\n]+'), ' ').trim();

    if (result.length > maxLength) {
      result = '${result.substring(0, maxLength)}…';
    }

    return result;
  }

  /// 提示词注入模式（与 [containsSuspiciousPatterns] 一致，但用于中和而非检测）。
  static final List<RegExp> _promptInjectionPatterns = [
    RegExp(
      r'ignore\s+(previous|all|the\s+above)\s+instructions',
      caseSensitive: false,
    ),
    RegExp(
      r'disregard\s+(previous|all|the\s+above)\s+instructions',
      caseSensitive: false,
    ),
    RegExp(r'system\s*:\s*you\s+are', caseSensitive: false),
    RegExp(r'pretend\s+(you\s+are|to\s+be)', caseSensitive: false),
    RegExp(r'jailbreak', caseSensitive: false),
    RegExp(r'DAN\s+mode', caseSensitive: false),
    RegExp(r'<\|im_start\|>', caseSensitive: false),
    RegExp(r'<\|system\|>', caseSensitive: false),
  ];

  /// 轻量清理 URL 字段（仅去控制字符 + 空白），不做格式校验（格式校验由 UrlValidator 负责）。
  String sanitizeUrlField(String input) {
    if (input.isEmpty) return input;
    var result = input;
    result = result.replaceAll(_nullByteRegex, '');
    result = result.replaceAll(_controlCharsRegex, '');
    // URL 内不应含换行/空白（防 CRLF 注入到 header 或换行伪装）
    result = result.replaceAll(RegExp(r'[\r\n\t ]'), '');
    return result;
  }

  String _normalizeLineEndings(String text) {
    return text.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  }

  String _normalizeWhitespace(String text) {
    return text
        .replaceAll(RegExp(r'[ \t]+\n'), '\n')
        .replaceAll(RegExp(r'\n{4,}'), '\n\n\n');
  }
}

class SanitizeResult {
  final String cleaned;
  final List<String> warnings;

  const SanitizeResult({required this.cleaned, required this.warnings});

  bool get hasWarnings => warnings.isNotEmpty;
}
