import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../auth/domain/profile.dart';
import '../../../social/domain/post.dart';
import '../../domain/car.dart';
import '../../domain/car_documents.dart';
import '../../domain/car_meet.dart';
import '../../domain/car_mod.dart';
import '../../domain/car_toy.dart';
import '../../domain/portrait_style.dart';

// What the car page shows, worked out from plain data so the page body can be
// pumped in tests without Supabase (see test/car_page_test.dart).

/// Turns a stored URL into an image. The app caches network images; tests
/// hand in bundled assets.
typedef CarImageResolver = ImageProvider Function(String url);

ImageProvider defaultCarImage(String url) => CachedNetworkImageProvider(url);

// ------------------------------------------------------------ portraits ---

/// One finished AI portrait of the car.
class CarPortraitMedia {
  const CarPortraitMedia({required this.url, this.style, this.portrait, this.wearing = false});

  final String url;

  /// The portrait's look (from its row, or its file name for visitors).
  final PortraitStyle? style;

  /// The owner's portrait row (null for visitors, who only see the one in use).
  final CarPortrait? portrait;

  /// The car wears it: it fronts the car where a photo would.
  final bool wearing;

  /// "Night city portrait", for buttons and the viewer.
  String get label => '${style?.name ?? 'AI'} portrait';
}

/// `…/portraits/<car>/night_city.png` → Night city.
PortraitStyle? portraitStyleFromUrl(String url) {
  final path = Uri.tryParse(url)?.path ?? url;
  final file = path.split('/').last;
  final dot = file.lastIndexOf('.');
  return PortraitStyle.byId(dot > 0 ? file.substring(0, dot) : file);
}

/// The finished portraits, newest row order: the owner passes their
/// [portraits] (null while loading); visitors only get the one the car wears.
List<CarPortraitMedia> carPortraitsFor(Car car, {List<CarPortrait>? portraits}) {
  final out = <CarPortraitMedia>[];
  final seen = <String>{};
  for (final p in portraits ?? const <CarPortrait>[]) {
    if (!p.isReady || !seen.add(p.url!)) continue;
    out.add(CarPortraitMedia(url: p.url!, style: p.style, portrait: p, wearing: p.url == car.portraitUrl));
  }
  final wearing = car.portraitUrl;
  if (wearing != null && seen.add(wearing)) {
    out.add(CarPortraitMedia(url: wearing, style: portraitStyleFromUrl(wearing), wearing: true));
  }
  return out;
}

// --------------------------------------------------------------- album ---

/// How the album lays out [count] photos: one wide picture, two or four as
/// squares two to a row, anything else three to a row.
({int columns, double aspect}) albumLayout(int count) => switch (count) {
      1 => (columns: 1, aspect: 16 / 10),
      2 || 4 => (columns: 2, aspect: 1.0),
      _ => (columns: 3, aspect: 1.0),
    };

// --------------------------------------------------------------- specs ---

typedef CarSpec = ({String label, String value});

final _blankSpec = RegExp(r'^[\s\-–—?.·]*$|^(n/?a|unknown|none|tbc)$', caseSensitive: false);

/// The spec values the car really has: `cars.specs` split on " · " plus the
/// body style, each with a label for the spec sheet. Never a placeholder.
List<CarSpec> carSpecs(Car car) {
  final out = <CarSpec>[];
  for (final raw in (car.specs ?? '').split('·')) {
    final v = raw.trim();
    if (v.isEmpty || _blankSpec.hasMatch(v)) continue;
    out.add((label: specLabel(v), value: v));
  }
  final body = (car.bodyStyle ?? '').trim();
  if (body.isNotEmpty && !_blankSpec.hasMatch(body) && !out.any((s) => s.value.toLowerCase().contains(body.toLowerCase()))) {
    out.add((label: 'Body', value: body.length <= 3 ? body.toUpperCase() : body[0].toUpperCase() + body.substring(1)));
  }
  return out;
}

