import 'dart:async';

import 'package:car_meet/core/supabase/supabase_client.dart';
import 'package:car_meet/core/theme/app_theme.dart';
import 'package:car_meet/features/auth/domain/profile.dart';
import 'package:car_meet/features/events/domain/event.dart';
import 'package:car_meet/features/friends/application/nicknames.dart';
import 'package:car_meet/features/friends/domain/friend.dart';
import 'package:car_meet/features/profile/domain/car.dart';
import 'package:car_meet/features/profile/presentation/widgets/profile_header.dart';
import 'package:car_meet/features/social/application/community_providers.dart';
import 'package:car_meet/features/social/application/social_providers.dart';
import 'package:car_meet/features/social/data/social_repository.dart';
import 'package:car_meet/features/social/domain/club.dart';
import 'package:car_meet/features/social/domain/follow.dart';
import 'package:car_meet/features/social/domain/post.dart';
import 'package:car_meet/features/social/presentation/club_screen.dart';
import 'package:car_meet/features/vendors/domain/vendor.dart';
import 'package:car_meet/features/vendors/presentation/widgets/partner_tabs.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// ------------------------------------------------------------- fakes ---

/// Follows kept in memory. [gate] holds the next follow / unfollow until it
/// completes; [fail] makes them throw.
class _FakeSocial extends SocialRepository {
  // Never reaches the network; no token refresh timer left running.
  _FakeSocial() : super(SupabaseClient('http://localhost', 'test-key', authOptions: const AuthClientOptions(autoRefreshToken: false)));

  final followed = <FollowTarget>{};
  final counts = <FollowTarget, int>{};
  final asked = <FollowTarget>[];
  Completer<void>? gate;
  bool fail = false;

  Future<void> _wait() async {
    final g = gate;
    if (g != null) await g.future;
    if (fail) throw Exception('No connection');
  }

  @override
  Future<bool> isFollowingTarget(String me, FollowTarget t) async {
    asked.add(t);
    return followed.contains(t);
  }

  @override
  Future<void> followTarget(String me, FollowTarget t) async {
    await _wait();
    if (followed.add(t)) counts[t] = (counts[t] ?? 0) + 1;
  }

  @override
  Future<void> unfollowTarget(String me, FollowTarget t) async {
    await _wait();
    if (followed.remove(t)) counts[t] = (counts[t] ?? 1) - 1;
  }

  @override
  Future<int> followerCount(FollowTarget t) async => counts[t] ?? 0;
}

const FollowTarget _club = (kind: FollowKind.club, id: 'c1');
const FollowTarget _keith = (kind: FollowKind.person, id: 'u-keith');

final _profile = Profile(id: 'u-keith', username: 'keith_ek9', displayName: 'Keith Lim', createdAt: DateTime(2026));

final _crew = Club(
  id: 'c1',
  name: 'TT Spot Crew',
  handle: 'ttspot_crew',
  description: 'Weekly mamak runs.',
  // No logo: the crest asset, no network image.
  homeState: 'Selangor',
  ownerId: 'u-owner',
  createdAt: DateTime(2026),
  memberCount: 12,
);

// No lat/lng (no map), no photos and no logo URL (no network images).
const _shop = PublicVendor(id: 'v-1', name: 'Garage 21 Performance', type: 'workshop', phone: '+60 12-345 6789');

/// A 360 x 800 phone (the narrowest we design for) at [scale].
Future<void> _pump(WidgetTester t, Widget child, {double scale = 1, List overrides = const [], bool scaffold = true}) async {
  t.view.physicalSize = const Size(1080, 2400);
  t.view.devicePixelRatio = 3;
  addTearDown(t.view.reset);
  await t.pumpWidget(ProviderScope(
    retry: (_, _) => null,
    overrides: [nicknamesProvider.overrideWithValue(const <String, String>{}), ...overrides.cast()],
    child: MaterialApp(
      theme: AppTheme.current,
      builder: (context, c) => MediaQuery(data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)), child: c!),
      home: scaffold ? Scaffold(body: SingleChildScrollView(child: child)) : child,
    ),
  ));
  await t.pump();
  expect(t.takeException(), isNull);
}

Widget _header({bool isMe = false, FriendshipStatus friendship = FriendshipStatus.none, bool? following = false, VoidCallback? onFollow, VoidCallback? onCall}) => ProfileHeader(
      profile: _profile,
      isMe: isMe,
      cars: const <Car>[],
      stats: const ProfileStats(cars: 1, organised: 0, attended: 3, went: 2),
      friendCount: 14,
      points: null,
      moments: const <Story>[],
      friendship: friendship,
      onMeets: () {},
      onFriends: null,
      onPoints: () {},
      onEdit: () {},
      onRewards: () {},
      onQr: () {},
      onAvatar: () {},
      onGarage: () {},
      onFriendAction: () {},
      onMessage: () {},
      onCall: onCall,
      following: following,
      onFollow: onFollow,
    );

