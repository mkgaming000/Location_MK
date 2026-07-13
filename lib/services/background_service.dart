import 'dart:async';
import 'dart:ui';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../utils/constants.dart';
import '../utils/logger.dart';
import 'auth_service.dart';
import 'firebase_service.dart';
import 'location_service.dart';

/// Sets up and controls the Android foreground service that keeps location
/// sharing alive when the app is minimized, the screen is locked, or the
/// screen is off.
///
/// The foreground service shows a persistent notification:
///   Title: "Live Location Sharing Active"
///   Body:  "Your live location is being shared with paired devices."
///
/// Architecture note: the foreground service runs in a separate Dart
/// isolate. Firebase Auth state does NOT transfer across isolates. The
/// isolate signs in anonymously and gets its own UID. The DB rules allow
/// ANY authenticated user to write to live_locations (first writer owns
/// the node), so the isolate's writes succeed.
class BackgroundService {
  BackgroundService._();
  static final BackgroundService instance = BackgroundService._();

  final FlutterBackgroundService _service = FlutterBackgroundService();
  bool _configured = false;

  Future<void> initialize() async {
    if (_configured) return;
    _configured = true;
    await _configureNotifications();
    await _configureService();
  }

  Future<void> _configureNotifications() async {
    final notifications = FlutterLocalNotificationsPlugin();

    const channel = AndroidNotificationChannel(
      AppConstants.notificationChannelId,
      AppConstants.notificationChannelName,
      description: AppConstants.notificationChannelDescription,
      importance: Importance.low,
      showBadge: false,
      enableVibration: false,
      playSound: false,
    );

    await notifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);
  }

  Future<void> _configureService() async {
    await _service.configure(
      androidConfiguration: AndroidConfiguration(
        onStart: onStart,
        autoStart: false,
        isForegroundMode: true,
        notificationChannelId: AppConstants.notificationChannelId,
        initialNotificationTitle: AppConstants.notificationTitle,
        initialNotificationContent: AppConstants.notificationText,
        foregroundServiceNotificationId: AppConstants.notificationId,
      ),
      iosConfiguration: IosConfiguration(
        autoStart: false,
        onForeground: onStart,
        onBackground: onIosBackground,
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Public control API
  // ---------------------------------------------------------------------------

  Future<void> startSharing({
    required String deviceId,
    required String deviceName,
  }) async {
    if (!_configured) {
      await initialize();
    }
    if (!await _service.isRunning()) {
      await _service.startService();
    }
    _service.invoke('start-sharing', {
      'device_id': deviceId,
      'device_name': deviceName,
    });
    AppLogger.background('startSharing invoked for device: $deviceId');
  }

  Future<void> stopSharing({required String deviceId}) async {
    _service.invoke('stop-sharing', {'device_id': deviceId});
    await Future.delayed(const Duration(milliseconds: 500));
    if (await _service.isRunning()) {
      _service.invoke('stop-service');
    }
    AppLogger.background('stopSharing invoked for device: $deviceId');
  }

  Future<bool> isSharing() async {
    if (!_configured) return false;
    return _service.isRunning();
  }

  // ---------------------------------------------------------------------------
  // Service entry point (runs in a separate isolate)
  // ---------------------------------------------------------------------------

  @pragma('vm:entry-point')
  static Future<void> onStart(ServiceInstance service) async {
    DartPluginRegistrant.ensureInitialized();
    try {
      await Firebase.initializeApp();
    } catch (e) {
      // Firebase may already be initialized in this isolate.
      AppLogger.background('Firebase already initialized: $e');
    }

    service.on('stop-service').listen((event) {
      AppLogger.background('stop-service received');
      service.stopSelf();
    });

    String? activeDeviceId;
    String? activeDeviceName;
    StreamSubscription<LocationUpdate>? locationSub;
    StreamSubscription<List<ConnectivityResult>>? connectivitySub;
    Timer? heartbeatTimer;
    bool isSharing = false;

    final LocationService location = LocationService.instance;
    final FirebaseService firebase = FirebaseService.instance;
    final AuthService auth = AuthService.instance;

    // Authenticate in this isolate.
    try {
      await auth.initialize();
      AppLogger.background('Auth initialized in isolate, uid: ${auth.uid}');
    } catch (e, st) {
      AppLogger.error('BackgroundService auth init failed', e, st);
    }

    service.on('start-sharing').listen((event) async {
      if (event == null) return;
      final newId = event['device_id'] as String?;
      final newName = event['device_name'] as String?;
      if (newId == null) {
        AppLogger.background('start-sharing: device_id is null');
        return;
      }

      if (isSharing && activeDeviceId == newId) {
        AppLogger.background('start-sharing ignored — already sharing');
        return;
      }

      // Cancel any prior session.
      await locationSub?.cancel();
      await connectivitySub?.cancel();
      heartbeatTimer?.cancel();
      await location.stopMonitoring();

      activeDeviceId = newId;
      activeDeviceName = newName ?? 'Unknown Device';
      isSharing = true;

      AppLogger.background('Starting sharing for: $activeDeviceId');

      await _beginSharing(
        deviceId: activeDeviceId!,
        deviceName: activeDeviceName!,
        location: location,
        firebase: firebase,
        setLocationSub: (s) => locationSub = s,
        setConnectivitySub: (s) => connectivitySub = s,
        setHeartbeat: (t) => heartbeatTimer = t,
      );
    });

    service.on('stop-sharing').listen((event) async {
      final id = (event?['device_id'] as String?) ?? activeDeviceId;
      AppLogger.background('stop-sharing received for: $id');
      if (id != null) {
        try {
          await firebase.markOffline(id);
        } catch (e, st) {
          AppLogger.error('markOffline failed', e, st);
        }
      }
      isSharing = false;
      await locationSub?.cancel();
      locationSub = null;
      await connectivitySub?.cancel();
      connectivitySub = null;
      heartbeatTimer?.cancel();
      heartbeatTimer = null;
      await location.stopMonitoring();
    });
  }

  static Future<void> _beginSharing({
    required String deviceId,
    required String deviceName,
    required LocationService location,
    required FirebaseService firebase,
    required void Function(StreamSubscription<LocationUpdate>?) setLocationSub,
    required void Function(StreamSubscription<List<ConnectivityResult>>?)
        setConnectivitySub,
    required void Function(Timer) setHeartbeat,
  }) async {
    // Start GPS monitoring.
    try {
      await location.startMonitoring(
        interval: AppConstants.locationUpdateInterval,
        distanceFilterMeters: AppConstants.locationDistanceFilterMeters,
      );
      AppLogger.background('GPS monitoring started');
    } catch (e, st) {
      AppLogger.error('startMonitoring failed', e, st);
      return;
    }

    // Publish the initial location immediately.
    final initial = await location.getCurrentLocation();
    if (initial != null) {
      await _publish(
        firebase: firebase,
        deviceId: deviceId,
        deviceName: deviceName,
        location: initial,
        online: true,
      );
      AppLogger.background('Initial location published: ${initial.latitude}, ${initial.longitude}');
    }

    // Subscribe to location updates — every new position is published.
    setLocationSub(
      location.locationStream.listen((update) {
        _publish(
          firebase: firebase,
          deviceId: deviceId,
          deviceName: deviceName,
          location: update,
          online: true,
        );
      }),
    );

    // Network connectivity — republish on reconnect.
    setConnectivitySub(
      Connectivity().onConnectivityChanged.listen((results) {
        final online = results.any((r) => r != ConnectivityResult.none);
        if (!online) {
          AppLogger.network('lost — pausing publishes');
        } else {
          AppLogger.network('restored — republishing');
          final last = location.lastLocation ?? initial;
          if (last != null) {
            _publish(
              firebase: firebase,
              deviceId: deviceId,
              deviceName: deviceName,
              location: last,
              online: true,
            );
          }
        }
      }),
    );

    // Heartbeat — every 10 seconds, refresh online flag + timestamp.
    setHeartbeat(
      Timer.periodic(const Duration(seconds: 10), (_) async {
        final results = await Connectivity().checkConnectivity();
        final online = results.any((r) => r != ConnectivityResult.none);
        if (!online) return;
        final last = location.lastLocation ?? initial;
        if (last == null) return;
        _publish(
          firebase: firebase,
          deviceId: deviceId,
          deviceName: deviceName,
          location: last,
          online: true,
        );
      }),
    );
  }

  /// Publishes a location update with retry on transient failure.
  static Future<void> _publish({
    required FirebaseService firebase,
    required String deviceId,
    required String deviceName,
    required LocationUpdate location,
    required bool online,
  }) async {
    const maxAttempts = 3;
    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        await firebase.publishLocation(
          deviceId: deviceId,
          deviceName: deviceName,
          latitude: location.latitude,
          longitude: location.longitude,
          accuracy: location.accuracy,
          online: online,
        );
        return; // success
      } catch (e, st) {
        AppLogger.error('publish attempt $attempt failed', e, st);
        if (attempt < maxAttempts) {
          await Future.delayed(Duration(seconds: attempt));
        }
      }
    }
    AppLogger.error('publish failed after $maxAttempts attempts');
  }

  @pragma('vm:entry-point')
  static Future<bool> onIosBackground(ServiceInstance service) async {
    return false;
  }
}
