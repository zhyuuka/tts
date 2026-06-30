import 'package:dio/dio.dart';

import '../../core/logger/app_logger.dart';

/// 联网搜索引擎枚举
///
/// 支持四种搜索引擎：
/// - [duckduckgo]: DuckDuckGo 免费搜索，无需 API Key，隐私友好
/// - [searxng]:     SearXNG 聚合搜索引擎，需自建实例或使用公共实例
/// - [bing]:        Bing Web Search API，需 API Key，1000次/月免费
/// - [google]:      Google Programmable Search，需 API Key + 搜索引擎 ID，100次/天免费
enum SearchEngine {
  duckduckgo('duckduckgo', 'DuckDuckGo', '免费，无需配置'),
  searxng('searxng', 'SearXNG', '聚合多引擎，需实例地址'),
  bing('bing', 'Bing', '需 API Key，1000次/月'),
  google('google', 'Google', '需 API Key，100次/天');

  const SearchEngine(this.id, this.name, this.description);

  /// 存储用 ID
  final String id;

  /// 显示名称
  final String name;

  /// 简短描述
  final String description;
}

/// 单条搜索结果
class SearchResult {
  /// 结果标题
  final String title;

  /// 结果链接
  final String url;

  /// 结果摘要
  final String snippet;

  const SearchResult({
    required this.title,
    required this.url,
    required this.snippet,
  });
}

/// 联网搜索服务
///
/// 提供统一的搜索接口，支持多种搜索引擎后端。
/// 搜索结果会注入到 AI 对话上下文中，使 AI 能获取实时互联网信息。
///
/// 使用方式：
/// ```dart
/// final service = SearchService();
/// final context = await service.search('最新科技新闻', engine: SearchEngine.duckduckgo);
/// // context 为格式化的搜索结果文本，可直接拼入 AI 消息
/// ```
class SearchService {
  final Dio _dio;

  /// 默认最多返回的搜索结果条数
  static const int defaultMaxResults = 5;

