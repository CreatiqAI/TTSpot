import 'package:car_meet/core/geo/latlng.dart';
import 'package:car_meet/core/theme/app_theme.dart';
import 'package:car_meet/features/auth/domain/profile.dart';
import 'package:car_meet/features/events/application/plan_draft.dart';
import 'package:car_meet/features/events/domain/cover_presets.dart';
import 'package:car_meet/features/events/domain/event.dart';
import 'package:car_meet/features/events/presentation/create_event_screen.dart';
import 'package:car_meet/features/friends/application/friends_providers.dart';
import 'package:car_meet/features/map/application/map_providers.dart';
import 'package:car_meet/features/vendors/application/vendors_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _mamak = LatLng(3.1390, 101.6869);

void main() {
  group('PlanDraft', () {
    final wed = DateTime(2026, 10, 7, 14, 0); // a Wednesday afternoon

    test('TT sessions ask Where, When, Who, Make it yours, Review; meets ask the kind first', () {
      expect(PlanDraft(session: true, now: wed).steps, [PlanStep.where, PlanStep.when, PlanStep.who, PlanStep.style, PlanStep.review]);
      expect(PlanDraft(session: false, now: wed).steps.first, PlanStep.kind);
      expect(PlanDraft(session: false, now: wed).steps.length, 6);
    });

    test('Where needs a pin and a name', () {
      final d = PlanDraft(session: true, now: wed);
      expect(d.problem(PlanStep.where, now: wed), isNotNull);
      d.setPlace(_mamak, name: 'Mamak Sri Melur', address: 'Jalan 1, KL');
      expect(d.problem(PlanStep.where, now: wed), isNull);
      d.venueCtrl.text = '  ';
      expect(d.problem(PlanStep.where, now: wed), contains('name'));
    });

    test('When must be at least 10 minutes out, and a week at most for underground clubs', () {
      final d = PlanDraft(session: true, now: wed);
      expect(d.problem(PlanStep.when, now: wed), isNull); // tonight 9 pm
      d.setStart(wed.add(const Duration(minutes: 5)));
      expect(d.problem(PlanStep.when, now: wed), contains('10 minutes'));
      final u = PlanDraft(session: false, underground: true, now: wed)..setStart(wed.add(const Duration(days: 9)));
      expect(u.problem(PlanStep.when, now: wed), contains('7 days'));
    });

    test('the title follows the place until the member types their own', () {
      final d = PlanDraft(session: true, now: wed);
      expect(d.title, 'TT session');
      d.setPlace(_mamak, name: 'Mamak Sri Melur');
      expect(d.title, 'TT @ Mamak Sri Melur');
      d.titleCtrl.text = 'Friday teh tarik';
      d.titleTyped();
      d.setPlace(_mamak, name: 'Somewhere else');
      expect(d.title, 'Friday teh tarik');
      final m = PlanDraft(session: false, now: wed)..setPlace(_mamak, name: 'Sunway');
      m.setType(EventType.convoy);
      expect(m.title, 'Convoy @ Sunway');
    });

    test('TT sessions end after the chosen duration; meets keep no end', () {
      final d = PlanDraft(session: true, now: wed)..setMinutes(180);
      expect(d.endsAt, d.startsAt.add(const Duration(hours: 3)));
      expect(PlanDraft(session: false, now: wed).endsAt, isNull);
    });

    test('a preset other than the type\'s own is saved as its public URL', () {
      final d = PlanDraft(session: true, now: wed);
      expect(d.presetUrl, isNull);
      expect(d.coverAsset, 'assets/covers/tt.jpg');
      d.pickPreset('club');
      expect(d.coverAsset, 'assets/covers/club.jpg');
      expect(d.presetUrl, endsWith('/storage/v1/object/public/event-covers/presets/club.jpg'));
      d.pickPreset('tt');
      expect(d.presetUrl, isNull, reason: 'the type default needs no cover_url');
    });

    test('quick times: tonight, tomorrow night, the coming Saturday', () {
      final q = PlanDraft.quickTimes(wed);
      expect(q.map((e) => e.label), ['Tonight', 'Tomorrow night', 'This weekend']);
      expect(q[0].at, DateTime(2026, 10, 7, 21));
      expect(q[1].at, DateTime(2026, 10, 8, 21));
      expect(q[2].at, DateTime(2026, 10, 10, 21));
      // Late on a Sunday: tonight is in an hour, the weekend is next Saturday.
      final sun = DateTime(2026, 10, 11, 22, 10);
      final late = PlanDraft.quickTimes(sun);
      expect(late[0].at, DateTime(2026, 10, 11, 23, 15));
      expect(late[2].at, DateTime(2026, 10, 17, 21));
      // Meets default to 8 pm.
      expect(PlanDraft.quickTimes(wed, session: false)[0].at.hour, 20);
    });
  });

  group('cover presets', () {
    test('the type\'s own cover comes first', () {
      expect(coverPresetsFor(EventType.convoy).first.id, 'convoy');
      expect(coverPresetsFor(EventType.tt).first.id, 'tt');
    });

    test('a preset URL maps back to the bundled file; a photo does not', () {
      expect(presetCoverAsset('https://x.supabase.co/storage/v1/object/public/event-covers/presets/club.jpg'), 'assets/covers/club.jpg');
      expect(presetCoverAsset('https://x.supabase.co/storage/v1/object/public/event-covers/presets/club_t.jpg'), 'assets/covers/club.jpg');
      expect(presetCoverAsset('https://x.supabase.co/storage/v1/object/public/event-covers/abc/123.jpg'), isNull);
      expect(presetCoverAsset(null), isNull);
    });
  });

  group('wizard', () {
    Future<void> pump(WidgetTester tester, Widget screen, {double scale = 1.0}) async {
      tester.view.physicalSize = const Size(1080, 2340); // 393 x 851 at 2.75x
      tester.view.devicePixelRatio = 2.75;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            userLocationProvider.overrideWith((ref) async => null),
            friendsProvider.overrideWith((ref) async => const <Profile>[]),
            myVendorProvider.overrideWith((ref) async => null),
          ],
          child: MaterialApp(
            theme: AppTheme.current,
            builder: (context, child) => MediaQuery(data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)), child: child!),
            home: screen,
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    Future<void> next(WidgetTester tester) async {
      await tester.tap(find.byKey(const Key('plan-next')));
      await tester.pumpAndSettle();
    }

    testWidgets('Next is held back until the step is answered', (tester) async {
      await pump(tester, const CreateEventScreen(session: true, showMap: false));
      expect(find.text('Where?'), findsOneWidget);
      expect(find.text('Step 1 of 5 · Where'), findsOneWidget);
      expect(find.text('Use my location'), findsOneWidget);
      expect(find.byKey(const Key('plan-back')), findsNothing);
      await next(tester);
      expect(find.byKey(const Key('plan-error')), findsOneWidget);
      expect(find.text('Where?'), findsOneWidget, reason: 'still on the first step');
    });

    testWidgets('a TT session: every step in order, Back keeps the answers, Edit returns to the review', (tester) async {
      await pump(tester, const CreateEventScreen(session: true, showMap: false, at: _mamak, venue: 'Mamak Sri Melur'));
      // Opened on a place: straight to When.
      expect(find.text('When?'), findsOneWidget);
      expect(find.text('Step 2 of 5 · When'), findsOneWidget);
      await tester.tap(find.byKey(const Key('plan-quick-Tomorrow night')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('3 h'));
      await tester.pumpAndSettle();

      // Back to Where: the place is still there.
      await tester.tap(find.byKey(const Key('plan-back')));
      await tester.pumpAndSettle();
      expect(find.text('Where?'), findsOneWidget);
      expect(tester.widget<TextField>(find.byKey(const Key('plan-venue'))).controller!.text, 'Mamak Sri Melur');

      await next(tester); // When, answers kept
      expect(tester.widget<Semantics>(find.ancestor(of: find.text('Tomorrow night'), matching: find.byType(Semantics)).first).properties.selected, isTrue);
      await next(tester); // Who
      expect(find.text('Who\'s it for?'), findsOneWidget);
      await tester.tap(find.byKey(const Key('plan-audience-everyone')));
      await tester.pumpAndSettle();
      await next(tester); // Make it yours
      expect(find.text('Make it yours'), findsOneWidget);
      final title = find.byKey(const Key('plan-title'));
      expect(tester.widget<TextField>(title).controller!.text, 'TT @ Mamak Sri Melur');

      // An empty title stops Next.
      await tester.enterText(title, '');
      await next(tester);
      expect(find.byKey(const Key('plan-error')), findsOneWidget);
      expect(find.text('Make it yours'), findsOneWidget);
      await tester.enterText(title, 'Friday teh tarik');
      await tester.tap(find.byKey(const Key('plan-cover-club')));
      await tester.pumpAndSettle();
      await next(tester);

      // Review: the summary, then Edit → Where → back to the review.
      expect(find.text('Looks good?'), findsOneWidget);
      expect(find.text('Friday teh tarik'), findsOneWidget);
      expect(find.text('Everyone on TT Spot'), findsOneWidget);
      expect(find.textContaining('3 h'), findsOneWidget);
      expect(find.text('Post TT session'), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, 'Edit').first);
      await tester.pumpAndSettle();
      expect(find.text('Where?'), findsOneWidget);
      expect(find.text('Back to review'), findsOneWidget);
      await next(tester);
      expect(find.text('Looks good?'), findsOneWidget);
      expect(find.text('Friday teh tarik'), findsOneWidget, reason: 'the typed title survived the round trip');
    });

    testWidgets('a hosted meet asks what kind first and suggests the title from it', (tester) async {
      await pump(tester, const CreateEventScreen(vendorId: 'v1', showMap: false, at: _mamak, venue: 'Auto Lab'));
      expect(find.text('What kind of meet?'), findsOneWidget);
      expect(find.text('Step 1 of 6 · What kind'), findsOneWidget);
      await tester.tap(find.byKey(const Key('plan-kind-convoy')));
      await tester.pumpAndSettle();
      await next(tester); // Where (already filled)
      expect(find.text('Where?'), findsOneWidget);
      await next(tester); // When
      expect(find.text('HOW LONG'), findsNothing, reason: 'meets have no duration');
      await next(tester); // Who: a partner doesn't invite friends
      expect(find.textContaining('INVITE FRIENDS'), findsNothing);
      await next(tester); // Make it yours
      expect(tester.widget<TextField>(find.byKey(const Key('plan-title'))).controller!.text, 'Convoy @ Auto Lab');
      await next(tester);
      expect(find.text('Publish meet'), findsOneWidget);
    });

    for (final scale in [1.0, 1.3]) {
      testWidgets('every step lays out at text x$scale', (tester) async {
        await pump(tester, const CreateEventScreen(session: true, showMap: false, at: _mamak, venue: 'Restoran Nasi Kandar Pelita Jalan Ampang'), scale: scale);
        for (var i = 0; i < 3; i++) {
          expect(tester.takeException(), isNull);
          await next(tester);
        }
        expect(find.text('Looks good?'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.tap(find.byKey(const Key('plan-back')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('plan-back')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('plan-back')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('plan-back')));
        await tester.pumpAndSettle();
        expect(find.text('Where?'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  });
}
