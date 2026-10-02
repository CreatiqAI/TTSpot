import 'package:car_meet/core/theme/app_theme.dart';
import 'package:car_meet/features/events/domain/event.dart';
import 'package:car_meet/features/social/domain/post.dart';
import 'package:car_meet/features/vendors/domain/vendor.dart';
import 'package:car_meet/features/vendors/presentation/widgets/hours_editor.dart';
import 'package:car_meet/features/vendors/presentation/widgets/partner_tabs.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

// ------------------------------------------------------------- fakes ---

final _now = DateTime.now();

const _hours = {
  'mon': {'open': '10:00', 'close': '19:00'},
  'tue': {'open': '10:00', 'close': '19:00'},
  'wed': {'open': '10:00', 'close': '19:00'},
  'thu': {'open': '10:00', 'close': '19:00'},
  'fri': {'open': '10:00', 'close': '22:30'},
  'sat': {'open': '09:00', 'close': '22:30'},
  'sun': null,
};

// No lat/lng (no map), no photos and no logo URL (no network images).
const _vendor = PublicVendor(
  id: 'v-1',
  name: 'Garage 21 Performance',
  type: 'workshop',
  address: 'Lot 12, Jalan Kenari 5, Bandar Puchong Jaya, 47100 Puchong, Selangor',
  phone: '+60 12-345 6789',
  description: 'Dyno tuning, alignment and coilover setups. Walk-ins welcome on weekdays; weekends by appointment.',
  placeId: 'pl-1',
  hoursJson: _hours,
);

const _products = [
  Product(id: 'p1', vendorId: 'v-1', name: 'Semi-slick tyres, set of four, fitted and balanced', active: true, price: 2400),
  Product(id: 'p2', vendorId: 'v-1', name: 'Dyno tune', active: true),
];

Voucher _voucher(String id, {String? productId, int points = 0}) => Voucher(
      id: id,
      title: 'Weekend special $id',
      kind: DiscountKind.percent,
      value: 10,
      minSpend: 0,
      pointsCost: points,
      claimsCount: 0,
      perUserLimit: 1,
      startsAt: _now,
      active: true,
      vendorId: 'v-1',
      productId: productId,
      productName: productId == null ? null : 'Semi-slick tyres',
    );

final _vouchers = [_voucher('a', productId: 'p1'), _voucher('b', points: 150), _voucher('c')];

final _events = [
  Event(
    id: 'e1',
    organizerId: 'u-1',
    title: 'Dyno day at Garage 21',
    type: EventType.meet,
    startsAt: _now.add(const Duration(days: 3)),
    venueName: 'Garage 21, Puchong',
    lat: 3.03,
    lng: 101.62,
    status: EventStatus.active,
    attendeeCount: 12,
    createdAt: _now,
    vendorId: 'v-1',
  ),
];

final _refreshed = <PartnerTab>[];

Widget _app({required double scale, String? initialTab}) => ProviderScope(
      child: MaterialApp(
        theme: AppTheme.current,
        home: Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(context).copyWith(size: const Size(360, 740), textScaler: TextScaler.linear(scale)),
            child: Scaffold(
              body: PartnerPageView(
                vendor: _vendor,
                products: _products,
                vouchers: _vouchers,
                posts: const <FeedPost>[],
                events: _events,
                initialTab: initialTab,
                onMessage: () {},
                onRefresh: (t) async => _refreshed.add(t),
              ),
            ),
          ),
        ),
      ),
    );

/// A 360 x 740 phone with a status bar and a home bar.
Future<void> _pump(WidgetTester tester, {required double scale, required bool dark, String? initialTab}) async {
  tester.view.physicalSize = const Size(1080, 2220);
  tester.view.devicePixelRatio = 3;
  tester.view.padding = const FakeViewPadding(top: 24 * 3, bottom: 16 * 3);
  addTearDown(tester.view.reset);
  AppColors.dark = dark;
  addTearDown(() => AppColors.dark = false);
  _refreshed.clear();
  await tester.pumpWidget(_app(scale: scale, initialTab: initialTab));
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
}

