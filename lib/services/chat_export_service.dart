import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../core/logger/app_logger.dart';
import '../models/conversation.dart';
import '../models/message.dart';

enum ExportFormat { json, markdown, html }

class ChatExportService {
  static Future<Directory?> _getExportDir() async {
    try {
      if (Platform.isAndroid) {
        final externalDir = await getExternalStorageDirectory();
        if (externalDir != null) {
          return Directory('${externalDir.path}/XinglingChat');
        }
      }
      if (Platform.isIOS) {
        final externalDir = await getApplicationDocumentsDirectory();
        return Directory('${externalDir.path}/XinglingChat');
      }
      final dir = await getApplicationDocumentsDirectory();
      return Directory('${dir.path}/XinglingChat');
    } catch (e) {
      AppLogger.e('[ChatExportService] 获取导出目录失败: $e');
      return null;
    }
  }

  Future<String?> exportConversation({
    required Conversation conversation,
    required List<Message> messages,
    required ExportFormat format,
    bool share = false,
  }) async {
    try {
      final exportDir = await _getExportDir();
      if (exportDir == null) {
        AppLogger.e('[ChatExportService] 无法获取导出目录');
        return null;
      }

      if (!exportDir.existsSync()) {
        exportDir.createSync(recursive: true);
      }

      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final sanitizedName = conversation.name.replaceAll(
        RegExp(r'[^\w\u4e00-\u9fff]'),
        '_',
      );

      String filePath;
      String content;

      switch (format) {
        case ExportFormat.json:
          filePath =
              '${exportDir.path}${Platform.pathSeparator}${sanitizedName}_$timestamp.json';
          content = _toJson(conversation, messages);
        case ExportFormat.markdown:
          filePath =
              '${exportDir.path}${Platform.pathSeparator}${sanitizedName}_$timestamp.md';
          content = _toMarkdown(conversation, messages);
        case ExportFormat.html:
          filePath =
              '${exportDir.path}${Platform.pathSeparator}${sanitizedName}_$timestamp.html';
          content = _toHtml(conversation, messages);
      }

      final file = File(filePath);
      await file.writeAsString(content);

      AppLogger.i('[ChatExportService] 导出成功: $filePath');

      if (share) {
        await Share.shareXFiles([
          XFile(filePath),
        ], subject: '杏铃聊天记录 - ${conversation.name}');
        return filePath;
      }

      return filePath;
    } catch (e) {
      AppLogger.e('[ChatExportService] 导出失败: $e');
      return null;
    }
  }

  String _toJson(Conversation conversation, List<Message> messages) {
    final data = {
      'conversation': {
        'id': conversation.id,
        'name': conversation.name,
        'systemPrompt': conversation.systemPrompt,
        'createdAt': conversation.createdAt.toIso8601String(),
        'updatedAt': conversation.updatedAt.toIso8601String(),
      },
      'messages': messages.map((m) => m.toJson()).toList(),
      'exportedAt': DateTime.now().toIso8601String(),
      'format': 'xingling_chat_v1',
    };
    return const JsonEncoder.withIndent('  ').convert(data);
  }

  String _toMarkdown(Conversation conversation, List<Message> messages) {
    final buffer = StringBuffer();

    buffer.writeln('# ${conversation.name}');
    buffer.writeln();
    buffer.writeln(
      '> 导出时间: ${_formatDateTime(DateTime.now())} | '
      '消息数: ${messages.length}',
    );
    buffer.writeln();
    buffer.writeln('---');
    buffer.writeln();

    for (final msg in messages) {
      final role = msg.role == 'user' ? '用户' : '助手';
      final time = msg.timestamp != null ? _formatDateTime(msg.timestamp!) : '';

      buffer.writeln('### $role${time.isNotEmpty ? ' · $time' : ''}');
      buffer.writeln();
      buffer.writeln(msg.content);
      buffer.writeln();

      if (msg.reasoningContent != null && msg.reasoningContent!.isNotEmpty) {
        buffer.writeln('<details>');
        buffer.writeln('<summary>思考过程</summary>');
        buffer.writeln();
        buffer.writeln(msg.reasoningContent!);
        buffer.writeln();
        buffer.writeln('</details>');
        buffer.writeln();
      }

      buffer.writeln('---');
      buffer.writeln();
    }

    return buffer.toString();
  }

