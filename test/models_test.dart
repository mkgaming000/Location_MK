import 'package:flutter_test/flutter_test.dart';

import 'package:live_location_share/models/device.dart';
import 'package:live_location_share/models/live_location.dart';
import 'package:live_location_share/utils/constants.dart';

void main() {
  group('Device', () {
    test('fromMap parses correctly with all fields', () {
      final device = Device.fromMap({
        'name': 'Manoj Phone',
        'owner_uid': 'uid-123',
        'added_at': 1700000000000,
      }, 'device-abc');

      expect(device.id, 'device-abc');
      expect(device.name, 'Manoj Phone');
      expect(device.ownerUid, 'uid-123');
      expect(device.addedAt?.millisecondsSinceEpoch, 1700000000000);
    });

    test('fromMap handles missing fields gracefully', () {
      final device = Device.fromMap({}, 'device-x');

      expect(device.id, 'device-x');
      expect(device.name, 'Unknown Device');
      expect(device.ownerUid, '');
      expect(device.addedAt, isNull);
    });

    test('toMap roundtrips', () {
      final original = Device(
        id: 'dev-x',
        name: 'Office Phone',
        ownerUid: 'uid-9',
        addedAt: DateTime.fromMillisecondsSinceEpoch(1700000000000),
      );
      final map = original.toMap();
      expect(map['name'], 'Office Phone');
      expect(map['owner_uid'], 'uid-9');
      expect(map['added_at'], 1700000000000);
    });

    test('copyWith creates a new instance with updated fields', () {
      final original = Device(
        id: 'dev-1',
        name: 'Old Name',
        ownerUid: 'uid-1',
      );
      final updated = original.copyWith(name: 'New Name');
      expect(updated.name, 'New Name');
      expect(updated.id, 'dev-1');
      expect(updated.ownerUid, 'uid-1');
    });

    test('equality is based on id only', () {
      final a = Device(id: 'dev-1', name: 'A', ownerUid: 'uid-1');
      final b = Device(id: 'dev-1', name: 'B', ownerUid: 'uid-2');
      expect(a == b, isTrue);
      expect(a.hashCode, b.hashCode);
    });
  });

  group('LiveLocation', () {
    test('coordinatesText uses comma without spaces', () {
      final loc = LiveLocation(
        deviceId: 'dev-1',
        name: 'Test',
        latitude: 13.082680,
        longitude: 80.270721,
        accuracy: 5.0,
        timestamp: DateTime.now(),
        online: true,
        ownerUid: 'uid-1',
      );
      // Spec: format must be "latitude,longitude" e.g. 13.082680,80.270721
      expect(loc.coordinatesText, contains(','));
      expect(loc.coordinatesText.contains(' '), isFalse);
    });

    test('isStale is true for timestamps older than 15 seconds', () {
      final loc = LiveLocation(
        deviceId: 'dev-1',
        name: 'Test',
        latitude: 0,
        longitude: 0,
        accuracy: 0,
        timestamp: DateTime.now().subtract(const Duration(minutes: 5)),
        online: true,
        ownerUid: '',
      );
      expect(loc.isStale, isTrue);
    });

    test('isStale is false for recent timestamps', () {
      final loc = LiveLocation(
        deviceId: 'dev-1',
        name: 'Test',
        latitude: 0,
        longitude: 0,
        accuracy: 0,
        timestamp: DateTime.now(),
        online: true,
        ownerUid: '',
      );
      expect(loc.isStale, isFalse);
    });

    test('fromMap parses all fields correctly', () {
      final loc = LiveLocation.fromMap({
        'name': 'Test Device',
        'latitude': 13.082680,
        'longitude': 80.270721,
        'accuracy': 5.5,
        'timestamp': 1700000000000,
        'online': true,
        'owner_uid': 'uid-xyz',
      }, 'dev-1');

      expect(loc.deviceId, 'dev-1');
      expect(loc.name, 'Test Device');
      expect(loc.latitude, 13.082680);
      expect(loc.longitude, 80.270721);
      expect(loc.accuracy, 5.5);
      expect(loc.online, isTrue);
      expect(loc.ownerUid, 'uid-xyz');
      expect(loc.timestamp.millisecondsSinceEpoch, 1700000000000);
    });

    test('fromMap handles missing fields with defaults', () {
      final loc = LiveLocation.fromMap({}, 'dev-1');

      expect(loc.deviceId, 'dev-1');
      expect(loc.name, 'Unknown Device');
      expect(loc.latitude, 0.0);
      expect(loc.longitude, 0.0);
      expect(loc.accuracy, 0.0);
      expect(loc.online, isFalse);
      expect(loc.ownerUid, '');
    });

    test('copyWith creates a new instance with updated fields', () {
      final original = LiveLocation(
        deviceId: 'dev-1',
        name: 'Test',
        latitude: 13.0,
        longitude: 80.0,
        accuracy: 5.0,
        timestamp: DateTime.now(),
        online: true,
        ownerUid: 'uid-1',
      );
      final updated = original.copyWith(online: false);
      expect(updated.online, isFalse);
      expect(updated.latitude, 13.0);
      expect(updated.deviceId, 'dev-1');
    });
  });

  group('AppConstants', () {
    test('notification text is set and non-empty', () {
      expect(AppConstants.notificationTitle, isNotEmpty);
      expect(AppConstants.notificationText, isNotEmpty);
      expect(AppConstants.notificationTitle, 'Live Location Sharing Active');
    });

    test('database paths are correct', () {
      expect(AppConstants.liveLocationsPath, 'live_locations');
      expect(AppConstants.userDevicesPath, 'user_devices');
      expect(AppConstants.pairingsPath, 'pairings');
    });

    test('location update interval is between 3-5 seconds', () {
      expect(AppConstants.locationUpdateInterval.inSeconds,
          greaterThanOrEqualTo(3));
      expect(AppConstants.locationUpdateInterval.inSeconds,
          lessThanOrEqualTo(5));
    });

    test('default device names includes required examples from spec', () {
      expect(AppConstants.defaultDeviceNames, contains('Manoj Phone'));
      expect(AppConstants.defaultDeviceNames, contains('Office Phone'));
      expect(AppConstants.defaultDeviceNames, contains('Dad Phone'));
      expect(AppConstants.defaultDeviceNames, contains('Friend Phone'));
    });

    test('notification channel id is non-empty', () {
      expect(AppConstants.notificationChannelId, isNotEmpty);
    });

    test('notification id is positive', () {
      expect(AppConstants.notificationId, greaterThan(0));
    });
  });
}
