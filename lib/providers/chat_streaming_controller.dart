import 'dart:async';

/// 流式输出状态控制器
///
/// 做什么：管理 AI 流式响应的状态（内容、reasoning、取消标志）和 notify 节流。
/// 为什么这样做：从 ChatProvider God Class 抽出（P2 #14），让流式状态管理独立可测。
///
/// 设计说明：
/// - 不继承 ChangeNotifier，通过 [onNotify] 回调通知调用方（ChatProvider）触发 UI 更新。
/// - 节流策略：100ms 间隔 + 8 字符阈值，长文本场景减少约 80% 通知，肉眼仍流畅。
class ChatStreamingController {
  /// 通知回调（通常传入 ChatProvider 的 notifyListeners）。
  final void Function() onNotify;

  bool _isStreaming = false;
  String _streamingContent = '';
  String _streamingReasoning = '';
  bool _isCancelled = false;
  Timer? _streamNotifyTimer;
  bool _streamNotifyPending = false;
  int _lastNotifiedStreamLength = 0;

  ChatStreamingController({required this.onNotify});

  // ── 只读 getters ──
  bool get isStreaming => _isStreaming;
  bool get isCancelled => _isCancelled;
  String get streamingContent => _streamingContent;
  String get streamingReasoning => _streamingReasoning;
  bool get streamingHasReasoning => _streamingReasoning.isNotEmpty;

  // ── 状态变更 ──

  /// 开始流式：重置所有状态，标记 isStreaming=true。
  void startStream() {
    _isStreaming = true;
    _isCancelled = false;
    _streamingContent = '';
    _streamingReasoning = '';
    _lastNotifiedStreamLength = 0;
  }

  /// 追加流式内容。
  void appendContent(String content) {
    _streamingContent += content;
  }

  /// 追加流式 reasoning 内容。
  void appendReasoning(String reasoning) {
    _streamingReasoning += reasoning;
  }

  /// 标记取消（用户点击停止）。
  void markCancelled() {
    _isCancelled = true;
  }

  /// 重置取消标志（清理后重新允许发送）。
  void resetCancelled() {
    _isCancelled = false;
  }

  /// 结束流式并清空内容状态（isCancelled 由调用方按需 resetCancelled）。
  void finishStream() {
    _isStreaming = false;
    _streamingContent = '';
    _streamingReasoning = '';
  }

  // ── 节流通知 ──

  /// 节流通知：100ms 间隔 + 8 字符阈值，减少 notifyListeners 次数。
  ///
  /// 为什么这样做：原 50ms 节流最高 20 次/秒 notifyListeners，
  /// 长文本场景 flutter_markdown rebuild 可达 10-30ms，主线程繁忙。
  void throttledNotify() {
    final currentLen = _streamingContent.length;
    // 首次（_lastNotifiedStreamLength == 0）或内容增长超 8 字符才考虑通知。
    final shouldNotify =
        _lastNotifiedStreamLength == 0 ||
        currentLen - _lastNotifiedStreamLength >= 8;
    if (!shouldNotify) return;

    if (_streamNotifyTimer?.isActive ?? false) {
      _streamNotifyPending = true;
      return;
    }
    onNotify();
    _lastNotifiedStreamLength = currentLen;
    _streamNotifyTimer = Timer(const Duration(milliseconds: 100), () {
      if (_streamNotifyPending) {
        _streamNotifyPending = false;
        onNotify();
        _lastNotifiedStreamLength = _streamingContent.length;
      }
      _streamNotifyTimer = null;
    });
  }

  /// 取消节流 timer 并重置节流状态。
  void cancelNotify() {
    _streamNotifyTimer?.cancel();
    _streamNotifyTimer = null;
    _streamNotifyPending = false;
    _lastNotifiedStreamLength = 0;
  }

  /// 释放资源（取消 timer）。
  void dispose() {
    cancelNotify();
  }
}
