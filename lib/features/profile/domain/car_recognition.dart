/// What the `recognize-car` edge function saw in a photo. Everything here is
/// a guess: the forms prefill from it and keep every field editable.
class CarRecognition {
  const CarRecognition({
    required this.make,
    required this.model,
    this.yearFrom,
    this.yearTo,
    this.color,
    this.bodyStyle = '',
    required this.confidence,
    this.specLine = '',
    this.plate,
  });

  final String make;
  final String model;
  final int? yearFrom;
  final int? yearTo;
  /// One of kCarColors keys, or null when the paint could not be bucketed.
  final String? color;
  /// hatchback, sedan, SUV… or '' when unknown.
  final String bodyStyle;
  /// 0–1 for make + model together.
  final double confidence;
  /// Short factory line like "1.5 L NA · 102 hp · CVT", or '' when unsure.
  final String specLine;
  /// Where the number plate sits, or null when none was seen.
  final PlateBox? plate;

  /// Good enough to prefill the form with.
  bool get confident => confidence >= 0.5 && make.isNotEmpty && model.isNotEmpty;

  /// A single year when the guess pins one down, else null (the form shows
  /// the range as a hint instead).
  int? get year => yearFrom != null && yearFrom == yearTo ? yearFrom : null;

  /// "2018–2022" style hint when the guess is a generation, not a year.
  String? get yearRange {
    if (yearFrom == null || yearTo == null || yearFrom == yearTo) return null;
    return '$yearFrom–$yearTo';
  }

  /// True when the owner kept the make and model the guess was for, so the
  /// spec line and body style still describe the car.
  bool matches(String make, String model) =>
      make.trim().toLowerCase() == this.make.trim().toLowerCase() && model.trim().toLowerCase() == this.model.trim().toLowerCase();

  factory CarRecognition.fromMap(Map<String, dynamic> m) {
    PlateBox? plate;
    final p = m['plate'];
    if (p is Map && p['found'] == true && p['box'] is List) {
      final b = (p['box'] as List).map((v) => (v as num).toDouble()).toList();
      if (b.length == 4) plate = PlateBox(b[0], b[1], b[2], b[3]);
    }
    return CarRecognition(
      make: (m['make'] as String?)?.trim() ?? '',
      model: (m['model'] as String?)?.trim() ?? '',
      yearFrom: (m['yearFrom'] as num?)?.toInt(),
      yearTo: (m['yearTo'] as num?)?.toInt(),
      color: m['color'] as String?,
      bodyStyle: (m['bodyStyle'] as String?)?.trim() ?? '',
      confidence: ((m['confidence'] as num?) ?? 0).toDouble().clamp(0, 1),
      specLine: (m['specLine'] as String?)?.trim() ?? '',
      plate: plate,
    );
  }
}

/// A number plate's bounding box as fractions (0–1) of the image size.
class PlateBox {
  const PlateBox(this.x0, this.y0, this.x1, this.y1);
  final double x0;
  final double y0;
  final double x1;
  final double y1;
}
