import 'package:car_meet/core/guide/guide.dart';
import 'package:car_meet/core/guide/guide_controller.dart';
import 'package:car_meet/core/supabase/supabase_client.dart';
import 'package:car_meet/core/theme/app_theme.dart';
import 'package:car_meet/features/accounts/application/active_account.dart';
import 'package:car_meet/features/auth/data/auth_repository.dart';
import 'package:car_meet/features/auth/domain/profile.dart';
import 'package:car_meet/features/friends/application/friends_providers.dart';
import 'package:car_meet/features/friends/application/nicknames.dart';
import 'package:car_meet/features/friends/domain/friend.dart';
import 'package:car_meet/features/guides/home_guides.dart';
import 'package:car_meet/features/safety/data/safety_repository.dart';
import 'package:car_meet/features/settings/application/settings_providers.dart';
import 'package:car_meet/features/social/application/chat_providers.dart';
import 'package:car_meet/features/social/application/notification_providers.dart';
import 'package:car_meet/features/social/application/share_ride.dart';
import 'package:car_meet/features/social/application/social_providers.dart';
import 'package:car_meet/features/social/domain/club.dart';
import 'package:car_meet/features/social/domain/post.dart';
import 'package:car_meet/features/social/presentation/create_hub_sheet.dart';
import 'package:car_meet/features/social/presentation/explore_screen.dart';
import 'package:car_meet/features/social/presentation/inbox_screen.dart';
import 'package:car_meet/features/titi/application/titi_controller.dart';
import 'package:car_meet/features/titi/presentation/titi_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

// TiTi guides for Home, the + sheet, Chats and the TiTi chat
// (docs/titi-guides-plan.md, lib/features/guides/home_guides.dart).

const _me = 'me-1';

/// Records the guides asked for; never draws anything.
class _FakeGuides extends GuideController {
  _FakeGuides(super.ref);
  final shown = <Guide>[];

  @override
  bool seen(String id) => false;

  @override
  Future<GuideResult> showOnce(BuildContext context, Guide guide, {bool force = false}) async {
    shown.add(guide);
    return GuideResult.finished;
  }
}

Post _post(String id) => Post(
      id: id,
      authorId: 'u-2',
      kind: PostKind.post,
      caption: 'Weekend run to Genting',
      photoUrls: const ['https://x.supabase.co/storage/v1/object/public/post-photos/u-2/posts/1.jpg'],
      coverAspect: 1,
      createdAt: DateTime(2026, 10, 5),
      likeCount: 3,
      commentCount: 0,
      voteCount: 0,
    );

class _FakeForYou extends ForYouFeed {
  _FakeForYou(this.ids);
  final List<String> ids;
  @override
  Future<ForYouState> build() async => ForYouState(items: [for (final id in ids) FeedPost(post: _post(id), likedByMe: false, savedByMe: false)], done: true);
}

class _NoSignals extends FeedSignals {
  _NoSignals(super.ref);
  @override
  void seen(Iterable<String> ids) {}
  @override
  void flush() {}
}

class _FakeSettings extends SettingsNotifier {
  @override
  AppSettings build() => AppSettings(const {});
}

class _FakeTiti extends TitiController {
  @override
  TitiState build() => const TitiState(loading: false);
  @override
  Future<void> ensureLatest() async {}
}

final _club = Club(id: 'c1', name: 'Myvi Owners KL', handle: 'myvi_kl', ownerId: 'u1', createdAt: DateTime(2026), memberCount: 12);

Future<_FakeGuides> _pump(WidgetTester t, Widget home, {List<Override> overrides = const [], double scale = 1.0}) async {
  t.view.physicalSize = const Size(1080, 2400);
  t.view.devicePixelRatio = 3;
  addTearDown(t.view.reset);
  late _FakeGuides guides;
  await t.pumpWidget(ProviderScope(
    key: UniqueKey(),
    overrides: [
      currentUserIdProvider.overrideWithValue(_me),
      guideControllerProvider.overrideWith((ref) => guides = _FakeGuides(ref)),
      ...overrides,
    ],
    child: MaterialApp(
      theme: AppTheme.current,
      builder: (context, child) => MediaQuery(data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)), child: child!),
      home: home,
    ),
  ));
  for (var i = 0; i < 8; i++) {
    await t.pump(const Duration(milliseconds: 50));
  }
  // Built lazily: the gate / trigger read it. Make sure it exists.
  ProviderScope.containerOf(t.element(find.byType(MaterialApp))).read(guideControllerProvider);
  return guides;
}