/// "Engine", "Power", "Gearbox"… for a spec value, or "Spec".
String specLabel(String v) {
  final s = v.toLowerCase();
  bool has(String pattern) => RegExp(pattern, caseSensitive: false).hasMatch(s);
  if (has(r'\b\d+\s?(hp|bhp|ps|kw)\b')) return 'Power';
  if (has(r'\b\d+\s?nm\b')) return 'Torque';
  if (has(r'0\s?[-–]\s?100|\b\d+(\.\d+)?\s?s\b')) return '0–100';
  if (has(r'km/h|mph')) return 'Top speed';
  if (has(r'\b(cvt|e-cvt|dct|pdk|dsg|amt|at|mt|manual|auto|automatic|tiptronic|sequential)\b|\d+-speed')) return 'Gearbox';
  if (has(r'\b(fwd|rwd|awd|4wd|4x4|quattro|xdrive|4matic|front-wheel|rear-wheel|all-wheel)\b')) return 'Drive';
  if (has(r'\b\d(\.\d)?\s?l\b|\b\d{3,4}\s?cc\b|turbo|\bna\b|hybrid|electric|\bev\b|\bv\d+\b|flat|rotary|kwh')) return 'Engine';
  if (has(r'seat')) return 'Seats';
  return 'Spec';
}

// ---------------------------------------------------------- mod tiles ---

/// A mod category's tile colours (background, letters), per theme.
({Color bg, Color fg}) modTint(ModCategory c) {
  final (light, dark) = switch (c) {
    ModCategory.wheels => (const Color(0xFF1D4ED8), const Color(0xFF7CA8FF)),
    ModCategory.exhaust => (const Color(0xFFB91C1C), const Color(0xFFFF8A8A)),
    ModCategory.engine => (const Color(0xFFC2410C), const Color(0xFFFFA36B)),
    ModCategory.intake => (const Color(0xFF0F766E), const Color(0xFF4FD8C6)),
    ModCategory.suspension => (const Color(0xFF6D28D9), const Color(0xFFB9A2FF)),
    ModCategory.brakes => (const Color(0xFFBE123C), const Color(0xFFFF8BA6)),
    ModCategory.body => (const Color(0xFF15803D), const Color(0xFF6BE09A)),
    ModCategory.lighting => (const Color(0xFFA16207), const Color(0xFFF7CF4A)),
    ModCategory.interior => (const Color(0xFF334155), const Color(0xFFCBD5E1)),
    ModCategory.audio => (const Color(0xFFA21CAF), const Color(0xFFF08CFF)),
    ModCategory.other => (const Color(0xFF4B5563), const Color(0xFFD1D5DB)),
  };
  final fg = AppColors.dark ? dark : light;
  return (bg: fg.withValues(alpha: AppColors.dark ? 0.16 : 0.10), fg: fg);
}

// ------------------------------------------------------------- history ---

enum CarHistoryKind { mod, meet, parked }

/// One event in the car's history: a mod, a meet it went to, the day it was
/// parked in the garage.
class CarHistoryItem {
  const CarHistoryItem({required this.kind, required this.date, required this.title, required this.sub, this.image, this.mod, this.meet});
  final CarHistoryKind kind;
  final DateTime date;
  final String title;
  final String sub;
  final String? image;
  final CarMod? mod;
  final CarMeet? meet;

  String get eyebrow => switch (kind) {
        CarHistoryKind.mod => 'MOD · ${mod!.category.short.toUpperCase()}',
        CarHistoryKind.meet => 'MEET',
        CarHistoryKind.parked => 'PARKED',
      };
}

