// Points restructure and four-tier badges (0.3.55,
// supabase/migrations/20261006000108_points_badges.sql): the tier maths, the
// Friday 6 PM points week, the badges page, the profile honour row and the
// points page at text 1.0 and 1.3.

import 'package:car_meet/core/supabase/supabase_client.dart';
import 'package:car_meet/core/theme/app_theme.dart';
import 'package:car_meet/features/auth/domain/profile.dart';
import 'package:car_meet/features/badges/application/badges_providers.dart';
import 'package:car_meet/features/badges/domain/badges.dart';
import 'package:car_meet/features/badges/presentation/honour_picker_sheet.dart';
import 'package:car_meet/features/badges/presentation/honour_row.dart';
import 'package:car_meet/features/friends/application/nicknames.dart';
import 'package:car_meet/features/friends/domain/friend.dart';
import 'package:car_meet/features/points/application/points_providers.dart';
import 'package:car_meet/features/points/domain/points.dart';
import 'package:car_meet/features/points/domain/points_week.dart';
import 'package:car_meet/features/points/domain/verification.dart';
import 'package:car_meet/features/points/presentation/points_screen.dart';
import 'package:car_meet/features/profile/domain/car.dart';
import 'package:car_meet/features/profile/presentation/badges_screen.dart';
import 'package:car_meet/features/profile/presentation/widgets/profile_header.dart';
import 'package:car_meet/features/social/domain/post.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

const _me = 'u-me';

BadgeProgress _badge(String id, {int tier = 0, int count = 0, bool onProfile = false}) => BadgeProgress(
      id: id,
      name: kBadgeNames[id]!,
      description: switch (id) {
        'explorer' => 'Different spots, partner shops and meets you checked in at. TT sessions don\'t count.',
        _ => 'What this badge counts, in a sentence.',
      },
      unit: switch (id) {
        'posts' => 'posts',
        'organizer' => 'meets organized',
        'joiner' => 'meets joined',
        'explorer' => 'places',
        _ => 'followers',
      },
      thresholds: switch (id) {
        'joiner' => const [1, 20, 50, 100],
        'popular' => const [1, 50, 100, 200],
        _ => const [1, 10, 20, 50],
      },
      storedTier: tier,
      count: count,
      onProfile: onProfile,
    );

final _allBadges = [
  _badge('posts', tier: 2, count: 12, onProfile: true),
  _badge('organizer', tier: 4, count: 57),
  _badge('joiner', tier: 1, count: 3, onProfile: true),
  _badge('explorer'),
  _badge('popular', tier: 3, count: 140, onProfile: true),
];

const _three = [
  HonourBadge(id: 'organizer', name: 'Car meet organizer', tier: 4),
  HonourBadge(id: 'joiner', name: 'Car meet joining', tier: 2),
  HonourBadge(id: 'popular', name: 'Popular', tier: 1),
];

Future<void> _pump(WidgetTester t, Widget child, {double scale = 1, List overrides = const []}) async {
  t.view.physicalSize = const Size(1080, 2400); // 360 x 800, the narrowest we design for
  t.view.devicePixelRatio = 3;
  addTearDown(t.view.reset);
  await t.pumpWidget(ProviderScope(
    retry: (_, _) => null,
    overrides: [nicknamesProvider.overrideWithValue(const <String, String>{}), ...overrides.cast()],
    child: MaterialApp(
      theme: AppTheme.current,
      builder: (context, c) => MediaQuery(data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)), child: c!),
      home: child,
    ),
  ));
  await t.pump();
  await t.pump();
}

