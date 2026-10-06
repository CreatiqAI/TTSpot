import 'package:car_meet/core/geo/latlng.dart';
import 'package:car_meet/core/theme/app_theme.dart';
import 'package:car_meet/features/friends/application/friends_providers.dart';
import 'package:car_meet/features/friends/domain/friend.dart';
import 'package:car_meet/features/map/application/map_providers.dart';
import 'package:car_meet/features/map/presentation/widgets/map_legend.dart';
import 'package:car_meet/features/map/presentation/widgets/place_card.dart';
import 'package:car_meet/features/settings/application/settings_providers.dart';
import 'package:car_meet/features/social/application/community_providers.dart';
import 'package:car_meet/features/social/domain/club.dart';
import 'package:car_meet/features/vendors/application/vendors_providers.dart';
import 'package:car_meet/features/vendors/domain/vendor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

class _FakeSettings extends SettingsNotifier {
  @override
  AppSettings build() => AppSettings(const {'map_key_seen': false});
}

class _QuietSettingsActions extends SettingsActions {
  _QuietSettingsActions(super.ref);
  @override
  Future<void> patch(Map<String, dynamic> patch) async {}
}

void _phone(WidgetTester t, Size size) {
  t.view.physicalSize = size * 3;
  t.view.devicePixelRatio = 3;
  addTearDown(t.view.reset);
}

Widget _scaled(double scale, Widget child) => Builder(
      builder: (context) => MediaQuery(data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)), child: child),
    );

// ---------------------------------------------------------------------- key ---

Future<void> _pumpKey(
  WidgetTester t, {
  required Set<LegendGlyph> present,
  List<({Color color, String tag, String names})> tagged = const [],
  ValueChanged<String>? onRow,
  ({String row, int index, int total})? cycle,
  double scale = 1,
  Size size = const Size(393, 851),
}) async {
  _phone(t, size);
  await t.pumpWidget(ProviderScope(
    overrides: [
      settingsProvider.overrideWith(_FakeSettings.new),
      settingsActionsProvider.overrideWith(_QuietSettingsActions.new),
    ],
    child: MaterialApp(
      theme: AppTheme.current,
      home: _scaled(
        scale,
        Scaffold(
          backgroundColor: Colors.grey,
          body: SafeArea(
            child: Align(
              alignment: Alignment.topLeft,
              child: Padding(
                padding: const EdgeInsets.only(left: 12, top: 60, bottom: 200),
                child: MapLegend(light: true, present: present, tagged: tagged, onRow: onRow, cycle: cycle),
              ),
            ),
          ),
        ),
      ),
    ),
  ));
  await t.pump();
}

const _a = LatLng(3.1036, 101.7488); // the map centre in these tests
const _near = LatLng(3.1040, 101.7490);
const _mid = LatLng(3.1100, 101.7500);
const _far = LatLng(3.1500, 101.8000);

// --------------------------------------------------------------- the card ---

Place _place({String? vendorId, String name = 'Auto Lab', String kind = 'workshop'}) => Place(
      id: 'p1',
      name: name,
      kind: kind,
      lat: 3.1036,
      lng: 101.7488,
      createdAt: DateTime(2026),
      checkinsTotal: 12,
      upcomingMeets: 2,
      recommended: vendorId == null,
      vendorId: vendorId,
      vendorName: vendorId == null ? null : name,
    );

Future<GoRouter> _pumpCard(WidgetTester t, Place place, {double scale = 1, Size size = const Size(393, 851), bool light = true}) async {
  _phone(t, size);
  final router = GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(
        path: '/',
        builder: (_, _) => Scaffold(
          backgroundColor: Colors.grey,
          body: Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
              child: MapPalette(light: light, child: PlacePreviewCard(place: place, onClose: () {})),
            ),
          ),
        ),
      ),
      GoRoute(path: '/partner/:id', builder: (_, s) => Scaffold(body: Text('SHOP ${s.pathParameters['id']}'))),
      GoRoute(path: '/place/:id', builder: (_, s) => Scaffold(body: Text('SPOT ${s.pathParameters['id']}'))),
    ],
  );
  await t.pumpWidget(ProviderScope(
    overrides: [
      placeProvider.overrideWith((ref, id) async => place),
      userLocationProvider.overrideWith((ref) async => const LatLng(3.1100, 101.7500)),
      vendorPublicProvider.overrideWith((ref, id) async => PublicVendor(id: id, name: place.name, type: 'workshop', address: '12, Jalan Klang Lama, 58000 Kuala Lumpur')),
      shopVouchersProvider.overrideWith((ref) async => const []),
      friendPinsProvider.overrideWith((ref) => Stream.value(const <FriendPin>[])),
      placeRecentVisitorsProvider.overrideWith((ref, id) async => const <PlaceVisit>[]),
    ],
    child: MaterialApp.router(
      theme: AppTheme.current,
      routerConfig: router,
      builder: (context, c) => MediaQuery(data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)), child: c!),
    ),
  ));
  await t.pump();
  await t.pump(const Duration(milliseconds: 100));
  return router;
}

