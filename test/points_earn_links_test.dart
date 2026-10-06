import 'package:car_meet/core/supabase/supabase_client.dart';
import 'package:car_meet/core/theme/app_icons.dart';
import 'package:car_meet/core/theme/app_theme.dart';
import 'package:car_meet/features/map/application/map_providers.dart';
import 'package:car_meet/features/points/application/points_providers.dart';
import 'package:car_meet/features/points/domain/points.dart';
import 'package:car_meet/features/points/domain/points_week.dart';
import 'package:car_meet/features/points/domain/verification.dart';
import 'package:car_meet/features/points/presentation/points_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

/// Points & rewards: every How to earn row is a shortcut to where you earn
/// it (a chevron, greys while pressed).

const _me = 'u-me';

const _rules = [
  PointRule(reason: 'meet_checkin', points: 10, label: 'Check in at a meet', description: 'Scan the host\'s QR.', sort: 10, limitNote: 'Once per meet'),
  PointRule(reason: 'spot_checkin', points: 10, label: 'Check in at a spot or partner shop', description: 'Within 300 m.', sort: 20, limitNote: 'Once per spot per week'),
  PointRule(reason: 'weekly_post', points: 10, label: 'Share a post', description: 'Passes the photo check.', sort: 30, limitNote: '1 post a week'),
  PointRule(reason: 'referral_referrer', points: 5, label: 'Bring a friend', description: 'They join with your code.', sort: 40, limitNote: 'When they do their first check-in'),
  PointRule(reason: 'referral_referee', points: 5, label: 'Join with a code', description: 'Enter a code.', sort: 45, limitNote: 'Paid at your first check-in'),
  PointRule(reason: 'badge', points: 10, label: 'Earn a badge', description: 'Every new tier.', sort: 50, limitNote: 'Each new tier counts'),
];

/// The map tab stand-in: which layer it was asked for, and map vs list.
class _MapProbe extends ConsumerWidget {
  const _MapProbe();
  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      Scaffold(body: Text('map ${ref.watch(mapModeProvider).name} list ${ref.watch(mapListViewProvider)}'));
}

Future<(GoRouter, ProviderContainer)> _pump(WidgetTester t, {double scale = 1}) async {
  t.view.physicalSize = const Size(1080, 2400);
  t.view.devicePixelRatio = 3;
  addTearDown(t.view.reset);
  final router = GoRouter(initialLocation: '/me/points', routes: [
    GoRoute(path: '/me/points', builder: (_, _) => const PointsScreen()),
    GoRoute(path: '/map', builder: (_, _) => const _MapProbe()),
    GoRoute(path: '/create/post/:kind', builder: (_, s) => Scaffold(body: Text('new ${s.pathParameters['kind']}'))),
    GoRoute(path: '/profile/:id/badges', builder: (_, s) => Scaffold(body: Text('badges of ${s.pathParameters['id']}'))),
    GoRoute(path: '/me/qr', builder: (_, _) => const Scaffold(body: Text('my qr'))),
  ]);
  addTearDown(router.dispose);
  final container = ProviderContainer(
    retry: (_, _) => null,
    overrides: [
      currentUserIdProvider.overrideWithValue(_me),
      pointsBalanceProvider.overrideWith((ref) async => 1240),
      pointRulesProvider.overrideWith((ref) async => _rules),
      pointHistoryProvider.overrideWith((ref) async => const <PointEntry>[]),
      myVerificationsProvider.overrideWith((ref) async => const <SpotVerification>[]),
      pointsWeekProvider.overrideWith((ref) async => PointsWeek(weekStart: DateTime.utc(2026, 10, 2, 10), nextReset: DateTime.utc(2026, 10, 9, 10))),
      myReferralCodeProvider.overrideWith((ref) async => 'K3V9QX'),
    ],
  );
  addTearDown(container.dispose);
  await t.pumpWidget(UncontrolledProviderScope(
    container: container,
    child: MaterialApp.router(
      theme: AppTheme.current,
      routerConfig: router,
      builder: (context, c) => MediaQuery(data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)), child: c!),
    ),
  ));
  await t.pump();
  await t.pump();
  return (router, container);
}

Finder _row(String label) => find.ancestor(of: find.descendant(of: find.byType(EarnRow), matching: find.text(label)), matching: find.byType(EarnRow));

