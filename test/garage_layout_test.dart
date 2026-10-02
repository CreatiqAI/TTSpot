import 'package:car_meet/core/theme/app_theme.dart';
import 'package:car_meet/features/profile/domain/car.dart';
import 'package:car_meet/features/profile/domain/car_documents.dart';
import 'package:car_meet/features/profile/domain/car_mod.dart';
import 'package:car_meet/features/profile/domain/garage_look.dart';
import 'package:car_meet/features/profile/presentation/garage/collector_card.dart';
import 'package:car_meet/features/profile/presentation/garage/garage_bay.dart';
import 'package:car_meet/features/profile/presentation/garage/garage_body.dart';
import 'package:car_meet/features/profile/presentation/garage/garage_panel.dart';
import 'package:car_meet/features/profile/presentation/garage/garage_scenery.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// The full-screen garage (GarageScene) on a small (360 x 640) and a tall
// (412 x 915) phone, at 100 % and 130 % text, bay and cards, owner and
// visitor, as its own route and inside the Home tab. Any overflow or layout
// error throws, and the car must stand big, whole and clear of the top bar
// and the panel.

const _base = 'https://x.supabase.co/storage/v1/object/public/car-photos/u1';
final _now = DateTime.now();
DateTime _days(int n) => DateTime(_now.year, _now.month, _now.day).add(Duration(days: n));

Car _cutout() => Car(
      id: 'a',
      ownerId: 'u1',
      make: 'Porsche',
      model: '911 Carrera',
      year: 2021,
      photoUrls: const ['$_base/a.jpg'],
      createdAt: DateTime(2026, 9, 1),
      isDefault: true,
      specs: '3.0 L twin-turbo · 385 hp · 8-speed PDK · RWD',
      bodyStyle: 'coupe',
      cutoutUrl: '$_base/a_cut.png',
      cutoutSource: '$_base/a.jpg',
    );

Car _carded() => Car(
      id: 'b',
      ownerId: 'u1',
      make: 'Honda',
      model: 'Civic Type R FL5 with a very long name',
      year: 2023,
      photoUrls: const ['$_base/b.jpg'],
      createdAt: DateTime(2026, 9, 2),
      bodyStyle: 'hatchback',
      color: 'white',
    );

CarMod _mod(String id, ModCategory cat, String title, {double? cost, int daysAgo = 30}) => CarMod(
      id: id,
      carId: 'a',
      category: cat,
      title: title,
      cost: cost,
      doneOn: _days(-daysAgo),
      photoUrls: const [],
      isPrivate: false,
      createdAt: _days(-daysAgo),
    );

final _richFacts = GarageFacts(
  mods: [
    _mod('m1', ModCategory.wheels, 'Forged 20 inch wheels with a really long name that wraps', cost: 18500, daysAgo: 21),
    _mod('m2', ModCategory.exhaust, 'Titanium exhaust', cost: 24000, daysAgo: 60),
    _mod('m3', ModCategory.body, 'Full-front PPF', cost: 6500, daysAgo: 400),
    _mod('m4', ModCategory.audio, 'Focal speakers', daysAgo: 90),
  ],
  meets: 7,
  posts: 12,
  papers: CarDocuments(carId: 'a', roadTaxExpiry: _days(72), insuranceExpiry: _days(10), puspakomDue: _days(-12)),
  papersLoaded: true,
);

const _emptyFacts = GarageFacts(mods: [], meets: 0, posts: 0, papersLoaded: true);

enum _Host { route, home }

final _calls = <String>[];

/// Holds the bay index like GarageBody does, and records every callback.
class _Harness extends StatefulWidget {
  const _Harness({required this.view, required this.mine, required this.host, this.parking = const {}});
  final GarageView view;
  final bool mine;
  final _Host host;
  final Set<String> parking;

  @override
  State<_Harness> createState() => _HarnessState();
}

class _HarnessState extends State<_Harness> {
  int index = 0;
  final cars = [_cutout(), _carded()];

