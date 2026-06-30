// 做什么：左侧边栏 —— 品牌、新建对话、会话列表、底部导航。
// 为什么这样做：与会话列表分离，列表条目独立为 ConversationTile，便于复用与
// 单独刷新。底部导航只保留「对话 / 设置」两个入口，符合"入口最小化"原则。

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/chat_provider.dart';
import '../../theme/app_colors.dart';
import '../home_screen.dart';
import 'conversation_tile.dart';

class Sidebar extends StatelessWidget {
  final AppView current;
  final ValueChanged<AppView> onNavigate;

  const Sidebar({
    super.key,
    required this.current,
    required this.onNavigate,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 280,
      decoration: const BoxDecoration(
        color: AppColors.sidebar,
        border: Border(right: BorderSide(color: AppColors.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _Brand(),
          _NewChatButton(onCreated: () => onNavigate(AppView.chat)),
          const SizedBox(height: 4),
          const _SearchField(),
          const _ListLabel(label: '会话'),
          const Expanded(child: _ConversationList()),
          _NavFoot(current: current, onNavigate: onNavigate),
        ],
      ),
    );
  }
}

// ── 品牌 ──
class _Brand extends StatelessWidget {
  const _Brand();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              gradient: AppColors.logoGradient,
              borderRadius: BorderRadius.circular(9),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x4D8B7CFF),
                  blurRadius: 18,
                  offset: Offset(0, 6),
                ),
              ],
            ),
            child: const Center(
              child: Icon(Icons.auto_awesome, size: 15, color: Colors.white),
            ),
          ),
          const SizedBox(width: 11),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '杏铃',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontSize: 15,
                ),
              ),
              const Text(
                'XINGLING CHAT',
                style: TextStyle(
                  color: AppColors.textTertiary,
                  fontSize: 9.5,
                  letterSpacing: 1.4,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── 新建对话 ──
class _NewChatButton extends StatelessWidget {
  final VoidCallback onCreated;
  const _NewChatButton({required this.onCreated});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => _create(context),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0x298B7CFF), Color(0x0F8B7CFF)],
              ),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0x478B7CFF)),
            ),
            child: Row(
              children: [
                const Icon(Icons.add, size: 16, color: Color(0xFFE8E5FF)),
                const SizedBox(width: 10),
                Text(
                  '新对话',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: const Color(0xFFE8E5FF),
                  ),
                ),
                const Spacer(),
                Text(
                  '⌘N',
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 10.5,
                    color: AppColors.textTertiary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _create(BuildContext context) async {
    final chat = context.read<ChatProvider>();
    await chat.createConversation('新的对话');
    onCreated();
  }
}

// ── 搜索框（视觉占位，本地过滤）──
class _SearchField extends StatelessWidget {
  const _SearchField();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
      child: TextField(
        style: const TextStyle(fontSize: 13, color: AppColors.textPrimary),
        decoration: InputDecoration(
          isDense: true,
          prefixIcon: const Icon(Icons.search, size: 16),
          prefixIconConstraints: const BoxConstraints(
            minWidth: 36,
            minHeight: 36,
          ),
          hintText: '搜索会话…',
          contentPadding: const EdgeInsets.symmetric(vertical: 9),
          filled: true,
          fillColor: AppColors.surface,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: AppColors.border),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: AppColors.border),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: AppColors.borderStrong),
          ),
        ),
      ),
    );
  }
}

class _ListLabel extends StatelessWidget {
  final String label;
  const _ListLabel({required this.label});

  @override
  Widget build(BuildContext context) {
    final count = context.select<ChatProvider, int>(
      (c) => c.conversations.length,
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 6),
      child: Row(
        children: [
          Text(
            label.toUpperCase(),
            style: const TextStyle(
              color: AppColors.textTertiary,
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.4,
            ),
          ),
          const Spacer(),
          Text(
            '$count',
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 10,
              color: AppColors.textTertiary,
            ),
          ),
        ],
      ),
    );
  }
}

// ── 会话列表 ──
class _ConversationList extends StatelessWidget {
  const _ConversationList();

  @override
  Widget build(BuildContext context) {
    final chat = context.watch<ChatProvider>();

    if (chat.isInitializing) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: AppColors.accent,
            ),
          ),
        ),
      );
    }

    final convs = chat.conversations;
    if (convs.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            '暂无会话\n点击「新对话」开始',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textTertiary, fontSize: 12.5),
          ),
        ),
      );
    }

    final currentId = chat.currentConversationId;

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
      itemCount: convs.length,
      itemBuilder: (context, i) {
        final conv = convs[i];
        return ConversationTile(
          conversation: conv,
          selected: conv.id == currentId,
          onTap: () => chat.switchConversation(conv.id),
          onRename: (name) => chat.renameConversation(conv.id, name),
          onDelete: () => chat.deleteConversation(conv.id),
        );
      },
    );
  }
}

// ── 底部导航 ──
class _NavFoot extends StatelessWidget {
  final AppView current;
  final ValueChanged<AppView> onNavigate;
  const _NavFoot({required this.current, required this.onNavigate});

  @override
  Widget build(BuildContext context) {
    final chat = context.watch<ChatProvider>();
    final hasError = chat.error != null;

    return Container(
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _NavTile(
            icon: Icons.chat_bubble_outline,
            label: '对话',
            active: current == AppView.chat,
            onTap: () => onNavigate(AppView.chat),
          ),
          _NavTile(
            icon: Icons.settings_outlined,
            label: '设置',
            active: current == AppView.settings,
            // 设置入口若存在错误用红点提示，但不增加额外入口
            trailingBadge: hasError,
            onTap: () => onNavigate(AppView.settings),
          ),
        ],
      ),
    );
  }
}

class _NavTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final bool trailingBadge;
  final VoidCallback onTap;

  const _NavTile({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
    this.trailingBadge = false,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(9),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
          decoration: active
              ? BoxDecoration(
                  color: AppColors.surface2,
                  borderRadius: BorderRadius.circular(9),
                )
              : null,
          child: Row(
            children: [
              Icon(
                icon,
                size: 16,
                color: active ? AppColors.textPrimary : AppColors.textSecondary,
              ),
              const SizedBox(width: 11),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  color: active
                      ? AppColors.textPrimary
                      : AppColors.textSecondary,
                ),
              ),
              const Spacer(),
              if (trailingBadge)
                Container(
                  width: 6,
                  height: 6,
                  decoration: const BoxDecoration(
                    color: AppColors.rose,
                    shape: BoxShape.circle,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}


