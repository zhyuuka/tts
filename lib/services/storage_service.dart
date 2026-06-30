import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../core/logger/app_logger.dart';
import '../models/conversation.dart';
import '../models/message.dart';
import 'async_file_writer.dart';
import 'batch_write_scheduler.dart';

class StorageService {
  static const String _appDataDir = 'xingling_data';
  static const String _convListFile = 'conversations.json';
  static const String _chatRecordsDir = 'chat_records';
  static const String _memoriesDir = 'memories';
  static const String _messagesFile = 'messages.json';
  static const String _memoryFile = 'memory.json';

  String? _rootPath;
  bool _initialized = false;
  String _currentServiceId = 'deepseek';

  List<Conversation> _convCache = [];
  bool _convCacheDirty = false;
  DateTime? _convCacheTime;
  static const Duration _convCacheTtl = Duration(seconds: 30);

  final AsyncFileWriter _asyncWriter = AsyncFileWriter.instance;
  final BatchWriteScheduler _batchScheduler = BatchWriteScheduler.instance;

  bool get isInitialized => _initialized;
  String get rootPath => _rootPath ?? '';
  String get currentServiceId => _currentServiceId;

  String get _servicePath => '$_rootPath/$_currentServiceId';
  String get _convListFilePath => '$_servicePath/$_convListFile';

  String messagesFilePath(String convId) =>
      '$_servicePath/$_chatRecordsDir/$convId/$_messagesFile';

  String memoryFilePath(String convId) =>
      '$_servicePath/$_memoriesDir/$convId/$_memoryFile';

  AsyncFileWriter get asyncWriter => _asyncWriter;
  BatchWriteScheduler get batchScheduler => _batchScheduler;

  Future<bool> init({String? customPath, String serviceId = 'deepseek'}) async {
    try {
      _currentServiceId = serviceId;

      if (customPath != null && customPath.isNotEmpty) {
        if (await _testPathWritable(customPath)) {
          _rootPath = customPath;
        } else {
          AppLogger.w('[Storage] 自定义路径不可写 ($customPath)，回退到默认路径');
          _rootPath = await _getDefaultRootPath();
        }
      } else {
        _rootPath = await _getDefaultRootPath();
      }

      AppLogger.i('[Storage] 使用存储路径: $_rootPath');
      AppLogger.i('[Storage] 当前服务: $_currentServiceId');

      Directory('$_servicePath/$_chatRecordsDir').createSync(recursive: true);
      Directory('$_servicePath/$_memoriesDir').createSync(recursive: true);

      final convListFile = File(_convListFilePath);
      if (!convListFile.existsSync()) {
        convListFile.writeAsStringSync(jsonEncode({'conversations': []}));
        AppLogger.i('[Storage] 创建新的 conversations.json');
      } else {
        AppLogger.i(
          '[Storage] 已存在 conversations.json, 大小: ${convListFile.lengthSync()} bytes',
        );
      }

      final testFile = File('$_rootPath/.health_check');
      testFile.writeAsStringSync('ok');
      final check = testFile.readAsStringSync();
      testFile.deleteSync();
      if (check != 'ok') {
        AppLogger.e('[Storage] 启动读写自检失败！');
        _initialized = false;
        return false;
      }

      _loadConvCache();

      _batchScheduler.configure(
        interval: const Duration(seconds: 5),
        threshold: 3,
      );

      _initialized = true;
      AppLogger.i('[Storage] 初始化成功 (异步写入模式)');

      restoreLostData();
      _convertLegacyMessageFormats();

      return true;
    } catch (e, st) {
      AppLogger.e('[Storage] 初始化失败: $e\n$st');
      _initialized = false;
      return false;
    }
  }

  void _loadConvCache() {
    try {
      final file = File(_convListFilePath);
      if (file.existsSync()) {
        final content = file.readAsStringSync();
        final data = jsonDecode(content) as Map<String, dynamic>;
        final list = data['conversations'] as List<dynamic>? ?? [];
        _convCache =
            list
                .map((e) => Conversation.fromJson(e as Map<String, dynamic>))
                .toList()
              ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
        _convCacheDirty = false;
        _convCacheTime = DateTime.now();
        AppLogger.d('[Storage] 会话缓存加载: ${_convCache.length} 条');
      }
    } catch (e) {
      AppLogger.e('[Storage] 会话缓存加载失败: $e');
      _convCache = [];
    }
  }

  void _updateConvCache(List<Conversation> conversations) {
    _convCache = List<Conversation>.from(conversations)
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    _convCacheDirty = false;
    _convCacheTime = DateTime.now();
  }