  SearchService({Dio? dio})
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              connectTimeout: const Duration(seconds: 8),
              receiveTimeout: const Duration(seconds: 10),
            ),
          );

  /// 执行联网搜索，返回格式化的上下文文本
  ///
  /// [query] - 搜索关键词
  /// [engine] - 搜索引擎（默认 duckduckgo）
  /// [apiKey] - API Key（Bing/Google 需要）
  /// [searchEngineId] - Google 搜索引擎 ID（cx）
  /// [customUrl] - SearXNG 自定义实例地址（如 https://searx.be）
  /// [maxResults] - 最多返回几条结果（默认 5）
  ///
  /// 返回格式化文本，包含搜索结果标题、链接和摘要。
  /// 搜索失败时返回空字符串（不抛异常，保证 AI 对话不中断）。
  Future<String> search({
    required String query,
    SearchEngine engine = SearchEngine.duckduckgo,
    String? apiKey,
    String? searchEngineId,
    String? customUrl,
    int maxResults = defaultMaxResults,
    CancelToken? cancelToken,
  }) async {
    try {
      final results = await _doSearch(
        query: query,
        engine: engine,
        apiKey: apiKey,
        searchEngineId: searchEngineId,
        customUrl: customUrl,
        maxResults: maxResults,
        cancelToken: cancelToken,
      );

      if (results.isEmpty) return '';

      // 将搜索结果格式化为 AI 可读的上下文文本
      final buffer = StringBuffer();
      buffer.writeln('以下是从互联网搜索到的相关信息（搜索词: "$query"）：');
      buffer.writeln();
      for (var i = 0; i < results.length; i++) {
        final r = results[i];
        buffer.writeln('[${i + 1}] ${r.title}');
        buffer.writeln('    链接: ${r.url}');
        buffer.writeln('    摘要: ${r.snippet}');
        buffer.writeln();
      }
      buffer.writeln('请参考以上搜索结果回答用户问题。如果搜索结果与问题无关，请忽略并使用自身知识回答。');
      return buffer.toString();
    } catch (e) {
      AppLogger.e('[SearchService] 搜索失败: $e');
      return '';
    }
  }

  Future<List<SearchResult>> searchRaw({
    required String query,
    SearchEngine engine = SearchEngine.duckduckgo,
    String? apiKey,
    String? searchEngineId,
    String? customUrl,
    int maxResults = defaultMaxResults,
    CancelToken? cancelToken,
  }) async {
    try {
      return await _doSearch(
        query: query,
        engine: engine,
        apiKey: apiKey,
        searchEngineId: searchEngineId,
        customUrl: customUrl,
        maxResults: maxResults,
        cancelToken: cancelToken,
      );
    } catch (e) {
      AppLogger.e('[SearchService] 搜索失败: $e');
      return [];
    }
  }

  Future<List<SearchResult>> _doSearch({
    required String query,
    required SearchEngine engine,
    String? apiKey,
    String? searchEngineId,
    String? customUrl,
    required int maxResults,
    CancelToken? cancelToken,
  }) async {
    switch (engine) {
      case SearchEngine.duckduckgo:
        return _searchDuckDuckGo(query, maxResults, cancelToken);
      case SearchEngine.searxng:
        return _searchSearXNG(query, customUrl ?? '', maxResults, cancelToken);
      case SearchEngine.bing:
        return _searchBing(query, apiKey ?? '', maxResults, cancelToken);
      case SearchEngine.google:
        return _searchGoogle(
          query,
          apiKey ?? '',
          searchEngineId ?? '',
          maxResults,
          cancelToken,
        );
    }
  }

  // ── DuckDuckGo 搜索 ──
  //
  // 使用 DuckDuckGo Lite 版本的 HTML 端点。
  // 无需 API Key，零配置，但可能有频率限制（个人使用足够）。
  // 隐私友好，不追踪用户搜索记录。
  Future<List<SearchResult>> _searchDuckDuckGo(
    String query,
    int maxResults,
    CancelToken? cancelToken,
  ) async {
    final response = await _dio.post(
      'https://lite.duckduckgo.com/lite/',
      data: 'q=${Uri.encodeComponent(query)}',
      options: Options(
        headers: {
          'Content-Type': 'application/x-www-form-urlencoded',
          'User-Agent':
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
        },
        connectTimeout: const Duration(seconds: 6),
        receiveTimeout: const Duration(seconds: 8),
      ),
      cancelToken: cancelToken,
    );

    final html = response.data.toString();
    return _parseDuckDuckGoHtml(html, maxResults);
  }

  /// 解析 DuckDuckGo Lite 的 HTML 响应
  ///
  /// HTML 结构：
  /// - 结果链接: <a class="result-link" href="...">标题</a>
  /// - 结果摘要: <td class="result-snippet">...</td>
  /// - 真实 URL 在链接后紧跟的 <td> 中
  List<SearchResult> _parseDuckDuckGoHtml(String html, int maxResults) {
    final results = <SearchResult>[];

    // 用正则匹配结果表格行，每行包含一个搜索结果
    // DuckDuckGo Lite 的结构是 <tr><td>链接</td><td>摘要</td></tr>
    final rowPattern = RegExp(
      r'<a[^>]+class="result-link"[^>]*href="([^"]*)"[^>]*>(.*?)</a>.*?'
      r'<td[^>]+class="result-snippet"[^>]*>(.*?)</td>',
      dotAll: true,
    );

    // 备用模式：匹配更宽松的结构
    final linkPattern = RegExp(
      r'class="result-link"[^>]*href="([^"]*)"[^>]*>(.*?)</a>',
      dotAll: true,
    );
    final snippetPattern = RegExp(
      r'class="result-snippet"[^>]*>(.*?)</td>',
      dotAll: true,
    );

    // 先尝试精确匹配
    for (final match in rowPattern.allMatches(html)) {
      final url = _stripDdgRedirect(match.group(1) ?? '');
      final title = _stripHtmlTags(match.group(2) ?? '');
      final snippet = _stripHtmlTags(match.group(3) ?? '');

      if (url.isNotEmpty && title.isNotEmpty) {
        results.add(SearchResult(title: title, url: url, snippet: snippet));
        if (results.length >= maxResults) break;
      }
    }

    // 精确匹配失败时使用宽松匹配
    if (results.isEmpty) {
      final links = linkPattern.allMatches(html).toList();
      final snippets = snippetPattern.allMatches(html).toList();

      final count = links.length < snippets.length
          ? links.length
          : snippets.length;
      for (var i = 0; i < count && results.length < maxResults; i++) {
        final url = _stripDdgRedirect(links[i].group(1) ?? '');
        final title = _stripHtmlTags(links[i].group(2) ?? '');
        final snippet = _stripHtmlTags(snippets[i].group(1) ?? '');

        if (url.isNotEmpty && title.isNotEmpty) {
          results.add(SearchResult(title: title, url: url, snippet: snippet));
        }
      }
    }

    return results;
  }

  /// 去除 DuckDuckGo 的重定向前缀
  ///
  /// DuckDuckGo 的链接格式为：`/l/?uddg=ENCODED_URL&rut=...`
  /// 需要提取 `uddg` 参数中的真实 URL
  String _stripDdgRedirect(String url) {
    if (url.startsWith('/l/')) {
      final uri = Uri.parse('https://lite.duckduckgo.com$url');
      final realUrl = uri.queryParameters['uddg'];
      if (realUrl != null) {
        return Uri.decodeComponent(realUrl);
      }
    }
    // 已经是完整 URL
    if (url.startsWith('http')) return url;
    return '';
  }

  // ── SearXNG 搜索 ──
  //
  // SearXNG 是开源的聚合元搜索引擎，可同时搜索 Google/Bing/DuckDuckGo 等多个引擎。
  // 需要用户自建实例或使用公共实例（如 https://searx.be, https://search.sapti.me）。
  // 使用 JSON API: GET /search?q=QUERY&format=json
  Future<List<SearchResult>> _searchSearXNG(
    String query,
    String instanceUrl,
    int maxResults,
    CancelToken? cancelToken,
  ) async {
    final baseUrl = instanceUrl.startsWith('http')
        ? instanceUrl
        : 'https://$instanceUrl';
    final cleanUrl = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;

    final response = await _dio.get(
      '$cleanUrl/search',
      queryParameters: {'q': query, 'format': 'json', 's': 0},
      options: Options(
        headers: {
          'User-Agent':
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
        },
        receiveTimeout: const Duration(seconds: 15),
      ),
      cancelToken: cancelToken,
    );

    final data = response.data;
    if (data is! Map) return [];

    final results = data['results'] as List? ?? [];
    return results
        .take(maxResults)
        .map((item) => item as Map<String, dynamic>)
        .where((item) => (item['url'] as String?)?.isNotEmpty == true)
        .map(
          (item) => SearchResult(
            title: item['title'] as String? ?? '',
            url: item['url'] as String? ?? '',
            snippet: item['content'] as String? ?? '',
          ),
        )
        .toList();
  }

  // ── Bing Web Search API ──
  //
  // 微软 Bing 搜索 API，结果质量高。
  // 免费额度：1000次/月（需在 Azure 注册）。
  // API 端点: https://api.bing.microsoft.com/v7.0/search
  // 文档: https://learn.microsoft.com/en-us/bing/search-apis/bing-web-search/
  Future<List<SearchResult>> _searchBing(
    String query,
    String apiKey,
    int maxResults,
    CancelToken? cancelToken,
  ) async {
    if (apiKey.isEmpty) {
      AppLogger.w('[SearchService] Bing 搜索需要 API Key');
      return [];
    }

    final response = await _dio.get(
      'https://api.bing.microsoft.com/v7.0/search',
      queryParameters: {'q': query, 'count': maxResults, 'mkt': 'zh-CN'},
      options: Options(
        headers: {'Ocp-Apim-Subscription-Key': apiKey},
        receiveTimeout: const Duration(seconds: 15),
      ),
      cancelToken: cancelToken,
    );

    final data = response.data;
    if (data is! Map) return [];

    final webPages = data['webPages'] as Map<String, dynamic>? ?? {};
    final values = webPages['value'] as List? ?? [];

    return values
        .take(maxResults)
        .map((item) => item as Map<String, dynamic>)
        .map(
          (item) => SearchResult(
            title: item['name'] as String? ?? '',
            url: item['url'] as String? ?? '',
            snippet: item['snippet'] as String? ?? '',
          ),
        )
        .toList();
  }

  // ── Google Programmable Search API ──
  //
  // 谷歌可编程搜索引擎（原名 Custom Search JSON API）。
  // 免费额度：100次/天（需注册 Google Cloud 并启用 API）。
  // 需要两个配置：
  ///   1. API Key - 在 Google Cloud Console 获取
  ///   2. 搜索引擎 ID (cx) - 在 https://programmablesearchengine.google.com 创建
  // API 端点: https://www.googleapis.com/customsearch/v1
  // 文档: https://developers.google.com/custom-search/v1/overview
  Future<List<SearchResult>> _searchGoogle(
    String query,
    String apiKey,
    String searchEngineId,
    int maxResults,
    CancelToken? cancelToken,
  ) async {
    if (apiKey.isEmpty || searchEngineId.isEmpty) {
      AppLogger.w('[SearchService] Google 搜索需要 API Key 和搜索引擎 ID');
      return [];
    }

    final response = await _dio.get(
      'https://www.googleapis.com/customsearch/v1',
      queryParameters: {
        'key': apiKey,
        'cx': searchEngineId,
        'q': query,
        'num': maxResults,
        'lr': 'lang_zh-CN',
      },
      options: Options(receiveTimeout: const Duration(seconds: 15)),
      cancelToken: cancelToken,
    );

    final data = response.data;
    if (data is! Map) return [];

    final items = data['items'] as List? ?? [];
    return items
        .take(maxResults)
        .map((item) => item as Map<String, dynamic>)
        .map(
          (item) => SearchResult(
            title: item['title'] as String? ?? '',
            url: item['link'] as String? ?? '',
            snippet: item['snippet'] as String? ?? '',
          ),
        )
        .toList();
  }

  // ── HTML 工具方法 ──

  /// 去除 HTML 标签，提取纯文本
  ///
  /// 将 `<b>text</b>` 转为 `text`，同时处理 HTML 实体（如 `&amp;` → `&`）
  String _stripHtmlTags(String html) {
    return html
        .replaceAll(RegExp(r'<[^>]*>'), '') // 去除所有 HTML 标签
        .replaceAll(RegExp(r'&amp;'), '&')
        .replaceAll(RegExp(r'&lt;'), '<')
        .replaceAll(RegExp(r'&gt;'), '>')
        .replaceAll(RegExp(r'&quot;'), '"')
        .replaceAll(RegExp(r'&#39;'), "'")
        .replaceAll(RegExp(r'&nbsp;'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ') // 合并多余空白
        .trim();
  }
}
