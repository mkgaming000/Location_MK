import 'dart:async';
import 'dart:ui';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../utils/constants.dart';
import 'auth_service.dart';
import 'firebase_service.dart';
import 'location_service.dart';

/// Sets up and controls the Android foreground service that keeps location
/// sharing alive when the app is minimized, the screen is locked, or the
/// screen is off.
///
/// The service is configured with a persistent notification showing
/// "Live Location Sharing Active" plus two actions:
///   - **Stop Sharing** — stops the service immediately
///   - **Open App** — brings the app to the foreground
///
/// Architecture note: the foreground service runs in a separate Dart
/// isolate, which means it does NOT share auth state with the main isolate.
/// On isolate start we re-authenticate anonymously and register a fresh
/// `user_devices/{uid}/device_id` mapping so the DB security rules accept
/// the isolate's writes to `live_locations/{device_id}`.
class BackgroundService {
  BackgroundService._();
  static final BackgroundService instance = BackgroundService._();

  final FlutterBackgroundService _service = FlutterBackgroundService();

  bool _configured = false;

  // ---------------------------------------------------------------------------
  // Initialization (called once at app start)
  // ---------------------------------------------------------------------------

  /// Configures the foreground service. Does NOT start it — the service is
  /// only started when the user calls [startSharing]. Must be called once
  /// before [startSharing] — typically from `main.dart`.
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
        // Auto-start is OFF — we start the service only when the user
        // explicitly taps "Start Sharing".
        autoStart: false,
        isForegroundMode: true,
        notificationChannelId: AppConstants.notificationChannelId,
        initialNotificationTitle: AppConstants.notificationTitle,
        initialNotificationContent: AppConstants.notificationText,
        foregroundServiceNotificationId: AppConstants.notificationId,
        // The foreground service type is declared in AndroidManifest.xml
        // (`android:foregroundServiceType="location"`) so it is honored
        // by Android 14+ without relying on plugin API differences.
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

  /// Starts sharing location. The foreground service keeps running even when
  /// the app is minimized, the screen is locked, or the screen is off.
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
  }

  /// Stops sharing location and tears down the foreground service.
  Future<void> stopSharing({required String deviceId}) async {
    _service.invoke('stop-sharing', {'device_id': deviceId});
    // Give the service a moment to flush the offline marker, then stop it.
    await Future.delayed(const Duration(milliseconds: 500));
    if (await _service.isRunning()) {
      _service.invoke('stop-service');
    }
  }

  /// Returns whether the foreground service is currently running.
  Future<bool> isSharing() async {
    if (!_configured) return false;
    return _service.isRunning();
  }

  // ---------------------------------------------------------------------------
  // Service entry point (runs in a separate isolate)
  // ---------------------------------------------------------------------------

  @pragma('vm:entry-point')
  static Future<void> onStart(ServiceInstance service) async {
    // The background service runs in a separate Dart isolate. We must
    // initialize Flutter binding and Firebase explicitly here.
    DartPluginRegistrant.ensureInitialized();
    try {
      await Firebase.initializeApp();
    } catch (_) {
      // Firebase may already be initialized in this isolate; ignore.
    }

    // Listen for control events from the UI isolate. These are idempotent
    // — duplicate registrations are safe because the plugin deduplicates.
    service.on('stop-service').listen((event) {
      service.stopSelf();
    });

    // Active state held by this isolate.
    String? activeDeviceId;
    String? activeDeviceName;
    StreamSubscription<LocationUpdate>? locationSub;
    StreamSubscription<List<ConnectivityResult>>? connectivitySub;
    Timer? heartbeatTimer;
    bool isSharing = false;

    final LocationService location = LocationService.instance;
    final FirebaseService firebase = FirebaseService.instance;
    final AuthService auth = AuthService.instance;

    // Authenticate in this isolate (auth state doesn't transfer across
    // isolates — we re-sign-in anonymously here).
    try {
      await auth.initialize();
    } catch (e) {
      debugPrint('[BackgroundService] auth init failed: $e');
    }

    service.on('start-sharing').listen((event) async {
      if (event == null) return;
      final newId = event['device_id'] as String?;
      final newName = event['device_name'] as String?;
      if (newId == null) return;

      // If already sharing, ignore duplicate start-sharing events.
      if (isSharing && activeDeviceId == newId) {
        debugPrint('[BackgroundService] start-sharing ignored — already '
            'sharing this device.');
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

      // Register the isolate's UID → device_id mapping so DB rules accept
      // our writes to live_locations/{device_id}.
      try {
        await firebase.registerSelfDevice(
          deviceId: activeDeviceId!,
          deviceName: activeDeviceName!,
        );
      } catch (e) {
        debugPrint('[BackgroundService] registerSelfDevice failed: $e');
      }

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
      if (id != null) {
        try {
          await firebase.markOffline(id);
        } catch (e) {
          debugPrint('[BackgroundService] markOffline failed: $e');
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

  /// Begins live location monitoring + publishing. Called from the
  /// `start-sharing` event handler.
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
    } catch (e) {
      debugPrint('[BackgroundService] startMonitoring failed: $e');
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
    }

    // Subscribe to subsequent location updates — every new position is
    // published to Firebase, replacing the previous one.
    setLocationSub(
      location.locationStream.listen((update) {
        // Fire-and-forget publish — but catch errors so they don't propagate
        // to the stream subscription and kill it.
        _publish(
          firebase: firebase,
          deviceId: deviceId,
          deviceName: deviceName,
          location: update,
          online: true,
        );
      }),
    );

    // Network connectivity — pause publishing while offline, force-publish
    // on reconnect so the receiver sees a fresh heartbeat immediately.
    setConnectivitySub(
      Connectivity().onConnectivityChanged.listen((results) {
        final online = results.any((r) => r != ConnectivityResult.none);
        if (!online) {
          debugPrint('[BackgroundService] Network lost — pausing publishes.');
        } else {
          debugPrint('[BackgroundService] Network restored — republishing.');
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

    // Heartbeat — every 10 seconds, refresh the online flag and timestamp
    // even if the position has not changed (so the receiver sees a live
    // heartbeat).
    setHeartbeat(
      Timer.periodic(const Duration(seconds: 10), (_) async {
        final results = await Connectivity().checkConnectivity();
        // We are online if ANY of the results is a real connection.
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
      } catch (e) {
        debugPrint('[BackgroundService] publish attempt $attempt failed: $e');
        if (attempt < maxAttempts) {
          await Future.delayed(Duration(seconds: attempt));
        }
      }
    }
    debugPrint('[BackgroundService] publish failed after $maxAttempts '
        'attempts — giving up.');
  }

  @pragma('vm:entry-point')
  static Future<bool> onIosBackground(ServiceInstance service) async {
    // iOS does not support a true foreground service — return false so the
    // app gracefully degrades to in-app-only sharing.
    return false;
  }
}
