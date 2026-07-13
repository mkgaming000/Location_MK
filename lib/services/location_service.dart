import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';

import '../utils/logger.dart';

/// Wraps Android GPS access via [Geolocator] and network status via
/// [connectivity_plus].
///
/// CRITICAL: This service runs in BOTH the main isolate AND the background
/// service isolate. When running in the background isolate, it CANNOT show
/// permission dialogs — permissions must be granted from the UI before the
/// background service starts.
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

  Future<bool> isGpsEnabled() async {
    try {
      return await Geolocator.isLocationServiceEnabled();
    } catch (e) {
      AppLogger.gps('isGpsEnabled', e, StackTrace.current);
      return false;
    }
  }

  Future<bool> hasInternet() async {
    try {
      final results = await Connectivity().checkConnectivity();
      return results.any((r) => r != ConnectivityResult.none);
    } catch (e) {
      AppLogger.error('hasInternet failed', e);
      return false;
    }
  }

  /// Checks (but does NOT request) location permissions.
  /// Safe to call from the background isolate — never shows dialogs.
  ///
  /// Returns `true` only if ALL required permissions are already granted:
  /// - Location service enabled
  /// - Foreground location granted
  /// - Background location granted (Android 10+)
  Future<bool> hasPermissions() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        AppLogger.gps('hasPermissions: location service disabled');
        return false;
      }

      final permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        AppLogger.gps('hasPermissions: foreground location not granted ($permission)');
        return false;
      }

      // Check background location (Android 10+).
      final bgStatus = await Permission.locationAlways.status;
      if (!bgStatus.isGranted) {
        AppLogger.gps('hasPermissions: background location not granted');
        return false;
      }

      AppLogger.gps('hasPermissions: all permissions granted');
      return true;
    } catch (e, st) {
      AppLogger.error('hasPermissions failed', e, st);
      return false;
    }
  }

  // ---------------------------------------------------------------------------
  // Monitoring start / stop
  // ---------------------------------------------------------------------------

  /// Starts monitoring location and connectivity.
  /// Does NOT request permissions — only checks them. If permissions are
  /// missing, throws a [StateError] with a descriptive message.
  /// Permission requests must happen in the UI isolate before calling this.
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

    // CHECK permissions (do NOT request — this runs in background isolate
    // on Android 14 where requesting permissions crashes the app).
    final hasPerms = await hasPermissions();
    if (!hasPerms) {
      throw StateError(
        'Location permissions not granted. Grant "Allow all the time" '
        'location permission in Settings before starting sharing.',
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
    //    Use LocationSettings (NOT AndroidSettings) to avoid foreground
    //    notification conflicts with flutter_background_service.
    //    The background service IS the foreground service — geolocator
    //    must NOT try to create its own.
    final distanceFilterInt = distanceFilterMeters.round().clamp(0, 1000);
    _positionSub = Geolocator.getPositionStream(
      locationSettings: LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: distanceFilterInt,
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
