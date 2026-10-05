import 'package:car_meet/core/theme/app_theme.dart';
import 'package:car_meet/core/theme/titi.dart';
import 'package:car_meet/features/profile/domain/car.dart';
import 'package:car_meet/features/profile/domain/car_documents.dart';
import 'package:car_meet/features/profile/domain/car_mod.dart';
import 'package:car_meet/features/profile/presentation/garage/garage_facts.dart';
import 'package:car_meet/features/profile/presentation/garage/garage_images.dart';
import 'package:car_meet/features/profile/presentation/garage/garage_studio.dart';
import 'package:car_meet/features/profile/presentation/widgets/toy_car_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// The garage studio with 0, 1 and 3 cars, owner and visitor, on a small
// (360 x 640) and a tall (412 x 915) phone at 100 % and 130 % text, in the
// light and the dark app theme. Any overflow or layout error throws.

const _base = 'https://x.supabase.co/storage/v1/object/public/car-photos/u1';
final _now = DateTime.now();
DateTime _days(int n) => DateTime(_now.year, _now.month, _now.day).add(Duration(days: n));

Car _toy() => Car(
      id: 'a',
      ownerId: 'u1',
      make: 'Toyota',
      model: 'Estima',
      year: 2007,
      photoUrls: const ['$_base/a.jpg'],
      createdAt: DateTime(2026, 9, 1),
      isDefault: true,
      color: 'white',
      bodyStyle: 'mpv',
      toyUrl: '$_base/a_toy.png',
      toyStatus: 'ready',
    );

Car _pending() => Car(
      id: 'b',
      ownerId: 'u1',
      make: 'Honda',
      model: 'Civic Type R FL5 with a very long name',
      year: 2023,
      photoUrls: const ['$_base/b.jpg'],
      createdAt: DateTime(2026, 9, 2),
      bodyStyle: 'hatchback',
      color: 'grey',
      toyStatus: 'pending',
    );

Car _bare() => Car(
      id: 'c',
      ownerId: 'u1',
      make: 'Perodua',
      model: 'Myvi',
      photoUrls: const [],
      createdAt: DateTime(2026, 9, 3),
      bodyStyle: 'hatchback',
      toyStatus: 'failed',
    );

CarMod _mod(String id, ModCategory cat, String title, {double? cost}) => CarMod(
      id: id,
      carId: 'a',
      category: cat,
      title: title,
      cost: cost,
      doneOn: _days(-30),
      photoUrls: const [],
      isPrivate: false,
      createdAt: _days(-30),
    );

final _richFacts = GarageFacts(
  mods: [_mod('m1', ModCategory.wheels, 'Forged wheels', cost: 18500), _mod('m2', ModCategory.exhaust, 'Titanium exhaust', cost: 24000)],
  meets: 12,
  posts: 5,
  papers: CarDocuments(carId: 'a', roadTaxExpiry: _days(21), insuranceExpiry: _days(-3), puspakomDue: _days(200)),
  papersLoaded: true,
);

const _emptyFacts = GarageFacts(mods: [], meets: 0, posts: 0, papersLoaded: true);

final _calls = <String>[];

class _Harness extends StatefulWidget {
  const _Harness({required this.cars, required this.mine, this.back = true, this.bottomPadding = 28});
  final List<Car> cars;
  final bool mine;
  final bool back;
  final double bottomPadding;

  @override
  State<_Harness> createState() => _HarnessState();
}

class _HarnessState extends State<_Harness> {
  int index = 0;

  @override
  Widget build(BuildContext context) {
    final mine = widget.mine;
    return GarageStudio(
      cars: widget.cars,
      index: index,
      onIndex: (i) => setState(() => index = i),
      mine: mine,
      title: mine ? 'My garage' : 'titi_onboard1\'s garage',
      todayId: 'a',
      facts: index == 0 ? _richFacts : _emptyFacts,
      bottomPadding: widget.bottomPadding,
      onBack: widget.back ? () => _calls.add('back') : null,
      onAdd: mine ? () => _calls.add('add') : null,
      onOpen: (c) => _calls.add('open:${c.id}'),
      onMore: mine ? (c) => _calls.add('more:${c.id}') : null,
      onMakeToday: mine ? (c) => _calls.add('today:${c.id}') : null,
      onEdit: mine ? (c) => _calls.add('edit:${c.id}') : null,
      onPapers: mine ? (c) => _calls.add('papers:${c.id}') : null,
      onRefresh: () async => _calls.add('refresh'),
      empty: GarageEmptyCard(
        pose: TitiPose.camera,
        title: 'Park your first car',
        subtitle: 'Your daily, your project, your weekend toy.',
        actionLabel: mine ? 'Add a car' : null,
        onAction: mine ? () => _calls.add('add') : null,
      ),
    );
  }
}