  void _convertLegacyMessageFormats() {
    if (!_initialized) return;
    try {
      AppLogger.d('[Storage] 开始检测旧格式聊天记录...');

      final conversations = getConversations();
      for (final conv in conversations) {
        final messages = getMessages(conv.id);

        bool needsConversion = false;
        for (final msg in messages) {
          if (msg.content.isEmpty ||
              !['user', 'assistant', 'system'].contains(msg.role)) {
            needsConversion = true;
            break;
          }
        }

        if (needsConversion) {
          AppLogger.i('[Storage] 检测到会话 ${conv.id} 需要格式转换');
          _convertLegacyMessages(conv.id);
        }
      }

      AppLogger.d('[Storage] 旧格式检测完成');
    } catch (e) {
      AppLogger.e('[Storage] 检测旧格式聊天记录失败: $e');
    }
  }

  void _convertLegacyMessages(String conversationId) {
    try {
      final oldFile = File(messagesFilePath(conversationId));
      if (!oldFile.existsSync()) return;

      final backupFile = File('${oldFile.path}.backup');
      oldFile.copySync(backupFile.path);

      final content = oldFile.readAsStringSync();
      final list = jsonDecode(content) as List<dynamic>;

      final convertedMessages = <Message>[];

      for (final item in list) {
        final json = item as Map<String, dynamic>;
        final message = Message.fromJson(json);

        if (message.content.isEmpty) {
          final converted = _convertLegacyMessageFormat(json);
          convertedMessages.add(converted);
        } else {
          convertedMessages.add(message);
        }
      }

      saveMessagesSync(conversationId, convertedMessages);
      AppLogger.i('[Storage] 会话 $conversationId 的消息格式转换完成');
    } catch (e) {
      AppLogger.e('[Storage] 转换旧格式消息失败 ($conversationId): $e');
    }
  }

  Message _convertLegacyMessageFormat(Map<String, dynamic> json) {
    String? role;
    String? content;

    role = json['role'] ?? json['type'] ?? json['sender'] ?? 'user';

    content =
        json['content'] ??
        json['text'] ??
        json['message'] ??
        json['data'] ??
        '';

    if (role is String) {
      role = role.toLowerCase().replaceAll(' ', '');
      if (role.contains('user')) {
        role = 'user';
      } else if (role.contains('assistant') ||
          role.contains('ai') ||
          role.contains('bot')) {
        role = 'assistant';
      } else if (role.contains('system')) {
        role = 'system';
      }
    }

    return Message(role: role ?? 'user', content: content ?? '');
  }

  void restoreLostData() {
    if (!_initialized) return;
    try {
      AppLogger.d('[Storage] 开始检查并恢复丢失的历史聊天记录...');

      final currentConvFile = File(_convListFilePath);

      if (!currentConvFile.existsSync() || currentConvFile.lengthSync() == 0) {
        final rootConvFile = File('$_rootPath/$_convListFile');
        final rootChatDir = Directory('$_rootPath/$_chatRecordsDir');

        if (rootConvFile.existsSync()) {
          AppLogger.i('[Storage] 检测到根目录有历史数据，开始恢复...');

          if (!currentConvFile.existsSync()) {
            rootConvFile.copySync(currentConvFile.path);
            AppLogger.i('[Storage] 恢复会话列表完成');
          }

          if (rootChatDir.existsSync()) {
            final serviceChatDir = Directory('$_servicePath/$_chatRecordsDir');
            serviceChatDir.createSync(recursive: true);

            for (final entity in rootChatDir.listSync()) {
              if (entity is Directory) {
                final target = Directory(
                  '${serviceChatDir.path}/${entity.path.split(Platform.pathSeparator).last}',
                );
                if (!target.existsSync()) {
                  _copyDirectorySync(entity, target);
                }
              }
            }
            AppLogger.i('[Storage] 恢复聊天记录完成');
          }

          AppLogger.i('[Storage] 历史聊天记录恢复成功！');
          _loadConvCache();
        } else {
          AppLogger.d('[Storage] 未找到可恢复的历史数据');
        }
      } else {
        AppLogger.d('[Storage] 当前服务目录已有数据，无需恢复');
      }
    } catch (e) {
      AppLogger.e('[Storage] 恢复历史聊天记录失败: $e');
    }
  }

