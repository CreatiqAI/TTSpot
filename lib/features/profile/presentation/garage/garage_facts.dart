import '../../domain/car.dart';
import '../../domain/car_documents.dart';
import '../../domain/car_mod.dart';

/// What the garage knows about the car in view. Null while it loads.
class GarageFacts {
  const GarageFacts({this.mods, this.meets, this.posts, this.papers, this.papersLoaded = false});

  /// Newest first. Prices only come back for the owner.
  final List<CarMod>? mods;
  final int? meets;
  final int? posts;

  /// The owner's papers; null when none are saved (see [papersLoaded]).
  final CarDocuments? papers;
  final bool papersLoaded;

  double? get spent => mods?.fold<double>(0, (s, m) => s + (m.cost ?? 0));
}

/// RM 850 · RM 12.5k · RM 1.2m: fits a quarter of a phone width.
String compactMoney(double v) {
  String trim(double x) => x.toStringAsFixed(x >= 100 || x == x.roundToDouble() ? 0 : 1);
  if (v >= 1000000) return '${trim(v / 1000000)}m';
  if (v >= 10000) return '${trim(v / 1000)}k';
  final s = v.toStringAsFixed(0);
  return s.replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');
}

/// The line under the name: the spec line, else body style and colour.
String carSubline(Car c) {
  final spec = c.specLine;
  if (spec != null) return spec;
  String cap(String s) => s.length <= 3 ? s.toUpperCase() : s[0].toUpperCase() + s.substring(1);
  final parts = [
    if ((c.bodyStyle ?? '').trim().isNotEmpty) cap(c.bodyStyle!.trim()),
    if ((c.color ?? '').trim().isNotEmpty) cap(c.color!.trim()),
  ];
  return parts.isEmpty ? 'No specs yet' : parts.join(' · ');
}
