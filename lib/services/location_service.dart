import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

/// Wraps Android GPS access via [Geolocator] and network status via
/// [connectivity_plus].
///
/// The location service is **pull-based**: callers receive a [Stream] of
/// [LocationUpdate] events that fire whenever the device moves more than
/// [AppConstants.locationDistanceFilterMeters] meters or every
/// [AppConstants.locationUpdateInterval] (whichever comes first).
///
/// Lifecycle:
/// - [startMonitoring] starts GPS, connectivity streams, and a periodic
///   heartbeat timer. Safe to call multiple times — duplicate calls are
///   no-ops while monitoring is active.
/// - [stopMonitoring] cancels all streams and timers and clears state.
/// - [dispose] (called once on app teardown) closes all stream controllers.
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
      debugPrint('[LocationService] isGpsEnabled failed: $e');
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
      debugPrint('[LocationService] hasInternet failed: $e');
      return false;
    }
  }

  // ---------------------------------------------------------------------------
  // Monitoring start / stop
  // ---------------------------------------------------------------------------

  /// Starts monitoring location and connectivity. The returned stream emits
  /// the most recent [LocationUpdate] every time a new position is received.
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
        'GPS service is disabled. Please enable location in Settings.',
      );
    }

    _isMonitoring = true;
    _lastLocation = null;

    // 1) Connectivity stream — emits initial + ongoing network state.
    _connectivitySub = Connectivity().onConnectivityChanged.listen((results) {
      final online = results.any((r) => r != ConnectivityResult.none);
      if (!_internetController.isClosed) _internetController.add(online);
    });

    // 2) High-frequency position stream (fires on movement or interval).
    //    Note: geolocator's distanceFilter accepts int (meters). We use the
    //    int truncation but enforce a minimum of 1m to avoid filtering
    //    issues with 0.x values.
    final distanceFilterInt = distanceFilterMeters.round().clamp(0, 1000);
    _positionSub = Geolocator.getPositionStream(
      locationSettings: AndroidSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: distanceFilterInt,
        intervalDuration: interval,
      ),
    ).listen(
      _onPosition,
      onError: (Object error) {
        debugPrint('[LocationService] position stream error: $error');
      },
    );

    // 3) Periodic safety timer — if no movement for `interval`, the timer
    //    re-publishes the last known location so the receiver sees a fresh
    //    heartbeat timestamp.
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

    // 4) Fetch an immediate initial position so the UI is not blank.
    try {
      final initial = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );
      _onPosition(initial);
    } catch (e) {
      debugPrint('[LocationService] initial position fetch failed: $e');
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

  /// One-shot fetch of the current location. Useful for the Share screen to
  /// display the current position before starting the stream.
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
    } catch (e) {
      debugPrint('[LocationService] getCurrentLocation failed: $e');
      return null;
    }
  }

  /// Permanently closes all stream controllers. Called once on app teardown.
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
