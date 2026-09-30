import 'package:flutter/widgets.dart';

import '../../../core/theme/app_icons.dart';

/// What part of the car a mod touches. `name` is the value stored in
/// `car_mods.category`.
enum ModCategory {
  engine('Engine', AppIcons.gauge),
  exhaust('Exhaust', AppIcons.fire),
  intake('Intake', AppIcons.pulse),
  suspension('Suspension', AppIcons.slidersHorizontal),
  wheels('Wheels & tyres', AppIcons.tire),
  brakes('Brakes', AppIcons.target),
  body('Body & aero', AppIcons.car),
  lighting('Lighting', AppIcons.lightning),
  interior('Interior', AppIcons.steeringWheel),
  audio('Audio', AppIcons.microphoneStage),
  other('Other', AppIcons.wrench);

  const ModCategory(this.label, this.icon);
  final String label;
  final IconData icon;

  /// One word, for the summary line ("Wheels", not "Wheels & tyres").
  String get short => switch (this) {
        wheels => 'Wheels',
        body => 'Body',
        _ => label,
      };

  static ModCategory fromDb(String? v) => ModCategory.values.where((c) => c.name == v).firstOrNull ?? other;
}

/// One entry of a car's mods log, from `car_mod_list()`. [cost] is only ever
/// filled in for the owner; everyone else gets null from the server.
class CarMod {
  const CarMod({
    required this.id,
    required this.carId,
    required this.category,
    required this.title,
    this.description,
    this.cost,
    this.shop,
    this.vendorId,
    this.vendorName,
    required this.doneOn,
    required this.photoUrls,
    required this.isPrivate,
    required this.createdAt,
  });

  final String id;
  final String carId;
  final ModCategory category;
  final String title;
  final String? description;
  final double? cost;
  final String? shop;
  /// Set when the shop is a TT Spot partner (tap through to their page).
  final String? vendorId;
  final String? vendorName;
  final DateTime doneOn;
  /// One photo from the current form; older entries can have up to five.
  final List<String> photoUrls;
  /// "Only me": hidden from everyone but the owner.
  final bool isPrivate;
  final DateTime createdAt;

  String? get photo => photoUrls.firstOrNull;
  String? get shopName => vendorName ?? ((shop ?? '').trim().isEmpty ? null : shop!.trim());

  factory CarMod.fromMap(Map<String, dynamic> m) => CarMod(
        id: m['id'] as String,
        carId: m['car_id'] as String,
        category: ModCategory.fromDb(m['category'] as String?),
        title: m['title'] as String,
        description: m['description'] as String?,
        cost: (m['cost'] as num?)?.toDouble(),
        shop: m['shop'] as String?,
        vendorId: m['vendor_id'] as String?,
        vendorName: m['vendor_name'] as String?,
        doneOn: DateTime.parse(m['done_on'] as String),
        photoUrls: ((m['photo_urls'] as List?) ?? const []).cast<String>(),
        isPrivate: m['is_private'] as bool? ?? false,
        createdAt: DateTime.parse(m['created_at'] as String).toLocal(),
      );
}

/// "12 mods · Suspension, Exhaust, Wheels": the count and the three
/// categories with the most entries ("Other" only when nothing else).
String modsSummary(List<CarMod> mods) {
  if (mods.isEmpty) return 'No mods yet';
  final counts = <ModCategory, int>{};
  for (final m in mods) {
    counts[m.category] = (counts[m.category] ?? 0) + 1;
  }
  final ranked = counts.keys.toList()
    ..sort((a, b) {
      if ((a == ModCategory.other) != (b == ModCategory.other)) return a == ModCategory.other ? 1 : -1;
      final byCount = counts[b]!.compareTo(counts[a]!);
      return byCount != 0 ? byCount : a.index.compareTo(b.index);
    });
  final top = ranked.where((c) => c != ModCategory.other || ranked.length == 1).take(3).map((c) => c.short);
  return '${mods.length} mod${mods.length == 1 ? '' : 's'} · ${top.join(', ')}';
}