List<Override> _homeOverrides(List<String> ids) => [
      forYouFeedProvider.overrideWith(() => _FakeForYou(ids)),
      followingFeedProvider.overrideWith((ref) async => const <FeedPost>[]),
      feedSignalsProvider.overrideWith((ref) => _NoSignals(ref)),
      shareRideCarProvider.overrideWith((ref) async => null),
    ];

final _me1 = Profile(id: _me, displayName: 'Me Myself', username: 'me_myself', createdAt: DateTime(2026));

List<Override> get _inboxOverrides => [
      inboxProvider.overrideWith((ref) async => const []),
      friendsProvider.overrideWith((ref) async => const <Profile>[]),
      friendPinsProvider.overrideWith((ref) => Stream.value(const <FriendPin>[])),
      storiesProvider.overrideWith((ref) async => const <StoryGroup>[]),
      currentProfileProvider.overrideWith((ref) async => _me1),
      unreadNotificationsProvider.overrideWith((ref) => Stream.value(0)),
      nicknamesProvider.overrideWithValue(const {}),
      settingsProvider.overrideWith(_FakeSettings.new),
      blockedUserIdsProvider.overrideWith((ref) async => <String>{}),
    ];

int _words(String s) => s.trim().split(RegExp(r'\s+')).length;

void main() {
  group('guide definitions', () {
    final all = <Guide>[
      homeGuide(hasPost: true),
      homeGuide(hasPost: false),
      createGuide(),
      createGuide(social: false),
      chatsGuide(),
      titiChatGuide(starters: true),
      titiChatGuide(starters: false),
    ];

    test('the right ids, all of them known', () {
      expect(homeGuide(hasPost: true).id, GuideIds.home);
      expect(createGuide().id, GuideIds.create);
      expect(chatsGuide().id, GuideIds.chats);
      expect(titiChatGuide(starters: true).id, GuideIds.titiChat);
      for (final g in all) {
        expect(GuideIds.all, contains(g.id));
      }
    });

    test('2 to 4 steps each (TiTi chat: 1 or 2), every step points at something', () {
      for (final g in all) {
        final min = g.id == GuideIds.titiChat ? 1 : 2;
        expect(g.steps.length, inInclusiveRange(min, 4), reason: g.id);
        for (final s in g.steps) {
          expect(s.target, isNotNull, reason: '${g.id}: ${s.title}');
          expect(s.tapTarget, isFalse, reason: 'Next-only guides');
        }
      }
    });

    test('short copy: titles <= 40 chars and 2-5 words, bodies <= 110 chars and <= 18 words', () {
      for (final g in all) {
        for (final s in g.steps) {
          expect(s.title.length, lessThanOrEqualTo(40), reason: s.title);
          expect(_words(s.title), inInclusiveRange(2, 5), reason: s.title);
          expect(s.body.length, lessThanOrEqualTo(110), reason: s.body);
          expect(_words(s.body), lessThanOrEqualTo(18), reason: s.body);
        }
      }
    });

    test('home: the post step only with a post on screen', () {
      expect(homeGuide(hasPost: true).steps.map((s) => s.target), [HomeGuideKeys.feedSwitch, HomeGuideKeys.clubsEvents, HomeGuideKeys.firstPost, HomeGuideKeys.search]);
      expect(homeGuide(hasPost: false).steps.map((s) => s.target), [HomeGuideKeys.feedSwitch, HomeGuideKeys.clubsEvents, HomeGuideKeys.search]);
      // Nothing mounted: decided from the key.
      expect(homeGuide().steps.length, 3);
    });

    test('create: TT now first, then everything else', () {
      final g = createGuide();
      expect(g.steps.first.target, CreateGuideKeys.ttNow);
      expect(g.steps.first.title, 'TT now');
      expect(g.steps.first.body, contains('teh tarik'));
      expect(g.steps.last.target, CreateGuideKeys.make);
      expect(createGuide(social: false).steps.last.body, isNot(contains('Post')));
    });

    test('chats: TiTi then Activity; TiTi chat: input, then starters while empty', () {
      expect(chatsGuide().steps.map((s) => s.target), [ChatsGuideKeys.titi, ChatsGuideKeys.activity]);
      expect(titiChatGuide(starters: true).steps.map((s) => s.target), [TitiChatGuideKeys.input, TitiChatGuideKeys.starters]);
      expect(titiChatGuide(starters: false).steps.map((s) => s.target), [TitiChatGuideKeys.input]);
    });
  });

  group('screens build with a fake guide controller', () {
    for (final scale in const [1.0, 1.3]) {
      testWidgets('Home: keys on the feed switch, Clubs & Events, first post, search ($scale)', (t) async {
        await _pump(t, const ExploreScreen(), overrides: _homeOverrides(['p1', 'p2', 'p3']), scale: scale);
        expect(find.text('For you'), findsOneWidget);
        expect(t.takeException(), isNull);
        for (final k in [HomeGuideKeys.feedSwitch, HomeGuideKeys.clubsEvents, HomeGuideKeys.firstPost, HomeGuideKeys.search]) {
          expect(k.currentContext, isNotNull, reason: '$k');
        }
        // The first tile is the post the key sits on.
        expect(find.descendant(of: find.byKey(HomeGuideKeys.firstPost), matching: find.text('Weekend run to Genting')), findsOneWidget);
        expect(homeGuide().steps.length, 4, reason: 'a post is on screen');
      });
    }

    testWidgets('Home with an empty feed: no post step', (t) async {
      await _pump(t, const ExploreScreen(), overrides: _homeOverrides(const []));
      expect(find.text('Nothing here yet'), findsOneWidget);
      expect(HomeGuideKeys.firstPost.currentContext, isNull);
      expect(homeGuide().steps.map((s) => s.target), isNot(contains(HomeGuideKeys.firstPost)));
      expect(t.takeException(), isNull);
    });

    for (final scale in const [1.0, 1.3]) {
      testWidgets('Chats: TiTi row and the Activity tab carry the keys ($scale)', (t) async {
        await _pump(t, const InboxScreen(), overrides: _inboxOverrides, scale: scale);
        expect(find.text('TiTi'), findsOneWidget);
        expect(find.text('Activity'), findsOneWidget);
        expect(ChatsGuideKeys.titi.currentContext, isNotNull);
        expect(ChatsGuideKeys.activity.currentContext, isNotNull);
        expect(find.descendant(of: find.byKey(ChatsGuideKeys.titi), matching: find.text('TiTi')), findsOneWidget);
        expect(t.takeException(), isNull);
      });

      testWidgets('TiTi chat: the input and the starters carry the keys ($scale)', (t) async {
        await _pump(t, const TitiScreen(), overrides: [titiControllerProvider.overrideWith(_FakeTiti.new)], scale: scale);
        expect(find.text('Fuel price this week'), findsOneWidget);
        expect(TitiChatGuideKeys.input.currentContext, isNotNull);
        expect(TitiChatGuideKeys.starters.currentContext, isNotNull);
        expect(find.descendant(of: find.byKey(TitiChatGuideKeys.starters), matching: find.text('Fuel price this week')), findsOneWidget);
        expect(t.takeException(), isNull);
      });
    }
  });

  group('the + sheet', () {
    Widget opener() => Scaffold(
          body: Consumer(
            builder: (context, ref, _) => Center(child: TextButton(onPressed: () => showCreateHub(context, ref), child: const Text('open'))),
          ),
        );

    testWidgets('first open: the create guide once the sheet has slid in, and the sheet keeps working', (t) async {
      final guides = await _pump(t, opener());
      await t.tap(find.text('open'));
      await t.pump(); // the sheet starts sliding in
      await t.pump(const Duration(milliseconds: 50));
      expect(guides.shown, isEmpty, reason: 'not while it is still moving');
      await t.pumpAndSettle();
      await t.pump(const Duration(milliseconds: 300));
      expect(guides.shown.map((g) => g.id), [GuideIds.create]);
      expect(CreateGuideKeys.ttNow.currentContext, isNotNull);
      expect(CreateGuideKeys.make.currentContext, isNotNull);
      expect(find.descendant(of: find.byKey(CreateGuideKeys.ttNow), matching: find.text('TT NOW')), findsOneWidget);
      expect(find.descendant(of: find.byKey(CreateGuideKeys.make), matching: find.text('Plan a TT session')), findsOneWidget);
      // Still a working sheet: More opens in place.
      await t.tap(find.byKey(const Key('create-more')));
      await t.pumpAndSettle();
      expect(find.text('Suggest a spot'), findsOneWidget);
      expect(guides.shown, hasLength(1), reason: 'once per open, not per rebuild');
      expect(t.takeException(), isNull);
    });

    testWidgets('a club account: no create guide (no TT now there)', (t) async {
      final guides = await _pump(t, opener());
      ProviderScope.containerOf(t.element(find.byType(MaterialApp))).read(activeAccountProvider.notifier).set(ClubAccount(_club));
      await t.tap(find.text('open'));
      await t.pumpAndSettle();
      await t.pump(const Duration(milliseconds: 300));
      expect(find.text('Club meet'), findsOneWidget);
      expect(guides.shown, isEmpty);
      expect(t.takeException(), isNull);
    });
  });
}
