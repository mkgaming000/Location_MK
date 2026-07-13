/// Application-wide constants for Live Location Share.
class AppConstants {
  AppConstants._();

  // App metadata
  static const String appName = 'Live Location Share';
  static const String appVersion = '1.0.0';

  // Firebase Realtime Database root paths
  static const String liveLocationsPath = 'live_locations';
  static const String userDevicesPath = 'user_devices';
  static const String pairingsPath = 'pairings';

  // SharedPreferences keys
  static const String prefDeviceId = 'device_id';
  static const String prefDeviceName = 'device_name';
  static const String prefThemeMode = 'theme_mode';

  // Location update configuration
  static const Duration locationUpdateInterval = Duration(seconds: 4);
  static const double locationDistanceFilterMeters = 5.0;

  // Online/offline detection — a location is considered stale if its
  // timestamp is older than this duration.
  static const Duration onlineTimeout = Duration(seconds: 15);

  // Foreground service configuration
  static const int notificationId = 20240613;
  static const String notificationChannelId = 'live_location_share_channel';
  static const String notificationChannelName = 'Live Location Sharing';
  static const String notificationChannelDescription =
      'Shows persistent notification while location sharing is active.';
  static const String notificationTitle = 'Live Location Sharing Active';
  static const String notificationText =
      'Your live location is being shared with paired devices.';

  // Default device name suggestions
  static const List<String> defaultDeviceNames = [
    'Manoj Phone',
    'Office Phone',
    'Dad Phone',
    'Friend Phone',
    'My Phone',
    'Work Phone',
  ];
}
