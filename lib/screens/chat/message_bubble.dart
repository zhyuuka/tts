// 做什么：单条消息气泡 —— 头像、Markdown 正文、可折叠思考、检索来源、附件、操作。
// 为什么这样做：把零件化渲染逻辑收敛到一处；流式气泡复用同一组件，仅 streaming=true。

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:provider/provider.dart';

import '../../models/message.dart';
import '../../providers/chat_provider.dart';
import '../../theme/app_colors.dart';

class MessageBubble extends StatelessWidget {
  final Message message;
  final bool streaming;

  const MessageBubble({super.key, required this.message, this.streaming = false});

  bool get _isUser => message.role == 'user';

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 11),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Avatar(isUser: _isUser),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 名字行
                Padding(
                  padding: const EdgeInsets.only(top: 2, bottom: 5),
                  child: Text(
                    _isUser ? '你' : '杏铃',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textTertiary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                if (!_isUser) _buildReasoning(),
                if (!_isUser) _buildSources(),
                _buildAttachments(),
                _buildContent(context),
                if (!_isUser && !streaming) ...[
                  const SizedBox(height: 8),
                  _Actions(message: message),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── 正文 ──
  Widget _buildContent(BuildContext context) {
    if (message.content.isEmpty && !streaming) {
      return const SizedBox.shrink();
    }
    if (_isUser) {
      // 用户消息走简洁气泡
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        decoration: BoxDecoration(
          color: AppColors.surface2,
          border: Border.all(color: AppColors.border),
          borderRadius: BorderRadius.circular(12),
        ),
        child: SelectableText(
          message.content,
          style: const TextStyle(
            fontSize: 14,
            height: 1.6,
            color: AppColors.textPrimary,
          ),
        ),
      );
    }

    // AI 消息走 Markdown
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        MarkdownBody(
          data: message.content,
          selectable: true,
          styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
            p: const TextStyle(fontSize: 14, height: 1.7, color: AppColors.textPrimary),
            code: TextStyle(
              fontFamily: 'monospace',
              fontSize: 12.5,
              color: AppColors.accent2,
              backgroundColor: AppColors.surface2,
            ),
            codeblockDecoration: BoxDecoration(
              color: AppColors.surface,
              border: Border.all(color: AppColors.border),
              borderRadius: BorderRadius.circular(10),
            ),
            codeblockPadding: const EdgeInsets.all(13),
            blockquoteDecoration: BoxDecoration(
              border: Border(
                left: BorderSide(color: AppColors.accent, width: 2),
              ),
            ),
            h1: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            h2: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            h3: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600),
            a: const TextStyle(color: AppColors.accent2),
          ),
        ),
        if (streaming) const _Caret(),
      ],
    );
  }

  // ── 思考过程 ──
  Widget _buildReasoning() {
    final r = message.reasoningContent;
    if (r == null || r.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: _ReasoningBlock(reasoning: r),
    );
  }

  // ── 检索来源 ──
  Widget _buildSources() {
    final srcs = message.searchSources;
    if (srcs.isEmpty) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(top: 4, bottom: 8),
      padding: const EdgeInsets.fromLTRB(12, 9, 12, 11),
      decoration: BoxDecoration(
        color: const Color(0x084ADE9D),
        border: Border.all(color: const Color(0x224ADE9D)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: const [
              Icon(Icons.travel_explore, size: 11, color: AppColors.teal),
              SizedBox(width: 7),
              Text(
                '联网检索',
                style: TextStyle(
                  fontSize: 11,
                  color: AppColors.teal,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.6,
                ),
              ),
              SizedBox(width: 6),
              Text(
                '· 来源',
                style: TextStyle(fontSize: 11, color: AppColors.textTertiary),
              ),
            ],
          ),
          const SizedBox(height: 7),
          for (var i = 0; i < srcs.length; i++)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                children: [
                  Text(
                    '${i + 1}',
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 10,
                      color: AppColors.textTertiary,
                      width: 1,
                    ),
                    width: 14,
                  ),
                  const SizedBox(width: 5),
                  Expanded(
                    child: Text(
                      srcs[i].title.isEmpty ? srcs[i].url : srcs[i].title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      _hostOf(srcs[i].url),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 10.5,
                        color: AppColors.textTertiary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  // ── 附件 ──
  Widget _buildAttachments() {
    final atts = message.attachments;
    if (atts == null || atts.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: atts.map((a) {
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.surface,
              border: Border.all(color: AppColors.border),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.insert_drive_file_outlined,
                  size: 13,
                  color: AppColors.textSecondary,
                ),
                const SizedBox(width: 6),
                Text(
                  (a.name != null && a.name!.isNotEmpty) ? a.name! : '附件',
                  style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  String _hostOf(String url) {
    final uri = Uri.tryParse(url);
    return uri?.host ?? url;
  }
}

// ── 头像 ──
class _Avatar extends StatelessWidget {
  final bool isUser;
  const _Avatar({required this.isUser});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 30,
      height: 30,
      decoration: BoxDecoration(
        color: isUser ? AppColors.userAvatarBg : AppColors.aiAvatarBg,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(
          color: isUser ? AppColors.border : const Color(0x408B7CFF),
        ),
      ),
      child: Center(
        child: isUser
            ? const Text(
                '你',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
              )
            : const Icon(Icons.auto_awesome, size: 14, color: AppColors.accent2),
      ),
    );
  }
}

// ── 思考块（可折叠）──
class _ReasoningBlock extends StatefulWidget {
  final String reasoning;
  const _ReasoningBlock({required this.reasoning});

  @override
  State<_ReasoningBlock> createState() => _ReasoningBlockState();
}

class _ReasoningBlockState extends State<_ReasoningBlock> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0x0DFFFFFF),
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              child: Row(
                children: [
                  const Icon(
                    Icons.psychology_outlined,
                    size: 13,
                    color: AppColors.accent2,
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    '思考过程',
                    style: TextStyle(fontSize: 12, color: AppColors.textSecondary, fontWeight: FontWeight.w500),
                  ),
                  const Spacer(),
                  AnimatedRotation(
                    turns: _expanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 150),
                    child: const Icon(
                      Icons.keyboard_arrow_down,
                      size: 14,
                      color: AppColors.textTertiary,
                    ),
                  ),
                ],
              ),
            ),
          ),
          AnimatedCrossFade(
            duration: const Duration(milliseconds: 150),
            crossFadeState: _expanded
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            firstChild: const SizedBox(width: double.infinity, height: 0),
            secondChild: Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: SelectableText(
                widget.reasoning,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12.5,
                  height: 1.6,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── 流式光标 ──
class _Caret extends StatefulWidget {
  const _Caret();

  @override
  State<_Caret> createState() => _CaretState();
}

class _CaretState extends State<_Caret> with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _c,
      child: Container(
        width: 7,
        height: 15,
        margin: const EdgeInsets.only(top: 6, left: 2),
        decoration: BoxDecoration(
          color: AppColors.accent2,
          borderRadius: BorderRadius.circular(1),
        ),
      ),
    );
  }
}

// ── 操作行 ──
class _Actions extends StatelessWidget {
  final Message message;
  const _Actions({required this.message});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _ActionChip(
          icon: Icons.copy_outlined,
          label: '复制',
          onTap: () async {
            await Clipboard.setData(ClipboardData(text: message.content));
            if (!context.mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('已复制'), duration: Duration(seconds: 1)),
            );
          },
        ),
        const SizedBox(width: 2),
        _ActionChip(
          icon: Icons.refresh,
          label: '重试',
          onTap: () => context.read<ChatProvider>().retryLastMessage(),
        ),
      ],
    );
  }
}

class _ActionChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _ActionChip({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(6),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 11, color: AppColors.textTertiary),
            const SizedBox(width: 5),
            Text(
              label,
              style: const TextStyle(fontSize: 11, color: AppColors.textTertiary),
            ),
          ],
        ),
      ),
    );
  }
}
