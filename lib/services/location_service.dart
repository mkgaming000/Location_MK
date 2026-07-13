import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';

import '../utils/logger.dart';

/// Wraps Android GPS access via [Geolocator] and network status via
/// [connectivity_plus].
///
/// On Android 14+, this service explicitly checks and requests location
/// permissions BEFORE starting the position stream. Without this, the
/// background service crashes with a SecurityException.
class LocationService {
  LocationService._();
  static final LocationService instance = LocationService._();

  StreamSubscription<Position>? _positionSub;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;
  Timer? _periodicTimer;
  bool _controllersClosed = false;

  final StreamController<LocationUpdate> _locationController =
      StreamController<LocationUpdate>.broadcast();
  Stream<LocationUpdate> get locationStream => _locationController.stream;

  final StreamController<bool> _internetController =
      StreamController<bool>.broadcast();
  Stream<bool> get internetStream => _internetController.stream;

  final StreamController<bool> _gpsController =
      StreamController<bool>.broadcast();
  Stream<bool> get gpsStream => _gpsController.stream;

  LocationUpdate? _lastLocation;
  LocationUpdate? get lastLocation => _lastLocation;

  bool _isMonitoring = false;
  bool get isMonitoring => _isMonitoring;

  // ---------------------------------------------------------------------------
  // GPS state checks
  // ---------------------------------------------------------------------------

  /// Returns `true` if the device GPS service is enabled.
  Future<bool> isGpsEnabled() async {
    try {
      return await Geolocator.isLocationServiceEnabled();
    } catch (e) {
      AppLogger.gps('isGpsEnabled', e, StackTrace.current);
      return false;
    }
  }

  /// Returns `true` if the device currently has an active internet
  /// connection (WiFi, mobile, or ethernet).
  Future<bool> hasInternet() async {
    try {
      final results = await Connectivity().checkConnectivity();
      return results.any((r) => r != ConnectivityResult.none);
    } catch (e) {
      AppLogger.error('hasInternet failed', e);
      return false;
    }
  }

  /// Ensures location permissions are granted before starting the GPS stream.
  /// This is CRITICAL for Android 14+ where the background service crashes
  /// if permissions are missing.
  ///
  /// Returns `true` if permissions are granted, `false` otherwise.
  /// Throws on unrecoverable errors.
  Future<bool> ensurePermissions() async {
    try {
      // Check if location service is enabled.
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        AppLogger.gps('ensurePermissions: location service disabled');
        return false;
      }

      // Check foreground location permission.
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.denied) {
        AppLogger.gps('ensurePermissions: foreground location denied');
        return false;
      }

      if (permission == LocationPermission.deniedForever) {
        AppLogger.gps('ensurePermissions: foreground location permanently denied');
        return false;
      }

      // Check background location permission (Android 10+).
      final bgStatus = await Permission.locationAlways.status;
      if (!bgStatus.isGranted) {
        AppLogger.gps('ensurePermissions: background location not granted');
        // Try to request it — on Android 11+ this shows the "Allow all the
        // time" dialog.
        final result = await Permission.locationAlways.request();
        if (!result.isGranted) {
          AppLogger.gps('ensurePermissions: background location request denied');
          return false;
        }
      }