  void migrateLegacyData() {
    if (!_initialized) return;
    try {
      final oldConvFile = File('$_rootPath/$_convListFile');
      if (!oldConvFile.existsSync()) return;

      AppLogger.i('[Storage] 检测到旧版数据，开始迁移到 $_currentServiceId/ ...');
      final oldChatDir = Directory('$_rootPath/$_chatRecordsDir');
      final oldMemDir = Directory('$_rootPath/$_memoriesDir');

      if (oldConvFile.existsSync()) {
        final serviceConvFile = File(_convListFilePath);
        if (!serviceConvFile.existsSync()) {
          oldConvFile.copySync(serviceConvFile.path);
          AppLogger.i('[Storage] 迁移 conversations.json 完成');
        }
      }

      if (oldChatDir.existsSync()) {
        final serviceChatDir = Directory('$_servicePath/$_chatRecordsDir');
        for (final entity in oldChatDir.listSync()) {
          if (entity is Directory) {
            final target = Directory(
              '${serviceChatDir.path}/${entity.path.split(Platform.pathSeparator).last}',
            );
            if (!target.existsSync()) {
              _copyDirectorySync(entity, target);
            }
          }
        }
        AppLogger.i('[Storage] 迁移 chat_records 完成');
      }

      if (oldMemDir.existsSync()) {
        final serviceMemDir = Directory('$_servicePath/$_memoriesDir');
        for (final entity in oldMemDir.listSync()) {
          if (entity is Directory) {
            final target = Directory(
              '${serviceMemDir.path}/${entity.path.split(Platform.pathSeparator).last}',
            );
            if (!target.existsSync()) {
              _copyDirectorySync(entity, target);
            }
          }
        }
        AppLogger.i('[Storage] 迁移 memories 完成');
      }

      AppLogger.i('[Storage] 旧版数据迁移完成，旧数据保留为备份');

      final backupInfoFile = File('$_rootPath/backup_info.txt');
      backupInfoFile.writeAsStringSync('''
数据迁移备份信息
迁移时间: ${DateTime.now()}
原路径: $_rootPath
目标路径: $_servicePath
旧数据已保留，如需恢复请手动复制
      ''');

      _loadConvCache();
    } catch (e) {
      AppLogger.e('[Storage] 旧版数据迁移失败: $e');
    }
  }

  void _copyDirectorySync(Directory source, Directory target) {
    target.createSync(recursive: true);
    for (final entity in source.listSync(recursive: false)) {
      final name = entity.path.split(Platform.pathSeparator).last;
      if (entity is File) {
        entity.copySync('${target.path}/$name');
      } else if (entity is Directory) {
        _copyDirectorySync(entity, Directory('${target.path}/$name'));
      }
    }
  }

  void switchService(String serviceId) {
    _currentServiceId = serviceId;
    AppLogger.i('[Storage] 切换服务到: $serviceId, 路径: $_servicePath');

    Directory('$_servicePath/$_chatRecordsDir').createSync(recursive: true);
    Directory('$_servicePath/$_memoriesDir').createSync(recursive: true);

    final convListFile = File(_convListFilePath);
    if (!convListFile.existsSync()) {
      convListFile.writeAsStringSync(jsonEncode({'conversations': []}));
    }

    _loadConvCache();
  }

  // ── 会话列表管理（带缓存） ──

  /// 获取会话列表（同步，带缓存）。
  ///
  /// 已废弃：建议外部调用使用 [getConversationsAsync] 替代，避免主线程阻塞。
  /// 为什么废弃：同步读文件会阻塞 UI 线程，30 个会话的 conversations.json
  /// 可能达 60MB，会导致明显卡顿。
  /// 保留 sync 版本供内部 backup/import 等兼容逻辑使用（待逐步迁移到 async）。
  @Deprecated('使用 getConversationsAsync 替代，避免阻塞 UI 线程')
  List<Conversation> getConversations() {
    if (!_initialized) {
      AppLogger.w('[Storage] getConversations: 未初始化！');
      return [];
    }

    final cacheValid =
        !_convCacheDirty &&
        _convCache.isNotEmpty &&
        _convCacheTime != null &&
        DateTime.now().difference(_convCacheTime!) < _convCacheTtl;
    if (cacheValid) {
      return List<Conversation>.from(_convCache);
    }

    try {
      final file = File(_convListFilePath);
      if (!file.existsSync()) {
        AppLogger.w('[Storage] getConversations: 文件不存在 ${file.path}');
        return [];
      }
      final content = file.readAsStringSync();
      final data = jsonDecode(content) as Map<String, dynamic>;
      final list = data['conversations'] as List<dynamic>? ?? [];
      final result =
          list
              .map((e) => Conversation.fromJson(e as Map<String, dynamic>))
              .toList()
            ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

      _convCache = result;
      _convCacheDirty = false;
      _convCacheTime = DateTime.now();

      return List<Conversation>.from(result);
    } catch (e) {
      AppLogger.e('[Storage] getConversations 读取失败: $e');
      return List<Conversation>.from(_convCache);
    }
  }

