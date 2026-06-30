import 'dart:convert';

import 'package:flutter/material.dart';

import '../core/logger/app_logger.dart';
import '../models/message.dart';
import '../services/storage_service.dart';

enum DuplicateStrategy { skip, keepBoth, overwrite }

class ImportResult {
  final int totalMessages;
  final int importedCount;
  final int skippedCount;
  final int overwrittenCount;

  ImportResult({
    required this.totalMessages,
    required this.importedCount,
    required this.skippedCount,
    required this.overwrittenCount,
  });
}

class BackupProvider extends ChangeNotifier {
  final StorageService _storageService;

  bool _isExporting = false;
  bool _isImporting = false;
  String? _error;
  bool _disposed = false;

  BackupProvider({required StorageService storageService})
    : _storageService = storageService;

  bool get isExporting => _isExporting;
  bool get isImporting => _isImporting;
  String? get error => _error;
  bool get isReady => _storageService.isInitialized;

  Future<String?> exportBackup() async {
    if (!isReady) {
      _error = '存储服务未就绪，无法导出';
      notifyListeners();
      return null;
    }

    _isExporting = true;
    _error = null;
    notifyListeners();

    try {
      AppLogger.i('[BackupProvider] 开始导出备份');
      final filePath = await _storageService.exportBackup();
      AppLogger.i('[BackupProvider] 导出成功: $filePath');
      return filePath;
    } on Exception catch (e) {
      // N5: 只捕获 Exception，让 Error（内存溢出等）向上传播不吞掉
      AppLogger.e('[BackupProvider] 导出失败: $e');
      _error = '导出失败';
      notifyListeners();
      return null;
    } finally {
      _isExporting = false;
      notifyListeners();
    }
  }

  Future<int?> importBackup(String filePath) async {
    if (!isReady) {
      _error = '存储服务未就绪，无法导入';
      notifyListeners();
      return null;
    }

    _isImporting = true;
    _error = null;
    notifyListeners();

    try {
      AppLogger.i('[BackupProvider] 开始导入备份: $filePath');
      final count = await _storageService.importBackup(filePath);
      AppLogger.i('[BackupProvider] 导入成功，共 $count 条记录');
      return count;
    } on Exception catch (e) {
      // N5: 只捕获 Exception，让 Error（内存溢出等）向上传播不吞掉
      AppLogger.e('[BackupProvider] 导入失败: $e');
      _error = '导入失败';
      notifyListeners();
      return null;
    } finally {
      _isImporting = false;
      notifyListeners();
    }
  }

  Future<ImportResult> importWithDedup({
    required String conversationId,
    required List<Message> newMessages,
    required DuplicateStrategy strategy,
  }) async {
    if (!isReady) {
      _error = '存储服务未就绪';
      notifyListeners();
      return ImportResult(
        totalMessages: newMessages.length,
        importedCount: 0,
        skippedCount: newMessages.length,
        overwrittenCount: 0,
      );
    }

    _isImporting = true;
    _error = null;
    notifyListeners();

    try {
      final existingMessages = _storageService.getMessages(conversationId);
      final existingHashes = <String>{};

      for (final msg in existingMessages) {
        existingHashes.add(_messageHash(msg));
      }

      int importedCount = 0;
      int skippedCount = 0;
      int overwrittenCount = 0;
      final resultMessages = List<Message>.from(existingMessages);

      for (final msg in newMessages) {
        final hash = _messageHash(msg);

        if (existingHashes.contains(hash)) {
          switch (strategy) {
            case DuplicateStrategy.skip:
              skippedCount++;
            case DuplicateStrategy.keepBoth:
              resultMessages.add(msg);
              importedCount++;
            case DuplicateStrategy.overwrite:
              final idx = resultMessages.indexWhere(
                (m) => _messageHash(m) == hash,
              );
              if (idx != -1) {
                resultMessages[idx] = msg;
                overwrittenCount++;
              }
          }
        } else {
          resultMessages.add(msg);
          importedCount++;
        }
      }

      final success = await _storageService.saveMessagesAsync(
        conversationId,
        resultMessages,
      );

      if (!success) {
        _error = '保存消息失败';
        notifyListeners();
      }

      AppLogger.i(
        '[BackupProvider] 导入完成: 总计 ${newMessages.length}, '
        '导入 $importedCount, 跳过 $skippedCount, 覆盖 $overwrittenCount',
      );

      return ImportResult(
        totalMessages: newMessages.length,
        importedCount: importedCount,
        skippedCount: skippedCount,
        overwrittenCount: overwrittenCount,
      );
    } on Exception catch (e) {
      // N5: 只捕获 Exception，让 Error（内存溢出等）向上传播不吞掉
      AppLogger.e('[BackupProvider] 去重导入失败: $e');
      _error = '导入失败';
      notifyListeners();
      return ImportResult(
        totalMessages: newMessages.length,
        importedCount: 0,
        skippedCount: newMessages.length,
        overwrittenCount: 0,
      );
    } finally {
      _isImporting = false;
      notifyListeners();
    }
  }

  String _messageHash(Message msg) {
    final timestamp = msg.timestamp?.millisecondsSinceEpoch ?? 0;
    final content = msg.content.length > 200
        ? msg.content.substring(0, 200)
        : msg.content;
    final input = '${msg.role}:$timestamp:$content';
    final bytes = utf8.encode(input);
    var hash = 0xcbf29ce484222325;
    for (final b in bytes) {
      hash ^= b;
      hash *= 0x100000001b3;
      hash = hash & 0x7FFFFFFFFFFFFFFF;
    }
    return hash.toRadixString(36);
  }

  List<Message> parseBackupContent(String content) {
    // 空安全：jsonDecode 未 try-catch 会导致非合法 JSON 时崩溃
    // 记录日志后 rethrow，让调用方显示用户友好的错误提示
    dynamic data;
    try {
      data = jsonDecode(content);
    } on FormatException catch (e) {
      AppLogger.e('[BackupProvider] 备份文件 JSON 格式错误: $e');
      rethrow;
    }
    List<Message>? messages;

    if (data is List) {
      messages = data
          .map((e) => Message.fromJson(e as Map<String, dynamic>))
          .toList();
    } else if (data is Map) {
      for (final key in ['messages', 'chat', 'records', 'data']) {
        if (data.containsKey(key) && data[key] is List) {
          messages = (data[key] as List)
              .map((e) => Message.fromJson(e as Map<String, dynamic>))
              .toList();
          break;
        }
      }
    }

    return messages ?? [];
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
