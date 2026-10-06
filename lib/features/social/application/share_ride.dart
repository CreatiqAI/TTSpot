import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/config/media.dart';
import '../../../core/supabase/supabase_client.dart';
import '../../../core/utils/friendly_error.dart';
import '../../../core/utils/http_bytes.dart';
import '../../auth/data/auth_repository.dart';
import '../../points/application/points_providers.dart';
import '../../profile/application/plate_hiding.dart' show compactBlurredPhoto;
import '../../profile/application/profile_providers.dart';
import '../../profile/domain/car.dart';
import '../../settings/application/settings_providers.dart';
import '../data/social_repository.dart';
import '../domain/post.dart';
import 'social_providers.dart';

// "Share your ride": the first-post nudge at the top of Home (For you) and on
// my empty Posts tab. Every member adds car photos at sign-up, few post. One
// tap turns the car into a normal post: its photos copied into post-photos
// (with grid thumbnails, like any upload), "My <make> <model>", the car
// tagged. The database gives 10 points for it (point_rules 'weekly_post':
// the first post of each points week, when the photo check says ok).

/// profiles.settings key: "Not now" was tapped (kept across devices).
const kShareRideDismissedKey = 'share_ride_dismissed';

/// The car to offer: my default car when it has photos, else the first one that does.
Car? shareRideCarOf(List<Car> cars) {
  Car? first;
  for (final c in cars) {
    if (c.photoUrls.isEmpty) continue;
    if (c.isDefault) return c;
    first ??= c;
  }
  return first;
}

/// The nudge shows for a car with photos, no posts of mine yet, not dismissed.
bool shouldNudgeShareRide({required Car? car, required bool hasPosts, required bool dismissed}) => car != null && !hasPosts && !dismissed;

/// "My Perodua Myvi".
String shareRideCaption(Car car) => 'My ${'${car.make} ${car.model}'.trim()}';

/// Whether "Not now" was tapped, from my profile settings.
bool shareRideDismissedIn(Map<String, dynamic>? settings) => settings?[kShareRideDismissedKey] == true;

/// What "Post it" posts.
typedef ShareRideDraft = ({String caption, String carId, List<String> photoUrls, double coverAspect});

class ShareRideRepository {
  /// [download], [upload] and [create] default to a plain GET of the public
  /// photo, [SocialRepository.uploadPhoto] and [SocialRepository.createPost].
  ShareRideRepository(
    this._client,
    SocialRepository social, {
    Future<Uint8List> Function(String url)? download,
    Future<String> Function(String me, Uint8List jpeg)? upload,
    Future<Post> Function(String me, ShareRideDraft draft)? create,
  })  : _download = download ?? downloadBytes,
        _upload = upload ?? ((me, jpeg) => social.uploadPhoto(userId: me, bytes: jpeg)),
        _create = create ??
            ((me, d) => social.createPost(authorId: me, kind: PostKind.post, caption: d.caption, photoUrls: d.photoUrls, coverAspect: d.coverAspect, carId: d.carId));
  final SupabaseClient _client;
  final Future<Uint8List> Function(String url) _download;
  final Future<String> Function(String me, Uint8List jpeg) _upload;
  final Future<Post> Function(String me, ShareRideDraft draft) _create;

  /// Do I have a post of my own (not as a club or partner)? Flagged ones count too.
  Future<bool> hasPersonalPost(String me) async {
    final rows = await _client.from('posts').select('id').eq('author_id', me).eq('as_club', false).eq('as_vendor', false).limit(1);
    return rows.isNotEmpty;
  }

  /// [car] as a normal post, through the same upload + insert path as the
  /// create screen: each photo re-uploaded to post-photos with its thumbnail,
  /// cover aspect from the first photo.
  Future<Post> share({required String me, required Car car}) async {
    final urls = <String>[];
    var aspect = 1.0;
    for (final url in car.photoUrls.take(kPostMaxPhotos)) {
      final bytes = await _download(url);
      if (urls.isEmpty) aspect = await _aspectOf(bytes);
      // uploadPhoto stores a .jpg; a PNG car photo is re-encoded (same pixels).
      final jpeg = _isPng(bytes) ? await compactBlurredPhoto(bytes) : bytes;
      urls.add(await _upload(me, jpeg));
    }
    return _create(me, (caption: shareRideCaption(car), carId: car.id, photoUrls: urls, coverAspect: aspect));
  }

