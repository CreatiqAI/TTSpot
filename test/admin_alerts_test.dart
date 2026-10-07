import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:car_meet/core/push/in_app_notice.dart';
import 'package:car_meet/core/router/app_router.dart';
import 'package:car_meet/core/theme/app_icons.dart';
import 'package:car_meet/core/theme/app_theme.dart';
import 'package:car_meet/features/auth/domain/profile.dart';
import 'package:car_meet/features/social/domain/admin_alert.dart';
import 'package:car_meet/features/social/domain/notification.dart';
import 'package:car_meet/features/social/presentation/activity_screen.dart';

// Admin alerts (0.3.61): supabase/migrations/20261008000117_admin_alerts.sql
// writes `admin` rows to every admin; body `<kind>:<detail>`.

final _titi = Profile(id: 'u1', username: 'titi_onboard1', displayName: 'Titi', createdAt: DateTime(2026));

AppNotification _n(String body, {String? postId}) => AppNotification(
      id: 'n-$body',
      type: NotificationType.admin,
      actor: _titi,
      body: body,
      postId: postId,
      read: false,
      createdAt: DateTime.now(),
    );

void main() {
  group('parse', () {
    test('the type comes from the database', () {
      expect(NotificationType.fromDb('admin'), NotificationType.admin);
    });

    test('report: target type and reason (a reason may hold colons)', () {
      final a = AdminAlert.parse('report:post:Spam: selling stuff')!;
      expect(a.kind, AdminAlertKind.report);
      expect(a.subject, 'post');
      expect(a.detail, 'Spam: selling stuff');
    });

    test('spot and verify: the whole rest is the place name', () {
      expect(AdminAlert.parse('spot:Cafe: The Garage')!.subject, 'Cafe: The Garage');
      expect(AdminAlert.parse('verify:Devi\'s Corner, Bangsar')!.subject, "Devi's Corner, Bangsar");
    });

    test('flagged: post or moment, then the categories', () {
      final a = AdminAlert.parse('flagged:moment:violence')!;
      expect(a.kind, AdminAlertKind.flagged);
      expect(a.subject, 'moment');
      expect(a.detail, 'violence');
      expect(AdminAlert.parse('flagged:post:')!.detail, '');
    });

    test('anything else is not an admin alert', () {
      expect(AdminAlert.parse(null), isNull);
      expect(AdminAlert.parse('hello'), isNull);
      expect(AdminAlert.parse('applied:Auto Lab'), isNull);
    });
  });

  group('copy and routes', () {
    test('titles are short', () {
      expect(AdminAlert.parse('report:post:x')!.title, 'Report');
      expect(AdminAlert.parse('spot:x')!.title, 'Spot suggested');
      expect(AdminAlert.parse('verify:x')!.title, 'Photo to check');
      expect(AdminAlert.parse('flagged:post:x')!.title, 'Flagged post');
      expect(AdminAlert.parse('flagged:moment:x')!.title, 'Flagged moment');
    });

    test('one-line sentences', () {
      expect(AdminAlert.parse('report:post:Spam')!.sentence(who: 'titi'), 'New report on a post: Spam');
      expect(AdminAlert.parse('report:profile:')!.sentence(), 'New report on a member');
      expect(AdminAlert.parse('report:post_comment:Rude')!.sentence(), 'New report on a comment: Rude');
      expect(AdminAlert.parse('report:story:x')!.sentence(), 'New report on a moment: x');
      expect(AdminAlert.parse('spot:Nadayu28')!.sentence(who: 'titi'), 'Spot suggested by @titi: Nadayu28');
      expect(AdminAlert.parse('verify:Nadayu28')!.sentence(who: 'titi'), 'Spot photo to check by @titi at Nadayu28');
      expect(AdminAlert.parse('flagged:moment:violence')!.sentence(who: 'titi'), 'Photo check hid a moment by @titi (violence). Approve or remove it.');
      expect(AdminAlert.parse('flagged:post:')!.sentence(), 'Photo check hid a post. Approve or remove it.');
    });

    test('each kind opens its queue', () {
      expect(AdminAlert.parse('report:post:x')!.route, Routes.adminQueues);
      expect(AdminAlert.parse('spot:x')!.route, Routes.adminSuggestions);
      expect(AdminAlert.parse('verify:x')!.route, Routes.adminReview);
      expect(AdminAlert.parse('flagged:post:x')!.route, Routes.adminModeration);
    });

    test('Activity text and route', () {
      final (text, route) = activityText(_n('report:club:Fake club'));
      expect(text, 'New report on a club: Fake club');
      expect(route, Routes.adminQueues);
      // An unknown body still opens the queues.
      expect(activityText(_n('something new')), ('something new', Routes.adminQueues));
    });

    test('the push function uses the same titles and routes', () {
      final ts = File('supabase/functions/push/index.ts').readAsStringSync();
      for (final s in ['case "admin"', '"Report"', '"Spot suggested"', '"Photo to check"', '"Flagged moment"', '"Flagged post"']) {
        expect(ts.contains(s), isTrue, reason: s);
      }
      for (final r in [Routes.adminQueues, Routes.adminSuggestions, Routes.adminReview, Routes.adminModeration]) {
        expect(ts.contains('"$r"'), isTrue, reason: r);
      }
    });

    test('the in-app banner gets a shield', () {
      final n = InAppNotice.fromPush({'kind': 'admin', 'title': 'Report', 'body': 'New report on a post', 'route': '/admin/queues'})!;
      expect(n.badge, AppIcons.shieldCheck);
      expect(n.route, '/admin/queues');
    });
  });

  group('widgets', () {
    tearDown(() => AppColors.dark = false);

    Future<void> pumpRows(WidgetTester tester, List<AppNotification> rows, {double scale = 1.0}) async {
      tester.view.physicalSize = const Size(320 * 3, 780 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final router = GoRouter(routes: [
        GoRoute(path: '/', builder: (_, _) => Scaffold(body: ListView(children: [for (final n in rows) ActivityRow(n: n, badges: const [], me: 'me')]))),
        for (final p in ['queues', 'review', 'moderation'])
          GoRoute(path: '/admin/$p', builder: (_, s) => Scaffold(body: Text('admin $p ${s.uri.queryParameters['open'] ?? ''}'.trim()))),
      ]);
      await tester.pumpWidget(ProviderScope(
        child: MaterialApp.router(
          theme: AppTheme.current,
          routerConfig: router,
          builder: (context, child) => MediaQuery(data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)), child: child!),
        ),
      ));
      await tester.pumpAndSettle();
    }

    List<AppNotification> rows() => [
          _n('report:post:This is a really long reason somebody typed about a post they did not like at all, really long'),
          _n('spot:Restoran Nasi Kandar Pelita Bangsar Utama Jalan Telawi'),
          _n('verify:Persatuan Kereta Myvi Lembah Klang Selangor Car Park'),
          _n('flagged:moment:sexual, violence/graphic'),
        ];

    for (final dark in [false, true]) {
      for (final scale in [1.0, 1.3]) {
        testWidgets('admin rows fit at 320 wide (${dark ? 'dark' : 'light'}, font ×$scale)', (tester) async {
          AppColors.dark = dark;
          await pumpRows(tester, rows(), scale: scale);
          expect(find.byType(ActivityRow), findsNWidgets(4));
          expect(find.textContaining('New report on a post', findRichText: true), findsOneWidget);
          expect(find.textContaining('Spot suggested by @titi_onboard1', findRichText: true), findsOneWidget);
          expect(find.textContaining('Spot photo to check', findRichText: true), findsOneWidget);
          expect(find.textContaining('Photo check hid a moment', findRichText: true), findsOneWidget);
          // System rows: no actor name in bold before the sentence.
          expect(find.textContaining('titi_onboard1 New report', findRichText: true), findsNothing);
          expect(tester.takeException(), isNull);
        });
      }
    }

    testWidgets('each admin row opens its queue', (tester) async {
      for (final (i, page) in [(0, 'admin queues'), (1, 'admin queues suggestions'), (2, 'admin review'), (3, 'admin moderation')]) {
        await pumpRows(tester, rows());
        await tester.tap(find.byType(ActivityRow).at(i), warnIfMissed: false);
        await tester.pumpAndSettle();
        expect(find.text(page), findsOneWidget, reason: 'row $i');
      }
    });
  });
}
