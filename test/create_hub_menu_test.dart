import 'package:car_meet/core/theme/app_theme.dart';
import 'package:car_meet/features/accounts/application/active_account.dart';
import 'package:car_meet/features/profile/presentation/profile_menu.dart';
import 'package:car_meet/features/social/domain/club.dart';
import 'package:car_meet/features/social/presentation/create_hub_sheet.dart';
import 'package:car_meet/features/vendors/domain/vendor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

final _club = Club(id: 'c1', name: 'Myvi Owners KL', handle: 'myvi_kl', ownerId: 'u1', createdAt: DateTime(2026), memberCount: 12);
final _shop = Vendor(id: 'v1', name: 'Auto Lab', type: 'workshop', active: true, commissionRate: 0.01, createdAt: DateTime(2026));

Future<void> _pump(WidgetTester tester, Widget child, {double scale = 1.0}) async {
  tester.view.physicalSize = const Size(1080, 2340); // 393 x 851 at 2.75x
  tester.view.devicePixelRatio = 2.75;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.current,
      builder: (context, c) => MediaQuery(data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)), child: c!),
      home: Scaffold(body: SingleChildScrollView(padding: const EdgeInsets.all(16), child: child)),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('Create sheet', () {
    testWidgets('personal: TT NOW, Post, Moment, Plan a TT session on top; the rest behind More', (tester) async {
      final routes = <String>[];
      var ttNow = 0;
      await _pump(tester, CreateHubContent(account: const PersonalAccount(), onRoute: routes.add, onTtNow: () => ttNow++));
      expect(find.text('TT NOW'), findsOneWidget);
      expect(find.text('Post'), findsOneWidget);
      expect(find.text('Moment'), findsOneWidget);
      expect(find.text('Plan a TT session'), findsOneWidget);
      expect(find.text('More'), findsOneWidget);
      for (final hidden in ['Guide', 'Spotted', 'Poll', 'Ask TiTi', 'Suggest a spot', 'Add a car', 'Start a car club']) {
        expect(find.text(hidden), findsNothing, reason: '$hidden waits behind More');
      }

      await tester.tap(find.byKey(const Key('create-more')));
      await tester.pumpAndSettle();
      expect(find.text('Guide'), findsOneWidget);
      expect(find.text('Share your favourite route or a list of spots'), findsOneWidget);
      expect(find.text('Spotted'), findsOneWidget);
      expect(find.text('Poll'), findsOneWidget);
      expect(find.text('Start a car club'), findsOneWidget);

      await tester.tap(find.text('TT NOW'));
      expect(ttNow, 1);
      await tester.tap(find.text('Plan a TT session'));
      expect(routes.last, '/create-event?session=1');
    });

    testWidgets('club: post and plan a meet as the club; no TT NOW, no Moment', (tester) async {
      final routes = <String>[];
      await _pump(tester, CreateHubContent(account: ClubAccount(_club), onRoute: routes.add, onTtNow: () {}));
      expect(find.text('Create as Myvi Owners KL'), findsOneWidget);
      expect(find.text('As Myvi Owners KL'), findsOneWidget);
      expect(find.text('Club meet'), findsOneWidget);
      expect(find.text('TT NOW'), findsNothing);
      expect(find.text('Moment'), findsNothing);
      expect(find.text('Guide'), findsNothing);
      await tester.tap(find.text('Club meet'));
      expect(routes.last, '/create-event?club=c1');
      await tester.tap(find.byKey(const Key('create-more')));
      await tester.pumpAndSettle();
      expect(find.text('Poll'), findsOneWidget);
      expect(find.text('Guide'), findsOneWidget);
      expect(find.text('Start a car club'), findsNothing);
    });

    testWidgets('partner: post and host an event as the shop', (tester) async {
      final routes = <String>[];
      await _pump(tester, CreateHubContent(account: PartnerAccount(_shop), onRoute: routes.add, onTtNow: () {}));
      expect(find.text('Create as Auto Lab'), findsOneWidget);
      expect(find.text('Post'), findsOneWidget);
      expect(find.text('Event'), findsOneWidget);
      expect(find.text('TT NOW'), findsNothing);
      await tester.tap(find.text('Event'));
      expect(routes.last, '/create-event?vendor=v1');
      await tester.tap(find.byKey(const Key('create-more')));
      await tester.pumpAndSettle();
      expect(find.text('Poll'), findsOneWidget);
      expect(find.text('Spotted'), findsNothing);
    });

    for (final scale in [1.0, 1.3]) {
      testWidgets('lays out at text x$scale with More open', (tester) async {
        await _pump(tester, CreateHubContent(account: const PersonalAccount(), onRoute: (_) {}, onTtNow: () {}), scale: scale);
        await tester.tap(find.byKey(const Key('create-more')));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('Me menu', () {
    testWidgets('top layer: the everyday things and Log out; the rest under More', (tester) async {
      await _pump(tester, const ProfileMenuSheet(isAdmin: false, isVendor: false, canRunClubs: false, canSwitch: false));
      for (final label in ['Settings', 'Edit profile', 'Friends', 'Saved posts', 'Points & rewards', 'Cards & blind boxes', 'More', 'Log out']) {
        expect(find.text(label), findsOneWidget, reason: label);
      }
      for (final label in ['Switch account', 'My moments', 'Invite friends', 'Badges', 'Become a partner', 'Run a car club', 'Switch to TT Spot Admin']) {
        expect(find.text(label), findsNothing, reason: label);
      }

      await tester.tap(find.byKey(const Key('menu-more')));
      await tester.pumpAndSettle();
      for (final label in ['My moments', 'Invite friends', 'Badges', 'Run a car club', 'Become a partner', 'Apply to be an organizer']) {
        expect(find.text(label), findsOneWidget, reason: label);
      }
      expect(find.text('Switch to TT Spot Admin'), findsNothing);
      expect(find.text('Log out'), findsNothing);

      await tester.tap(find.byKey(const Key('menu-back')));
      await tester.pumpAndSettle();
      expect(find.text('Settings'), findsOneWidget);
    });

    testWidgets('Switch account only with a second account; admin and partner wording under More', (tester) async {
      await _pump(tester, const ProfileMenuSheet(isAdmin: true, isVendor: true, canRunClubs: true, canSwitch: true));
      expect(find.text('Switch account'), findsOneWidget);
      await tester.tap(find.byKey(const Key('menu-more')));
      await tester.pumpAndSettle();
      expect(find.text('Partner dashboard'), findsOneWidget);
      expect(find.text('My car club'), findsOneWidget);
      expect(find.text('Switch to TT Spot Admin'), findsOneWidget);
    });

    testWidgets('a row pops its action', (tester) async {
      String? picked;
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.current,
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async => picked = await showModalBottomSheet<String>(
                context: context,
                isScrollControlled: true,
                builder: (_) => const ProfileMenuSheet(isAdmin: false, isVendor: false, canRunClubs: false, canSwitch: false),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Points & rewards'));
      await tester.pumpAndSettle();
      expect(picked, 'points');
    });

    for (final scale in [1.0, 1.3]) {
      testWidgets('both layers lay out at text x$scale', (tester) async {
        await _pump(tester, const ProfileMenuSheet(isAdmin: true, isVendor: false, canRunClubs: false, canSwitch: true, bottomPadding: 100), scale: scale);
        expect(tester.takeException(), isNull);
        await tester.tap(find.byKey(const Key('menu-more')));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }
  });
}
