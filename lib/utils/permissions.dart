import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';

/// Centralized runtime-permission helpers for Android.
///
/// Handles Android 10–15 correctly:
/// - Android 10+: requests ACCESS_BACKGROUND_LOCATION separately
/// - Android 11+: shows "Allow all the time" dialog
/// - Android 12+: precise location toggle
/// - Android 13+: POST_NOTIFICATIONS for foreground service notification
/// - Android 14+: FOREGROUND_SERVICE_LOCATION must be granted before service start
/// - Android 15+: stricter foreground service enforcement
class AppPermissions {
  AppPermissions._();

  // ---------------------------------------------------------------------------
  // Individual permission requests
  // ---------------------------------------------------------------------------

  /// Requests foreground location permission (ACCESS_FINE_LOCATION +
  /// ACCESS_COARSE_LOCATION).
  static Future<PermissionResult> requestForegroundLocation() async {
    final status = await Permission.location.request();
    _logPermission('location', status);
    if (status.isGranted) {
      return const PermissionResult(
        granted: true,
        message: 'Location permission granted.',
        shouldOpenSettings: false,
      );
    }
    return PermissionResult(
      granted: false,
      message: status.isPermanentlyDenied
          ? 'Location permission permanently denied. Open Settings → Permissions → Location → "Allow only while using the app".'
          : 'Location permission is required to share your live location.',
      shouldOpenSettings: status.isPermanentlyDenied,
    );
  }

  /// Requests background location permission (ACCESS_BACKGROUND_LOCATION).
  /// Must be called AFTER foreground location is granted (Android requirement).
  static Future<PermissionResult> requestBackgroundLocation() async {
    final status = await Permission.locationAlways.request();
    _logPermission('locationAlways', status);
    if (status.isGranted) {
      return const PermissionResult(
        granted: true,
        message: 'Background location permission granted.',
        shouldOpenSettings: false,
      );
    }
    return PermissionResult(
      granted: false,
      message: status.isPermanentlyDenied
          ? 'Background location permanently denied. Open Settings → Permissions → Location → "Allow all the time". Without this, sharing stops when the app is minimized.'
          : 'Background location is required. Choose "Allow all the time" so sharing continues when the app is in the background.',
      shouldOpenSettings: status.isPermanentlyDenied,
    );
  }

  /// Requests notification permission (POST_NOTIFICATIONS, Android 13+).
  /// Notifications are REQUIRED for the foreground service on Android 14+.
  static Future<PermissionResult> requestNotifications() async {
    final status = await Permission.notification.request();
    _logPermission('notification', status);
    if (status.isGranted || status == PermissionStatus.provisional) {
      return const PermissionResult(
        granted: true,
        message: 'Notification permission granted.',
        shouldOpenSettings: false,
      );
    }
    return PermissionResult(
      granted: false,
      message: status.isPermanentlyDenied
          ? 'Notification permission permanently denied. The foreground service notification is REQUIRED on Android 13+. Open Settings → Permissions → Notifications → Allow.'
          : 'Notification permission is required for the foreground service notification on Android 13+.',
      shouldOpenSettings: status.isPermanentlyDenied,
    );
  }

  // ---------------------------------------------------------------------------
  // Combined permission flow
  // ---------------------------------------------------------------------------

  /// Runs the full sharing-permission flow in the correct order:
  /// 1. Foreground location
  /// 2. Background location (Android 10+)
  /// 3. Notifications (Android 13+)
  ///
  /// Returns the first failure, or success if all pass.
  /// Notifications are treated as recommended (not required) — the build will
  /// still proceed if denied, but the user is warned.
  static Future<PermissionResult> requestSharingPermissions() async {
    // 1. Foreground location (required)
    final foreground = await requestForegroundLocation();
    if (!foreground.granted) {
      return foreground;
    }

    // 2. Background location (required for sharing when app is minimized)
    final background = await requestBackgroundLocation();
    if (!background.granted) {
      return background;
    }

    // 3. Notifications (recommended — foreground service needs it on Android 13+)
    final notifications = await requestNotifications();
    if (!notifications.granted) {
      // Don't fail — just warn. The service can still run, but the
      // notification may not be visible.
      return PermissionResult(
        granted: true,
        message:
            'Permissions granted. Note: Notifications are recommended for the sharing indicator. '
            'You can enable them later in Settings.',
        shouldOpenSettings: false,
      );
    }

    return const PermissionResult(
      granted: true,
      message: 'All permissions granted.',
      shouldOpenSettings: false,
    );
  }

  // ---------------------------------------------------------------------------
  // Status checks
  // ---------------------------------------------------------------------------

  /// Checks whether all sharing-related permissions are currently granted.
  static Future<bool> hasAllSharingPermissions() async {
    final location = await Permission.location.isGranted;
    final background = await Permission.locationAlways.isGranted;
    return location && background;
  }

  /// Checks whether the foreground service can be started on the current
  /// Android version. On Android 14+, this requires FOREGROUND_SERVICE_LOCATION
  /// permission (declared in manifest, not runtime-granted) AND location
  /// permissions.
  static Future<bool> canStartForegroundService() async {
    final location = await Permission.location.isGranted;
    final background = await Permission.locationAlways.isGranted;
    // FOREGROUND_SERVICE and FOREGROUND_SERVICE_LOCATION are normal permissions
    // (granted at install time), so we just need the location perms.
    return location && background;
  }

  // ---------------------------------------------------------------------------
  // Settings
  // ---------------------------------------------------------------------------

  /// Opens the system app-settings page so the user can manually grant
  /// permanently-denied permissions.
  static Future<void> openAppSettingsPage() async {
    await openAppSettings();
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  static void _logPermission(String name, PermissionStatus status) {
    debugPrint('[Permission] $name = $status');
  }

  static String permissionLabel(Permission permission) {
    if (permission == Permission.location) return 'Location';
    if (permission == Permission.locationAlways) {
      return 'Background Location';
    }
    if (permission == Permission.notification) return 'Notifications';
    return permission.toString();
  }
}

/// Result of a permission request, with a human-friendly message ready for the
/// UI to display via a SnackBar.
class PermissionResult {
  const PermissionResult({
    required this.granted,
    required this.message,
    required this.shouldOpenSettings,
  });

  final bool granted;
  final String message;
  final bool shouldOpenSettings;
}