void main() {
  // ------------------------------------------------------------ tiers ---
  group('tier maths', () {
    test('counts reach tiers by the four thresholds', () {
      const joiner = [1, 20, 50, 100];
      expect(tierForCount(joiner, 0), 0);
      expect(tierForCount(joiner, 1), 1);
      expect(tierForCount(joiner, 19), 1);
      expect(tierForCount(joiner, 20), 2);
      expect(tierForCount(joiner, 99), 3);
      expect(tierForCount(joiner, 100), 4);
      expect(tierForCount(joiner, 5000), 4);
    });

    test('progress to the next tier', () {
      final posts = _badge('posts', tier: 2, count: 12);
      expect(posts.tier, 2);
      expect(posts.nextTier, 3);
      expect(posts.nextThreshold, 20);
      expect(posts.progressLabel, '12 / 20 posts to Platinum');
      expect(posts.fraction, closeTo(0.6, 1e-9));

      final locked = _badge('explorer');
      expect(locked.earned, isFalse);
      expect(locked.progressLabel, '0 / 1 places to Bronze');
      expect(locked.fraction, 0);
    });

    test('gold is the top: no next threshold, a full bar', () {
      final gold = _badge('organizer', tier: 4, count: 57);
      expect(gold.isTop, isTrue);
      expect(gold.nextThreshold, isNull);
      expect(gold.fraction, 1);
      expect(gold.progressLabel, '57 meets organized · top tier');
    });

    test('a tier never goes down when the count drops (unfollows)', () {
      final popular = _badge('popular', tier: 3, count: 30);
      expect(popular.tier, 3);
      expect(popular.progressLabel, '30 / 200 followers to Gold');
    });

    test('shows the tier the count reaches before the database catches up', () {
      final joiner = _badge('joiner', tier: 1, count: 20);
      expect(joiner.tier, 2);
    });

    test('art paths: <id>_<tier>.png, locked uses bronze, single-art fallback', () {
      expect(badgeArt('joiner', 3), 'assets/badges/joiner_3.png');
      expect(badgeArt('posts', 0), 'assets/badges/posts_1.png');
      expect(badgeArt('popular', 9), 'assets/badges/popular_4.png');
      expect(badgeFallbackArt('posts'), 'assets/badges/first_post.png');
      expect(badgeFallbackArt('organizer'), 'assets/badges/organiser.png');
      expect(badgeFallbackArt('joiner'), 'assets/badges/first_meet.png');
      expect(badgeFallbackArt('explorer'), 'assets/badges/explorer.png');
      expect(badgeFallbackArt('popular'), 'assets/badges/popular.png');
    });

    test('tier names and Activity lines', () {
      expect([for (var t = 0; t <= 4; t++) badgeTierName(t)], ['Locked', 'Bronze', 'Silver', 'Platinum', 'Gold']);
      expect(badgeActivityText('Explorer', '1'), 'You earned the Explorer badge: Bronze.');
      expect(badgeActivityText('Car meet joining', '3'), 'Your Car meet joining badge is now Platinum.');
      expect(badgeActivityText('Popular', null), 'You earned the Popular badge.');
      expect(isRetiredBadgeRow('garage_open'), isTrue);
      expect(isRetiredBadgeRow('first_meet'), isTrue);
      expect(isRetiredBadgeRow('explorer'), isFalse);
      expect(isRetiredBadgeRow(null), isTrue);
    });

    test('reads badge_progress rows', () {
      final b = BadgeProgress.fromMap({
        'badge_id': 'joiner',
        'name': 'Car meet joining',
        'description': 'Meets you joined.',
        'unit': 'meets joined',
        'thresholds': [1, 20, 50, 100],
        'sort': 3,
        'tier': 1,
        'tier_reached_at': '2026-10-06T10:17:04.103696+00:00',
        'progress': 7,
        'on_profile': true,
      });
      expect((b.id, b.tier, b.count, b.nextThreshold, b.onProfile), ('joiner', 1, 7, 20, true));
    });
  });

  // ------------------------------------------------------- points week ---
  group('points week (Friday 6 PM Malaysia time)', () {
    DateTime myt(String s) => DateTime.parse('$s+08:00');

    test('the week starts on the Friday 18:00 at or before', () {
      expect(pointsWeekStart(myt('2026-10-08T23:00:00')), myt('2026-10-02T18:00:00')); // Thu night
      expect(pointsWeekStart(myt('2026-10-09T17:59:00')), myt('2026-10-02T18:00:00')); // Fri, a minute early
      expect(pointsWeekStart(myt('2026-10-09T18:00:00')), myt('2026-10-09T18:00:00')); // Fri, on the dot
      expect(pointsWeekStart(myt('2026-10-10T12:00:00')), myt('2026-10-09T18:00:00')); // Sat
      expect(pointsWeekStart(myt('2026-10-04T09:00:00')), myt('2026-10-02T18:00:00')); // Sun
      expect(pointsWeekStart(myt('2026-10-02T17:59:59')), myt('2026-09-25T18:00:00'));
    });

    test('the next reset is a week after the start, whatever the input zone', () {
      expect(nextPointsReset(myt('2026-10-09T17:59:00')), myt('2026-10-09T18:00:00'));
      expect(nextPointsReset(myt('2026-10-09T18:00:00')), myt('2026-10-16T18:00:00'));
      // 10:00 UTC on a Friday is 18:00 in Malaysia.
      expect(nextPointsReset(DateTime.utc(2026, 10, 9, 9, 59)), DateTime.utc(2026, 10, 9, 10));
      expect(nextPointsReset(DateTime.utc(2026, 12, 31, 23)), myt('2027-01-01T18:00:00'));
    });

    test('labels', () {
      expect(resetLabel(DateTime(2026, 10, 9, 18)), 'Fri 6 PM');
      expect(resetLabel(DateTime(2026, 10, 9, 0, 30)), 'Fri 12:30 AM');
      expect(resetLabel(DateTime(2026, 10, 10, 12)), 'Sat 12 PM');
    });

    test('the spot check-in snack (always Malaysia time)', () {
      final fri = DateTime.utc(2026, 10, 9, 10); // Friday 18:00 in Malaysia
      expect(spotCheckinMessage(isNew: true, total: 4, points: 10), 'Checked in · +10 points. That\'s 4 for this spot.');
      expect(spotCheckinMessage(isNew: true, total: 5, points: 0, againAt: fri), 'Checked in. That\'s 5 for this spot. Points here again after Fri 6 PM.');
      expect(spotCheckinMessage(isNew: false, total: 5, points: 0, againAt: fri), 'Already checked in here today. Points here again after Fri 6 PM.');
    });

    test('reads points_week_status', () {
      final w = PointsWeek.fromMap({'week_start': '2026-10-02T10:00:00+00:00', 'next_reset': '2026-10-09T10:00:00+00:00', 'post_done': true});
      expect(w.nextReset, DateTime.utc(2026, 10, 9, 10));
      expect(w.postDone, isTrue);
      expect(w.resetText, 'Fri 6 PM'); // whatever zone the phone is in
      expect(malaysiaClock(DateTime.utc(2026, 10, 9, 10)).hour, 18);
    });

    test('How to earn limit lines', () {
      final week = PointsWeek(weekStart: DateTime.utc(2026, 10, 2, 10), nextReset: DateTime.utc(2026, 10, 9, 10));
      final reset = week.resetText;
      expect(PointsScreen.limitLine(_rules[1], week), 'Once per spot per week · resets $reset');
      expect(PointsScreen.limitLine(_rules[2], week), '1 post a week · resets $reset');
      expect(PointsScreen.limitLine(_rules[2], PointsWeek(weekStart: week.weekStart, nextReset: week.nextReset, postDone: true)), 'Paid this week · next one after $reset');
      expect(PointsScreen.limitLine(_rules[0], week), 'Once per meet');
    });
  });

  // ------------------------------------------------------- badges page ---
  group('badges page', () {
    for (final scale in [1.0, 1.3]) {
      testWidgets('every badge, its tier, progress and the four steps (text $scale)', (t) async {
        await _pump(
          t,
          const BadgesScreen(userId: _me),
          scale: scale,
          overrides: [
            currentUserIdProvider.overrideWithValue(_me),
            badgeProgressProvider(_me).overrideWith((ref) async => _allBadges),
          ],
        );
        expect(t.takeException(), isNull);
        expect(find.text('4 of 5 earned · bronze, silver, platinum, gold'), findsOneWidget);
        expect(find.text('Choose for profile'), findsOneWidget);
        expect(find.text('12 / 20 posts to Platinum'), findsOneWidget);
        expect(find.text('Car meet organizer'), findsOneWidget);
        expect(find.text('57 meets organized · top tier'), findsOneWidget);
        await t.scrollUntilVisible(find.text('0 / 1 places to Bronze'), 200, scrollable: find.byType(Scrollable).first);
        expect(find.text('Locked'), findsOneWidget);
        await t.scrollUntilVisible(find.text('140 / 200 followers to Gold'), 200, scrollable: find.byType(Scrollable).first);
        expect(t.takeException(), isNull);
        expect(find.text('On profile'), findsWidgets);
        // All four steps on every card.
        expect(find.text('Platinum'), findsWidgets);
      });
    }

    testWidgets("someone else's page: no picker", (t) async {
      await _pump(
        t,
        const BadgesScreen(userId: 'u-keith'),
        overrides: [
          currentUserIdProvider.overrideWithValue(_me),
          badgeProgressProvider('u-keith').overrideWith((ref) async => _allBadges),
        ],
      );
      expect(find.text('Choose for profile'), findsNothing);
      expect(find.text('On profile'), findsNothing);
    });

    testWidgets('Choose for profile opens the picker with my current three', (t) async {
      await _pump(
        t,
        const BadgesScreen(userId: _me),
        overrides: [
          currentUserIdProvider.overrideWithValue(_me),
          badgeProgressProvider(_me).overrideWith((ref) async => _allBadges),
          honourBadgesProvider(_me).overrideWith((ref) async => const [
                HonourBadge(id: 'posts', name: 'Posts', tier: 2),
                HonourBadge(id: 'joiner', name: 'Car meet joining', tier: 1),
              ]),
        ],
      );
      await t.tap(find.text('Choose for profile'));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
      expect(find.text('Up to 3. They show under your numbers in the order you pick them.'), findsOneWidget);
      final sheet = find.byType(HonourPickerSheet);
      expect(find.descendant(of: sheet, matching: find.text('1')), findsOneWidget); // Posts first
      expect(find.descendant(of: sheet, matching: find.text('2')), findsOneWidget); // then Car meet joining
      expect(find.descendant(of: sheet, matching: find.text('3')), findsNothing);
      expect(find.text('All badges'), findsNothing); // already on the badges page
    });
  });

  // ----------------------------------------------------- honour row ---
  group('profile honour row', () {
    Widget header() => SingleChildScrollView(
          child: ProfileHeader(
            profile: Profile(id: _me, username: 'testing', displayName: 'App Review', createdAt: DateTime(2026)),
            isMe: false,
            cars: const <Car>[],
            stats: const ProfileStats(cars: 1, organised: 0, attended: 1, went: 3),
            friendCount: 2,
            points: null,
            moments: const <Story>[],
            friendship: FriendshipStatus.none,
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
          ),
        );

    for (final scale in [1.0, 1.3]) {
      for (final n in [0, 1, 3]) {
        testWidgets('$n badge${n == 1 ? '' : 's'} under the numbers (text $scale)', (t) async {
          await _pump(
            t,
            Scaffold(body: header()),
            scale: scale,
            overrides: [honourBadgesProvider(_me).overrideWith((ref) async => _three.take(n).toList())],
          );
          expect(t.takeException(), isNull);
          expect(find.byType(HonourMedallion), findsNWidgets(n));
          if (n == 0) expect(find.byType(HonourRow), findsNothing);
          if (n >= 1) {
            expect(find.text('Car meet organizer'), findsOneWidget);
            expect(find.text('Gold'), findsOneWidget);
          }
          if (n == 3) {
            expect(find.text('Silver'), findsOneWidget);
            expect(find.text('Bronze'), findsOneWidget);
            // Same height side by side, long names on two lines, not cut.
            final sizes = [for (final e in find.byType(HonourMedallion).evaluate()) (e.renderObject! as RenderBox).size.height];
            expect(sizes.toSet().length, 1);
            final name = t.widget<Text>(find.text('Car meet organizer'));
            expect(name.maxLines, 2);
          }
          // The rest of the header is still there.
          expect(find.text('Meets'), findsOneWidget);
        });
      }
    }

    testWidgets('a load error shows no row and no error', (t) async {
      await _pump(t, Scaffold(body: header()), overrides: [honourBadgesProvider(_me).overrideWith((ref) async => throw Exception('offline'))]);
      expect(t.takeException(), isNull);
      expect(find.byType(HonourMedallion), findsNothing);
    });

    testWidgets("on someone else's profile a tap opens their badges", (t) async {
      final router = GoRouter(initialLocation: '/p', routes: [
        GoRoute(path: '/p', builder: (_, _) => const Scaffold(body: ProfileHonourRow(userId: 'u-keith', isMe: false))),
        GoRoute(path: '/profile/:id/badges', builder: (_, s) => Scaffold(body: Text('badges of ${s.pathParameters['id']}'))),
      ]);
      addTearDown(router.dispose);
      await t.pumpWidget(ProviderScope(
        retry: (_, _) => null,
        overrides: [honourBadgesProvider('u-keith').overrideWith((ref) async => _three.take(1).toList())],
        child: MaterialApp.router(theme: AppTheme.current, routerConfig: router),
      ));
      await t.pump();
      await t.pump();
      await t.tap(find.byType(HonourMedallion));
      await t.pumpAndSettle();
      expect(find.text('badges of u-keith'), findsOneWidget);
    });
  });

  // ------------------------------------------------------- points page ---
  group('points page', () {
    final history = [
      PointEntry(id: 3, delta: 10, reason: 'badge', label: 'Earn a badge', note: 'Explorer · Bronze', createdAt: DateTime.now().subtract(const Duration(minutes: 5))),
      PointEntry(id: 2, delta: 10, reason: 'spot_checkin', label: 'Check in at a spot or partner shop', note: "Devi's Corner, Bangsar", createdAt: DateTime.now().subtract(const Duration(minutes: 5))),
      PointEntry(id: 1, delta: -100, reason: 'box', label: 'Blind box', createdAt: DateTime.now().subtract(const Duration(days: 2))),
      PointEntry(id: 0, delta: 50, reason: 'freepoints', label: 'Free points', note: 'Given by an admin', createdAt: DateTime.now().subtract(const Duration(days: 3))),
    ];
    final week = PointsWeek(weekStart: DateTime.utc(2026, 10, 2, 10), nextReset: DateTime.utc(2026, 10, 9, 10));

    Future<GoRouter> pumpPoints(WidgetTester t, {double scale = 1}) async {
      t.view.physicalSize = const Size(1080, 2400);
      t.view.devicePixelRatio = 3;
      addTearDown(t.view.reset);
      final router = GoRouter(initialLocation: '/me/points', routes: [
        GoRoute(path: '/me/points', builder: (_, _) => const PointsScreen()),
        GoRoute(path: '/profile/:id/badges', builder: (_, s) => Scaffold(body: Text('badges of ${s.pathParameters['id']}'))),
        GoRoute(path: '/me/qr', builder: (_, _) => const Scaffold(body: Text('my qr'))),
      ]);
      addTearDown(router.dispose);
      await t.pumpWidget(ProviderScope(
        retry: (_, _) => null,
        overrides: [
          currentUserIdProvider.overrideWithValue(_me),
          pointsBalanceProvider.overrideWith((ref) async => 1240),
          pointRulesProvider.overrideWith((ref) async => _rules),
          pointHistoryProvider.overrideWith((ref) async => history),
          myVerificationsProvider.overrideWith((ref) async => const <SpotVerification>[]),
          pointsWeekProvider.overrideWith((ref) async => week),
          myReferralCodeProvider.overrideWith((ref) async => 'K3V9QX'),
        ],
        child: MaterialApp.router(
          theme: AppTheme.current,
          routerConfig: router,
          builder: (context, c) => MediaQuery(data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)), child: c!),
        ),
      ));
      await t.pump();
      await t.pump();
      return router;
    }

    for (final scale in [1.0, 1.3]) {
      testWidgets('balance, how to earn with limits, history (text $scale)', (t) async {
        await pumpPoints(t, scale: scale);
        expect(t.takeException(), isNull);
        expect(find.text('1,240'), findsOneWidget);
        expect(find.text('HOW TO EARN'), findsOneWidget);
        // Only the paying rules, each with its limit under the title.
        expect(find.text('Check in at a meet'), findsOneWidget);
        expect(find.text('Once per meet'), findsOneWidget);
        expect(find.text('Once per spot per week · resets ${week.resetText}'), findsOneWidget);
        expect(find.text('1 post a week · resets ${week.resetText}'), findsOneWidget);
        expect(find.text('Verified spot check-in'), findsNothing); // retired
        expect(find.text('Share your first post'), findsNothing); // retired
        // Each paying rule with its amount on the right.
        for (final (label, amount) in const [
          ('Check in at a meet', '+10'),
          ('Check in at a spot or partner shop', '+10'),
          ('Share a post', '+10'),
          ('Bring a friend', '+5'),
          ('Join with a code', '+5'),
          ('Earn a badge', '+10'),
        ]) {
          // (The history can hold the same words: only the How to earn row.)
          final title = find.descendant(of: find.byType(EarnRow), matching: find.text(label));
          await t.scrollUntilVisible(title, 100, scrollable: find.byType(Scrollable).first);
          final row = find.ancestor(of: title, matching: find.byType(EarnRow));
          expect(find.descendant(of: row, matching: find.text(amount)), findsOneWidget, reason: label);
        }
        expect(find.byType(EarnRow, skipOffstage: false), findsWidgets);
        expect(t.takeException(), isNull);
        await t.scrollUntilVisible(find.text('Blind box'), 200, scrollable: find.byType(Scrollable).first);
        expect(t.takeException(), isNull);
        expect(find.textContaining('Explorer · Bronze'), findsOneWidget);
        expect(find.textContaining('Given by an admin'), findsNothing); // admin notes stay off
        expect(find.text('-100'), findsOneWidget);
      });
    }

    testWidgets('"Earn a badge" opens my badges', (t) async {
      final router = await pumpPoints(t);
      final row = find.ancestor(of: find.text('Earn a badge'), matching: find.byType(EarnRow));
      await t.ensureVisible(row);
      await t.tap(row);
      await t.pumpAndSettle();
      expect(router.state.uri.toString(), '/profile/$_me/badges');
      expect(find.text('badges of $_me'), findsOneWidget);
    });
  });
}

