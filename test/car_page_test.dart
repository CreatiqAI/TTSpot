import 'package:car_meet/core/theme/app_theme.dart';
import 'package:car_meet/features/auth/domain/profile.dart';
import 'package:car_meet/features/profile/domain/car.dart';
import 'package:car_meet/features/profile/domain/car_documents.dart';
import 'package:car_meet/features/profile/domain/car_meet.dart';
import 'package:car_meet/features/profile/domain/car_mod.dart';
import 'package:car_meet/features/profile/domain/car_toy.dart';
import 'package:car_meet/features/profile/domain/portrait_style.dart';
import 'package:car_meet/features/profile/presentation/car_page/car_page_model.dart';
import 'package:car_meet/features/profile/presentation/car_page/car_page_view.dart';
import 'package:car_meet/features/profile/presentation/garage/garage_images.dart';
import 'package:car_meet/features/profile/presentation/widgets/toy_car_image.dart';
import 'package:car_meet/features/social/domain/post.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// The car page (0.3.56 redesign): the toy in the dark studio, then the
// summary and the sections, for the owner and a visitor, with and without a
// toy, with 0, 1 and 6 photos, at 100 % and 130 % text, light and dark. Any
// overflow or layout error throws.

// ------------------------------------------------------------- fakes ---

const _owner = 'u-owner';
const _base = 'https://x.supabase.co/storage/v1/object/public/car-photos/$_owner';
final _today = DateTime.now();
DateTime _days(int n) => DateTime(_today.year, _today.month, _today.day).add(Duration(days: n));

Car _car({
  String owner = _owner,
  String model = '911 Carrera',
  int photos = 6,
  String? color = 'red',
  String? toyStatus = 'ready',
  bool toy = true,
  String? toyColor = 'red',
  bool today = true,
  String? portrait,
  String? description = 'Weekend toy. Sepang twice a year, mamak every Thursday.',
}) =>
    Car(
      id: 'c-911',
      ownerId: owner,
      make: 'Porsche',
      model: model,
      year: 2021,
      color: color,
      isDefault: today,
      description: description,
      photoUrls: [for (var i = 0; i < photos; i++) '$_base/911_$i.jpg'],
      createdAt: _days(-200),
      specs: '3.0 L twin-turbo · 385 hp · 8-speed PDK · RWD',
      bodyStyle: 'coupe',
      portraitUrl: portrait,
      toyUrl: toy ? '$_base/toys/c-911/1_toy.png' : null,
      toyStatus: toyStatus,
      toySource: photos > 0 ? '$_base/911_0.jpg' : null,
      toyColor: toy ? toyColor : null,
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
        photoUrls: photo ? ['https://x.supabase.co/storage/v1/object/public/post-photos/$id.jpg'] : const [],
        coverAspect: 1,
        createdAt: _days(-5),
        likeCount: 3,
        commentCount: 1,
        voteCount: 0,
      ),
      likedByMe: false,
      savedByMe: false,
    );

final _profile = Profile(id: _owner, username: 'keith_gt', createdAt: _days(-400));

CarPageData _rich({Car? car}) => CarPageData(
      car: car ?? _car(portrait: '$_base/portraits/c-911/night_city.png'),
      mine: true,
      owner: _profile,
      mods: [
        _mod('m1', ModCategory.wheels, 'Forged 20 inch wheels with a really long name that wraps', cost: 18500, shop: 'Auto Lab', photo: true, daysAgo: 21),
        _mod('m2', ModCategory.exhaust, 'Titanium exhaust', cost: 24000, vendor: 'Garage 21 Performance Exhaust Specialists', daysAgo: 60),
        _mod('m3', ModCategory.body, 'Full-front PPF', cost: 6500, shop: 'Detail Haus', private: true, daysAgo: 400),
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
      ),
      portraits: [
        _portrait('race_poster', PortraitStatus.pending),
        _portrait('night_city', PortraitStatus.ready),
        _portrait('golden_hour', PortraitStatus.ready),
        _portrait('film', PortraitStatus.failed, refunded: true),
      ],
      portraitsEnabled: true,
      posts: [_post('p1'), _post('p2', photo: false), _post('p3', kind: PostKind.spotted)],
      meets: [
        CarMeet(eventId: 'e1', title: 'TTDI Thursday', startsAt: _days(-10), venue: 'Plaza TTDI', checkedIn: true),
        CarMeet(eventId: 'e2', title: 'Sepang track day', startsAt: _days(-120), checkedIn: false),
      ],
    );

