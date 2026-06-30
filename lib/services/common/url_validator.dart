import '../../core/logger/app_logger.dart';

/// 用户输入 URL 的格式校验结果。
class UrlValidationResult {
  /// 是否通过校验。
  final bool valid;

  /// 失败原因（valid 为 false 时有值）。
  final String? error;

  /// 归一化后的 URL（去首尾空白、补 https 前缀等）。
  /// valid 为 true 时可直接用于持久化。
  final String normalized;

  const UrlValidationResult({
    required this.valid,
    this.error,
    required this.normalized,
  });

  @override
  String toString() => valid
      ? 'UrlValidationResult(valid, "$normalized")'
      : 'UrlValidationResult(invalid: $error)';
}

/// 用户输入 URL 的格式校验工具。
///
/// 为什么需要它（P1 #12）：custom_model_base_url、searxng_url 等用户输入直接用于
/// Dio 请求，此前无任何格式校验。非法或恶意格式可能导致请求失败、连到非预期主机，
/// 或触发 Dio 解析异常。本类只做"格式合理性"校验，不做网络可达性探测。
///
/// 设计原则：
/// - 纯 Dart，无副作用，便于单元测试（参考 input_sanitizer 的测试模式）。
/// - 不做网络请求，仅静态校验。
/// - 返回 normalized URL，调用方可直接持久化，避免各处重复 trim/补前缀。
class UrlValidator {
  UrlValidator._();

  /// 校验 AI 服务商请求地址（custom_model_base_url 等）。
  ///
  /// 规则：
  /// - 非空、去空白。
  /// - 必须含 host，scheme 为 http/https（无 scheme 时按 https 补全）。
  /// - 不允许 file/ftp/data 等非网络 scheme。
  static UrlValidationResult validateServiceUrl(String input) {
    final raw = input.trim();
    if (raw.isEmpty) {
      return const UrlValidationResult(
        valid: false,
        error: '请输入请求地址',
        normalized: '',
      );
    }

    // 若用户没写 scheme，统一按 https 补全（与 search_service 的 SearXNG 处理一致）
    final withScheme = raw.contains('://') ? raw : 'https://$raw';

    final uri = Uri.tryParse(withScheme);
    if (uri == null || uri.host.isEmpty) {
      return UrlValidationResult(
        valid: false,
        error: '地址格式无效，无法解析主机名',
        normalized: raw,
      );
    }

    // 只允许 http/https，拒绝 file/data/ftp 等
    if (uri.scheme != 'http' && uri.scheme != 'https') {
      AppLogger.w('[UrlValidator] 拒绝非 http(s) scheme: ${uri.scheme}');
      return UrlValidationResult(
        valid: false,
        error: '仅支持 http 或 https 地址',
        normalized: raw,
      );
    }

    // 禁止明显的本地/内网探测（避免用户被诱导配置到 localhost 或内网地址）
    // 注意：开发调试时确有 localhost 合法需求，此处仅记录警告，不拦截。
    if (_looksLikeLoopback(uri.host)) {
      AppLogger.i('[UrlValidator] 主机指向本地回环，仅作提示不拦截: ${uri.host}');
    }

    return UrlValidationResult(valid: true, normalized: withScheme);
  }

  /// 校验 SearXNG 实例地址。
  ///
  /// 复用 [validateServiceUrl]，但额外要求：地址不能只是裸域名 + 必须能拼出 /search 端点。
  /// 当前实现等价于 serviceUrl（search_service 内部会补 /search 路径）。
  static UrlValidationResult validateSearXngUrl(String input) {
    final result = validateServiceUrl(input);
    if (!result.valid) {
      // 错误文案针对 SearXNG 语境调整
      return UrlValidationResult(
        valid: false,
        error: result.error == '请输入请求地址' ? '请输入 SearXNG 实例地址' : result.error,
        normalized: result.normalized,
      );
    }
    return result;
  }

  /// 判断 host 是否为本地回环（127.0.0.0/8、::1、localhost）。
  /// 仅用于提示日志，不做拦截。
  static bool _looksLikeLoopback(String host) {
    final lower = host.toLowerCase();
    if (lower == 'localhost') return true;
    if (lower == '::1') return true;
    if (lower.startsWith('127.')) return true;
    return false;
  }
}
