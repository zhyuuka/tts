# 更新日志 / Changelog

本文件记录杏铃聊天社区版（开源后端库）的版本演进。

原完整项目的版本演进历史（1.900 - 1.909）见 `lib/data/changelog_data.dart`，本文件仅记录开源版的版本。

---

## [1.0.0] - 2026-06-27

### 新增 / Added

- 首次开源发布
- 后端核心代码 96 个 Dart 文件，包含：
  - 服务层 `lib/services/`（67 文件，9 个子域：AI 适配 / 记忆 / 存储 / Agent / 语音 / OCR / 搜索 / 设置 / 通用工具）
  - 状态层 `lib/providers/`（10 文件，基于 ChangeNotifier）
  - 数据模型层 `lib/models/`（9 文件，含 Agent 子域）
  - 基础设施层 `lib/core/`（5 文件：启动编排 / 日志 / 错误体系）
  - 数据层 `lib/data/`（1 文件：更新日志数据）
  - 工具层 `lib/util/`（4 文件：附件字节 / 图像缓存）
- 开源版新增 `lib/core/constants/app_icons.dart`：精简版 AppIcons 常量类（纯字符串，无 Flutter UI 依赖）
- MIT 开源协议
- 中英双语 README
- 贡献指南 CONTRIBUTING.md
- API Key 模板 `.env.example`（17 家 AI 服务商）

### 变更 / Changed

- `lib/data/changelog_data.dart` 的 import 从 `'../theme/app_icon_themes.dart'` 改为 `'../core/constants/app_icons.dart'`（解除对 Flutter Material 的依赖）
- `lib/services/common/dev_mode_service.dart`：
  - 移除 `DevModeLabel` UI 组件类（194 行，依赖 `app_snack_bar.dart` 和 Flutter Material）
  - 移除 `triggerCode = '0828'` 常量（开源后触发码无意义，使用方应自行设计 UI 入口）
  - `import 'package:flutter/material.dart'` 改为 `import 'package:flutter/foundation.dart'`（仅需 ChangeNotifier）
- `pubspec.yaml` 从 application 形式改为 library 形式，移除 19 个 UI 相关依赖（cupertino_icons / image_picker / file_picker / flutter_animate / flutter_markdown / flutter_screenutil 等），仅保留后端实际 import 的 12 个第三方包

### 移除 / Removed

- 移除原项目的 UI 层（`lib/screens/`）、主题层（`lib/theme/`）、应用入口（`lib/main.dart`）
- 移除原项目的平台配置（`android/` / `ios/` / `windows/` 等）
- 移除原项目的资源文件（`assets/`）
- 移除 `dev_mode_service.dart` 中的 `DevModeLabel` UI 组件和 `triggerCode` 常量

### 隐私保护 / Privacy

- 删除 `reports/` 目录（saropa_lints 工具缓存，含开发机本地路径）
- 在 `.gitignore` 中添加 `reports/` / `.saropa_session` / `.saropa_lints/` 忽略规则
- 验证无硬编码 API Key / Token / 个人信息 / 数据库凭证泄露

### 已知问题 / Known Issues

- `services/` 根目录仍有 45 个文件平铺，可继续按 `ai/` / `memory/` / `storage/` / `speech/` 子域拆分
- 4 个 info 级 lint 项（与原项目一致，非新增）：
  - `speech_recognition_service.dart:246/247/253` deprecated_member_use（speech_to_text 包内部 API 变更）
  - `storage_service.dart:1130` unintended_html_in_doc_comment
- `backup_provider` / `chat_provider` 中仍有同步 IO 调用未迁移到 async
- 无前端 UI，需使用方自行实现或等待社区贡献

### 验证 / Verified

- `dart analyze lib`：0 error, 0 warning, 4 info
- `flutter pub get`：110 个依赖成功解析
- 隐私扫描：无敏感信息泄露
