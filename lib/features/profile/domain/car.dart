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
    this.color,
    this.isDefault = false,
    this.portraitUrl,
    this.specs,
    this.bodyStyle,
  });

  final String id;
  final String ownerId;
  final String make;
  final String model;
  final int? year;
  final String? description;
  final List<String> photoUrls;
  final DateTime createdAt;
  /// One of kCarColors keys (red, black, white, grey, silver, blue, yellow, green, orange).
  final String? color;
  /// Fronts the profile, drives on the map, goes with me to meets.
  final bool isDefault;
  /// AI portrait (plate-free) when generated; falls back to the first photo.
  final String? portraitUrl;
  /// Short factory spec line from the recogniser ("1.5 L NA · 102 hp · CVT").
  final String? specs;
  /// hatchback, sedan, SUV… from the recogniser.
  final String? bodyStyle;

  String get title => '$make $model';
  /// Spec line worth showing, or null.
  String? get specLine => (specs ?? '').trim().isEmpty ? null : specs!.trim();
  String? get cover => portraitUrl ?? (photoUrls.isEmpty ? null : photoUrls.first);

  factory Car.fromMap(Map<String, dynamic> m) => Car(
        id: m['id'] as String,
        ownerId: m['owner_id'] as String,
        make: m['make'] as String,
        model: m['model'] as String,
        year: m['year'] as int?,
        description: m['description'] as String?,
        photoUrls: ((m['photo_urls'] as List?) ?? const []).cast<String>(),
        createdAt: DateTime.parse(m['created_at'] as String).toLocal(),
        color: m['color'] as String?,
        isDefault: m['is_default'] as bool? ?? false,
        portraitUrl: m['portrait_url'] as String?,
        specs: m['specs'] as String?,
        bodyStyle: m['body_style'] as String?,
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
