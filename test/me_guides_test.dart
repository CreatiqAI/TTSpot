import 'package:car_meet/core/guide/guide.dart';
import 'package:car_meet/core/guide/guide_controller.dart';
import 'package:car_meet/core/router/app_router.dart';
import 'package:car_meet/core/theme/app_icons.dart';
import 'package:car_meet/core/theme/app_theme.dart';
import 'package:car_meet/core/theme/titi.dart';
import 'package:car_meet/features/auth/data/auth_repository.dart';
import 'package:car_meet/features/cards/application/cards_providers.dart';
import 'package:car_meet/features/cards/domain/cards.dart';
import 'package:car_meet/features/cards/presentation/open_box_screen.dart';
import 'package:car_meet/features/guides/me_guides.dart';
import 'package:car_meet/features/profile/presentation/widgets/profile_header.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

// TiTi's Me & cards guides: the definitions, their copy limits, the
// first-box journey's stages and the open box screen's "What can cards do?".

/// Shows nothing; remembers what it was asked to show and answers [result].
class _FakeGuides extends GuideController {
  _FakeGuides(super.ref, {this.seenIds = const {}, this.result = GuideResult.finished, this.tipsOn = true});
  final Set<String> seenIds;
  final GuideResult result;
  final bool tipsOn;
  final shown = <({Guide guide, bool force})>[];

  @override
  bool get enabled => tipsOn;

  @override
  bool seen(String id) => seenIds.contains(id);

  @override
  bool get showing => false;

  @override
  Future<GuideResult> showOnce(BuildContext context, Guide guide, {bool force = false}) async {
    shown.add((guide: guide, force: force));
    return result;
  }
}

/// Every guide this track defines, in every variant.
List<Guide> _allGuides({int boxCost = MeGuides.defaultBoxCost}) {
  final profile = ProfileGuideKeys();
  final cardsTab = CardsTabGuideKeys();
  final cardsScreen = CardsScreenGuideKeys();
  return [
    MeGuides.firstBoxIntro(),
    MeGuides.firstBoxCardsTab(profile.cardsTab),
    MeGuides.firstBoxTour(cardsTab, points: profile.points, boxCost: boxCost),
    MeGuides.profile(profile),
    MeGuides.profile(profile, showCards: true),
    MeGuides.garage(GarageGuideKeys()),
    MeGuides.carPage(CarPageGuideKeys()),
    MeGuides.points(PointsGuideKeys(), boxCost: boxCost),
    MeGuides.cards(collection: cardsTab.grid, trades: cardsTab.trades, prizes: cardsTab.prizes),
    MeGuides.cards(collection: cardsScreen.collection, trades: cardsScreen.trades, prizes: cardsScreen.prizes),
    MeGuides.rewards(RewardsGuideKeys()),
  ];
}

// ------------------------------------------------------- open box harness ---

const _card = CardType(id: 'c1', setId: 's1', number: 1, name: 'Myvi Kencang', rarity: CardRarity.common, color: Color(0xFF9AA0A8), active: true, sort: 1);

class _FakeActions extends CardsActions {
  _FakeActions(super.ref);

  @override
  Future<BoxResult> openBox(String boxId) async => const BoxResult(userCardId: 'uc-1', card: _card, held: 1);
}

_FakeGuides? _guides;

