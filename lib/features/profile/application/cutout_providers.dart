import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/supabase/supabase_client.dart';
import '../../../core/utils/http_bytes.dart';
import '../data/car_cutout_channel.dart';
import '../data/profile_repository.dart';
import '../domain/car.dart';
import '../domain/garage_look.dart';
import 'profile_providers.dart';

/// Cars whose cut-out is being made right now: their bay shows
/// "Parking your car…" until it's done.
class CutoutJobs extends Notifier<Set<String>> {
  @override
  Set<String> build() => const {};

  void _set(String carId, bool running) {
    final next = {...state};
    running ? next.add(carId) : next.remove(carId);
    state = next;
  }
}

final cutoutJobsProvider = NotifierProvider<CutoutJobs, Set<String>>(CutoutJobs.new);

/// Makes a car's garage cut-out in the background, on the owner's phone only:
/// after a car's photos are saved, and when the owner opens a garage with a
/// car whose cover has no cut-out yet. Never throws and never blocks a save.
class CutoutService {
  CutoutService(this._ref);
  final Ref _ref;

  /// `carId|photo` tried this session, so a failure isn't retried on every rebuild.
  final _tried = <String>{};
  final _running = <String>{};
  final _retries = <String, int>{};
  /// A newer cover that came in while the car's cut-out was still running
  /// (the save that put a blurred copy in front, say): cut that one next.
  final _queued = <String, (Car, Uint8List?)>{};

  /// Cuts [car] out of its cover photo when it has none for that photo.
  /// [coverBytes]: the cover as just uploaded, to skip downloading it again.
  Future<void> ensure(Car car, {Uint8List? coverBytes}) async {
    final me = _ref.read(currentUserIdProvider);
    final source = car.photoCover;
    if (me == null || car.ownerId != me || source == null || !needsCutout(car)) return;
    if (CarCutoutChannel.unsupported) return;
    final key = '${car.id}|$source';
    if (_tried.contains(key)) return;
    if (_running.contains(car.id)) {
      _queued[car.id] = (car, coverBytes);
      return;
    }
    _tried.add(key);
    _running.add(car.id);
    final jobs = _ref.read(cutoutJobsProvider.notifier);
    jobs._set(car.id, true);
    var retry = false;
    try {
      final bytes = coverBytes ?? await downloadBytes(source);
      final res = await CarCutoutChannel.cut(bytes);
      final report = res.report;
      if (kDebugMode) debugPrint('Cut-out ${car.model}: $report');
      switch (report.status) {
        case CutoutStatus.unsupported:
          return; // nothing stored: another phone of theirs may manage it
        case CutoutStatus.notReady:
          retry = true; // the model is still downloading
          return;
        case CutoutStatus.error:
          return; // try again next session
        case CutoutStatus.ok:
        case CutoutStatus.noSubject:
          break;
      }
      final repo = _ref.read(profileRepositoryProvider);
      final reject = CutoutGate.check(report);
      if (kDebugMode && reject != null) debugPrint('Cut-out ${car.model} goes to the card: ${reject.name}');
      String? url;
      if (reject == null && res.png != null) {
        url = await repo.uploadCutout(userId: me, carId: car.id, photoUrl: source, png: res.png!);
      }
      final kept = await repo.saveCutout(carId: car.id, url: url, source: source);
      if (!kept && url != null) {
        // The cover changed while this ran: the cut-out belongs to no car
        // now, and it was made from a photo that may show the plate.
        await repo.deleteUnreferencedPhotos(ownerId: me, staleCutouts: [url]);
      }
      _ref.invalidate(userCarsProvider(me));
      _ref.invalidate(carProvider(car.id));
    } catch (e) {
      if (kDebugMode) debugPrint('Cut-out for ${car.id} failed: $e');
    } finally {
      _running.remove(car.id);
      jobs._set(car.id, false);
      if (retry) _scheduleRetry(car, key);
      final next = _queued.remove(car.id);
      if (next != null) unawaited(ensure(next.$1, coverBytes: next.$2));
    }
  }

  /// The segmentation model downloads in the background the first time: try
  /// again a few times while the app is open.
  void _scheduleRetry(Car car, String key) {
    final n = (_retries[key] ?? 0) + 1;
    if (n > 4) return;
    _retries[key] = n;
    Timer(Duration(seconds: 15 * n), () {
      _tried.remove(key);
      unawaited(ensure(car));
    });
  }
}

final cutoutServiceProvider = Provider<CutoutService>((ref) => CutoutService(ref));
