import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/supabase_client.dart';
import '../../../core/utils/friendly_error.dart';
import '../data/toy_repository.dart';
import '../domain/car.dart';
import '../domain/car_toy.dart';
import 'profile_providers.dart';

/// Re-read my cars this often while one of them has a toy pending (the
/// realtime channel normally gets there first; this covers a dropped one).
const kToyPollEvery = Duration(seconds: 8);

/// Stop polling this long after the last pending car was seen: the server
/// fails jobs at 15 minutes, a lost one is not worth a query every 8 s.
const kToyPollFor = Duration(minutes: 5);

/// Gap between the lazy toy requests for cars that never had one (one at a
/// time, so an old garage does not fire a burst at Kie).
const kToyRequestGap = Duration(seconds: 3);

/// Keeps my garage fresh while toys are being made, and asks for the ones
/// that are missing.
///
/// Watch it from the owner's garage screen:
/// ```dart
/// ref.watch(toyWatcherProvider);
/// ```
/// and keep reading cars from `userCarsProvider(me)` / `carProvider(id)` as
/// before: this provider invalidates those when a car row changes (realtime
/// channel on `cars`, plus a light poll while any car is pending), so
/// `car.toyUrl` / `car.toy` swap from the fallback to the toy on their own.
///
/// The lazy backfill lives here too: a car whose `toy_status` is null (or
/// whose cover or paint changed since its toy) gets `request_car_toy` once
/// per session, one car at a time, [kToyRequestGap] apart. New cars, cover
/// changes and paint changes are booked by the database itself (migrations
/// 0106, 0110), so this only catches up on what the daily cap held back.
///
/// Auto-disposed: leaving the garage tears the channel and timers down.
final toyWatcherProvider = Provider.autoDispose<void>((ref) {
  final me = ref.watch(currentUserIdProvider);
  if (me == null) return;
  final repo = ref.watch(toyRepositoryProvider);
  final tried = <String>{};
  Timer? poll;
  Timer? requestTimer;
  DateTime? lastPending;
  var requesting = false;
  var disposed = false;

  void refresh([String? carId]) {
    if (disposed) return;
    ref.invalidate(userCarsProvider(me));
    if (carId != null) ref.invalidate(carProvider(carId));
  }

  void schedulePoll() {
    poll?.cancel();
    poll = Timer(kToyPollEvery, () {
      final since = lastPending;
      if (disposed || since == null || DateTime.now().difference(since) > kToyPollFor) return;
      refresh();
    });
  }

  Future<void> requestNext(List<Car> plan) async {
    if (requesting || plan.isEmpty || disposed) return;
    requesting = true;
    final car = plan.first;
    tried.add(toyTryKey(car));
    try {
      final job = await repo.request(car.id);
      if (kDebugMode) debugPrint('Toy for ${car.model}: ${job == null ? 'nothing to do' : 'job $job'}');
      if (job != null) {
        lastPending = DateTime.now();
        refresh(car.id);
      }
    } catch (e) {
      if (kDebugMode) debugPrint('Toy for ${car.id} not requested: $e');
    } finally {
      requesting = false;
    }
    final rest = plan.skip(1).toList();
    if (rest.isNotEmpty && !disposed) {
      requestTimer?.cancel();
      requestTimer = Timer(kToyRequestGap, () => requestNext(rest));
    }
  }

  ref.listen<AsyncValue<List<Car>>>(userCarsProvider(me), (_, next) {
    final cars = next.value;
    if (cars == null) return;
    if (cars.any((c) => c.toyPending)) {
      lastPending = DateTime.now();
      schedulePoll();
    } else {
      poll?.cancel();
    }
    final plan = toyRequestPlan(cars, me: me, tried: tried);
    if (plan.isNotEmpty && !requesting) unawaited(requestNext(plan));
  }, fireImmediately: true);

  RealtimeChannel? channel;
  try {
    channel = repo.subscribeCars(me, (carId) {
      refresh(carId);
      schedulePoll();
    });
  } catch (e) {
    if (kDebugMode) debugPrint('Toy watcher: no realtime ($e); polling only');
  }

  ref.onDispose(() {
    disposed = true;
    poll?.cancel();
    requestTimer?.cancel();
    channel?.unsubscribe();
  });
});

/// "Remake": a fresh toy from the current cover, on the member's request
/// (free, capped at `toy_daily_limit` a day per car). Throws an
/// [AppException] with the server's reason when it cannot.
class ToyActions {
  ToyActions(this._ref);
  final Ref _ref;

  Future<void> remake(String carId) async {
    final me = _ref.read(currentUserIdProvider);
    if (me == null) throw const AppException('You\'re signed out. Sign in again.');
    try {
      await _ref.read(toyRepositoryProvider).request(carId, manual: true);
    } finally {
      _ref.invalidate(carToyQuotaProvider(carId));
    }
    _ref.invalidate(userCarsProvider(me));
    _ref.invalidate(carProvider(carId));
  }
}

final toyActionsProvider = Provider<ToyActions>((ref) => ToyActions(ref));

/// Toy renders left today for one of my cars (the edit form's paint hint,
/// the car page's "the new paint goes on after…"). Errors read as "unknown"
/// (null) so a hint never blocks anything.
final carToyQuotaProvider = FutureProvider.autoDispose.family<ToyQuota?, String>((ref, carId) async {
  try {
    return await ref.watch(toyRepositoryProvider).quota(carId);
  } catch (e) {
    if (kDebugMode) debugPrint('Toy quota for $carId: $e');
    return null;
  }
});
