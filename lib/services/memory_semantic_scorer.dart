import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';

import '../core/logger/app_logger.dart';
import 'ai_service_factory.dart';
import 'settings_service.dart';

class SemanticScoreResult {
  final double importance;
  final String summary;
  final List<String> semanticKeywords;
  final String? category;
  final bool isPersonalInfo;
  final bool hasTimeReference;
  final bool hasConflictPotential;

  const SemanticScoreResult({
    required this.importance,
    required this.summary,
    this.semanticKeywords = const [],
    this.category,
    this.isPersonalInfo = false,
    this.hasTimeReference = false,
    this.hasConflictPotential = false,
  });

  factory SemanticScoreResult.fallback(double regexScore) {
    return SemanticScoreResult(
      importance: regexScore,
      summary: '',
      semanticKeywords: const [],
    );
  }
}

/// 记忆语义评分器
///
/// 做什么：用 LLM 对记忆内容做重要性评分、摘要、关键词抽取、冲突检测。
/// 为什么这样做：纯正则评分无法理解语义（如"我决定下周搬家"的重要性），
/// LLM 能给出更准确的评分；但需可配置服务商，避免硬编码豆包。
///
/// 配置来源优先级：
/// 1. attachSettings() 注入 SettingsService 后，每次 score() 前自动从 settings 读取
/// 2. configure() 手动配置（向后兼容，外部测试用）
/// 3. 都没有则 isConfigured=false，走正则 fallback
class MemorySemanticScorer {
  static MemorySemanticScorer? _instance;
  static MemorySemanticScorer get instance =>
      _instance ??= MemorySemanticScorer._();

  MemorySemanticScorer._();

  final Dio _dio = Dio();

  /// 设置服务引用（注入后每次 score 前自动从 settings 读取最新配置）
  /// 为什么这样做：用户可能在运行时切换服务商/模型/API Key，
  /// 每次 score 前刷新配置可立即生效，无需重启 App。
  SettingsService? _settings;

  String? _apiKey;
  String _serviceId = 'doubao';
  String _model = 'ep-20241211143509-qn4v7';
  String _baseUrl = 'https://ark.cn-beijing.volces.com/api/v3';

  static const Duration _minInterval = Duration(seconds: 5);
  DateTime? _lastCallTime;
  int _totalCalls = 0;
  int _failedCalls = 0;
  int _skippedCalls = 0;

  static const int _minContentLength = 50;
  static const int _maxContentLength = 2000;

  int get totalCalls => _totalCalls;
  int get failedCalls => _failedCalls;
  int get skippedCalls => _skippedCalls;

  /// 注入 SettingsService，启用"从设置读取配置"模式
  /// 为什么这样做：避免硬编码豆包，允许用户复用任意已配置的 AI 服务商
  void attachSettings(SettingsService settings) {
    _settings = settings;
    AppLogger.i('[SemanticScorer] 已绑定 SettingsService，将从设置读取配置');
  }

  /// 手动配置（向后兼容 + 外部测试用）
  /// 为什么保留：单元测试或不依赖 SettingsService 的场景仍可直接配置
  void configure({
    required String apiKey,
    String serviceId = 'doubao',
    String? model,
    String? baseUrl,
  }) {
    _apiKey = apiKey;
    _serviceId = serviceId;

    if (model != null) _model = model;
    if (baseUrl != null) _baseUrl = baseUrl;

    _dio.options.baseUrl = _baseUrl;
    _dio.options.connectTimeout = const Duration(seconds: 10);
    _dio.options.receiveTimeout = const Duration(seconds: 15);

    AppLogger.i('[SemanticScorer] 配置完成: service=$_serviceId, model=$_model');
  }

  bool get isConfigured => _apiKey != null && _apiKey!.isNotEmpty;

