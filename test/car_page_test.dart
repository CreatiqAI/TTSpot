import 'package:car_meet/core/theme/app_theme.dart';
import 'package:car_meet/features/auth/domain/profile.dart';
import 'package:car_meet/features/profile/domain/car.dart';
import 'package:car_meet/features/profile/domain/car_documents.dart';
import 'package:car_meet/features/profile/domain/car_meet.dart';
import 'package:car_meet/features/profile/domain/car_mod.dart';
import 'package:car_meet/features/profile/domain/portrait_style.dart';
import 'package:car_meet/features/profile/presentation/car_page/car_page_model.dart';
import 'package:car_meet/features/profile/presentation/car_page/car_page_view.dart';
import 'package:car_meet/features/profile/presentation/car_page/car_stage.dart';
import 'package:car_meet/features/social/domain/post.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// ------------------------------------------------------------- fakes ---

const _owner = 'u-owner';
const _base = 'https://x.supabase.co/storage/v1/object/public/car-photos/$_owner';
final _today = DateTime.now();
DateTime _days(int n) => DateTime(_today.year, _today.month, _today.day).add(Duration(days: n));

Car _richCar() => Car(
      id: 'c-911',
      ownerId: _owner,
      make: 'Porsche',
      model: '911 Carrera',
      year: 2021,
      color: 'red',
      isDefault: true,
      description: 'Weekend toy. Sepang twice a year, mamak every Thursday.',
      photoUrls: const ['$_base/911_0.jpg', '$_base/911_1.jpg'],
      createdAt: _days(-200),
      specs: '3.0 L twin-turbo · 385 hp · 8-speed PDK · RWD',
      bodyStyle: 'coupe',
      cutoutUrl: '$_base/911_0_cut.png',
      cutoutSource: '$_base/911_0.jpg',
      portraitUrl: '$_base/portraits/c-911/night_city.png',
    );

Car _newCar({String owner = _owner}) => Car(
      id: 'c-myvi',
      ownerId: owner,
      make: 'Perodua',
      model: 'Myvi 1.5 AV',
      year: 2019,
      color: 'white',
      isDefault: true,
      photoUrls: const ['$_base/myvi_0.jpg'],
      createdAt: _days(-3),
      specs: '1.5 L · — · CVT',
    );

CarMod _mod(String id, ModCategory cat, String title, {double? cost, String? shop, String? vendor, bool private = false, bool photo = false, int daysAgo = 30}) => CarMod(
      id: id,
      carId: 'c-911',
      category: cat,
      title: title,
      cost: cost,
      shop: shop,
      vendorId: vendor == null ? null : 'v-1',
      vendorName: vendor,
      doneOn: _days(-daysAgo),
      photoUrls: photo ? ['$_base/mods/$id.jpg'] : const [],
      isPrivate: private,
      createdAt: _days(-daysAgo),
      description: id == 'm1' ? 'Forged monoblocks, 20 inch rear, Michelin PS4S all round.' : null,
    );

CarPortrait _portrait(String style, PortraitStatus status, {bool refunded = false}) => CarPortrait(
      id: 'p-$style',
      carId: 'c-911',
      styleId: style,
      status: status,
      url: status == PortraitStatus.ready ? '$_base/portraits/c-911/$style.png' : null,
      createdAt: _days(-1),
      pointsSpent: 300,
      refunded: refunded,
    );

FeedPost _post(String id, {bool photo = true, PostKind kind = PostKind.post}) => FeedPost(
      post: Post(
        id: id,
        authorId: _owner,
        kind: kind,
        caption: 'Golden hour at Bukit Tinggi with the crew, long caption to wrap',
        photoUrls: photo ? ['https://x.supabase.co/storage/v1/object/public/post-photos/$id.jpg', 'https://x.supabase.co/storage/v1/object/public/post-photos/${id}b.jpg'] : const [],
        coverAspect: 1,
        createdAt: _days(-5),
        likeCount: 3,
        commentCount: 1,
        voteCount: 0,
      ),
      likedByMe: false,
      savedByMe: false,
    );

