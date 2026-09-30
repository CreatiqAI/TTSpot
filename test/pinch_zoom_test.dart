import 'package:car_meet/core/widgets/pinch_zoom.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Scale of the lifted copy of the photo keyed [key], or null when it isn't out.
double? _liftedScale(WidgetTester t, [String key = 'photo']) {
  final lifted = t.widgetList<Transform>(find.byWidgetPredicate((w) => w is Transform && w.child?.key == Key(key)));
  return lifted.isEmpty ? null : lifted.first.transform.entry(0, 0);
}

Widget _page({required Widget photo}) => MaterialApp(
      home: Scaffold(
        body: ListView(
          physics: const PinchLockScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
          children: [
            const SizedBox(height: 100),
            SizedBox(height: 300, child: photo),
            const SizedBox(height: 2000),
          ],
        ),
      ),
    );

void main() {
  tearDown(() => PinchZoom.active.value = false);

  testWidgets('two fingers lift the photo, the page holds still, it springs back', (t) async {
    await t.pumpWidget(_page(photo: const PinchZoom(child: ColoredBox(key: Key('photo'), color: Colors.red))));
    final c = t.getCenter(find.byKey(const Key('photo')));
    final a = await t.startGesture(c - const Offset(40, 0), pointer: 1);
    final b = await t.startGesture(c + const Offset(40, 0), pointer: 2);
    for (var i = 1; i <= 8; i++) {
      // Spread apart and drift down together, like a real pinch.
      await a.moveBy(const Offset(-10, 6));
      await b.moveBy(const Offset(10, 6));
      await t.pump(const Duration(milliseconds: 16));
    }
    expect(PinchZoom.active.value, isTrue);
    expect(_liftedScale(t), closeTo(3.0, 0.05)); // 80 px apart → 240 px apart
    final list = t.state<ScrollableState>(find.byType(Scrollable).first);
    expect(list.position.pixels, 0, reason: 'the pinch must not scroll the page');

    await b.up();
    await t.pump(); // the spring starts on the next frame
    await t.pump(const Duration(milliseconds: 120));
    expect(_liftedScale(t)!, lessThan(3.0)); // on its way back
    await t.pump(const Duration(milliseconds: 200));
    await a.up();
    await t.pumpAndSettle();
    expect(PinchZoom.active.value, isFalse);
    expect(_liftedScale(t), isNull);
    expect(list.position.pixels, 0, reason: 'letting go must not fling the page');
  });

  testWidgets('one finger still scrolls the page', (t) async {
    await t.pumpWidget(_page(photo: const PinchZoom(child: ColoredBox(key: Key('photo'), color: Colors.red))));
    await t.drag(find.byKey(const Key('photo')), const Offset(0, -200));
    await t.pumpAndSettle();
    expect(t.state<ScrollableState>(find.byType(Scrollable).first).position.pixels, greaterThan(100));
    expect(_liftedScale(t), isNull);
  });

  testWidgets('a pinch that drifts sideways does not turn the photo page', (t) async {
    var page = 0;
    await t.pumpWidget(_page(
      photo: PageView(
        pageSnapping: false,
        physics: const PinchLockScrollPhysics(parent: PageScrollPhysics()),
        onPageChanged: (i) => page = i,
        children: const [
          PinchZoom(child: ColoredBox(key: Key('p0'), color: Colors.red)),
          PinchZoom(child: ColoredBox(key: Key('p1'), color: Colors.blue)),
        ],
      ),
    ));
    final c = t.getCenter(find.byKey(const Key('p0')));
    final a = await t.startGesture(c - const Offset(30, 0), pointer: 1);
    final b = await t.startGesture(c + const Offset(30, 0), pointer: 2);
    for (var i = 0; i < 8; i++) {
      await a.moveBy(const Offset(-6, 0));
      await b.moveBy(const Offset(30, 0)); // both lean right, fast
      await t.pump(const Duration(milliseconds: 16));
    }
    await b.up();
    await a.up();
    await t.pumpAndSettle();
    expect(page, 0);

    // A normal one-finger swipe still turns it.
    await t.fling(find.byKey(const Key('p0')), const Offset(-300, 0), 1000);
    await t.pumpAndSettle();
    expect(page, 1);
  });

  testWidgets('on a post page: pinch lifts the photo, no tap, like, refresh, scroll or page turn', (t) async {
    var taps = 0, likes = 0, refreshes = 0, page = 0;
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: RefreshIndicator(
          onRefresh: () async => refreshes++,
          child: ListView(
            physics: const PinchLockScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
            children: [
              const SizedBox(height: 60),
              GestureDetector(
                onTap: () => taps++,
                onDoubleTap: () => likes++,
                child: SizedBox(
                  height: 320,
                  child: PageView(
                    pageSnapping: false,
                    physics: const PinchLockScrollPhysics(parent: PageScrollPhysics()),
                    onPageChanged: (i) => page = i,
                    children: const [
                      PinchZoom(child: ColoredBox(key: Key('p0'), color: Colors.red)),
                      PinchZoom(child: ColoredBox(key: Key('p1'), color: Colors.blue)),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 1500),
            ],
          ),
        ),
      ),
    ));
    final list = t.state<ScrollableState>(find.byType(Scrollable).first);
    final c = t.getCenter(find.byKey(const Key('p0')));
    // Second finger lands a beat late, after the first has started moving.
    final a = await t.startGesture(c + const Offset(-20, 10), pointer: 1);
    await a.moveBy(const Offset(-30, 40));
    await t.pump(const Duration(milliseconds: 16));
    final b = await t.startGesture(c + const Offset(40, 0), pointer: 2);
    for (var i = 0; i < 10; i++) {
      await a.moveBy(const Offset(-8, 12));
      await b.moveBy(const Offset(14, 12));
      await t.pump(const Duration(milliseconds: 16));
    }
    expect(_liftedScale(t, 'p0'), greaterThan(1.5));
    await a.up();
    await t.pump();
    await t.pump(const Duration(milliseconds: 60));
    await b.up();
    await t.pumpAndSettle();
    expect(_liftedScale(t, 'p0'), isNull);
    expect(PinchZoom.active.value, isFalse);
    expect(page, 0);
    expect(taps, 0);
    expect(likes, 0);
    expect(refreshes, 0);
    // Only the first finger's lone drift before the pinch may have moved it.
    expect(list.position.pixels, lessThanOrEqualTo(0));
  });
}
