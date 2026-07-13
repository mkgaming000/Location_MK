import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';

/// Centralized logging service that captures stack traces and categorizes
/// errors by severity. All logs are visible in `flutter logs` and Logcat.
///
/// Usage:
///   AppLogger.info('message');
///   AppLogger.warning('message');
///   AppLogger.error('message', error, stackTrace);
///   AppLogger.firebase('operation', error);
///   AppLogger.gps('operation', error);
///   AppLogger.permission('permission', granted);
///   AppLogger.network('online');
class AppLogger {
  AppLogger._();

  static void info(String message) {
    debugPrint('[INFO] $message');
  }

  static void warning(String message) {
    debugPrint('[WARN] $message');
  }

  static void error(String message, [Object? error, StackTrace? stackTrace]) {
    debugPrint('[ERROR] $message');
    if (error != null) {
      debugPrint('  Error: $error');
    }
    if (stackTrace != null) {
      debugPrint('  StackTrace: $stackTrace');
    }
    // Also log to developer for capture in observatory
    developer.log(
      message,
      error: error,
      stackTrace: stackTrace,
      name: 'LocationMK',
    );
  }

  static void firebase(String operation, [Object? error, StackTrace? stackTrace]) {
    if (error != null) {
      error_('Firebase[$operation] failed: $error', error, stackTrace);
    } else {
      info('Firebase[$operation] success.');
    }
  }

  static void gps(String operation, [Object? error, StackTrace? stackTrace]) {
    if (error != null) {
      error_('GPS[$operation] failed: $error', error, stackTrace);
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

  /// Internal helper to avoid name clash with the public [error] method.
  static void error_(String message, Object? error, StackTrace? stackTrace) {
    error(message, error, stackTrace);
  }
}
