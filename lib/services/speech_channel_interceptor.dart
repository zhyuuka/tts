import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

typedef OnRecognizedText = void Function(String words, bool isFinal);
typedef OnSpeechError = void Function(String errorMsg);
typedef OnSpeechStatus = void Function(String status);

class SpeechChannelInterceptor {
  static const String _channelName = 'speech_to_text_windows';
  static SpeechChannelInterceptor? _instance;

  final MethodChannel _channel = const MethodChannel(_channelName);
  bool _isActive = false;
  OnRecognizedText? _onRecognized;
  OnSpeechError? _onError;
  OnSpeechStatus? _onStatus;

  static SpeechChannelInterceptor get instance =>
      _instance ??= SpeechChannelInterceptor._();

  SpeechChannelInterceptor._();

  bool get isActive => _isActive;

  bool get isWindows => Platform.isWindows;

  Future<void> activate({
    required OnRecognizedText onRecognized,
    required OnSpeechError onError,
    required OnSpeechStatus onStatus,
  }) async {
    if (_isActive) return;

    if (!isWindows) {
      debugPrint(
        '[SpeechChannelInterceptor] 非Windows平台，跳过激活 (当前: ${Platform.operatingSystem})',
      );
      return;
    }

    _onRecognized = onRecognized;
    _onError = onError;
    _onStatus = onStatus;

    _channel.setMethodCallHandler(_handleMethodCall);
    _isActive = true;
    debugPrint('[SpeechChannelInterceptor] 已激活，拦截通道 $_channelName');
  }

  void deactivate() {
    if (!_isActive) return;
    _channel.setMethodCallHandler(null);
    _isActive = false;
    _onRecognized = null;
    _onError = null;
    _onStatus = null;
    debugPrint('[SpeechChannelInterceptor] 已停用');
  }

  Future<dynamic> _handleMethodCall(MethodCall call) async {
    debugPrint('[SpeechChannelInterceptor] 收到方法调用: ${call.method}');

    switch (call.method) {
      case 'textRecognition':
        _handleTextRecognition(call.arguments);
        break;
      case 'notifyError':
        _handleNotifyError(call.arguments);
        break;
      case 'notifyStatus':
        _handleNotifyStatus(call.arguments);
        break;
      default:
        debugPrint('[SpeechChannelInterceptor] 未处理的方法: ${call.method}');
    }
    return null;
  }

  void _handleTextRecognition(dynamic arguments) {
    try {
      final jsonStr = arguments as String?;
      if (jsonStr == null || jsonStr.isEmpty) {
        debugPrint('[SpeechChannelInterceptor] textRecognition 参数为空');
        return;
      }

      final Map<String, dynamic> data = jsonDecode(jsonStr);
      final words = data['recognizedWords'] as String? ?? '';
      final isFinal = data['finalResult'] as bool? ?? false;

      debugPrint('[SpeechChannelInterceptor] 识别结果: "$words" (final: $isFinal)');

      if (words.isNotEmpty && _onRecognized != null) {
        _onRecognized!(words, isFinal);
      }
    } catch (e) {
      debugPrint('[SpeechChannelInterceptor] 解析 textRecognition 异常: $e');
    }
  }

  void _handleNotifyError(dynamic arguments) {
    final errorMsg = arguments?.toString() ?? '未知错误';
    debugPrint('[SpeechChannelInterceptor] 错误: $errorMsg');
    _onError?.call(errorMsg);
  }

  void _handleNotifyStatus(dynamic arguments) {
    final status = arguments?.toString() ?? '';
    debugPrint('[SpeechChannelInterceptor] 状态: $status');
    _onStatus?.call(status);
  }
}
