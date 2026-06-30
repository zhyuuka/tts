import 'dart:convert';

import '../models/attachment.dart';
import '../models/message.dart';
import '../util/attachment_bytes.dart';

/// 消息载荷转换器 - 提供通用的附件处理逻辑
///
/// 各个 AiService 可以继承此类或使用其静态方法
/// 来处理消息中的附件转换为 API 所需的格式
abstract class MessagePayloadConverter {
  static const int _maxTextChars = 120000;

  /// 从 PDF 原始字节中粗提取可读文本（无原生解析依赖）
  static String crudePdfText(List<int> bytes) {
    final s = String.fromCharCodes(
      bytes,
      0,
      bytes.length > 800000 ? 800000 : bytes.length,
    );
    final buf = StringBuffer();
    final re = RegExp(
      r'[\x20-\x7E\u4e00-\u9fff\u3000-\u303f\uff00-\uffef]{6,}',
    );
    for (final m in re.allMatches(s)) {
      final t = m.group(0);
      if (t != null && t.trim().length >= 6) buf.writeln(t.trim());
    }
    return buf.toString().trim();
  }

  static String truncate(String s) {
    if (s.length <= _maxTextChars) return s;
    return '${s.substring(0, _maxTextChars)}\n\n...[内容已截断]';
  }

  /// 加载附件字节并返回（带错误处理）
  static Future<List<int>?> loadAttachmentBytesSafe(Attachment a) async {
    try {
      return await loadAttachmentBytes(a);
    } catch (e) {
      return null;
    }
  }

  // ── OpenAI 兼容格式（多模态数组）──

  /// 将单条消息转换为 OpenAI 格式的 content（String 或 List）
  ///
  /// 支持的服务：OpenAI / 豆包 / 通义 / 混元 / HuggingFace 等
  static Future<Object> toOpenAiContent(Message m) async {
    if (m.role != 'user' || m.attachments == null || m.attachments!.isEmpty) {
      return m.content;
    }

    final parts = <Map<String, dynamic>>[];
    if (m.content.trim().isNotEmpty) {
      parts.add({'type': 'text', 'text': m.content});
    }

    for (final a in m.attachments!) {
      final bytes = await loadAttachmentBytesSafe(a);
      if (bytes == null) {
        parts.add({
          'type': 'text',
          'text': '\n[附件「${a.name ?? '未命名'}」无法读取，请重新选择文件]',
        });
        continue;
      }

      switch (a.type) {
        case 'image':
          final mime = a.mimeType ?? 'image/jpeg';
          parts.add({
            'type': 'image_url',
            'image_url': {'url': 'data:$mime;base64,${base64Encode(bytes)}'},
          });
          if (a.ocrText != null && a.ocrText!.trim().isNotEmpty) {
            parts.add({
              'type': 'text',
              'text':
                  '\n\n--- 图片「${a.name ?? ''}」OCR 识别结果 ---\n${a.ocrText!.trim()}',
            });
          }
          break;
        case 'text':
          var text = utf8.decode(bytes, allowMalformed: true);
          text = truncate(text);
          parts.add({
            'type': 'text',
            'text': '\n\n--- 附件: ${a.name ?? '文本'} --\n$text',
          });
          break;
        case 'pdf':
          var extracted = crudePdfText(bytes);
          if (extracted.isEmpty) {
            parts.add({
              'type': 'text',
              'text': '\n[PDF「${a.name ?? '文件'}」未能解析出文本，可尝试导出为 txt 或发送截图]',
            });
          } else {
            extracted = truncate(extracted);
            parts.add({
              'type': 'text',
              'text': '\n\n--- PDF: ${a.name ?? '文档'} --\n$extracted',
            });
          }
          break;
        default:
          parts.add({
            'type': 'text',
            'text': '\n[不支持的附件类型: ${a.type} ${a.name ?? ''}]',
          });
      }
    }

    if (parts.isEmpty) return m.content;
    return parts;
  }

  /// 将消息列表转换为 OpenAI 格式
  static Future<List<Map<String, dynamic>>> toOpenAiMessages(
    List<Message> messages,
  ) async {
    final out = <Map<String, dynamic>>[];
    for (final m in messages) {
      final content = await toOpenAiContent(m);
      out.add({'role': m.role, 'content': content});
    }
    return out;
  }

  // ── 纯文本格式（DeepSeek）──

  /// 将用户消息转换为纯文本格式（用于不支持多模态的服务）
  ///
  /// DeepSeek 的 deepseek-chat / deepseek-reasoner 仅支持纯文本
  static Future<String> toPlainTextWithAttachments(Message m) async {
    final buf = StringBuffer();
    if (m.content.trim().isNotEmpty) {
      buf.writeln(m.content.trim());
    }
    if (m.attachments != null && m.attachments!.isNotEmpty) {
      for (final a in m.attachments!) {
        final bytes = await loadAttachmentBytesSafe(a);
        if (bytes == null) {
          buf.writeln('\n[附件「${a.name ?? '未命名'}」无法读取，请重新选择文件]');
          continue;
        }
        switch (a.type) {
          case 'image':
            buf.writeln(
              '\n[图片「${a.name ?? '未命名'}」：当前服务仅支持纯文本，'
              '接口不接受图片。请用文字描述图片内容，或改用支持多模态的服务后再传图。]',
            );
            break;
          case 'text':
            var text = utf8.decode(bytes, allowMalformed: true);
            text = truncate(text);
            buf.writeln('\n\n--- 附件: ${a.name ?? '文本'} ---');
            buf.writeln(text);
            break;
          case 'pdf':
            var extracted = crudePdfText(bytes);
            if (extracted.isEmpty) {
              buf.writeln(
                '\n[PDF「${a.name ?? '文件'}」未能解析出可用文本，可尝试导出为 txt 后再上传。',
              );
            } else {
              extracted = truncate(extracted);
              buf.writeln('\n\n--- PDF: ${a.name ?? '文档'} ---');
              buf.writeln(extracted);
            }
            break;
          default:
            buf.writeln('\n[不支持的附件类型: ${a.type} ${a.name ?? ''}]');
        }
      }
    }
    final s = buf.toString().trim();
    return s.isEmpty ? m.content : s;
  }

