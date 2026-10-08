class Spot {
  final String id;
  final String name;
  final String description;
  final double latitude;
  final double longitude;
  final String type;
  final String createdBy;
  final DateTime createdAt;

  const Spot({
    required this.id,
    required this.name,
    required this.description,
    required this.latitude,
    required this.longitude,
    required this.type,
    required this.createdBy,
    required this.createdAt,
  });
}
