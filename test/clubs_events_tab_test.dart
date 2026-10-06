import 'package:car_meet/core/geo/latlng.dart';
import 'package:car_meet/core/supabase/supabase_client.dart';
import 'package:car_meet/core/theme/app_theme.dart';
import 'package:car_meet/features/events/domain/event.dart';
import 'package:car_meet/features/map/application/map_list_providers.dart';
import 'package:car_meet/features/map/application/map_providers.dart';
import 'package:car_meet/features/social/data/community_repository.dart';
import 'package:car_meet/features/social/domain/club.dart';
import 'package:car_meet/features/social/presentation/clubs_events_tab.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// Home's Clubs & Events tab (0.3.55): the filters, the order (official clubs
// first; live events, then day by day, nearest first), Join / Request, the
// empty states, at text x1.0 and x1.3, light and dark, on a 360 dp phone.

const _kl = LatLng(3.1478, 101.6953);

Club _club(String id, String name, {bool official = false, int members = 1, String policy = 'public', String? state = 'Kuala Lumpur'}) => Club(
      id: id,
      name: name,
      handle: id.replaceAll('-', '_'),
      homeState: state,
      ownerId: 'owner-$id',
      createdAt: DateTime(2026, 9, 1),
      memberCount: members,
      tier: official ? 'official' : 'underground',
      joinPolicy: policy,
    );

Event _event(String id, String title, {required DateTime starts, double lat = 3.15, double lng = 101.70, String? clubId, String? clubName, String? clubTier, String? vendorId, String? vendorName, bool organizer = false, int going = 3, String venue = 'Togeya Cafe, Bukit Jalil'}) =>
    Event(
      id: id,
      organizerId: 'host-$id',
      title: title,
      type: EventType.meet,
      startsAt: starts,
      venueName: venue,
      lat: lat,
      lng: lng,
      status: EventStatus.active,
      attendeeCount: going,
      createdAt: DateTime(2026, 9, 1),
      clubId: clubId,
      clubName: clubName,
      clubTier: clubTier,
      vendorId: vendorId,
      vendorName: vendorName,
      hostIsOrganizer: organizer,
    );

// Long names on purpose: nothing may overflow at x1.3 on 360 dp.
final _official = _club('c-official', 'TT Spot Crew Official Club of Kuala Lumpur', official: true, members: 2);
final _bigUnderground = _club('c-big', 'Myvi Owners Klang Valley Underground Society', members: 80);
final _private = _club('c-private', 'Night Owls', members: 6, policy: 'private', state: null);
final _mine = _club('c-mine', 'Weekend Wanderers', members: 12);

List<Event> _events(DateTime now) => [
      _event('e-later', 'Sunday breakfast run to Genting Highlands and back', starts: now.add(const Duration(days: 9)), vendorId: 'v1', vendorName: 'Grip Tyres & Wheels Bukit Jalil'),
      _event('e-live', 'TT at Togeya', starts: now.subtract(const Duration(hours: 1))),
      _event('e-tomorrow-far', 'Far meet', starts: DateTime(now.year, now.month, now.day + 1, 20), lat: 1.49, lng: 103.74, organizer: true),
      _event('e-tomorrow-near', 'Near meet', starts: DateTime(now.year, now.month, now.day + 1, 22), clubId: 'c-official', clubName: _official.name, clubTier: 'official'),
    ];

/// Clubs in memory: joins and requests change it.
class _FakeCommunity extends CommunityRepository {
  _FakeCommunity({this.mine = const []}) : super(SupabaseClient('http://localhost', 'test-key', authOptions: const AuthClientOptions(autoRefreshToken: false)));

  List<Club> mine;
  final joined = <String>[];
  final requested = <String, String?>{};

  @override
  Future<List<Club>> myClubs(String me) async => mine;

  @override
  Future<bool> joinClub(String clubId) async {
    joined.add(clubId);
    mine = [...mine, _club(clubId, 'joined')];
    return true;
  }

  @override
  Future<void> requestClubJoin(String clubId, String? message) async => requested[clubId] = message;

  @override
  Future<String?> myClubRequest(String clubId) async => requested.containsKey(clubId) ? 'pending' : null;
}

Future<_FakeCommunity> _pump(
  WidgetTester t, {
  List<Club>? clubs,
  List<Event>? events,
  double scale = 1.0,
  bool dark = false,
  LatLng? me = _kl,
}) async {
  AppColors.dark = dark;
  t.view.physicalSize = const Size(360 * 3, 760 * 3);
  t.view.devicePixelRatio = 3;
  addTearDown(t.view.reset);
  final repo = _FakeCommunity(mine: [_mine]);
  final router = GoRouter(routes: [
    GoRoute(path: '/', builder: (_, _) => const Scaffold(body: ClubsEventsTab())),
    GoRoute(path: '/club/apply', builder: (_, _) => const Scaffold(body: Text('club apply'))),
    GoRoute(path: '/club/:id', builder: (_, s) => Scaffold(body: Text('club ${s.pathParameters['id']}'))),
    GoRoute(path: '/event/:id', builder: (_, s) => Scaffold(body: Text('event ${s.pathParameters['id']}'))),
    GoRoute(path: '/create-event', builder: (_, _) => const Scaffold(body: Text('plan a meet'))),
  ]);
  await t.pumpWidget(ProviderScope(
    overrides: [
      currentUserIdProvider.overrideWithValue('me'),
      communityRepositoryProvider.overrideWithValue(repo),
      allClubsProvider.overrideWith((ref) async => clubs ?? [_private, _bigUnderground, _mine, _official]),
      allUpcomingMeetsProvider.overrideWith((ref) async => events ?? _events(DateTime.now())),
      meetHostNamesProvider.overrideWith((ref) async => {'host-e-live': 'Keith Lim', 'host-e-tomorrow-far': 'Johor Night Runners Organizer'}),
      userLocationProvider.overrideWith((ref) async => me),
    ],
    child: MaterialApp.router(
      theme: AppTheme.current,
      routerConfig: router,
      builder: (context, child) => MediaQuery(data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)), child: child!),
    ),
  ));
  await t.pumpAndSettle();
  return repo;
}