  String _toHtml(Conversation conversation, List<Message> messages) {
    final buffer = StringBuffer();

    buffer.writeln('<!DOCTYPE html>');
    buffer.writeln('<html lang="zh-CN">');
    buffer.writeln('<head>');
    buffer.writeln('<meta charset="UTF-8">');
    buffer.writeln(
      '<meta name="viewport" content="width=device-width, initial-scale=1.0">',
    );
    buffer.writeln('<title>${_escapeHtml(conversation.name)} - 杏铃聊天记录</title>');
    buffer.writeln('<style>');
    buffer.writeln(_htmlCss());
    buffer.writeln('</style>');
    buffer.writeln('</head>');
    buffer.writeln('<body>');
    buffer.writeln('<div class="container">');
    buffer.writeln('<h1>${_escapeHtml(conversation.name)}</h1>');
    buffer.writeln(
      '<p class="meta">导出时间: ${_formatDateTime(DateTime.now())} | '
      '消息数: ${messages.length}</p>',
    );

    for (final msg in messages) {
      final isUser = msg.role == 'user';
      final role = isUser ? '用户' : '助手';
      final time = msg.timestamp != null ? _formatDateTime(msg.timestamp!) : '';
      final bubbleClass = isUser ? 'bubble-user' : 'bubble-assistant';

      buffer.writeln('<div class="$bubbleClass">');
      buffer.writeln(
        '<div class="role">${isUser ? "" : ""} $role'
        '${time.isNotEmpty ? ' · $time' : ''}</div>',
      );

      if (msg.reasoningContent != null && msg.reasoningContent!.isNotEmpty) {
        buffer.writeln('<details class="reasoning">');
        buffer.writeln('<summary>思考过程</summary>');
        buffer.writeln(
          '<div class="reasoning-content">'
          '${_escapeHtml(msg.reasoningContent!)}'
          '</div>',
        );
        buffer.writeln('</details>');
      }

      buffer.writeln('<div class="content">${_escapeHtml(msg.content)}</div>');
      buffer.writeln('</div>');
    }

    buffer.writeln('</div>');
    buffer.writeln('</body>');
    buffer.writeln('</html>');

    return buffer.toString();
  }

  String _htmlCss() {
    return '''
* { margin: 0; padding: 0; box-sizing: border-box; }
body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif; background: #f5f5f5; color: #333; }
.container { max-width: 800px; margin: 0 auto; padding: 24px 16px; }
h1 { font-size: 24px; margin-bottom: 8px; }
.meta { color: #888; font-size: 14px; margin-bottom: 24px; }
.bubble-user { background: #e3f2fd; border-radius: 16px 16px 4px 16px; padding: 12px 16px; margin-bottom: 12px; max-width: 80%; margin-left: auto; }
.bubble-assistant { background: #fff; border-radius: 16px 16px 16px 4px; padding: 12px 16px; margin-bottom: 12px; max-width: 80%; box-shadow: 0 1px 3px rgba(0,0,0,0.1); }
.role { font-size: 12px; color: #888; margin-bottom: 6px; }
.content { white-space: pre-wrap; word-break: break-word; line-height: 1.6; font-size: 15px; }
.reasoning { margin-bottom: 8px; }
.reasoning summary { cursor: pointer; font-size: 13px; color: #666; }
.reasoning-content { padding: 8px; margin-top: 6px; background: #f9f9f9; border-radius: 8px; font-size: 13px; color: #666; white-space: pre-wrap; }
''';
  }

  String _formatDateTime(DateTime dt) {
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-'
        '${dt.day.toString().padLeft(2, '0')} '
        '${dt.hour.toString().padLeft(2, '0')}:'
        '${dt.minute.toString().padLeft(2, '0')}';
  }

  String _escapeHtml(String text) {
    return text
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&#39;');
  }
}