CarPageData _rich() => CarPageData(
      car: _richCar(),
      mine: true,
      owner: Profile(id: _owner, username: 'testing', createdAt: _days(-400)),
      mods: [
        _mod('m1', ModCategory.wheels, 'Forged 20 inch wheels with a really long name that wraps', cost: 18500, shop: 'Auto Lab', photo: true, daysAgo: 21),
        _mod('m2', ModCategory.exhaust, 'Titanium exhaust', cost: 24000, vendor: 'Garage 21 Performance Exhaust Specialists', daysAgo: 60),
        _mod('m3', ModCategory.body, 'Full-front PPF', cost: 6500, shop: 'Detail Haus', private: true, daysAgo: 400),
        _mod('m4', ModCategory.audio, 'Focal speakers', daysAgo: 90),
      ],
      documents: CarDocuments(
        carId: 'c-911',
        roadTaxExpiry: _days(72),
        insuranceExpiry: _days(20),
        insurer: 'Etiqa',
        policyNo: 'V1234567',
        ncdPct: 55,
        sumInsured: 450000,
        puspakomDue: _days(-12),
        serviceDueKm: 45000,
        note: 'Spare key in the drawer.',
      ),
      portraits: [
        _portrait('race_poster', PortraitStatus.pending),
        _portrait('night_city', PortraitStatus.ready),
        _portrait('golden_hour', PortraitStatus.ready),
        _portrait('film', PortraitStatus.failed, refunded: true),
      ],
      portraitsEnabled: true,
      posts: [_post('p1'), _post('p2', photo: false), _post('p3', kind: PostKind.spotted), _post('p4')],
      meets: [
        CarMeet(eventId: 'e1', title: 'TTDI Thursday', startsAt: _days(-10), venue: 'Plaza TTDI', checkedIn: true),
        CarMeet(eventId: 'e2', title: 'Sepang track day', startsAt: _days(-120), checkedIn: false),
      ],
      bayIndex: 0,
    );

CarPageData _fresh() => CarPageData(
      car: _newCar(),
      mine: true,
      mods: const [],
      portraits: const [],
      portraitsEnabled: true,
      posts: const [],
      meets: const [],
    );

CarPageData _visitor() => CarPageData(
      car: _newCar(owner: 'u-other'),
      mine: false,
      owner: Profile(id: 'u-other', username: 'titi_onboard1', createdAt: _days(-30)),
      mods: const [],
      posts: const [],
      meets: const [],
    );

// -------------------------------------------------------------- host ---

final _calls = <String>[];

CarPageActions _actions({bool owner = true}) => CarPageActions(
      back: () => _calls.add('back'),
      share: (m) => _calls.add('share:${m?.kind.name}'),
      more: owner ? (m) => _calls.add('more:${m?.kind.name}') : null,
      openMedia: (media, i) => _calls.add('media:$i/${media.length}'),
      addMod: () => _calls.add('addMod'),
      openMod: (m) => _calls.add('mod:${m.id}'),
      modPhotos: (m) => _calls.add('photos:${m.id}'),
      openPartner: (id) => _calls.add('partner:$id'),
      postAboutIt: () => _calls.add('post'),
      openPapers: () => _calls.add('papers'),
      paint: () => _calls.add('paint'),
      dismissPromo: () => _calls.add('dismiss'),
      messageOwner: () => _calls.add('message'),
      openOwner: () => _calls.add('owner'),
      openPost: (id) => _calls.add('openPost:$id'),
      openEvent: (id) => _calls.add('event:$id'),
    );

// Every URL draws a bundled picture: no network in tests.
ImageProvider _image(String url) => const AssetImage('assets/portrait_samples/showroom.webp');

/// A 390 x 844 iPhone (notch and home bar) at [scale] text size.
Future<void> _pump(WidgetTester tester, CarPageData data, {required double scale, required bool dark, CarPageActions? actions}) async {
  tester.view.physicalSize = const Size(1170, 2532);
  tester.view.devicePixelRatio = 3;
  tester.view.padding = const FakeViewPadding(top: 47 * 3, bottom: 34 * 3);
  addTearDown(tester.view.reset);
  AppColors.dark = dark;
  addTearDown(() => AppColors.dark = false);
  _calls.clear();
  await tester.pumpWidget(MaterialApp(
    theme: AppTheme.current,
    home: Builder(
      builder: (context) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
        child: CarPageView(data: data, actions: actions ?? _actions(), imageFor: _image),
      ),
    ),
  ));
  await tester.pump(const Duration(milliseconds: 400));
}

/// Scrolls to the bottom and back, failing on any layout error (overflow
/// stripes throw in tests).
Future<void> _sweep(WidgetTester tester) async {
  final scroll = find.byType(CustomScrollView);
  for (var i = 0; i < 8; i++) {
    await tester.drag(scroll, const Offset(0, -350));
    await tester.pump(const Duration(milliseconds: 120));
    expect(tester.takeException(), isNull);
  }
  for (var i = 0; i < 10; i++) {
    await tester.drag(scroll, const Offset(0, 400));
    await tester.pump(const Duration(milliseconds: 120));
    expect(tester.takeException(), isNull);
  }
}

