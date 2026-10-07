import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:car_meet/features/expo/stamps/application/stamps_providers.dart';
import 'package:car_meet/features/expo/stamps/domain/stamps_models.dart';
import 'package:car_meet/features/events/application/event_providers.dart';
import 'package:car_meet/features/expo/stamps/presentation/booth_qr_sheet_screen.dart';
import 'package:car_meet/features/expo/stamps/presentation/booth_setup_screen.dart';
import 'package:car_meet/features/expo/stamps/presentation/leads_screen.dart';
import 'package:car_meet/features/expo/stamps/presentation/my_leads_section.dart';
import 'package:car_meet/features/expo/stamps/presentation/stamps_screen.dart';

/// Phone-sized surface at the given text scale, no overflow allowed.
Future<void> _pump(WidgetTester tester, Widget child, List overrides, {double scale = 1.3}) async {
  tester.view.physicalSize = const Size(360 * 3, 780 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(
    overrides: [...overrides],
    child: MaterialApp(
      builder: (c, w) => MediaQuery(data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(scale)), child: w!),
      home: child,
    ),
  ));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

final _card = StampCard(
  goal: 8,
  reward: 'Free TT Spot T-shirt and a sticker pack',
  checkedIn: true,
  stops: [
    StampStop(id: 'a', name: 'Brembo Malaysia Performance Brakes', booths: const ['A019', 'A024'], stampedAt: DateTime(2026, 10, 7, 14, 5), freebie: 'Brembo keychain', freebieState: FreebieState.available),
    const StampStop(id: 'b', name: 'Bosch', booths: ['B002'], freebie: 'Sticker', freebieState: FreebieState.locked, freebieLeft: 12),
    StampStop(id: 'c', name: 'Michelin', booths: const ['C10'], stampedAt: DateTime(2026, 10, 7, 15, 1), freebie: 'Tyre gauge', freebieState: FreebieState.redeemed, freebieRedeemedAt: DateTime(2026, 10, 7, 15, 3)),
    const StampStop(id: 'd', name: 'Shell Helix', booths: ['D1'], freebie: 'Cap', freebieState: FreebieState.out),
    for (var i = 0; i < 6; i++) StampStop(id: 'x$i', name: 'Exhibitor number $i with a long name', booths: ['E$i']),
  ],
);