  @override
  Widget build(BuildContext context) {
    final mine = widget.mine;
    final inset = MediaQuery.paddingOf(context).bottom;
    return GarageScene(
      cars: cars,
      index: index,
      onIndex: (i) => setState(() => index = i),
      mine: mine,
      view: widget.view,
      title: mine ? 'My garage' : 'titi_onboard1\'s garage',
      todayId: 'a',
      parking: widget.parking,
      facts: index == 0 ? _richFacts : _emptyFacts,
      // Home keeps clear of the floating tab bar (64 + 10 + 12).
      bottomPadding: widget.host == _Host.home ? 86 : inset + 12,
      onBack: widget.host == _Host.route ? () => _calls.add('back') : null,
      onToggleView: () => _calls.add('toggle'),
      onAdd: mine ? () => _calls.add('add') : null,
      onOpen: (c) => _calls.add('open:${c.id}'),
      onMore: mine ? (c) => _calls.add('more:${c.id}') : null,
      onMakeToday: mine ? (c) => _calls.add('today:${c.id}') : null,
      onEdit: mine ? (c) => _calls.add('edit:${c.id}') : null,
      onPapers: mine ? (c) => _calls.add('papers:${c.id}') : null,
      onRefresh: () async => _calls.add('refresh'),
    );
  }
}

Future<void> _pump(
  WidgetTester tester, {
  required Size size,
  required double scale,
  required GarageView view,
  bool mine = true,
  _Host host = _Host.route,
  Set<String> parking = const {},
}) async {
  tester.view.physicalSize = size * 3;
  tester.view.devicePixelRatio = 3;
  tester.view.padding = const FakeViewPadding(top: 24 * 3, bottom: 16 * 3);
  addTearDown(tester.view.reset);
  _calls.clear();
  final harness = _Harness(view: view, mine: mine, host: host, parking: parking);
  await tester.pumpWidget(MaterialApp(
    theme: AppTheme.current,
    home: Builder(
      builder: (context) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
        child: host == _Host.route
            ? Scaffold(body: harness)
            // Home: the app bar with the Feed / Garage tabs above, the
            // floating tab bar over the bottom.
            : Scaffold(
                appBar: AppBar(title: const Text('TT Spot'), bottom: const PreferredSize(preferredSize: Size.fromHeight(48), child: SizedBox(height: 48))),
                body: MediaQuery.removePadding(context: context, removeBottom: true, child: harness),
              ),
      ),
    ),
  ));
  await tester.pump(const Duration(milliseconds: 50));
  // Decode the pictures for real, so the cut-out fades in.
  await tester.runAsync(() async {
    final context = tester.element(find.byType(GarageScene));
    await precacheImage(const AssetImage('assets/cars/coupe.png'), context);
    await precacheImage(ResizeImage(const AssetImage('assets/portrait_samples/showroom.webp'), width: 820, policy: ResizeImagePolicy.fit), context);
  });
  await tester.pump(const Duration(milliseconds: 50));
}

/// [text] in the panel (the cards on the stage carry the name too).
Finder _inPanel(String text) => find.descendant(of: find.byType(PanelGlass), matching: find.text(text));

Rect _screen(WidgetTester tester) => tester.getRect(find.byType(GarageScene));
double _barBottom(WidgetTester tester) => tester.getRect(find.byType(GarageTopBar)).bottom;
double _panelTop(WidgetTester tester) => tester.getRect(find.byType(PanelGlass)).top;

/// The cut-out car's slot (the image is fitted inside it, never cropped).
Rect _cutoutRect(WidgetTester tester) => tester.getRect(find.descendant(of: find.byType(StandingCutout), matching: find.byType(Image)).last);

Rect _standingCard(WidgetTester tester, String id) =>
    tester.getRect(find.descendant(of: find.byKey(ValueKey(id)), matching: find.byType(CollectorCard)).last);

Future<void> _settle(WidgetTester tester) async {
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
}

/// Scrolls the open panel until [finder] is in view.
Future<void> _reveal(WidgetTester tester, Finder finder) async {
  await Scrollable.ensureVisible(tester.element(finder), alignment: 0.5);
  await _settle(tester);
}

Future<void> _openPanel(WidgetTester tester) async {
  await tester.tap(find.bySemanticsLabel('Show more'));
  await _settle(tester);
}

Future<void> _closePanel(WidgetTester tester) async {
  await tester.tap(find.bySemanticsLabel('Show less'));
  await _settle(tester);
}

/// Swipes the bay (on the back wall, clear of the car and the panel).
Future<void> _swipe(WidgetTester tester, {required bool next}) async {
  final s = _screen(tester);
  final y = _barBottom(tester) + 30;
  await tester.dragFrom(Offset(s.center.dx + (next ? 80 : -80), y), Offset(next ? -s.width * 0.6 : s.width * 0.6, 0));
  await _settle(tester);
}

