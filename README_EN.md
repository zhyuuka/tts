# Xingling Chat (xingling_chat) Community Edition

[![License: MIT](https://img.shields.io/github/license/zhyuuka/xingling_chat_community?color=blue)](LICENSE)
[![CI](https://github.com/zhyuuka/xingling_chat_community/actions/workflows/ci.yml/badge.svg)](https://github.com/zhyuuka/xingling_chat_community/actions/workflows/ci.yml)
[![Last Commit](https://img.shields.io/github/last-commit/zhyuuka/xingling_chat_community)](https://github.com/zhyuuka/xingling_chat_community/commits/main)
[![Dart](https://img.shields.io/badge/Dart-3.x-0175C2?logo=dart)](https://dart.dev)
[![Flutter](https://img.shields.io/badge/Flutter-3.x-02569B?logo=flutter)](https://flutter.dev)


> Flutter backend library for multi-AI integration / dual-track long-term memory / Agent automation

English | [简体中文](./README.md)

---

## Important Notice (Please Read First)

**This project is a "half-finished" work — it contains only backend code, with no frontend UI.**

Honestly, I am a vibe coder — I code by intuition and passion, without a systematic programming foundation. I independently completed the backend design and implementation, but due to insufficient ability, frontend development has repeatedly hit setbacks, and **I have never been able to complete the frontend UI part**. The backend code has gone through multiple rounds of review and refactoring, with a relatively clear structure, but without UI it cannot be run or demonstrated directly.

Development was full of setbacks, and I almost gave up. I ultimately chose to open-source it because:

1. **Not letting the completed code go to waste**: The backend implements fairly complete capabilities including 17 AI service integrations, dual-track long-term memory, and Agent automation — it would be a pity to let it sit idle.
2. **Sincerely inviting community contributions for the frontend**: If you are skilled in Flutter UI development, you are welcome to contribute a frontend for this project. Whether it's a complete chat interface, settings page, or just partial components, all contributions are welcome.
3. **Learning and growing together**: The code inevitably has many shortcomings — please point out problems and offer suggestions. I will accept them humbly.

**If you are looking for an "out-of-the-box" chat application, this project is not suitable for you at this time.** But if you are willing to participate in building it, you are welcome to join.

---

## Project Overview

**Xingling Chat** is positioned as a "Personal AI Assistant + Mobile Automation Agent" two-in-one tool. This repository is its **backend core code** (Community Edition), including:

- **Service Layer** (`lib/services/`, 67 files): 9 subdomains including AI adapters, memory, storage, Agent, voice, OCR, search
- **State Layer** (`lib/providers/`, 10 files): State management and orchestration based on `ChangeNotifier`
- **Data Model Layer** (`lib/models/`, 9 files): Messages, conversations, attachments, Agent tasks
- **Infrastructure Layer** (`lib/core/`, 5 files): Bootstrapping, logging, error system
- **Data Layer** (`lib/data/`, 1 file): Changelog data
- **Utility Layer** (`lib/util/`, 4 files): Attachment byte handling, image cache

**Not included**: UI components (`screens/`), themes (`theme/`), app entry (`main.dart`), platform configurations (`android/` / `ios/`), asset files (`assets/`).

---

## Backend Capabilities

### 1. Unified Multi-AI Provider Integration

Supports 17 AI service providers with a unified abstract interface and factory pattern:

| Category | Providers | Notes |
|---|---|---|
| International | OpenAI / Gemini / Hugging Face | |
| China | DeepSeek / Doubao / Tongyi / Hunyuan / Moonshot / Zhipu / MiniMax / StepFun / Baichuan / iFlytek Spark / Lingyi Wanwu / ERNIE / Guiji | |
| Custom | Any OpenAI-compatible endpoint | Supports Ollama / vLLM etc. |

Features: streaming SSE responses, multimodal messages (text/image/PDF), context window management, token estimation.

### 2. Dual-Track Long-Term Memory System

- **MemU Intelligent Memory** (`memu_service.dart`, 1104 lines): WAL write-ahead logging, AI semantic scoring, automatic conflict resolution, TF-IDF vector retrieval, persona snapshot and recovery
- **MemLocal Short-Term Memory** (`memlocal_service.dart`, 482 lines): Conversation-level short-term context

### 3. Agent Automation (Android)

Operates the phone via Android accessibility service, with 4-level risk grading + banking protection + operation auditing:

- Perception-thinking-action loop (`agent_service.dart`)
- Native communication bridge (`accessibility_bridge.dart`)
- 4-level risk grading guard (`agent_safety_guard.dart`)
- 12 tool registry (`agent_tool_registry.dart`)
- Operation audit log (`agent_operation_logger.dart`)
- In-chat intent detection (`agent_intent_detector.dart`)

### 4. Multimodal Input

- **Speech Recognition**: Local sherpa_onnx + cloud Whisper/iFlytek/Tongyi
- **OCR**: Local ML Kit + Baidu/Tencent/Alibaba Cloud
- **Attachments**: Images / PDF / Files

### 5. Local TTS

Self-developed NCNN neural network speech synthesis (C++/Kotlin/Dart three layers), all platforms including HarmonyOS.

### 6. Web Search

DuckDuckGo / SearXNG / Bing / Google four-engine integration.

### 7. Settings System (Facade + Repository)

`SettingsService` acts as a facade, forwarding to 8 subdomain Repositories: AI / Search / Appearance / Speech / TTS / Agent / Changelog / OCR.

---

## Tech Stack

| Dimension | Choice | Version |
|---|---|---|
| Framework | Flutter + Dart | SDK ^3.11.1 |
| State Management | Provider (ChangeNotifier) | ^6.1.1 (backend only uses ChangeNotifier) |
| Network Layer | Dio + SSE streaming parser | ^5.4.0 |
| Local Storage | Hive (NoSQL) + JSON files | ^2.2.3 |
| Secure Storage | flutter_secure_storage (hardware encryption) | ^9.2.2 |
| Speech Recognition | speech_to_text + sherpa_onnx | ^7.0.0 / ^1.13.2 |
| OCR | google_mlkit_text_recognition | ^0.15.0 |
| Env Variables | flutter_dotenv | ^5.1.0 |
| Logging | logger | ^2.0.2+1 |

See [`pubspec.yaml`](./pubspec.yaml) for full dependencies.

---

## Project Structure

```
community_edition/
├── lib/                          ← Backend core code
│   ├── core/                     ← Infrastructure layer (5 files)
│   │   ├── app_bootstrap.dart    ← 6-stage boot orchestrator
│   │   ├── logger/               ← Logging + 4 regex desensitization groups
│   │   ├── errors/               ← sealed class error system
│   │   └── constants/            ← Constants (AppIcons added in open-source version)
│   ├── services/                 ← Service layer (67 files, grouped by subdomain)
│   │   ├── ai_service.dart       ← AI abstract base class (with common SSE parser)
│   │   ├── ai_service_factory.dart ← 17-provider factory (single entry point)
│   │   ├── *_service.dart × 16   ← Each AI provider implementation
│   │   ├── storage_service.dart  ← File storage (36 public methods)
│   │   ├── settings_service.dart ← Settings center Facade (772 lines)
│   │   ├── memu_service.dart     ← Intelligent memory manager (1104 lines)
│   │   ├── memlocal_service.dart ← Local short-term memory (482 lines)
│   │   ├── memory_*.dart × 5     ← Memory subsystems
│   │   ├── agent/                ← Agent automation subdomain (6 files)
│   │   ├── settings/             ← Settings Facade (8 Repositories)
│   │   ├── vision/               ← Vision subdomain (OCR)
│   │   ├── search/               ← Search subdomain
│   │   └── common/               ← Common utilities subdomain (6 files)
│   ├── providers/                ← State layer (10 files)
│   │   ├── chat_provider.dart    ← Chat Facade (403 lines)
│   │   ├── chat_send_orchestrator.dart ← Send orchestration
│   │   ├── chat_streaming_controller.dart ← Streaming control
│   │   ├── conversation_loader.dart ← Conversation loading
│   │   ├── ai_service_switcher.dart ← AI service switching
│   │   └── ...
│   ├── models/                   ← Data model layer (9 files)
│   │   ├── message.dart / conversation.dart / attachment.dart
│   │   └── agent/                ← Agent task models
│   ├── data/                     ← Data layer
│   │   └── changelog_data.dart   ← Changelog data
│   └── util/                     ← Utility layer (4 files)
│       ├── attachment_bytes.dart ← Attachment byte loading (conditional import)
│       └── image_cache_manager.dart ← Image cache
├── pubspec.yaml                  ← Dependency declaration
├── analysis_options.yaml         ← Lint rules
├── .env.example                  ← API Key template
├── .gitignore
├── LICENSE                       ← MIT
├── CONTRIBUTING.md               ← Contribution guide
├── CODE_OF_CONDUCT.md            ← Code of Conduct
├── SECURITY.md                   ← Security policy
├── .github/                      ← GitHub config
│   ├── ISSUE_TEMPLATE/           ← Issue templates
│   │   ├── bug_report.md
│   │   └── feature_request.md
│   └── PULL_REQUEST_TEMPLATE.md  ← PR template
├── README.md                     ← Chinese README
└── README_EN.md                  ← This file
```

---

## How to Use

### Option 1: Add as a dependency to your own Flutter project

1. Add to your Flutter project's `pubspec.yaml`:

```yaml
dependencies:
  xingling_chat_community:
    git:
      url: https://github.com/zhyuuka/xingling_chat_community.git
      ref: main
```

2. Import the modules you need in your code:

```dart
import 'package:xingling_chat_community/services/ai_service_factory.dart';
import 'package:xingling_chat_community/services/settings_service.dart';
import 'package:xingling_chat_community/providers/chat_provider.dart';

// Create AI service
final aiService = AiServiceFactory.createService('deepseek');

// Use settings service
final settings = SettingsService();
await settings.init();

// Use ChatProvider (needs your UI)
final chatProvider = ChatProvider(...);
```

3. Implement the UI layer yourself (chat interface, settings pages, etc.) and connect to the backend via Provider or other state management approaches.

### Option 2: Clone for study and learning

```bash
git clone https://github.com/zhyuuka/xingling_chat_community.git
cd xingling_chat_community
flutter pub get
dart analyze lib
```

---

## Configuring API Keys

The backend reads API keys via `flutter_secure_storage` (hardware-encrypted storage). At runtime, the UI layer calls `SettingsService.setApiKey()` to write them.

For development, you can use a `.env` file to configure default keys (read by `ai_service_factory.dart` via `flutter_dotenv`):

```bash
cp .env.example .env
# Edit .env to fill in your API keys
```

See [`.env.example`](./.env.example) for supported providers.

---

## Static Analysis & Testing

```bash
# Static analysis (should return 0 errors)
dart analyze lib

# Full lint check
flutter analyze

# Run unit tests (if any)
flutter test test/unit/
```

---

## Contribution Guide

**Our most urgent need is frontend UI contributions**, but backend code improvements, documentation enhancements, and issue reports are also welcome.

See [CONTRIBUTING.md](./CONTRIBUTING.md) for details.

### Current Backend TODOs

- `services/` root directory still has 45 flat files; can be further split into `ai/` / `memory/` / `storage/` / `speech/` subdomains
- 10 info-level lint items (code style suggestions, do not affect functionality)
- `backup_provider` / `chat_provider` still have synchronous IO calls not migrated to async

### Frontend Contribution Suggestions

If you'd like to contribute the frontend, recommended priorities:

1. **Chat main interface**: Message list + input box + streaming rendering (connect to `ChatProvider`)
2. **Settings page**: AI service selection + API key input + model selection (connect to `SettingsService`)
3. **Conversation management**: Conversation list + switching + renaming + deletion (connect to `ConversationProvider`)
4. **Memory dashboard**: View / edit memory entries (connect to `MemoryProvider`)

---

## License

[MIT License](./LICENSE)

Copyright (c) 2026 Xingling Chat Community Edition Contributors

---

## Security Policy

If you discover a security vulnerability, please DO NOT report it in a public issue. See [SECURITY.md](./SECURITY.md) for details.

---

## Code of Conduct

By participating in this project, you agree to abide by [CODE_OF_CONDUCT.md](./CODE_OF_CONDUCT.md). Please be friendly, respectful, and inclusive.

---

## Acknowledgements

- Thanks to the Flutter / Dart teams for the excellent toolchain
- Thanks to all AI service providers for their APIs
- Thanks to every future contributor who will offer code or suggestions for this project

---

## Contact

- File an Issue: [GitHub Issues](https://github.com/zhyuuka/xingling_chat_community/issues)
- Submit a Pull Request: Welcome
- Email (primary): 3684939695@qq.com
- Email (secondary): zhyuuka@gmail.com

I have limited ability and may not respond in time, but will carefully read every piece of feedback. Thank you again for your attention and support.
