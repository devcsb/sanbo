/// A user-confirmed place name stored only on the device.
class PlaceMemory {
  const PlaceMemory({
    required this.id,
    required this.latitude,
    required this.longitude,
    required this.name,
    required this.updatedAt,
    this.address,
  });

  final int id;
  final double latitude;
  final double longitude;
  final String name;
  final String? address;
  final DateTime updatedAt;

  String get displayName => name.trim();
}