  /// 异步获取会话列表（带缓存）。
  /// 为什么新增：原 getConversations 是 sync 版本，缓存失效时 sync 读文件阻塞主线程。
  /// 外部调用应优先使用此方法，内部兼容逻辑（backup/import）仍可用 sync 版本。
  Future<List<Conversation>> getConversationsAsync() async {
    if (!_initialized) {
      AppLogger.w('[Storage] getConversationsAsync: 未初始化！');
      return [];
    }

    final cacheValid =
        !_convCacheDirty &&
        _convCache.isNotEmpty &&
        _convCacheTime != null &&
        DateTime.now().difference(_convCacheTime!) < _convCacheTtl;
    if (cacheValid) {
      return List<Conversation>.from(_convCache);
    }

    try {
      final file = File(_convListFilePath);
      if (!await file.exists()) {
        AppLogger.w('[Storage] getConversationsAsync: 文件不存在 ${file.path}');
        return [];
      }
      final content = await file.readAsString();
      final data = jsonDecode(content) as Map<String, dynamic>;
      final list = data['conversations'] as List<dynamic>? ?? [];
      final result =
          list
              .map((e) => Conversation.fromJson(e as Map<String, dynamic>))
              .toList()
            ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

      _convCache = result;
      _convCacheDirty = false;
      _convCacheTime = DateTime.now();

      return List<Conversation>.from(result);
    } catch (e) {
      AppLogger.e('[Storage] getConversationsAsync 读取失败: $e');
      return List<Conversation>.from(_convCache);
    }
  }

  /// 获取会话列表的元数据（剥离 base64，用于列表展示）。
  /// 为什么新增：getConversations 返回完整数据（含 base64），
  /// 侧边栏列表只需 name/id/updatedAt，却加载了每个会话的完整 base64（30个会话可达60MB）。
  /// 此方法反序列化时把 avatarBase64/wallpaperBase64 置空，大幅降低列表内存占用。
  /// getConversations 保持不变，供 updateConversationAppearanceAsync 等需要完整数据的内部逻辑使用。
  List<Conversation> getConversationsMetadata() {
    if (!_initialized) {
      AppLogger.w('[Storage] getConversationsMetadata: 未初始化！');
      return [];
    }

    try {
      final file = File(_convListFilePath);
      if (!file.existsSync()) {
        AppLogger.w('[Storage] getConversationsMetadata: 文件不存在 ${file.path}');
        return [];
      }
      final content = file.readAsStringSync();
      final data = jsonDecode(content) as Map<String, dynamic>;
      final list = data['conversations'] as List<dynamic>? ?? [];
      final result = list.map((e) {
        final json = Map<String, dynamic>.from(e as Map<String, dynamic>);
        // 剥离大字段，列表展示不需要
        json['avatarBase64'] = '';
        json['wallpaperBase64'] = '';
        return Conversation.fromJson(json);
      }).toList()..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      return result;
    } catch (e) {
      AppLogger.e('[Storage] getConversationsMetadata 读取失败: $e');
      return [];
    }
  }

  /// 异步按需加载单个会话的外观（头像/壁纸 base64）。
  /// 为什么新增：列表用 getConversationsMetadata 剥离了 base64，
  /// 切换会话时需单独加载当前会话的 base64 供 UI 渲染。
  /// 优先从 _convCache 查找（缓存可能含完整数据），未命中则从磁盘读取。
  Future<({String avatarBase64, String wallpaperBase64})>
  getConversationAppearanceAsync(String id) async {
    if (!_initialized) {
      return (avatarBase64: '', wallpaperBase64: '');
    }

    try {
      // 优先从缓存查找（缓存可能含完整 base64）
      for (final conv in _convCache) {
        if (conv.id == id) {
          return (
            avatarBase64: conv.avatarBase64,
            wallpaperBase64: conv.wallpaperBase64,
          );
        }
      }

      // 缓存未命中，从磁盘读取并提取目标会话的 base64
      final file = File(_convListFilePath);
      if (!await file.exists()) {
        return (avatarBase64: '', wallpaperBase64: '');
      }
      final content = await file.readAsString();
      final data = jsonDecode(content) as Map<String, dynamic>;
      final list = data['conversations'] as List<dynamic>? ?? [];
      for (final e in list) {
        final json = e as Map<String, dynamic>;
        if (json['id'] == id) {
          return (
            avatarBase64: json['avatarBase64'] as String? ?? '',
            wallpaperBase64: json['wallpaperBase64'] as String? ?? '',
          );
        }
      }
      return (avatarBase64: '', wallpaperBase64: '');
    } catch (e) {
      AppLogger.e('[Storage] getConversationAppearanceAsync($id) 读取失败: $e');
      return (avatarBase64: '', wallpaperBase64: '');
    }
  }

  bool _saveConversationListSync(List<Conversation> conversations) {
    try {
      final sorted = List<Conversation>.from(conversations)
        ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      final json = jsonEncode({
        'conversations': sorted.map((c) => c.toJson()).toList(),
      });
      final file = File(_convListFilePath);
      file.writeAsStringSync(json, flush: true);
      _updateConvCache(conversations);
      return true;
    } catch (e) {
      AppLogger.e('[Storage] _saveConversationListSync 失败: $e');
      return false;
    }
  }