/// The page's own vertical scrollable (not the strip or the posts grid).
Finder get _page => find.byWidgetPredicate((w) => w is Scrollable && w.axisDirection == AxisDirection.down).first;

/// Scrolls [finder] into view (slivers below the fold aren't built yet).
Future<void> _reveal(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(finder, 150, scrollable: _page, maxScrolls: 60);
  await tester.pump(const Duration(milliseconds: 100));
}

Finder _tab(String label) => find.descendant(of: find.byKey(const ValueKey('car-tabs')), matching: find.text(label));

Future<void> _tapTab(WidgetTester tester, String label) async {
  await _reveal(tester, _tab(label));
  await tester.tap(_tab(label));
  await tester.pump(const Duration(milliseconds: 250));
}

/// Brings [finder] to the middle of the screen (the bottom bar covers the
/// last ~100 px) and taps it.
Future<void> _tap(WidgetTester tester, Finder finder) async {
  await _reveal(tester, finder);
  await Scrollable.ensureVisible(tester.element(finder), alignment: 0.5);
  await tester.pump(const Duration(milliseconds: 100));
  await tester.tap(finder);
  await tester.pump(const Duration(milliseconds: 100));
}

Future<void> _toTop(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.drag(find.byType(CustomScrollView), const Offset(0, 400));
    await tester.pump(const Duration(milliseconds: 60));
  }
}

