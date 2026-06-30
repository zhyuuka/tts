import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

import '../../core/logger/app_logger.dart';
import '../../models/agent/agent_event.dart';
import '../../models/agent/ui_node.dart';

/// 原生调用结果
///
/// 为什么这样做：所有原生调用返回 Result 而非抛异常，
/// 上层无需 try-catch，错误统一封装。
class BridgeResult<T> {
  final bool success;
  final T? data;
  final String? error;

  const BridgeResult.success(this.data) : success = true, error = null;
  const BridgeResult.failure(this.error) : success = false, data = null;

  /// 链式取值，失败时返回默认值
  T or(T defaultValue) => success ? (data ?? defaultValue) : defaultValue;
}

/// 安卓 Agent 原生通信桥接
///
/// 职责：封装 MethodChannel/EventChannel 细节，向上层暴露语义化 API。
/// 为什么单独成类：
/// 1. 隔离平台通信，上层（AgentService/ToolRegistry）不关心 channel
/// 2. 统一错误处理，所有方法返回 BridgeResult 不抛异常
/// 3. 平台判断集中在此，非 Android 平台调用返回 unsupported
///
/// 通道命名沿用项目现有 TTS 桥接模式（xingling.chat/tts）：
/// - MethodChannel: xingling.chat/agent
/// - EventChannel:  xingling.chat/agent_events
class AccessibilityBridge {
  AccessibilityBridge._();

  static final AccessibilityBridge instance = AccessibilityBridge._();

  static const _methodChannel = MethodChannel('xingling.chat/agent');
  static const _eventChannel = EventChannel('xingling.chat/agent_events');

  Stream<AgentEvent>? _eventStream;

  // ── 平台与权限 ──

  /// 平台是否支持 Agent（仅 Android）
  bool get isSupported => Platform.isAndroid;

  /// 检查无障碍服务是否已启用
  Future<bool> isServiceEnabled() async {
    if (!isSupported) return false;
    final res = await _invoke<bool>('isServiceEnabled', {});
    return res.or(false);
  }

  /// 跳转系统无障碍设置页
  Future<bool> openAccessibilitySettings() async {
    if (!isSupported) return false;
    final res = await _invoke<bool>('openAccessibilitySettings', {});
    return res.or(false);
  }

  /// 检查通知监听是否启用
  Future<bool> isNotificationListenerEnabled() async {
    if (!isSupported) return false;
    final res = await _invoke<bool>('isNotificationListenerEnabled', {});
    return res.or(false);
  }

  /// 跳转通知访问设置页
  Future<bool> openNotificationSettings() async {
    if (!isSupported) return false;
    final res = await _invoke<bool>('openNotificationSettings', {});
    return res.or(false);
  }

  // ── 感知 ──

  /// 提取当前屏幕 UI 树
  ///
  /// [maxDepth] 最大深度，默认 8（避免传输过大）
  /// [includeInvisible] 是否包含不可见节点，默认 false
  Future<BridgeResult<UiTree>> captureUiTree({
    int maxDepth = 8,
    bool includeInvisible = false,
  }) async {
    if (!isSupported) {
      return const BridgeResult.failure('platform_not_supported');
    }
    final res = await _invoke<Map>('captureUiTree', {
      'maxDepth': maxDepth,
      'includeInvisible': includeInvisible,
    });
    if (!res.success || res.data == null) {
      return BridgeResult.failure(res.error ?? 'capture_failed');
    }
    try {
      final tree = UiTree.fromJson(Map<String, dynamic>.from(res.data as Map));
      return BridgeResult.success(tree);
    } catch (e) {
      AppLogger.e('[AgentBridge] captureUiTree 解析失败', e);
      return BridgeResult.failure('parse_failed: $e');
    }
  }

  /// 截图（Android 11/API 30+）
  ///
  /// 为什么单独标注版本：takeScreenshot 仅 API 30+ 可用，
  /// Android 9/10 设备会返回 unsupported，上层应禁用 VLM fallback。
  Future<BridgeResult<Uint8List>> takeScreenshot() async {
    if (!isSupported) {
      return const BridgeResult.failure('platform_not_supported');
    }
    final res = await _invoke<Map>('takeScreenshot', {});
    if (!res.success || res.data == null) {
      return BridgeResult.failure(res.error ?? 'screenshot_failed');
    }
    final base64 = (res.data as Map)['base64'] as String?;
    if (base64 == null || base64.isEmpty) {
      return const BridgeResult.failure('screenshot_empty');
    }
    try {
      return BridgeResult.success(base64Decode(base64));
    } catch (e) {
      AppLogger.e('[AgentBridge] takeScreenshot 解码失败', e);
      return BridgeResult.failure('decode_failed: $e');
    }
  }

  // ── 手势 ──

  Future<BridgeResult<void>> tap(int x, int y) =>
      _invokeVoid('tap', {'x': x, 'y': y});

  Future<BridgeResult<void>> doubleTap(int x, int y) =>
      _invokeVoid('doubleTap', {'x': x, 'y': y});

  Future<BridgeResult<void>> longPress(int x, int y, {int durationMs = 1000}) =>
      _invokeVoid('longPress', {'x': x, 'y': y, 'durationMs': durationMs});

  Future<BridgeResult<void>> swipe(
    int startX,
    int startY,
    int endX,
    int endY, {
    int durationMs = 300,
  }) => _invokeVoid('swipe', {
    'startX': startX,
    'startY': startY,
    'endX': endX,
    'endY': endY,
    'durationMs': durationMs,
  });

  Future<BridgeResult<void>> pressBack() => _invokeVoid('pressBack', {});

  Future<BridgeResult<void>> pressHome() => _invokeVoid('pressHome', {});

