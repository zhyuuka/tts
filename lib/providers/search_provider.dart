import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../core/logger/app_logger.dart';
import '../services/common/debug_mode_service.dart';
import '../services/search/search_service.dart';
import '../services/settings_service.dart';

class SearchProvider extends ChangeNotifier {
  final SettingsService _settingsService;
  final SearchService _searchService;

  bool _isSearching = false;
  String? _error;
  CancelToken? _cancelToken;
  bool _disposed = false;

  SearchProvider({
    required SettingsService settingsService,
    required SearchService searchService,
  }) : _settingsService = settingsService,
       _searchService = searchService;

  bool get isSearching => _isSearching;
  String? get error => _error;
  bool get isEnabled =>
      _settingsService.isInitialized && _settingsService.isSearchEnabled();

  Future<String> performWebSearch(
    String query, {
    CancelToken? cancelToken,
  }) async {
    if (!isEnabled) {
      AppLogger.d('[SearchProvider] 搜索未启用，跳过');
      return '';
    }

    _isSearching = true;
    _error = null;
    notifyListeners();

    try {
      final engineId = _settingsService.getSearchEngine();
      final engine = SearchEngine.values.firstWhere(
        (e) => e.id == engineId,
        orElse: () => SearchEngine.duckduckgo,
      );
      final apiKey = _settingsService.getSearchApiKey();
      final googleCx = _settingsService.getGoogleSearchEngineId();
      final searxngUrl = _settingsService.getSearXngUrl();

      AppLogger.d('[SearchProvider] 联网搜索: engine=$engineId, query=$query');

      final context = await _searchService.search(
        query: query,
        engine: engine,
        apiKey: apiKey,
        searchEngineId: googleCx,
        customUrl: searxngUrl,
        cancelToken: cancelToken,
      );

      if (context.isNotEmpty) {
        AppLogger.i('[SearchProvider] 搜索成功，获取到上下文 (${context.length} 字符)');

        final dbg = DebugModeService.instance;
        dbg.logSearchContext(
          query: query,
          engine: engineId,
          resultCount: context
              .split('\n')
              .where((l) => l.startsWith('['))
              .length,
          contextPreview: context.substring(0, context.length.clamp(0, 200)),
        );
      } else {
        AppLogger.d('[SearchProvider] 搜索无结果');
      }

      return context;
    } on DioException catch (e) {
      if (CancelToken.isCancel(e)) {
        AppLogger.d('[SearchProvider] 搜索已取消');
        return '';
      }
      AppLogger.e('[SearchProvider] 联网搜索异常: $e');
      _error = '搜索失败: $e';
      return '';
    } catch (e) {
      AppLogger.e('[SearchProvider] 联网搜索异常: $e');
      _error = '搜索失败: $e';
      return '';
    } finally {
      _isSearching = false;
      notifyListeners();
    }
  }

  Future<String> searchWithTimeout(
    String query, {
    Duration timeout = const Duration(seconds: 10),
  }) async {
    _cancelToken?.cancel();
    _cancelToken = CancelToken();

    try {
      return await performWebSearch(query, cancelToken: _cancelToken).timeout(
        timeout,
        onTimeout: () {
          _cancelToken?.cancel();
          AppLogger.d('[SearchProvider] 联网搜索超时(${timeout.inSeconds}s)，已取消');
          return '';
        },
      );
    } catch (e) {
      AppLogger.d('[SearchProvider] 联网搜索失败，跳过: $e');
      return '';
    }
  }

  Future<List<SearchResult>> performWebSearchRaw(
    String query, {
    CancelToken? cancelToken,
  }) async {
    if (!isEnabled) return [];

    // 如果外部未传 cancelToken，使用内部 _cancelToken，使 cancelSearch() 能生效
    // 为什么这样做：原代码不使用 _cancelToken，导致 cancelSearch() 无法取消本方法发起的请求
    CancelToken? token = cancelToken;
    if (token == null) {
      _cancelToken?.cancel();
      _cancelToken = CancelToken();
      token = _cancelToken;
    }

    _isSearching = true;
    _error = null;
    notifyListeners();

    try {
      final engineId = _settingsService.getSearchEngine();
      final engine = SearchEngine.values.firstWhere(
        (e) => e.id == engineId,
        orElse: () => SearchEngine.duckduckgo,
      );
      final apiKey = _settingsService.getSearchApiKey();
      final googleCx = _settingsService.getGoogleSearchEngineId();
      final searxngUrl = _settingsService.getSearXngUrl();

      return await _searchService.searchRaw(
        query: query,
        engine: engine,
        apiKey: apiKey,
        searchEngineId: googleCx,
        customUrl: searxngUrl,
        cancelToken: token,
      );
    } catch (e) {
      AppLogger.e('[SearchProvider] 联网搜索异常: $e');
      return [];
    } finally {
      _isSearching = false;
      notifyListeners();
    }
  }

  void cancelSearch() {
    _cancelToken?.cancel();
    _cancelToken = null;
  }

  @override
  void dispose() {
    // 防御 double dispose：getter 公开导致外部可能拿到引用误调 dispose。
    // 为什么这样做：ChangeNotifier 重复 dispose 会抛 "used after disposed" 断言。
    // 同时取消正在进行的搜索请求，避免 dispose 后还有网络回调触发 notifyListeners。
    if (_disposed) return;
    _disposed = true;
    _cancelToken?.cancel();
    _cancelToken = null;
    super.dispose();
  }
}