  Future<bool> _saveConversationListAsync(
    List<Conversation> conversations, {
    bool immediate = false,
  }) async {
    try {
      final sorted = List<Conversation>.from(conversations)
        ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      final json = jsonEncode({
        'conversations': sorted.map((c) => c.toJson()).toList(),
      });

      // P1 #6 修复：先写入文件，成功后再更新缓存。
      // 为什么这样改：原代码先 _updateConvCache（标记 dirty=false）再异步写入，
      // 若写入失败，缓存与文件不一致，后续读会拿到未持久化的脏缓存。
      // 现在写入失败时设置 _convCacheDirty=true，下次读会自动从文件重载。
      final bool ok;
      if (immediate) {
        ok = await _batchScheduler.scheduleImmediate(
          filePath: _convListFilePath,
          content: json,
          flush: true,
          verify: true,
        );
      } else {
        ok = await _batchScheduler.schedule(
          filePath: _convListFilePath,
          content: json,
          flush: true,
          verify: true,
        );
      }

      if (ok) {
        _updateConvCache(conversations);
      } else {
        // 写入失败：标记缓存脏，下次读取时自动从文件重载，避免返回未持久化的数据
        _convCacheDirty = true;
        AppLogger.w('[Storage] _saveConversationListAsync 写入失败，已标记缓存为脏');
      }
      return ok;
    } catch (e) {
      AppLogger.e('[Storage] _saveConversationListAsync 失败: $e');
      _convCacheDirty = true;
      return false;
    }
  }

  // ── 会话 CRUD ──

  Conversation? createConversationSync(String name) {
    if (!_initialized) {
      AppLogger.w('[Storage] createConversationSync: 未初始化！');
      return null;
    }
    try {
      final id = 'conv_${DateTime.now().millisecondsSinceEpoch}';
      final conv = Conversation(id: id, name: name);

      final chatDir = Directory('$_servicePath/$_chatRecordsDir/$id');
      chatDir.createSync(recursive: true);
      File(messagesFilePath(id)).writeAsStringSync(jsonEncode([]), flush: true);

      final memDir = Directory('$_servicePath/$_memoriesDir/$id');
      memDir.createSync(recursive: true);
      File(
        memoryFilePath(id),
      ).writeAsStringSync(jsonEncode({'summaries': []}), flush: true);

      final conversations = getConversations();
      conversations.add(conv);
      _saveConversationListSync(conversations);

      AppLogger.i('[Storage] 创建会话成功: $id');
      return conv;
    } catch (e) {
      AppLogger.e('[Storage] createConversationSync 失败: $e');
      return null;
    }
  }

  Future<Conversation?> createConversationAsync(String name) async {
    if (!_initialized) return null;
    try {
      final id = 'conv_${DateTime.now().millisecondsSinceEpoch}';
      final conv = Conversation(id: id, name: name);

      final chatDir = Directory('$_servicePath/$_chatRecordsDir/$id');
      chatDir.createSync(recursive: true);

      await _asyncWriter.writeJson(
        filePath: messagesFilePath(id),
        data: [],
        flush: true,
      );

      final memDir = Directory('$_servicePath/$_memoriesDir/$id');
      memDir.createSync(recursive: true);

      await _asyncWriter.writeJson(
        filePath: memoryFilePath(id),
        data: {'summaries': []},
        flush: true,
      );

      final conversations = getConversations();
      conversations.add(conv);
      await _saveConversationListAsync(conversations, immediate: true);

      AppLogger.i('[Storage] 异步创建会话成功: $id');
      return conv;
    } catch (e) {
      AppLogger.e('[Storage] createConversationAsync 失败: $e');
      return null;
    }
  }

  bool renameConversationSync(String id, String newName) {
    if (!_initialized) return false;
    final conversations = getConversations();
    final index = conversations.indexWhere((c) => c.id == id);
    if (index == -1) return false;
    conversations[index] = conversations[index].copyWith(
      name: newName,
      updatedAt: DateTime.now(),
    );
    return _saveConversationListSync(conversations);
  }

  Future<bool> renameConversationAsync(String id, String newName) async {
    if (!_initialized) return false;
    final conversations = getConversations();
    final index = conversations.indexWhere((c) => c.id == id);
    if (index == -1) return false;
    conversations[index] = conversations[index].copyWith(
      name: newName,
      updatedAt: DateTime.now(),
    );
    return _saveConversationListAsync(conversations, immediate: true);
  }

  bool setConversationPromptSync(String id, String prompt) {
    if (!_initialized) return false;
    final conversations = getConversations();
    final index = conversations.indexWhere((c) => c.id == id);
    if (index == -1) return false;
    conversations[index] = conversations[index].copyWith(
      systemPrompt: prompt,
      updatedAt: DateTime.now(),
    );
    return _saveConversationListSync(conversations);
  }

  Future<bool> setConversationPromptAsync(String id, String prompt) async {
    if (!_initialized) return false;
    final conversations = getConversations();
    final index = conversations.indexWhere((c) => c.id == id);
    if (index == -1) return false;
    conversations[index] = conversations[index].copyWith(
      systemPrompt: prompt,
      updatedAt: DateTime.now(),
    );
    return _saveConversationListAsync(conversations, immediate: true);
  }

