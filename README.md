# 杏铃聊天（xingling\_chat）社区版

[![License: MIT](https://img.shields.io/github/license/zhyuuka/xingling_chat_community?color=blue)](LICENSE)
[![CI](https://github.com/zhyuuka/xingling_chat_community/actions/workflows/ci.yml/badge.svg)](https://github.com/zhyuuka/xingling_chat_community/actions/workflows/ci.yml)
[![Last Commit](https://img.shields.io/github/last-commit/zhyuuka/xingling_chat_community)](https://github.com/zhyuuka/xingling_chat_community/commits/main)
[![Dart](https://img.shields.io/badge/Dart-3.x-0175C2?logo=dart)](https://dart.dev)
[![Flutter](https://img.shields.io/badge/Flutter-3.x-02569B?logo=flutter)](https://flutter.dev)

> 多 AI 接入 / 双轨长期记忆 / Agent 自动化的 Flutter 后端库

[English](./README_EN.md) | 简体中文

***

## 重要说明（请先阅读）

**本项目是一个"半成品"，仅包含后端代码，没有前端 UI。**

我是一名 vibe coder，凭直觉和热情写代码，没有系统的编程基础。独立完成了后端的设计与实现，但因为能力不足，前端开发频频受挫，**始终未能完成前端 UI 部分**。后端代码经过多轮审查与重构，结构相对清晰，但没有 UI 就无法直接运行展示。

开发过程中频频受挫，一度想要放弃。最终选择开源，是希望：

1. **不浪费已完成的代码**：后端实现了 17 家 AI 接入、双轨长期记忆、Agent 自动化等较为完整的能力，独自埋没可惜。
2. **诚邀社区贡献前端**：如果你擅长 Flutter UI 开发，欢迎为本项目贡献一个前端。无论是完整的聊天界面、设置页面，还是部分组件，都非常欢迎。
3. **共同学习进步**：代码必然存在诸多不足，欢迎指出问题、提出建议，我会虚心接受。

**如果你正在寻找一个"开箱即用"的聊天应用，这个项目目前不适合你。** 但如果你愿意参与建设，欢迎一起把它做出来。

***

## 项目简介

**杏铃聊天** 定位为"个人 AI 助理 + 手机自动化 Agent"二合一工具。本仓库是其**后端核心代码**（社区版），包含：

- **服务层**（`lib/services/`，67 文件）：AI 适配、记忆、存储、Agent、语音、OCR、搜索等 9 个子域
- **状态层**（`lib/providers/`，10 文件）：基于 `ChangeNotifier` 的状态管理与编排
- **数据模型层**（`lib/models/`，9 文件）：消息、会话、附件、Agent 任务等
- **基础设施层**（`lib/core/`，5 文件）：启动编排、日志、错误体系
- **数据层**（`lib/data/`，1 文件）：更新日志数据
- **工具层**（`lib/util/`，4 文件）：附件字节处理、图像缓存

**不包含**：UI 组件（`screens/`）、主题（`theme/`）、应用入口（`main.dart`）、平台配置（`android/` / `ios/`）、资源文件（`assets/`）。

***

## 后端能力一览

### 1. 多 AI 提供商统一接入

支持 17 家 AI 服务商，统一抽象接口，工厂模式创建：

| 厂商  | 服务商                                                                                         | 备注                 |
| --- | ------------------------------------------------------------------------------------------- | ------------------ |
| 国际  | OpenAI / Gemini / Hugging Face                                                              | <br />             |
| 国内  | DeepSeek / 豆包 / 通义 / 混元 / Moonshot / 智谱 / MiniMax / StepFun / 百川 / 讯飞星火 / 零一万物 / ERNIE / 桂极 | <br />             |
| 自定义 | OpenAI 兼容协议任意端点                                                                             | 支持 Ollama / vLLM 等 |

特性：流式 SSE 响应、多模态消息（文本/图片/PDF）、上下文窗口管理、Token 估算。

### 2. 双轨长期记忆系统

- **MemU 智能记忆**（`memu_service.dart`，1104 行）：WAL 预写日志、AI 语义评分、冲突自动解决、TF-IDF 向量检索、人格快照与恢复
- **MemLocal 短期记忆**（`memlocal_service.dart`，482 行）：会话级短期上下文

### 3. Agent 自动化（Android）

通过 Android 无障碍服务操控手机，4 级风险分级 + 银行保护 + 操作审计：

- 感知-思考-行动循环（`agent_service.dart`）
- 原生通信桥接（`accessibility_bridge.dart`）
- 4 级风险分级守卫（`agent_safety_guard.dart`）
- 12 种工具注册表（`agent_tool_registry.dart`）
- 操作审计日志（`agent_operation_logger.dart`）
- 聊天内意图识别（`agent_intent_detector.dart`）

### 4. 多模态输入

- **语音识别**：本地 sherpa\_onnx + 云端 Whisper/讯飞/通义
- **OCR**：本地 ML Kit + 百度/腾讯/阿里云
- **附件**：图片 / PDF / 文件

### 5. 本地 TTS

自研 NCNN 神经网络语音合成（C++/Kotlin/Dart 三层），全平台含鸿蒙。

### 6. 联网搜索

DuckDuckGo / SearXNG / Bing / Google 四引擎集成。

### 7. 设置系统（Facade + Repository）

`SettingsService` 作为门面，转发到 8 个子域 Repository：AI / 搜索 / 外观 / 语音 / TTS / Agent / 更新日志 / OCR。

***

## 技术栈

| 维度   | 技术选型                             | 版本                          |
| ---- | -------------------------------- | --------------------------- |
| 框架   | Flutter + Dart                   | SDK ^3.11.1                 |
| 状态管理 | Provider（ChangeNotifier）         | ^6.1.1（仅后端用 ChangeNotifier） |
| 网络层  | Dio + SSE 流式解析                   | ^5.4.0                      |
| 本地存储 | Hive（NoSQL）+ JSON 文件             | ^2.2.3                      |
| 安全存储 | flutter\_secure\_storage（硬件加密）   | ^9.2.2                      |
| 语音识别 | speech\_to\_text + sherpa\_onnx  | ^7.0.0 / ^1.13.2            |
| OCR  | google\_mlkit\_text\_recognition | ^0.15.0                     |
| 环境变量 | flutter\_dotenv                  | ^5.1.0                      |
| 日志   | logger                           | ^2.0.2+1                    |

完整依赖见 [`pubspec.yaml`](./pubspec.yaml)。

***

## 项目结构

```
community_edition/
├── lib/                          ← 后端核心代码
│   ├── core/                     ← 基础设施层（5 文件）
│   │   ├── app_bootstrap.dart    ← 6 阶段启动编排器
│   │   ├── logger/               ← 日志 + 4 组正则脱敏
│   │   ├── errors/               ← sealed class 错误体系
│   │   └── constants/            ← 常量（开源版新增 AppIcons）
│   ├── services/                 ← 服务层（67 文件，按子域分组）
│   │   ├── ai_service.dart       ← AI 抽象基类（含通用 SSE 解析）
│   │   ├── ai_service_factory.dart ← 17 家厂商工厂（唯一入口）
│   │   ├── *_service.dart × 16   ← 各 AI 厂商实现
│   │   ├── storage_service.dart  ← 文件存储（36 个公开方法）
│   │   ├── settings_service.dart ← 设置中心 Facade（772 行）
│   │   ├── memu_service.dart     ← 智能记忆管理（1104 行）
│   │   ├── memlocal_service.dart ← 本地短期记忆（482 行）
│   │   ├── memory_*.dart × 5     ← 记忆子系统
│   │   ├── agent/                ← Agent 自动化子域（6 文件）
│   │   ├── settings/             ← 设置 Facade（8 个 Repository）
│   │   ├── vision/               ← 视觉子域（OCR）
│   │   ├── search/               ← 搜索子域
│   │   └── common/               ← 通用工具子域（6 文件）
│   ├── providers/                ← 状态层（10 文件）
│   │   ├── chat_provider.dart    ← 聊天 Facade（403 行）
│   │   ├── chat_send_orchestrator.dart ← 发送编排
│   │   ├── chat_streaming_controller.dart ← 流式控制
│   │   ├── conversation_loader.dart ← 会话加载
│   │   ├── ai_service_switcher.dart ← AI 服务切换
│   │   └── ...
│   ├── models/                   ← 数据模型层（9 文件）
│   │   ├── message.dart / conversation.dart / attachment.dart
│   │   └── agent/                ← Agent 任务模型
│   ├── data/                     ← 数据层
│   │   └── changelog_data.dart   ← 更新日志数据
│   └── util/                     ← 工具层（4 文件）
│       ├── attachment_bytes.dart ← 附件字节加载（条件导入）
│       └── image_cache_manager.dart ← 图像缓存
├── pubspec.yaml                  ← 依赖声明
├── analysis_options.yaml         ← Lint 规则
├── .env.example                  ← API Key 模板
├── .gitignore
├── LICENSE                       ← MIT
├── CONTRIBUTING.md               ← 贡献指南
├── CODE_OF_CONDUCT.md            ← 行为准则
├── SECURITY.md                   ← 安全策略
├── .github/                      ← GitHub 配置
│   ├── ISSUE_TEMPLATE/           ← Issue 模板
│   │   ├── bug_report.md
│   │   └── feature_request.md
│   └── PULL_REQUEST_TEMPLATE.md  ← PR 模板
├── README.md                     ← 本文件（中文）
└── README_EN.md                  ← 英文说明
```

***

## 如何使用

### 方式一：作为依赖引入到你自己的 Flutter 项目

1. 在你的 Flutter 项目 `pubspec.yaml` 中添加：

```yaml
dependencies:
  xingling_chat_community:
    git:
      url: https://github.com/zhyuuka/xingling_chat_community.git
      ref: main
```

1. 在代码中导入需要的模块：

```dart
import 'package:xingling_chat_community/services/ai_service_factory.dart';
import 'package:xingling_chat_community/services/settings_service.dart';
import 'package:xingling_chat_community/providers/chat_provider.dart';

// 创建 AI 服务
final aiService = AiServiceFactory.createService('deepseek');

// 使用设置服务
final settings = SettingsService();
await settings.init();

// 使用聊天 Provider（需配合你的 UI）
final chatProvider = ChatProvider(...);
```

1. 自行实现 UI 层（聊天界面、设置页面等），通过 Provider 或其他状态管理方式连接后端。

### 方式二：克隆研究学习

```bash
git clone https://github.com/zhyuuka/xingling_chat_community.git
cd xingling_chat_community
flutter pub get
dart analyze lib
```

***

## 配置 API Key

后端通过 `flutter_secure_storage` 读取 API Key（硬件加密存储），运行时由 UI 层调用 `SettingsService.setApiKey()` 写入。

开发期可使用 `.env` 文件配置默认 Key（由 `ai_service_factory.dart` 通过 `flutter_dotenv` 读取）：

```bash
cp .env.example .env
# 编辑 .env 填入你的 API Key
```

支持的服务商见 [`.env.example`](./.env.example)。

***

## 静态分析与测试

```bash
# 静态分析（应返回 0 error）
dart analyze lib

# 完整 Lint 检查
flutter analyze

# 运行单元测试（如有）
flutter test test/unit/
```

***

## 贡献指南

**我们最迫切的需求是前端 UI 贡献**，但也欢迎后端代码改进、文档完善、问题反馈。

详见 [CONTRIBUTING.md](./CONTRIBUTING.md)。

### 当前后端待优化项

- `services/` 根目录仍有 45 个文件平铺，可继续按 `ai/` / `memory/` / `storage/` / `speech/` 子域拆分
- 10 个 info 级 lint 项（代码风格建议，不影响功能）
- `backup_provider` / `chat_provider` 中仍有同步 IO 调用未迁移到 async

### 前端贡献建议

如果你愿意贡献前端，建议优先实现：

1. **聊天主界面**：消息列表 + 输入框 + 流式渲染（连接 `ChatProvider`）
2. **设置页面**：AI 服务选择 + API Key 输入 + 模型选择（连接 `SettingsService`）
3. **会话管理**：会话列表 + 切换 + 重命名 + 删除（连接 `ConversationProvider`）
4. **记忆仪表板**：查看 / 编辑记忆条目（连接 `MemoryProvider`）

***

## 开源协议

[MIT License](./LICENSE)

Copyright (c) 2026 杏铃聊天社区版贡献者

***

## 安全策略

如果你发现安全漏洞，请勿在公开 Issue 中报告，详见 [SECURITY.md](./SECURITY.md)。

***

## 行为准则

参与本项目即代表你同意遵守 [CODE\_OF\_CONDUCT.md](./CODE_OF_CONDUCT.md)。请保持友善、尊重、包容。

***

## 致谢

- 感谢所有 AI 接力审查者（详见 `BACKEND_OPEN_SOURCE_RELAY_2026-06-26.md`）对后端代码的多轮重构
- 感谢 Flutter / Dart 团队提供的优秀工具链
- 感谢各家 AI 服务商提供的 API
- 感谢未来每一位为本项目贡献代码或建议的你

***

## 联系方式

- 提交 Issue：[GitHub Issues](https://github.com/zhyuuka/xingling_chat_community/issues)
- 提交 Pull Request：欢迎
- 邮箱（主要）：3684939695@qq.com
- 邮箱（次要）：zhyuuka@gmail.com

我能力有限，回复可能不及时，但一定会认真阅读每一条反馈。再次感谢你的关注与支持。
