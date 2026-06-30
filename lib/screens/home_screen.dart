// 做什么：主框架 —— 左侧边栏 + 右侧内容区，视图在「对话 / 设置」间切换。
// 为什么这样做：遵循设计画布的"单界面入口最小化"原则。底部导航只暴露
// 两个入口（对话 / 设置），其余操作均在其所属视图内完成，避免顶栏堆砌按钮。
// 窄屏（< 760px）时侧边栏可折叠，保证移动端可用。

import 'package:flutter/material.dart';

import 'chat/chat_screen.dart';
import 'settings/settings_screen.dart';
import 'sidebar/sidebar.dart';

enum AppView { chat, settings }

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  AppView _view = AppView.chat;
  bool _sidebarOpen = false;

  void _navigate(AppView v) {
    setState(() {
      _view = v;
      _sidebarOpen = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final isNarrow = MediaQuery.sizeOf(context).width < 760;

    Widget content = AnimatedSwitcher(
      duration: const Duration(milliseconds: 200),
      child: _view == AppView.chat
          ? ChatScreen(
              key: const ValueKey('chat'),
              onToggleSidebar: isNarrow
                  ? () => setState(() => _sidebarOpen = true)
                  : null,
            )
          : SettingsScreen(
              key: const ValueKey('settings'),
              onClose: () => _navigate(AppView.chat),
            ),
    );

    if (!isNarrow) {
      // 宽屏：侧边栏常驻
      return Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        body: SafeArea(
          child: Row(
            children: [
              Sidebar(current: _view, onNavigate: _navigate),
              Expanded(child: content),
            ],
          ),
        ),
      );
    }

    // 窄屏：侧边栏作为浮层抽屉，点遮罩关闭
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: Stack(
          children: [
            content,
            if (_sidebarOpen) ...[
              // 遮罩
              GestureDetector(
                onTap: () => setState(() => _sidebarOpen = false),
                child: Container(
                  color: const Color(0xAA000000),
                ),
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: Sidebar(current: _view, onNavigate: _navigate),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