Future<void> _tapRow(WidgetTester t, String label) async {
  final row = _row(label);
  await t.scrollUntilVisible(row, 100, scrollable: find.byType(Scrollable).first);
  await t.tap(row);
  await t.pumpAndSettle();
}

void main() {
  for (final scale in [1.0, 1.3]) {
    testWidgets('every How to earn row has a chevron and fits (text $scale)', (t) async {
      await _pump(t, scale: scale);
      for (final r in _rules) {
        final row = _row(r.label);
        await t.scrollUntilVisible(row, 100, scrollable: find.byType(Scrollable).first);
        expect(find.descendant(of: row, matching: find.byIcon(AppIcons.caretRight)), findsOneWidget, reason: r.label);
        expect(t.widget<EarnRow>(row).onTap, isNotNull, reason: r.label);
      }
      expect(t.takeException(), isNull);
    });
  }

  testWidgets('"Share a post" opens the new post page (the + sheet\'s Post)', (t) async {
    final (router, _) = await _pump(t);
    await _tapRow(t, 'Share a post');
    expect(router.state.uri.toString(), '/create/post/post');
    expect(find.text('new post'), findsOneWidget);
  });

  testWidgets('"Check in at a meet" opens the Map tab on Events, as the map', (t) async {
    final (router, container) = await _pump(t);
    container.read(mapListViewProvider.notifier).set(true); // left on the list earlier
    await _tapRow(t, 'Check in at a meet');
    expect(router.state.uri.toString(), '/map');
    expect(container.read(mapModeProvider), MapMode.events);
    expect(find.text('map events list false'), findsOneWidget);
  });

  testWidgets('"Check in at a spot or partner shop" opens the Map tab on Spots', (t) async {
    final (router, container) = await _pump(t);
    await _tapRow(t, 'Check in at a spot or partner shop');
    expect(router.state.uri.toString(), '/map');
    expect(container.read(mapModeProvider), MapMode.spots);
    expect(find.text('map spots list false'), findsOneWidget);
  });

  testWidgets('"Earn a badge" still opens my badges; the referral rows my QR', (t) async {
    final (router, _) = await _pump(t);
    await _tapRow(t, 'Earn a badge');
    expect(router.state.uri.toString(), '/profile/$_me/badges');
    router.go('/me/points');
    await t.pumpAndSettle();
    await _tapRow(t, 'Bring a friend');
    expect(router.state.uri.toString(), '/me/qr');
    router.go('/me/points');
    await t.pumpAndSettle();
    await _tapRow(t, 'Join with a code');
    expect(router.state.uri.toString(), '/me/qr');
  });

  testWidgets('a row greys while pressed', (t) async {
    await _pump(t);
    final row = _row('Share a post');
    final well = t.widget<InkWell>(find.descendant(of: row, matching: find.byType(InkWell)).first);
    expect(well.highlightColor, AppColors.surfaceGray);
    final ink = Material.of(t.element(row));
    expect(ink, isNot(paints..rect(color: AppColors.surfaceGray)));
    final g = await t.startGesture(t.getCenter(row));
    for (var i = 0; i < 8; i++) {
      await t.pump(const Duration(milliseconds: 60)); // press timeout, then the highlight fades in
    }
    expect(ink, paints..rect(color: AppColors.surfaceGray));
    await g.cancel();
    await t.pumpAndSettle();
  });

  testWidgets('a rule with nowhere to go stays a plain row (no chevron)', (t) async {
    const odd = PointRule(reason: 'club_president_bonus', points: 1, label: 'Club meet bonus', description: 'A member checked in.', sort: 75);
    t.view.physicalSize = const Size(1080, 2400);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    VoidCallback? tap = () {};
    await t.pumpWidget(ProviderScope(
      child: MaterialApp(
        theme: AppTheme.current,
        home: Scaffold(
          body: Consumer(builder: (context, ref, _) {
            tap = PointsScreen.earnTap(context, ref, odd, me: _me);
            return EarnRow(rule: odd, limit: 'x', onTap: tap);
          }),
        ),
      ),
    ));
    expect(tap, isNull);
    expect(find.byIcon(AppIcons.caretRight), findsNothing);
  });
}