/// A car just parked: one photo, its first toy still being made, nothing logged.
CarPageData _fresh() => CarPageData(
      car: _car(model: 'Myvi 1.5 AV', photos: 1, color: 'white', toy: false, toyStatus: 'pending', today: false, description: null),
      mine: true,
      mods: const [],
      documents: null,
      portraits: const [],
      portraitsEnabled: true,
      posts: const [],
      meets: const [],
    );

/// Someone else's car: a toy, no photos, nothing logged.
CarPageData _visitor({int photos = 0}) => CarPageData(
      car: _car(owner: 'u-other', photos: photos, description: null),
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
      share: () => _calls.add('share'),
      more: () => _calls.add(owner ? 'more' : 'visitor-more'),
      editCar: () => _calls.add('edit'),
      makeToday: () => _calls.add('today'),
      retryToy: owner ? () => _calls.add('retry') : null,
      openPhoto: (urls, i) => _calls.add('photo:$i/${urls.length}'),
      addMod: () => _calls.add('addMod'),
      openMod: (m) => _calls.add('mod:${m.id}'),
      modPhotos: (m) => _calls.add('photos:${m.id}'),
      openPartner: (id) => _calls.add('partner:$id'),
      postAboutIt: () => _calls.add('post'),
      openPapers: () => _calls.add('papers'),
      newPortrait: () => _calls.add('paint'),
      openPortrait: (p, all) => _calls.add('portrait:${p.style?.id}/${all.length}'),
      dismissPromo: () => _calls.add('dismiss'),
      messageOwner: () => _calls.add('message'),
      openOwner: () => _calls.add('owner'),
      openPost: (id) => _calls.add('openPost:$id'),
      openEvent: (id) => _calls.add('event:$id'),
    );

// Every URL draws a bundled picture: no network in tests.
ImageProvider _image(String url) => url.endsWith('_toy.png') ? const AssetImage('assets/cars/sedan.png') : const AssetImage('assets/portrait_samples/showroom.webp');

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
  // The toy lands (450 ms) and its light sweep crosses (700 ms).
  await tester.pump(const Duration(milliseconds: 500));
  await tester.pump(const Duration(milliseconds: 800));
}

/// The page's own vertical scrollable.
Finder get _page => find.byWidgetPredicate((w) => w is Scrollable && w.axisDirection == AxisDirection.down).first;

/// Scrolls to the bottom and back, failing on any layout error (overflow
/// stripes throw in tests).
Future<void> _sweep(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.drag(_page, const Offset(0, -350), warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 120));
    expect(tester.takeException(), isNull);
  }
  for (var i = 0; i < 12; i++) {
    await tester.drag(_page, const Offset(0, 400), warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 120));
    expect(tester.takeException(), isNull);
  }
}

/// Scrolls [finder] into view (slivers below the fold aren't built yet).
Future<void> _reveal(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(finder, 150, scrollable: _page, maxScrolls: 80);
  await tester.pump(const Duration(milliseconds: 100));
}

/// Brings [finder] to the middle of the screen (clear of the top bar) and taps it.
Future<void> _tap(WidgetTester tester, Finder finder) async {
  await _reveal(tester, finder);
  await Scrollable.ensureVisible(tester.element(finder), alignment: 0.5);
  await tester.pump(const Duration(milliseconds: 100));
  await tester.tap(finder);
  await tester.pump(const Duration(milliseconds: 100));
}

Future<void> _toTop(WidgetTester tester) async {
  for (var i = 0; i < 14; i++) {
    await tester.drag(_page, const Offset(0, 400), warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 60));
  }
}