Future<void> _filter(WidgetTester t, ClubsEventsFilter f) async {
  await t.tap(find.byKey(Key('clubs-filter-${f.name}')));
  await t.pumpAndSettle();
}

double _y(WidgetTester t, Finder f) => t.getTopLeft(f).dy;

void main() {
  tearDown(() => AppColors.dark = false);

  group('order', () {
    test('official clubs first, then the biggest', () {
      final sorted = sortClubsForList([_private, _bigUnderground, _mine, _official]);
      expect(sorted.map((c) => c.id), ['c-official', 'c-big', 'c-mine', 'c-private']);
    });

    test('live first, then day by day, nearest first inside a day when I am located', () {
      final now = DateTime.now();
      final sorted = sortEventsForList(_events(now), origin: _kl, now: now);
      expect(sorted.map((e) => e.id), ['e-live', 'e-tomorrow-near', 'e-tomorrow-far', 'e-later']);
    });

    test('without my location: soonest first inside a day', () {
      final now = DateTime.now();
      final sorted = sortEventsForList(_events(now), now: now);
      expect(sorted.map((e) => e.id), ['e-live', 'e-tomorrow-far', 'e-tomorrow-near', 'e-later']);
    });

    test('over and cancelled meets drop out', () {
      final now = DateTime.now();
      final over = _event('e-over', 'Over', starts: now.subtract(const Duration(hours: 9)));
      expect(sortEventsForList([over, ..._events(now)], now: now).map((e) => e.id), isNot(contains('e-over')));
      expect(eventGroupOf(_events(now)[1], now), 'LIVE NOW');
    });
  });

  for (final dark in const [false, true]) {
    for (final scale in const [1.0, 1.3]) {
      final tag = '${dark ? 'dark' : 'light'}, x$scale';

      testWidgets('All: clubs (official first) then events, no overflow ($tag)', (t) async {
        await _pump(t, scale: scale, dark: dark);
        final bar = find.byKey(const Key('clubs-filter-bar'));
        for (final label in ['All', 'Official', 'Underground', 'Events']) {
          expect(find.descendant(of: bar, matching: find.text(label)), findsOneWidget);
        }
        expect(find.text('CLUBS · 4'), findsOneWidget);
        // Official above the bigger underground club.
        expect(_y(t, find.byKey(const Key('club-row-c-official'))), lessThan(_y(t, find.byKey(const Key('club-row-c-big')))));
        expect(find.text('OFFICIAL'), findsWidgets);
        // Join (public), Request (private), Joined (mine).
        expect(find.byKey(const Key('club-join-c-big')), findsOneWidget);
        expect(find.byKey(const Key('club-request-c-private')), findsOneWidget);
        expect(find.byKey(const Key('club-joined-c-mine')), findsOneWidget);
        await t.scrollUntilVisible(find.byKey(const Key('event-row-e-later')), 200, scrollable: find.byType(Scrollable).first);
        expect(find.text('EVENTS · 4'), findsOneWidget);
        expect(t.takeException(), isNull);
      });

      testWidgets('Official clubs only ($tag)', (t) async {
        await _pump(t, scale: scale, dark: dark);
        await _filter(t, ClubsEventsFilter.official);
        expect(find.byKey(const Key('club-row-c-official')), findsOneWidget);
        expect(find.byKey(const Key('club-row-c-big')), findsNothing);
        expect(find.byKey(const Key('event-row-e-live')), findsNothing);
        expect(t.takeException(), isNull);
      });

      testWidgets('Underground clubs only, biggest first ($tag)', (t) async {
        await _pump(t, scale: scale, dark: dark);
        await _filter(t, ClubsEventsFilter.underground);
        expect(find.byKey(const Key('club-row-c-official')), findsNothing);
        expect(find.byKey(const Key('club-row-c-big')), findsOneWidget);
        expect(find.byKey(const Key('club-row-c-private')), findsOneWidget);
        expect(_y(t, find.byKey(const Key('club-row-c-big'))), lessThan(_y(t, find.byKey(const Key('club-row-c-mine')))));
        expect(find.byKey(const Key('event-row-e-live')), findsNothing);
        expect(t.takeException(), isNull);
      });

      testWidgets('Events only: live first, host badges like the map ($tag)', (t) async {
        await _pump(t, scale: scale, dark: dark);
        await _filter(t, ClubsEventsFilter.events);
        expect(find.byKey(const Key('club-row-c-official')), findsNothing);
        expect(find.text('LIVE NOW'), findsOneWidget);
        expect(find.textContaining('Live now', findRichText: true), findsOneWidget);
        expect(_y(t, find.byKey(const Key('event-row-e-live'))), lessThan(_y(t, find.byKey(const Key('event-row-e-tomorrow-near')))));
        // Same day: the nearer one first.
        expect(_y(t, find.byKey(const Key('event-row-e-tomorrow-near'))), lessThan(_y(t, find.byKey(const Key('event-row-e-tomorrow-far')))));
        expect(find.text('OFFICIAL'), findsOneWidget);
        expect(find.text('ORGANIZER'), findsOneWidget);
        await t.scrollUntilVisible(find.byKey(const Key('event-row-e-later')), 200, scrollable: find.byType(Scrollable).first);
        expect(find.text('PARTNER'), findsOneWidget);
        expect(t.takeException(), isNull);
      });

      testWidgets('Empty: nothing at all, then each filter ($tag)', (t) async {
        await _pump(t, scale: scale, dark: dark, clubs: const [], events: const []);
        expect(find.text('No clubs or meets yet'), findsOneWidget);
        await _filter(t, ClubsEventsFilter.official);
        expect(find.text('No official clubs yet'), findsOneWidget);
        await _filter(t, ClubsEventsFilter.underground);
        expect(find.text('No underground clubs yet'), findsOneWidget);
        await _filter(t, ClubsEventsFilter.events);
        expect(find.text('No meets coming up'), findsOneWidget);
        expect(t.takeException(), isNull);
      });
    }
  }

  // 0.3.56: the filters wrapped onto 2 rows (only "Events" on the second).
  // Now one segmented row that fits, whatever the phone and text size.
  group('filter bar: always one row', () {
    // The whole tab at the sizes we design for; the bar alone (below) on
    // smaller phones and huge text.
    for (final (width, scale, alone) in const [(360.0, 1.0, false), (360.0, 1.3, false), (430.0, 1.0, false), (320.0, 1.3, true), (360.0, 2.0, true), (320.0, 2.0, true)]) {
      testWidgets('${width.toInt()} dp at text x$scale${alone ? ' (bar alone)' : ''}', (t) async {
        var picked = ClubsEventsFilter.all;
        if (alone) {
          t.view.physicalSize = Size(width * 3, 760 * 3);
          t.view.devicePixelRatio = 3;
          addTearDown(t.view.reset);
          await t.pumpWidget(MaterialApp(
            theme: AppTheme.current,
            builder: (context, child) => MediaQuery(data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)), child: child!),
            home: Scaffold(
              body: StatefulBuilder(
                builder: (context, setState) => Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
                  child: Align(alignment: Alignment.topLeft, child: ClubsEventsFilterBar(selected: picked, onChanged: (f) => setState(() => picked = f))),
                ),
              ),
            ),
          ));
          await t.pumpAndSettle();
        } else {
          await _pump(t, scale: scale);
          t.view.physicalSize = Size(width * 3, 760 * 3);
          await t.pumpAndSettle();
        }
        expect(t.takeException(), isNull);
        final bar = t.getRect(find.byKey(const Key('clubs-filter-bar')));
        final segments = [for (final f in ClubsEventsFilter.values) t.getRect(find.byKey(Key('clubs-filter-${f.name}')))];
        // One row: every segment on the same line, left to right, inside the bar.
        for (final r in segments) {
          expect((r.center.dy - segments.first.center.dy).abs(), lessThan(0.5));
          expect(r.left, greaterThanOrEqualTo(bar.left - 0.5));
          expect(r.right, lessThanOrEqualTo(bar.right + 0.5));
        }
        for (var i = 1; i < segments.length; i++) {
          expect(segments[i].left, greaterThanOrEqualTo(segments[i - 1].right - 0.5));
        }
        // Inside the 16 dp gutters; at normal sizes it fills the width.
        expect(bar.left, greaterThanOrEqualTo(16 - 0.5));
        expect(bar.right, lessThanOrEqualTo(width - 16 + 0.5));
        if (scale <= 1.3 && width >= 360) expect(bar.width, closeTo(width - 32, 0.5));
        // Labels are never cut or wrapped.
        for (final label in ['All', 'Official', 'Underground', 'Events']) {
          final text = t.widget<Text>(find.descendant(of: find.byKey(const Key('clubs-filter-bar')), matching: find.text(label)));
          expect(text.maxLines, 1);
          expect(text.overflow, isNot(TextOverflow.ellipsis));
        }
        // Still picks.
        await _filter(t, ClubsEventsFilter.events);
        if (alone) {
          expect(picked, ClubsEventsFilter.events);
        } else {
          expect(find.byKey(const Key('club-row-c-official')), findsNothing);
        }
        expect(t.takeException(), isNull);
      });
    }

    test('layout: room to spare is shared, tight phones lose padding, then scale', () {
      // Roomy: every segment gets its label + 24 + an equal share.
      final roomy = ClubsEventsFilterBar.layout([20, 60, 90, 50], 400);
      expect(roomy.scale, 1);
      expect(roomy.widths.fold(0.0, (a, b) => a + b), closeTo(400 - 2 * ClubsEventsFilterBar.inset, 1e-9));
      expect(roomy.widths[1] - roomy.widths[0], closeTo(40, 1e-9));
      // Tight: padding shrinks between 6 and 12 a side, still exactly fits.
      final tight = ClubsEventsFilterBar.layout([30, 80, 120, 70], 360);
      expect(tight.scale, 1);
      expect(tight.widths.fold(0.0, (a, b) => a + b), closeTo(360 - 2 * ClubsEventsFilterBar.inset, 1e-9));
      // Too big even at 6 a side: drawn smaller.
      final huge = ClubsEventsFilterBar.layout([60, 150, 220, 120], 320);
      expect(huge.scale, lessThan(1));
      expect(huge.widths.fold(0.0, (a, b) => a + b) * huge.scale, closeTo(320 - 2 * ClubsEventsFilterBar.inset, 1e-9));
    });
  });

  testWidgets('All with clubs but no meets: one line, not an empty page', (t) async {
    await _pump(t, events: const []);
    expect(find.byKey(const Key('club-row-c-official')), findsOneWidget);
    await t.scrollUntilVisible(find.text('No meets coming up.'), 200, scrollable: find.byType(Scrollable).first);
    expect(find.text('Plan one'), findsOneWidget);
  });

  testWidgets('All shows 5 clubs, See all shows the rest', (t) async {
    final many = [for (var i = 0; i < 8; i++) _club('c-$i', 'Club $i', members: 20 - i)];
    await _pump(t, clubs: many, events: const []);
    expect(find.byKey(const Key('club-row-c-4')), findsOneWidget);
    expect(find.byKey(const Key('club-row-c-5')), findsNothing);
    await t.tap(find.byKey(const Key('clubs-see-all')));
    await t.pumpAndSettle();
    await t.scrollUntilVisible(find.byKey(const Key('club-row-c-7')), 200, scrollable: find.byType(Scrollable).first);
    expect(find.byKey(const Key('club-row-c-7')), findsOneWidget);
  });

  testWidgets('Join: a public club in one tap, then Joined', (t) async {
    final repo = await _pump(t);
    await t.tap(find.byKey(const Key('club-join-c-big')));
    await t.pumpAndSettle();
    expect(repo.joined, ['c-big']);
    expect(find.textContaining("You're in. Welcome to"), findsOneWidget);
    expect(find.byKey(const Key('club-joined-c-big')), findsOneWidget);
  });

  testWidgets('Request: a private club asks, then Requested', (t) async {
    final repo = await _pump(t);
    await t.tap(find.byKey(const Key('club-request-c-private')));
    await t.pumpAndSettle();
    expect(find.text('Join Night Owls'), findsOneWidget);
    await t.enterText(find.byType(TextField).last, 'Civic daily');
    await t.tap(find.text('Send request'));
    await t.pumpAndSettle();
    expect(repo.requested, {'c-private': 'Civic daily'});
    expect(repo.joined, isEmpty);
    expect(find.byKey(const Key('club-requested-c-private')), findsOneWidget);
  });

  testWidgets('Search narrows clubs and meets; no match offers Clear search', (t) async {
    await _pump(t);
    await t.enterText(find.byKey(const Key('clubs-search')), 'night');
    await t.pumpAndSettle();
    expect(find.byKey(const Key('club-row-c-private')), findsOneWidget);
    expect(find.byKey(const Key('club-row-c-official')), findsNothing);
    expect(find.byKey(const Key('event-row-e-live')), findsNothing);
    await t.enterText(find.byKey(const Key('clubs-search')), 'zzz');
    await t.pumpAndSettle();
    expect(find.text('Nothing matches "zzz"'), findsOneWidget);
    await t.tap(find.text('Clear search'));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('club-row-c-official')), findsOneWidget);
  });

  testWidgets('Distances only when I am located', (t) async {
    await _pump(t, me: null);
    await _filter(t, ClubsEventsFilter.events);
    expect(find.textContaining(' km', findRichText: true), findsNothing);
  });

  testWidgets('Located: each meet says how far', (t) async {
    await _pump(t);
    await _filter(t, ClubsEventsFilter.events);
    expect(find.textContaining(' km', findRichText: true), findsWidgets);
  });

  testWidgets('Tap a club: its page', (t) async {
    await _pump(t);
    await t.tap(find.byKey(const Key('club-row-c-official')));
    await t.pumpAndSettle();
    expect(find.text('club c-official'), findsOneWidget);
  });
}
