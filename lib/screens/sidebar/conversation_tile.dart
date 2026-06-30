// 做什么：会话列表单条 —— 名称、服务商徽标、时间、选中态、重命名/删除。
// 为什么这样做：把单条渲染与菜单交互独立，避免列表 rebuild 时丢失菜单状态。

import 'package:flutter/material.dart';

import '../../models/conversation.dart';
import '../../theme/app_colors.dart';

class ConversationTile extends StatelessWidget {
  final Conversation conversation;
  final bool selected;
  final VoidCallback onTap;
  final ValueChanged<String> onRename;
  final VoidCallback onDelete;

  const ConversationTile({
    super.key,
    required this.conversation,
    required this.selected,
    required this.onTap,
    required this.onRename,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: onTap,
            onLongPress: () => _showMenu(context),
            child: Container(
              padding: const EdgeInsets.fromLTRB(11, 10, 11, 10),
              decoration: BoxDecoration(
                color: selected ? AppColors.surface2 : null,
                border: selected
                    ? Border.all(color: AppColors.borderStrong)
                    : Border.all(color: Colors.transparent),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      // 活跃指示点（选中时显示）
                      if (selected)
                        Container(
                          width: 6,
                          height: 6,
                          margin: const EdgeInsets.only(right: 7),
                          decoration: const BoxDecoration(
                            color: AppColors.teal,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(color: AppColors.teal, blurRadius: 6),
                            ],
                          ),
                        ),
                      Expanded(
                        child: Text(
                          conversation.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: selected
                                ? FontWeight.w600
                                : FontWeight.w500,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ),
                      // 更多操作（点击展开菜单）
                      InkWell(
                        borderRadius: BorderRadius.circular(4),
                        onTap: () => _showMenu(context),
                        child: const Padding(
                          padding: EdgeInsets.all(4),
                          child: Icon(
                            Icons.more_horiz,
                            size: 14,
                            color: AppColors.textTertiary,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(
                        Icons.chat_bubble_outline,
                        size: 11,
                        color: AppColors.textTertiary,
                      ),
                      const SizedBox(width: 5),
                      Text(
                        _formatTime(conversation.updatedAt),
                        style: const TextStyle(
                          fontSize: 10.5,
                          color: AppColors.textTertiary,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
        // 选中态左侧色条
        if (selected)
          Positioned(
            left: 0,
            top: 8,
            bottom: 8,
            child: Container(
              width: 2.5,
              decoration: BoxDecoration(
                gradient: AppColors.accentGradient,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
      ],
    );
  }

  void _showMenu(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
      ),
      builder: (sheetCtx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.edit_outlined, size: 18),
                title: const Text('重命名', style: TextStyle(fontSize: 14)),
                onTap: () {
                  Navigator.pop(sheetCtx);
                  _showRenameDialog(context);
                },
              ),
              ListTile(
                leading: const Icon(
                  Icons.delete_outline,
                  size: 18,
                  color: AppColors.rose,
                ),
                title: const Text(
                  '删除',
                  style: TextStyle(fontSize: 14, color: AppColors.rose),
                ),
                onTap: () {
                  Navigator.pop(sheetCtx);
                  onDelete();
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _showRenameDialog(BuildContext context) async {
    final controller = TextEditingController(text: conversation.name);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: AppColors.surface,
          title: const Text('重命名会话', style: TextStyle(fontSize: 16)),
          content: TextField(
            controller: controller,
            autofocus: true,
            style: const TextStyle(color: AppColors.textPrimary),
            decoration: const InputDecoration(hintText: '会话名称'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, controller.text.trim()),
              child: const Text('保存'),
            ),
          ],
        );
      },
    );
    if (result != null && result.isNotEmpty && result != conversation.name) {
      onRename(result);
    }
  }

  String _formatTime(DateTime t) {
    final now = DateTime.now();
    final diff = now.difference(t);
    if (diff.inMinutes < 1) return '刚刚';
    if (diff.inHours < 1) return '${diff.inMinutes}m';
    if (diff.inDays < 1) return '${diff.inHours}h';
    if (diff.inDays < 7) return '${diff.inDays}d';
    return '${t.month}/${t.day}';
  }
}
