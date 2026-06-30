import 'dart:io';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

bool get _isMobilePlatform {
  return !kIsWeb && (Platform.isAndroid || Platform.isIOS);
}

enum OcrEngine {
  local('local', '本地OCR', '设备端识别，无需网络'),
  baidu('baidu', '百度OCR', '需API Key，通用文字识别'),
  tencent('tencent', '腾讯OCR', '需API Key，通用印刷体识别'),
  aliyun('aliyun', '阿里云OCR', '需API Key，通用文字识别');

  const OcrEngine(this.id, this.name, this.description);

  final String id;
  final String name;
  final String description;
}

class OcrResult {
  final String text;
  final bool success;
  final String? error;
  final OcrEngine engine;

  const OcrResult({
    required this.text,
    required this.success,
    this.error,
    required this.engine,
  });
}

abstract class OcrService {
  Future<OcrResult> recognizeText(Uint8List imageBytes, {String? mimeType});
  bool get isAvailable;
  String get engineName;
}

class LocalOcrService implements OcrService {
  TextRecognizer? _textRecognizer;
  bool _available = false;

  @override
  bool get isAvailable => _available;

  @override
  String get engineName => '本地OCR';

  Future<void> init() async {
    if (!_isMobilePlatform) {
      _available = false;
      debugPrint('[LocalOcr] 当前平台不支持本地OCR（仅支持Android/iOS）');
      return;
    }
    try {
      _textRecognizer = TextRecognizer(script: TextRecognitionScript.chinese);
      _available = true;
      debugPrint('[LocalOcr] 初始化成功 (google_mlkit_text_recognition)');
    } catch (e) {
      debugPrint('[LocalOcr] 初始化失败: $e');
      _available = false;
    }
  }

  void dispose() {
    _textRecognizer?.close();
  }

  @override
  Future<OcrResult> recognizeText(
    Uint8List imageBytes, {
    String? mimeType,
  }) async {
    if (!_available || _textRecognizer == null) {
      return OcrResult(
        text: '',
        success: false,
        error: _isMobilePlatform
            ? '本地OCR初始化失败'
            : '当前平台不支持本地OCR（仅支持Android/iOS）',
        engine: OcrEngine.local,
      );
    }

    try {
      final tempDir = Directory.systemTemp;
      final tempFile = File(
        '${tempDir.path}/ocr_temp_${DateTime.now().millisecondsSinceEpoch}.png',
      );
      await tempFile.writeAsBytes(imageBytes);

      final inputImage = InputImage.fromFile(tempFile);
      final recognizedText = await _textRecognizer!.processImage(inputImage);

      await tempFile.delete();

      final text = recognizedText.text.trim();

      return OcrResult(
        text: text,
        success: text.isNotEmpty,
        engine: OcrEngine.local,
      );
    } catch (e) {
      debugPrint('[LocalOcr] 识别失败: $e');
      return OcrResult(
        text: '',
        success: false,
        error: e.toString(),
        engine: OcrEngine.local,
      );
    }
  }
}

class BaiduOcrService implements OcrService {
  final String apiKey;
  final String secretKey;

  BaiduOcrService({required this.apiKey, required this.secretKey});

  @override
  bool get isAvailable => apiKey.isNotEmpty && secretKey.isNotEmpty;

  @override
  String get engineName => '百度OCR';

