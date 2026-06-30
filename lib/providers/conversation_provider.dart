import 'dart:async';

import 'package:flutter/material.dart';

import '../core/logger/app_logger.dart';
import '../models/conversation.dart';
import '../services/settings_service.dart';
import '../services/storage_service.dart';

class ConversationProvider extends ChangeNotifier {
  final StorageService _storageService;
  final SettingsService _settingsService;

  List<Conversation> _conversations = [];
  Conversation? _currentConversation;
  bool _disposed = false;

  ConversationProvider({
    required StorageService storageService,
    required SettingsService settingsService,
  }) : _storageService = storageService,
       _settingsService = settingsService;

  List<Conversation> get conversations => _conversations;
  Conversation? get currentConversation => _currentConversation;
  String? get currentConversationId => _currentConversation?.id;

  bool get _storageReady => _storageService.isInitialized;
  bool get _settingsReady => _settingsService.isInitialized;

  void loadFromStorage() {
    if (!_storageReady) return;
    // 使用 metadata 版本（剥离 base64），避免列表加载所有会话的大字段到内存。
    // 当前会话的 base64 由 ChatProvider.switchConversation 按需加载。
    _conversations = _storageService.getConversationsMetadata();
    notifyListeners();
  }

  void refreshConversations() {
    loadFromStorage();
  }

  void switchTo(String id) {
    if (_currentConversation?.id == id) return;

    var conv = _conversations.where((c) => c.id == id).firstOrNull;
    if (conv == null && _storageReady) {
      // 使用 metadata 版本（剥离 base64），避免列表加载所有会话的大字段。
      _conversations = _storageService.getConversationsMetadata();
      conv = _conversations.where((c) => c.id == id).firstOrNull;
    }

    if (conv != null) {
      _currentConversation = conv;
      if (_settingsReady) {
        // N6/N7: 同步函数中调用异步 setLastConversationId，用 unawaited + async IIFE + try-catch
        // 为什么不改 async：switchTo 被 ChatProvider 多处同步调用，改 async 连锁影响大
        // 为什么用 async IIFE 而非 catchError：catchError 的 onError 类型签名要求返回 bool，
        // 与 Future<void> 不匹配，会触发 body_might_complete_normally_catch_error warning。
        // async IIFE + try-catch 完全避免类型陷阱，且语义更清晰。
        unawaited(() async {
          try {
            await _settingsService.setLastConversationId(id);
          } catch (e) {
            AppLogger.e('[ConversationProvider] 保存最后会话 id 失败: $e');
          }
        }());
      }
      notifyListeners();
    }
  }

  /// 按需加载当前会话的外观（头像/壁纸 base64）并更新 _currentConversation。
  /// 为什么新增：loadFromStorage/switchTo 使用 metadata 版本（无 base64），
  /// 切换会话后需调用此方法加载当前会话的 base64 供 UI 渲染。
  /// 由 ChatProvider.switchConversation 在 switchTo 之后调用。
  Future<void> loadCurrentAppearanceAsync(String id) async {
    if (!_storageReady) return;
    if (_currentConversation?.id != id) return;

    final appearance = await _storageService.getConversationAppearanceAsync(id);
    // 仅当 base64 有值时更新（避免覆盖已通过 updateAppearance 设置的值）
    if (appearance.avatarBase64.isNotEmpty ||
        appearance.wallpaperBase64.isNotEmpty) {
      _currentConversation = _currentConversation!.copyWith(
        avatarBase64: appearance.avatarBase64,
        wallpaperBase64: appearance.wallpaperBase64,
      );
      notifyListeners();
    }
  }

  Future<Conversation> createAndSwitch(String name) async {
    if (!_storageReady) {
      final conv = Conversation(
        id: 'conv_${DateTime.now().millisecondsSinceEpoch}',
        name: name,
      );
      _conversations.insert(0, conv);
      _currentConversation = conv;
      notifyListeners();
      return conv;
    }

    final conv = await _storageService.createConversationAsync(name);
    if (conv != null) {
      _conversations.insert(0, conv);
      _currentConversation = conv;
      if (_settingsReady) {
        // N6: async 方法中直接 await，避免错误静默丢失
        await _settingsService.setLastConversationId(conv.id);
      }
      notifyListeners();
      return conv;
    }

    final fallback = Conversation(
      id: 'conv_${DateTime.now().millisecondsSinceEpoch}',
      name: name,
    );
    _conversations.insert(0, fallback);
    _currentConversation = fallback;
    notifyListeners();
    return fallback;
  }

  Future<bool> rename(String id, String newName) async {
    if (!_storageReady) return false;
    final ok = await _storageService.renameConversationAsync(id, newName);
    if (ok) {
      final index = _conversations.indexWhere((c) => c.id == id);
      if (index != -1) {
        _conversations[index] = _conversations[index].copyWith(
          name: newName,
          updatedAt: DateTime.now(),
        );
        if (_currentConversation?.id == id) {
          _currentConversation = _conversations[index];
        }
        notifyListeners();
      }
    }
    return ok;
  }

  Future<bool> setPrompt(String id, String prompt) async {
    if (!_storageReady) return false;
    final ok = await _storageService.setConversationPromptAsync(id, prompt);
    if (ok) {
      final index = _conversations.indexWhere((c) => c.id == id);
      if (index != -1) {
        _conversations[index] = _conversations[index].copyWith(
          systemPrompt: prompt,
        );
        if (_currentConversation?.id == id) {
          _currentConversation = _conversations[index];
        }
        notifyListeners();
      }
    }
    return ok;
  }

  Future<bool> updateAppearance(
    String id, {
    String? avatarBase64,
    String? wallpaperBase64,
  }) async {
    if (!_storageReady) return false;
    final ok = await _storageService.updateConversationAppearanceAsync(
      id,
      avatarBase64: avatarBase64,
      wallpaperBase64: wallpaperBase64,
    );
    if (ok) {
      final index = _conversations.indexWhere((c) => c.id == id);
      if (index != -1) {
        _conversations[index] = _conversations[index].copyWith(
          avatarBase64: avatarBase64,
          wallpaperBase64: wallpaperBase64,
        );
        if (_currentConversation?.id == id) {
          _currentConversation = _conversations[index];
        }
        notifyListeners();
      }
    }
    return ok;
  }

  Future<bool> delete(String id) async {
    if (!_storageReady) return false;
    final ok = await _storageService.deleteConversationAsync(id);
    if (ok) {
      _conversations.removeWhere((c) => c.id == id);

      if (_currentConversation?.id == id) {
        if (_conversations.isNotEmpty) {
          _currentConversation = _conversations.first;
          if (_settingsReady) {
            // N6: async 方法中直接 await，避免错误静默丢失
            await _settingsService.setLastConversationId(
              _currentConversation!.id,
            );
          }
          // 切换到新会话后按需加载 base64
          await loadCurrentAppearanceAsync(_currentConversation!.id);
        } else {
          final newConv = await createAndSwitch('新的对话');
          _currentConversation = newConv;
        }
      }

      notifyListeners();
    }
    return ok;
  }

  @override
  void dispose() {
    // 防御 double dispose：getter 公开导致外部可能拿到引用误调 dispose。
    // 为什么这样做：ChangeNotifier 重复 dispose 会抛 "used after disposed" 断言。
    if (_disposed) return;
    _disposed = true;
    super.dispose();
  }
}