Future<ProviderContainer> _pumpBox(
  WidgetTester t, {
  Set<String> seen = const {},
  GuideResult result = GuideResult.finished,
  bool tipsOn = true,
  double scale = 1,
  Size size = const Size(393, 851),
  int moreBoxes = 0,
}) async {
  _guides = null;
  t.view.physicalSize = size * 3;
  t.view.devicePixelRatio = 3;
  addTearDown(t.view.reset);
  t.binding.defaultBinaryMessenger.setMockStreamHandler(const EventChannel('my.ttspot.app/motion'), MockStreamHandler.inline(onListen: (_, _) {}));
  addTearDown(() => t.binding.defaultBinaryMessenger.setMockStreamHandler(const EventChannel('my.ttspot.app/motion'), null));

  final router = GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(path: '/', builder: (_, _) => const Scaffold(body: Center(child: Text('HOME')))),
      GoRoute(path: Routes.garage, builder: (_, _) => const Scaffold(body: Center(child: Text('ME TAB')))),
      GoRoute(path: '/box', builder: (_, _) => const OpenBoxScreen(boxId: 'b1')),
    ],
  );
  final container = ProviderContainer(overrides: [
    guideControllerProvider.overrideWith((ref) => _guides = _FakeGuides(ref, seenIds: seen, result: result, tipsOn: tipsOn)),
    cardsActionsProvider.overrideWith((ref) => _FakeActions(ref)),
    myBoxesProvider.overrideWith((ref) async => [
          for (var i = 0; i <= moreBoxes; i++) CardBox(id: 'b${i + 1}', source: 'signup', status: 'sealed', pointsSpent: 0, createdAt: DateTime(2026)),
        ]),
    cardSettingsProvider.overrideWith((ref) async => const CardSettings()),
    currentProfileProvider.overrideWith((ref) async => null),
    cardTypesProvider.overrideWith((ref) async => const [_card]),
  ]);
  addTearDown(container.dispose);
  await t.pumpWidget(UncontrolledProviderScope(
    container: container,
    child: MaterialApp.router(
      theme: AppTheme.current,
      routerConfig: router,
      builder: (context, c) => MediaQuery(data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)), child: c!),
    ),
  ));
  router.push('/box');
  await t.pump();
  await t.pump(const Duration(milliseconds: 400));
  return container;
}

Future<void> _frames(WidgetTester t, int ms) async {
  for (var i = 0; i < ms ~/ 50; i++) {
    await t.pump(const Duration(milliseconds: 50));
  }
}

/// Three taps, the burst and flip, then "Add to my cards" and its flight.
Future<void> _openAndAdd(WidgetTester t) async {
  for (var i = 0; i < 3; i++) {
    await t.tap(find.image(const AssetImage('assets/titi/box_closed.png')), warnIfMissed: false);
    await t.pump(const Duration(milliseconds: 450));
  }
  await t.pump(const Duration(milliseconds: 1150));
  await t.pump(const Duration(milliseconds: 750));
  await t.pump(const Duration(milliseconds: 1200));
  expect(find.text('Add to my cards'), findsOneWidget);
  expect(find.text('What can cards do?'), findsNothing, reason: 'not before the card is added');
  await t.tap(find.text('Add to my cards'));
  await _frames(t, 2000);
}

