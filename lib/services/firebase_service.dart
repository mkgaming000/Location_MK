import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';

import '../models/device.dart';
import '../models/live_location.dart';
import '../utils/constants.dart';
import 'auth_service.dart';

/// All Firebase Realtime Database reads/writes for live location sharing.
///
/// The database structure:
/// ```
/// live_locations/
///   {device_id}/
///     name, latitude, longitude, accuracy, timestamp, online, owner_uid
/// user_devices/
///   {uid}/
///     device_id, device_name, updated_at
/// pairings/
///   {my_device_id}/
///     {paired_device_id}/ name, owner_uid, added_at
/// ```
///
/// Security (enforced by database.rules.json):
/// - A device's live location can ONLY be read by its owner OR by devices that
///   have an entry under `pairings/{their_device_id}/{my_device_id}` (i.e.
///   the target device has explicitly paired with the reader).
/// - Only the authenticated owner (matching `user_devices/{uid}/device_id`)
///   can write to `live_locations/{device_id}`.
/// - Pairings can only be written by the owner of the parent device_id.
class FirebaseService {
  FirebaseService._();
  static final FirebaseService instance = FirebaseService._();

  final FirebaseDatabase _db = FirebaseDatabase.instance;
  final AuthService _auth = AuthService.instance;

  // ---------------------------------------------------------------------------
  // Self (this device) registration
  // ---------------------------------------------------------------------------

  /// Registers the current device in `user_devices/{uid}` so DB security
  /// rules can resolve `auth.uid → device_id`. This is the keystone of the
  /// pairing enforcement: every read/write of `live_locations` and
  /// `pairings` depends on this mapping.
  Future<void> registerSelfDevice({
    required String deviceId,
    required String deviceName,
  }) async {
    final uid = _auth.uid;
    if (uid == null) {
      throw StateError('Cannot register device: not authenticated.');
    }
    await _db.ref('${AppConstants.userDevicesPath}/$uid').set({
      'device_id': deviceId,
      'device_name': deviceName,
      'updated_at': ServerValue.timestamp,
    });
  }

  /// Returns the device_id registered for the given uid, or null if not
  /// registered. Used for cross-device lookups.
  Future<String?> getDeviceIdForUid(String uid) async {
    final snap =
        await _db.ref('${AppConstants.userDevicesPath}/$uid/device_id').get();
    if (!snap.exists) return null;
    return snap.value as String?;
  }

  // ---------------------------------------------------------------------------
  // Live location publishing (used by the Share screen / background service)
  // ---------------------------------------------------------------------------

