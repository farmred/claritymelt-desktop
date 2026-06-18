/// Application-wide logging utility.
///
/// Provides a singleton [log] instance configured for ClarityMelt.
/// Use [AppLog] for all logging instead of `print()` or `debugPrint()`.
library;

import 'package:logger/logger.dart';

/// Global logger instance.
///
/// Usage:
/// ```dart
/// AppLog.info('Syncing UC machine IDs');
/// AppLog.warning('Key load failed', error, stackTrace);
/// AppLog.error('SSH connection failed', error, stackTrace);
/// AppLog.debug('Parsed 3 machines from uc ls');
/// ```
class AppLog {
  static final Logger _logger = Logger(
    printer: PrettyPrinter(
      methodCount: 0,
      errorMethodCount: 5,
      lineLength: 100,
      colors: true,
      printEmojis: true,
      dateTimeFormat: DateTimeFormat.onlyTimeAndSinceStart,
    ),
    level: Level.debug,
  );

  static void debug(String message, [Object? error, StackTrace? st]) {
    _logger.d(message, error: error, stackTrace: st);
  }

  static void info(String message, [Object? error, StackTrace? st]) {
    _logger.i(message, error: error, stackTrace: st);
  }

  static void warning(String message, [Object? error, StackTrace? st]) {
    _logger.w(message, error: error, stackTrace: st);
  }

  static void error(String message, [Object? error, StackTrace? st]) {
    _logger.e(message, error: error, stackTrace: st);
  }

  static void verbose(String message, [Object? error, StackTrace? st]) {
    _logger.v(message, error: error, stackTrace: st);
  }
}