// ------------------------------------------------------------ helpers ---

Finder get _bar => find.byType(TabBar);
Finder _tab(String label) => find.descendant(of: _bar, matching: find.text(label));
int _index(WidgetTester tester) => tester.widget<TabBar>(_bar).controller!.index;

/// A point on the visible part of the page under the pinned tab bar.
Offset _onPage(WidgetTester tester) => Offset(180, (tester.getBottomLeft(_bar).dy + 740) / 2);

Future<void> _swipe(WidgetTester tester, double dx) async {
  await tester.flingFrom(_onPage(tester), Offset(dx, 0), 1500);
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
}

/// Taps a tab, sliding the tab strip first (big text pushes some off-screen).
Future<void> _tapTab(WidgetTester tester, String label) async {
  final x = tester.getCenter(_tab(label)).dx;
  if (x < 24 || x > 336) {
    await tester.drag(find.descendant(of: _bar, matching: find.byType(Scrollable)), Offset(x < 24 ? 300 : -300, 0));
    await tester.pumpAndSettle();
  }
  await tester.tap(_tab(label));
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
}

/// Scrolls the current page until [finder] sits between the tabs and the
/// bottom of the screen.
Future<void> _reveal(WidgetTester tester, Finder finder) async {
  for (var i = 0; i < 30; i++) {
    final top = tester.getBottomLeft(_bar).dy;
    if (finder.evaluate().isNotEmpty) {
      final y = tester.getTopLeft(finder.first).dy;
      if (y >= top && y < 690) return;
      await tester.dragFrom(_onPage(tester), Offset(0, y < top ? 120 : -120));
    } else {
      await tester.dragFrom(_onPage(tester), const Offset(0, -120));
    }
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  }
  fail('Could not bring $finder into view');
}

/// Scrolls the header away until only the bar and the tabs are left.
Future<void> _collapse(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.dragFrom(_onPage(tester), const Offset(0, -300));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  }
}

double _titleOpacity(WidgetTester tester) => tester
    .widget<AnimatedOpacity>(find.ancestor(of: find.descendant(of: find.byType(AppBar), matching: find.text(_vendor.name, skipOffstage: false)), matching: find.byType(AnimatedOpacity)).first)
    .opacity;

Finder _text(String s) => find.text(s, skipOffstage: false);