  Future<bool> updateConversationAppearanceAsync(
    String id, {
    String? avatarBase64,
    String? wallpaperBase64,
  }) async {
    if (!_initialized) return false;
    final conversations = getConversations();
    final index = conversations.indexWhere((c) => c.id == id);
    if (index == -1) return false;
    conversations[index] = conversations[index].copyWith(
      avatarBase64: avatarBase64,
      wallpaperBase64: wallpaperBase64,
      updatedAt: DateTime.now(),
    );
    return _saveConversationListAsync(conversations, immediate: true);
  }

  bool deleteConversationSync(String id) {
    if (!_initialized) return false;
    try {
      final chatDir = Directory('$_servicePath/$_chatRecordsDir/$id');
      if (chatDir.existsSync()) {
        chatDir.deleteSync(recursive: true);
      }

      final memDir = Directory('$_servicePath/$_memoriesDir/$id');
      if (memDir.existsSync()) {
        memDir.deleteSync(recursive: true);
      }

      final conversations = getConversations();
      conversations.removeWhere((c) => c.id == id);
      return _saveConversationListSync(conversations);
    } catch (e) {
      AppLogger.e('[Storage] deleteConversationSync 失败: $e');
      return false;
    }
  }

  Future<bool> deleteConversationAsync(String id) async {
    if (!_initialized) return false;
    try {
      final chatDir = Directory('$_servicePath/$_chatRecordsDir/$id');
      if (chatDir.existsSync()) {
        chatDir.deleteSync(recursive: true);
      }

      final memDir = Directory('$_servicePath/$_memoriesDir/$id');
      if (memDir.existsSync()) {
        memDir.deleteSync(recursive: true);
      }

      final conversations = getConversations();
      conversations.removeWhere((c) => c.id == id);
      return _saveConversationListAsync(conversations, immediate: true);
    } catch (e) {
      AppLogger.e('[Storage] deleteConversationAsync 失败: $e');
      return false;
    }
  }

  void touchConversationSync(String id) {
    if (!_initialized) return;
    try {
      final conversations = getConversations();
      final index = conversations.indexWhere((c) => c.id == id);
      if (index != -1) {
        conversations[index] = conversations[index].copyWith(
          updatedAt: DateTime.now(),
        );
        _saveConversationListAsync(conversations);
      }
    } catch (e) {
      AppLogger.e('[Storage] touchConversationSync 失败: $e');
    }
  }

  // ── 聊天记录 ──

