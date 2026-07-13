/// Represents a paired device that the user has connected to.
///
/// A `Device` is the **local representation** of another phone the user has
/// paired with. It is NOT the live location data — that is stored in
/// [LiveLocation]. The [Device] only stores identifying metadata.
class Device {
  Device({
    required this.id,
    required this.name,
    required this.ownerUid,
    this.addedAt,
  });

  /// Creates a [Device] from a Firebase Realtime Database snapshot.
  factory Device.fromMap(Map<dynamic, dynamic> map, String id) {
    return Device(
      id: id,
      name: (map['name'] as String?) ?? 'Unknown Device',
      ownerUid: (map['owner_uid'] as String?) ?? '',
      addedAt: map['added_at'] is int
          ? DateTime.fromMillisecondsSinceEpoch(map['added_at'] as int)
          : null,
    );
  }

  /// Unique device ID — generated on first install and persisted locally.
  final String id;

  /// Human-readable name (e.g. "Manoj Phone", "Office Phone").
  final String name;

  /// Firebase anonymous UID of the device owner — used to enforce DB rules.
  final String ownerUid;

  /// When this device was added to the user's paired list.
  final DateTime? addedAt;

  Map<String, dynamic> toMap() => {
        'name': name,
        'owner_uid': ownerUid,
        if (addedAt != null) 'added_at': addedAt!.millisecondsSinceEpoch,
      };

  Device copyWith({
    String? id,
    String? name,
    String? ownerUid,
    DateTime? addedAt,
  }) {
    return Device(
      id: id ?? this.id,
      name: name ?? this.name,
      ownerUid: ownerUid ?? this.ownerUid,
      addedAt: addedAt ?? this.addedAt,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is Device && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'Device(id: $id, name: $name, ownerUid: $ownerUid)';
}
