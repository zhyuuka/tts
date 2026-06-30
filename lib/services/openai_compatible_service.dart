import 'package:dio/dio.dart';

import '../models/message.dart';
import 'ai_service.dart';
import 'message_payload_converter.dart';

abstract class OpenAiCompatibleService extends AiService {
  late final Dio _dio;
  String _apiKey;
  String _model;
  CancelToken? cancelToken;

  final String serviceBaseUrl;
  final String serviceDefaultModel;
  final bool usePlainTextMessages;

  double _temperature = 0.7;
  int _maxTokens = 4096;
  double _topP = 1.0;
  double _frequencyPenalty = 0;
  double _presencePenalty = 0;

  OpenAiCompatibleService({
    required String apiKey,
    required this.serviceBaseUrl,
    required this.serviceDefaultModel,
    this.usePlainTextMessages = false,
    String? model,
    Dio? dio,
  }) : _apiKey = apiKey,
       _model = model ?? serviceDefaultModel,
       _dio = dio ?? Dio() {
    _dio.options.baseUrl = serviceBaseUrl;
    _dio.options.connectTimeout = const Duration(seconds: 30);
    _dio.options.receiveTimeout = const Duration(seconds: 120);
  }

  @override
  String get apiKey => _apiKey;

  @override
  set apiKey(String value) => _apiKey = value;

  @override
  String get model => _model;

  @override
  set model(String? value) {
    if (value != null && value.isNotEmpty) {
      _model = value;
    }
  }

  double get temperature => _temperature;
  set temperature(double v) => _temperature = v.clamp(0, 2);

  int get maxTokens => _maxTokens;
  set maxTokens(int v) => _maxTokens = v.clamp(1, 1048576);

  double get topP => _topP;
  set topP(double v) => _topP = v.clamp(0, 1);

  double get frequencyPenalty => _frequencyPenalty;
  set frequencyPenalty(double v) => _frequencyPenalty = v.clamp(-2, 2);

  double get presencePenalty => _presencePenalty;
  set presencePenalty(double v) => _presencePenalty = v.clamp(-2, 2);

  Dio get dio => _dio;

  Map<String, dynamic> buildGenerationConfig() => _buildGenerationConfig();

  Map<String, dynamic> _buildGenerationConfig() {
    final config = <String, dynamic>{
      'model': _model,
      'temperature': _temperature,
      'max_tokens': _maxTokens,
    };
    if (_topP < 1.0) config['top_p'] = _topP;
    if (_frequencyPenalty != 0) config['frequency_penalty'] = _frequencyPenalty;
    if (_presencePenalty != 0) config['presence_penalty'] = _presencePenalty;
    return config;
  }

  @override
  Future<List<Map<String, dynamic>>> convertMessages(
    List<Message> messages,
  ) async {
    if (usePlainTextMessages) {
      return MessagePayloadConverter.toPlainTextMessages(messages);
    }
    return MessagePayloadConverter.toOpenAiMessages(messages);
  }

  @override
  Future<String> chat(List<Message> messages) async {
    try {
      final apiMessages = await convertMessages(messages);
      final response = await _dio.post(
        '/chat/completions',
        data: {
          ..._buildGenerationConfig(),
          'messages': apiMessages,
          'stream': false,
        },
        options: Options(
          headers: {
            'Content-Type': 'application/json',
            'Authorization': buildAuthHeader(),
          },
        ),
      );

      if (response.statusCode == 200) {
        final data = response.data;
        if (data.containsKey('error')) {
          final error = data['error'];
          throw AiException(
            message: error['message'] ?? 'API 返回错误',
            service: serviceName,
          );
        }

        final choices = data['choices'] as List?;
        if (choices == null || choices.isEmpty) {
          throw AiException(message: 'API 未返回任何回复', service: serviceName);
        }

        return choices.first['message']?['content'] as String? ?? '';
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
    cancelToken = CancelToken();
    try {
      final apiMessages = await convertMessages(messages);
      final response = await _dio.post<ResponseBody>(
        '/chat/completions',
        data: {
          ..._buildGenerationConfig(),
          'messages': apiMessages,
          'stream': true,
        },
        options: Options(
          headers: {
            'Content-Type': 'application/json',
            'Authorization': buildAuthHeader(),
          },
          responseType: ResponseType.stream,
          receiveTimeout: const Duration(minutes: 5),
        ),
        cancelToken: cancelToken,
      );
      yield* parseOpenAiSseStream(response.data!.stream);
    } on DioException catch (e) {
      if (!CancelToken.isCancel(e)) throw handleDioError(e);
    } finally {
      cancelToken = null;
    }
  }

  @override
  void cancelStream() {
    cancelToken?.cancel();
    cancelToken = null;
  }
}
