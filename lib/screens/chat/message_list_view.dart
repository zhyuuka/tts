// 做什么：消息列表 —— 渲染历史消息 + 流式气泡 + 空态引导，自动滚动到底。
// 为什么这样做：把滚动控制、空态、流式拼接集中在列表层，气泡只关心单条渲染。

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/message.dart';
import '../../providers/chat_provider.dart';
import '../../theme/app_colors.dart';
import 'message_bubble.dart';

class MessageListView extends StatefulWidget {
  const MessageListView({super.key});

  @override
  State<MessageListView> createState() => _MessageListViewState();
}

class _MessageListViewState extends State<MessageListView> {
  final ScrollController _ctrl = ScrollController();
  bool _autoScroll = true;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _maybeStickToBottom() {
    if (!_autoScroll || !_ctrl.hasClients) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_ctrl.hasClients) return;
      _ctrl.jumpTo(_ctrl.position.maxScrollExtent);
    });
  }

  bool _onScroll() {
    if (!_ctrl.hasClients) return _autoScroll;
    final pos = _ctrl.position;
    // 距底部 80px 内视为贴底
    final stick = pos.pixels >= pos.maxScrollExtent - 80;
    if (stick != _autoScroll) {
      setState(() => _autoScroll = stick);
    }
    return _autoScroll;
  }

  @override
  Widget build(BuildContext context) {
    final chat = context.watch<ChatProvider>();
    final messages = chat.messages;

    // 滚动监听
    WidgetsBinding.instance.addPostFrameCallback((_) => _onScroll());
    if (_autoScroll) _maybeStickToBottom();

    if (messages.isEmpty && !chat.isStreaming) {
      return const _EmptyState();
    }

    return ListView.builder(
      controller: _ctrl,
      padding: const EdgeInsets.symmetric(vertical: 24),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      itemCount: messages.length + (chat.isStreaming ? 1 : 0),
      itemBuilder: (context, i) {
        // 流式气泡：列表末尾追加一条临时 Message
        if (i == messages.length) {
          return MessageBubble(
            message: Message(
              role: 'assistant',
              content: chat.streamingContent,
              reasoningContent: chat.streamingHasReasoning
                  ? chat.streamingReasoning
                  : null,
              timestamp: DateTime.now(),
            ),
            streaming: true,
          );
        }
        return MessageBubble(message: messages[i]);
      },
    );
  }
}

// ── 空态引导 ──
class _EmptyState extends StatelessWidget {
  const _EmptyState();

  static const _prompts = <_Prompt>[
    _Prompt(
      title: '梳理一段代码逻辑',
      desc: '把后端 ChatProvider 的发送流程讲清楚',
    ),
    _Prompt(
      title: '比较两种实现',
      desc: 'Provider 与 Riverpod 在本项目的取舍',
    ),
    _Prompt(
      title: '写一段示例',
      desc: '为 Agent 安全守卫加一个单测',
    ),
    _Prompt(
      title: '帮我设计',
      desc: '给记忆系统设计一个可视化看板',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 74,
              height: 74,
              decoration: BoxDecoration(
                gradient: AppColors.logoGradient,
                borderRadius: BorderRadius.circular(22),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x558B7CFF),
                    blurRadius: 40,
                    offset: Offset(0, 14),
                  ),
                ],
              ),
              child: const Center(
                child: Icon(Icons.auto_awesome, size: 30, color: Colors.white),
              ),
            ),
            const SizedBox(height: 22),
            const Text(
              '开始一段新对话',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w600,
                letterSpacing: -0.2,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              '杏铃支持多 AI 接入、双轨长期记忆与流式回复。\n所有数据均保存在本地。',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textSecondary, height: 1.6),
            ),
            const SizedBox(height: 28),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: LayoutBuilder(
                builder: (context, c) {
                  final cols = c.maxWidth > 480 ? 2 : 1;
                  return GridView.count(
                    crossAxisCount: cols,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    mainAxisSpacing: 10,
                    crossAxisSpacing: 10,
                    childAspectRatio: 2.6,
                    children: _prompts
                        .map(
                          (p) => _PromptCard(
                            prompt: p,
                            onTap: () => _send(context, p.title),
                          ),
                        )
                        .toList(),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _send(BuildContext context, String text) async {
    context.read<ChatProvider>().sendMessage(text);
  }
}

class _Prompt {
  final String title;
  final String desc;
  const _Prompt({required this.title, required this.desc});
}

class _PromptCard extends StatelessWidget {
  final _Prompt prompt;
  final VoidCallback onTap;
  const _PromptCard({required this.prompt, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(11),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 11, 14, 11),
        decoration: BoxDecoration(
          color: AppColors.surface,
          border: Border.all(color: AppColors.border),
          borderRadius: BorderRadius.circular(11),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              prompt.title,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 3),
            Text(
              prompt.desc,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11.5, color: AppColors.textTertiary),
            ),
          ],
        ),
      ),
    );
  }
}
