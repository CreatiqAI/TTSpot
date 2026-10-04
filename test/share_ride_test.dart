import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:car_meet/core/config/media.dart';
import 'package:car_meet/core/supabase/supabase_client.dart';
import 'package:car_meet/core/theme/app_theme.dart';
import 'package:car_meet/features/auth/data/auth_repository.dart';
import 'package:car_meet/features/auth/domain/profile.dart';
import 'package:car_meet/features/profile/application/profile_providers.dart';
import 'package:car_meet/features/profile/domain/car.dart';
import 'package:car_meet/features/settings/application/settings_providers.dart';
import 'package:car_meet/features/social/application/moderation_providers.dart';
import 'package:car_meet/features/social/application/share_ride.dart';
import 'package:car_meet/features/social/application/social_providers.dart';
import 'package:car_meet/features/social/data/social_repository.dart';
import 'package:car_meet/features/social/domain/post.dart';
import 'package:car_meet/features/social/presentation/explore_screen.dart';
import 'package:car_meet/features/social/presentation/widgets/masonry_grid.dart';
import 'package:car_meet/features/social/presentation/widgets/share_ride_card.dart';
import 'package:car_meet/features/social/presentation/widgets/under_review_strip.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _me = 'me-1';
const _photos = 'https://x.supabase.co/storage/v1/object/public/car-photos/$_me';

SupabaseClient _dummyClient() => SupabaseClient('http://localhost', 'test-key', authOptions: const AuthClientOptions(autoRefreshToken: false));

Car _car({String id = 'car-1', bool isDefault = true, int photos = 2, String make = 'Perodua', String model = 'Myvi'}) => Car(
      id: id,
      ownerId: _me,
      make: make,
      model: model,
      photoUrls: [for (var i = 0; i < photos; i++) '$_photos/$id-$i.jpg'],
      createdAt: DateTime(2026, 9, 20),
      isDefault: isDefault,
    );

Post _post(String id, {String? caption}) => Post(
      id: id,
      authorId: _me,
      kind: PostKind.post,
      caption: caption,
      photoUrls: const ['https://x.supabase.co/storage/v1/object/public/post-photos/me-1/posts/1.jpg'],
      coverAspect: 1,
      createdAt: DateTime(2026, 10, 5),
      likeCount: 0,
      commentCount: 0,
      voteCount: 0,
    );

/// Posts in memory: [hasPost] answers the "any posts yet?" check, [share] records the car.
class _FakeShareRepo extends ShareRideRepository {
  _FakeShareRepo({this.hasPost = false, this.fail = false}) : super(_dummyClient(), SocialRepository(_dummyClient()));
  bool hasPost;
  bool fail;
  final shared = <Car>[];

  @override
  Future<bool> hasPersonalPost(String me) async => hasPost;

  @override
  Future<Post> share({required String me, required Car car}) async {
    await Future<void>.delayed(const Duration(milliseconds: 50));
    if (fail) throw const PostgrestException(message: 'Upload failed, try again.');
    shared.add(car);
    hasPost = true;
    return _post('new-post', caption: shareRideCaption(car));
  }
}

/// One page of For you: two posts by others.
class _FakeForYou extends ForYouFeed {
  @override
  Future<ForYouState> build() async => ForYouState(
        items: [
          for (final id in const ['p1', 'p2'])
            FeedPost(post: _post(id, caption: 'Weekend run to Genting'), likedByMe: false, savedByMe: false),
        ],
        done: true,
      );
}

class _NoSignals extends FeedSignals {
  _NoSignals(super.ref);
  @override
  void seen(Iterable<String> ids) {}
  @override
  void flush() {}
}

class _FakeSettings extends SettingsActions {
  _FakeSettings(super.ref);
  final patches = <Map<String, dynamic>>[];
  @override
  Future<void> patch(Map<String, dynamic> patch) async => patches.add(patch);
}

List<Override> _overrides({required _FakeShareRepo repo, List<Car>? cars, Map<String, dynamic> settings = const {}, String? me = _me, _FakeSettings Function(Ref ref)? settingsActions}) => [
      currentUserIdProvider.overrideWith((ref) => me),
      currentProfileProvider.overrideWith((ref) async => me == null ? null : Profile(id: me, username: 'myvi_mike', createdAt: DateTime(2026, 9, 1), settings: settings)),
      userCarsProvider(_me).overrideWith((ref) async => cars ?? [_car()]),
      shareRideRepositoryProvider.overrideWithValue(repo),
      if (settingsActions != null) settingsActionsProvider.overrideWith(settingsActions),
    ];

