import 'package:car_meet/core/guide/guide.dart';
import 'package:car_meet/core/guide/guide_controller.dart';
import 'package:car_meet/core/guide/guide_on_first_view.dart';
import 'package:car_meet/core/guide/guide_store.dart';
import 'package:car_meet/core/theme/titi.dart';
import 'package:car_meet/features/settings/application/settings_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

/// The overlay has a breathing ring and a per-frame measure ticker, so it
/// never "settles": pump in fixed steps instead of pumpAndSettle.
Future<void> settle(WidgetTester tester, [int ms = 700]) async {
  for (var i = 0; i < ms ~/ 50; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void useScreen(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

Future<void> systemBack(WidgetTester tester) async {
  final message = const JSONMethodCodec().encodeMethodCall(const MethodCall('popRoute'));
  await tester.binding.defaultBinaryMessenger.handlePlatformMessage('flutter/navigation', message, (_) {});
}

class _Page extends StatelessWidget {
  const _Page({required this.target, required this.onTap, this.alignment = Alignment.center, this.showTarget = true});
  final GlobalKey target;
  final VoidCallback onTap;
  final Alignment alignment;
  final bool showTarget;

  @override
  Widget build(BuildContext context) => Scaffold(
        body: SafeArea(
          child: Align(
            alignment: alignment,
            child: showTarget
                ? Padding(
                    padding: const EdgeInsets.all(12),
                    child: ElevatedButton(key: target, onPressed: onTap, child: const Text('Cards')),
                  )
                : const SizedBox.shrink(),
          ),
        ),
      );
}

Widget _app(MemoryGuideStore store, Widget home, {double textScale = 1}) => ProviderScope(
      overrides: [guideStoreProvider.overrideWithValue(store)],
      child: MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: home,
      ),
    );

GuideController _controller(WidgetTester tester) => ProviderScope.containerOf(tester.element(find.byType(Scaffold).first)).read(guideControllerProvider);

BuildContext _pageContext(WidgetTester tester) => tester.element(find.byType(Scaffold).first);

void main() {
  group('overlay', () {
    testWidgets('shows a step, Next advances, Got it finishes; marked seen at start', (tester) async {
      final store = MemoryGuideStore();
      final target = GlobalKey();
      await tester.pumpWidget(_app(store, _Page(target: target, onTap: () {})));
      final guide = Guide(id: GuideIds.cards, steps: [
        GuideStep(target: target, title: 'Your cards', body: 'Every card you pulled lives here.'),
        const GuideStep(title: 'Trade them', body: 'Swap cards with friends.', pose: TitiPose.thumbsUp),
      ]);
      GuideResult? result;
      final c = _controller(tester);
      c.showOnce(_pageContext(tester), guide).then((r) => result = r);
      await settle(tester);

      expect(c.showing, isTrue);
      expect(store.seen, [GuideIds.cards]);
      expect(find.text('Your cards'), findsOneWidget);
      expect(find.text('Next'), findsOneWidget);
      expect(find.byKey(const Key('guide-skip')), findsOneWidget);

      await tester.tap(find.byKey(const Key('guide-next')));
      await settle(tester);
      expect(find.text('Trade them'), findsOneWidget);
      expect(find.text('Your cards'), findsNothing);
      expect(find.text('Got it'), findsOneWidget);
      // Last step: no Skip.
      expect(find.byKey(const Key('guide-skip')), findsNothing);

      await tester.tap(find.byKey(const Key('guide-next')));
      await settle(tester, 500);
      expect(result, GuideResult.finished);
      expect(c.showing, isFalse);
      expect(find.text('Trade them'), findsNothing);
      expect(tester.takeException(), isNull);

      // Seen: a second showOnce does nothing.
      expect(await c.showOnce(_pageContext(tester), guide), GuideResult.notShown);
      // Forced (Replay / journeys) shows again.
      GuideResult? again;
      c.showOnce(_pageContext(tester), guide, force: true).then((r) => again = r);
      await settle(tester);
      expect(find.text('Your cards'), findsOneWidget);
      c.dismiss();
      await settle(tester, 500);
      expect(again, GuideResult.skipped);
    });

    testWidgets('Skip ends as skipped; the dim swallows taps on normal steps', (tester) async {
      final store = MemoryGuideStore();
      final target = GlobalKey();
      var taps = 0;
      await tester.pumpWidget(_app(store, _Page(target: target, onTap: () => taps++)));
      GuideResult? result;
      _controller(tester).showOnce(_pageContext(tester), Guide(id: GuideIds.home, steps: [
        GuideStep(target: target, title: 'Hello', body: 'This is it.'),
        const GuideStep(title: 'Two', body: 'Second.'),
      ])).then((r) => result = r);
      await settle(tester);

      // Inside the hole on a normal step: the button doesn't get it.
      await tester.tap(find.byKey(target), warnIfMissed: false);
      await settle(tester, 200);
      expect(taps, 0);
      // The dim: nothing happens.
      await tester.tapAt(const Offset(5, 5));
      await settle(tester, 200);
      expect(find.text('Hello'), findsOneWidget);
      expect(result, isNull);

      await tester.tap(find.byKey(const Key('guide-skip')));
      await settle(tester, 500);
      expect(result, GuideResult.skipped);
      expect(find.text('Hello'), findsNothing);
      // Gone: the page works again.
      await tester.tap(find.byKey(target));
      expect(taps, 1);
    });

    testWidgets('a "tap it" step lets the tap through and ends as tappedTarget', (tester) async {
      final store = MemoryGuideStore();
      final target = GlobalKey();
      var taps = 0;
      await tester.pumpWidget(_app(store, _Page(target: target, onTap: () => taps++, alignment: Alignment.bottomCenter)));
      GuideResult? result;
      _controller(tester).showOnce(_pageContext(tester), Guide(id: GuideIds.firstBox, steps: [
        GuideStep(target: target, title: 'Tap Cards', body: 'Your collection is in here.', tapTarget: true, circle: true),
      ])).then((r) => result = r);
      await settle(tester);

      expect(find.byKey(const Key('guide-next')), findsNothing);
      expect(find.byKey(const Key('guide-tap-hint')), findsOneWidget);
      // Outside the hole: swallowed.
      await tester.tapAt(const Offset(10, 10));
      await settle(tester, 200);
      expect(result, isNull);

      await tester.tap(find.byKey(target));
      await tester.pump();
      expect(taps, 1);
      await settle(tester, 500);
      expect(result, GuideResult.tappedTarget);
      expect(find.text('Tap Cards'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a missing target shows TiTi in the middle, no errors', (tester) async {
      useScreen(tester, const Size(360, 640));
      final store = MemoryGuideStore();
      final target = GlobalKey(); // never attached
      await tester.pumpWidget(_app(store, _Page(target: GlobalKey(), onTap: () {}, showTarget: false)));
      _controller(tester).showOnce(_pageContext(tester), Guide(id: GuideIds.points, steps: [
        GuideStep(target: target, title: 'Points', body: 'Earn them at meets and spots.'),
      ]));
      await settle(tester);
      expect(tester.takeException(), isNull);
      expect(find.text('Points'), findsOneWidget);
      final card = tester.getRect(find.byKey(const Key('guide-next')));
      final titi = tester.getRect(find.byType(Titi));
      // Card above TiTi, the pair around the middle of the screen.
      expect(card.bottom, lessThan(titi.top + 4));
      final middle = (tester.getRect(find.text('Points')).top + titi.bottom) / 2;
      expect((middle - 320).abs(), lessThan(60));
    });

    testWidgets('the card stays clear of the spotlight', (tester) async {
      useScreen(tester, const Size(360, 640));
      final store = MemoryGuideStore();
      final target = GlobalKey();
      await tester.pumpWidget(_app(store, _Page(target: target, onTap: () {}, alignment: Alignment.topCenter)));
      _controller(tester).showOnce(_pageContext(tester), Guide(id: GuideIds.map, steps: [
        GuideStep(target: target, title: 'Up here', body: 'Look at this.'),
      ]));
      await settle(tester);
      final hole = tester.getRect(find.byKey(target)).inflate(8);
      final title = tester.getRect(find.text('Up here'));
      expect(title.top, greaterThan(hole.bottom));
    });

    testWidgets('no overflow at text scale 1.3 on 360x640, target top, bottom and none', (tester) async {
      useScreen(tester, const Size(360, 640));
      for (final align in [Alignment.topCenter, Alignment.bottomCenter, Alignment.center]) {
        final store = MemoryGuideStore();
        final target = GlobalKey();
        await tester.pumpWidget(_app(store, _Page(target: target, onTap: () {}, alignment: align), textScale: 1.3));
        final steps = [
          GuideStep(target: target, title: 'Nice pull, collector!', body: 'Cards are collectibles. Collect them, trade them with friends, and some unlock real prizes.', nextLabel: 'Show me around'),
          for (var i = 0; i < 5; i++) GuideStep(target: i.isEven ? target : null, title: 'Step number $i here', body: 'Points come from meets, spots, a post a week, badges and friends.'),
          GuideStep(target: target, title: 'Tap Cards now', body: 'Your whole collection lives in this tab.', tapTarget: true),
        ];
        final c = _controller(tester);
        c.showOnce(_pageContext(tester), Guide(id: 'overflow-$align', steps: steps), force: true);
        await settle(tester);
        for (var i = 0; i < steps.length - 1; i++) {
          expect(tester.takeException(), isNull, reason: '$align step $i');
          await tester.tap(find.byKey(const Key('guide-next')));
          await settle(tester, 450);
        }
        expect(find.byKey(const Key('guide-tap-hint')), findsOneWidget);
        expect(tester.takeException(), isNull, reason: '$align tap step');
        c.dismiss();
        await settle(tester, 500);
        await tester.pumpWidget(const SizedBox());
      }
    });

    testWidgets('one guide at a time; tips off or not onboarded: not shown', (tester) async {
      final store = MemoryGuideStore();
      await tester.pumpWidget(_app(store, _Page(target: GlobalKey(), onTap: () {})));
      final c = _controller(tester);
      final ctx = _pageContext(tester);
      c.showOnce(ctx, const Guide(id: GuideIds.home, steps: [GuideStep(title: 'A', body: 'a')]));
      await settle(tester, 100);
      expect(await c.showOnce(ctx, const Guide(id: GuideIds.map, steps: [GuideStep(title: 'B', body: 'b')])), GuideResult.notShown);
      c.dismiss();
      await settle(tester, 500);

      store.tipsOn = false;
      expect(await c.showOnce(ctx, const Guide(id: GuideIds.chats, steps: [GuideStep(title: 'C', body: 'c')])), GuideResult.notShown);
      store
        ..tipsOn = true
        ..onboarded = false;
      expect(await c.showOnce(ctx, const Guide(id: GuideIds.chats, steps: [GuideStep(title: 'C', body: 'c')])), GuideResult.notShown);
      expect(store.seen, [GuideIds.home]);

      await c.resetAll();
      expect(store.seen, isEmpty);
      expect(c.seen(GuideIds.home), isFalse);
    });

    testWidgets('system Back closes the guide as skipped (no router)', (tester) async {
      final store = MemoryGuideStore();
      await tester.pumpWidget(_app(store, _Page(target: GlobalKey(), onTap: () {})));
      GuideResult? result;
      _controller(tester).showOnce(_pageContext(tester), const Guide(id: GuideIds.home, steps: [GuideStep(title: 'Back test', body: 'b')])).then((r) => result = r);
      await settle(tester);
      await systemBack(tester);
      await settle(tester, 500);
      expect(result, GuideResult.skipped);
      expect(find.text('Back test'), findsNothing);
    });

    testWidgets('Back with go_router closes the guide, not the page', (tester) async {
      final store = MemoryGuideStore();
      final router = GoRouter(routes: [
        GoRoute(path: '/', builder: (_, _) => const Scaffold(body: Text('root'))),
        GoRoute(path: '/b', builder: (_, _) => const Scaffold(body: Text('page b'))),
      ]);
      addTearDown(router.dispose);
      await tester.pumpWidget(ProviderScope(overrides: [guideStoreProvider.overrideWithValue(store)], child: MaterialApp.router(routerConfig: router)));
      router.push('/b');
      await tester.pumpAndSettle();
      expect(find.text('page b'), findsOneWidget);
      GuideResult? result;
      final ctx = tester.element(find.text('page b'));
      ProviderScope.containerOf(ctx).read(guideControllerProvider).showOnce(ctx, const Guide(id: GuideIds.event, steps: [GuideStep(title: 'Meet page', body: 'b')])).then((r) => result = r);
      await settle(tester);
      await systemBack(tester);
      await settle(tester, 500);
      expect(result, GuideResult.skipped);
      expect(find.text('page b'), findsOneWidget);
    });

    testWidgets('reduce motion still shows and ends cleanly', (tester) async {
      final store = MemoryGuideStore();
      final target = GlobalKey();
      await tester.pumpWidget(ProviderScope(
        overrides: [guideStoreProvider.overrideWithValue(store)],
        child: MaterialApp(
          builder: (context, child) => MediaQuery(data: MediaQuery.of(context).copyWith(disableAnimations: true), child: child!),
          home: _Page(target: target, onTap: () {}),
        ),
      ));
      GuideResult? result;
      _controller(tester).showOnce(_pageContext(tester), Guide(id: GuideIds.home, steps: [
        GuideStep(target: target, title: 'Calm', body: 'No springs.'),
        const GuideStep(title: 'Calm two', body: 'Still calm.'),
      ])).then((r) => result = r);
      await settle(tester, 300);
      expect(find.text('Calm'), findsOneWidget);
      await tester.tap(find.byKey(const Key('guide-next')));
      await settle(tester, 300);
      await tester.tap(find.byKey(const Key('guide-next')));
      await settle(tester, 300);
      expect(result, GuideResult.finished);
      expect(tester.takeException(), isNull);
    });
  });

  group('GuideOnFirstView', () {
    Widget page(MemoryGuideStore store, {bool ready = true, void Function(GuideResult)? onDone}) => _app(
          store,
          Scaffold(
            body: GuideOnFirstView(
              id: GuideIds.garage,
              ready: ready,
              onDone: onDone,
              build: () => const Guide(id: GuideIds.garage, steps: [GuideStep(title: 'Your garage', body: 'Your cars live here.')]),
              child: const SizedBox.expand(child: ColoredBox(color: Colors.white)),
            ),
          ),
        );

    testWidgets('shows after the delay when not seen', (tester) async {
      final store = MemoryGuideStore();
      GuideResult? done;
      await tester.pumpWidget(page(store, onDone: (r) => done = r));
      await settle(tester, 300);
      expect(find.text('Your garage'), findsNothing); // still waiting the beat
      await settle(tester, 1000);
      expect(find.text('Your garage'), findsOneWidget);
      expect(store.seen, [GuideIds.garage]);
      await tester.tap(find.byKey(const Key('guide-next')));
      await settle(tester, 500);
      expect(done, GuideResult.finished);
    });

    testWidgets('not when seen', (tester) async {
      final store = MemoryGuideStore(seen: [GuideIds.garage]);
      await tester.pumpWidget(page(store));
      await settle(tester, 2000);
      expect(find.text('Your garage'), findsNothing);
    });

    testWidgets('not when tips are off', (tester) async {
      final store = MemoryGuideStore(tipsOn: false);
      await tester.pumpWidget(page(store));
      await settle(tester, 2000);
      expect(find.text('Your garage'), findsNothing);
      expect(store.seen, isEmpty);
    });

    testWidgets('not while not onboarded', (tester) async {
      final store = MemoryGuideStore(onboarded: false);
      await tester.pumpWidget(page(store));
      await settle(tester, 2000);
      expect(find.text('Your garage'), findsNothing);
    });

    testWidgets('waits for ready', (tester) async {
      final store = MemoryGuideStore();
      await tester.pumpWidget(page(store, ready: false));
      await settle(tester, 2000);
      expect(find.text('Your garage'), findsNothing);
      await tester.pumpWidget(page(store));
      await settle(tester, 1200);
      expect(find.text('Your garage'), findsOneWidget);
      _controller(tester).dismiss();
      await settle(tester, 500);
    });

    testWidgets('not over a dialog; shows once it closes', (tester) async {
      final store = MemoryGuideStore();
      await tester.pumpWidget(page(store));
      final ctx = tester.element(find.byType(GuideOnFirstView));
      showDialog<void>(context: ctx, builder: (_) => const AlertDialog(content: Text('Dialog')));
      await settle(tester, 2000);
      expect(find.text('Your garage'), findsNothing);
      Navigator.of(ctx).pop();
      await settle(tester, 1500);
      expect(find.text('Your garage'), findsOneWidget);
      _controller(tester).dismiss();
      await settle(tester, 500);
    });

    testWidgets('a hidden tab (tickers off) waits until shown', (tester) async {
      final store = MemoryGuideStore();
      final visible = ValueNotifier(false);
      addTearDown(visible.dispose);
      await tester.pumpWidget(_app(
        store,
        Scaffold(
          body: ValueListenableBuilder<bool>(
            valueListenable: visible,
            builder: (_, on, _) => IndexedStack(
              index: on ? 1 : 0,
              children: [
                const SizedBox.expand(),
                TickerMode(
                  enabled: on,
                  child: GuideOnFirstView(
                    id: GuideIds.map,
                    build: () => const Guide(id: GuideIds.map, steps: [GuideStep(title: 'The map', body: 'Who is out now.')]),
                    child: const SizedBox.expand(child: ColoredBox(color: Colors.white)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ));
      await settle(tester, 2000);
      expect(find.text('The map'), findsNothing);
      visible.value = true;
      await settle(tester, 1200);
      expect(find.text('The map'), findsOneWidget);
      _controller(tester).dismiss();
      await settle(tester, 500);
    });
  });

  test('AppSettings reads tips and guides_seen', () {
    expect(const AppSettings({}).tipsOn, isTrue);
    expect(const AppSettings({}).guidesSeen, isEmpty);
    expect(const AppSettings({'tips': false}).tipsOn, isFalse);
    expect(const AppSettings({'guides_seen': ['home', 3, 'map']}).guidesSeen, ['home', 'map']);
  });
}