  /// 同步获取指定会话的消息列表。
  ///
  /// 已废弃：建议外部调用使用 [getMessagesAsync] 替代。
  /// 为什么废弃：同步读文件会阻塞 UI 线程，单个会话消息文件较大时
  /// 会导致 UI 卡顿。
  @Deprecated('使用 getMessagesAsync 替代，避免阻塞 UI 线程')
  List<Message> getMessages(String conversationId) {
    if (!_initialized) {
      AppLogger.w('[Storage] getMessages: 未初始化！');
      return [];
    }
    try {
      final file = File(messagesFilePath(conversationId));
      if (!file.existsSync()) {
        AppLogger.w('[Storage] getMessages: 文件不存在 $conversationId');
        return [];
      }
      final content = file.readAsStringSync();
      final list = jsonDecode(content) as List<dynamic>;
      return list
          .map((e) => Message.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      AppLogger.e('[Storage] getMessages($conversationId) 读取失败: $e');
      return [];
    }
  }

  Future<List<Message>> getMessagesAsync(String conversationId) async {
    if (!_initialized) {
      AppLogger.w('[Storage] getMessagesAsync: 未初始化！');
      return [];
    }
    try {
      final file = File(messagesFilePath(conversationId));
      if (!await file.exists()) {
        AppLogger.w('[Storage] getMessagesAsync: 文件不存在 $conversationId');
        return [];
      }
      final content = await file.readAsString();
      final list = jsonDecode(content) as List<dynamic>;
      return list
          .map((e) => Message.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      AppLogger.e('[Storage] getMessagesAsync($conversationId) 读取失败: $e');
      return [];
    }
  }

  /// 同步保存指定会话的消息列表。
  ///
  /// 已废弃：建议外部调用使用 [saveMessagesAsync] 替代。
  /// 为什么废弃：同步写文件会阻塞 UI 线程，消息量大时会导致 UI 卡顿；
  /// async 版本通过 AsyncFileWriter 在 Isolate 中写入。
  @Deprecated('使用 saveMessagesAsync 替代，避免阻塞 UI 线程')
  bool saveMessagesSync(String conversationId, List<Message> messages) {
    if (!_initialized) {
      AppLogger.w('[Storage] saveMessagesSync: 未初始化！无法保存！');
      return false;
    }
    try {
      final dir = Directory('$_servicePath/$_chatRecordsDir/$conversationId');
      if (!dir.existsSync()) {
        dir.createSync(recursive: true);
      }
      final jsonList = messages.map((m) => m.toJson()).toList();
      final jsonStr = jsonEncode(jsonList);
      final filePath = messagesFilePath(conversationId);
      final file = File(filePath);
      file.writeAsStringSync(jsonStr, flush: true);

      final verify = file.readAsStringSync();
      if (verify != jsonStr) {
        AppLogger.e('[Storage] saveMessagesSync: 写入验证失败！');
        return false;
      }

      touchConversationSync(conversationId);
      return true;
    } catch (e) {
      AppLogger.e('[Storage] saveMessagesSync($conversationId) 失败: $e');
      return false;
    }
  }

  Future<bool> saveMessagesAsync(
    String conversationId,
    List<Message> messages, {
    bool verify = true,
  }) async {
    if (!_initialized) return false;
    try {
      final dir = Directory('$_servicePath/$_chatRecordsDir/$conversationId');
      if (!dir.existsSync()) {
        dir.createSync(recursive: true);
      }

      final jsonList = messages.map((m) => m.toJson()).toList();
      final jsonStr = jsonEncode(jsonList);
      final filePath = messagesFilePath(conversationId);

      final result = await _asyncWriter.write(
        filePath: filePath,
        content: jsonStr,
        flush: true,
        verify: verify,
      );

      touchConversationSync(conversationId);
      return result;
    } catch (e) {
      AppLogger.e('[Storage] saveMessagesAsync($conversationId) 失败: $e');
      return false;
    }
  }

  bool clearMessagesSync(String conversationId) {
    return saveMessagesSync(conversationId, []);
  }

  Future<bool> clearMessagesAsync(String conversationId) async {
    return saveMessagesAsync(conversationId, []);
  }

  // ── 备份操作 ──

  Future<String?> exportBackup() async {
    try {
      final conversations = getConversations();
      final backupData = <String, dynamic>{
        'version': 2,
        'serviceId': _currentServiceId,
        'exportTime': DateTime.now().toIso8601String(),
        'conversations': conversations.map((c) {
          final messages = getMessages(c.id);
          return {
            ...c.toJson(),
            'messages': messages.map((m) => m.toJson()).toList(),
          };
        }).toList(),
      };

      Directory? backupBaseDir;
      try {
        if (Platform.isAndroid) {
          final externalDir = await getExternalStorageDirectory();
          if (externalDir != null) {
            backupBaseDir = Directory(
              '${externalDir.path}/XinglingChat/backup',
            );
          }
        } else if (Platform.isIOS) {
          final appDir = await getApplicationDocumentsDirectory();
          backupBaseDir = Directory('${appDir.path}/XinglingChat/backup');
        } else {
          final appDir = await getApplicationDocumentsDirectory();
          backupBaseDir = Directory('${appDir.path}/XinglingChat/backup');
        }
      } catch (_) {
        // path_provider 不可用（如测试环境），回退到 _rootPath
      }

      backupBaseDir ??= Directory('$_rootPath/backup');

      if (!backupBaseDir.existsSync()) {
        backupBaseDir.createSync(recursive: true);
      }

      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final filePath = '${backupBaseDir.path}/xingling_backup_$timestamp.json';
      await File(
        filePath,
      ).writeAsString(const JsonEncoder.withIndent('  ').convert(backupData));
      return filePath;
    } catch (e) {
      AppLogger.e('[Storage] exportBackup 失败: $e');
      return null;
    }
  }

  Future<int?> importBackup(String filePath) async {
    try {
      final file = File(filePath);
      if (!file.existsSync()) return null;

      final content = await file.readAsString();
      // P1 #8 修复：把 CPU 密集的 jsonDecode + 消息转换移到 isolate，避免阻塞 UI 线程。
      // 为什么这样做：原代码在主线程做 jsonDecode（大备份可能几 MB）+ 逐条 Message.fromJson，
      // 导入大备份时 UI 会明显卡顿。compute 内部用 Isolate.run 在独立 isolate 执行。
      final parsed = await compute(_parseBackupContent, content);
      final version = parsed['version'] as int? ?? 1;
      int importedCount = 0;

      if (version >= 2) {
        final items = (parsed['items'] as List<_BackupItem>?) ?? const [];
        for (final item in items) {
          // 写入操作用 async 版本，避免在主线程做 sync 文件 IO
          final created = await createConversationAsync(item.conversation.name);
          if (created == null) continue;

          if (item.conversation.systemPrompt.isNotEmpty) {
            await setConversationPromptAsync(
              created.id,
              item.conversation.systemPrompt,
            );
          }

          await saveMessagesAsync(created.id, item.messages);
          importedCount++;
        }
      } else {
        final messages =
            (parsed['legacyMessages'] as List<Message>?) ?? const [];
        final conv = await createConversationAsync('导入的对话');
        if (conv != null) {
          await saveMessagesAsync(conv.id, messages);
          importedCount = 1;
        }
      }

      return importedCount;
    } catch (e) {
      AppLogger.e('[Storage] importBackup 失败: $e');
      return null;
    }
  }

  // ── 生命周期 ──

  Future<void> flushPendingWrites() async {
    if (!_initialized) return;
    AppLogger.i('[Storage] 开始 flush 待写入数据...');
    await _batchScheduler.flushAndWait();
    AppLogger.i('[Storage] flush 完成');
  }

  Future<void> close() async {
    await flushPendingWrites();
    _batchScheduler.dispose();
    _asyncWriter.dispose();
    _initialized = false;
    AppLogger.i('[Storage] 已关闭');
  }

  Map<String, dynamic> getWriteStats() {
    return {
      'asyncWriter': {
        'totalWrites': _asyncWriter.totalWrites,
        'failedWrites': _asyncWriter.failedWrites,
        'avgWriteMs': _asyncWriter.avgWriteMs.toStringAsFixed(2),
      },
      'batchScheduler': {
        'batchedWrites': _batchScheduler.batchedWrites,
        'directWrites': _batchScheduler.directWrites,
        'flushCount': _batchScheduler.flushCount,
        'pendingCount': _batchScheduler.pendingCount,
      },
      'convCache': {
        'count': _convCache.length,
        'dirty': _convCacheDirty,
        'lastRefresh': _convCacheTime?.toIso8601String(),
      },
    };
  }

  // ── 内部辅助 ──

  Future<String> _getDefaultRootPath() async {
    Directory? appDir;

    try {
      appDir = await getApplicationDocumentsDirectory();
      AppLogger.d('[Storage] 使用应用私有目录: ${appDir.path}');
    } catch (e) {
      AppLogger.w('[Storage] 获取应用私有目录失败: $e');

      appDir = await getExternalStorageDirectory();
      if (appDir == null) {
        AppLogger.w('[Storage] 所有目录获取失败，使用临时目录');
        appDir = await getTemporaryDirectory();
      }
    }

    final path = '${appDir.path}/$_appDataDir';
    AppLogger.d('[Storage] 最终存储路径: $path');
    return path;
  }

  static Future<bool> _testPathWritable(String path) async {
    try {
      final dir = Directory(path);
      if (!dir.existsSync()) {
        dir.createSync(recursive: true);
      }
      final testFile = File('$path/.write_test');
      testFile.writeAsStringSync('test', flush: true);
      final readBack = testFile.readAsStringSync();
      testFile.deleteSync();
      return readBack == 'test';
    } catch (e) {
      AppLogger.w('[Storage] 路径可写性测试失败 ($path): $e');
      return false;
    }
  }
}

/// P1 #8: 备份导入的解析结果项（用于 isolate 返回）。
/// 为什么用独立类：compute 需要可跨 isolate 传递的简单数据载体，
/// Conversation 和 Message 都是纯 POJO（无闭包/SendPort），可安全跨 isolate 传递。
class _BackupItem {
  final Conversation conversation;
  final List<Message> messages;
  _BackupItem({required this.conversation, required this.messages});
}

/// P1 #8: 在 isolate 中解析备份文件内容。
/// 为什么是顶层函数：compute 要求回调是顶层函数或静态方法，
/// 不能是闭包或实例方法（无法跨 isolate 传递）。
/// 做什么：jsonDecode + Conversation.fromJson + Message.fromJson，
/// 把 CPU 密集的解析工作从主线程移走，避免导入大备份时 UI 卡顿。
/// 返回：Map 含 'version' (int)，v2 时含 'items' (List<_BackupItem>)，
/// v1 时含 'legacyMessages' (List<Message>)。
Map<String, dynamic> _parseBackupContent(String content) {
  final data = jsonDecode(content) as Map<String, dynamic>;
  final version = data['version'] as int? ?? 1;

  if (version >= 2) {
    final convList = data['conversations'] as List<dynamic>? ?? [];
    final items = <_BackupItem>[];
    for (final convData in convList) {
      final convJson = convData as Map<String, dynamic>;
      final conv = Conversation.fromJson(convJson);
      final messagesList = convJson['messages'] as List<dynamic>? ?? [];
      final messages = messagesList
          .map((m) => Message.fromJson(m as Map<String, dynamic>))
          .toList();
      items.add(_BackupItem(conversation: conv, messages: messages));
    }
    return {'version': version, 'items': items};
  } else {
    final messagesList = data['messages'] as List<dynamic>? ?? [];
    final messages = messagesList
        .map((m) => Message.fromJson(m as Map<String, dynamic>))
        .toList();
    return {'version': version, 'legacyMessages': messages};
  }
}
