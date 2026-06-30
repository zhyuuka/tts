// 做什么：输入区 —— 自动增高输入框、发送/停止切换、联网开关、Token 计数。
// 为什么这样做：把发送编排收敛到一处，按 isStreaming 切换发送/停止图标；
// 联网开关复用 ChatProvider.toggleSearchEnabled，避免新增入口。

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/chat_provider.dart';
import '../../services/settings_service.dart';
import '../../theme/app_colors.dart';

class Composer extends StatefulWidget {
  const Composer({super.key});

  @override
  State<Composer> createState() => _ComposerState();
}

class _ComposerState extends State<Composer> {
  final TextEditingController _ctrl = TextEditingController();
  final FocusNode _focus = FocusNode();
  bool _hasText = false;

  @override
  void initState() {
    super.initState();
    _ctrl.addListener(_onChanged);
  }

  @override
  void dispose() {
    _ctrl.removeListener(_onChanged);
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _onChanged() {
    final has = _ctrl.text.trim().isNotEmpty;
    if (has != _hasText) setState(() => _hasText = has);
  }

  Future<void> _send() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty) return;
    final chat = context.read<ChatProvider>();
    _ctrl.clear();
    _focus.requestFocus();
    await chat.sendMessage(text);
  }

  @override
  Widget build(BuildContext context) {
    final chat = context.watch<ChatProvider>();
    final streaming = chat.isStreaming;
    final searchOn = context.select<SettingsService, bool>(
      (s) => s.isInitialized ? s.isSearchEnabled() : false,
    );

    // 错误条
    final err = chat.error;
    final hasErr = err != null && err.isNotEmpty;

    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 8, 28, 18),
      child: Column(
        children: [
          if (hasErr)
            Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              decoration: BoxDecoration(
                color: const Color(0x22FF7A8A),
                border: Border.all(color: const Color(0x44FF7A8A)),
                borderRadius: BorderRadius.circular(9),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.error_outline,
                    size: 14,
                    color: AppColors.rose,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      err,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12, color: AppColors.rose),
                    ),
                  ),
                  InkWell(
                    onTap: chat.clearError,
                    child: const Padding(
                      padding: EdgeInsets.all(4),
                      child: Icon(Icons.close, size: 13, color: AppColors.rose),
                    ),
                  ),
                ],
              ),
            ),
          Container(
            constraints: const BoxConstraints(maxWidth: 780),
            decoration: BoxDecoration(
              color: AppColors.surface,
              border: Border.all(color: AppColors.border),
              borderRadius: BorderRadius.circular(14),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x33000000),
                  blurRadius: 40,
                  offset: Offset(0, 12),
                ),
              ],
            ),
            child: Column(
              children: [
                // 输入框
                TextField(
                  controller: _ctrl,
                  focusNode: _focus,
                  minLines: 1,
                  maxLines: 6,
                  textInputAction: TextInputAction.newline,
                  style: const TextStyle(
                    fontSize: 14,
                    height: 1.6,
                    color: AppColors.textPrimary,
                  ),
                  decoration: InputDecoration(
                    hintText: '给杏铃发消息…（Enter 发送 / Shift+Enter 换行）',
                    hintStyle: const TextStyle(
                      color: AppColors.textTertiary,
                      fontSize: 14,
                    ),
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    contentPadding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
                  ),
                  onSubmitted: (_) {
                    if (!streaming && _hasText) _send();
                  },
                ),
                // 工具栏
                Padding(
                  padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
                  child: Row(
                    children: [
                      _ToolButton(
                        icon: Icons.attach_file,
                        label: '附件',
                        onTap: () => _notImplemented(context),
                      ),
                      const SizedBox(width: 8),
                      _ToolButton(
                        icon: Icons.travel_explore,
                        label: '联网',
                        active: searchOn,
                        onTap: () =>
                            context.read<ChatProvider>().toggleSearchEnabled(),
                      ),
                      const SizedBox(width: 8),
                      _ToolButton(
                        icon: Icons.mic_none_outlined,
                        label: '语音',
                        onTap: () => _notImplemented(context),
                      ),
                      const Spacer(),
                      _TokenCounter(chat: chat),
                      const SizedBox(width: 8),
                      _SendButton(
                        streaming: streaming,
                        enabled: streaming || _hasText,
                        onTap: () {
                          if (streaming) {
                            context.read<ChatProvider>().stopGeneration();
                          } else {
                            _send();
                          }
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 9),
          const Text(
            '杏铃可能出错，请核对重要信息。对话与记忆均存储在本地。',
            style: TextStyle(fontSize: 11, color: AppColors.textTertiary),
          ),
        ],
      ),
    );
  }

  void _notImplemented(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('该入口将在后续版本启用'),
        duration: Duration(seconds: 1),
      ),
    );
  }
}

// ── 工具按钮 ──
class _ToolButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;
  const _ToolButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.active = false,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: active ? AppColors.tealSoft : Colors.transparent,
          border: Border.all(
            color: active ? const Color(0x4D4ADE9D) : AppColors.border,
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 14,
              color: active ? AppColors.teal : AppColors.textSecondary,
            ),
            const SizedBox(width: 7),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: active ? AppColors.teal : AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Token 计数 ──
class _TokenCounter extends StatelessWidget {
  final ChatProvider chat;
  const _TokenCounter({required this.chat});

  @override
  Widget build(BuildContext context) {
    final used = chat.estimateContextTokens();
    final max = chat.maxContextTokens;
    final ratio = max > 0 ? used / max : 0.0;
    final color = ratio > 0.9
        ? AppColors.rose
        : ratio > 0.7
        ? AppColors.amber
        : AppColors.textTertiary;
    return Text(
      '${_fmt(used)} / ${_fmt(max)}',
      style: TextStyle(
        fontFamily: 'monospace',
        fontSize: 11,
        color: color,
      ),
    );
  }

  String _fmt(int n) {
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}k';
    return '$n';
  }
}

// ── 发送 / 停止按钮 ──
class _SendButton extends StatelessWidget {
  final bool streaming;
  final bool enabled;
  final VoidCallback onTap;
  const _SendButton({
    required this.streaming,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isStop = streaming;
    return Tooltip(
      message: isStop ? '停止生成' : '发送',
      child: InkWell(
        borderRadius: BorderRadius.circular(9),
        onTap: enabled ? onTap : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            gradient: isStop
                ? null
                : (enabled
                    ? AppColors.accentGradient
                    : const LinearGradient(colors: [AppColors.surface3, AppColors.surface3])),
            color: isStop ? AppColors.surface3 : null,
            border: isStop
                ? Border.all(color: const Color(0x44FF7A8A))
                : null,
            borderRadius: BorderRadius.circular(9),
            boxShadow: !isStop && enabled
                ? const [
                    BoxShadow(
                      color: Color(0x558B7CFF),
                      blurRadius: 16,
                      offset: Offset(0, 6),
                    ),
                  ]
                : null,
          ),
          child: Center(
            child: Icon(
              isStop ? Icons.stop_rounded : Icons.arrow_upward_rounded,
              size: 16,
              color: isStop ? AppColors.rose : (enabled ? AppColors.accentOn : AppColors.textTertiary),
            ),
          ),
        ),
      ),
    );
  }
}
