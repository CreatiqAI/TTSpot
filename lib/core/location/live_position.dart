import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' show LatLng;

/// One live GPS fix, the newest good one the phone has given us.
class LivePosition {
  const LivePosition({required this.latLng, required this.accuracyM, required this.at, this.heading});
  final LatLng latLng;
  /// Radius the phone is confident about, in metres.
  final double accuracyM;
  final DateTime at;
  final double? heading;

  Duration get age => DateTime.now().difference(at);
  bool get isGood => accuracyM <= LivePositionNotifier.goodAccuracyM;
}

/// The single source of truth for where I am while the app is open. Starts a
/// high-accuracy stream (every 5 m of movement), throws away fixes that are
/// worse than what we already have, and pauses in the background. Feeds my
/// pin on the map, distances in lists, and the upload to friends.
///
/// Never prompts for permission: the location gate screen does that with
/// context. `start()` is safe to call again after permission is granted.
class LivePositionNotifier extends Notifier<LivePosition?> with WidgetsBindingObserver {
  static const goodAccuracyM = 100.0;
  /// A cached fix older than this is not worth showing.
  static const cachedMaxAge = Duration(minutes: 2);

  StreamSubscription<Position>? _sub;
  bool _running = false;

  @override
  LivePosition? build() {
    ref.onDispose(stop);
    return null;
  }

  bool get running => _running;

  Future<void> start() async {
    if (_running) return;
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return;
      final perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) return;
    } catch (_) {
      return;
    }
    _running = true;
    WidgetsBinding.instance.addObserver(this);
    // Seed from the cache only when it is fresh; a stale fix is worse than none.
    try {
      final last = await Geolocator.getLastKnownPosition();
      if (last != null && DateTime.now().difference(last.timestamp) < cachedMaxAge) _accept(last);
    } catch (_) {}
    _listen();
    unawaited(refresh());
  }

  void _listen() {
    _sub?.cancel();
    _sub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.best, distanceFilter: 5),
    ).listen(_accept, onError: (_) {});
  }

  /// Ask for one fresh fix now (the locate button). Returns the newest
  /// position we trust, which may be the one we already had.
  Future<LatLng?> refresh() async {
    if (!_running) await start();
    if (!_running) return state?.latLng;
    try {
      final p = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.best, timeLimit: Duration(seconds: 10)),
      );
      _accept(p);
    } catch (_) {}
    return state?.latLng;
  }

  void _accept(Position p) {
    final acc = p.accuracy.isNaN ? 9999.0 : p.accuracy;
    final cur = state;
    if (cur != null) {
      // Never go backwards in time.
      if (p.timestamp.isBefore(cur.at)) return;
      // A worse fix replaces a good one only once the good one is getting old
      // (the phone lost GPS; better to move the pin than to freeze it).
      if (acc > goodAccuracyM && cur.accuracyM < acc && cur.age < const Duration(seconds: 45)) return;
    }
    state = LivePosition(
      latLng: LatLng(p.latitude, p.longitude),
      accuracyM: acc,
      at: p.timestamp,
      heading: p.heading.isNaN || p.heading < 0 ? null : p.heading,
    );
  }

  @override
  // ignore: avoid_renaming_method_parameters
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (!_running) return;
    if (s == AppLifecycleState.resumed) {
      if (_sub == null) {
        _listen();
        unawaited(refresh());
      }
    } else if (s == AppLifecycleState.paused || s == AppLifecycleState.hidden) {
      _sub?.cancel();
      _sub = null;
    }
  }

  void stop() {
    _sub?.cancel();
    _sub = null;
    if (_running) WidgetsBinding.instance.removeObserver(this);
    _running = false;
  }
}

final livePositionProvider = NotifierProvider<LivePositionNotifier, LivePosition?>(LivePositionNotifier.new);

/// iOS lets people grant "approximate" location (a few km). `reduced` here
/// means every pin and distance is rounded; offer the one-time precise prompt.
final locationPrecisionProvider = FutureProvider<LocationAccuracyStatus>((ref) async {
  ref.watch(livePositionProvider.select((p) => p == null)); // re-check once the first fix lands
  try {
    return await Geolocator.getLocationAccuracy();
  } catch (_) {
    return LocationAccuracyStatus.unknown;
  }
});

/// Ask iOS for precise location for this session. Falls back to the app's
/// settings page when the prompt was already answered.
Future<bool> requestPreciseLocation() async {
  try {
    final r = await Geolocator.requestTemporaryFullAccuracy(purposeKey: 'TTSpotMap');
    if (r == LocationAccuracyStatus.precise) return true;
    await Geolocator.openAppSettings();
  } catch (_) {}
  return false;
}
