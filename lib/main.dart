// 做什么：应用入口，编排启动流程并向 widget 树注入 Provider。
// 为什么这样做：原项目无 main.dart（仅后端库）。本文件通过 AppBootstrap
// 完成全部服务初始化，再用 MultiProvider 注入 ChatProvider / SettingsService /
// AgentProvider，最后挂载 XinglingApp。

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'app.dart';
import 'core/app_bootstrap.dart';
import 'providers/agent_provider.dart';
import 'providers/chat_provider.dart';
import 'services/settings_service.dart';

Future<void> main() async {
  // AppBootstrap.initCore 内部已调用 WidgetsFlutterBinding.ensureInitialized()。
  final bootstrap = AppBootstrap();
  final result = await bootstrap.run();

  runApp(
    MultiProvider(
      providers: [
        // .value：实例由 bootstrap 创建并持有生命周期，Provider 不重复构建
        ChangeNotifierProvider<ChatProvider>.value(value: result.chatProvider),
        ChangeNotifierProvider<SettingsService>.value(value: result.settings),
        ChangeNotifierProvider<AgentProvider>.value(
          value: result.agentProvider,
        ),
      ],
      child: const XinglingApp(),
    ),
  );
}