  @override
  Future<OcrResult> recognizeText(
    Uint8List imageBytes, {
    String? mimeType,
  }) async {
    if (!isAvailable) {
      return const OcrResult(
        text: '',
        success: false,
        error: '百度OCR未配置API Key',
        engine: OcrEngine.baidu,
      );
    }

    try {
      final dio = Dio();
      final tokenResponse = await dio.post(
        'https://aip.baidubce.com/oauth/2.0/token',
        queryParameters: {
          'grant_type': 'client_credentials',
          'client_id': apiKey,
          'client_secret': secretKey,
        },
      );

      final accessToken = tokenResponse.data['access_token'] as String?;
      if (accessToken == null) {
        return const OcrResult(
          text: '',
          success: false,
          error: '获取百度AccessToken失败',
          engine: OcrEngine.baidu,
        );
      }

      final base64Image = base64Encode(imageBytes);
      final response = await dio.post(
        'https://aip.baidubce.com/rest/2.0/ocr/v1/general_basic',
        queryParameters: {'access_token': accessToken},
        data: 'image=${Uri.encodeComponent(base64Image)}',
        options: Options(contentType: Headers.formUrlEncodedContentType),
      );

      final wordsResult = response.data['words_result'] as List?;
      if (wordsResult == null || wordsResult.isEmpty) {
        return const OcrResult(
          text: '',
          success: false,
          error: '未识别到文字',
          engine: OcrEngine.baidu,
        );
      }

      final text = wordsResult
          .map((item) => item['words'] as String? ?? '')
          .where((w) => w.isNotEmpty)
          .join('\n');

      return OcrResult(
        text: text,
        success: text.isNotEmpty,
        engine: OcrEngine.baidu,
      );
    } catch (e) {
      debugPrint('[BaiduOcr] 识别失败: $e');
      return OcrResult(
        text: '',
        success: false,
        error: e.toString(),
        engine: OcrEngine.baidu,
      );
    }
  }
}

class TencentOcrService implements OcrService {
  final String secretId;
  final String secretKey;

  TencentOcrService({required this.secretId, required this.secretKey});

  @override
  bool get isAvailable => secretId.isNotEmpty && secretKey.isNotEmpty;

  @override
  String get engineName => '腾讯OCR';

  @override
  Future<OcrResult> recognizeText(
    Uint8List imageBytes, {
    String? mimeType,
  }) async {
    if (!isAvailable) {
      return const OcrResult(
        text: '',
        success: false,
        error: '腾讯OCR未配置',
        engine: OcrEngine.tencent,
      );
    }

    try {
      final base64Image = base64Encode(imageBytes);
      final dio = Dio();
      final response = await dio.post(
        'https://ocr.tencentcloudapi.com/',
        data: {'ImageBase64': base64Image},
        options: Options(
          headers: {
            'Authorization': 'TC3-HMAC-SHA256 Credential=$secretId',
            'Content-Type': 'application/json',
            'X-TC-Action': 'GeneralBasicOCR',
            'X-TC-Version': '2018-11-19',
          },
        ),
      );

      final textDetections =
          response.data['Response']?['TextDetections'] as List?;
      if (textDetections == null || textDetections.isEmpty) {
        return const OcrResult(
          text: '',
          success: false,
          error: '未识别到文字',
          engine: OcrEngine.tencent,
        );
      }

      final text = textDetections
          .map((item) => item['DetectedText'] as String? ?? '')
          .where((t) => t.isNotEmpty)
          .join('\n');

      return OcrResult(
        text: text,
        success: text.isNotEmpty,
        engine: OcrEngine.tencent,
      );
    } catch (e) {
      debugPrint('[TencentOcr] 识别失败: $e');
      return OcrResult(
        text: '',
        success: false,
        error: e.toString(),
        engine: OcrEngine.tencent,
      );
    }
  }
}

class AliyunOcrService implements OcrService {
  final String appCode;

  AliyunOcrService({required this.appCode});

  @override
  bool get isAvailable => appCode.isNotEmpty;

  @override
  String get engineName => '阿里云OCR';