  /// 从 SettingsService 刷新配置
  ///
  /// 做什么：读取用户配置的 scorerServiceId/model/apiKey/baseUrl 并更新内部状态。
  /// 为什么这样做：用户可能随时修改设置，每次评分前刷新保证配置最新；
  /// apiKey 优先从缓存读（同步、快），缓存为空时回退到 secure storage（异步）。
  /// 失败时保留旧配置，避免单次读取失败导致完全 fallback。
  Future<void> _refreshConfigFromSettings() async {
    final settings = _settings;
    if (settings == null) return; // 未注入 settings，使用 configure() 的配置

    try {
      final serviceId = settings.getMemoryScorerServiceId();
      final model = settings.getMemoryScorerModel();
      final baseUrl = AiServiceFactory.getBaseUrl(serviceId);

      // serviceId 或 baseUrl 为空说明用户未配置该服务商
      if (serviceId.isEmpty || baseUrl.isEmpty) {
        AppLogger.w('[SemanticScorer] 设置中的服务商无效: $serviceId');
        return;
      }

      // 优先从缓存读 API Key；缓存为空时从 secure storage 异步加载
      // 为什么这样做：缓存读取同步且快，避免每次评分都访问 secure storage
      var apiKey = settings.getApiKeyForService(serviceId);
      if (apiKey == null || apiKey.isEmpty) {
        apiKey = await settings.loadApiKeyForService(serviceId);
      }

      _serviceId = serviceId;
      _baseUrl = baseUrl;
      if (model.isNotEmpty) _model = model;
      _apiKey = apiKey;

      _dio.options.baseUrl = _baseUrl;
      _dio.options.connectTimeout = const Duration(seconds: 10);
      _dio.options.receiveTimeout = const Duration(seconds: 15);
    } catch (e) {
      AppLogger.w('[SemanticScorer] 从设置读取配置失败: $e');
    }
  }

  Future<SemanticScoreResult> score({
    required String content,
    required double regexScore,
    String? conversationId,
  }) async {
    // 每次评分前从 settings 刷新配置（若有）
    // 为什么这样做：用户可能刚切换服务商或更新 API Key，需立即生效
    await _refreshConfigFromSettings();

    if (!isConfigured) {
      _skippedCalls++;
      return SemanticScoreResult.fallback(regexScore);
    }

    if (content.length < _minContentLength) {
      _skippedCalls++;
      return SemanticScoreResult.fallback(regexScore);
    }

    if (!_checkRateLimit()) {
      _skippedCalls++;
      return SemanticScoreResult.fallback(regexScore);
    }

    if (regexScore >= 0.8) {
      return SemanticScoreResult(
        importance: regexScore,
        summary: _quickSummarize(content),
        semanticKeywords: _extractSemanticKeywords(content),
        isPersonalInfo: true,
      );
    }

    _totalCalls++;
    _lastCallTime = DateTime.now();

    try {
      final result = await _callLLM(content);
      return _mergeScores(regexScore, result);
    } catch (e) {
      _failedCalls++;
      AppLogger.w('[SemanticScorer] LLM 调用失败: $e');
      return SemanticScoreResult.fallback(regexScore);
    }
  }

  Future<SemanticScoreResult> _callLLM(String content) async {
    final truncated = content.length > _maxContentLength
        ? '${content.substring(0, _maxContentLength)}...'
        : content;

    final prompt =
        '''分析以下用户对话内容，返回JSON格式的重要性评分。

内容: "$truncated"

请返回严格的JSON（不要markdown代码块）:
{
  "importance": 0.0-1.0的评分,
  "summary": "一句话摘要",
  "keywords": ["关键词1", "关键词2"],
  "category": "个人信息/偏好/事件/情感/计划/知识/其他",
  "isPersonalInfo": true/false,
  "hasTimeReference": true/false,
  "hasConflictPotential": true/false
}

评分标准:
- 0.9+: 核心个人信息(姓名/住址/联系方式/健康/重要关系)
- 0.7-0.9: 重要偏好/计划/承诺/时间相关事件
- 0.5-0.7: 一般偏好/情感表达/日常事件
- 0.3-0.5: 普通对话/闲聊
- 0.0-0.3: 无实质内容

hasConflictPotential: 该信息是否可能与其他记忆冲突(如改变偏好、取消计划等)''';

    final messages = [
      {'role': 'system', 'content': '你是一个精确的信息分析助手。只返回JSON，不要任何其他文字。'},
      {'role': 'user', 'content': prompt},
    ];

    final response = await _dio.post(
      '/chat/completions',
      data: {
        'model': _model,
        'messages': messages,
        'temperature': 0.1,
        'max_tokens': 300,
      },
      options: Options(
        headers: {
          'Authorization': 'Bearer $_apiKey',
          'Content-Type': 'application/json',
        },
      ),
    );

    final body = response.data as Map<String, dynamic>;
    final choices = body['choices'] as List<dynamic>?;
    if (choices == null || choices.isEmpty) {
      throw Exception('空响应');
    }

    final reply = choices[0]['message']['content'] as String;
    return _parseLLMResponse(reply);
  }

