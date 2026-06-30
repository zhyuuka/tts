import 'package:dio/dio.dart';

import 'ai_service.dart';
import '../models/message.dart';
import 'message_payload_converter.dart';

class CustomModelService extends AiService {
  late final Dio _dio;
  @override
  String apiKey;
  final String baseUrl;
  String _model;
  CancelToken? _cancelToken;

  CustomModelService({
    required this.apiKey,
    required this.baseUrl,
    required String model,
    Dio? dio,
  }) : _model = model,
       _dio = dio ?? Dio() {
    _dio.options.baseUrl = baseUrl;
    _dio.options.connectTimeout = const Duration(seconds: 30);
    _dio.options.receiveTimeout = const Duration(seconds: 120);
  }

  @override
  String get model => _model;

  @override
  set model(String? value) {
    if (value != null && value.isNotEmpty) {
      _model = value;
    }
  }

  @override
  String get serviceId => 'custom';

  @override
  String get serviceName => '自定义模型';

  @override
  Future<List<Map<String, dynamic>>> convertMessages(
    List<Message> messages,
  ) async {
    return MessagePayloadConverter.toOpenAiMessages(messages);
  }

  @override
  Future<String> chat(List<Message> messages) async {
    try {
      final apiMessages = await convertMessages(messages);
      final response = await _dio.post(
        '/chat/completions',
        data: {'model': _model, 'messages': apiMessages, 'stream': false},
        options: Options(
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $apiKey',
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
    _cancelToken = CancelToken();
    try {
      final apiMessages = await convertMessages(messages);
      final response = await _dio.post<ResponseBody>(
        '/chat/completions',
        data: {'model': _model, 'messages': apiMessages, 'stream': true},
        options: Options(
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $apiKey',
          },
          responseType: ResponseType.stream,
          receiveTimeout: const Duration(minutes: 5),
        ),
        cancelToken: _cancelToken,
      );
      yield* parseOpenAiSseStream(response.data!.stream);
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

  Map<String, dynamic> toJson() {
    return {
      'serviceId': serviceId,
      'apiKey': apiKey.isNotEmpty ? '••••••••' : '',
      'baseUrl': baseUrl,
      'model': model,
    };
  }

  factory CustomModelService.fromJson(Map<String, dynamic> json) {
    return CustomModelService(
      apiKey: json['apiKey'] ?? '',
      baseUrl: json['baseUrl'] ?? '',
      model: json['model'] ?? '',
    );
  }
}
