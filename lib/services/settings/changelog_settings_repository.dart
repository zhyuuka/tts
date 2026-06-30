import 'package:hive_flutter/hive_flutter.dart';

/// 更新日志配置仓库（Facade 模式阶段 2：更新日志子域）
///
/// 做什么：把 SettingsService 中更新日志相关配置（显示模式、不再提醒、
/// AI 搜索开关、AI 搜索不再提醒）抽到独立类。
/// 为什么这样做：更新日志子域虽然方法不多但逻辑独立，
/// 抽出后 SettingsService 保留同名 getter/setter 作为 Facade 转发。
class ChangelogSettingsRepository {
  // ── 依赖（通过构造函数注入）──
  final Future<bool> Function(
    Future<dynamic> Function(Box<dynamic> box) operation,
  )
  _safeWrite;
  final T Function<T>(T Function(Box<dynamic> box) operation, T defaultValue)
  _safeRead;

  ChangelogSettingsRepository({
    required Future<bool> Function(
      Future<dynamic> Function(Box<dynamic> box) operation,
    )
    safeWrite,
    required T Function<T>(
      T Function(Box<dynamic> box) operation,
      T defaultValue,
    )
    safeRead,
  }) : _safeWrite = safeWrite,
       _safeRead = safeRead;

  // ── 常量键 ──
  static const String _changelogModeKey = 'changelog_mode';
  static const String _changelogDontRemindModeKey =
      'changelog_dont_remind_mode';
  static const String _changelogAiSearchEnabledKey =
      'changelog_ai_search_enabled';
  static const String _changelogDontRemindAiSearchKey =
      'changelog_dont_remind_ai_search';

  // ── 更新日志设置 ──

  String getChangelogMode() {
    return _safeRead<String>(
      (box) => (box.get(_changelogModeKey) as String?) ?? 'professional',
      'professional',
    );
  }

  Future<bool> setChangelogMode(String mode) async {
    return await _safeWrite((box) => box.put(_changelogModeKey, mode));
  }

  bool isChangelogDontRemindMode() {
    return _safeRead<bool>(
      (box) => (box.get(_changelogDontRemindModeKey) as bool?) ?? false,
      false,
    );
  }

  Future<bool> setChangelogDontRemindMode(bool dontRemind) async {
    return await _safeWrite(
      (box) => box.put(_changelogDontRemindModeKey, dontRemind),
    );
  }

  bool isChangelogAiSearchEnabled() {
    return _safeRead<bool>(
      (box) => (box.get(_changelogAiSearchEnabledKey) as bool?) ?? false,
      false,
    );
  }

  Future<bool> setChangelogAiSearchEnabled(bool enabled) async {
    return await _safeWrite(
      (box) => box.put(_changelogAiSearchEnabledKey, enabled),
    );
  }

  bool isChangelogDontRemindAiSearch() {
    return _safeRead<bool>(
      (box) => (box.get(_changelogDontRemindAiSearchKey) as bool?) ?? false,
      false,
    );
  }

  Future<bool> setChangelogDontRemindAiSearch(bool dontRemind) async {
    return await _safeWrite(
      (box) => box.put(_changelogDontRemindAiSearchKey, dontRemind),
    );
  }
}