// The live rules after 20261006000108 (retired ones kept, inactive).
const _rules = [
  PointRule(reason: 'meet_checkin', points: 10, label: 'Check in at a meet', description: 'Scan the host\'s QR.', sort: 10, limitNote: 'Once per meet'),
  PointRule(reason: 'spot_checkin', points: 10, label: 'Check in at a spot or partner shop', description: 'Within 300 m.', sort: 20, limitNote: 'Once per spot per week'),
  PointRule(reason: 'weekly_post', points: 10, label: 'Share a post', description: 'Passes the photo check.', sort: 30, limitNote: '1 post a week'),
  PointRule(reason: 'spot_verified', points: 0, label: 'Verified spot check-in', description: 'Retired.', sort: 25, active: false),
  PointRule(reason: 'referral_referrer', points: 5, label: 'Bring a friend', description: 'They join with your code.', sort: 40, limitNote: 'When they do their first check-in'),
  PointRule(reason: 'referral_referee', points: 5, label: 'Join with a code', description: 'Enter a code.', sort: 45, limitNote: 'Paid at your first check-in'),
  PointRule(reason: 'first_post', points: 50, label: 'Share your first post', description: 'Retired.', sort: 45, active: false),
  PointRule(reason: 'badge', points: 10, label: 'Earn a badge', description: 'Every new tier.', sort: 50, limitNote: 'Each new tier counts'),
  PointRule(reason: 'box', points: 0, label: 'Blind box', description: 'Spent on a blind box.', sort: 200),
];
