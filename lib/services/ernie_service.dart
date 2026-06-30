import 'package:dio/dio.dart';

import '../models/message.dart';
import 'ai_service.dart';
import 'message_payload_converter.dart';

class ErnieService extends AiService {
  late final Dio _dio;
  String _apiKey;
  String _model;
  CancelToken? _cancelToken;

  double _temperature = 0.7;
  int _maxTokens = 4096;
  double _topP = 1.0;

  ErnieService({required String apiKey, String? model})
    : _apiKey = apiKey,
      _model = model ?? 'ernie-5.1' {
    _dio = Dio();
    _dio.options.baseUrl =
        'https://aip.baidubce.com/rpc/2.0/ai_custom/v1/wenxinworkshop';
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
    if (value != null && value.isNotEmpty) _model = value;
  }

  double get temperature => _temperature;
  set temperature(double v) => _temperature = v.clamp(0.01, 1);

  int get maxTokens => _maxTokens;
  set maxTokens(int v) => _maxTokens = v.clamp(1, 1048576);

  double get topP => _topP;
  set topP(double v) => _topP = v.clamp(0, 1);

  static const Map<String, String> _modelEndpointMap = {
    'ernie-5.1': 'ernie-5.1',
    'ernie-4.0-8k': 'completions_pro',
    'ernie-3.5-8k': 'completions',
    'ernie-speed-128k': 'ernie-speed-128k',
    'ernie-lite-8k': 'eb-instant',
  };

  String get _endpoint => _modelEndpointMap[_model] ?? 'completions_pro';

  Map<String, dynamic> _buildGenerationConfig() {
    final config = <String, dynamic>{};
    if (_temperature != 0.7) config['temperature'] = _temperature;
    if (_maxTokens != 4096) config['max_output_tokens'] = _maxTokens;
    if (_topP < 1.0) config['top_p'] = _topP;
    return config;
  }

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
        '/$_endpoint',
        queryParameters: {'access_token': _apiKey},
        data: {
          'messages': apiMessages,
          'stream': false,
          ..._buildGenerationConfig(),
        },
        options: Options(headers: {'Content-Type': 'application/json'}),
      );

      if (response.statusCode == 200) {
        final data = response.data;
        if (data.containsKey('error_code')) {
          throw AiException(
            message: data['error_msg'] ?? 'API 返回错误',
            service: serviceName,
          );
        }
        return data['result'] as String? ?? '';
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
        '/$_endpoint',
        queryParameters: {'access_token': _apiKey},
        data: {
          'messages': apiMessages,
          'stream': true,
          ..._buildGenerationConfig(),
        },
        options: Options(
          headers: {'Content-Type': 'application/json'},
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

  @override
  String get serviceName => '文心一言';

  @override
  String get serviceId => 'ernie';
}