void main() {
  for (final scale in [1.0, 1.3]) {
    testWidgets('StampsScreen at text scale $scale', (tester) async {
      await _pump(tester, const StampsScreen(eventId: 'e1'), [myStampsProvider.overrideWith((ref, id) async => _card)], scale: scale);
      expect(find.text('2 of 8 stamps'), findsOneWidget);
      expect(find.text('Scan a booth'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('Freebies'), 300);
      await tester.pump();
      expect(find.text('Ready to collect'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('StampsScreen: rally done shows Collect', (tester) async {
    final done = StampCard(goal: 1, reward: 'T-shirt', checkedIn: true, rally: RallyState.done, stops: [_card.stops.first]);
    await _pump(tester, const StampsScreen(eventId: 'e1'), [myStampsProvider.overrideWith((ref, id) async => done)]);
    expect(find.text('Collect T-shirt'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('StampsScreen: no stops', (tester) async {
    await _pump(tester, const StampsScreen(eventId: 'e1'), [myStampsProvider.overrideWith((ref, id) async => const StampCard())]);
    expect(find.text('No stamp stops yet'), findsOneWidget);
  });

  testWidgets('BoothSetupScreen at text scale 1.3', (tester) async {
    final rows = [
      const BoothSetupRow(
        id: 'aaaaaaaa-1',
        name: 'Brembo Malaysia Performance Brakes Sdn Bhd',
        booths: ['A019', 'A024'],
        stampStop: true,
        freebie: 'Keychain',
        freebieLimit: 200,
        stampCode: 'abc',
        stamps: 120,
        freebiesRedeemed: 80,
        leads: 14,
        staff: [BoothStaff(userId: 'u1', username: 'brembo_staff_one', name: 'Staff')],
      ),
      const BoothSetupRow(id: 'bbbbbbbb-2', name: 'Bosch', booths: ['B002']),
    ];
    await _pump(tester, const BoothSetupScreen(eventId: 'e1'), [
      boothSetupProvider.overrideWith((ref, id) async => rows),
      rallySettingsProvider.overrideWith((ref, id) async => const RallySettings(goal: 8, reward: 'T-shirt')),
    ]);
    expect(find.text('Stamp rally'), findsOneWidget);
    expect(find.text('@brembo_staff_one'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Bosch'), 300, scrollable: find.byType(Scrollable).first);
    await tester.pump();
    expect(find.text('Add booth staff'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('BoothQrSheetScreen at text scale 1.3', (tester) async {
    final rows = [
      const BoothSetupRow(id: 'aaaaaaaa-1', name: 'Brembo Malaysia Performance Brakes Sdn Bhd', booths: ['A019', 'A024'], stampStop: true, freebie: 'Keychain', stampCode: 'abc123'),
      const BoothSetupRow(id: 'bbbbbbbb-2', name: 'Bosch', booths: ['B002'], stampStop: true, stampCode: 'def456'),
      const BoothSetupRow(id: 'cccccccc-3', name: 'Not a stop', booths: ['C1'], stampCode: 'x'),
    ];
    await _pump(tester, const BoothQrSheetScreen(eventId: 'e1'), [
      boothSetupProvider.overrideWith((ref, id) async => rows),
      eventDetailProvider.overrideWith((ref, id) async => null),
    ]);
    expect(find.text('Share all'), findsOneWidget);
    expect(find.text('A019 · A024'), findsOneWidget);
    expect(find.text('Not a stop'), findsNothing);
    expect(find.text('Scan with TT Spot to collect a stamp'), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });

  testWidgets('LeadsScreen at text scale 1.3', (tester) async {
    final leads = [
      Lead(
        id: 'l1',
        userId: 'u1',
        name: 'Ahmad Faizal bin Abdullah',
        username: 'faizal_fd2_turbo',
        state: 'Selangor',
        carMake: 'Honda',
        carModel: 'Civic FD2 Type R',
        createdAt: DateTime.now(),
        note: 'Wants a quote for a big brake kit, call after 6 PM',
        shared: true,
        phone: '+60123456789',
        email: 'faizal@example.com',
      ),
      Lead(id: 'l2', userId: 'u2', name: 'Mei', createdAt: DateTime(2026, 10, 6, 11)),
    ];
    await _pump(tester, const LeadsScreen(eventId: 'e1', exhibitorId: 'x1'), [
      exhibitorLeadsProvider.overrideWith((ref, id) async => leads),
      myStaffBoothsProvider.overrideWith((ref, id) async => const [StaffBooth(id: 'x1', name: 'Brembo Malaysia')]),
    ]);
    expect(find.text('2 leads'), findsOneWidget);
    expect(find.text('Brembo Malaysia'), findsOneWidget);
    expect(find.text('Add a note'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('MyLeadsSection hides when empty, lists booths otherwise', (tester) async {
    await _pump(tester, const Scaffold(body: MyLeadsSection(eventId: 'e1')), [myEventLeadsProvider.overrideWith((ref, id) async => const <MyLead>[])]);
    expect(find.text('Booths with your contact'), findsNothing);

    await _pump(tester, const Scaffold(body: MyLeadsSection(eventId: 'e2')), [
      myEventLeadsProvider.overrideWith((ref, id) async => const [MyLead(id: 'l1', exhibitorId: 'x1', exhibitorName: 'Brembo Malaysia Performance Brakes', booths: ['A019'])]),
    ]);
    expect(find.text('Booths with your contact'), findsOneWidget);
    expect(find.text('Remove'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