void main() {
  group('map key', () {
    testWidgets('a tap on a row asks for that kind; rows are 44 px buttons; the header alone folds it', (t) async {
      final taps = <String>[];
      await _pumpKey(
        t,
        present: {LegendGlyph.me, LegendGlyph.partner, LegendGlyph.cafe, LegendGlyph.eventMajor},
        tagged: [(color: Colors.pink, tag: 'pink', names: 'Ali, Ben')],
        onRow: taps.add,
      );
      for (final label in ['You', 'Partner shop', 'Car café', 'Official event', 'Ali, Ben']) {
        expect(find.text(label), findsOneWidget);
      }
      // every row is at least 44 px tall
      for (final key in ['map-key-me', 'map-key-partner', 'map-key-cafe', 'map-key-eventMajor', 'map-key-tag-pink']) {
        expect(t.getSize(find.byKey(ValueKey(key))).height, greaterThanOrEqualTo(44), reason: key);
      }

      await t.tap(find.text('Partner shop'));
      await t.tap(find.text('Car café'));
      await t.tap(find.text('Ali, Ben'));
      await t.tap(find.text('You'));
      expect(taps, ['g:partner', 'g:cafe', 't:pink', 'g:me']);
      expect(glyphOfKeyRow(taps[0]), LegendGlyph.partner);
      expect(glyphOfKeyRow(taps[2]), isNull);
      expect(find.text('Partner shop'), findsOneWidget, reason: 'a row tap does not fold the key');

      // pressed state: the row's highlight paints while the finger is down
      final well = t.widget<InkWell>(find.ancestor(of: find.text('Official event'), matching: find.byType(InkWell)).first);
      expect(well.highlightColor, isNotNull);
      final ink = Material.of(t.element(find.text('Official event')));
      expect(ink, isNot(paints..rect(color: well.highlightColor)));
      final g = await t.startGesture(t.getCenter(find.text('Official event')));
      for (var i = 0; i < 8; i++) {
        await t.pump(const Duration(milliseconds: 60)); // press timeout, then the highlight fades in
      }
      expect(ink, paints..rect(color: well.highlightColor));
      await g.up();
      await t.pump(const Duration(milliseconds: 300));

      // only the header folds and unfolds
      await t.tap(find.byKey(const ValueKey('map-key-header')));
      await t.pump(const Duration(milliseconds: 300));
      expect(find.text('Partner shop'), findsNothing);
      await t.tap(find.byKey(const ValueKey('map-key-header')));
      await t.pump(const Duration(milliseconds: 300));
      expect(find.text('Partner shop'), findsOneWidget);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
    });

    testWidgets('the row being stepped through shows where it is', (t) async {
      await _pumpKey(t, present: {LegendGlyph.partner, LegendGlyph.cafe}, onRow: (_) {}, cycle: (row: 'g:partner', index: 1, total: 3));
      expect(find.text('2/3'), findsOneWidget);
      await t.pumpWidget(const SizedBox());
    });

    for (final size in [const Size(360, 640), const Size(393, 851)]) {
      for (final scale in [1.0, 1.3]) {
        testWidgets('a busy key fits ${size.width.round()}x${size.height.round()} at text x$scale (scrolls inside)', (t) async {
          await _pumpKey(t, present: LegendGlyph.values.toSet(), tagged: [(color: Colors.pink, tag: 'pink', names: 'Ali, Ben, Chong')], onRow: (_) {}, scale: scale, size: size);
          expect(t.takeException(), isNull);
          final panel = t.getRect(find.byType(MapLegend));
          expect(panel.width, lessThanOrEqualTo(size.width * 0.45 + 0.5));
          expect(panel.bottom, lessThanOrEqualTo(size.height));
          await t.pumpWidget(const SizedBox());
        });
      }
    }
  });

  group('KeyCycle', () {
    final now = DateTime(2026, 10, 6, 12);
    var asked = 0;
    List<KeyTarget> pins() {
      asked++;
      return [(_far, null), (_near, null), (_mid, null)];
    }

    test('first tap: the nearest pin to the centre', () {
      asked = 0;
      final c = KeyCycle.tap(null, 'g:partner', now, inView: pins, origin: _a)!;
      expect(c.current.$1, _near);
      expect([for (final t in c.targets) t.$1], [_near, _mid, _far]);
      expect(asked, 1);
    });

    test('the same row again steps to the next nearest, round and round, without asking again', () {
      asked = 0;
      var c = KeyCycle.tap(null, 'g:partner', now, inView: pins, origin: _a)!;
      c = KeyCycle.tap(c, 'g:partner', now.add(const Duration(seconds: 3)), inView: pins, origin: _far)!;
      expect(c.current.$1, _mid);
      expect(c.index, 1);
      c = KeyCycle.tap(c, 'g:partner', now.add(const Duration(seconds: 6)), inView: pins, origin: _far)!;
      expect(c.current.$1, _far);
      c = KeyCycle.tap(c, 'g:partner', now.add(const Duration(seconds: 9)), inView: pins, origin: _far)!;
      expect(c.current.$1, _near, reason: 'back to the first');
      expect(asked, 1, reason: 'the list from the first tap is kept, even though the camera moved');
    });

    test('another row, or the same one much later, starts afresh', () {
      asked = 0;
      var c = KeyCycle.tap(null, 'g:partner', now, inView: pins, origin: _a)!;
      c = KeyCycle.tap(c, 'g:cafe', now.add(const Duration(seconds: 2)), inView: pins, origin: _a)!;
      expect(c.row, 'g:cafe');
      expect(c.index, 0);
      c = KeyCycle.tap(c, 'g:cafe', now.add(const Duration(minutes: 5)), inView: pins, origin: _far)!;
      expect(c.index, 0);
      expect(c.current.$1, _far, reason: 'nearest to the new origin');
      expect(asked, 3);
    });

    test('nothing of that kind in view: no target', () {
      expect(KeyCycle.tap(null, 'g:partner', now, inView: () => const [], origin: _a), isNull);
    });

    test('the target carries the pin tap (what opens its card / page)', () {
      var opened = 0;
      final c = KeyCycle.tap(null, 'g:partner', now, inView: () => [(_near, () => opened++)], origin: _a)!;
      c.current.$2!();
      expect(opened, 1);
    });
  });

  group('place card', () {
    for (final partner in [true, false]) {
      for (final scale in [1.0, 1.3]) {
        for (final size in [const Size(393, 851), const Size(360, 640)]) {
          testWidgets('${partner ? 'partner' : 'spot'}: full-width main action, Go now and TT here under it (${size.width.round()} wide, text x$scale)', (t) async {
            await _pumpCard(t, _place(vendorId: partner ? 'v1' : null, name: partner ? 'Auto Lab Performance Garage' : 'Wheels Cafe Bangsar South'), scale: scale, size: size);
            expect(t.takeException(), isNull);
            final view = find.byKey(const ValueKey('place-card-view'));
            expect(find.descendant(of: view, matching: find.text(partner ? 'View shop' : 'View spot')), findsOneWidget);
            final card = t.getRect(find.byType(PlacePreviewCard));
            final main = t.getRect(view);
            final go = t.getRect(find.text('Go now'));
            final tt = t.getRect(find.text('TT here'));
            expect(main.width, greaterThan(card.width - 40), reason: 'its own full-width row');
            expect(main.height, greaterThanOrEqualTo(46));
            expect(go.top, greaterThan(main.bottom), reason: 'the pair sits under it');
            expect((go.center.dy - tt.center.dy).abs(), lessThan(1), reason: 'Go now and TT here side by side');
            expect(card.bottom, lessThanOrEqualTo(size.height));
          });
        }
      }
    }

    testWidgets('the main button and the header both open the page', (t) async {
      final router = await _pumpCard(t, _place(vendorId: 'v1'));
      await t.tap(find.byKey(const ValueKey('place-card-view')));
      await t.pumpAndSettle();
      expect(find.text('SHOP v1'), findsOneWidget);
      router.pop();
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('place-card-header')));
      await t.pumpAndSettle();
      expect(find.text('SHOP v1'), findsOneWidget);
    });

    testWidgets('a spot opens its spot page', (t) async {
      await _pumpCard(t, _place(), light: false);
      await t.tap(find.text('View spot'));
      await t.pumpAndSettle();
      expect(find.text('SPOT p1'), findsOneWidget);
    });
  });
}