Widget _partner({bool? following = false, int? followers, VoidCallback? onFollow}) => Scaffold(
      body: PartnerPageView(
        vendor: _shop,
        products: const <Product>[],
        vouchers: const <Voucher>[],
        posts: const <FeedPost>[],
        events: const <Event>[],
        onMessage: () {},
        following: following,
        followers: followers,
        onFollow: onFollow,
      ),
    );

/// [text] inside a [T] (also subclasses, e.g. FilledButton.icon's).
Finder _inside<T>(String text) => find.ancestor(of: find.text(text), matching: find.byWidgetPredicate((w) => w is T));

/// Scrolls [text] into view and taps it.
Future<void> _tap(WidgetTester t, String text) async {
  await t.ensureVisible(find.text(text));
  await t.pumpAndSettle();
  await t.tap(find.text(text));
}

/// The club page, its data faked. [member] and [me] pick who is looking
/// ('u-owner' is the club's owner).
List _clubOverrides(_FakeSocial social, {bool member = false, String me = 'u-me'}) => [
      currentUserIdProvider.overrideWithValue(me),
      socialRepositoryProvider.overrideWithValue(social),
      clubProvider('c1').overrideWith((ref) async => _crew),
      isClubMemberProvider('c1').overrideWith((ref) async => member),
      clubMembersProvider('c1').overrideWith((ref) async => const <Profile>[]),
      clubMemberRolesProvider('c1').overrideWith((ref) async => const <String, String>{}),
      clubEventsProvider('c1').overrideWith((ref) async => const <Event>[]),
      postsWhereProvider((column: 'club_id', value: 'c1')).overrideWith((ref) async => const <FeedPost>[]),
      myClubInviteProvider('c1').overrideWith((ref) async => null),
      myClubInviteRoleProvider('c1').overrideWith((ref) async => null),
      myClubShareProvider('c1').overrideWith((ref) async => true),
      myClubRequestProvider('c1').overrideWith((ref) async => null),
      clubLeaderboardProvider('c1').overrideWith((ref) async => const <ClubLeader>[]),
      clubJoinRequestsProvider('c1').overrideWith((ref) async => const <ClubJoinRequest>[]),
    ];

