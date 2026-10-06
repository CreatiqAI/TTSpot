import 'package:car_meet/core/theme/app_theme.dart';
import 'package:car_meet/features/auth/data/auth_repository.dart';
import 'package:car_meet/features/cards/application/cards_providers.dart';
import 'package:car_meet/features/cards/domain/cards.dart';
import 'package:car_meet/features/cards/presentation/open_box_screen.dart';
import 'package:car_meet/features/cards/presentation/widgets/card_face.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

const _card = CardType(
  id: 'c1',
  setId: 's1',
  number: 1,
  name: 'Myvi Kencang',
  rarity: CardRarity.common,
  color: Color(0xFF9AA0A8),
  active: true,
  sort: 1,
  description: 'The little car that could, and did.',
);

/// The server's open_box(): the card is the member's the moment this
/// resolves. Counts the calls so a test can tell the roll really ran.
class _FakeActions extends CardsActions {
  _FakeActions(super.ref);
  int opened = 0;

  @override
  Future<BoxResult> openBox(String boxId) async {
    opened++;
    return const BoxResult(userCardId: 'uc-1', card: _card, held: 1);
  }
}

_FakeActions? _actions;

Future<GoRouter> _pump(WidgetTester t, {double scale = 1, Size size = const Size(393, 851), int moreBoxes = 0, String boxId = 'b1'}) async {
  _actions = null;
  t.view.physicalSize = size * 3;
  t.view.devicePixelRatio = 3;
  addTearDown(t.view.reset);
  // The phone's accelerometer: nothing comes in, but listening must not throw.
  t.binding.defaultBinaryMessenger.setMockStreamHandler(const EventChannel('my.ttspot.app/motion'), MockStreamHandler.inline(onListen: (_, _) {}));
  addTearDown(() => t.binding.defaultBinaryMessenger.setMockStreamHandler(const EventChannel('my.ttspot.app/motion'), null));

  final router = GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(path: '/', builder: (_, _) => const Scaffold(body: Center(child: Text('HOME')))),
      GoRoute(path: '/box', builder: (_, _) => OpenBoxScreen(boxId: boxId)),
    ],
  );
  await t.pumpWidget(ProviderScope(
    overrides: [
      cardsActionsProvider.overrideWith((ref) => _actions = _FakeActions(ref)),
      myBoxesProvider.overrideWith((ref) async => [
            for (var i = 0; i <= moreBoxes; i++) CardBox(id: 'b${i + 1}', source: 'signup', status: 'sealed', pointsSpent: 0, createdAt: DateTime(2026)),
          ]),
      cardSettingsProvider.overrideWith((ref) async => const CardSettings(common: 89.5, rare: 10, legendary: 0.5)),
      currentProfileProvider.overrideWith((ref) async => null),
      cardTypesProvider.overrideWith((ref) async => const [_card]),
    ],
    child: MaterialApp.router(
      theme: AppTheme.current,
      routerConfig: router,
      builder: (context, c) => MediaQuery(data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)), child: c!),
    ),
  ));
  router.push('/box');
  await t.pump();
  await t.pump(const Duration(milliseconds: 400));
  return router;
}

/// Three taps on the box, then the burst, the drop-in flip and the button.
Future<void> _openIt(WidgetTester t) async {
  for (var i = 0; i < 3; i++) {
    // the crack overlay sits on the image; the tap still lands on the box
    await t.tap(find.image(const AssetImage('assets/titi/box_closed.png')), warnIfMissed: false);
    await t.pump(const Duration(milliseconds: 450));
  }
  await t.pump(const Duration(milliseconds: 1150)); // burst
  await t.pump(const Duration(milliseconds: 750)); // flip
  await t.pump(const Duration(milliseconds: 1200)); // reveal + "Add to my cards" rises
  expect(find.text('Myvi Kencang'), findsOneWidget);
}

