import 'package:flutter_test/flutter_test.dart';

import 'package:live_location_share/services/device_identity.dart';

void main() {
  group('DeviceIdentity.parsePairPayload', () {
    test('parses valid JSON payload with device_id and device_name', () {
      const payload =
          '{"device_id":"abc-123","device_name":"Manoj Phone","app":"Live Location Share"}';
      final result = DeviceIdentity.parsePairPayload(payload);

      expect(result, isNotNull);
      expect(result!.deviceId, 'abc-123');
      expect(result.deviceName, 'Manoj Phone');
    });

    test('returns null for empty string', () {
      final result = DeviceIdentity.parsePairPayload('');
      expect(result, isNull);
    });

    test('returns null for invalid JSON', () {
      const payload = 'not json at all {{{}}';
      final result = DeviceIdentity.parsePairPayload(payload);
      expect(result, isNull);
    });

    test('returns null for JSON missing device_id', () {
      const payload = '{"device_name":"Manoj Phone"}';
      final result = DeviceIdentity.parsePairPayload(payload);
      expect(result, isNull);
    });

    test('returns null for JSON missing device_name', () {
      const payload = '{"device_id":"abc-123"}';
      final result = DeviceIdentity.parsePairPayload(payload);
      expect(result, isNull);
    });

    test('accepts plain device ID string (no JSON) as fallback', () {
      const payload = '550e8400-e29b-41d4-a716-446655440000';
      final result = DeviceIdentity.parsePairPayload(payload);

      expect(result, isNotNull);
      expect(result!.deviceId, '550e8400-e29b-41d4-a716-446655440000');
      expect(result.deviceName, 'Paired Device');
    });

    test('rejects plain strings longer than 64 characters', () {
      final longString = 'a' * 100;
      final result = DeviceIdentity.parsePairPayload(longString);
      expect(result, isNull);
    });
  });
}
