# 贡献指南 / Contributing Guide

首先，**非常感谢**你考虑为杏铃聊天社区版做贡献！

First of all, **thank you so much** for considering contributing to Xingling Chat Community Edition!

---

## 最迫切的需求：前端 UI / Most Urgent Need: Frontend UI

如 README 所述，我是一名 vibe coder，凭直觉和热情写代码，独立完成了后端，但**无法独立完成前端 UI**。如果你擅长 Flutter UI 开发，这是最有价值的贡献方向。

As stated in the README, I am a vibe coder who codes by intuition and passion, independently completed the backend but **cannot independently complete the frontend UI**. If you are skilled in Flutter UI development, this is the most valuable contribution direction.

### 优先级 / Priorities

1. **聊天主界面 / Chat Main Screen**
   - 消息列表（支持流式渲染）/ Message list (with streaming rendering)
   - 输入框（多行 + 表情 + 附件）/ Input box (multi-line + emoji + attachments)
   - 连接 `ChatProvider` / Connect to `ChatProvider`

2. **设置页面 / Settings Page**
   - AI 服务选择 / AI service selection
   - API Key 输入 / API key input
   - 模型选择 / Model selection
   - 连接 `SettingsService` / Connect to `SettingsService`

3. **会话管理 / Conversation Management**
   - 会话列表 + 切换 + 重命名 + 删除 / List + switch + rename + delete
   - 连接 `ConversationProvider` / Connect to `ConversationProvider`

4. **记忆仪表板 / Memory Dashboard**
   - 查看 / 编辑记忆条目 / View / edit memory entries
   - 连接 `MemoryProvider` / Connect to `MemoryProvider`

---

## 后端贡献也欢迎 / Backend Contributions Also Welcome

也欢迎后端代码改进、Bug 修复、性能优化、文档完善、测试补充。

Backend code improvements, bug fixes, performance optimizations, documentation enhancements, and test additions are also welcome.

### 当前后端待优化项 / Current Backend TODOs

- `services/` 根目录仍有 45 个文件平铺，可继续按 `ai/` / `memory/` / `storage/` / `speech/` 子域拆分
- 10 个 info 级 lint 项（代码风格建议）
- `backup_provider` / `chat_provider` 中仍有同步 IO 调用未迁移到 async

---

## 如何贡献 / How to Contribute

### 1. Fork 并克隆仓库 / Fork and Clone

```bash
git clone https://github.com/zhyuuka/xingling_chat_community.git
cd xingling_chat_community
flutter pub get
```

### 2. 创建分支 / Create a Branch

```bash
git checkout -b feature/your-feature-name
# 或 / or
git checkout -b fix/your-bugfix-name
```

### 3. 编写代码 / Write Code

**代码规范 / Code Style**:

- 使用**中文（简体）** 注释，注明"做什么"和"为什么这样做"
- Use Chinese (Simplified) comments, explaining "what" and "why"
- 每个函数都要有文档注释 / Every function should have doc comments
- 遵循现有代码风格 / Follow existing code style
- 保持简洁，不过度工程化 / Keep it simple, no over-engineering

**静态分析 / Static Analysis**:

```bash
dart analyze lib
# 必须返回 0 error / Must return 0 errors
```

### 4. 测试 / Testing

如果你修改了后端逻辑，请确保现有测试通过：

If you modified backend logic, make sure existing tests pass:

```bash
flutter test test/unit/
```

如果你添加了新功能，建议同时添加测试。

If you add new features, consider adding tests as well.

### 5. 提交 / Commit

提交信息格式 / Commit message format:

```
<type>(<scope>): <subject>

<body>
```

类型 / Types:
- `feat`: 新功能 / New feature
- `fix`: Bug 修复 / Bug fix
- `docs`: 文档 / Documentation
- `style`: 代码风格 / Code style
- `refactor`: 重构 / Refactoring
- `test`: 测试 / Tests
- `chore`: 杂项 / Miscellaneous

示例 / Example:

```
feat(ui): 实现聊天主界面消息列表

- 使用 ListView.builder 渲染消息
- 支持流式 SSE 响应实时更新
- 连接 ChatProvider 的 messages getter
```

### 6. 推送并提交 Pull Request / Push and Submit PR

```bash
git push origin feature/your-feature-name
```

然后在 GitHub 上提交 Pull Request，描述你的改动。

Then submit a Pull Request on GitHub, describing your changes.

---

## Pull Request 审查 / PR Review

- 我会在能力范围内尽快审查 / I will review as soon as possible within my ability
- 审查可能提出修改建议 / Review may suggest changes
- 请保持耐心和友善 / Please be patient and kind

---

## 报告 Bug / Reporting Bugs

如果你发现 Bug，请通过 GitHub Issues 提交，包含：

If you find a bug, please submit via GitHub Issues, including:

1. **Bug 描述**：发生了什么？/ Bug description: What happened?
2. **复现步骤**：如何触发？/ Reproduction steps: How to trigger?
3. **期望行为**：应该发生什么？/ Expected behavior: What should happen?
4. **实际行为**：实际发生了什么？/ Actual behavior: What actually happened?
5. **环境信息**：Flutter 版本、平台、设备 / Environment info: Flutter version, platform, device
6. **日志**：如有错误日志请附上 / Logs: Attach error logs if any

---

## 提交功能建议 / Suggesting Features

欢迎通过 GitHub Issues 提交功能建议，请描述：

Feature suggestions via GitHub Issues are welcome. Please describe:

1. **使用场景**：为什么需要这个功能？/ Use case: Why is this feature needed?
2. **建议方案**：你希望怎么实现？/ Proposed solution: How would you like it implemented?
3. **替代方案**：有没有其他选择？/ Alternatives: Are there other options?

---

## 行为准则 / Code of Conduct

本项目遵守 [CODE_OF_CONDUCT.md](./CODE_OF_CONDUCT.md)。请保持友善、尊重、包容。我们欢迎所有水平的贡献者，包括初学者。

This project follows [CODE_OF_CONDUCT.md](./CODE_OF_CONDUCT.md). Please be friendly, respectful, and inclusive. We welcome contributors of all levels, including beginners.

---

## 联系 / Contact

- GitHub Issues: 主要沟通渠道 / Main communication channel
- 邮箱（主要）/ Email (primary): 3684939695@qq.com
- 邮箱（次要）/ Email (secondary): zhyuuka@gmail.com
- 我能力有限，回复可能不及时，但一定会认真阅读 / I have limited ability and may not respond in time, but will carefully read

再次感谢你的贡献！Thanks again for your contribution!
