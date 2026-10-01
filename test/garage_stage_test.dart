import 'package:car_meet/features/profile/domain/car.dart';
import 'package:car_meet/features/profile/presentation/garage/collector_card.dart';
import 'package:car_meet/features/profile/presentation/garage/garage_bay.dart';
import 'package:car_meet/features/profile/presentation/garage/garage_deck.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Car _car(String id, String model, {bool today = false}) => Car(
      id: id,
      ownerId: 'u1',
      make: 'Perodua',
      model: model,
      photoUrls: const [],
      createdAt: DateTime(2026, 9, 1),
      isDefault: today,
      bodyStyle: 'hatchback',
    );

/// A 390 x 844 phone with the system text size at 130 %.
Widget _host(WidgetTester tester, Widget child) {
  tester.view.physicalSize = const Size(1170, 2532);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  return MaterialApp(
    home: MediaQuery.withClampedTextScaling(
      minScaleFactor: 1.3,
      maxScaleFactor: 1.3,
      child: Scaffold(body: Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: child)),
    ),
  );
}

void main() {
  final cars = [_car('a', 'Myvi 1.5 AV', today: true), _car('b', 'Civic Type R FL5 with a very long name')];

  testWidgets('bay: the door rolls up, arrows move between bays, the last bay parks another car', (tester) async {
    var index = 0;
    var added = 0;
    final opened = <String>[];
    await tester.pumpWidget(_host(tester, StatefulBuilder(
      builder: (context, setState) => GarageBayStage(
        cars: cars,
        index: index,
        height: 380,
        onIndex: (i) => setState(() => index = i),
        onOpen: (c) => opened.add(c.id),
        onAdd: () => added++,
      ),
    )));
    // Door shut, then up after the intro.
    expect(find.text('PRIVATE GARAGE'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 4000));
    expect(find.text('PRIVATE GARAGE'), findsNothing);
    expect(find.text('01'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('Next car'));
    await tester.pumpAndSettle();
    expect(index, 1);
    expect(find.text('02'), findsOneWidget);

    // Swipe left to the empty bay.
    await tester.drag(find.byType(GarageBayStage), const Offset(-300, 0));
    await tester.pumpAndSettle();
    expect(index, 2);
    expect(find.text('PARK ANOTHER CAR'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Park another car'));
    expect(added, 1);

    // Back to the first car and open it.
    await tester.tap(find.bySemanticsLabel('Previous car'));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('Previous car'));
    await tester.pumpAndSettle();
    expect(index, 0);
    await tester.tap(find.descendant(of: find.byKey(const ValueKey('a')), matching: find.byType(CollectorCard)).last);
    expect(opened, ['a']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('bay: a second visit skips the door', (tester) async {
    await tester.pumpWidget(_host(tester, GarageBayStage(cars: cars, index: 0, height: 380, onIndex: (_) {}, onOpen: (_) {})));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('PRIVATE GARAGE'), findsNothing);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('cards: deals the deck, swipes, taps a side card to bring it forward', (tester) async {
    var index = 0;
    final opened = <String>[];
    await tester.pumpWidget(_host(tester, StatefulBuilder(
      builder: (context, setState) => GarageCardDeck(
        cars: cars,
        index: index,
        height: 420,
        todayId: 'a',
        onIndex: (i) => setState(() => index = i),
        onOpen: (c) => opened.add(c.id),
        onAdd: () {},
      ),
    )));
    await tester.pumpAndSettle();
    expect(find.text('BAY 01'), findsOneWidget);
    expect(find.text('TODAY'), findsOneWidget);

    await tester.drag(find.byType(GarageCardDeck), const Offset(-220, 0));
    await tester.pumpAndSettle();
    expect(index, 1);

    // The first car's card now leans in from the left: tap its visible part
    // to bring it forward, then tap it again to open it.
    final a = tester.getRect(find.byKey(const ValueKey('a')));
    await tester.tapAt(Offset(a.left + a.width * 0.45, a.center.dy + 50));
    await tester.pumpAndSettle();
    expect(index, 0);
    await tester.tap(find.byKey(const ValueKey('a')));
    expect(opened, ['a']);

    await tester.tap(find.bySemanticsLabel('Next car'));
    await tester.pumpAndSettle();
    expect(index, 1);
    expect(tester.takeException(), isNull);
  });
}
