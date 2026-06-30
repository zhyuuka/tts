class TokenEstimator {
  static const Map<String, int> _serviceContextLimits = {
    'openai': 1048576,
    'deepseek': 131072,
    'guiji': 131072,
    'zhipu': 128000,
    'moonshot': 131072,
    'doubao': 131072,
    'tongyi': 131072,
    'hunyuan': 128000,
    'minimax': 131072,
    'stepfun': 131072,
    'baichuan': 131072,
    'spark': 128000,
    'yi': 128000,
    'ernie': 131072,
    'gemini': 1048576,
    'huggingface': 131072,
    'custom': 1048576,
  };

  int estimateTokens(String text) {
    if (text.isEmpty) return 0;
    int cjkCount = 0;
    int otherCount = 0;
    for (var rune in text.runes) {
      // CJK 统一表意文字、扩展A、兼容表意、CJK标点、全角字符算 CJK。
      // 为什么这样做：这些字符在 tokenizer 中通常 1 字符 ≈ 1 token。
      // 原代码 rune > 0x7F 把所有非 ASCII（含代码符号 { } ; = > 和 emoji）
      // 都当 CJK 按 1.5 系数计算，严重高估代码文本的 token 数。
      if ((rune >= 0x4E00 && rune <= 0x9FFF) ||
          (rune >= 0x3400 && rune <= 0x4DBF) ||
          (rune >= 0x3000 && rune <= 0x303F) ||
          (rune >= 0xFF00 && rune <= 0xFFEF) ||
          (rune >= 0xF900 && rune <= 0xFAFF)) {
        cjkCount++;
      } else {
        otherCount++;
      }
    }
    // CJK 系数 1.0（GPT-4 中文约 0.6-1.5，国产模型更优约 0.5-1.0，取保守值），
    // 其他字符 0.25（英文约 4 字符/token）。避免高估导致提前截断上下文。
    return (cjkCount * 1.0 + otherCount * 0.25).ceil();
  }

  int estimateContextTokens(
    List<String> contents, {
    String streamingContent = '',
    String streamingReasoning = '',
  }) {
    int total = 0;
    for (final content in contents) {
      total += estimateTokens(content);
    }
    if (streamingContent.isNotEmpty) {
      total += estimateTokens(streamingContent);
    }
    if (streamingReasoning.isNotEmpty) {
      total += estimateTokens(streamingReasoning);
    }
    return total;
  }

  int maxContextTokens(String serviceId) {
    return _serviceContextLimits[serviceId] ?? 65536;
  }
}
