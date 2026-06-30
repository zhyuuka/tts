import 'package:dio/dio.dart';

import '../models/message.dart';
import 'ai_service.dart';
import 'message_payload_converter.dart';

class GeminiService extends AiService {
  late final Dio _dio;
  String _apiKey;
  String _model;
  CancelToken? _cancelToken;

  double _temperature = 0.7;
  int _maxTokens = 8192;
  double _topP = 1.0;

  @override
  String get serviceName => 'Gemini';

  @override
  String get serviceId => 'gemini';

  @override
  String get apiKey => _apiKey;

  @override
  set apiKey(String value) => _apiKey = value;

  @override
  String get model => _model;

  @override
  set model(String? value) {
    if (value != null && value.isNotEmpty) _model = value;
  }

  double get temperature => _temperature;
  set temperature(double v) => _temperature = v.clamp(0, 2);

  int get maxTokens => _maxTokens;
  set maxTokens(int v) => _maxTokens = v.clamp(1, 1048576);

  double get topP => _topP;
  set topP(double v) => _topP = v.clamp(0, 1);

  static const String _defaultModel = 'gemini-3.1';
  static const String _baseUrl =
      'https://generativelanguage.googleapis.com/v1beta';

  GeminiService({
    required String apiKey,
    String model = _defaultModel,
    Dio? dio,
  }) : _apiKey = apiKey,
       _model = model,
       _dio = dio ?? Dio() {
    _dio.options.baseUrl = _baseUrl;
    _dio.options.connectTimeout = const Duration(seconds: 30);
    _dio.options.receiveTimeout = const Duration(seconds: 120);
  }

  Map<String, dynamic> _buildGenerationConfig() {
    final config = <String, dynamic>{
      'temperature': _temperature,
      'maxOutputTokens': _maxTokens,
    };
    if (_topP < 1.0) config['topP'] = _topP;
    return config;
  }

  @override
  Future<List<Map<String, dynamic>>> convertMessages(
    List<Message> messages,
  ) async {
    return MessagePayloadConverter.toGeminiContents(messages);
  }

  @override
  Future<String> chat(List<Message> messages) async {
    try {
      final contents = await convertMessages(messages);

      final response = await _dio.post(
        '/models/$_model:generateContent',
        data: {
          'contents': contents,
          'generationConfig': _buildGenerationConfig(),
        },
        options: Options(
          headers: {
            'Content-Type': 'application/json',
            'x-goog-api-key': apiKey,
          },
        ),
      );

      if (response.statusCode == 200) {
        final data = response.data;
        if (data.containsKey('error')) {
          throw AiException(
            message: data['error']?['message'] ?? 'API 返回错误',
            service: serviceName,
          );
        }

        final candidates = data['candidates'] as List?;
        if (candidates == null || candidates.isEmpty) {
          throw AiException(message: 'API 未返回任何回复', service: serviceName);
        }

        final parts = candidates.first['content']?['parts'] as List?;
        if (parts == null || parts.isEmpty) {
          throw AiException(message: '回复消息格式错误', service: serviceName);
        }

        return parts.first['text'] as String? ?? '';
      } else {
        throw AiException(
          message: '请求失败',
          service: serviceName,
          code: response.statusCode?.toString(),
        );
      }
    } on DioException catch (e) {
      throw handleDioError(e);
    } catch (e) {
      if (e is AiException) rethrow;
      throw AiException(message: '未知错误: $e', service: serviceName);
    }
  }

  @override
  Stream<ChatChunk> chatStream(List<Message> messages) async* {
    _cancelToken = CancelToken();
    try {
      final contents = await convertMessages(messages);

      final response = await _dio.post<ResponseBody>(
        '/models/$_model:streamGenerateContent',
        queryParameters: {'alt': 'sse'},
        data: {
          'contents': contents,
          'generationConfig': _buildGenerationConfig(),
        },
        options: Options(
          headers: {
            'Content-Type': 'application/json',
            'x-goog-api-key': apiKey,
          },
          responseType: ResponseType.stream,
          receiveTimeout: const Duration(minutes: 5),
        ),
        cancelToken: _cancelToken,
      );
      yield* parseGeminiSseStream(response.data!.stream);
    } on DioException catch (e) {
      if (!CancelToken.isCancel(e)) throw handleDioError(e);
    } finally {
      _cancelToken = null;
    }
  }

  @override
  void cancelStream() {
    _cancelToken?.cancel();
    _cancelToken = null;
  }
}