Future<void> _pump(WidgetTester tester, {required Size size, required double scale, required List<Car> cars, bool mine = true, bool dark = false, bool back = true}) async {
  tester.view.physicalSize = size * 3;
  tester.view.devicePixelRatio = 3;
  tester.view.padding = const FakeViewPadding(top: 24 * 3, bottom: 16 * 3);
  addTearDown(tester.view.reset);
  addTearDown(() => AppColors.dark = false);
  AppColors.dark = dark;
  _calls.clear();
  await tester.pumpWidget(MaterialApp(
    theme: AppTheme.current,
    home: Builder(
      builder: (context) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
        child: Scaffold(body: _Harness(cars: cars, mine: mine, back: back)),
      ),
    ),
  ));
  await tester.pump(const Duration(milliseconds: 50));
}

/// Lets the pager, the landing and the sweep finish. (Not pumpAndSettle:
/// the "building" caption's shimmer never stops.)
Future<void> _settle(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 20));
  await tester.pump(const Duration(milliseconds: 1700));
  await tester.pump(const Duration(milliseconds: 20));
  expect(tester.takeException(), isNull);
}

/// Scrolls the page until [finder] is in view.
Future<void> _reveal(WidgetTester tester, Finder finder) async {
  await Scrollable.ensureVisible(tester.element(finder), alignment: 0.5);
  await _settle(tester);
}

Rect _hero(WidgetTester tester, String id) => tester.getRect(find.byKey(ValueKey('hero-$id')));