/// The nudge on a 360 dp phone at [scale], above a stand-in feed.
Future<ProviderContainer> _pump(WidgetTester t, List<Override> overrides, {required double scale, List<String>? opened, bool hasPosts = false}) async {
  t.view.physicalSize = const Size(1080, 2400);
  t.view.devicePixelRatio = 3;
  addTearDown(t.view.reset);
  await t.pumpWidget(ProviderScope(
    key: UniqueKey(), // a fresh container per pump
    overrides: overrides,
    child: MaterialApp(
      theme: AppTheme.current,
      builder: (context, child) => MediaQuery(data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)), child: child!),
      home: Scaffold(
        body: ListView(
          children: [
            ShareRideNudge(hasPosts: hasPosts, openPost: (_, id) => opened?.add(id)),
            const SizedBox(height: 200, child: Placeholder()),
          ],
        ),
      ),
    ),
  ));
  for (var i = 0; i < 5; i++) {
    await t.pump(const Duration(milliseconds: 50));
  }
  return ProviderScope.containerOf(t.element(find.byType(ListView)));
}

void main() {
  group('rules', () {
    test('the default car with photos wins, else the first car that has photos', () {
      final plain = _car(id: 'a', isDefault: false);
      final daily = _car(id: 'b', isDefault: true);
      expect(shareRideCarOf([plain, daily])?.id, 'b');
      expect(shareRideCarOf([_car(id: 'c', isDefault: true, photos: 0), plain])?.id, 'a');
      expect(shareRideCarOf([_car(photos: 0)]), isNull);
      expect(shareRideCarOf(const []), isNull);
    });

    test('shown only for a car with photos, no posts and not dismissed', () {
      final car = _car();
      expect(shouldNudgeShareRide(car: car, hasPosts: false, dismissed: false), isTrue);
      expect(shouldNudgeShareRide(car: car, hasPosts: true, dismissed: false), isFalse);
      expect(shouldNudgeShareRide(car: car, hasPosts: false, dismissed: true), isFalse);
      expect(shouldNudgeShareRide(car: null, hasPosts: false, dismissed: false), isFalse);
    });

    test('caption and the stored "Not now"', () {
      expect(shareRideCaption(_car(make: 'Honda', model: 'Civic FD2')), 'My Honda Civic FD2');
      expect(shareRideCaption(_car(make: 'Proton', model: '')), 'My Proton');
      expect(shareRideDismissedIn({kShareRideDismissedKey: true}), isTrue);
      expect(shareRideDismissedIn(const {}), isFalse);
      expect(shareRideDismissedIn(null), isFalse);
    });
  });

  group('shareRideCarProvider', () {
    Future<Car?> read(List<Override> o) async {
      final c = ProviderContainer(overrides: o);
      addTearDown(c.dispose);
      return c.read(shareRideCarProvider.future);
    }

    test('offers my car when I have none posted', () async {
      expect((await read(_overrides(repo: _FakeShareRepo())))?.id, 'car-1');
    });
    test('nothing once I have a post', () async {
      expect(await read(_overrides(repo: _FakeShareRepo(hasPost: true))), isNull);
    });
    test('nothing after Not now (any device: it is in profiles.settings)', () async {
      expect(await read(_overrides(repo: _FakeShareRepo(), settings: {kShareRideDismissedKey: true})), isNull);
    });
    test('nothing without car photos', () async {
      expect(await read(_overrides(repo: _FakeShareRepo(), cars: [_car(photos: 0)])), isNull);
    });
    test('nothing when signed out', () async {
      expect(await read(_overrides(repo: _FakeShareRepo(), me: null)), isNull);
    });
  });

  for (final scale in const [1.0, 1.3]) {
    testWidgets('shown with my car, the offer and both buttons, no overflow ($scale)', (t) async {
      await _pump(t, _overrides(repo: _FakeShareRepo()), scale: scale);
      expect(find.byKey(const Key('share-ride-card')), findsOneWidget);
      expect(find.text('Share your ride'), findsOneWidget);
      expect(find.text('Your first post earns 50 points'), findsOneWidget);
      expect(find.text('Post it'), findsOneWidget);
      expect(find.text('Not now'), findsOneWidget);
      expect(t.takeException(), isNull);
    });

    testWidgets('hidden: already posted, dismissed, or no photos ($scale)', (t) async {
      await _pump(t, _overrides(repo: _FakeShareRepo(hasPost: true)), scale: scale);
      expect(find.byKey(const Key('share-ride-card')), findsNothing);
      await _pump(t, _overrides(repo: _FakeShareRepo(), settings: {kShareRideDismissedKey: true}), scale: scale);
      expect(find.byKey(const Key('share-ride-card')), findsNothing);
      await _pump(t, _overrides(repo: _FakeShareRepo(), cars: [_car(photos: 0)]), scale: scale);
      expect(find.byKey(const Key('share-ride-card')), findsNothing);
      // My Posts tab with posts already: nothing, even if the check is stale.
      await _pump(t, _overrides(repo: _FakeShareRepo()), scale: scale, hasPosts: true);
      expect(find.byKey(const Key('share-ride-card')), findsNothing);
      expect(t.takeException(), isNull);
    });

    testWidgets('Post it shares the car, thanks me and opens the post ($scale)', (t) async {
      final repo = _FakeShareRepo();
      final opened = <String>[];
      await _pump(t, _overrides(repo: repo), scale: scale, opened: opened);
      await t.tap(find.byKey(const Key('share-ride-post')));
      await t.pump();
      // Busy: a spinner, buttons off.
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      await t.pump(const Duration(milliseconds: 100));
      await t.pump(const Duration(milliseconds: 100));
      expect(repo.shared.single.id, 'car-1');
      expect(opened, ['new-post']);
      expect(find.text('Your ride is up'), findsOneWidget);
      expect(find.text('Your 50 points are on the way'), findsOneWidget);
      expect(find.text('View post'), findsOneWidget);
      expect(t.takeException(), isNull);
      // View post opens it again; Done closes the card.
      await t.tap(find.text('View post'));
      expect(opened, ['new-post', 'new-post']);
      await t.tap(find.text('Done'));
      await t.pump();
      expect(find.byKey(const Key('share-ride-card')), findsNothing);
      await t.pump(const Duration(seconds: 9)); // the points refresh timer
    });

    testWidgets('a failed post keeps the card with the error ($scale)', (t) async {
      final repo = _FakeShareRepo(fail: true);
      await _pump(t, _overrides(repo: repo), scale: scale);
      await t.tap(find.byKey(const Key('share-ride-post')));
      await t.pump(const Duration(milliseconds: 100));
      await t.pump(const Duration(milliseconds: 100));
      expect(find.text('Share your ride'), findsOneWidget);
      expect(find.textContaining('Upload failed'), findsOneWidget);
      expect(find.text('Post it'), findsOneWidget);
      expect(t.takeException(), isNull);
    });

    testWidgets('Not now hides it and saves it to my settings ($scale)', (t) async {
      final repo = _FakeShareRepo();
      late _FakeSettings settings;
      await _pump(t, _overrides(repo: repo, settingsActions: (ref) => settings = _FakeSettings(ref)), scale: scale);
      await t.tap(find.byKey(const Key('share-ride-not-now')));
      await t.pump();
      expect(find.byKey(const Key('share-ride-card')), findsNothing);
      expect(settings.patches, [
        {kShareRideDismissedKey: true},
      ]);
      expect(repo.shared, isEmpty);
    });
  }

  for (final scale in const [1.0, 1.3]) {
    testWidgets('Home: on top of For you, not on Following, no overflow ($scale)', (t) async {
      t.view.physicalSize = const Size(1080, 2400);
      t.view.devicePixelRatio = 3;
      addTearDown(t.view.reset);
      await t.pumpWidget(ProviderScope(
        overrides: [
          ..._overrides(repo: _FakeShareRepo()),
          forYouFeedProvider.overrideWith(_FakeForYou.new),
          followingFeedProvider.overrideWith((ref) async => const <FeedPost>[]),
          feedSignalsProvider.overrideWith((ref) => _NoSignals(ref)),
        ],
        child: MaterialApp(
          theme: AppTheme.current,
          builder: (context, child) => MediaQuery(data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)), child: child!),
          home: const ExploreScreen(),
        ),
      ));
      for (var i = 0; i < 6; i++) {
        await t.pump(const Duration(milliseconds: 50));
      }
      final card = find.byKey(const Key('share-ride-card'));
      expect(card, findsOneWidget);
      // Above the grid: under the For you / Following chips, before the first tile.
      expect(t.getTopLeft(card).dy, lessThan(t.getTopLeft(find.byType(PostTile).first).dy));
      expect(t.getTopLeft(card).dy, greaterThan(t.getTopLeft(find.text('For you')).dy));
      expect(t.takeException(), isNull);
      await t.tap(find.text('Following'));
      await t.pump(const Duration(milliseconds: 200));
      expect(card, findsNothing);
      expect(t.takeException(), isNull);
    });
  }

  testWidgets('Post it after posting from the create screen: no second post', (t) async {
    final repo = _FakeShareRepo();
    final opened = <String>[];
    await _pump(t, _overrides(repo: repo), scale: 1.0, opened: opened);
    repo.hasPost = true; // posted elsewhere since the card loaded
    await t.tap(find.byKey(const Key('share-ride-post')));
    await t.pump(const Duration(milliseconds: 100));
    expect(repo.shared, isEmpty);
    expect(opened, isEmpty);
    expect(find.byKey(const Key('share-ride-card')), findsNothing);
  });

  group('ShareRideRepository.share', () {
    testWidgets('re-uploads every photo, cover aspect from the first, caption and car tagged', (t) async {
      // A real 400 x 300 PNG, so the aspect comes from actual pixels.
      final png = await t.runAsync(() async {
        final rec = ui.PictureRecorder();
        Canvas(rec).drawRect(const Rect.fromLTWH(0, 0, 400, 300), Paint()..color = const Color(0xFFE00008));
        final img = await rec.endRecording().toImage(400, 300);
        final data = await img.toByteData(format: ui.ImageByteFormat.png);
        return data!.buffer.asUint8List();
      });
      final downloads = <String>[];
      final uploads = <({String me, Uint8List bytes})>[];
      ShareRideDraft? draft;
      final repo = ShareRideRepository(
        _dummyClient(),
        SocialRepository(_dummyClient()),
        download: (url) async {
          downloads.add(url);
          return png!;
        },
        upload: (me, bytes) async {
          uploads.add((me: me, bytes: bytes));
          return 'u${uploads.length - 1}';
        },
        create: (me, d) async {
          draft = d;
          return _post('created', caption: d.caption);
        },
      );
      final car = _car(photos: 3);
      final post = await t.runAsync(() => repo.share(me: _me, car: car));
      expect(downloads, car.photoUrls);
      expect(uploads.map((u) => u.me), [_me, _me, _me]);
      expect(draft!.caption, 'My Perodua Myvi');
      expect(draft!.carId, 'car-1');
      expect(draft!.photoUrls, ['u0', 'u1', 'u2']);
      expect(draft!.coverAspect, closeTo(400 / 300, 0.001));
      expect(post!.id, 'created');
    });

    testWidgets('at most $kPostMaxPhotos photos, like the create screen', (t) async {
      var n = 0;
      final repo = ShareRideRepository(
        _dummyClient(),
        SocialRepository(_dummyClient()),
        download: (_) async => Uint8List.fromList(const [0xFF, 0xD8, 0xFF, 0xE0]), // a JPEG head: no re-encode
        upload: (_, _) async => 'u${n++}',
        create: (me, d) async => _post('x', caption: d.caption),
      );
      await t.runAsync(() => repo.share(me: _me, car: _car(photos: 14)));
      expect(n, kPostMaxPhotos);
    });
  });

  group('Under review on my Posts tab', () {
    test('states from the database', () {
      expect(ModerationState.fromDb('flagged').hidden, isTrue);
      expect(ModerationState.fromDb('removed').hidden, isTrue);
      expect(ModerationState.fromDb('pending').hidden, isFalse);
      expect(ModerationState.fromDb('ok').hidden, isFalse);
      expect(ModerationState.fromDb(null), ModerationState.ok);
    });

    for (final scale in const [1.0, 1.3]) {
      testWidgets('labels only my hidden posts, no overflow ($scale)', (t) async {
        t.view.physicalSize = const Size(1080, 2400);
        t.view.devicePixelRatio = 3;
        addTearDown(t.view.reset);
        await t.pumpWidget(MaterialApp(
          theme: AppTheme.current,
          builder: (context, child) => MediaQuery(data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)), child: child!),
          home: Scaffold(
            body: UnderReviewStrip(
              posts: [_post('a', caption: 'My Honda Civic FD2 at the Genting meet last night, long caption'), _post('b'), _post('c')],
              states: const {'a': ModerationState.flagged, 'c': ModerationState.removed},
            ),
          ),
        ));
        await t.pump(const Duration(milliseconds: 50));
        expect(find.byKey(const Key('under-review-a')), findsOneWidget);
        expect(find.byKey(const Key('under-review-b')), findsNothing);
        expect(find.text('Under review'), findsOneWidget);
        expect(find.text('Removed'), findsOneWidget);
        expect(find.text('Only you can see this until our team checks it.'), findsOneWidget);
        expect(t.takeException(), isNull);
      });
    }
  });
}