  /// Publishes (overwrites) the live location for [deviceId].
  /// This is the ONLY write path for `live_locations/{deviceId}`.
  /// DB rules ensure only the owner can write here.
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
    await ref.set({
      'name': deviceName,
      'latitude': latitude,
      'longitude': longitude,
      'accuracy': accuracy,
      'timestamp': ServerValue.timestamp,
      'online': online,
      'owner_uid': uid,
    });
  }

  /// Marks [deviceId] as offline without removing the record.
  /// Used when the user stops sharing.
  Future<void> markOffline(String deviceId) async {
    final uid = _auth.uid;
    final ref = _db.ref('${AppConstants.liveLocationsPath}/$deviceId');
    await ref.update({
      'online': false,
      'timestamp': ServerValue.timestamp,
      if (uid != null) 'owner_uid': uid,
    });
  }

  /// Removes the live location entry entirely (used when the user explicitly
  /// stops sharing AND wants their data cleared).
  Future<void> deleteLocation(String deviceId) async {
    await _db.ref('${AppConstants.liveLocationsPath}/$deviceId').remove();
  }

  // ---------------------------------------------------------------------------
  // Live location subscription (used by the Receiver screen)
  // ---------------------------------------------------------------------------

  /// Returns a stream of [LiveLocation] updates for [deviceId].
  /// Emits `null` when the device has no published location (e.g. it is
  /// offline and the record was deleted).
  ///
  /// DB rules will reject the read if the current user has not been paired
  /// by [deviceId]'s owner — i.e. `pairings/{deviceId}/{my_device_id}` does
  /// not exist. In that case the stream emits `null` and logs an error.
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
    }).handleError((error) {
      debugPrint('[FirebaseService] watchLocation($deviceId) error: $error');
    });
  }

  // ---------------------------------------------------------------------------
  // Pairings
  // ---------------------------------------------------------------------------

  /// Adds a paired device under `pairings/{my_device_id}/{their_device_id}`.
  ///
  /// IMPORTANT: This is a ONE-DIRECTIONAL pairing — it allows the CURRENT
  /// device to read THEIR live location. For them to read ours, they must
  /// independently pair with us on their device. This enforces the spec's
  /// "Only paired devices can view each other's location" rule on a
  /// per-direction basis (mutual visibility requires both sides to pair).
  ///
  /// Returns the resolved [Device] (looks up the device's name from
  /// `live_locations` if available).
  Future<Device> addPairedDevice({
    required String myDeviceId,
    required String theirDeviceId,
    String theirDeviceName = 'Paired Device',
  }) async {
    final uid = _auth.uid;
    if (uid == null) {
      throw StateError('Cannot pair device: not authenticated.');
    }
    if (myDeviceId == theirDeviceId) {
      throw ArgumentError('Cannot pair a device with itself.');
    }
    final now = DateTime.now().millisecondsSinceEpoch;

    // Try to fetch the actual name from the live_locations node first.
    // DB rules: this read will succeed only if THEIR device has already
    // paired with US — otherwise we fall back to the user-supplied name.
    String resolvedName = theirDeviceName;
    String resolvedOwnerUid = '';
    try {
      final snapshot = await _db
          .ref('${AppConstants.liveLocationsPath}/$theirDeviceId')
          .get();
      if (snapshot.exists && snapshot.value is Map) {
        final map = snapshot.value;
        resolvedName = (map['name'] as String?) ?? theirDeviceName;
        resolvedOwnerUid = (map['owner_uid'] as String?) ?? '';
      }
    } catch (e) {
      // Read denied — they haven't paired with us yet, which is fine.
      debugPrint('[FirebaseService] pair lookup denied (expected): $e');
    }

    final device = Device(
      id: theirDeviceId,
      name: resolvedName,
      ownerUid: resolvedOwnerUid,
      addedAt: DateTime.fromMillisecondsSinceEpoch(now),
    );

    await _db
        .ref('${AppConstants.pairingsPath}/$myDeviceId/$theirDeviceId')
        .set({
      'name': resolvedName,
      'owner_uid': resolvedOwnerUid,
      'added_at': now,
    });

    return device;
  }

  /// Removes a paired device from `pairings/{my_device_id}/{their_id}`.
  Future<void> removePairedDevice({
    required String myDeviceId,
    required String theirDeviceId,
  }) async {
    await _db
        .ref('${AppConstants.pairingsPath}/$myDeviceId/$theirDeviceId')
        .remove();
  }

  /// Returns a stream of this device's paired devices list.
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
    }).handleError((error) {
      debugPrint('[FirebaseService] watchPairedDevices error: $error');
    });
  }

  /// One-shot fetch of all paired devices.
  Future<List<Device>> getPairedDevices(String myDeviceId) async {
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
  }

  // ---------------------------------------------------------------------------
  // Network availability / reconnection
  // ---------------------------------------------------------------------------

  /// Reconnects the Firebase Realtime Database client after a network
  /// outage. FirebaseDatabase auto-reconnects, but this method forces a
  /// reconnect and refreshes the auth token.
  Future<void> reconnect() async {
    try {
      await _db.goOnline();
      final user = FirebaseAuth.instance.currentUser;
      await user?.getIdToken(forceRefresh: true);
    } catch (e) {
      debugPrint('Firebase reconnect failed: $e');
    }
  }

  /// Sets the database connection offline (used when network is lost to
  /// avoid hanging writes).
  Future<void> goOffline() async {
    try {
      await _db.goOffline();
    } catch (e) {
      debugPrint('Firebase goOffline failed: $e');
    }
  }
}