      AppLogger.gps('ensurePermissions: all permissions granted');
      return true;
    } catch (e, st) {
      AppLogger.error('ensurePermissions failed', e, st);
      return false;
    }
  }

  // ---------------------------------------------------------------------------
  // Monitoring start / stop
  // ---------------------------------------------------------------------------

  /// Starts monitoring location and connectivity.
  /// Calls [ensurePermissions] first — if permissions are missing, throws
  /// a [StateError] with a descriptive message.
  Future<void> startMonitoring({
    Duration interval = const Duration(seconds: 4),
    double distanceFilterMeters = 5.0,
  }) async {
    if (_isMonitoring) return;
    if (_controllersClosed) {
      throw StateError('LocationService has been disposed.');
    }

    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!_gpsController.isClosed) _gpsController.add(serviceEnabled);
    if (!serviceEnabled) {
      throw StateError(
        'GPS service is disabled. Enable location in Settings.',
      );
    }

    // CRITICAL: Ensure permissions before starting the stream.
    // Without this, Android 14 crashes with SecurityException.
    final hasPermissions = await ensurePermissions();
    if (!hasPermissions) {
      throw StateError(
        'Location permissions not granted. Grant "Allow all the time" '
        'location permission in Settings.',
      );
    }

    _isMonitoring = true;
    _lastLocation = null;

    // 1) Connectivity stream.
    _connectivitySub = Connectivity().onConnectivityChanged.listen((results) {
      final online = results.any((r) => r != ConnectivityResult.none);
      if (!_internetController.isClosed) _internetController.add(online);
    });

    // 2) Position stream.
    final distanceFilterInt = distanceFilterMeters.round().clamp(0, 1000);
    _positionSub = Geolocator.getPositionStream(
      locationSettings: AndroidSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: distanceFilterInt,
        intervalDuration: interval,
        // CRITICAL for Android 14+: explicit foreground notification config
        // is handled by flutter_background_service, but we must set the
        // locationSettings to use the proper interval.
        foregroundNotificationConfig: null,
      ),
    ).listen(
      _onPosition,
      onError: (Object error) {
        AppLogger.gps('position stream error', error, StackTrace.current);
      },
    );

    // 3) Periodic heartbeat timer.
    _periodicTimer = Timer.periodic(interval, (_) {
      if (_lastLocation != null) {
        final refreshed = LocationUpdate(
          latitude: _lastLocation!.latitude,
          longitude: _lastLocation!.longitude,
          accuracy: _lastLocation!.accuracy,
          timestamp: DateTime.now(),
        );
        _lastLocation = refreshed;
        if (!_locationController.isClosed) _locationController.add(refreshed);
      }
    });

    // 4) Fetch an immediate initial position.
    try {
      final initial = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );
      _onPosition(initial);
    } catch (e, st) {
      AppLogger.gps('initial position fetch', e, st);
    }
  }

  void _onPosition(Position position) {
    final update = LocationUpdate(
      latitude: position.latitude,
      longitude: position.longitude,
      accuracy: position.accuracy,
      timestamp: position.timestamp,
    );
    _lastLocation = update;
    if (!_locationController.isClosed) _locationController.add(update);
  }

  /// Stops all monitoring streams and timers.
  Future<void> stopMonitoring() async {
    _isMonitoring = false;
    await _positionSub?.cancel();
    _positionSub = null;
    await _connectivitySub?.cancel();
    _connectivitySub = null;
    _periodicTimer?.cancel();
    _periodicTimer = null;
    _lastLocation = null;
  }

  /// One-shot fetch of the current location.
  Future<LocationUpdate?> getCurrentLocation() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return null;
    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );
      final update = LocationUpdate(
        latitude: position.latitude,
        longitude: position.longitude,
        accuracy: position.accuracy,
        timestamp: position.timestamp,
      );
      _lastLocation = update;
      return update;
    } catch (e, st) {
      AppLogger.gps('getCurrentLocation', e, st);
      return null;
    }
  }

  /// Permanently closes all stream controllers.
  Future<void> dispose() async {
    await stopMonitoring();
    await _locationController.close();
    await _internetController.close();
    await _gpsController.close();
    _controllersClosed = true;
  }
}

/// Immutable snapshot of a single GPS reading.
class LocationUpdate {
  const LocationUpdate({
    required this.latitude,
    required this.longitude,
    required this.accuracy,
    required this.timestamp,
  });

  final double latitude;
  final double longitude;
  final double accuracy;
  final DateTime timestamp;

  String get coordinatesText => '$latitude,$longitude';

  @override
  String toString() =>
      'LocationUpdate(lat: $latitude, lng: $longitude, acc: $accuracy, '
      'ts: $timestamp)';
}
