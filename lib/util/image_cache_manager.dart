import 'package:flutter/widgets.dart';

/// 全局图像缓存管理器，避免重复解码base64
class ImageCacheManager {
  static final ImageCacheManager _instance = ImageCacheManager._internal();
  factory ImageCacheManager() => _instance;
  ImageCacheManager._internal();

  final Map<String, ImageProvider> _cache = {};

  ImageProvider? getImage(String base64) {
    return _cache[base64];
  }

  void setImage(String base64, ImageProvider provider) {
    _cache[base64] = provider;
  }

  void clear() {
    _cache.clear();
  }
}