/// Newest first. Prices only when [showPrices] (the owner).
List<CarHistoryItem> carHistory(Car car, {required List<CarMod> mods, required List<CarMeet> meets, required bool showPrices}) {
  final items = <CarHistoryItem>[
    for (final m in mods)
      CarHistoryItem(
        kind: CarHistoryKind.mod,
        date: m.doneOn,
        title: m.title,
        sub: [?m.shopName, if (showPrices && m.cost != null) 'RM ${formatRinggit(m.cost!)}'].join(' · '),
        image: m.photo,
        mod: m,
      ),
    for (final e in meets)
      CarHistoryItem(
        kind: CarHistoryKind.meet,
        date: e.startsAt,
        title: e.title,
        sub: [e.checkedIn ? 'Checked in' : 'On the list', ?e.venue].join(' · '),
        image: e.coverUrl,
        meet: e,
      ),
    CarHistoryItem(
      kind: CarHistoryKind.parked,
      date: car.createdAt,
      title: 'Parked in the garage',
      sub: 'The first photo of this car on TT Spot',
      image: car.photoCover,
    ),
  ];
  // By calendar day, newest first; on the same day the car was parked before
  // anything else happened to it.
  DateTime day(DateTime d) => DateTime(d.year, d.month, d.day);
  items.sort((a, b) {
    final byDay = day(b.date).compareTo(day(a.date));
    if (byDay != 0) return byDay;
    if ((a.kind == CarHistoryKind.parked) != (b.kind == CarHistoryKind.parked)) return a.kind == CarHistoryKind.parked ? 1 : -1;
    return b.date.compareTo(a.date);
  });
  return items;
}

// --------------------------------------------------------------- dates ---

const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

/// "11 Sep" this year, "11 Sep 2025" before.
String formatShortDay(DateTime d, {DateTime? now}) {
  final n = now ?? DateTime.now();
  return d.year == n.year ? '${d.day} ${_months[d.month - 1]}' : formatDay(d);
}

/// 45,000 · 1,250.50
String formatRinggit(double v) {
  final s = v.toStringAsFixed(v == v.roundToDouble() ? 0 : 2);
  final parts = s.split('.');
  final whole = parts[0].replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');
  return parts.length > 1 ? '$whole.${parts[1]}' : whole;
}

// ---------------------------------------------------------------- data ---

/// Everything the car page body draws. Lists are null while they load.
class CarPageData {
  const CarPageData({
    required this.car,
    required this.mine,
    this.owner,
    this.mods,
    this.documents,
    this.documentsLoading = false,
    this.portraits,
    this.portraitsEnabled = false,
    this.portraitCost = 300,
    this.posts,
    this.meets,
    this.promoDismissed = false,
    this.messaging = false,
    this.toyQuota,
  });

  final Car car;
  final bool mine;
  final Profile? owner;
  final List<CarMod>? mods;
  final CarDocuments? documents;
  final bool documentsLoading;

  /// Every portrait row of this car (owner only; visitors can't read them).
  final List<CarPortrait>? portraits;
  final bool portraitsEnabled;
  final int portraitCost;
  final List<FeedPost>? posts;
  final List<CarMeet>? meets;

  final bool promoDismissed;

  /// "Message owner" is opening the chat.
  final bool messaging;

  /// Toy renders left today (owner, only asked for while a new paint waits).
  final ToyQuota? toyQuota;

  int get readyPortraits => portraits?.where((p) => p.isReady).length ?? 0;

  /// The Portraits section: the owner's when portraits are on or any exist;
  /// a visitor's only when the car wears one.
  bool get showPortraits => mine ? (portraitsEnabled || readyPortraits > 0 || portraitNews.isNotEmpty || car.portraitUrl != null) : car.portraitUrl != null;

  /// "Make it look pro": the owner, portraits on, none made yet, a photo to
  /// paint from, and not closed on this phone.
  bool get showPromo => mine && portraitsEnabled && portraits != null && readyPortraits == 0 && car.photoUrls.isNotEmpty && !promoDismissed;

  /// Portraits still painting, and ones that failed in the last week.
  List<CarPortrait> get portraitNews {
    if (!mine) return const [];
    final weekAgo = DateTime.now().subtract(const Duration(days: 7));
    return [
      for (final p in portraits ?? const <CarPortrait>[])
        if (p.isPending || (p.status == PortraitStatus.failed && p.createdAt.isAfter(weekAgo))) p,
    ].take(3).toList();
  }
}