  Future<BridgeResult<void>> pressRecents() => _invokeVoid('pressRecents', {});

  // ── 文本输入 ──

  /// 输入文本
  ///
  /// 原生侧策略：优先 ACTION_SET_TEXT（API 21+ 官方推荐），
  /// 失败 fallback 剪贴板+ACTION_PASTE。
  /// 密码框由原生侧强制用 ACTION_SET_TEXT（避免剪贴板泄露明文）。
  Future<BridgeResult<void>> inputText(String text) =>
      _invokeVoid('inputText', {'text': text});

  Future<BridgeResult<void>> clearInput() => _invokeVoid('clearInput', {});

  // ── App 管理 ──

  Future<BridgeResult<void>> launchApp(String packageName) =>
      _invokeVoid('launchApp', {'packageName': packageName});

  Future<BridgeResult<({String package, String activity})>>
  getForegroundApp() async {
    if (!isSupported) {
      return const BridgeResult.failure('platform_not_supported');
    }
    final res = await _invoke<Map>('getForegroundApp', {});
    if (!res.success || res.data == null) {
      return BridgeResult.failure(res.error ?? 'get_failed');
    }
    final map = Map<String, dynamic>.from(res.data as Map);
    return BridgeResult.success((
      package: (map['package'] as String?) ?? '',
      activity: (map['activity'] as String?) ?? '',
    ));
  }

  /// 获取已安装的可启动 App 列表
  Future<BridgeResult<List<({String package, String label})>>>
  getInstalledApps() async {
    if (!isSupported) {
      return const BridgeResult.failure('platform_not_supported');
    }
    final res = await _invoke<List>('getInstalledApps', {});
    if (!res.success || res.data == null) {
      return BridgeResult.failure(res.error ?? 'get_failed');
    }
    final apps = (res.data as List)
        .map((e) {
          final map = Map<String, dynamic>.from(e as Map);
          return (
            package: (map['package'] as String?) ?? '',
            label: (map['label'] as String?) ?? '',
          );
        })
        .where((e) => e.package.isNotEmpty)
        .toList();
    return BridgeResult.success(apps);
  }

  // ── 通知 ──

  Future<BridgeResult<List<Map<String, dynamic>>>> readNotifications({
    int limit = 50,
  }) async {
    if (!isSupported) {
      return const BridgeResult.failure('platform_not_supported');
    }
    final res = await _invoke<List>('readNotifications', {'limit': limit});
    if (!res.success || res.data == null) {
      return BridgeResult.failure(res.error ?? 'read_failed');
    }
    final list = (res.data as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    return BridgeResult.success(list);
  }

  // ── 紧急停止 ──

  /// 通知原生取消正在执行的手势
  /// 为什么这样做：紧急停止时 Dart 侧取消 LLM 流，原生侧取消手势
  Future<void> emergencyStopNative() async {
    if (!isSupported) return;
    await _invokeVoid('emergencyStop', {});
  }

  // ── 前台服务（常驻通知 + 紧急停止按钮）──

  /// 启动前台服务，显示常驻通知
  ///
  /// 做什么：Agent 任务运行期间显示常驻通知，通知含"紧急停止"按钮。
  /// 为什么这样做：
  /// 1. Android 9+ 后台执行需前台服务保活
  /// 2. 用户随时知道 Agent 在运行，可一键停止
  Future<void> startForegroundService(String goal) async {
    if (!isSupported) return;
    await _invokeVoid('startForeground', {'goal': goal});
  }

  /// 停止前台服务，移除常驻通知
  Future<void> stopForegroundService() async {
    if (!isSupported) return;
    await _invokeVoid('stopForeground', {});
  }

  // ── 事件流 ──

  /// 监听原生事件流
  ///
  /// 为什么返回 Stream：上层（Provider）用 StreamSubscription 订阅，
  /// 可随时取消。Stream 自动处理 EventChannel 的 onListen/onCancel。
  Stream<AgentEvent> get events {
    _eventStream ??= _eventChannel
        .receiveBroadcastStream()
        .map(
          (event) =>
              AgentEvent.fromMap(Map<String, dynamic>.from(event as Map)),
        )
        .handleError((e) {
          AppLogger.e('[AgentBridge] 事件流错误', e);
        });
    return _eventStream!;
  }

  // ── 内部工具 ──

  /// 统一的 MethodChannel 调用封装
  /// 为什么这样做：所有调用走同一入口，便于日志、错误处理、平台判断
  Future<BridgeResult<T>> _invoke<T>(
    String method,
    Map<String, dynamic> args, {
    T? defaultValue,
  }) async {
    try {
      final result = await _methodChannel.invokeMethod<T>(method, args);
      return BridgeResult.success(result ?? defaultValue as T);
    } on PlatformException catch (e) {
      AppLogger.e('[AgentBridge] $method 调用失败: ${e.code} ${e.message}');
      return BridgeResult.failure('${e.code}: ${e.message ?? e.code}');
    } on MissingPluginException catch (e) {
      AppLogger.w('[AgentBridge] $method 未实现（插件未注册）');
      return BridgeResult.failure('not_implemented: ${e.message}');
    } catch (e) {
      AppLogger.e('[AgentBridge] $method 未知错误', e);
      return BridgeResult.failure('unknown: $e');
    }
  }

  /// 无返回值的调用封装
  Future<BridgeResult<void>> _invokeVoid(
    String method,
    Map<String, dynamic> args,
  ) async {
    final res = await _invoke<bool>(method, args, defaultValue: false);
    if (res.success && (res.data ?? false)) {
      return const BridgeResult.success(null);
    }
    return BridgeResult.failure(res.error ?? '$method returned false');
  }
}