void main() {
  setUp(() {
    // No network in tests: the cut-out is a bundled transparent car, every
    // photo a bundled picture.
    garageImageFor = (url) => url.endsWith('_cut.png') ? const AssetImage('assets/cars/coupe.png') : const AssetImage('assets/portrait_samples/showroom.webp');
  });

  const sizes = {'small 360x640': Size(360, 640), 'tall 412x915': Size(412, 915)};

  for (final entry in sizes.entries) {
    for (final scale in [1.0, 1.3]) {
      final mode = '${entry.key} @$scale';
      final size = entry.value;

      testWidgets('bay, owner ($mode): door over the whole screen, big car on the floor, panel opens, swipe, empty bay', (tester) async {
        GarageBayStage.debugResetDoor();
        await _pump(tester, size: size, scale: scale, view: GarageView.bay);
        final screen = _screen(tester);
        expect(screen.size, size);

        // The roller door covers the whole screen; the panel waits below it.
        expect(find.text('PRIVATE GARAGE'), findsOneWidget);
        final door = tester.getRect(find.ancestor(of: find.text('PRIVATE GARAGE'), matching: find.byType(RepaintBoundary)).first);
        expect(door, screen);
        expect(_panelTop(tester), greaterThanOrEqualTo(screen.bottom));
        await tester.pump(const Duration(milliseconds: 4000));
        await _settle(tester);
        expect(find.text('PRIVATE GARAGE'), findsNothing);

        // Collapsed panel: ~a quarter of the screen with the name and buttons.
        final top = _barBottom(tester);
        final panelTop = _panelTop(tester);
        final collapsed = (screen.bottom - panelTop) / screen.height;
        expect(collapsed, inInclusiveRange(0.2, 0.38));
        expect(find.text('911 Carrera'), findsOneWidget);
        expect(find.text('PORSCHE · 2021'), findsOneWidget);
        expect(find.text('TODAY\'S CAR'), findsOneWidget);
        expect(find.text('3.0 L twin-turbo · 385 hp · 8-speed PDK · RWD'), findsOneWidget);
        expect(find.text('Edit').hitTestable(), findsOneWidget);
        expect(find.text('Open car').hitTestable(), findsOneWidget);
        // Two cars and the empty bay.
        expect(find.bySemanticsLabel(RegExp(r'^Bay \d$')), findsNWidgets(3));

        // The car: ~88 % of the width, centred, standing between the top bar
        // and the panel.
        final car = _cutoutRect(tester);
        expect(car.width / screen.width, closeTo(0.88, 0.015));
        expect(car.center.dx, closeTo(screen.center.dx, 1));
        expect(car.top, greaterThanOrEqualTo(top - 0.5));
        expect(car.bottom, lessThanOrEqualTo(panelTop));

        await tester.tap(find.text('Open car').hitTestable());
        await tester.tap(find.text('Edit').hitTestable());
        await tester.tap(find.bySemanticsLabel('More'));
        await tester.longPress(find.bySemanticsLabel('Porsche 911 Carrera'));
        expect(_calls, ['open:a', 'edit:a', 'more:a', 'more:a']);

        // Pulled up: the numbers, the papers and the latest mods; the car
        // rises and shrinks to stay in view above the panel.
        await _openPanel(tester);
        final openTop = _panelTop(tester);
        final open = (screen.bottom - openTop) / screen.height;
        expect(open, greaterThan(collapsed + 0.1));
        expect(open, lessThanOrEqualTo(size.height > 800 ? 0.62 : 0.72));
        for (final label in ['Mods', 'Spent', 'Meets', 'Posts', 'PAPERS', 'RECENT MODS']) {
          expect(find.text(label), findsOneWidget, reason: label);
        }
        expect(find.text('RM 49k'), findsOneWidget);
        expect(find.text('7'), findsOneWidget);
        expect(find.text('Insurance · 10 days left'), findsOneWidget);
        expect(find.text('Titanium exhaust'), findsOneWidget);
        expect(find.text('4 in all'), findsOneWidget);
        final lifted = _cutoutRect(tester);
        expect(lifted.top, greaterThanOrEqualTo(top - 0.5));
        expect(lifted.bottom, lessThanOrEqualTo(openTop + 1));
        await tester.tap(find.text('Insurance · 10 days left'));
        expect(_calls.last, 'papers:a');
        // The end of the panel scrolls into reach: Open car again.
        await _reveal(tester, find.text('Open car').last);
        expect(find.text('Open car').last.hitTestable(), findsOneWidget);
        await tester.tap(find.text('Open car').last);
        expect(_calls.last, 'open:a');
        await _reveal(tester, find.bySemanticsLabel('Show less'));
        await _closePanel(tester);
        expect(_panelTop(tester), closeTo(panelTop, 1));

        // Swipe to the second car: it stands as its card, the panel follows.
        await _swipe(tester, next: true);
        expect(_inPanel('Civic Type R FL5 with a very long name'), findsOneWidget);
        expect(find.text('Hatchback · White'), findsOneWidget);
        expect(find.text('Make today\'s car').hitTestable(), findsOneWidget);
        expect(_panelTop(tester), closeTo(panelTop, 1));
        final card = _standingCard(tester, 'b');
        expect(card.top, greaterThanOrEqualTo(top - 0.5));
        expect(card.bottom, lessThanOrEqualTo(panelTop));
        expect(card.center.dx, closeTo(screen.center.dx, 1));
        await tester.tap(find.text('Make today\'s car').hitTestable());
        expect(_calls.last, 'today:b');
        await _openPanel(tester);
        expect(find.text('No mods logged yet. Add them on the car page.'), findsOneWidget);
        expect(find.text('Add road tax and insurance dates'), findsOneWidget);
        await _closePanel(tester);

        // The empty bay, full screen: a big plus on the floor, and the same
        // panel height with Add a car (nothing to pull up).
        await tester.tap(find.bySemanticsLabel('Next car'));
        await _settle(tester);
        expect(find.text('PARK ANOTHER CAR'), findsOneWidget);
        expect(find.text('Park another car'), findsOneWidget);
        expect(find.bySemanticsLabel('Show more'), findsNothing);
        expect(_panelTop(tester), closeTo(panelTop, 1));
        final plusFinder = find.descendant(of: find.byType(GarageBayStage), matching: find.bySemanticsLabel('Park another car'));
        final plus = tester.getRect(plusFinder);
        expect(plus.top, greaterThanOrEqualTo(top));
        expect(plus.bottom, lessThanOrEqualTo(panelTop));
        await tester.tap(plusFinder);
        await tester.tap(find.text('Add a car').hitTestable());
        await tester.tap(find.descendant(of: find.byType(GarageTopBar), matching: find.bySemanticsLabel('Add a car')));
        expect(_calls.sublist(_calls.length - 3), ['add', 'add', 'add']);

        // Top bar: back and the view toggle.
        await tester.tap(find.bySemanticsLabel('Back'));
        await tester.tap(find.bySemanticsLabel('Cards view'));
        expect(_calls.sublist(_calls.length - 2), ['back', 'toggle']);
        expect(tester.takeException(), isNull);
      });

      testWidgets('cards, owner ($mode): a big card centred between the bar and the panel', (tester) async {
        await _pump(tester, size: size, scale: scale, view: GarageView.cards);
        await _settle(tester);
        final screen = _screen(tester);
        final top = _barBottom(tester);
        final panelTop = _panelTop(tester);
        expect((screen.bottom - panelTop) / screen.height, inInclusiveRange(0.2, 0.38));

        final card = tester.getRect(find.byKey(const ValueKey('a')));
        // Bigger than the old deck's (at most 60 % of the width, 252 px).
        expect(card.width, greaterThanOrEqualTo(size.width * (size.height > 800 ? 0.68 : 0.55)));
        expect(card.center.dx, closeTo(screen.center.dx, 1));
        expect(card.top, greaterThanOrEqualTo(top));
        expect(card.bottom, lessThanOrEqualTo(panelTop));
        expect(_inPanel('911 Carrera'), findsOneWidget);
        expect(find.bySemanticsLabel('Bay view'), findsOneWidget);

        await _openPanel(tester);
        final openTop = _panelTop(tester);
        final shrunk = tester.getRect(find.byKey(const ValueKey('a')));
        expect(shrunk.top, greaterThanOrEqualTo(top - 0.5));
        expect(shrunk.bottom, lessThanOrEqualTo(openTop + 1));
        expect(find.text('Spent'), findsOneWidget);
        await _closePanel(tester);

        await tester.drag(find.byKey(const ValueKey('a')), const Offset(-220, 0));
        await _settle(tester);
        expect(find.text('Make today\'s car').hitTestable(), findsOneWidget);
        await tester.tap(find.bySemanticsLabel('Next car'));
        await _settle(tester);
        expect(find.text('PARK ANOTHER CAR'), findsOneWidget);
        expect(find.text('Add a car').hitTestable(), findsOneWidget);
        expect(tester.takeException(), isNull);
      });

      testWidgets('bay, visitor ($mode): read-only, no prices or papers', (tester) async {
        await _pump(tester, size: size, scale: scale, view: GarageView.bay, mine: false);
        await tester.pump(const Duration(milliseconds: 4000));
        await _settle(tester);
        expect(find.text('titi_onboard1\'s garage'), findsOneWidget);
        expect(find.bySemanticsLabel('Add a car'), findsNothing);
        expect(find.text('DAILY'), findsOneWidget);
        expect(find.text('Edit'), findsNothing);
        expect(find.text('Make today\'s car'), findsNothing);
        expect(find.bySemanticsLabel('More'), findsNothing);
        expect(find.bySemanticsLabel(RegExp(r'^Bay \d$')), findsNWidgets(2));
        final car = _cutoutRect(tester);
        expect(car.width / size.width, closeTo(0.88, 0.015));
        expect(car.bottom, lessThanOrEqualTo(_panelTop(tester)));

        await _openPanel(tester);
        expect(find.text('Spent'), findsNothing);
        expect(find.text('PAPERS'), findsNothing);
        expect(find.text('Meets'), findsOneWidget);
        // No menu on someone else's car: a long press just opens it.
        await tester.longPress(find.bySemanticsLabel('Porsche 911 Carrera'));
        await tester.tap(find.text('Open car').hitTestable().first);
        expect(_calls, ['open:a', 'open:a']);

        await _closePanel(tester);
        await _swipe(tester, next: true);
        expect(_inPanel('Civic Type R FL5 with a very long name'), findsOneWidget);
        // The last car: no empty bay after it.
        await _swipe(tester, next: true);
        expect(find.text('PARK ANOTHER CAR'), findsNothing);
        expect(tester.takeException(), isNull);
      });
    }
  }

  for (final scale in [1.0, 1.3]) {
    for (final view in GarageView.values) {
      testWidgets('home tab, small phone, ${view.name} @$scale: fits above the tab bar', (tester) async {
        GarageBayStage.debugResetDoor();
        await _pump(tester, size: const Size(360, 640), scale: scale, view: view, host: _Host.home);
        await tester.pump(const Duration(milliseconds: 4000));
        await _settle(tester);
        final screen = _screen(tester);
        final top = _barBottom(tester);
        final panelTop = _panelTop(tester);
        expect(find.bySemanticsLabel('Back'), findsNothing);
        expect(find.text('My garage'), findsOneWidget);
        // The buttons sit above the floating tab bar.
        final open = tester.getRect(find.text('Open car').hitTestable());
        expect(open.bottom, lessThanOrEqualTo(screen.bottom - 86));
        final car = view == GarageView.bay ? _cutoutRect(tester) : tester.getRect(find.byKey(const ValueKey('a')));
        expect(car.top, greaterThanOrEqualTo(top - 0.5));
        expect(car.bottom, lessThanOrEqualTo(panelTop));

        await _openPanel(tester);
        await _reveal(tester, find.text('Open car').last);
        expect(find.text('Open car').last.hitTestable(), findsOneWidget);
        await _reveal(tester, find.bySemanticsLabel('Show less'));
        await _closePanel(tester);
        await _swipe(tester, next: true);
        await _swipe(tester, next: true);
        expect(find.text('Park another car'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('parking a cut-out: the shimmering silhouette, no overflow at 130 % on a small phone', (tester) async {
    await _pump(tester, size: const Size(360, 640), scale: 1.3, view: GarageView.bay, parking: {'a'});
    await tester.pump(const Duration(milliseconds: 4000));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.text('Parking your car…'), findsOneWidget);
    final chip = tester.getRect(find.text('Parking your car…'));
    expect(chip.top, greaterThanOrEqualTo(_barBottom(tester)));
    expect(chip.bottom, lessThanOrEqualTo(_panelTop(tester)));
    expect(tester.takeException(), isNull);
  });

  testWidgets('a tablet: the car scales with the screen and is never cropped', (tester) async {
    await _pump(tester, size: const Size(820, 1180), scale: 1.0, view: GarageView.bay);
    await tester.pump(const Duration(milliseconds: 4000));
    await _settle(tester);
    final car = _cutoutRect(tester);
    expect(car.width / 820, closeTo(0.88, 0.015));
    expect(car.top, greaterThanOrEqualTo(_barBottom(tester)));
    expect(car.bottom, lessThanOrEqualTo(_panelTop(tester)));
    // The panel keeps a readable width, centred.
    final panel = tester.getRect(find.byType(PanelGlass));
    expect(panel.width, 640);
    expect(panel.center.dx, closeTo(410, 1));
    expect(tester.takeException(), isNull);
  });

  test('the car looks the same in the test fixtures as in the app', () {
    expect(garageLookFor(_cutout()), GarageLook.cutout);
    expect(garageLookFor(_carded()), GarageLook.card);
  });
}
