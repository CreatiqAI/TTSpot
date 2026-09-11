/// A row from `cars`.
class Car {
  const Car({
    required this.id,
    required this.ownerId,
    required this.make,
    required this.model,
    this.year,
    this.description,
    required this.photoUrls,
    required this.createdAt,
    this.showSpend = true,
  });

  final String id;
  final String ownerId;
  final String make;
  final String model;
  final int? year;
  final String? description;
  final List<String> photoUrls;
  final DateTime createdAt;
  final bool showSpend;

  String get title => '$make $model';
  String? get cover => photoUrls.isEmpty ? null : photoUrls.first;

  factory Car.fromMap(Map<String, dynamic> m) => Car(
        id: m['id'] as String,
        ownerId: m['owner_id'] as String,
        make: m['make'] as String,
        model: m['model'] as String,
        year: m['year'] as int?,
        description: m['description'] as String?,
        photoUrls: ((m['photo_urls'] as List?) ?? const []).cast<String>(),
        createdAt: DateTime.parse(m['created_at'] as String).toLocal(),
        showSpend: (m['show_spend'] as bool?) ?? true,
      );
}

class ProfileStats {
  const ProfileStats({required this.cars, required this.organised, required this.attended, this.went = 0, this.places = 0});
  final int cars;
  final int organised;
  final int attended;
  /// Meets with a check-in (proven went).
  final int went;
  /// Distinct places checked in at.
  final int places;
}