  /// 将消息列表转换为纯文本格式（每条消息都是字符串 content）
  static Future<List<Map<String, dynamic>>> toPlainTextMessages(
    List<Message> messages,
  ) async {
    final out = <Map<String, dynamic>>[];
    for (final m in messages) {
      final String content;
      if (m.role == 'user' &&
          m.attachments != null &&
          m.attachments!.isNotEmpty) {
        content = await toPlainTextWithAttachments(m);
      } else {
        content = m.content;
      }
      out.add({'role': m.role, 'content': content});
    }
    return out;
  }

  // ── Gemini 格式 ──

  /// 将单条消息转换为 Gemini contents 条目
  static Future<Map<String, dynamic>> toGeminiContent(Message m) async {
    if (m.role != 'user' || m.attachments == null || m.attachments!.isEmpty) {
      return {
        'role': m.role == 'assistant' ? 'model' : m.role,
        'parts': [
          {'text': m.content},
        ],
      };
    }

    final parts = <Map<String, dynamic>>[];
    if (m.content.trim().isNotEmpty) {
      parts.add({'text': m.content});
    }

    for (final a in m.attachments!) {
      final bytes = await loadAttachmentBytesSafe(a);
      if (bytes == null) {
        parts.add({'text': '\n[附件「${a.name ?? '未命名'}」无法读取]'});
        continue;
      }

      switch (a.type) {
        case 'image':
          final mime = a.mimeType ?? 'image/jpeg';
          parts.add({
            'inline_data': {'mime_type': mime, 'data': base64Encode(bytes)},
          });
          if (a.ocrText != null && a.ocrText!.trim().isNotEmpty) {
            parts.add({
              'text':
                  '\n\n--- 图片「${a.name ?? ''}」OCR 识别结果 ---\n${a.ocrText!.trim()}',
            });
          }
          break;
        case 'text':
          var text = utf8.decode(bytes, allowMalformed: true);
          text = truncate(text);
          parts.add({'text': '\n\n--- 附件: ${a.name ?? '文本'} --\n$text'});
          break;
        case 'pdf':
          var extracted = crudePdfText(bytes);
          if (extracted.isEmpty) {
            parts.add({
              'text': '\n[PDF「${a.name ?? '文件'}」未能解析出文本，可尝试导出为 txt 或发送截图]',
            });
          } else {
            extracted = truncate(extracted);
            parts.add({
              'text': '\n\n--- PDF: ${a.name ?? '文档'} --\n$extracted',
            });
          }
          break;
        default:
          parts.add({'text': '\n[不支持的附件: ${a.type}]'});
      }
    }

    return {'role': m.role == 'assistant' ? 'model' : m.role, 'parts': parts};
  }

  /// 将消息列表转换为 Gemini contents 格式（处理 system 消息合并）
  static Future<List<Map<String, dynamic>>> toGeminiContents(
    List<Message> messages,
  ) async {
    final out = <Map<String, dynamic>>[];

    // 收集所有 system 消息，合并成一个前置的 user 消息
    final systemMessages = <String>[];
    final normalMessages = <Message>[];

    for (final m in messages) {
      if (m.role == 'system') {
        systemMessages.add(m.content);
      } else {
        normalMessages.add(m);
      }
    }

    // 如果有 system 消息，将它们合并并作为第一条消息的前缀
    if (systemMessages.isNotEmpty) {
      final combinedSystem = systemMessages.join('\n\n');

      if (normalMessages.isNotEmpty && normalMessages.first.role == 'user') {
        // 将 system 内容附加到第一条 user 消息前面
        final firstMsg = normalMessages.first;
        final modifiedFirstMsg = Message(
          role: 'user',
          content: '$combinedSystem\n\n${firstMsg.content}',
          attachments: firstMsg.attachments,
        );
        out.add(await toGeminiContent(modifiedFirstMsg));
        // 添加剩余的消息
        for (var i = 1; i < normalMessages.length; i++) {
          out.add(await toGeminiContent(normalMessages[i]));
        }
      } else {
        // 如果没有 user 消息开头，创建一个单独的 user 消息来包含 system 内容
        out.add({
          'role': 'user',
          'parts': [
            {'text': combinedSystem},
          ],
        });
        for (final m in normalMessages) {
          out.add(await toGeminiContent(m));
        }
      }
    } else {
      // 没有 system 消息，正常处理
      for (final m in messages) {
        out.add(await toGeminiContent(m));
      }
    }

    return out;
  }
}
