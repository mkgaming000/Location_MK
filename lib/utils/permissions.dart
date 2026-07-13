import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

/// Centralized runtime-permission helpers for Android.
class AppPermissions {
  AppPermissions._();

  /// All permissions the app needs to start live location sharing.
  static const List<Permission> sharingRequiredPermissions = [
    Permission.location,
    Permission.notification,
  ];

  /// Background location must be requested separately AFTER foreground
  /// location is granted (Android limitation).
  static const Permission backgroundLocationPermission =
      Permission.locationAlways;

  /// Requests foreground location + notification permissions.
  /// Returns `true` only if both are granted (notification may be soft-failed
  /// on Android 13+ if the user declines — see [requestSharingPermissions]).
  static Future<PermissionResult> requestForegroundPermissions() async {
    final results = await [
      Permission.location,
      Permission.notification,
    ].request();

    final locationStatus = results[Permission.location] ?? PermissionStatus.denied;
    final notifStatus =
        results[Permission.notification] ?? PermissionStatus.denied;

    final locationGranted = locationStatus.isGranted;
    final notifGranted = notifStatus.isGranted ||
        notifStatus == PermissionStatus.permanentlyDenied;

    if (locationGranted) {
      return PermissionResult(
        granted: true,
        message: notifGranted
            ? 'All required permissions granted.'
            : 'Location granted. Notifications are recommended but optional.',
        shouldOpenSettings: false,
      );
    }
    return PermissionResult(
      granted: false,
      message: locationStatus.isPermanentlyDenied
          ? 'Location permission permanently denied. Please enable it in Settings.'
          : 'Location permission is required to share your live location.',
      shouldOpenSettings: locationStatus.isPermanentlyDenied,
    );
  }

  /// Requests background location permission. Must be called after foreground
  /// location permission is granted.
  static Future<PermissionResult> requestBackgroundLocation() async {
    final status = await Permission.locationAlways.request();
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
          ? 'Background location permanently denied. Enable "Allow all the time" in Settings to share while the app is in the background.'
          : 'Background location is required for sharing when the app is minimized.',
      shouldOpenSettings: status.isPermanentlyDenied,
    );
  }

  /// Convenience method that runs the full sharing-permission flow:
  /// foreground → background. Returns the final result.
  static Future<PermissionResult> requestSharingPermissions() async {
    final foreground = await requestForegroundPermissions();
    if (!foreground.granted) {
      return foreground;
    }
    return requestBackgroundLocation();
  }

  /// Checks whether all sharing-related permissions are currently granted.
  static Future<bool> hasAllSharingPermissions() async {
    final location = await Permission.location.isGranted;
    final background = await Permission.locationAlways.isGranted;
    // Notification is recommended but not strictly required.
    return location && background;
  }

  /// Opens the system app-settings page so the user can manually grant
  /// permanently-denied permissions.
  static Future<void> openAppSettingsPage() async {
    await openAppSettings();
  }

  /// Returns a human-friendly label for a permission.
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

/// Helpers to render permission status as Material 3 chips.
extension PermissionStatusX on PermissionStatus {
  String get friendlyName {
    switch (this) {
      case PermissionStatus.granted:
        return 'Granted';
      case PermissionStatus.denied:
        return 'Denied';
      case PermissionStatus.permanentlyDenied:
        return 'Permanently Denied';
      case PermissionStatus.restricted:
        return 'Restricted';
      case PermissionStatus.limited:
        return 'Limited';
      case PermissionStatus.provisional:
        return 'Provisional';
    }
  }

  Color color(ColorScheme scheme) {
    switch (this) {
      case PermissionStatus.granted:
        return scheme.primary;
      case PermissionStatus.denied:
      case PermissionStatus.permanentlyDenied:
        return scheme.error;
      default:
        return scheme.tertiary;
    }
  }
}