void main() {
  for (final dark in [false, true]) {
    for (final scale in [1.0, 1.3]) {
      final mode = '${dark ? 'dark' : 'light'} @$scale';

      testWidgets('five tabs with counts; tap, swipe, empty state, collapse ($mode)', (tester) async {
        await _pump(tester, scale: scale, dark: dark);

        // All five tabs, counts as badges (none for Info / empty Posts).
        for (final l in ['Info', 'Products', 'Vouchers', 'Posts', 'Events']) {
          expect(_tab(l), findsOneWidget);
        }
        expect(find.descendant(of: _bar, matching: find.text('3')), findsOneWidget);
        expect(find.descendant(of: _bar, matching: find.text('2')), findsOneWidget);
        expect(find.descendant(of: _bar, matching: find.text('1')), findsOneWidget);
        expect(find.descendant(of: _bar, matching: find.text('0')), findsNothing);

        // Opens on Info; the name only shows in the bar once collapsed.
        expect(_index(tester), PartnerTab.info.index);
        expect(_text('Hours'), findsOneWidget);
        expect(_titleOpacity(tester), 0);

        // The badge follows the label colour: selected vs unselected.
        final idleBadge = tester.widget<Text>(find.descendant(of: _bar, matching: find.text('3'))).style!.color;
        expect(idleBadge, AppColors.textSecondary);

        // Tap Vouchers: its own page.
        await _tapTab(tester, 'Vouchers');
        expect(_index(tester), PartnerTab.vouchers.index);
        expect(_text('See all in Rewards'), findsOneWidget);
        expect(_text('10% off · Weekend special a'), findsOneWidget);
        expect(_text('Hours'), findsNothing);
        expect(tester.widget<Text>(find.descendant(of: _bar, matching: find.text('3'))).style!.color, AppColors.textPrimary);

        // Swipe left: Posts, which is empty.
        await _swipe(tester, -300);
        expect(_index(tester), PartnerTab.posts.index);
        expect(_text('Nothing posted yet.'), findsOneWidget);
        expect(_text('See all in Rewards'), findsNothing);

        // Swipe left again: Events.
        await _swipe(tester, -300);
        expect(_index(tester), PartnerTab.events.index);
        expect(_text('Dyno day at Garage 21'), findsOneWidget);

        // Swipe right twice: back to Vouchers, then Products (grid, no overflow).
        await _swipe(tester, 300);
        await _swipe(tester, 300);
        expect(_index(tester), PartnerTab.vouchers.index);
        await _tapTab(tester, 'Products');
        expect(_text('Dyno tune'), findsOneWidget);
        expect(_text('Ask for price'), findsOneWidget);
        expect(_text('Voucher'), findsOneWidget);

        // Collapse: the bar shows the name, tabs pin right under it, and the
        // page starts below the tabs (not hidden under the bar).
        await _tapTab(tester, 'Vouchers');
        await _collapse(tester);
        expect(_titleOpacity(tester), 1);
        expect(tester.getTopLeft(_bar).dy, moreOrLessEquals(24 + kToolbarHeight, epsilon: 1));
        final firstVoucher = find.text('10% off · Weekend special a');
        expect(firstVoucher, findsOneWidget);
        expect(tester.getTopLeft(firstVoucher).dy, greaterThanOrEqualTo(tester.getBottomLeft(_bar).dy));

        // Info, collapsed: open the week of hours.
        await _tapTab(tester, 'Info');
        final summary = find.text(OpeningHours.fromJson(_hours).summary);
        await _reveal(tester, summary);
        await tester.tap(summary);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.text('Mon'), findsOneWidget);
        expect(find.text('Closed'), findsWidgets);

        // Further down: contact (phone + Message / WhatsApp) and check in.
        await _reveal(tester, find.text('Check in'));
        expect(find.text('Contact'), findsOneWidget);
        expect(find.text('+60 12-345 6789'), findsOneWidget);
        expect(find.text('WhatsApp'), findsWidgets);
      });
    }
  }

  testWidgets('?tab=vouchers opens on Vouchers; a new tab moves the same page', (tester) async {
    await _pump(tester, scale: 1.3, dark: false, initialTab: 'vouchers');
    expect(_index(tester), PartnerTab.vouchers.index);
    expect(_text('See all in Rewards'), findsOneWidget);
    expect(_text('Hours'), findsNothing);

    // Same route reused with ?tab=events.
    await tester.pumpWidget(_app(scale: 1.3, initialTab: 'events'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(_index(tester), PartnerTab.events.index);
    expect(_text('Dyno day at Garage 21'), findsOneWidget);
  });

  testWidgets('unknown ?tab= falls back to Info', (tester) async {
    await _pump(tester, scale: 1.0, dark: true, initialTab: 'nope');
    expect(_index(tester), PartnerTab.info.index);
    expect(_text('Hours'), findsOneWidget);
  });

  testWidgets('pull to refresh asks for that tab', (tester) async {
    await _pump(tester, scale: 1.0, dark: false, initialTab: 'events');
    await tester.fling(find.text('Dyno day at Garage 21'), const Offset(0, 400), 1200);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(_refreshed, [PartnerTab.events]);
  });

  test('parse', () {
    expect(PartnerTab.parse('products'), PartnerTab.products);
    expect(PartnerTab.parse(null), isNull);
    expect(PartnerTab.parse('x'), isNull);
  });
}