void main() {
  test('followersLabel', () {
    expect(followersLabel(0), '0 followers');
    expect(followersLabel(1), '1 follower');
    expect(followersLabel(128), '128 followers');
    expect(followersLabel(1204), '1,204 followers');
  });

  group('FollowNotifier', () {
    ProviderContainer container(_FakeSocial social, {String? me = 'u-me'}) {
      final c = ProviderContainer(retry: (_, _) => null, overrides: [
        socialRepositoryProvider.overrideWithValue(social),
        currentUserIdProvider.overrideWithValue(me),
      ]);
      addTearDown(c.dispose);
      c.listen(followProvider(_club), (_, _) {});
      return c;
    }

    test('flips at once, then the server answers and the count follows', () async {
      final social = _FakeSocial()..counts[_club] = 2;
      final c = container(social);
      expect(await c.read(followProvider(_club).future), isFalse);
      expect(await c.read(followerCountProvider(_club).future), 2);

      social.gate = Completer();
      final done = c.read(followProvider(_club).notifier).toggle();
      expect(c.read(followProvider(_club)).value, isTrue, reason: 'optimistic: Following before the server answers');
      // A second tap while the first is under way does nothing.
      await c.read(followProvider(_club).notifier).toggle();
      expect(c.read(followProvider(_club)).value, isTrue);
      social.gate!.complete();
      await done;
      expect(c.read(followProvider(_club)).value, isTrue);
      expect(social.followed, contains(_club));
      expect(await c.read(followerCountProvider(_club).future), 3);
    });

    test('a failed unfollow puts Following back and rethrows', () async {
      final social = _FakeSocial()..followed.add(_club);
      final c = container(social);
      expect(await c.read(followProvider(_club).future), isTrue);
      social.fail = true;
      await expectLater(c.read(followProvider(_club).notifier).toggle(), throwsException);
      expect(c.read(followProvider(_club)).value, isTrue);
      expect(social.followed, contains(_club));
    });

    test('never follows myself, never asks the server', () async {
      final social = _FakeSocial();
      final c = container(social, me: 'u-keith');
      expect(await c.read(followProvider(_keith).future), isFalse);
      expect(social.asked, isNot(contains(_keith)));
    });
  });

  for (final scale in [1.0, 1.3]) {
    group('text x$scale', () {
      // ------------------------------------------------------ profile ---
      testWidgets('profile: Add friend · Follow · Message for someone who is not my friend', (t) async {
        var taps = 0;
        await _pump(t, _header(onFollow: () => taps++), scale: scale);
        expect(find.text('Add friend'), findsOneWidget);
        expect(find.text('Follow'), findsOneWidget);
        expect(find.text('Following'), findsNothing);
        expect(find.text('Message'), findsOneWidget);
        // Left to right, the same width each.
        final add = t.getRect(find.ancestor(of: find.text('Add friend'), matching: find.byType(Material)).first);
        final follow = t.getRect(find.ancestor(of: find.text('Follow'), matching: find.byType(Material)).first);
        final message = t.getRect(find.ancestor(of: find.text('Message'), matching: find.byType(Material)).first);
        expect(add.right, lessThan(follow.left));
        expect(follow.right, lessThan(message.left));
        expect(follow.width, moreOrLessEquals(add.width, epsilon: 0.5));
        // Follow in brand red on a red tint; three across, text only.
        final pill = t.widget<Material>(find.ancestor(of: find.text('Follow'), matching: find.byType(Material)).first);
        expect(pill.color, AppColors.brand.withValues(alpha: 0.1));
        expect(find.byType(Icon), findsNothing);
        await t.tap(find.text('Follow'));
        expect(taps, 1);
      });

      testWidgets('profile: Following once I follow, beside Add friend or Requested', (t) async {
        for (final f in [FriendshipStatus.none, FriendshipStatus.pendingOut]) {
          await _pump(t, _header(friendship: f, following: true, onFollow: () {}), scale: scale);
          expect(find.text('Following'), findsOneWidget, reason: '$f');
          expect(t.widget<Material>(find.ancestor(of: find.text('Following'), matching: find.byType(Material)).first).color, AppColors.surfaceGray);
          expect(find.text('Follow'), findsNothing);
          expect(find.text(f == FriendshipStatus.pendingOut ? 'Requested' : 'Add friend'), findsOneWidget);
          expect(find.text('Message'), findsOneWidget);
        }
      });

      testWidgets('profile: while they wait for me, just Accept request and Message', (t) async {
        await _pump(t, _header(friendship: FriendshipStatus.pendingIn, onFollow: () {}), scale: scale);
        expect(find.text('Accept request'), findsOneWidget);
        expect(find.text('Message'), findsOneWidget);
        expect(find.text('Follow'), findsNothing);
        expect(find.text('Following'), findsNothing);
      });

      testWidgets('profile: no Follow for friends, on my own page, or when hidden', (t) async {
        await _pump(t, _header(friendship: FriendshipStatus.friends, onFollow: () {}, onCall: () {}), scale: scale);
        expect(find.text('Friends'), findsNWidgets(2)); // the count's label and the button
        expect(find.text('Call'), findsOneWidget);
        expect(find.text('Follow'), findsNothing);
        expect(find.text('Following'), findsNothing);

        await _pump(t, _header(isMe: true, onFollow: () {}), scale: scale);
        expect(find.text('Edit profile'), findsOneWidget);
        expect(find.text('Follow'), findsNothing);

        // Someone I blocked: the screen passes no onFollow.
        await _pump(t, _header(), scale: scale);
        expect(find.text('Add friend'), findsOneWidget);
        expect(find.text('Follow'), findsNothing);
      });

      // ------------------------------------------------------ partner ---
      testWidgets('partner page: red Follow beside Message, follower chip', (t) async {
        var taps = 0;
        await _pump(t, _partner(followers: 128, onFollow: () => taps++), scale: scale, scaffold: false);
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
        expect(find.text('Follow'), findsOneWidget);
        expect(_inside<FilledButton>('Follow'), findsOneWidget);
        expect(_inside<ElevatedButton>('Message'), findsOneWidget);
        expect(find.text('128 followers'), findsOneWidget);
        await t.tap(find.text('Follow'));
        expect(taps, 1);
      });

      testWidgets('partner page: grey Following once followed; "1 follower"', (t) async {
        await _pump(t, _partner(following: true, followers: 1, onFollow: () {}), scale: scale, scaffold: false);
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
        expect(_inside<ElevatedButton>('Following'), findsOneWidget);
        expect(find.text('Follow'), findsNothing);
        expect(find.text('1 follower'), findsOneWidget);
      });

      testWidgets("partner page: the shop's own owner sees no Follow and no chip at 0", (t) async {
        await _pump(t, _partner(following: null, followers: 0), scale: scale, scaffold: false);
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
        expect(find.text('Follow'), findsNothing);
        expect(find.text('Following'), findsNothing);
        expect(find.textContaining('follower'), findsNothing);
        expect(_inside<FilledButton>('Message'), findsOneWidget, reason: 'Message stays full width');
      });

      // --------------------------------------------------------- club ---
      testWidgets('club page: outsiders follow (at once), unfollow from the sheet; count in the header', (t) async {
        final social = _FakeSocial()..counts[_club] = 3;
        await _pump(t, const ClubScreen(clubId: 'c1'), scale: scale, scaffold: false, overrides: _clubOverrides(social));
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
        expect(find.text('followers'), findsOneWidget);
        expect(find.text('3'), findsOneWidget);
        // Clubs are public by default (0.3.52): outsiders join at once.
        expect(find.text('Join club'), findsOneWidget);
        expect(find.text('Post'), findsNothing, reason: 'Follow takes the place of the greyed-out Post');
        // Down to the end and back: every row laid out (an overflow fails the test).
        await t.scrollUntilVisible(find.text('POSTS'), 300, scrollable: find.byType(Scrollable).first);
        expect(t.takeException(), isNull);
        await t.scrollUntilVisible(find.text('Follow'), -300, scrollable: find.byType(Scrollable).first);

        social.gate = Completer();
        await _tap(t, 'Follow');
        await t.pump();
        expect(find.text('Following'), findsOneWidget, reason: 'flips before the server answers');
        social.gate!.complete();
        social.gate = null;
        await t.pumpAndSettle();
        expect(find.text('Following'), findsOneWidget);
        expect(find.text('4'), findsOneWidget);

        await _tap(t, 'Following');
        await t.pumpAndSettle();
        expect(find.text('Unfollow TT Spot Crew?'), findsOneWidget);
        expect(t.takeException(), isNull);
        await t.tap(_inside<FilledButton>('Unfollow'));
        await t.pumpAndSettle();
        expect(find.text('Follow'), findsOneWidget);
        expect(find.text('3'), findsOneWidget);
        expect(social.followed, isEmpty);
      });

      testWidgets('club page: Cancel in the sheet keeps Following', (t) async {
        final social = _FakeSocial()..followed.add(_club)..counts[_club] = 1;
        await _pump(t, const ClubScreen(clubId: 'c1'), scale: scale, scaffold: false, overrides: _clubOverrides(social));
        await t.pumpAndSettle();
        expect(find.text('follower'), findsOneWidget);
        await _tap(t, 'Following');
        await t.pumpAndSettle();
        await t.tap(find.text('Cancel'));
        await t.pumpAndSettle();
        expect(find.text('Following'), findsOneWidget);
        expect(social.followed, contains(_club));
      });

      testWidgets('club page: members and officers get Post, not Follow', (t) async {
        // The members-only rows (map switch, club garage) are ListTiles on a
        // tinted box, which debug builds warn about; that is older than Follow
        // and harmless. Anything else (an overflow) fails the test.
        final errors = <FlutterErrorDetails>[];
        final previous = FlutterError.onError;
        FlutterError.onError = errors.add;
        try {
          await _pump(t, const ClubScreen(clubId: 'c1'), scale: scale, scaffold: false, overrides: _clubOverrides(_FakeSocial(), member: true));
          await t.pumpAndSettle();
          expect(find.text('Member'), findsWidgets);
          expect(find.text('Post'), findsOneWidget);
          expect(find.text('Follow'), findsNothing);
          expect(find.text('Following'), findsNothing);
          await t.scrollUntilVisible(find.text('POSTS'), 300, scrollable: find.byType(Scrollable).first);

          await _pump(t, const ClubScreen(clubId: 'c1'), scale: scale, scaffold: false, overrides: _clubOverrides(_FakeSocial(), member: true, me: 'u-owner'));
          await t.pumpAndSettle();
          expect(find.text('Post as club'), findsOneWidget);
          expect(find.text('Follow'), findsNothing);
          await t.scrollUntilVisible(find.text('POSTS'), 300, scrollable: find.byType(Scrollable).first);
        } finally {
          FlutterError.onError = previous;
        }
        expect(errors.where((e) => !e.toString().contains('ListTile background color')).map((e) => e.toString()), isEmpty);
      });
    });
  }
}
