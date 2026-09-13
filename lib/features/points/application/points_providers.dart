import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/supabase/supabase_client.dart';
import '../../../core/utils/friendly_error.dart';
import '../../events/application/event_providers.dart';
import '../../friends/application/friends_providers.dart';
import '../../map/application/map_providers.dart';
import '../../social/application/notification_providers.dart';
import '../../social/application/community_providers.dart';
import '../../social/application/social_providers.dart';
import '../../vendors/application/vendors_providers.dart';
import '../data/points_repository.dart';
import '../domain/points.dart';
import '../domain/verification.dart';

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

/// My sticker check-ins (pending / review / decided).
final myVerificationsProvider = FutureProvider<List<SpotVerification>>((ref) {
  if (ref.watch(currentUserIdProvider) == null) return Future.value(const []);
  return ref.watch(pointsRepositoryProvider).myVerifications();
});

/// Admin: what needs a human.
final adminReviewQueueProvider = FutureProvider<List<SpotVerification>>((ref) {
  ref.watch(currentUserIdProvider); // never show the previous admin's queue after a user switch
  return ref.watch(pointsRepositoryProvider).adminQueue();
});

/// Result of handling a scanned code, for the scanner screen to show.
/// [silent] = don't show a dialog, just go to [route].
class ScanOutcome {
  const ScanOutcome({required this.title, this.subtitle, this.route, this.points = 0, this.silent = false});
  final String title;
  final String? subtitle;
  final String? route;
  final int points;
  final bool silent;
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
      case SpotCode(:final placeId, :final code):
        return ScanOutcome(title: 'Spot sticker', route: '/spot/$placeId/verify?code=$code', silent: true);
      case VoucherCode(:final claimId, :final code):
        final vendor = await _ref.read(myVendorProvider.future);
        if (vendor == null) {
          throw const AppException('That\'s a member\'s voucher. Only the partner shop can scan it at the counter.');
        }
        return ScanOutcome(title: 'Voucher', route: '/vendor/redeem/$claimId?code=$code', silent: true);
    }
  }

  /// Sticker flow: upload the proof, create the pending row, run the AI check.
  Future<VerifyResult> verifySpot({required String placeId, required String code, required XFile photo, void Function(String stage)? onStage}) async {
    final me = _ref.read(currentUserIdProvider);
    if (me == null) throw const AppException('You\'re signed out. Sign in again.');
    onStage?.call('Uploading photo…');
    final url = await _repo.uploadProof(userId: me, bytes: await photo.readAsBytes());
    onStage?.call('Getting your location…');
    final pos = await _quickFix();
    onStage?.call('Checking the photo…');
    final id = await _repo.submitVerification(placeId: placeId, code: code, photoUrl: url, lat: pos?.latitude, lng: pos?.longitude);
    final result = await _repo.runVerification(id);
    _ref.invalidate(myVerificationsProvider);
    if (result.status == VerificationStatus.approved) {
      refreshBalance();
      _ref.invalidate(placeProvider(placeId));
      _ref.invalidate(placeMomentsProvider(placeId));
      _ref.invalidate(placeRegularsProvider(placeId));
      _ref.invalidate(placeRecentVisitorsProvider(placeId));
      _ref.invalidate(myPlaceCheckinTodayProvider(placeId));
      _ref.invalidate(topSpotsProvider);
      _ref.invalidate(notificationsProvider);
    }
    return result;
  }

  Future<void> review(String id, {required bool approve, String? note}) async {
    await _repo.reviewVerification(id, approve: approve, note: note);
    _ref.invalidate(adminReviewQueueProvider);
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
