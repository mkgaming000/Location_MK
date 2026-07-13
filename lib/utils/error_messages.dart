import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';

/// Centralized error-handling helpers that translate platform exceptions into
/// specific, actionable, user-friendly messages.
///
/// NEVER returns "An unexpected error occurred" — every error type gets a
/// specific message that tells the user exactly what went wrong and what to do.
class ErrorMessages {
  ErrorMessages._();

  /// Returns a human-friendly message for a Firebase Auth error.
  static String forAuth(FirebaseAuthException e) {
    switch (e.code) {
      case 'network-request-failed':
        return 'Network error during authentication. Check your internet connection and try again.';
      case 'operation-not-allowed':
        return 'Anonymous sign-in is not enabled. Go to Firebase Console → Authentication → Sign-in method → Enable Anonymous.';
      case 'too-many-requests':
        return 'Too many login attempts. Wait a few minutes before trying again.';
      case 'user-token-expired':
        return 'Your session has expired. Restart the app to sign in again.';
      case 'user-disabled':
        return 'This account has been disabled.';
      case 'null-user':
        return 'No authenticated user found. Restart the app.';
      case 'configuration-not-found':
        return 'Firebase configuration not found. Check google-services.json is correct.';
      case 'api-not-available':
        return 'Firebase API not available. Check your google-services.json configuration.';
      default:
        return 'Authentication failed (${e.code}). ${e.message ?? "Restart the app and try again."}';
    }
  }

  /// Returns a human-friendly message for a Firebase Database error.
  static String forDatabase(FirebaseException e) {
    switch (e.code) {
      case 'permission-denied':
        return 'Firebase permission denied. Check your database security rules in Firebase Console.';
      case 'unavailable':
        return 'Firebase service is temporarily unavailable. Check your connection and try again.';
      case 'network-error':
        return 'Network error connecting to Firebase. Check your internet connection.';
      case 'data-stale':
        return 'Data is outdated. Refreshing...';
      case 'disconnected':
        return 'Disconnected from Firebase server. Reconnecting automatically...';
      case 'quota-exceeded':
        return 'Firebase quota exceeded. Try again later or upgrade your Firebase plan.';
      case 'max-retries':
        return 'Firebase operation timed out after multiple retries. Check your connection.';
      case 'user-code-error':
        return 'Data format error. The data in Firebase may be corrupted.';
      default:
        return 'Database error (${e.code}). ${e.message ?? "Try again."}';
    }
  }

  /// Returns a human-friendly message for a StateError (e.g. "not authenticated").
  static String forStateError(StateError e) {
    final msg = e.message.toLowerCase();
    if (msg.contains('not authenticated')) {
      return 'Authentication required. Restart the app to sign in.';
    }
    if (msg.contains('not initialized')) {
      return 'App not fully initialized. Restart the app.';
    }
    if (msg.contains('disposed')) {
      return 'Operation cancelled — the screen was closed.';
    }
    return 'Operation failed: ${e.message}';
  }

  /// Returns a human-friendly message for an ArgumentError.
  static String forArgumentError(ArgumentError e) {
    if (e.message.contains('Cannot pair a device with itself')) {
      return 'Cannot pair your own device. Enter the Device ID of a DIFFERENT phone.';
    }
    return 'Invalid input: ${e.message}';
  }

  /// Returns a human-friendly message for a TimeoutException.
  static String forTimeout(TimeoutException e) {
    return 'Operation timed out. Check your internet connection and try again.';
  }

  /// Returns a human-friendly message for a FormatException.
  static String forFormat(FormatException e) {
    return 'Invalid data format: ${e.message}. The Device ID may be malformed.';
  }

  /// Returns a human-friendly message for any error, with SPECIFIC messages
  /// for every known error type. Never returns a generic message.
  static String forAny(Object error) {
    if (error is FirebaseAuthException) return forAuth(error);
    if (error is FirebaseException) return forDatabase(error);
    if (error is StateError) return forStateError(error);
    if (error is ArgumentError) return forArgumentError(error);
    if (error is TimeoutException) return forTimeout(error);
    if (error is FormatException) return forFormat(error);
    // Last resort — include the actual error type and message so the user
    // can report it. Never hide the real error.
    return 'Error: ${error.toString()}';
  }
}
