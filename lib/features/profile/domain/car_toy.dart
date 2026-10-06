import 'car.dart';

/// `cars.toy_status`: null (never asked) | pending | ready | failed.
enum ToyStatus {
  none,
  pending,
  ready,
  failed;

  static ToyStatus parse(String? raw) => switch (raw) {
        'pending' => ToyStatus.pending,
        'ready' => ToyStatus.ready,
        'failed' => ToyStatus.failed,
        _ => ToyStatus.none,
      };
}

/// The nine paints a car (and its toy) can have: the kCarColors keys.
const kPaintKeys = {'red', 'black', 'white', 'grey', 'silver', 'blue', 'yellow', 'green', 'orange'};

/// A paint key, or null for anything else ("match the photo"), the same way
/// the database reads it (`toy_paint_key`, migration 0110).
String? paintKeyOf(String? raw) {
  final k = raw?.trim().toLowerCase();
  return k != null && kPaintKeys.contains(k) ? k : null;
}

/// The die-cast toy of a car (migration 0106, edge function car-toy), in the
/// car's paint (0110).
extension CarToy on Car {
  ToyStatus get toy => ToyStatus.parse(toyStatus);

  /// A toy is being made right now; the garage shows the fallback (or the
  /// old toy) and swaps the new one in when it lands (the watcher keeps the
  /// car fresh).
  bool get toyPending => toy == ToyStatus.pending;

  /// The toy to show, or null: a ready render, even a stale one (an older
  /// cover or paint) while the new one is still being made.
  String? get toyToShow => toyUrl;

  /// The paint the member picked, or null (match the photo).
  String? get paint => paintKeyOf(color);

  /// The paint the toy on show was made in, or null (the photo's colour).
  String? get toyPaint => paintKeyOf(toyColor);

  /// The ready toy was made from a cover that is no longer the cover.
  bool get toyStale => toy == ToyStatus.ready && toyUrl != null && toySource != photoCover;

  /// The toy on show wears another paint than the one picked.
  bool get toyPaintStale => toyUrl != null && toyPaint != paint;

  /// A new paint is being put on the toy right now (the old toy stays on
  /// show under "Repainting your toy car…").
  bool get toyRepainting => toyPending && toyPaintStale;

  /// A new paint was picked but no repaint is running: the daily cap held it
  /// back (the app asks again once it frees up), or the repaint failed.
  bool get toyPaintWaiting => !toyPending && toyPaintStale;

  /// Whether the owner's app should ask for a toy (free, automatic): never
  /// asked, or the cover or the paint changed since the last ready render.
  /// Pending, ready-for-this-cover-and-paint, failed-for-this-cover (no
  /// credit burn on a car that keeps failing; "Remake" is the way out) and
  /// no photo: no.
  bool get toyNeedsRequest {
    if (photoCover == null) return false;
    return switch (toy) {
      ToyStatus.none => true,
      ToyStatus.pending => false,
      ToyStatus.ready => toySource != photoCover || toyPaint != paint,
      ToyStatus.failed => toySource != photoCover,
    };
  }
}

/// Which of [cars] the watcher should ask a toy for, in order: the owner's
/// cars that need one and were not tried yet this session (keyed by car id,
/// cover and paint, so a new cover or paint is tried again).
List<Car> toyRequestPlan(Iterable<Car> cars, {required String? me, required Set<String> tried}) {
  if (me == null) return const [];
  return [
    for (final c in cars)
      if (c.ownerId == me && c.toyNeedsRequest && !tried.contains(toyTryKey(c))) c,
  ];
}

String toyTryKey(Car car) => '${car.id}|${car.photoCover}|${car.paint}';

/// `car_toy_quota(car)`: toy renders left for one car in the rolling 24 h.
class ToyQuota {
  const ToyQuota({required this.limit, required this.used, this.nextAt, this.pending = false, this.enabled = true});

  factory ToyQuota.fromMap(Map<String, dynamic> m) => ToyQuota(
        limit: (m['limit'] as num?)?.toInt() ?? 3,
        used: (m['used'] as num?)?.toInt() ?? 0,
        nextAt: m['next_at'] == null ? null : DateTime.tryParse(m['next_at'] as String)?.toLocal(),
        pending: m['pending'] as bool? ?? false,
        enabled: m['enabled'] as bool? ?? true,
      );

  final int limit;
  final int used;

  /// When the next render frees up (only once [left] is 0).
  final DateTime? nextAt;
  final bool pending;
  final bool enabled;

  int get left => (limit - used).clamp(0, limit);
  bool get capped => left == 0;
}

/// "9:40 PM", "9:40 PM tomorrow" (relative to [now]).
String formatToyTime(DateTime t, {DateTime? now}) {
  final n = now ?? DateTime.now();
  final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
  final m = t.minute.toString().padLeft(2, '0');
  final clock = '$h:$m ${t.hour < 12 ? 'AM' : 'PM'}';
  final sameDay = t.year == n.year && t.month == n.month && t.day == n.day;
  return sameDay ? clock : '$clock tomorrow';
}

/// What the member reads when the day's renders are used up.
String toyCapMessage(ToyQuota q, {DateTime? now}) {
  final when = q.nextAt == null ? 'tomorrow' : 'after ${formatToyTime(q.nextAt!, now: now)}';
  return '${q.limit} toy renders a day per car, and today\'s are used. The new paint goes on $when.';
}