  SemanticScoreResult _parseLLMResponse(String reply) {
    try {
      String jsonStr = reply.trim();
      if (jsonStr.startsWith('```')) {
        jsonStr = jsonStr
            .replaceAll(RegExp(r'^```\w*\n?'), '')
            .replaceAll(RegExp(r'\n?```$'), '');
      }

      final data = _parseJson(jsonStr);
      if (data == null) {
        return const SemanticScoreResult(
          importance: 0.5,
          summary: '',
          semanticKeywords: [],
        );
      }

      return SemanticScoreResult(
        importance: _clampDouble(
          (data['importance'] as num?)?.toDouble() ?? 0.5,
          0.0,
          1.0,
        ),
        summary: (data['summary'] as String?) ?? '',
        semanticKeywords: _parseStringList(data['keywords']),
        category: data['category'] as String?,
        isPersonalInfo: data['isPersonalInfo'] as bool? ?? false,
        hasTimeReference: data['hasTimeReference'] as bool? ?? false,
        hasConflictPotential: data['hasConflictPotential'] as bool? ?? false,
      );
    } catch (e) {
      AppLogger.w('[SemanticScorer] 解析 LLM 响应失败: $e');
      return const SemanticScoreResult(
        importance: 0.5,
        summary: '',
        semanticKeywords: [],
      );
    }
  }

  SemanticScoreResult _mergeScores(
    double regexScore,
    SemanticScoreResult llmResult,
  ) {
    double finalImportance;

    if (regexScore >= 0.8) {
      finalImportance = regexScore;
    } else if (llmResult.importance >= 0.8) {
      finalImportance = (regexScore * 0.3 + llmResult.importance * 0.7).clamp(
        0.0,
        1.0,
      );
    } else {
      finalImportance = (regexScore * 0.4 + llmResult.importance * 0.6).clamp(
        0.0,
        1.0,
      );
    }

    return SemanticScoreResult(
      importance: finalImportance,
      summary: llmResult.summary,
      semanticKeywords: llmResult.semanticKeywords,
      category: llmResult.category,
      isPersonalInfo: llmResult.isPersonalInfo || regexScore >= 0.7,
      hasTimeReference: llmResult.hasTimeReference,
      hasConflictPotential: llmResult.hasConflictPotential,
    );
  }

  bool _checkRateLimit() {
    if (_lastCallTime == null) return true;
    return DateTime.now().difference(_lastCallTime!) >= _minInterval;
  }

  String _quickSummarize(String content) {
    final sentences = content.split(RegExp(r'[。！？\n]'));
    final meaningful = sentences
        .where((s) => s.trim().length > 5)
        .take(2)
        .map((s) => s.trim())
        .toList();
    return meaningful.join('；');
  }

  List<String> _extractSemanticKeywords(String content) {
    final patterns = <RegExp, String>{
      RegExp(r'(?:我叫|名字是|我是)\s*(\S{1,10})'): '姓名',
      RegExp(r'(?:住在|地址|家在)\s*(\S{1,20})'): '地址',
      RegExp(r'(?:喜欢|爱|偏好)\s*(\S{1,15})'): '偏好',
      RegExp(r'(?:讨厌|不喜欢|反感)\s*(\S{1,15})'): '反感',
      RegExp(r'(?:害怕|恐惧|怕)\s*(\S{1,15})'): '恐惧',
      RegExp(r'(?:下周|明天|今天|本周|下个月)\s*(\S{1,20})'): '时间计划',
      RegExp(r'(?:决定|打算|计划)\s*(\S{1,20})'): '计划',
      RegExp(r'(?:养了|买了|有)\s*(\S{1,10})'): '拥有',
    };

    final keywords = <String>[];
    for (final entry in patterns.entries) {
      final match = entry.key.firstMatch(content);
      if (match != null) {
        keywords.add('${entry.value}:${match.group(1) ?? ""}');
      }
    }

    return keywords;
  }

  Map<String, dynamic>? _parseJson(String str) {
    try {
      final start = str.indexOf('{');
      final end = str.lastIndexOf('}');
      if (start == -1 || end == -1 || end <= start) return null;
      return _jsonDecode(str.substring(start, end + 1));
    } catch (_) {
      return null;
    }
  }

  Map<String, dynamic> _jsonDecode(String s) {
    return jsonDecode(s) as Map<String, dynamic>;
  }

  List<String> _parseStringList(dynamic value) {
    if (value is List) {
      return value.map((e) => e.toString()).toList();
    }
    return [];
  }

  double _clampDouble(double v, double min, double max) {
    if (v < min) return min;
    if (v > max) return max;
    return v;
  }

  void dispose() {
    _dio.close();
    _instance = null;
    AppLogger.i(
      '[SemanticScorer] 已关闭 (调用: $_totalCalls, 失败: $_failedCalls, 跳过: $_skippedCalls)',
    );
  }
}
