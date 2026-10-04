import 'car_photo_storage.dart' show parsePhotoOriginals;

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
    this.cutoutUrl,
    this.cutoutSource,
    this.garageStyle = 'auto',
    this.photoOriginals = const {},
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
  /// The car cut out of its cover photo (PNG with alpha) for the garage bay;
  /// null when none was made or it failed the quality check.
  final String? cutoutUrl;
  /// The photo [cutoutUrl] was made from: a new cover photo makes it stale.
  final String? cutoutSource;
  /// 'auto' (cut-out when there is a good one) | 'card' (always the photo card).
  final String garageStyle;
  /// Blurred photo URL → its original in the private car-originals bucket
  /// (`<uid>/<file>`), so the owner can take the blur off again. Photos
  /// blurred before 2 Oct 2026 have no entry.
  final Map<String, String> photoOriginals;

  String get title => '$make $model';
  /// Spec line worth showing, or null.
  String? get specLine => (specs ?? '').trim().isEmpty ? null : specs!.trim();
  String? get cover => portraitUrl ?? (photoUrls.isEmpty ? null : photoUrls.first);
  /// The member's own cover photo (never the AI portrait): what the garage
  /// cuts out and frames.
  String? get photoCover => photoUrls.isEmpty ? null : photoUrls.first;

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
        cutoutUrl: m['cutout_url'] as String?,
        cutoutSource: m['cutout_source'] as String?,
        garageStyle: m['garage_style'] as String? ?? 'auto',
        photoOriginals: parsePhotoOriginals(m['photo_originals']),
      );
}

class ProfileStats {
  const ProfileStats({required this.cars, required this.organised, required this.attended, this.went = 0, this.places = 0});
  final int cars;
  final int organised;
  final int attended;
  /// The profile's "Meets": meets and TT sessions they joined, checked in at
  /// or host, once started and not cancelled (SQL `went_event_ids`, migration
  /// 0104). Future RSVPs count from the start. Everyone sees the same number.
  final int went;
  /// Distinct places checked in at.
  final int places;
}
