import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';

import '../models/device.dart';
import '../models/live_location.dart';
import '../utils/constants.dart';
import '../utils/logger.dart';
import 'auth_service.dart';

/// All Firebase Realtime Database reads/writes for live location sharing.
///
/// Database structure:
/// ```
/// live_locations/
///   {device_id}/  name, latitude, longitude, accuracy, timestamp, online, owner_uid
/// user_devices/
///   {uid}/  device_id, device_name, updated_at
/// pairings/
///   {my_device_id}/
///     {paired_device_id}/  name, owner_uid, added_at
/// ```
class FirebaseService {
  FirebaseService._();
  static final FirebaseService instance = FirebaseService._();

  final FirebaseDatabase _db = FirebaseDatabase.instance;
  final AuthService _auth = AuthService.instance;

  // ---------------------------------------------------------------------------
  // Self (this device) registration
  // ---------------------------------------------------------------------------

  Future<void> registerSelfDevice({
    required String deviceId,
    required String deviceName,
  }) async {
    final uid = _auth.uid;
    if (uid == null) {
      throw StateError('Cannot register device: not authenticated.');
    }
    try {
      await _db.ref('${AppConstants.userDevicesPath}/$uid').set({
        'device_id': deviceId,
        'device_name': deviceName,
        'updated_at': ServerValue.timestamp,
      });
      AppLogger.firebase('registerSelfDevice');
    } catch (e, st) {
      AppLogger.firebase('registerSelfDevice', e, st);
      rethrow;
    }
  }

  // ---------------------------------------------------------------------------
  // Live location publishing
  // ---------------------------------------------------------------------------

  Future<void> publishLocation({
    required String deviceId,
    required String deviceName,
    required double latitude,
    required double longitude,
    required double accuracy,
    required bool online,
  }) async {
    final uid = _auth.uid;
    if (uid == null) {
      throw StateError('Cannot publish location: not authenticated.');
    }
    final ref = _db.ref('${AppConstants.liveLocationsPath}/$deviceId');
    try {
      await ref.set({
        'name': deviceName,
        'latitude': latitude,
        'longitude': longitude,
        'accuracy': accuracy,
        'timestamp': ServerValue.timestamp,
        'online': online,
        'owner_uid': uid,
      });
    } catch (e, st) {
      AppLogger.firebase('publishLocation', e, st);
      rethrow;
    }
  }

  Future<void> markOffline(String deviceId) async {
    final uid = _auth.uid;
    final ref = _db.ref('${AppConstants.liveLocationsPath}/$deviceId');
    try {
      await ref.update({
        'online': false,
        'timestamp': ServerValue.timestamp,
        if (uid != null) 'owner_uid': uid,
      });
      AppLogger.firebase('markOffline');
    } catch (e, st) {
      AppLogger.firebase('markOffline', e, st);
      rethrow;
    }
  }

  Future<void> deleteLocation(String deviceId) async {
    try {
      await _db.ref('${AppConstants.liveLocationsPath}/$deviceId').remove();
      AppLogger.firebase('deleteLocation');
    } catch (e, st) {
      AppLogger.firebase('deleteLocation', e, st);
      rethrow;
    }
  }

  // ---------------------------------------------------------------------------
  // Live location subscription (used by the Receiver screen)
  // ---------------------------------------------------------------------------

  /// Returns a stream of [LiveLocation] updates for [deviceId].
  /// Emits `null` when the device has no published location.
  /// Errors are PROPAGATED to the listener (not swallowed).
  Stream<LiveLocation?> watchLocation(String deviceId) {
    return _db
        .ref('${AppConstants.liveLocationsPath}/$deviceId')
        .onValue
        .map((event) {
      final snapshot = event.snapshot;
      if (!snapshot.exists || snapshot.value == null) return null;
      final value = snapshot.value;
      if (value is! Map) return null;
      return LiveLocation.fromMap(value, deviceId);
    });
  }

  // ---------------------------------------------------------------------------
  // Pairings
  // ---------------------------------------------------------------------------

  /// Checks if a device exists in the `user_devices` mapping by scanning
  /// for any uid that has this device_id registered.
  /// Returns the owner_uid if found, or null if the device doesn't exist.
  Future<String?> checkDeviceExists(String deviceId) async {
    try {
      // Try to read from live_locations — if the device has ever shared,
      // there will be an entry with owner_uid.
      final locSnap = await _db
          .ref('${AppConstants.liveLocationsPath}/$deviceId/owner_uid')
          .get();
      if (locSnap.exists && locSnap.value is String) {
        return locSnap.value as String;
      }
      // If no live_locations entry, check if anyone has this device paired.
      // This is a best-effort check — we can't enumerate all user_devices
      // due to security rules, but we can check pairings.
      return null;
    } catch (e, st) {
      AppLogger.firebase('checkDeviceExists', e, st);
      return null;
    }
  }

