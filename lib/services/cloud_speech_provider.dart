import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import 'settings_service.dart';
import 'secure_storage_service.dart';

enum CloudSpeechProviderType { openaiWhisper, xunfei, tongyi }

enum CloudSpeechState { idle, recording, uploading, recognizing, error, done }

class CloudSpeechResult {
  final String text;
  final bool isFinal;
  final double confidence;
  final String? errorMessage;
  final CloudSpeechProviderType provider;

  const CloudSpeechResult({
    required this.text,
    required this.isFinal,
    required this.confidence,
    this.errorMessage,
    required this.provider,
  });

  bool get hasError => errorMessage != null && errorMessage!.isNotEmpty;
}

abstract class CloudSpeechProvider {
  CloudSpeechProviderType get type;
  String get displayName;
  String get apiKeyHint;
  String get baseUrlHint;

  Future<CloudSpeechResult> recognize(File audioFile, {String? language});
  Future<bool> validateConfig({required String apiKey, String? baseUrl});

  static CloudSpeechProvider create(CloudSpeechProviderType type) {
    switch (type) {
      case CloudSpeechProviderType.openaiWhisper:
        return OpenAIWhisperProvider();
      case CloudSpeechProviderType.xunfei:
        return XunfeiSttProvider();
      case CloudSpeechProviderType.tongyi:
        return TongyiParaformerProvider();
    }
  }
}

class OpenAIWhisperProvider extends CloudSpeechProvider {
  @override
  CloudSpeechProviderType get type => CloudSpeechProviderType.openaiWhisper;

  @override
  String get displayName => 'OpenAI Whisper';

  @override
  String get apiKeyHint => 'sk-...';

  @override
  String get baseUrlHint => 'https://api.openai.com/v1 (可选，留空使用默认)';

  static const String _defaultBaseUrl = 'https://api.openai.com/v1';

  @override
  Future<bool> validateConfig({required String apiKey, String? baseUrl}) async {
    if (apiKey.isEmpty) return false;
    try {
      final dio = Dio(
        BaseOptions(
          baseUrl: baseUrl?.trim().isEmpty == true
              ? _defaultBaseUrl
              : (baseUrl ?? _defaultBaseUrl),
          headers: {'Authorization': 'Bearer $apiKey'},
          connectTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 10),
        ),
      );
      final response = await dio.get('/models');
      return response.statusCode == 200;
    } catch (_) {
      return true;
    }
  }

  @override
  Future<CloudSpeechResult> recognize(
    File audioFile, {
    String? language,
  }) async {
    try {
      final apiKey = await _getApiKey();
      final baseUrl = await _getBaseUrl();

      if (apiKey.isEmpty) {
        return CloudSpeechResult(
          text: '',
          isFinal: false,
          confidence: 0,
          provider: type,
          errorMessage: '未配置 API Key',
        );
      }

      final dio = Dio(
        BaseOptions(
          baseUrl: baseUrl.trim().isEmpty ? _defaultBaseUrl : baseUrl,
          headers: {'Authorization': 'Bearer $apiKey'},
          connectTimeout: const Duration(seconds: 30),
          sendTimeout: const Duration(seconds: 120),
          receiveTimeout: const Duration(seconds: 120),
        ),
      );

      final fileName = audioFile.path.split('/').last;
      final formData = FormData.fromMap({
        'file': await MultipartFile.fromFile(
          audioFile.path,
          filename: fileName,
        ),
        'model': 'whisper-1',
        'language': language ?? 'zh',
        'response_format': 'verbose_json',
      });

      debugPrint('[OpenAIWhisper] 开始上传音频文件: ${audioFile.lengthSync()} bytes');

      final response = await dio.post(
        '/audio/transcriptions',
        data: formData,
        options: Options(contentType: 'multipart/form-data'),
      );

      if (response.statusCode != 200) {
        return CloudSpeechResult(
          text: '',
          isFinal: false,
          confidence: 0,
          provider: type,
          errorMessage:
              'API 错误 (${response.statusCode}): ${response.statusMessage}',
        );
      }

      final data = response.data;
      final text = data['text'] as String? ?? '';
      final segments = data['segments'] as List<dynamic>? ?? [];
      double avgConfidence = 0.0;
      if (segments.isNotEmpty) {
        final values = segments
            .map((s) => (s['avg_logprob'] as num?)?.toDouble() ?? 0)
            .toList();
        final sum = values.reduce((a, b) => a + b);
        avgConfidence = sum / segments.length;
      }

      debugPrint(
        '[OpenAIWhisper] 识别完成: "$text" (置信度: ${avgConfidence.toStringAsFixed(2)})',
      );

      return CloudSpeechResult(
        text: text,
        isFinal: true,
        confidence: avgConfidence.clamp(0.0, 1.0),
        provider: type,
      );
    } on DioException catch (e) {
      final msg =
          e.response?.data?['error']?['message']?.toString() ?? e.message;
      debugPrint('[OpenAIWhisper] 网络错误: $msg');
      return CloudSpeechResult(
        text: '',
        isFinal: false,
        confidence: 0,
        provider: type,
        errorMessage: msg,
      );
    } catch (e) {
      debugPrint('[OpenAIWhisper] 异常: $e');
      return CloudSpeechResult(
        text: '',
        isFinal: false,
        confidence: 0,
        provider: type,
        errorMessage: '识别异常: $e',
      );
    }
  }

  Future<String> _getApiKey() async {
    final secureStorage = SecureStorageService.instance;
    return await secureStorage.getCloudSpeechApiKey() ?? '';
  }

  Future<String> _getBaseUrl() async {
    final settings = SettingsService.instance;
    return settings.getCloudSpeechBaseUrl();
  }
}

