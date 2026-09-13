import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import '../../../core/supabase/supabase_client.dart';
import '../../../core/utils/friendly_error.dart';
import '../../events/application/event_providers.dart';
import '../../friends/application/friends_providers.dart';
import '../../map/application/map_providers.dart';
import '../../social/application/notification_providers.dart';
import '../data/points_repository.dart';
import '../domain/points.dart';

/// My balance. Invalidate after anything that earns or spends.
final pointsBalanceProvider = FutureProvider<int>((ref) async {
  final me = ref.watch(currentUserIdProvider);
  if (me == null) return 0;
  return ref.watch(pointsRepositoryProvider).balance(me);
});

final pointHistoryProvider = FutureProvider<List<PointEntry>>((ref) {
  if (ref.watch(currentUserIdProvider) == null) return Future.value(const []);
  return ref.watch(pointsRepositoryProvider).history();
});

final pointRulesProvider = FutureProvider<List<PointRule>>((ref) => ref.watch(pointsRepositoryProvider).rules());

final myReferralsProvider = FutureProvider<({int total, int rewarded})>((ref) async {
  final me = ref.watch(currentUserIdProvider);
  if (me == null) return (total: 0, rewarded: 0);
  return ref.watch(pointsRepositoryProvider).myReferrals(me);
});

/// The payload for my friend QR. Refetch after [PointsActions.rotateQr].
final myQrPayloadProvider = FutureProvider<String>((ref) {
  if (ref.watch(currentUserIdProvider) == null) return Future.value('');
  return ref.watch(pointsRepositoryProvider).myQrPayload();
});

/// Result of handling a scanned code, for the scanner screen to show.
class ScanOutcome {
  const ScanOutcome({required this.title, this.subtitle, this.route, this.points = 0});
  final String title;
  final String? subtitle;
  final String? route;
  final int points;
}

class PointsActions {
  PointsActions(this._ref);
  final Ref _ref;

  PointsRepository get _repo => _ref.read(pointsRepositoryProvider);

  void refreshBalance() {
    _ref.invalidate(pointsBalanceProvider);
    _ref.invalidate(pointHistoryProvider);
  }

  Future<void> rotateQr() async {
    await _repo.rotateMyQr();
    _ref.invalidate(myQrPayloadProvider);
  }

  Future<bool> claimReferral(String code) async {
    final ok = await _repo.claimReferral(code);
    _ref.invalidate(myReferralsProvider);
    return ok;
  }

  /// Handles any TT Spot QR. Throws [AppException] with a friendly message on failure.
  Future<ScanOutcome> handle(ScannedCode code) async {
    switch (code) {
      case FriendCode(:final username, :final token):
        if (token.isEmpty) throw const AppException('That QR code is missing its key. Ask them to show it from the app.');
        final id = await _repo.addFriendByQr(username: username, token: token);
        _ref.invalidate(friendsProvider);
        _ref.invalidate(friendPinsProvider);
        _ref.invalidate(friendshipStatusProvider(id));
        _ref.invalidate(myReferralsProvider);
        return ScanOutcome(title: 'You and @$username are now friends', subtitle: 'They\'ll show up on your map.', route: '/profile/$id');
      case MeetCheckinCode(:final eventId, :final code):
        final pos = await _quickFix();
        final r = await _repo.checkinByQr(eventId: eventId, code: code, lat: pos?.latitude, lng: pos?.longitude);
        _ref.invalidate(myCheckinsProvider);
        _ref.invalidate(eventDetailProvider(eventId));
        _ref.invalidate(eventCheckedInProvider(eventId));
        _ref.invalidate(eventRecapProvider(eventId));
        _ref.invalidate(liveEventsProvider);
        _ref.invalidate(notificationsProvider);
        refreshBalance();
        return ScanOutcome(
          title: r.isNew ? 'Checked in' : 'Already checked in',
          subtitle: r.isNew ? 'You\'re on the record for this meet.' : 'You were already counted for this meet.',
          route: '/event/$eventId',
          points: r.isNew ? r.points : 0,
        );
      case SpotCode():
        throw const AppException('Spot stickers are coming soon.');
    }
  }

  Future<Position?> _quickFix() async {
    try {
      final last = await Geolocator.getLastKnownPosition();
      if (last != null && DateTime.now().difference(last.timestamp) < const Duration(minutes: 5)) return last;
      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.medium, timeLimit: Duration(seconds: 5)),
      );
    } catch (_) {
      return null;
    }
  }
}

final pointsActionsProvider = Provider<PointsActions>((ref) => PointsActions(ref));