void main() {
  // ------------------------------------------------------------ definitions ---

  test('every guide builds with its own id and the steps it promises', () {
    final profile = ProfileGuideKeys();
    final cardsTab = CardsTabGuideKeys();

    final intro = MeGuides.firstBoxIntro();
    expect(intro.id, GuideIds.firstBox);
    expect(intro.steps, hasLength(1));
    expect(intro.steps.single.target, isNull);
    expect(intro.steps.single.pose, TitiPose.celebrate);
    expect(intro.steps.single.title, 'Nice pull!');
    expect(intro.steps.single.nextLabel, 'Show me');

    final tap = MeGuides.firstBoxCardsTab(profile.cardsTab);
    expect(tap.id, GuideIds.firstBox);
    expect(tap.steps.single.tapTarget, isTrue);
    expect(tap.steps.single.target, same(profile.cardsTab));
    expect(tap.steps.single.pose, TitiPose.gift);

    final tour = MeGuides.firstBoxTour(cardsTab, points: profile.points, boxCost: 120);
    expect(tour.id, GuideIds.firstBox);
    expect([for (final s in tour.steps) s.target], [cardsTab.grid, cardsTab.trades, profile.points, cardsTab.getBox, cardsTab.prizes, null]);
    expect(tour.steps.last.pose, TitiPose.thumbsUp);
    expect(tour.steps.last.title, "You're all set!");
    expect(tour.steps[3].body, startsWith('120 points'), reason: 'the live box price');
    expect(tour.steps.every((s) => !s.tapTarget), isTrue);

    final plain = MeGuides.profile(profile);
    expect(plain.id, GuideIds.profile);
    expect([for (final s in plain.steps) s.target], [profile.garage, profile.points, profile.badges, profile.qr]);
    final withCards = MeGuides.profile(profile, showCards: true);
    expect([for (final s in withCards.steps) s.target], [profile.garage, profile.points, profile.cardsTab, profile.qr]);

    expect(MeGuides.garage(GarageGuideKeys()).id, GuideIds.garage);
    expect(MeGuides.carPage(CarPageGuideKeys()).id, GuideIds.carPage);
    expect(MeGuides.points(PointsGuideKeys()).id, GuideIds.points);
    expect(MeGuides.cards(collection: cardsTab.grid, trades: cardsTab.trades, prizes: cardsTab.prizes).id, GuideIds.cards);
    expect(MeGuides.rewards(RewardsGuideKeys()).id, GuideIds.rewards);

    for (final g in _allGuides()) {
      expect(GuideIds.all, contains(g.id));
      // first-visit guides stay short; only the journey's tour runs longer
      if (g.id != GuideIds.firstBox) expect(g.steps.length, inInclusiveRange(2, 4), reason: g.id);
    }
    // only the journey's "Tap Cards" makes the member tap
    final tapping = [for (final g in _allGuides()) for (final s in g.steps) if (s.tapTarget) s.title];
    expect(tapping, ['Your cards live here']);
  });

  test('copy stays short: titles at most 40 characters, bodies at most 110', () {
    for (final cost in [MeGuides.defaultBoxCost, 99999]) {
      for (final g in _allGuides(boxCost: cost)) {
        for (final s in g.steps) {
          expect(s.title.length, lessThanOrEqualTo(40), reason: '${g.id}: "${s.title}"');
          expect(s.body.length, lessThanOrEqualTo(110), reason: '${g.id}: "${s.body}"');
          expect(s.title.trim(), isNotEmpty);
          expect(s.body.trim(), isNotEmpty);
        }
      }
    }
  });

  test('the points copy matches point_rules (10 a meet, spot, weekly post, badge; 5 a friend)', () {
    final tour = MeGuides.firstBoxTour(CardsTabGuideKeys(), points: GlobalKey());
    final points = tour.steps.firstWhere((s) => s.title == 'Points');
    expect(points.body, contains('pay 10'));
    expect(points.body, contains('pays 5'));
    final reset = MeGuides.points(PointsGuideKeys()).steps.firstWhere((s) => s.title == 'Weekly reset');
    expect(reset.body, contains('Friday at 6 PM'));
  });

  // ----------------------------------------------------------- journey stages ---

  Future<(ProviderContainer, BuildContext, WidgetRef)> pumpRef(WidgetTester t, GuideResult result) async {
    final container = ProviderContainer(overrides: [
      guideControllerProvider.overrideWith((ref) => _guides = _FakeGuides(ref, result: result)),
    ]);
    addTearDown(container.dispose);
    late BuildContext ctx;
    late WidgetRef wref;
    await t.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(home: Consumer(builder: (context, ref, _) {
        ctx = context;
        wref = ref;
        return const SizedBox();
      })),
    ));
    return (container, ctx, wref);
  }

  testWidgets('journey: a tap on the spotlighted Cards tab moves the stage to first_box:cards', (t) async {
    final (container, ctx, ref) = await pumpRef(t, GuideResult.tappedTarget);
    container.read(guideJourneyProvider.notifier).go(FirstBoxStage.me);
    final key = GlobalKey();
    final r = await runFirstBoxCardsTabStep(ctx, ref, key);
    expect(r, GuideResult.tappedTarget);
    expect(container.read(guideJourneyProvider), 'first_box:cards');
    final shown = _guides!.shown.single;
    expect(shown.force, isTrue, reason: 'journeys bypass seen');
    expect(shown.guide.id, GuideIds.firstBox);
    expect(shown.guide.steps.single.target, same(key));
  });

  for (final result in [GuideResult.skipped, GuideResult.notShown, GuideResult.finished]) {
    testWidgets('journey: the Cards tab step ending ${result.name} ends the journey', (t) async {
      final (container, ctx, ref) = await pumpRef(t, result);
      container.read(guideJourneyProvider.notifier).go(FirstBoxStage.me);
      await runFirstBoxCardsTabStep(ctx, ref, GlobalKey());
      expect(container.read(guideJourneyProvider), isNull);
    });
  }

  testWidgets('journey: the Cards tab tour clears the stage when it ends', (t) async {
    final (container, ctx, ref) = await pumpRef(t, GuideResult.finished);
    container.read(guideJourneyProvider.notifier).go(FirstBoxStage.cards);
    final cards = CardsTabGuideKeys();
    final points = GlobalKey();
    await runFirstBoxTour(ctx, ref, cards, points: points);
    expect(container.read(guideJourneyProvider), isNull);
    final shown = _guides!.shown.single;
    expect(shown.force, isTrue);
    expect(shown.guide.steps.map((s) => s.target), contains(points));
  });

  testWidgets('the profile tab strip with guide keys: the Cards tab is keyed and still switches', (t) async {
    final cardsKey = GlobalKey();
    var selected = 0;
    await t.pumpWidget(MaterialApp(
      theme: AppTheme.current,
      home: Scaffold(
        body: StatefulBuilder(
          builder: (context, set) => CustomScrollView(slivers: [
            SliverPersistentHeader(
              pinned: true,
              delegate: ProfileTabBar(
                tabs: const [(AppIcons.squaresFour, 'Posts'), (AppIcons.cards, 'Cards')],
                selected: selected,
                onSelect: (i) => set(() => selected = i),
                tabKeys: [null, cardsKey],
              ),
            ),
          ]),
        ),
      ),
    ));
    expect(cardsKey.currentContext, isNotNull);
    expect(find.descendant(of: find.byKey(cardsKey), matching: find.text('Cards')), findsOneWidget);
    await t.tap(find.byKey(cardsKey));
    await t.pumpAndSettle();
    expect(selected, 1);
  });

  // -------------------------------------------------------- open box button ---

  testWidgets('first box: "What can cards do?" shows once the card is added, and the screen stays', (t) async {
    await _pumpBox(t);
    await _openAndAdd(t);
    expect(find.text('Saved to My cards'), findsOneWidget);
    expect(find.text('What can cards do?'), findsOneWidget);
    expect(find.text('HOME'), findsNothing, reason: 'it waits for the member');
    expect(_guides!.shown, isEmpty, reason: 'nothing until they tap it');
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('first box seen before: no button, the screen closes as it always did', (t) async {
    await _pumpBox(t, seen: {GuideIds.firstBox});
    await _openAndAdd(t);
    expect(find.text('What can cards do?'), findsNothing);
    expect(find.text('HOME'), findsOneWidget);
  });

  testWidgets('tips switched off: no button', (t) async {
    await _pumpBox(t, tipsOn: false);
    await _openAndAdd(t);
    expect(find.text('What can cards do?'), findsNothing);
    expect(find.text('HOME'), findsOneWidget);
  });

  testWidgets('"What can cards do?" finished: the journey moves to Me and the app goes to the Me tab', (t) async {
    final container = await _pumpBox(t);
    await _openAndAdd(t);
    await t.tap(find.text('What can cards do?'));
    await _frames(t, 600);
    final shown = _guides!.shown.single;
    expect(shown.guide.id, GuideIds.firstBox);
    expect(shown.force, isTrue);
    expect(shown.guide.steps.single.nextLabel, 'Show me');
    expect(container.read(guideJourneyProvider), FirstBoxStage.me);
    expect(find.text('ME TAB'), findsOneWidget);
  });

  testWidgets('"What can cards do?" skipped: no journey, the screen just closes', (t) async {
    final container = await _pumpBox(t, result: GuideResult.skipped);
    await _openAndAdd(t);
    await t.tap(find.text('What can cards do?'));
    await _frames(t, 600);
    expect(container.read(guideJourneyProvider), isNull);
    expect(find.text('HOME'), findsOneWidget);
    expect(find.text('ME TAB'), findsNothing);
  });

  testWidgets('with the button showing, the X still closes', (t) async {
    await _pumpBox(t);
    await _openAndAdd(t);
    await t.tap(find.byKey(const ValueKey('open-box-close')));
    await _frames(t, 600);
    expect(find.text('HOME'), findsOneWidget);
    expect(_guides!.shown, isEmpty);
  });

  for (final size in [const Size(393, 851), const Size(360, 640)]) {
    for (final scale in [1.0, 1.3]) {
      testWidgets('the button lays out on ${size.width.round()}x${size.height.round()} at text x$scale', (t) async {
        await _pumpBox(t, size: size, scale: scale, moreBoxes: 2);
        await _openAndAdd(t);
        final b = t.getRect(find.byKey(const ValueKey('open-box-what-cards')));
        expect(b.height, greaterThanOrEqualTo(48));
        expect(b.bottom, lessThanOrEqualTo(size.height));
        expect(t.takeException(), isNull);
        await t.pumpWidget(const SizedBox());
      });
    }
  }
}