class XunfeiSttProvider extends CloudSpeechProvider {
  @override
  CloudSpeechProviderType get type => CloudSpeechProviderType.xunfei;

  @override
  String get displayName => '讯飞语音识别';

  @override
  String get apiKeyHint => '讯飞 APPID|APIKey|APISecret';

  @override
  String get baseUrlHint => 'wss://iat-api.xfyun.cn/v2/iat';

  @override
  Future<bool> validateConfig({required String apiKey, String? baseUrl}) async {
    final parts = apiKey.split('|');
    return parts.length >= 2 && parts.every((p) => p.isNotEmpty);
  }

  @override
  Future<CloudSpeechResult> recognize(
    File audioFile, {
    String? language,
  }) async {
    return CloudSpeechResult(
      text: '',
      isFinal: false,
      confidence: 0,
      provider: type,
      errorMessage: '讯飞语音识别开发中，请先使用 OpenAI Whisper',
    );
  }
}

class TongyiParaformerProvider extends CloudSpeechProvider {
  @override
  CloudSpeechProviderType get type => CloudSpeechProviderType.tongyi;

  @override
  String get displayName => '通义 Paraformer';

  @override
  String get apiKeyHint => '通义 DashScope API Key';

  @override
  String get baseUrlHint => 'https://dashscope.aliyuncs.com/api/v1';

  @override
  Future<bool> validateConfig({required String apiKey, String? baseUrl}) async {
    return apiKey.isNotEmpty && apiKey.startsWith('sk-');
  }

  @override
  Future<CloudSpeechResult> recognize(
    File audioFile, {
    String? language,
  }) async {
    try {
      final apiKey = await _getApiKey();

      if (apiKey.isEmpty) {
        return CloudSpeechResult(
          text: '',
          isFinal: false,
          confidence: 0,
          provider: type,
          errorMessage: '未配置 DashScope API Key',
        );
      }

      final dio = Dio(
        BaseOptions(
          baseUrl: 'https://dashscope.aliyuncs.com/api/v1',
          headers: {'Authorization': 'Bearer $apiKey'},
          connectTimeout: const Duration(seconds: 30),
          sendTimeout: const Duration(seconds: 120),
          receiveTimeout: const Duration(seconds: 120),
        ),
      );

      final formData = FormData.fromMap({
        'file': await MultipartFile.fromFile(audioFile.path),
        'model': 'paraformer-v2',
        'language': language ?? 'zh',
        'sample_rate': 16000,
        'format': 'wav',
      });

      debugPrint('[TongyiParaformer] 开始上传音频文件');

      final response = await dio.post(
        '/services/audio/asr/transcription',
        data: formData,
        options: Options(contentType: 'multipart/form-data'),
      );

      if (response.statusCode != 200) {
        final errorMsg =
            response.data?['message']?.toString() ?? response.statusMessage;
        return CloudSpeechResult(
          text: '',
          isFinal: false,
          confidence: 0,
          provider: type,
          errorMessage: 'API错误 ($errorMsg)',
        );
      }

      final data = response.data;
      final output = data['output'];
      final text =
          output?['sentence']?.map((s) => s['text']?.toString()).join('') ??
          output?['text'] ??
          '';

      debugPrint('[TongyiParaformer] 识别完成: "$text"');

      return CloudSpeechResult(
        text: text,
        isFinal: true,
        confidence: 1.0,
        provider: type,
      );
    } on DioException catch (e) {
      final msg = e.response?.data?['message']?.toString() ?? e.message;
      return CloudSpeechResult(
        text: '',
        isFinal: false,
        confidence: 0,
        provider: type,
        errorMessage: msg,
      );
    } catch (e) {
      return CloudSpeechResult(
        text: '',
        isFinal: false,
        confidence: 0,
        provider: type,
        errorMessage: '异常: $e',
      );
    }
  }

  Future<String> _getApiKey() async {
    final secureStorage = SecureStorageService.instance;
    return await secureStorage.getCloudSpeechApiKey() ?? '';
  }
}