void main() {
  for (final dark in [false, true]) {
    for (final scale in [1.0, 1.3]) {
      final mode = '${dark ? 'dark' : 'light'} @$scale';

      testWidgets('owner, rich car ($mode): strip, spec sheet, build list + history, papers rings, posts grid', (tester) async {
        await _pump(tester, _rich(), scale: scale, dark: dark);
        expect(tester.takeException(), isNull);

        // Cut-out first, then two photos and two finished portraits (the
        // pending and failed ones show as news, not in the strip).
        expect(find.byType(CarMediaStrip), findsOneWidget);
        expect(find.bySemanticsLabel('Show the car in the bay'), findsOneWidget);
        expect(find.bySemanticsLabel('Show photo 2'), findsOneWidget);
        expect(find.bySemanticsLabel('Show the Night city portrait'), findsOneWidget);
        expect(find.bySemanticsLabel('Show the Golden hour portrait'), findsOneWidget);
        expect(find.text('IN THE BAY'), findsOneWidget);
        await tester.tap(find.bySemanticsLabel('Show the Night city portrait'));
        await tester.pump(const Duration(milliseconds: 400));
        expect(find.text('PORTRAIT · NIGHT CITY'), findsOneWidget);
        await tester.tap(find.bySemanticsLabel('Show photo 2'));
        await tester.pump(const Duration(milliseconds: 400));
        expect(find.text('PHOTO 2 OF 2'), findsOneWidget);

        // Painting / failed news for the owner.
        await _reveal(tester, find.text('Painting your 911 Carrera…'));
        expect(find.textContaining('didn\'t come out'), findsOneWidget);

        // Identity: kicker, colour, today's car, four specs + body → sheet.
        expect(find.text('PORSCHE · 2021'), findsOneWidget);
        expect(find.text('Red'), findsOneWidget);
        expect(find.text('TODAY\'S CAR'), findsOneWidget);
        await _reveal(tester, find.text('SPEC SHEET'));
        await _reveal(tester, find.text('Coupe'));
        expect(find.text('Gearbox'), findsOneWidget);
        await _reveal(tester, find.text('Spent'));
        expect(find.text('RM 49k'), findsOneWidget);
        // Portraits exist: no promo.
        expect(find.text('MAKE IT LOOK PRO'), findsNothing);

        // Build: codes, owner prices, private note, add.
        await _tapTab(tester, 'Build');
        expect(find.text('WHL'), findsOneWidget);
        expect(find.text('RM 18,500'), findsOneWidget);
        expect(find.text('Garage 21 Performance Exhaust Specialists'), findsOneWidget);
        await _reveal(tester, find.text('Prices are only visible to you.'));
        expect(find.text('+ Add a mod'), findsOneWidget);
        await _sweep(tester);

        // History: mods, meets, parked.
        await _tap(tester, find.text('History'));
        await _reveal(tester, find.text('TTDI Thursday'));
        expect(find.text('Checked in · Plaza TTDI'), findsOneWidget);
        await _reveal(tester, find.text('Parked in the garage'));
        await _sweep(tester);

        // Papers: rings, soon / overdue tags, mileage service, insurance details.
        await _tapTab(tester, 'Papers');
        await _reveal(tester, find.text('Road tax'));
        await _reveal(tester, find.text('Renew soon'));
        await _reveal(tester, find.textContaining('Etiqa · Policy V1234567'));
        await _reveal(tester, find.text('Overdue'));
        await _reveal(tester, find.text('At 45,000 km'));
        await _reveal(tester, find.text('Spare key in the drawer.'));
        await _sweep(tester);

        // Posts: the grid.
        await _tapTab(tester, 'Posts');
        await _reveal(tester, find.bySemanticsLabel(RegExp('Golden hour at Bukit Tinggi')).first);
        await _sweep(tester);

        // Bottom bar.
        await tester.tap(find.text('Add a mod').last);
        await tester.tap(find.text('Post about it').last);
        expect(_calls, containsAllInOrder(['addMod', 'post']));
        expect(find.text('Message owner'), findsNothing);
        expect(find.text('In the garage of'), findsNothing);
        expect(tester.takeException(), isNull);
      });

      testWidgets('owner, new car ($mode): one framed photo, no strip, promo card, empty tabs', (tester) async {
        await _pump(tester, _fresh(), scale: scale, dark: dark);
        expect(tester.takeException(), isNull);

        expect(find.byType(CarMediaStrip), findsNothing);
        expect(find.text('YOUR PHOTO · TAP TO VIEW'), findsOneWidget);
        // Real specs only: the "—" is dropped, two chips, no sheet.
        expect(find.text('1.5 L'), findsOneWidget);
        expect(find.text('CVT'), findsOneWidget);
        expect(find.text('—'), findsNothing);
        expect(find.text('SPEC SHEET'), findsNothing);

        await _reveal(tester, find.text('MAKE IT LOOK PRO'));
        await _tap(tester, find.text('Paint my Myvi 1.5 AV · 300 points'));
        await _tap(tester, find.bySemanticsLabel('Hide this'));
        expect(_calls, containsAllInOrder(['paint', 'dismiss']));

        await _tapTab(tester, 'Build');
        await _reveal(tester, find.text('STOCK AND PROUD?'));
        expect(find.text('History'), findsNothing);
        await _sweep(tester);
        await _tapTab(tester, 'Papers');
        await _reveal(tester, find.text('NEVER MISS A RENEWAL'));
        await _tap(tester, find.text('Add road tax date'));
        expect(_calls.last, 'papers');
        await _sweep(tester);
        await _tapTab(tester, 'Posts');
        await _reveal(tester, find.text('SHOW IT OFF'));
        await _sweep(tester);

        // The stage opens the viewer.
        await _toTop(tester);
        await tester.tapAt(const Offset(195, 220));
        expect(_calls.last, 'media:0/1');
        expect(tester.takeException(), isNull);
      });

      testWidgets('visitor, nothing logged ($mode): no tabs, Message owner, owner row', (tester) async {
        await _pump(tester, _visitor(), scale: scale, dark: dark, actions: _actions(owner: false));
        expect(tester.takeException(), isNull);

        await _reveal(tester, find.text('In the garage of'));
        expect(find.text('Build'), findsNothing);
        expect(find.text('Papers'), findsNothing);
        expect(find.text('Posts'), findsOneWidget); // the stat label only
        expect(find.text('Spent'), findsNothing);
        await _toTop(tester);
        expect(find.text('MAKE IT LOOK PRO'), findsNothing);
        expect(find.text('PHOTO · TAP TO VIEW'), findsOneWidget);
        expect(find.bySemanticsLabel('More'), findsNothing);
        await _sweep(tester);

        await _tap(tester, find.text('@titi_onboard1'));
        await tester.tap(find.text('Message owner'));
        await tester.tap(find.bySemanticsLabel('Share this car'));
        expect(_calls, containsAllInOrder(['owner', 'message', 'share:photo']));
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('visitor with mods and posts sees Build and Posts, no prices', (tester) async {
    final rich = _rich();
    final data = CarPageData(
      car: rich.car,
      mine: false,
      owner: rich.owner,
      mods: [for (final m in rich.mods!.where((m) => !m.isPrivate)) _mod(m.id, m.category, m.title, shop: m.shop, daysAgo: 10)],
      posts: rich.posts,
      meets: rich.meets,
    );
    await _pump(tester, data, scale: 1.3, dark: false, actions: _actions(owner: false));
    // Visitors see the portrait the car wears, not the owner's others.
    expect(find.bySemanticsLabel('Show the Night city portrait'), findsOneWidget);
    expect(find.bySemanticsLabel('Show the Golden hour portrait'), findsNothing);
    expect(find.bySemanticsLabel('More'), findsNothing);
    await _reveal(tester, _tab('Build'));
    expect(_tab('Posts'), findsOneWidget);
    expect(_tab('Papers'), findsNothing);
    await _reveal(tester, find.text('WHL'));
    expect(find.text('Prices are only visible to you.'), findsNothing);
    expect(find.text('+ Add a mod'), findsNothing);
    expect(find.textContaining('RM '), findsNothing);
    await _sweep(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the pinned tab bar follows a theme flip on a live page', (tester) async {
    await _pump(tester, _fresh(), scale: 1.0, dark: false);
    await _reveal(tester, _tab('Build'));
    Color? tabsColour() => (tester.widget<Container>(find.byKey(const ValueKey('car-tabs'))).decoration as BoxDecoration?)?.color;
    expect(tabsColour(), AppColors.bg);
    // The app flips AppColors and rebuilds the same page (no new route).
    AppColors.dark = true;
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.current,
      home: Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.noScaling),
          child: CarPageView(data: _fresh(), actions: _actions(), imageFor: _image),
        ),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 100));
    expect(tabsColour(), AppColors.bg);
    expect(AppColors.bg, const Color(0xFF0F1115));
    expect(tester.takeException(), isNull);
  });

  test('history: newest first, and the day it was parked sits under that day\'s mods', () {
    final car = _newCar();
    final sameDay = CarMod(
      id: 'm-same',
      carId: car.id,
      category: ModCategory.exhaust,
      title: 'Exhaust on day one',
      doneOn: DateTime(car.createdAt.year, car.createdAt.month, car.createdAt.day),
      photoUrls: const [],
      isPrivate: false,
      createdAt: car.createdAt,
    );
    final items = carHistory(car, mods: [sameDay], meets: [CarMeet(eventId: 'e', title: 'Night meet', startsAt: _days(-1), checkedIn: true)], showPrices: false);
    expect(items.map((e) => e.kind), [CarHistoryKind.meet, CarHistoryKind.mod, CarHistoryKind.parked]);
    expect(items[1].sub, '');
  });

  test('specs: labels, blanks dropped, body style added once', () {
    final specs = carSpecs(_richCar());
    expect(specs.map((s) => s.label), ['Engine', 'Power', 'Gearbox', 'Drive', 'Body']);
    expect(carSpecs(_newCar()).map((s) => s.value), ['1.5 L', 'CVT']);
  });

  test('media: cut-out, photos, then portraits; opens on the cut-out', () {
    final car = _richCar();
    final media = carMediaFor(car, portraits: _rich().portraits);
    expect(media.map((m) => m.kind), [CarMediaKind.cutout, CarMediaKind.photo, CarMediaKind.photo, CarMediaKind.portrait, CarMediaKind.portrait]);
    expect(initialMediaIndex(car, media), 0);
    // A stale cut-out (made from another cover) is left out.
    final stale = Car(id: car.id, ownerId: car.ownerId, make: car.make, model: car.model, photoUrls: car.photoUrls, createdAt: car.createdAt, cutoutUrl: car.cutoutUrl, cutoutSource: 'old.jpg', portraitUrl: car.portraitUrl);
    final m2 = carMediaFor(stale);
    expect(m2.first.kind, CarMediaKind.photo);
    // No cut-out: it opens on the portrait the car wears.
    expect(m2[initialMediaIndex(stale, m2)].style?.id, 'night_city');
  });

  test('meets: merged per event, checked in wins, future and cancelled left out', () {
    Map<String, dynamic> row(String id, int days, {String status = 'active'}) => {
          'event_id': id,
          'events': {'id': id, 'title': 'Meet $id', 'starts_at': _days(days).toUtc().toIso8601String(), 'venue_name': 'V', 'status': status},
        };
    final meets = CarMeet.merge(
      attended: [row('a', -5), row('b', -1), row('f', 3), row('x', -2, status: 'cancelled'), {'event_id': 'hidden', 'events': null}],
      checkins: [row('a', -5)],
    );
    expect(meets.map((m) => m.eventId), ['b', 'a']);
    expect(meets.last.checkedIn, isTrue);
    expect(meets.first.checkedIn, isFalse);
  });
}