  static bool _isPng(Uint8List b) => b.length > 4 && b[0] == 0x89 && b[1] == 0x50 && b[2] == 0x4E && b[3] == 0x47;

  static Future<double> _aspectOf(Uint8List bytes) async {
    try {
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final a = frame.image.width / frame.image.height;
      frame.image.dispose();
      codec.dispose();
      return a.isFinite && a > 0 ? a : 1.0;
    } catch (_) {
      return 1.0;
    }
  }
}

final shareRideRepositoryProvider = Provider<ShareRideRepository>(
  (ref) => ShareRideRepository(ref.watch(supabaseProvider), ref.watch(socialRepositoryProvider)),
);

/// The car to offer, or null when the nudge stays away (no car with photos,
/// "Not now" tapped, or I have posted already). Cheap checks first: members
/// who never see it never run the posts query.
final shareRideCarProvider = FutureProvider<Car?>((ref) async {
  final me = ref.watch(currentUserIdProvider);
  if (me == null) return null;
  final profile = await ref.watch(currentProfileProvider.future);
  if (profile == null || shareRideDismissedIn(profile.settings)) return null;
  final car = shareRideCarOf(await ref.watch(userCarsProvider(me).future));
  if (car == null) return null;
  final hasPosts = await ref.watch(shareRideRepositoryProvider).hasPersonalPost(me);
  return shouldNudgeShareRide(car: car, hasPosts: hasPosts, dismissed: false) ? car : null;
});

/// What the card is doing this session.
class ShareRideState {
  const ShareRideState({this.busy = false, this.posted, this.closed = false, this.error});
  final bool busy;

  /// Just posted: the card thanks me (with this car's photo) until Done.
  final ({String postId, Car car})? posted;

  /// "Not now" or Done: gone for this session (and "Not now" for good).
  final bool closed;
  final String? error;
}

class ShareRideController extends Notifier<ShareRideState> {
  Timer? _points;

  @override
  ShareRideState build() {
    ref.watch(currentUserIdProvider); // a new account starts fresh
    ref.onDispose(() => _points?.cancel());
    return const ShareRideState();
  }

  /// "Post it". Returns the new post's id, or null when nothing was posted
  /// (busy, signed out, already posted, or an error now in [ShareRideState.error]).
  Future<String?> post(Car car) async {
    if (state.busy) return null;
    final me = ref.read(currentUserIdProvider);
    if (me == null) return null;
    state = const ShareRideState(busy: true);
    final repo = ref.read(shareRideRepositoryProvider);
    try {
      // Posted from the create screen since the card loaded: no second "first post".
      if (await repo.hasPersonalPost(me)) {
        if (ref.mounted) state = const ShareRideState(closed: true);
        ref.invalidate(shareRideCarProvider);
        return null;
      }
      final post = await repo.share(me: me, car: car);
      if (!ref.mounted) return post.id;
      state = ShareRideState(posted: (postId: post.id, car: car));
      // Show it: my Posts tab, the For you grid (an explicit refresh is fine here).
      ref.read(socialActionsProvider).refreshPost(post.id, authorId: me);
      ref.invalidate(forYouFeedProvider);
      ref.invalidate(shareRideCarProvider);
      // The points land once the photo check says ok, a few seconds later.
      _points?.cancel();
      _points = Timer(const Duration(seconds: 8), () {
        if (ref.mounted) ref.invalidate(pointsBalanceProvider);
      });
      return post.id;
    } catch (e) {
      if (ref.mounted) state = ShareRideState(error: friendlyError(e));
      return null;
    }
  }

  /// "Not now": hidden at once, and for good once the setting is saved.
  Future<void> notNow() async {
    state = const ShareRideState(closed: true);
    try {
      await ref.read(settingsActionsProvider).patch({kShareRideDismissedKey: true});
    } catch (_) {
      // Still hidden for this session; it may ask once more next time.
    }
  }

  /// Done, after posting.
  void close() => state = const ShareRideState(closed: true);
}

final shareRideControllerProvider = NotifierProvider<ShareRideController, ShareRideState>(ShareRideController.new);