/// Lets the flight finish, the profile refresh answer and the route pop.
Future<void> _settle(WidgetTester t) async {
  for (var i = 0; i < 20; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

Finder get _front => find.byKey(const ValueKey('card-front'));
Finder get _back => find.byKey(const ValueKey('card-back'));

/// A few real frames: an animation started now needs a first tick to begin.
Future<void> _frames(WidgetTester t, int ms) async {
  for (var i = 0; i < ms ~/ 50; i++) {
    await t.pump(const Duration(milliseconds: 50));
  }
}

Future<void> _swipe(WidgetTester t, double dx) async {
  await t.dragFrom(t.getCenter(find.byType(TiltCard)), Offset(dx, 0));
  await _frames(t, 500);
}

void main() {
  testWidgets('the revealed card flips back and forth on every swipe, either way, and on a tap', (t) async {
    await _pump(t);
    await _openIt(t);
    expect(_actions?.opened ?? 0, 1, reason: 'the server roll ran once');
    expect(_front, findsOneWidget);
    expect(find.text('Swipe or tap to flip'), findsOneWidget);

    // left, left, left: back, front, back (it never gets stuck on one side)
    await _swipe(t, -220);
    expect(_back, findsOneWidget);
    await _swipe(t, -220);
    expect(_front, findsOneWidget);
    await _swipe(t, -220);
    expect(_back, findsOneWidget);
    // right, right: front, back
    await _swipe(t, 220);
    expect(_front, findsOneWidget);
    await _swipe(t, 220);
    expect(_back, findsOneWidget);
    // a small nudge springs back
    await _swipe(t, 40);
    expect(_back, findsOneWidget);
    // taps turn it too
    await t.tap(find.byType(TiltCard));
    await _frames(t, 500);
    expect(_front, findsOneWidget);
    await t.tap(find.byType(TiltCard));
    await _frames(t, 500);
    expect(_back, findsOneWidget);
    // still on the screen: a tap on the card never closes it
    expect(find.text('HOME'), findsNothing);
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('Add to my cards: the card flies into "My cards", +1, saved, then the screen closes', (t) async {
    await _pump(t);
    await _openIt(t);
    expect(find.text('Add to my cards'), findsOneWidget);
    expect(find.text('Already in your cards · tap outside to close'), findsOneWidget);

    await t.tap(find.text('Add to my cards'));
    await _frames(t, 250);
    expect(find.text('My cards'), findsOneWidget, reason: 'the button becomes the target');
    // the flying copy is up, the original hidden
    expect(_front, findsNWidgets(2));
    await _frames(t, 600);
    expect(find.text('Saved to My cards'), findsOneWidget);
    expect(find.text('+1'), findsOneWidget);
    await _settle(t);
    expect(find.text('HOME'), findsOneWidget);
    expect(_actions?.opened ?? 0, 1);
    expect(t.takeException(), isNull);
  });

  testWidgets('after the reveal the X closes (the card is already saved)', (t) async {
    await _pump(t);
    await _openIt(t);
    await t.tap(find.byKey(const ValueKey('open-box-close')));
    await _settle(t);
    expect(find.text('HOME'), findsOneWidget);
    expect(_actions?.opened ?? 0, 1);
  });

  testWidgets('a tap on the blank space outside the card closes', (t) async {
    await _pump(t);
    await _openIt(t);
    await t.tapAt(const Offset(16, 160));
    await _settle(t);
    expect(find.text('HOME'), findsOneWidget);
  });

  testWidgets('system back closes after the reveal', (t) async {
    await _pump(t);
    await _openIt(t);
    await t.binding.handlePopRoute();
    await _settle(t);
    expect(find.text('HOME'), findsOneWidget);
  });

  testWidgets('a swipe down from outside the card closes; a short one springs back', (t) async {
    await _pump(t);
    await _openIt(t);
    await t.dragFrom(const Offset(16, 200), const Offset(0, 50));
    await t.pump(const Duration(milliseconds: 400));
    expect(find.text('HOME'), findsNothing);
    await t.dragFrom(const Offset(16, 200), const Offset(0, 220));
    await _settle(t);
    expect(find.text('HOME'), findsOneWidget);
  });

  testWidgets('the QA preview (debug / local release test) reveals a sample card without the server', (t) async {
    await _pump(t, boxId: kOpenBoxPreviewId);
    await _openIt(t);
    expect(_actions?.opened ?? 0, 0, reason: 'no box opened, nothing rolled');
    expect(_front, findsOneWidget);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('before any shake the X leaves at once and never opens the box', (t) async {
    await _pump(t);
    await t.tap(find.byKey(const ValueKey('open-box-close')));
    await _settle(t);
    expect(find.text('HOME'), findsOneWidget);
    expect(_actions?.opened ?? 0, 0, reason: 'the box stays sealed');
  });

  for (final size in [const Size(393, 851), const Size(360, 640)]) {
    for (final scale in [1.0, 1.3]) {
      testWidgets('revealed screen lays out on ${size.width.round()}x${size.height.round()} at text x$scale', (t) async {
        await _pump(t, scale: scale, size: size, moreBoxes: 2);
        await _openIt(t);
        expect(find.text('Open another (2)'), findsOneWidget);
        // the X and the button are on screen and big enough to hit
        final x = t.getRect(find.byKey(const ValueKey('open-box-close')));
        expect(x.width, greaterThanOrEqualTo(44));
        expect(x.top, greaterThanOrEqualTo(0));
        final add = t.getRect(find.byKey(const ValueKey('open-box-add')));
        expect(add.height, greaterThanOrEqualTo(48));
        expect(add.bottom, lessThanOrEqualTo(size.height));
        expect(t.takeException(), isNull);
        await t.pumpWidget(const SizedBox());
      });
    }
  }
}
