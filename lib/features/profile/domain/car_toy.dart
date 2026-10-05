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

/// The die-cast toy of a car (migration 0106, edge function car-toy).
extension CarToy on Car {
  ToyStatus get toy => ToyStatus.parse(toyStatus);

  /// A toy is being made right now; the garage shows the fallback and swaps
  /// the toy in when it lands (the watcher keeps the car fresh).
  bool get toyPending => toy == ToyStatus.pending;

  /// The toy to show, or null: a ready render, even a stale one (an older
  /// cover) while the new one is still being made.
  String? get toyToShow => toyUrl;

  /// The ready toy was made from a cover that is no longer the cover.
  bool get toyStale => toy == ToyStatus.ready && toyUrl != null && toySource != photoCover;

  /// Whether the owner's app should ask for a toy (free, automatic): never
  /// asked, or the cover changed since the last render (ready or failed).
  /// Pending, ready-for-this-cover, failed-for-this-cover (no credit burn on
  /// a car that keeps failing; "Remake" is the way out) and no photo: no.
  bool get toyNeedsRequest {
    if (photoCover == null) return false;
    return switch (toy) {
      ToyStatus.none => true,
      ToyStatus.pending => false,
      ToyStatus.ready || ToyStatus.failed => toySource != photoCover,
    };
  }
}

/// Which of [cars] the watcher should ask a toy for, in order: the owner's
/// cars that need one and were not tried yet this session (keyed by car id +
/// cover, so a new cover is tried again).
List<Car> toyRequestPlan(Iterable<Car> cars, {required String? me, required Set<String> tried}) {
  if (me == null) return const [];
  return [
    for (final c in cars)
      if (c.ownerId == me && c.toyNeedsRequest && !tried.contains(toyTryKey(c))) c,
  ];
}

String toyTryKey(Car car) => '${car.id}|${car.photoCover}';
