import '../utils/constants.dart';

/// The latest live location data for a single device.
///
/// This model mirrors the structure stored in
/// `live_locations/{device_id}` in Firebase Realtime Database.
///
/// IMPORTANT: Only the **latest** location is ever stored. Each update
/// overwrites the previous one — no history is kept.
class LiveLocation {
  LiveLocation({
    required this.deviceId,
    required this.name,
    required this.latitude,
    required this.longitude,
    required this.accuracy,
    required this.timestamp,
    required this.online,
    required this.ownerUid,
  });

  /// Parses a [LiveLocation] from a Firebase Realtime Database snapshot.
  factory LiveLocation.fromMap(Map<dynamic, dynamic> map, String deviceId) {
    return LiveLocation(
      deviceId: deviceId,
      name: (map['name'] as String?) ?? 'Unknown Device',
      latitude: (map['latitude'] as num?)?.toDouble() ?? 0.0,
      longitude: (map['longitude'] as num?)?.toDouble() ?? 0.0,
      accuracy: (map['accuracy'] as num?)?.toDouble() ?? 0.0,
      timestamp: map['timestamp'] is int
          ? DateTime.fromMillisecondsSinceEpoch(map['timestamp'] as int)
          : DateTime.now(),
      online: (map['online'] as bool?) ?? false,
      ownerUid: (map['owner_uid'] as String?) ?? '',
    );
  }

  final String deviceId;
  final String name;
  final double latitude;
  final double longitude;
  final double accuracy;
  final DateTime timestamp;
  final bool online;
  final String ownerUid;

  Map<String, dynamic> toMap() => {
        'name': name,
        'latitude': latitude,
        'longitude': longitude,
        'accuracy': accuracy,
        'timestamp': timestamp.millisecondsSinceEpoch,
        'online': online,
        'owner_uid': ownerUid,
      };

  /// Returns the human-friendly coordinates string used by the Copy button.
  /// Format: `latitude,longitude` (no spaces) per the spec.
  String get coordinatesText => '$latitude,$longitude';

  /// Returns true if the location is older than [AppConstants.onlineTimeout].
  bool get isStale =>
      DateTime.now().difference(timestamp) > AppConstants.onlineTimeout;

  LiveLocation copyWith({
    String? deviceId,
    String? name,
    double? latitude,
    double? longitude,
    double? accuracy,
    DateTime? timestamp,
    bool? online,
    String? ownerUid,
  }) {
    return LiveLocation(
      deviceId: deviceId ?? this.deviceId,
      name: name ?? this.name,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      accuracy: accuracy ?? this.accuracy,
      timestamp: timestamp ?? this.timestamp,
      online: online ?? this.online,
      ownerUid: ownerUid ?? this.ownerUid,
    );
  }

  @override
  String toString() =>
      'LiveLocation(deviceId: $deviceId, name: $name, lat: $latitude, '
      'lng: $longitude, online: $online, ts: $timestamp)';
}
