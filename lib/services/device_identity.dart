import 'dart:convert';
import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../utils/constants.dart';

/// Generates, persists, and retrieves the unique Device ID for this
/// installation.
///
/// The Device ID is a UUID v4 generated on first launch and stored in
/// `SharedPreferences`. It survives app upgrades and is the primary key used
/// in the `live_locations/{device_id}` path.
class DeviceIdentity {
  DeviceIdentity._();
  static final DeviceIdentity instance = DeviceIdentity._();

  String? _deviceId;
  String? _deviceName;

  String? get deviceId => _deviceId;
  String? get deviceName => _deviceName;

  /// Loads the device ID and name from local storage. Generates a new ID if
  /// none exists yet.
  Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    var id = prefs.getString(AppConstants.prefDeviceId);
    if (id == null) {
      id = const Uuid().v4();
      await prefs.setString(AppConstants.prefDeviceId, id);
    }
    var name = prefs.getString(AppConstants.prefDeviceName);
    if (name == null) {
      name = _generateDefaultName();
      await prefs.setString(AppConstants.prefDeviceName, name);
    }
    _deviceId = id;
    _deviceName = name;
  }

  /// Updates the user-facing device name.
  Future<void> setDeviceName(String name) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(AppConstants.prefDeviceName, name);
    _deviceName = name;
  }

  /// Generates a random default device name from the suggestion list plus a
  /// 4-digit suffix to avoid collisions.
  String _generateDefaultName() {
    final rng = Random();
    final base = AppConstants.defaultDeviceNames[
        rng.nextInt(AppConstants.defaultDeviceNames.length)];
    final suffix = rng.nextInt(9000) + 1000;
    return '$base $suffix';
  }

  /// Generates a QR payload for pairing. Format: JSON with device_id and name.
  String get pairPayload {
    final map = {
      'device_id': _deviceId,
      'device_name': _deviceName,
      'app': AppConstants.appName,
    };
    return jsonEncode(map);
  }

  /// Parses a QR payload back into (device_id, device_name).
  static ({String deviceId, String deviceName})? parsePairPayload(String raw) {
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      final id = map['device_id'] as String?;
      final name = map['device_name'] as String?;
      if (id == null || name == null) return null;
      return (deviceId: id, deviceName: name);
    } catch (_) {
      // If the payload is a plain device ID string (no JSON), accept it.
      final trimmed = raw.trim();
      if (trimmed.isNotEmpty && trimmed.length <= 64) {
        return (deviceId: trimmed, deviceName: 'Paired Device');
      }
      return null;
    }
  }
}