  @override
  Future<OcrResult> recognizeText(
    Uint8List imageBytes, {
    String? mimeType,
  }) async {
    if (!isAvailable) {
      return const OcrResult(
        text: '',
        success: false,
        error: '阿里云OCR未配置',
        engine: OcrEngine.aliyun,
      );
    }

    try {
      final base64Image = base64Encode(imageBytes);
      final dio = Dio();
      final response = await dio.post(
        'https://ocrapi-advanced.taobao.com/ocrservice/advanced',
        data: {'img': base64Image},
        options: Options(
          headers: {
            'Authorization': 'APPCODE $appCode',
            'Content-Type': 'application/json',
          },
        ),
      );

      final prismWordsInfo = response.data['prism_wordsInfo'] as List?;
      if (prismWordsInfo == null || prismWordsInfo.isEmpty) {
        return const OcrResult(
          text: '',
          success: false,
          error: '未识别到文字',
          engine: OcrEngine.aliyun,
        );
      }

      final text = prismWordsInfo
          .map((item) => item['word'] as String? ?? '')
          .where((w) => w.isNotEmpty)
          .join('\n');

      return OcrResult(
        text: text,
        success: text.isNotEmpty,
        engine: OcrEngine.aliyun,
      );
    } catch (e) {
      debugPrint('[AliyunOcr] 识别失败: $e');
      return OcrResult(
        text: '',
        success: false,
        error: e.toString(),
        engine: OcrEngine.aliyun,
      );
    }
  }
}

class OcrServiceManager {
  LocalOcrService? _localService;
  OcrService? _cloudService;
  OcrEngine _currentEngine = OcrEngine.local;

  bool _localEnabled = true;
  bool _cloudEnabled = false;
  bool _autoOcr = true;

  bool get localEnabled => _localEnabled;
  bool get cloudEnabled => _cloudEnabled;
  bool get autoOcr => _autoOcr;
  OcrEngine get currentEngine => _currentEngine;

  Future<void> init() async {
    _localService = LocalOcrService();
    await _localService!.init();
  }

  void dispose() {
    _localService?.dispose();
  }

  void configure({
    bool? localEnabled,
    bool? cloudEnabled,
    bool? autoOcr,
    OcrEngine? cloudEngine,
    String? baiduApiKey,
    String? baiduSecretKey,
    String? tencentSecretId,
    String? tencentSecretKey,
    String? aliyunAppCode,
  }) {
    if (localEnabled != null) _localEnabled = localEnabled;
    if (cloudEnabled != null) _cloudEnabled = cloudEnabled;
    if (autoOcr != null) _autoOcr = autoOcr;
    if (cloudEngine != null) _currentEngine = cloudEngine;

    if (cloudEngine != null || cloudEnabled == true) {
      _cloudService = _createCloudService(
        engine: _currentEngine,
        baiduApiKey: baiduApiKey,
        baiduSecretKey: baiduSecretKey,
        tencentSecretId: tencentSecretId,
        tencentSecretKey: tencentSecretKey,
        aliyunAppCode: aliyunAppCode,
      );
    }
  }

  OcrService? _createCloudService({
    required OcrEngine engine,
    String? baiduApiKey,
    String? baiduSecretKey,
    String? tencentSecretId,
    String? tencentSecretKey,
    String? aliyunAppCode,
  }) {
    switch (engine) {
      case OcrEngine.baidu:
        if (baiduApiKey != null && baiduSecretKey != null) {
          return BaiduOcrService(
            apiKey: baiduApiKey,
            secretKey: baiduSecretKey,
          );
        }
        return null;
      case OcrEngine.tencent:
        if (tencentSecretId != null && tencentSecretKey != null) {
          return TencentOcrService(
            secretId: tencentSecretId,
            secretKey: tencentSecretKey,
          );
        }
        return null;
      case OcrEngine.aliyun:
        if (aliyunAppCode != null) {
          return AliyunOcrService(appCode: aliyunAppCode);
        }
        return null;
      default:
        return null;
    }
  }

  Future<OcrResult> recognizeText(
    Uint8List imageBytes, {
    String? mimeType,
  }) async {
    if (_cloudEnabled && _cloudService != null && _cloudService!.isAvailable) {
      final result = await _cloudService!.recognizeText(
        imageBytes,
        mimeType: mimeType,
      );
      if (result.success) return result;
    }

    if (_localEnabled && _localService != null && _localService!.isAvailable) {
      return await _localService!.recognizeText(imageBytes, mimeType: mimeType);
    }

    return const OcrResult(
      text: '',
      success: false,
      error: '无可用的OCR服务',
      engine: OcrEngine.local,
    );
  }
}
