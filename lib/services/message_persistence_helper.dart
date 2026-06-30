import '../core/logger/app_logger.dart';
import '../models/message.dart';
import 'storage_service.dart';

/// 消息持久化辅助类
///
/// 做什么：保存消息到存储，失败时记录状态并延迟 2s 重试一次。
/// 为什么这样做：从 ChatProvider God Class 抽出（P2 #14），让保存+重试逻辑独立可测。
///
/// 设计说明：
/// - [_saveFailed] 是"曾出错"的只读信号，不引入新职责。
/// - 重试仅一次，避免无限重试占用资源。
/// - 重试用的 [messages] 是保存时的快照引用，若期间用户又发了新消息，
///   _messages 已变但重试仍用旧快照——这是可接受的，因为新消息会触发新的保存调用覆盖文件。
class MessagePersistenceHelper {
  final StorageService _storageService;

  // P1 #7: 记录消息保存是否曾失败，供 UI 可选展示提示。
  bool _saveFailed = false;

  MessagePersistenceHelper(this._storageService);

  /// 是否曾出现保存失败（只读信号，供 UI 可选展示提示）。
  bool get hasSaveError => _saveFailed;

  /// 保存消息，失败时延迟 2s 重试一次。
  ///
  /// 流程：
  /// 1. 存储未就绪 → 记录失败并返回
  /// 2. 首次保存失败 → 记录失败 + 延迟 2s 重试一次
  /// 3. 重试结果仅打日志，不再触发新的重试
  void saveMessagesWithRetry(String convId, List<Message> messages) {
    if (!_storageService.isInitialized) {
      AppLogger.e('[MessagePersistence] 存储未就绪，跳过保存消息 convId=$convId');
      _saveFailed = true;
      return;
    }
    _storageService.saveMessagesAsync(convId, messages).then((ok) {
      if (ok) {
        AppLogger.d(
          '[MessagePersistence] 保存消息成功 convId=$convId, 消息数: ${messages.length}',
        );
        return;
      }
      AppLogger.e(
        '[MessagePersistence] 保存消息失败 convId=$convId, 消息数: ${messages.length}',
      );
      _saveFailed = true;
      // 延迟 2s 重试一次：给底层 IO 一点恢复时间，避免立即重试再次失败
      Future.delayed(const Duration(seconds: 2), () {
        if (!_storageService.isInitialized) return;
        _storageService.saveMessagesAsync(convId, messages).then((retryOk) {
          if (retryOk) {
            AppLogger.i('[MessagePersistence] 保存消息重试成功 convId=$convId');
          } else {
            AppLogger.e('[MessagePersistence] 保存消息重试仍失败 convId=$convId');
          }
        });
      });
    });
  }
}
