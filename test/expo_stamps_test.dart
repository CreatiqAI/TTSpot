import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:car_meet/features/expo/stamps/application/stamps_scan.dart';
import 'package:car_meet/features/expo/stamps/domain/stamps_models.dart';
import 'package:car_meet/features/expo/stamps/presentation/exhibitor_extras.dart';
import 'package:car_meet/features/expo/stamps/presentation/stamps_screen.dart';
import 'package:car_meet/features/expo/stamps/presentation/widgets/hand_over_card.dart';

Widget _wrap(Widget child, {double scale = 1.0}) => MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(size: const Size(360, 780), textScaler: TextScaler.linear(scale)),
        child: Scaffold(body: SingleChildScrollView(child: Padding(padding: const EdgeInsets.all(16), child: child))),
      ),
    );

void main() {
  group('CSV', () {
    test('plain cells pass through', () {
      expect(csvCell('Ali'), 'Ali');
      expect(csvCell(null), '');
      expect(csvCell(''), '');
    });

    test('commas, quotes and line breaks are quoted', () {
      expect(csvCell('Kuala Lumpur, MY'), '"Kuala Lumpur, MY"');
      expect(csvCell('the "FD2" guy'), '"the ""FD2"" guy"');
      expect(csvCell('line one\nline two'), '"line one\nline two"');
      expect(csvCell('cr\rhere'), '"cr\rhere"');
    });

    test('formula cells are defused, phone numbers are not', () {
      expect(csvCell('=HYPERLINK("x")'), '"\'=HYPERLINK(""x"")"');
      expect(csvCell('@SUM(A1)'), "'@SUM(A1)");
      expect(csvCell('+cmd'), "'+cmd");
      expect(csvCell('-2+3'), "'-2+3");
      expect(csvCell('+60123456789'), '+60123456789');
      expect(csvCell('+60 12-345 6789'), '+60 12-345 6789');
    });

    test('leadsCsv: BOM, header, CRLF rows, handle without @', () {
      final csv = leadsCsv([
        Lead(
          id: '1',
          userId: 'u1',
          name: 'Ali, Bin Abu',
          username: 'ali',
          state: 'Selangor',
          carMake: 'Honda',
          carModel: 'Civic FD2',
          createdAt: DateTime(2026, 10, 7, 14, 5),
          note: 'Wants "brake" kit',
          phone: '+60123456789',
          email: 'ali@example.com',
          shared: true,
        ),
        Lead(id: '2', userId: 'u2', name: 'Mei', createdAt: DateTime(2026, 10, 7, 9, 0)),
      ]);
      expect(csv.startsWith('﻿'), isTrue);
      final lines = csv.substring(1).split('\r\n');
      expect(lines[0], 'Name,Handle,State,Car,Phone,Email,Note,Saved at');
      expect(lines[1], '"Ali, Bin Abu",ali,Selangor,Honda Civic FD2,+60123456789,ali@example.com,"Wants ""brake"" kit",2026-10-07 14:05');
      expect(lines[2], 'Mei,,,,,,,2026-10-07 09:00');
      expect(lines[3], '');
      expect(lines.length, 4);
    });
  });

  group('models', () {
    test('StampCard parses and counts progress', () {
      final card = StampCard.fromMap({
        'goal': 2,
        'reward': 'Free T-shirt',
        'checked_in': true,
        'rally': 'done',
        'stops': [
          {'id': 'a', 'name': 'Bosch', 'booths': ['B002'], 'stamped_at': '2026-10-07T06:00:00Z', 'freebie': 'Sticker', 'freebie_state': 'available', 'freebie_left': null},
          {'id': 'b', 'name': 'Brembo', 'booths': ['A019', 'A024'], 'stamped_at': null, 'freebie': 'Keychain', 'freebie_state': 'locked', 'freebie_left': 3},
          {'id': 'c', 'name': 'Plain', 'booths': [], 'freebie_state': 'none'},
        ],
      });
      expect(card.stamped, 1);
      expect(card.target, 2);
      expect(card.progress, 0.5);
      expect(card.rally, RallyState.done);
      expect(card.freebies.map((s) => s.id), ['a', 'b']);
      expect(card.stop('b')!.freebieLeft, 3);
      expect(boothLabel(card.stop('b')!.booths), 'A019 · A024');
      expect(card.stop('a')!.freebieState, FreebieState.available);
    });

    test('no goal: progress counts every stop', () {
      final card = StampCard.fromMap({
        'stops': [
          {'id': 'a', 'name': 'A', 'stamped_at': '2026-10-07T06:00:00Z'},
          {'id': 'b', 'name': 'B'},
          {'id': 'c', 'name': 'C'},
          {'id': 'd', 'name': 'D'},
        ],
      });
      expect(card.hasRally, isFalse);
      expect(card.target, 4);
      expect(card.progress, 0.25);
    });

    test('FreebieState.parse', () {
      expect(FreebieState.parse('available'), FreebieState.available);
      expect(FreebieState.parse('out'), FreebieState.out);
      expect(FreebieState.parse('redeemed'), FreebieState.redeemed);
      expect(FreebieState.parse('locked'), FreebieState.locked);
      expect(FreebieState.parse(null), FreebieState.none);
    });

    test('StampResult titles', () {
      StampResult r(Map<String, dynamic> m) => StampResult.fromMap({'event_id': 'e', 'exhibitor_id': 'x', 'exhibitor_name': 'Brembo', ...m});
      expect(r({'new': true, 'stamps': 3, 'goal': 8}).title, 'Stamp 3 of 8');
      expect(r({'new': true, 'stamps': 3}).title, 'Booth stamped');
      expect(r({'new': false, 'stamps': 3, 'goal': 8}).title, 'Already stamped');

      final free = r({'new': true, 'stamps': 1, 'freebie': 'Keychain', 'freebie_left': 4});
      expect(free.freebieWaiting, isTrue);
      expect(free.subtitle, 'Brembo · Free Keychain waiting for you');

      expect(r({'freebie': 'Keychain', 'freebie_left': 0}).freebieWaiting, isFalse);
      expect(r({'freebie': 'Keychain', 'freebie_redeemed': true}).freebieWaiting, isFalse);
      expect(r({'freebie': 'Keychain', 'freebie_left': null}).freebieWaiting, isTrue);

      final done = r({'new': true, 'stamps': 8, 'goal': 8, 'rally_done': true, 'reward': 'T-shirt'});
      expect(done.subtitle, 'Brembo · Stamp rally done! Collect your T-shirt');
    });

    test('LeadSaved title', () {
      final l = LeadSaved.fromMap({'exhibitor_id': 'x', 'exhibitor_name': 'Bosch', 'new': true, 'name': 'Ali', 'username': 'ali', 'car': 'Honda Civic'});
      expect(l.title, 'Lead saved · Ali');
      expect(l.subtitle, 'Honda Civic · Bosch');
      expect(LeadSaved.fromMap({'exhibitor_id': 'x', 'exhibitor_name': 'Bosch', 'new': false, 'name': 'Ali'}).title, 'Already saved · Ali');
    });

    test('Lead car and contact', () {
      final l = Lead.fromMap({'id': '1', 'user_id': 'u', 'name': 'Ali', 'car_make': 'Honda', 'car_model': null, 'created_at': '2026-10-07T06:00:00Z', 'shared': false});
      expect(l.car, 'Honda');
      expect(l.hasContact, isFalse);
    });

    test('payloads and routes', () {
      expect(boothQrPayload('ex-1', 'abc123'), 'ttspot://booth/ex-1/abc123');
      expect(stampsRouteAfterScan('e1', null), '/event/e1/stamps');
      expect(stampsRouteAfterScan('e1', 'x1'), '/event/e1/stamps?freebie=x1');
      expect(leadsPickRoute('e1', 'x1', 'p a'), '/event/e1/booth/x1/leads?pass=p+a');
    });

    test('clock shows seconds', () {
      expect(clockWithSeconds(DateTime(2026, 10, 7, 14, 5, 9)), '2:05:09 PM');
      expect(clockWithSeconds(DateTime(2026, 10, 7, 0, 0, 0)), '12:00:00 AM');
    });
  });

  group('widgets', () {
    testWidgets('ExhibitorExtrasView draws nothing when nothing applies', (tester) async {
      await tester.pumpWidget(_wrap(const ExhibitorExtrasView(info: ExhibitorExtrasInfo())));
      expect(find.byType(InkWell), findsNothing);
    });

    testWidgets('ExhibitorExtrasView: stamp, freebie and leads lines', (tester) async {
      var leads = 0;
      await tester.pumpWidget(_wrap(
        ExhibitorExtrasView(
          info: const ExhibitorExtrasInfo(stampStop: true, freebie: 'Keychain', freebieState: FreebieState.locked, amStaff: true, leadCount: 12),
          onLeads: () => leads++,
        ),
        scale: 1.3,
      ));
      expect(find.text('Scan the booth QR to get a stamp'), findsOneWidget);
      expect(find.text('Free Keychain · stamp to unlock'), findsOneWidget);
      await tester.tap(find.text('Leads (12)'));
      expect(leads, 1);
      expect(tester.takeException(), isNull);
    });

    testWidgets('StampTile fits at text scale 1.3', (tester) async {
      await tester.pumpWidget(_wrap(
        Row(
          children: [
            SizedBox(
              width: 100,
              child: StampTile(
                stop: StampStop(id: 'a', name: 'Brembo Malaysia Performance Brakes', booths: const ['A019', 'A024'], stampedAt: DateTime(2026, 10, 7, 14, 5)),
                onTap: () {},
              ),
            ),
            const SizedBox(width: 10),
            SizedBox(width: 100, child: StampTile(stop: const StampStop(id: 'b', name: 'Bosch', booths: ['B002']), onTap: () {})),
          ],
        ),
        scale: 1.3,
      ));
      expect(find.text('B002'), findsOneWidget);
      expect(find.text('2:05 PM'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('SwipeToConfirm fires only on a full swipe', (tester) async {
      var calls = 0;
      await tester.pumpWidget(_wrap(SwipeToConfirm(label: 'Staff: swipe to hand over', onConfirmed: () async {
        calls++;
        return true;
      })));
      final track = find.byType(SwipeToConfirm);
      await tester.drag(track, const Offset(60, 0));
      await tester.pump(const Duration(milliseconds: 300));
      expect(calls, 0);
      await tester.drag(track, const Offset(1200, 0));
      await tester.pump(const Duration(milliseconds: 300));
      expect(calls, 1);
    });

    testWidgets('HandOverCard after hand over shows the time', (tester) async {
      await tester.pumpWidget(_wrap(
        HandOverCard(item: 'Keychain', kind: 'FREEBIE', from: 'Brembo', redeemedAt: DateTime(2026, 10, 7, 14, 14), onRedeem: () async => DateTime.now()),
        scale: 1.3,
      ));
      expect(find.text('Handed over · 2:14 PM'), findsOneWidget);
      expect(find.byType(SwipeToConfirm), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('HandOverCard live: clock and slider', (tester) async {
      await tester.pumpWidget(_wrap(
        HandOverCard(item: 'Keychain', kind: 'FREEBIE', from: 'Brembo', onRedeem: () async => DateTime.now()),
        scale: 1.3,
      ));
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('Show this to the booth staff'), findsOneWidget);
      expect(find.text('Staff: swipe to hand over'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox()); // dispose the ticking clock
    });
  });
}