void main() {
  setUp(() {
    garageImageFor = (url) => url.endsWith('_toy.png')
        ? const AssetImage('assets/cars/sedan.png')
        : url.endsWith('_cut.png')
            ? const AssetImage('assets/cars/coupe.png')
            : const AssetImage('assets/portrait_samples/showroom.webp');
  });

  const sizes = {'small 360x640': Size(360, 640), 'tall 412x915': Size(412, 915)};

  for (final entry in sizes.entries) {
    for (final scale in [1.0, 1.3]) {
      for (final dark in [false, true]) {
        final mode = '${entry.key} @$scale ${dark ? 'dark' : 'light'}';
        final size = entry.value;

        testWidgets('three cars, owner ($mode): card, rail, stats, buttons, papers; thumbnails and swipes change car', (tester) async {
          await _pump(tester, size: size, scale: scale, dark: dark, cars: [_toy(), _pending(), _bare()]);
          await _settle(tester);
          final screen = tester.getRect(find.byType(GarageStudio));
          expect(screen.size, size);

          // The header and the first car's card.
          expect(find.text('MY GARAGE'), findsOneWidget);
          expect(find.bySemanticsLabel('Add a car'), findsOneWidget);
          expect(find.bySemanticsLabel('Back'), findsOneWidget);
          expect(find.text('Estima'), findsOneWidget);
          expect(find.text('TOYOTA · 2007'), findsOneWidget);
          expect(find.text('TODAY\'S CAR'), findsOneWidget);
          expect(find.text('White, matched from your photo'), findsOneWidget);
          final hero = _hero(tester, 'a');
          expect(hero.left, 20);
          expect(hero.right, size.width - 20);
          // The toy fills most of the card and sits inside it.
          final toy = tester.getRect(find.descendant(of: find.byKey(const ValueKey('hero-a')), matching: find.byType(ToyCarImage)));
          expect(toy.width, closeTo(hero.width * 0.86, 0.5));
          expect(toy.top, greaterThan(hero.top));
          expect(toy.bottom, lessThan(hero.bottom));
          // Thumbnails: three, the first selected.
          expect(find.byType(ToyRail), findsOneWidget);
          expect(find.descendant(of: find.byType(ToyRail), matching: find.byType(ToyCarImage)), findsNWidgets(3));

          // Stats and buttons (scroll them into view on the small phone).
          await _reveal(tester, find.text('Mods'));
          expect(find.text('2'), findsOneWidget);
          expect(find.text('Spent'), findsOneWidget);
          expect(find.text('RM 42.5k'), findsOneWidget);
          expect(find.text('12'), findsOneWidget);
          expect(find.text('Posts'), findsOneWidget);
          await _reveal(tester, find.text('Open car'));
          expect(find.text('Edit'), findsOneWidget);
          expect(find.text('Make today\'s car'), findsNothing);
          await tester.tap(find.text('Open car'));
          await tester.tap(find.text('Edit'));
          await tester.tap(find.bySemanticsLabel('More'));
          expect(_calls, ['open:a', 'edit:a', 'more:a']);

          // Papers: one row each, real dates only.
          await _reveal(tester, find.text('Road tax'));
          expect(find.text('21 days left'), findsOneWidget);
          expect(find.text('Soon'), findsOneWidget);
          expect(find.text('Insurance'), findsOneWidget);
          expect(find.text('Expired 3 days ago'), findsOneWidget);
          expect(find.text('Expired'), findsOneWidget);
          expect(find.text('PUSPAKOM'), findsOneWidget);
          expect(find.text('OK'), findsOneWidget);
          await tester.tap(find.text('Road tax'));
          expect(_calls.last, 'papers:a');

          // A thumbnail moves the pager; the second car is not today's car.
          await _reveal(tester, find.byType(ToyRail));
          await tester.tap(find.bySemanticsLabel('Honda Civic Type R FL5 with a very long name'));
          await _settle(tester);
          expect(find.text('Civic Type R FL5 with a very long name'), findsOneWidget);
          expect(find.text('TODAY\'S CAR'), findsNothing);
          expect(find.text('Building your toy car…'), findsOneWidget);
          await _reveal(tester, find.text('Make today\'s car'));
          await tester.tap(find.text('Make today\'s car'));
          expect(_calls.last, 'today:b');
          // No papers saved for it: one quiet row to add them.
          await _reveal(tester, find.text('Road tax and insurance'));
          expect(find.text('Add'), findsOneWidget);

          // Swipe on to the third car (no photo: body art, no colour line).
          await _reveal(tester, find.byKey(const ValueKey('hero-b')));
          await tester.drag(find.byKey(const ValueKey('hero-b')), Offset(-size.width * 0.7, 0));
          await _settle(tester);
          expect(find.text('Myvi'), findsOneWidget);
          expect(find.textContaining('matched from'), findsNothing);
          expect(find.text('Building your toy car…'), findsNothing);
          // And one car back with a swipe the other way.
          await tester.drag(find.byKey(const ValueKey('hero-c')), Offset(size.width * 0.7, 0));
          await _settle(tester);
          expect(find.text('Civic Type R FL5 with a very long name'), findsOneWidget);
          expect(find.text('Myvi'), findsNothing);
          expect(tester.takeException(), isNull);
        });

        testWidgets('one car, visitor ($mode): their title, DAILY, no rail, no edit, no papers', (tester) async {
          await _pump(tester, size: size, scale: scale, dark: dark, mine: false, cars: [_toy()]);
          await _settle(tester);
          expect(find.text('TITI_ONBOARD1\'S GARAGE'), findsOneWidget);
          expect(find.bySemanticsLabel('Add a car'), findsNothing);
          expect(find.text('DAILY'), findsOneWidget);
          expect(find.text('White, matched from the photo'), findsOneWidget);
          expect(find.byType(ToyRail), findsNothing);
          await _reveal(tester, find.text('Open car'));
          expect(find.text('Spent'), findsNothing);
          expect(find.text('Edit'), findsNothing);
          expect(find.bySemanticsLabel('More'), findsNothing);
          expect(find.text('Road tax'), findsNothing);
          await tester.tap(find.text('Open car'));
          expect(_calls, ['open:a']);
          // A single car never leaves the page.
          await tester.drag(find.byKey(const ValueKey('hero-a')), Offset(-size.width * 0.7, 0));
          await _settle(tester);
          expect(find.text('Estima'), findsOneWidget);
        });

        testWidgets('no cars, owner ($mode): the header and the empty card', (tester) async {
          await _pump(tester, size: size, scale: scale, dark: dark, cars: const [], back: false);
          await _settle(tester);
          expect(find.text('MY GARAGE'), findsOneWidget);
          expect(find.bySemanticsLabel('Back'), findsNothing);
          expect(find.text('Park your first car'), findsOneWidget);
          expect(find.byType(GarageHeroCard), findsNothing);
          expect(find.byType(StatsRow), findsNothing);
          await _reveal(tester, find.text('Add a car'));
          await tester.tap(find.text('Add a car'));
          expect(_calls, ['add']);
        });
      }
    }
  }

  testWidgets('the toy lands: scales up from 0.86 and fades in, then the light sweeps once', (tester) async {
    await _pump(tester, size: const Size(412, 915), scale: 1.0, cars: [_toy(), _pending()]);
    await _settle(tester);
    final before = tester.getRect(find.descendant(of: find.byKey(const ValueKey('hero-a')), matching: find.byType(ToyCarImage)));
    Opacity opacityA() => tester.widgetList<Opacity>(find.descendant(of: find.byKey(const ValueKey('hero-a')), matching: find.byType(Opacity))).first;
    Finder sweepA() => find.descendant(of: find.byKey(const ValueKey('hero-a')), matching: find.byType(ShaderMask));
    // Away to the second car, then back: the first toy starts small and
    // faint, lands at full size, then the streak crosses it once.
    await tester.tap(find.bySemanticsLabel('Honda Civic Type R FL5 with a very long name'));
    await _settle(tester);
    expect(find.byKey(const ValueKey('hero-a')), findsNothing, reason: 'the first card has left the pager');
    await tester.tap(find.bySemanticsLabel('Toyota Estima'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(opacityA().opacity, lessThan(1));
    expect(sweepA(), findsNothing);
    await tester.pump(const Duration(milliseconds: 500));
    expect(opacityA().opacity, 1);
    await tester.pump(const Duration(milliseconds: 100));
    expect(sweepA(), findsOneWidget);
    await _settle(tester);
    expect(sweepA(), findsNothing);
    final after = tester.getRect(find.descendant(of: find.byKey(const ValueKey('hero-a')), matching: find.byType(ToyCarImage)));
    expect(after, before);
  });

  testWidgets('tablet width: the page stays at most 640 wide, centred', (tester) async {
    await _pump(tester, size: const Size(820, 1180), scale: 1.0, cars: [_toy(), _pending(), _bare()]);
    await _settle(tester);
    final hero = _hero(tester, 'a');
    expect(hero.width, 600);
    expect(hero.center.dx, 410);
  });
}
