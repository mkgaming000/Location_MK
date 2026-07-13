import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';

/// Centralized logging service that captures stack traces and categorizes
/// errors by severity. All logs are visible in `flutter logs` and Logcat.
class AppLogger {
  AppLogger._();

  static void info(String message) {
    debugPrint('[INFO] $message');
  }

  static void warning(String message) {
    debugPrint('[WARN] $message');
  }

  static void error(String message, [Object? errorObj, StackTrace? stackTrace]) {
    debugPrint('[ERROR] $message');
    if (errorObj != null) {
      debugPrint('  Error: $errorObj');
    }
    if (stackTrace != null) {
      debugPrint('  StackTrace: $stackTrace');
    }
    developer.log(
      message,
      error: errorObj,
      stackTrace: stackTrace,
      name: 'LocationMK',
    );
  }

  static void firebase(String operation, [Object? errorObj, StackTrace? stackTrace]) {
    if (errorObj != null) {
      error('Firebase[$operation] failed: $errorObj', errorObj, stackTrace);
    } else {
      info('Firebase[$operation] success.');
    }
  }

  static void gps(String operation, [Object? errorObj, StackTrace? stackTrace]) {
    if (errorObj != null) {
      error('GPS[$operation] failed: $errorObj', errorObj, stackTrace);
    } else {
      info('GPS[$operation] success.');
    }
  }

  static void permission(String permission, bool granted) {
    info('Permission[$permission] = ${granted ? "GRANTED" : "DENIED"}');
  }

  static void network(String status) {
    info('Network: $status');
  }

  static void background(String message) {
    info('[BackgroundService] $message');
  }
}
