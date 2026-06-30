import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';

class DeviceInfo {
  static bool _isHuaweiDevice = false;
  static bool _checked = false;

  static bool get isHuaweiOrHonor {
    if (_checked) return _isHuaweiDevice;
    _checked = true;

    try {
      final brand = _brand.toLowerCase();
      final model = _model.toLowerCase();

      _isHuaweiDevice =
          brand.contains('huawei') ||
          brand.contains('honor') ||
          model.contains('hua-') ||
          model.contains('honor') ||
          model.contains('sea-') ||
          model.contains('lio-') ||
          model.contains('ano-') ||
          model.contains('stg-') ||
          model.contains('els-') ||
          model.contains('hw') ||
          model.contains('kirin') ||
          model.contains('harmony');

      if (_isHuaweiDevice) {
        debugPrint('[DeviceInfo] 检测到华为/荣耀设备: brand=$brand, model=$model');
      }
    } catch (_) {
      _isHuaweiDevice = false;
    }

    return _isHuaweiDevice;
  }

  static String get _brand {
    try {
      return Platform.localHostname.split('.').first;
    } catch (_) {
      return 'unknown';
    }
  }

  static String get _model => _brand;

  static void forceHuawei(bool value) {
    _isHuaweiDevice = value;
    _checked = true;
  }

  static void reset() {
    _isHuaweiDevice = false;
    _checked = false;
  }
}