void main() {
  setUp(() {
    garageImageFor = _image;
  });

  for (final dark in [false, true]) {
    for (final scale in [1.0, 1.3]) {
      final mode = '${dark ? 'dark' : 'light'} @$scale';

      testWidgets('owner, toy and 6 photos ($mode): studio, summary, album, mods, papers, portraits, posts', (tester) async {
        await _pump(tester, _rich(), scale: scale, dark: dark);
        expect(tester.takeException(), isNull);

        // The studio: make · year, the model, today's car, the toy, its paint.
        expect(find.byKey(const ValueKey('car-hero')), findsOneWidget);
        expect(find.text('PORSCHE · 2021'), findsOneWidget);
        expect(find.descendant(of: find.byKey(const ValueKey('car-hero')), matching: find.text('911 Carrera')), findsOneWidget);
        expect(find.text('TODAY\'S CAR'), findsOneWidget);
        expect(ToyCarImage.stateFor(_rich().car, mine: true), 'toy');
        expect(find.byType(ToyCarImage), findsOneWidget);
        expect(find.text('Red paint'), findsOneWidget);

        // Summary: specs, the description, the numbers, the buttons.
        await _reveal(tester, find.text('8-speed PDK'));
        expect(find.text('Coupe'), findsOneWidget);
        await _reveal(tester, find.text('Spent'));
        expect(find.text('RM 49k'), findsOneWidget);
        expect(find.text('In their garage'), findsNothing);
        expect(find.text('Message owner'), findsNothing);
        await _tap(tester, find.text('Edit car'));
        await _tap(tester, find.text('Post about it')); // today's car already
        await _tap(tester, find.bySemanticsLabel('More'));
        expect(_calls, ['edit', 'post', 'more']);

        // Album: six photos three to a row, the first marked as the cover.
        await _reveal(tester, find.textContaining('Album'));
        expect(find.text('Album  6'), findsOneWidget);
        // The section's action sits at the right edge.
        expect(tester.getRect(find.text('Edit').first).right, greaterThan(390 - 40));
        await _reveal(tester, find.bySemanticsLabel('Photo 6 of 6'));
        expect(find.text('COVER'), findsOneWidget);
        await _tap(tester, find.bySemanticsLabel('Photo 3 of 6'));
        expect(_calls.last, 'photo:2/6');
        final first = tester.getRect(find.bySemanticsLabel('Photo 1 of 6'));
        final third = tester.getRect(find.bySemanticsLabel('Photo 3 of 6'));
        final fourth = tester.getRect(find.bySemanticsLabel('Photo 4 of 6'));
        expect(third.top, first.top);
        expect(fourth.top, greaterThan(first.bottom));
        expect(first.width, closeTo(first.height, 0.5));

        // Mods with owner prices, the private lock and the timeline.
        await _reveal(tester, find.text('Mods  3'));
        await _reveal(tester, find.text('WHL'));
        expect(find.text('RM 18,500'), findsOneWidget);
        await _reveal(tester, find.text('Prices are only visible to you.'));
        await _tap(tester, find.text('+ Add a mod'));
        expect(_calls.last, 'addMod');
        await _tap(tester, find.text('History'));
        await _reveal(tester, find.text('TTDI Thursday'));
        await _tap(tester, find.text('TTDI Thursday'));
        expect(_calls.last, 'event:e1');
        await _tap(tester, find.text('List'));

        // Papers: owner only.
        await _reveal(tester, find.text('Papers'));
        await _reveal(tester, find.text('Renew soon'));
        await _reveal(tester, find.textContaining('Etiqa · Policy V1234567'));
        await _reveal(tester, find.text('At 45,000 km'));

        // Portraits: painting / failed news, two finished, the one on the car marked.
        await _reveal(tester, find.text('Portraits  2'));
        await _reveal(tester, find.text('Painting your 911 Carrera…'));
        await _reveal(tester, find.bySemanticsLabel('Night city portrait, on the car'));
        expect(find.text('ON THE CAR'), findsOneWidget);
        await _tap(tester, find.bySemanticsLabel('Golden hour portrait'));
        expect(_calls.last, 'portrait:golden_hour/2');
        expect(find.text('MAKE IT LOOK PRO'), findsNothing);

        // Posts.
        await _reveal(tester, find.text('Posts  3'));
        await _reveal(tester, find.bySemanticsLabel(RegExp('Golden hour at Bukit Tinggi')).first);

        await _sweep(tester);
        // The top bar: Back and Share over the studio.
        await _toTop(tester);
        await tester.tap(find.bySemanticsLabel('Share'));
        await tester.tap(find.bySemanticsLabel('Back'));
        expect(_calls.sublist(_calls.length - 2), ['share', 'back']);
        expect(tester.takeException(), isNull);
      });

      testWidgets('owner, new car ($mode): toy on its way, 1 photo, empty sections, promo', (tester) async {
        final d = _fresh();
        await _pump(tester, d, scale: scale, dark: dark);
        expect(tester.takeException(), isNull);
        expect(ToyCarImage.stateFor(d.car, mine: true), 'pending');
        expect(find.text('Building your toy car…'), findsOneWidget);
        expect(find.text('White paint'), findsOneWidget);
        expect(find.text('TODAY\'S CAR'), findsNothing);

        await _tap(tester, find.text('Make today\'s car'));
        expect(_calls.last, 'today');

        // One photo: one wide picture, no cover tag.
        await _reveal(tester, find.text('Album  1'));
        final photo = tester.getRect(find.bySemanticsLabel('Photo of the car'));
        expect(photo.width, closeTo(390 - 32, 0.5));
        expect(find.text('COVER'), findsNothing);
        expect(find.text('Edit'), findsOneWidget);

        await _reveal(tester, find.text('STOCK AND PROUD?'));
        await _tap(tester, find.text('Log a mod'));
        expect(_calls.last, 'addMod');
        await _reveal(tester, find.text('NEVER MISS A RENEWAL'));
        await _reveal(tester, find.text('MAKE IT LOOK PRO'));
        await _tap(tester, find.text('Paint my Myvi 1.5 AV · 300 points'));
        expect(_calls.last, 'paint');
        await _tap(tester, find.bySemanticsLabel('Hide this'));
        expect(_calls.last, 'dismiss');
        await _reveal(tester, find.text('SHOW IT OFF'));
        await _sweep(tester);
        expect(tester.takeException(), isNull);
      });

      testWidgets('owner, no photos ($mode): body-type art, no "building", add photos', (tester) async {
        final d = CarPageData(
          car: _car(photos: 0, toy: false, toyStatus: null, color: null),
          mine: true,
          mods: const [],
          portraits: const [],
          posts: const [],
          meets: const [],
        );
        await _pump(tester, d, scale: scale, dark: dark);
        expect(ToyCarImage.stateFor(d.car, mine: true), 'fallback');
        expect(find.text('Building your toy car…'), findsNothing);
        expect(find.textContaining(' paint'), findsNothing);
        await _reveal(tester, find.text('Album'));
        await _tap(tester, find.text('+ Add photos of your car'));
        expect(_calls.last, 'edit');
        // Portraits are off: no section.
        expect(find.textContaining('Portraits'), findsNothing);
        await _sweep(tester);
        expect(tester.takeException(), isNull);
      });

      testWidgets('visitor, toy and no photos ($mode): read-only, Message owner, report in More', (tester) async {
        await _pump(tester, _visitor(), scale: scale, dark: dark, actions: _actions(owner: false));
        expect(tester.takeException(), isNull);
        expect(find.text('DAILY'), findsOneWidget);
        expect(find.text('Red paint'), findsOneWidget);
        expect(ToyCarImage.stateFor(_visitor().car, mine: false), 'toy');

        await _reveal(tester, find.text('@titi_onboard1'));
        expect(find.text('In their garage'), findsOneWidget);
        expect(find.text('Spent'), findsNothing);
        expect(find.text('Edit car'), findsNothing);
        // Nothing to show: no album, mods, papers, portraits or posts sections.
        expect(find.textContaining('Album'), findsNothing);
        expect(find.textContaining('Mods  '), findsNothing);
        expect(find.text('Papers'), findsNothing);
        expect(find.textContaining('Portraits'), findsNothing);
        await _tap(tester, find.text('@titi_onboard1'));
        await _tap(tester, find.text('Message owner'));
        await _tap(tester, find.bySemanticsLabel('More'));
        expect(_calls, ['owner', 'message', 'visitor-more']);
        await _sweep(tester);
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('visitor with photos, mods and posts: album, mods without prices, the portrait the car wears', (tester) async {
    final rich = _rich();
    final data = CarPageData(
      car: _car(owner: 'u-other', photos: 2, portrait: '$_base/portraits/c-911/night_city.png'),
      mine: false,
      owner: rich.owner,
      mods: [for (final m in rich.mods!.where((m) => !m.isPrivate)) _mod(m.id, m.category, m.title, shop: m.shop, daysAgo: 10)],
      posts: rich.posts,
      meets: rich.meets,
    );
    await _pump(tester, data, scale: 1.3, dark: false, actions: _actions(owner: false));
    await _reveal(tester, find.text('Album  2'));
    expect(find.text('Edit'), findsNothing);
    final a = tester.getRect(find.bySemanticsLabel('Photo 1 of 2'));
    final b = tester.getRect(find.bySemanticsLabel('Photo 2 of 2'));
    expect(a.top, b.top);
    expect(find.text('COVER'), findsNothing);
    await _reveal(tester, find.text('WHL'));
    expect(find.text('Prices are only visible to you.'), findsNothing);
    expect(find.text('+ Add a mod'), findsNothing);
    expect(find.textContaining('RM '), findsNothing);
    expect(find.text('Papers'), findsNothing);
    await _reveal(tester, find.text('Portraits  1'));
    await _tap(tester, find.bySemanticsLabel('Night city portrait, on the car'));
    expect(_calls.last, 'portrait:night_city/1');
    await _reveal(tester, find.text('Posts  3'));
    await _sweep(tester);
    expect(tester.takeException(), isNull);
  });

  group('paint and repaint', () {
    for (final scale in [1.0, 1.3]) {
      testWidgets('repainting: the old toy dimmed under the pill, "Repainting in Blue…" (@$scale)', (tester) async {
        final car = _car(color: 'blue', toyColor: 'red', toyStatus: 'pending');
        expect(car.toyRepainting, isTrue);
        await _pump(tester, _rich(car: car), scale: scale, dark: false);
        expect(ToyCarImage.stateFor(car, mine: true), 'repainting');
        expect(find.text(kRepaintingCaption), findsOneWidget);
        expect(find.text('Repainting in Blue…'), findsOneWidget);
        expect(find.text('Try again'), findsNothing);
        expect(tester.takeException(), isNull);
      });

      testWidgets('a repaint the cap holds back says when it goes on (@$scale)', (tester) async {
        final car = _car(color: 'blue', toyColor: 'red', toyStatus: 'ready');
        expect(car.toyPaintWaiting, isTrue);
        final next = DateTime.now().add(const Duration(hours: 3));
        final d = _rich(car: car);
        final data = CarPageData(
          car: car,
          mine: true,
          mods: d.mods,
          portraits: const [],
          posts: const [],
          meets: const [],
          toyQuota: ToyQuota(limit: 3, used: 3, nextAt: next),
        );
        await _pump(tester, data, scale: scale, dark: true);
        expect(find.text('Blue paint is next'), findsOneWidget);
        expect(find.textContaining('3 toy renders a day per car'), findsOneWidget);
        expect(find.text(kRepaintingCaption), findsNothing);
        expect(tester.takeException(), isNull);
      });

      testWidgets('a repaint that failed offers Try again (@$scale)', (tester) async {
        final car = _car(color: 'blue', toyColor: 'red', toyStatus: 'failed');
        await _pump(tester, _rich(car: car), scale: scale, dark: false);
        expect(find.text('The Blue repaint didn\'t work'), findsOneWidget);
        expect(find.textContaining('The new paint didn\'t take'), findsOneWidget);
        await tester.tap(find.text('Try again'));
        expect(_calls.last, 'retry');
        // Visitors see the toy they see: still red, no notes.
        await _pump(tester, CarPageData(car: _car(owner: 'u-other', color: 'blue', toyColor: 'red', toyStatus: 'failed'), mine: false), scale: scale, dark: false, actions: _actions(owner: false));
        expect(find.text('Red paint'), findsOneWidget);
        expect(find.text('Try again'), findsNothing);
        expect(tester.takeException(), isNull);
      });
    }
  });

  test('album layout: one wide, two and four in pairs, otherwise threes', () {
    expect(albumLayout(1), (columns: 1, aspect: 16 / 10));
    expect(albumLayout(2).columns, 2);
    expect(albumLayout(3).columns, 3);
    expect(albumLayout(4).columns, 2);
    expect(albumLayout(5).columns, 3);
    expect(albumLayout(6).columns, 3);
  });

  test('portraits: the owner\'s ready ones (the one worn marked), visitors only the one worn', () {
    final car = _car(portrait: '$_base/portraits/c-911/night_city.png');
    final mine = carPortraitsFor(car, portraits: _rich().portraits);
    expect(mine.map((p) => p.style?.id), ['night_city', 'golden_hour']);
    expect(mine.first.wearing, isTrue);
    final theirs = carPortraitsFor(car);
    expect(theirs, hasLength(1));
    expect(theirs.single.style?.id, 'night_city');
    expect(theirs.single.portrait, isNull);
  });

  test('history: newest first, and the day it was parked sits under that day\'s mods', () {
    final car = _car(photos: 1);
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
    final specs = carSpecs(_car());
    expect(specs.map((s) => s.label), ['Engine', 'Power', 'Gearbox', 'Drive', 'Body']);
    final blank = Car(id: 'x', ownerId: 'u', make: 'Perodua', model: 'Myvi', photoUrls: const [], createdAt: _today, specs: '1.5 L · — · CVT');
    expect(carSpecs(blank).map((s) => s.value), ['1.5 L', 'CVT']);
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
