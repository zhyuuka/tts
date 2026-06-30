// 做什么：对话主视图 —— 顶栏 + 消息列表 + 输入区。
// 为什么这样做：把三段聚合在同一 Column，列表区自适应高度。空会话时展示
// 引导卡片，降低首次使用门槛。入口最小化：顶栏仅保留「侧栏切换 / 导出 / 更多」。

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/chat_provider.dart';
import '../../theme/app_colors.dart';
import 'composer.dart';
import 'message_list_view.dart';

class ChatScreen extends StatelessWidget {
  /// 窄屏时由顶栏触发侧边栏打开；宽屏传 null 隐藏该按钮。
  final VoidCallback? onToggleSidebar;

  const ChatScreen({super.key, this.onToggleSidebar});

  @override
  Widget build(BuildContext context) {
    final chat = context.watch<ChatProvider>();
    final conv = chat.currentConversation;
    final service = chat.currentAiService;

    return Column(
      children: [
        _TopBar(
          title: conv?.name ?? '杏铃',
          serviceName: service.serviceName,
          serviceId: service.serviceId,
          isStreaming: chat.isStreaming,
          onToggleSidebar: onToggleSidebar,
        ),
        const Divider(height: 1),
        Expanded(child: MessageListView()),
        const Divider(height: 1),
        const Composer(),
      ],
    );
  }
}

class _TopBar extends StatelessWidget {
  final String title;
  final String serviceName;
  final String serviceId;
  final bool isStreaming;
  final VoidCallback? onToggleSidebar;

  const _TopBar({
    required this.title,
    required this.serviceName,
    required this.serviceId,
    required this.isStreaming,
    this.onToggleSidebar,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 54,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Row(
        children: [
          if (onToggleSidebar != null)
            IconButton(
              icon: const Icon(Icons.menu, size: 18),
              onPressed: onToggleSidebar,
              tooltip: '会话列表',
            ),
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 14.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          // 模型徽标
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            decoration: BoxDecoration(
              color: AppColors.surface,
              border: Border.all(color: AppColors.border),
              borderRadius: BorderRadius.circular(7),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 14,
                  height: 14,
                  decoration: BoxDecoration(
                    color: AppColors.serviceColor(serviceId),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(width: 7),
                Text(
                  serviceName,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          if (isStreaming) ...[
            const SizedBox(width: 10),
            const _LiveDot(),
          ],
          const SizedBox(width: 6),
          _IconBtn(
            icon: Icons.file_download_outlined,
            tooltip: '导出会话',
            onTap: () => _export(context),
          ),
          const _IconBtn(
            icon: Icons.more_horiz,
            tooltip: '更多',
          ),
        ],
      ),
    );
  }

  Future<void> _export(BuildContext context) async {
    final chat = context.read<ChatProvider>();
    final path = await chat.exportBackup();
    if (!context.mounted) return;
    if (path != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已导出：$path')),
      );
    } else {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('导出失败')));
    }
  }
}

class _LiveDot extends StatelessWidget {
  const _LiveDot();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const _Pulse(),
        const SizedBox(width: 6),
        Text(
          '流式中',
          style: TextStyle(
            fontFamily: 'monospace',
            fontSize: 11.5,
            color: AppColors.teal,
          ),
        ),
      ],
    );
  }
}

class _Pulse extends StatefulWidget {
  const _Pulse();

  @override
  State<_Pulse> createState() => _PulseState();
}

class _PulseState extends State<_Pulse> with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  late final Animation<double> _a;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat(reverse: true);
    _a = Tween<double>(begin: 1, end: 0.35).animate(
      CurvedAnimation(parent: _c, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _a,
      child: Container(
        width: 6,
        height: 6,
        decoration: const BoxDecoration(
          color: AppColors.teal,
          shape: BoxShape.circle,
          boxShadow: [BoxShadow(color: AppColors.teal, blurRadius: 8)],
        ),
      ),
    );
  }
}

class _IconBtn extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;
  const _IconBtn({required this.icon, required this.tooltip, this.onTap});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: const Padding(
          padding: EdgeInsets.all(8),
          child: Icon(icon, size: 16, color: AppColors.textSecondary),
        ),
      ),
    );
  }
}
