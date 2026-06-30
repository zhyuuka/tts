import '../models/message.dart';
import 'settings_service.dart';
import 'token_estimator.dart';

/// Token 估算服务
///
/// 做什么：估算消息列表和流式内容的 token 数，以及当前服务商的最大上下文。
/// 为什么这样做：从 ChatProvider God Class 抽出（P2 #14），让 Token 估算逻辑独立可测。
class ChatTokenService {
  final TokenEstimator _tokenEstimator = TokenEstimator();
  final SettingsService _settingsService;

  ChatTokenService(this._settingsService);

  /// 估算当前上下文（消息列表 + 流式内容）的 token 数。
  ///
  /// [isStreaming] 为 true 时计入 [streamingContent]/[streamingReasoning]。
  int estimateContextTokens(
    List<Message> messages, {
    bool isStreaming = false,
    String streamingContent = '',
    String streamingReasoning = '',
  }) {
    final contents = <String>[];
    for (final msg in messages) {
      contents.add(msg.content);
      if (msg.reasoningContent != null) {
        contents.add(msg.reasoningContent!);
      }
    }
    return _tokenEstimator.estimateContextTokens(
      contents,
      streamingContent: isStreaming ? streamingContent : '',
      streamingReasoning: isStreaming ? streamingReasoning : '',
    );
  }

  /// 估算单段文本的 token 数。
  int estimateInputTokens(String text) => _tokenEstimator.estimateTokens(text);

  /// 当前服务商的最大上下文 token 数。
  /// Settings 未初始化时回退到 'doubao' 的限制。
  int get maxContextTokens {
    final serviceId = _settingsService.isInitialized
        ? _settingsService.getAiServiceId()
        : 'doubao';
    return _tokenEstimator.maxContextTokens(serviceId);
  }
}
