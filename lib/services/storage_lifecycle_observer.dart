import 'package:flutter/widgets.dart';

import '../core/logger/app_logger.dart';
import 'storage_service.dart';

class StorageLifecycleObserver extends WidgetsBindingObserver {
  final StorageService _storageService;

  DateTime? _lastFlushTime;
  static const Duration _minFlushInterval = Duration(seconds: 2);

  StorageLifecycleObserver({required StorageService storageService})
    : _storageService = storageService {
    WidgetsBinding.instance.addObserver(this);
    AppLogger.i('[LifecycleObserver] 已注册');
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.paused:
        _onAppPaused();
        break;
      case AppLifecycleState.inactive:
        _onAppInactive();
        break;
      case AppLifecycleState.detached:
        _onAppDetached();
        break;
      case AppLifecycleState.resumed:
        _onAppResumed();
        break;
      case AppLifecycleState.hidden:
        break;
    }
  }

  void _onAppPaused() {
    AppLogger.i('[LifecycleObserver] 应用进入后台，触发 flush...');
    _flushIfNeeded();
  }

  void _onAppInactive() {
    AppLogger.d('[LifecycleObserver] 应用变为非活跃状态');
    _flushIfNeeded();
  }

  void _onAppDetached() {
    AppLogger.w('[LifecycleObserver] 应用即将被销毁，紧急 flush！');
    _storageService.flushPendingWrites();
  }

  void _onAppResumed() {
    AppLogger.d('[LifecycleObserver] 应用恢复前台');
  }

  void _flushIfNeeded() {
    final now = DateTime.now();
    if (_lastFlushTime != null &&
        now.difference(_lastFlushTime!) < _minFlushInterval) {
      AppLogger.d(
        '[LifecycleObserver] 距上次 flush 不足 ${_minFlushInterval.inSeconds}s，跳过',
      );
      return;
    }

    _lastFlushTime = now;
    _storageService.flushPendingWrites();
  }

  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    AppLogger.i('[LifecycleObserver] 已注销');
  }
}
