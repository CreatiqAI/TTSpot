import 'package:car_meet/core/geo/latlng.dart';
import 'package:car_meet/core/theme/app_icons.dart';
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
  List<({Color color, String names})> tagged = const [],
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
                child: MapLegend(light: true, present: present, tagged: tagged),
              ),
            ),
          ),
        ),
      ),
    ),
  ));
  await t.pump();
}

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
    testWidgets('plain rows for the kinds in view only; no row is a button; a tap folds and unfolds it', (t) async {
      await _pumpKey(
        t,
        present: {LegendGlyph.me, LegendGlyph.partner, LegendGlyph.cafe, LegendGlyph.eventMajor},
        tagged: [(color: Colors.pink, names: 'Ali, Ben')],
      );
      for (final label in ['You', 'Partner shop', 'Car café', 'Official event', 'Ali, Ben']) {
        expect(find.text(label), findsOneWidget);
      }
      // only what is in view
      for (final label in ['Friend', 'Mamak', 'Partner event', 'Moment']) {
        expect(find.text(label), findsNothing, reason: label);
      }
      // compact rows, no carets, no step counter: nothing says "tap me"
      expect(t.getSize(find.text('Partner shop')).height, lessThan(30));
      expect(find.byIcon(AppIcons.caretRight), findsNothing, reason: 'open: only the KEY header caret, pointing down');
      expect(find.byIcon(AppIcons.caretDown), findsOneWidget);
      // one tap target for the whole panel (the fold), none per row
      expect(find.byType(InkWell), findsOneWidget);

      await t.tap(find.text('KEY'));
      await t.pump(const Duration(milliseconds: 300));
      expect(find.text('Partner shop'), findsNothing);
      expect(find.byIcon(AppIcons.caretRight), findsOneWidget);
      await t.tap(find.text('KEY'));
      await t.pump(const Duration(milliseconds: 300));
      expect(find.text('Partner shop'), findsOneWidget);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
    });

    testWidgets('nothing in view: no key at all', (t) async {
      await _pumpKey(t, present: const {});
      expect(find.text('KEY'), findsNothing);
      await t.pumpWidget(const SizedBox());
    });

    for (final size in [const Size(360, 640), const Size(393, 851)]) {
      for (final scale in [1.0, 1.3]) {
        testWidgets('a busy key fits ${size.width.round()}x${size.height.round()} at text x$scale (scrolls inside)', (t) async {
          await _pumpKey(t, present: LegendGlyph.values.toSet(), tagged: [(color: Colors.pink, names: 'Ali, Ben, Chong')], scale: scale, size: size);
          expect(t.takeException(), isNull);
          final panel = t.getRect(find.byType(MapLegend));
          expect(panel.width, lessThanOrEqualTo(size.width * 0.45 + 0.5));
          expect(panel.bottom, lessThanOrEqualTo(size.height));
          await t.pumpWidget(const SizedBox());
        });
      }
    }
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
