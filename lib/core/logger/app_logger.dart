import 'package:flutter/foundation.dart';
import 'package:logger/logger.dart';

import '../errors/chat_error.dart';

class AppLogger {
  static late final Logger _instance;
  static bool _initialized = false;
  static Level? _cachedLevel;

  static void init({Level? minLevel, bool? printColors}) {
    if (_initialized) return;

    final effectiveMinLevel =
        minLevel ?? (kReleaseMode ? Level.warning : Level.debug);
    _cachedLevel = effectiveMinLevel;

    _instance = Logger(
      level: effectiveMinLevel,
      printer: PrettyPrinter(
        methodCount: 0,
        errorMethodCount: 5,
        lineLength: 120,
        colors: printColors ?? !kReleaseMode,
        printEmojis: true,
        dateTimeFormat: DateTimeFormat.onlyTimeAndSinceStart,
        noBoxingByDefault: true,
      ),
    );

    _initialized = true;
    _instance.i('AppLogger initialized (min level: ${effectiveMinLevel.name})');
  }

  static Logger module(String moduleName) {
    if (!_initialized) init();
    return Logger(
      printer: PrettyPrinter(
        methodCount: 0,
        errorMethodCount: 2,
        lineLength: 100,
        colors: !kReleaseMode,
        printEmojis: true,
        dateTimeFormat: DateTimeFormat.onlyTimeAndSinceStart,
      ),
      level: _cachedLevel ?? Level.debug,
    );
  }

  static void t(String message, [Object? error, StackTrace? stackTrace]) =>
      _log(Level.trace, message, error, stackTrace);

  static void d(String message, [Object? error, StackTrace? stackTrace]) =>
      _log(Level.debug, message, error, stackTrace);

  static void i(String message, [Object? error, StackTrace? stackTrace]) =>
      _log(Level.info, message, error, stackTrace);

  static void w(String message, [Object? error, StackTrace? stackTrace]) =>
      _log(Level.warning, message, error, stackTrace);

  static void e(String message, [Object? error, StackTrace? stackTrace]) =>
      _log(Level.error, message, error, stackTrace);

  static void f(String message, [Object? error, StackTrace? stackTrace]) =>
      _log(Level.fatal, message, error, stackTrace);

  static void _log(
    Level level,
    String message,
    Object? error,
    StackTrace? stackTrace,
  ) {
    if (!_initialized) init();

    final safeMessage = _sanitize(message);
    final safeError = error != null ? _sanitize(error.toString()) : null;

    _instance.log(level, safeMessage, error: safeError, stackTrace: stackTrace);
  }

  static String _sanitize(String input) {
    var result = input;
    final apiKeyPatterns = [
      RegExp(
        r'(api[_-]?key["\s]*[:=]["\s]*)([a-zA-Z0-9_-]{20,})',
        caseSensitive: false,
      ),
      RegExp(r'("apiKey"\s*:\s*")([a-zA-Z0-9_-]{20,})"'),
      RegExp(r'(sk-)[a-zA-Z0-9]{20,}'),
      RegExp(r'(Bearer\s+)([a-zA-Z0-9._-]{20,})'),
    ];

    for (final pattern in apiKeyPatterns) {
      result = result.replaceAllMapped(
        pattern,
        (m) => '${m.group(1)}***MASKED***',
      );
    }

    final tokenPatterns = [
      RegExp(
        r'(token["\s]*[:=]["\s]*)([a-zA-Z0-9]{20,})',
        caseSensitive: false,
      ),
      RegExp(r'(access_token=)([a-zA-Z0-9.-_]{20,})'),
    ];
    for (final pattern in tokenPatterns) {
      result = result.replaceAllMapped(
        pattern,
        (m) => '${m.group(1)}***TOKEN***',
      );
    }

    final passwordPatterns = [
      RegExp(r'(password["\s]*[:=]["\s]*)(\S+)', caseSensitive: false),
      RegExp(r'(passwd["\s]*[:=]["\s]*)(\S+)', caseSensitive: false),
    ];
    for (final pattern in passwordPatterns) {
      result = result.replaceAllMapped(
        pattern,
        (m) => '${m.group(1)}***PASSWORD***',
      );
    }

    return result;
  }
}

extension ChatErrorLogging on ChatError {
  void logError([String? context]) {
    AppLogger.e('${context ?? ''}$userMessage$technicalDetails');
  }

  void logWarning([String? context]) {
    AppLogger.w('${context ?? ''}$userMessage$technicalDetails');
  }
}

extension PerformanceTimer on String {
  Stopwatch Function() startTimer([Level logLevel = Level.debug]) {
    final sw = Stopwatch()..start();
    final label = this;

    return () {
      sw.stop();
      final msg =
          '$label completed in ${sw.elapsedMilliseconds}ms (${sw.elapsed.inMilliseconds / 1000}s)';

      if (logLevel == Level.trace) {
        AppLogger.t(msg);
      } else if (logLevel == Level.debug) {
        AppLogger.d(msg);
      } else if (logLevel == Level.info) {
        AppLogger.i(msg);
      } else if (logLevel == Level.warning) {
        AppLogger.w(msg);
      } else if (logLevel == Level.error) {
        AppLogger.e(msg);
      } else {
        AppLogger.f(msg);
      }

      return sw;
    };
  }
}
