import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

/// Centralized error-handling helpers that translate platform exceptions into
/// user-friendly messages.
class ErrorMessages {
  ErrorMessages._();

  /// Returns a human-friendly message for a Firebase Auth error.
  static String forAuth(FirebaseAuthException e) {
    switch (e.code) {
      case 'network-request-failed':
        return 'Network error. Please check your internet connection.';
      case 'operation-not-allowed':
        return 'Anonymous sign-in is not enabled in Firebase Console.';
      case 'too-many-requests':
        return 'Too many requests. Please try again in a few minutes.';
      case 'user-token-expired':
        return 'Your session has expired. Please restart the app.';
      case 'null-user':
        return 'No authenticated user. Please restart the app.';
      default:
        return 'Authentication error: ${e.message ?? e.code}';
    }
  }

  /// Returns a human-friendly message for a Firebase Database error.
  static String forDatabase(FirebaseException e) {
    switch (e.code) {
      case 'permission-denied':
        return 'Permission denied. You are not authorized to access this data.';
      case 'unavailable':
        return 'Service is temporarily unavailable. Please check your '
            'connection and try again.';
      case 'network-error':
        return 'Network error. Please check your internet connection.';
      case 'data-stale':
        return 'The data is outdated. Please refresh.';
      case 'disconnected':
        return 'Disconnected from server. Reconnecting...';
      default:
        return 'Database error: ${e.message ?? e.code}';
    }
  }

  /// Returns a human-friendly message for any error, falling back to a
  /// generic message for non-Firebase errors.
  static String forAny(Object error) {
    if (error is FirebaseAuthException) return forAuth(error);
    if (error is FirebaseException) return forDatabase(error);
    debugPrint('[ErrorMessages] Unhandled error: $error');
    return 'An unexpected error occurred. Please try again.';
  }
}