  /// Checks if a device is already paired.
  Future<bool> isAlreadyPaired(String myDeviceId, String theirDeviceId) async {
    try {
      final snap = await _db
          .ref('${AppConstants.pairingsPath}/$myDeviceId/$theirDeviceId')
          .get();
      return snap.exists;
    } catch (e, st) {
      AppLogger.firebase('isAlreadyPaired', e, st);
      return false;
    }
  }

  /// Adds a paired device. Performs validation:
  /// - Checks auth state
  /// - Prevents self-pairing
  /// - Prevents duplicate pairing
  ///
  /// Note: We do NOT read live_locations first — pairing is independent of
  /// whether the device has shared its location. The name is either
  /// user-supplied or a default. Once the device starts sharing, the
  /// receiver screen will display the actual name from live_locations.
  ///
  /// Throws specific exceptions with meaningful messages.
  Future<Device> addPairedDevice({
    required String myDeviceId,
    required String theirDeviceId,
    String theirDeviceName = 'Paired Device',
  }) async {
    final uid = _auth.uid;
    if (uid == null) {
      throw StateError('Authentication failed. Restart the app to sign in.');
    }
    if (myDeviceId == theirDeviceId) {
      throw ArgumentError('Cannot pair a device with itself.');
    }

    // Check for duplicate pairing
    final alreadyPaired = await isAlreadyPaired(myDeviceId, theirDeviceId);
    if (alreadyPaired) {
      throw StateError('Already paired. This device is in your paired list.');
    }

    final now = DateTime.now().millisecondsSinceEpoch;

    final device = Device(
      id: theirDeviceId,
      name: theirDeviceName,
      ownerUid: '',
      addedAt: DateTime.fromMillisecondsSinceEpoch(now),
    );

    try {
      await _db
          .ref('${AppConstants.pairingsPath}/$myDeviceId/$theirDeviceId')
          .set({
        'name': theirDeviceName,
        'owner_uid': '',
        'added_at': now,
      });
      AppLogger.firebase('addPairedDevice');
    } catch (e, st) {
      AppLogger.firebase('addPairedDevice', e, st);
      rethrow;
    }

    return device;
  }

  Future<void> removePairedDevice({
    required String myDeviceId,
    required String theirDeviceId,
  }) async {
    try {
      await _db
          .ref('${AppConstants.pairingsPath}/$myDeviceId/$theirDeviceId')
          .remove();
      AppLogger.firebase('removePairedDevice');
    } catch (e, st) {
      AppLogger.firebase('removePairedDevice', e, st);
      rethrow;
    }
  }

  /// Returns a stream of this device's paired devices list.
  /// Errors are PROPAGATED to the listener (not swallowed).
  Stream<List<Device>> watchPairedDevices(String myDeviceId) {
    return _db
        .ref('${AppConstants.pairingsPath}/$myDeviceId')
        .onValue
        .map((event) {
      final snapshot = event.snapshot;
      if (!snapshot.exists || snapshot.value == null) return <Device>[];
      final value = snapshot.value;
      if (value is! Map) return <Device>[];
      final devices = <Device>[];
      value.forEach((key, val) {
        if (val is Map) {
          devices.add(Device.fromMap(val, key.toString()));
        }
      });
      devices.sort((a, b) => a.name.compareTo(b.name));
      return devices;
    });
  }

  Future<List<Device>> getPairedDevices(String myDeviceId) async {
    try {
      final snapshot =
          await _db.ref('${AppConstants.pairingsPath}/$myDeviceId').get();
      if (!snapshot.exists || snapshot.value == null) return <Device>[];
      final value = snapshot.value;
      if (value is! Map) return <Device>[];
      final devices = <Device>[];
      value.forEach((key, val) {
        if (val is Map) {
          devices.add(Device.fromMap(val, key.toString()));
        }
      });
      devices.sort((a, b) => a.name.compareTo(b.name));
      return devices;
    } catch (e, st) {
      AppLogger.firebase('getPairedDevices', e, st);
      rethrow;
    }
  }

  // ---------------------------------------------------------------------------
  // Network availability / reconnection
  // ---------------------------------------------------------------------------

  Future<void> reconnect() async {
    try {
      await _db.goOnline();
      final user = FirebaseAuth.instance.currentUser;
      await user?.getIdToken(true);
      AppLogger.firebase('reconnect');
    } catch (e, st) {
      AppLogger.firebase('reconnect', e, st);
    }
  }

  Future<void> goOffline() async {
    try {
      await _db.goOffline();
    } catch (e) {
      AppLogger.error('goOffline failed', e);
    }
  }
}
