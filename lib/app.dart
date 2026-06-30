// 做什么：根 Widget，挂载主题与首页。
// 为什么单独成文件：main.dart 仅负责启动编排，UI 根节点独立便于测试与热重载。

import 'package:flutter/material.dart';

import 'screens/home_screen.dart';
import 'theme/app_theme.dart';

class XinglingApp extends StatelessWidget {
  const XinglingApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '杏铃聊天',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      home: const HomeScreen(),
    );
  }
}
