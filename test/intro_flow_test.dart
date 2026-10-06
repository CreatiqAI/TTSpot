import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:car_meet/core/theme/app_theme.dart';
import 'package:car_meet/features/auth/presentation/sign_in_screen.dart';
import 'package:car_meet/features/auth/presentation/welcome_screen.dart';
import 'package:car_meet/features/onboarding/presentation/intro_screen.dart';

/// Welcome → Get started → Never miss a meet → Your crew, live → Create an
/// account; Skip jumps straight to Create an account; I already have an
/// account goes to Sign in. The slides loop their motion, so time is pumped
/// by hand (pumpAndSettle would never return).
void main() {
  Future<GoRouter> pump(WidgetTester tester, {bool dark = false, double scale = 1.0, String start = '/welcome'}) async {
    // 500 x 844 at 2x: wider than the 390 mockup frame, because the
    // (untouched) Welcome header row needs it under the test font, whose
    // glyphs are all a full em wide.
    tester.view.physicalSize = const Size(1000, 1688);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    AppColors.dark = dark;
    addTearDown(() => AppColors.dark = false);
    final router = GoRouter(
      initialLocation: start,
      routes: [
        GoRoute(path: '/welcome', builder: (_, _) => const WelcomeScreen()),
        GoRoute(path: '/intro', builder: (_, _) => const IntroScreen()),
        GoRoute(path: '/sign-in', builder: (_, s) => SignInScreen(signUp: s.uri.queryParameters['mode'] == 'signup')),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(ProviderScope(
      child: MaterialApp.router(
        theme: AppTheme.current,
        routerConfig: router,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
      ),
    ));
    await tester.pump();
    return router;
  }

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  // At 1.3x the walk starts on the slides: the Welcome screen is not this
  // track's (its header row is too wide for the test font at that size).
  for (final (dark, scale) in [(false, 1.0), (true, 1.3)]) {
    testWidgets('Get started walks both slides into Create an account (dark=$dark, x$scale)', (tester) async {
      await pump(tester, dark: dark, scale: scale, start: scale > 1 ? '/intro' : '/welcome');
      if (scale <= 1) {
        expect(find.text('Get started'), findsOneWidget);
        await tester.tap(find.text('Get started'));
        await settle(tester);
      }

      expect(find.text('NEVER MISS A MEET'), findsOneWidget);
      // One example from each row (they rotate, starting at random).
      int shown(List<String> titles) => titles.where((t) => find.text(t).evaluate().isNotEmpty).length;
      expect(shown(const ['TT at the mamak', 'Car park meet', 'Teh tarik TT', 'Club night', 'Midnight supper run']), 1);
      expect(shown(const ['Sunrise convoy', 'Track day', 'Charity drive', 'Official club meet', "Fraser's Hill run"]), 1);
      expect(shown(const ['New spot nearby', 'Detailing deal', 'Circuit nearby', 'Car wash deal', 'Scenic route']), 1);
      expect(find.text('Skip'), findsOneWidget);
      expect(find.text('Continue'), findsOneWidget);

      await tester.tap(find.text('Continue'));
      await settle(tester);
      expect(find.text('YOUR CREW, LIVE'), findsOneWidget);
      expect(find.text('Continue'), findsOneWidget);

      await tester.tap(find.text('Continue'));
      await settle(tester);
      expect(find.text('CREATE YOUR ACCOUNT'), findsOneWidget);
      expect(find.text('Sign up'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }, variant: TargetPlatformVariant.only(TargetPlatform.android));
  }

  testWidgets('Skip goes straight to Create an account', (tester) async {
    await pump(tester);
    await tester.tap(find.text('Get started'));
    await settle(tester);
    await tester.tap(find.text('Skip'));
    await settle(tester);
    expect(find.text('CREATE YOUR ACCOUNT'), findsOneWidget);
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));

  testWidgets('I already have an account goes to Sign in, not the slides', (tester) async {
    await pump(tester);
    await tester.tap(find.text('I already have an account'));
    await settle(tester);
    expect(find.text('WELCOME BACK'), findsOneWidget);
    expect(find.text('NEVER MISS A MEET'), findsNothing);
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));

  testWidgets('Replay from About says Done at the end and pops', (tester) async {
    tester.view.physicalSize = const Size(780, 1688);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.current,
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const IntroScreen(replay: true))),
            child: const Text('Show the intro again'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('Show the intro again'));
    await settle(tester);
    expect(find.text('NEVER MISS A MEET'), findsOneWidget);
    await tester.tap(find.text('Continue'));
    await settle(tester);
    expect(find.text('Done'), findsOneWidget);
    await tester.tap(find.text('Done'));
    await settle(tester);
    expect(find.text('Show the intro again'), findsOneWidget);
    expect(find.text('YOUR CREW, LIVE'), findsNothing);
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));
}
