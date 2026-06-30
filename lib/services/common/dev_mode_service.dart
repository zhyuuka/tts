// 开源版：原 lib/services/common/dev_mode_service.dart 同时包含
// DevModeService（逻辑类，ChangeNotifier）和 DevModeLabel（UI 组件，StatelessWidget）。
// 后端开源库不包含 UI 组件，故此处仅保留 DevModeService 类。
// 为什么这样做：DevModeLabel 依赖 lib/screens/widgets/app_snack_bar.dart
// 和 Flutter Material（Icons/Colors/AlertDialog 等），属于 UI 层。
// 后端库保持纯逻辑，UI 组件由使用方自行实现。
//
// 移除的内容：
// - import 'package:flutter/services.dart';（仅 DevModeLabel 用 Clipboard）
// - import '../../screens/widgets/app_snack_bar.dart';（UI 依赖）
// - class DevModeLabel extends StatelessWidget { ... }（194 行 UI 组件）
//
// import 调整：原 'package:flutter/material.dart' 改为 'package:flutter/foundation.dart'，
// 因为 DevModeService 只需要 ChangeNotifier 和 notifyListeners，不需要 Material UI。
import 'package:flutter/foundation.dart';

/// 开发者模式服务（纯逻辑）。
///
/// 在原完整项目中，[DevModeService] 与 [DevModeLabel]（UI 组件）共存于此文件。
/// 开源后端库仅保留本类。UI 层应自行实现开发者模式标签的渲染逻辑，
/// 通过 [isEnabled] getter 和 [ListenableBuilder] 监听状态变化。
class DevModeService extends ChangeNotifier {
  static final DevModeService _instance = DevModeService._internal();
  factory DevModeService() => _instance;
  DevModeService._internal();

  bool _isEnabled = false;

  /// 开发者模式是否启用。
  bool get isEnabled => _isEnabled;

  /// 加载状态（当前实现：始终重置为 false，无持久化）。
  Future<void> loadState() async {
    _isEnabled = false;
  }

  /// 切换启用状态。
  void toggle() {
    _isEnabled = !_isEnabled;
    notifyListeners();
  }

  /// 启用开发者模式。
  void enable() {
    if (!_isEnabled) {
      _isEnabled = true;
      notifyListeners();
    }
  }

  /// 禁用开发者模式。
  void disable() {
    if (_isEnabled) {
      _isEnabled = false;
      notifyListeners();
    }
  }

  // 开源版说明：原完整项目中本类有一个 static const String triggerCode = '0828';
  // 用于在聊天框输入触发码激活开发者模式。开源版移除此机制，
  // 因为开源后触发码会公开，无意义。使用方应在 UI 层自行提供开发者模式入口
  // （例如：设置页长按版本号 5 次、或通过环境变量注入触发码等）。
  // 通过 enable() / disable() / toggle() 方法即可控制开关状态。
}
