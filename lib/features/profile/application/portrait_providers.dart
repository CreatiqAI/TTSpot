import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/supabase/supabase_client.dart';
import '../../../core/utils/friendly_error.dart';
import '../../points/application/points_providers.dart';
import '../data/portrait_repository.dart';
import '../domain/portrait_style.dart';
import 'profile_providers.dart';

/// Jobs older than this are considered lost (the RPC marks them failed on the
/// next request); we stop polling for them.
const _kPortraitTimeout = Duration(minutes: 15);

/// All portraits of one car, newest first. Live: a realtime channel on
/// car_portraits fires a reload on every change, and while any recent job is
/// still pending it also re-reads every 5 s in case the channel drops. When a
/// job flips to ready the car itself is refreshed (the first portrait fronts
/// it). Auto-disposed: leaving the car page tears the channel down; coming
/// back re-reads.
final carPortraitsProvider = StreamProvider.autoDispose.family<List<CarPortrait>, String>((ref, carId) {
  final repo = ref.watch(portraitRepositoryProvider);
  final controller = StreamController<List<CarPortrait>>();
  Timer? poll;
  var closed = false;
  var hadPending = false;

  Future<void> load() async {
    if (closed) return;
    try {
      final list = await repo.fetchPortraits(carId);
      if (closed) return;
      controller.add(list);
      final pending = list.any((p) => p.isPending);
      final recent = list.any((p) => p.isPending && DateTime.now().difference(p.createdAt) < _kPortraitTimeout);
      if (hadPending && !pending) {
        ref.invalidate(carProvider(carId));
        final me = ref.read(currentUserIdProvider);
        if (me != null) ref.invalidate(userCarsProvider(me));
      }
      hadPending = pending;
      poll?.cancel();
      if (recent) poll = Timer(const Duration(seconds: 5), load);
    } catch (e, st) {
      if (!closed) controller.addError(e, st);
    }
  }

  final channel = repo.subscribe(carId, load);
  load();
  ref.onDispose(() {
    closed = true;
    poll?.cancel();
    channel.unsubscribe();
    controller.close();
  });
  return controller.stream;
});

/// Request / choose / clear. Never blocks the UI: request returns as soon as
/// the job is booked; the list above shows it painting.
class PortraitActions {
  PortraitActions(this._ref);
  final Ref _ref;

  /// Books the job and pays for it (the server takes the points in the same
  /// step, and gives them back if the job fails).
  Future<void> request(String carId, String styleId) async {
    final me = _ref.read(currentUserIdProvider);
    if (me == null) throw const AppException('You\'re signed out. Sign in again.');
    try {
      await _ref.read(portraitRepositoryProvider).request(carId: carId, styleId: styleId);
    } finally {
      // Paid, or refused for the balance: either way show the real number.
      _ref.invalidate(pointsBalanceProvider);
    }
    _ref.invalidate(carPortraitsProvider(carId));
    _ref.invalidate(pointHistoryProvider);
  }

  Future<void> choose(CarPortrait p) async {
    await _ref.read(portraitRepositoryProvider).choose(p.id);
    _refreshCar(p.carId);
  }

  Future<void> usePhotos(String carId) async {
    await _ref.read(portraitRepositoryProvider).clear(carId);
    _refreshCar(carId);
  }

  void _refreshCar(String carId) {
    _ref.invalidate(carProvider(carId));
    final me = _ref.read(currentUserIdProvider);
    if (me != null) _ref.invalidate(userCarsProvider(me));
  }
}

/// The portrait switch and price, from `platform_settings`:
/// `portraits_enabled` (a kill switch for everyone, admins too) and
/// `portrait_cost_points` (what one portrait costs; 0 = free).
typedef PortraitSettings = ({bool enabled, int cost});

final portraitSettingsProvider = FutureProvider<PortraitSettings>((ref) async {
  ref.watch(currentUserIdProvider);
  try {
    final rows = await ref.watch(supabaseProvider).from('platform_settings').select('key, value').inFilter('key', ['portraits_enabled', 'portrait_cost_points']);
    final byKey = {for (final r in rows) r['key'] as String: r['value']};
    final on = byKey['portraits_enabled'];
    final cost = byKey['portrait_cost_points'];
    return (
      enabled: on == true || on == 'true' || on == 1 || on == '1',
      cost: cost is num ? cost.toInt() : int.tryParse('$cost') ?? kDefaultPortraitCost,
    );
  } catch (_) {
    return (enabled: false, cost: kDefaultPortraitCost);
  }
});

/// Mirrors the server default of `portrait_cost_points`.
const kDefaultPortraitCost = 300;

/// Whether anyone may start an AI portrait right now. No admin bypass: admins
/// pay points like everyone else.
final portraitsEnabledProvider = Provider<AsyncValue<bool>>((ref) => ref.watch(portraitSettingsProvider).whenData((s) => s.enabled));

final portraitActionsProvider = Provider<PortraitActions>((ref) => PortraitActions(ref));
