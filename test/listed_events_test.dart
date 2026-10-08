import 'package:car_meet/core/geo/latlng.dart';
import 'package:car_meet/core/guide/guide.dart';
import 'package:car_meet/core/guide/guide_store.dart';
import 'package:car_meet/core/supabase/supabase_client.dart';
import 'package:car_meet/core/theme/app_icons.dart';
import 'package:car_meet/core/theme/app_theme.dart';
import 'package:car_meet/features/auth/data/auth_repository.dart';
import 'package:car_meet/features/auth/domain/profile.dart';
import 'package:car_meet/features/events/application/event_providers.dart';
import 'package:car_meet/features/events/domain/event.dart';
import 'package:car_meet/features/events/domain/event_detail.dart';
import 'package:car_meet/features/events/presentation/event_details_screen.dart';
import 'package:car_meet/features/expo/door/application/door_providers.dart';
import 'package:car_meet/features/expo/door/domain/door_models.dart';
import 'package:car_meet/features/floorplan/application/floorplan_providers.dart';
import 'package:car_meet/features/floorplan/domain/floorplan.dart';
import 'package:car_meet/features/guides/map_guides.dart';
import 'package:car_meet/features/map/application/map_providers.dart';
import 'package:car_meet/features/organizer/application/organizer_providers.dart';
import 'package:car_meet/features/organizer/domain/organizer_models.dart';
import 'package:car_meet/features/social/application/social_providers.dart';
import 'package:car_meet/features/social/presentation/clubs_events_tab.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

// Listed public events (MIAPEX, MotoGP…): TiTi lists them, TiTi isn't the
// host. The page names the real organiser, links the official page and has
// no host tools.

const _id = 'e1';
const _titi = 'u-titi';

Map<String, dynamic> _row({bool listing = true, String? organiser = 'Sepang International Circuit', String? url = 'https://www.sepangcircuit.com/motogp'}) => {
      'id': _id,
      'organizer_id': _titi,
      'title': 'Petronas Grand Prix of Malaysia',
      'description': 'MotoGP at Sepang.',
      'event_type': 'trackday',
      'cover_url': null,
      'starts_at': DateTime.now().add(const Duration(days: 3)).toUtc().toIso8601String(),
      'ends_at': null,
      'venue_name': 'Sepang International Circuit',
      'lat': 2.7608,
      'lng': 101.7382,
      'max_attendees': null,
      'status': 'active',
      'attendee_count': 12,
      'checkin_count': 0,
      'created_at': '2026-10-09T00:00:00Z',
      'host_is_organizer': true,
      if (listing) 'is_listing': true,
      if (listing) 'organiser_name': organiser,
      if (listing) 'source_url': url,
    };

Event _event({
  bool listing = true,
  String organizer = _titi,
  String? organiserName = 'Sepang International Circuit',
  String? url = 'https://www.sepangcircuit.com/motogp',
  bool live = false,
}) {
  final now = DateTime.now();
  return Event(
    id: _id,
    organizerId: organizer,
    title: 'Petronas Grand Prix of Malaysia 2026, the MotoGP weekend at Sepang',
    type: EventType.trackday,
    startsAt: live ? now.subtract(const Duration(hours: 1)) : now.add(const Duration(days: 3)),
    endsAt: live ? now.add(const Duration(hours: 5)) : null,
    venueName: 'Sepang International Circuit, Jalan Pekeliling 64000 KLIA Selangor',
    lat: 2.7608,
    lng: 101.7382,
    status: EventStatus.active,
    attendeeCount: 12,
    createdAt: DateTime(2026),
    description: 'MotoGP at Sepang.',
    hostIsOrganizer: true,
    isListing: listing,
    organiserName: listing ? organiserName : null,
    sourceUrl: listing ? url : null,
  );
}

EventDetail _detail(Event e) => EventDetail(
      event: e,
      organizer: Profile(id: e.organizerId, username: 'titi', displayName: 'TiTi', createdAt: DateTime(2026)),
      attendeesPreview: const [],
      isAttending: false,
    );

EventHub _hub({bool big = false}) => EventHub.fromMap({
      'checked_in': false,
      'live': false,
      'registration': {'has_form': false, 'required': false, 'questions': 0, 'done': false},
      'levels': big ? 1 : 0,
      'exhibitors': big ? 10 : 0,
      'agenda': 0,
      'stamp_stops': 0,
      'my_stamps': 0,
      'contest': null,
      'my_booths': const [],
      'is_host': false,
      'car': null,
    });

const _host = EventRole(role: 'host', tools: true, hostVerified: true);

Future<void> _pump(WidgetTester t, {required Event event, String me = 'u-me', EventRole role = EventRole.none, EventHub? hub, double scale = 1.0}) async {
  t.view.physicalSize = const Size(1080, 1800 * 3);
  t.view.devicePixelRatio = 3;
  addTearDown(t.view.reset);
  debugEventPageMaps = false;
  addTearDown(() => debugEventPageMaps = true);
  await t.pumpWidget(ProviderScope(
    key: UniqueKey(),
    overrides: [
      currentUserIdProvider.overrideWith((ref) => me),
      currentProfileProvider.overrideWith((ref) async => Profile(id: me, username: 'me', createdAt: DateTime(2026))),
      guideStoreProvider.overrideWithValue(MemoryGuideStore(seen: const [GuideIds.event])),
      mapOriginProvider.overrideWith((ref) => const LatLng(3.15, 101.7)),
      eventDetailProvider(_id).overrideWith((ref) async => _detail(event)),
      eventHubProvider(_id).overrideWith((ref) async => hub ?? _hub()),
      myEventRoleProvider(_id).overrideWith((ref) async => role),
      isOrganizerProvider.overrideWith((ref, id) async => true),
      myDrawStatusProvider(_id).overrideWith((ref) async => const <MyDraw>[]),
      eventDrawsProvider(_id).overrideWith((ref) async => const <LuckyDraw>[]),
      eventCommentsProvider(_id).overrideWith((ref) async => const <EventComment>[]),
      eventMomentsProvider(_id).overrideWith((ref) async => const []),
      postsWhereProvider.overrideWith((ref, key) async => const []),
      myCheckinsProvider.overrideWith((ref) async => const <String>{}),
      eventCheckedInProvider(_id).overrideWith((ref) async => const <Profile>[]),
      floorLevelsProvider(_id).overrideWith((ref) async => const <FloorLevel>[]),
      myEventPositionProvider(_id).overrideWith((ref) async => null),
      isMeetHostProvider(_id).overrideWith((ref) async => role.isHostCircle),
    ],
    child: MaterialApp(
      theme: AppTheme.light,
      builder: (context, app) => MediaQuery(data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)), child: app!),
      home: const EventDetailsScreen(eventId: _id),
    ),
  ));
  await t.pump();
  await t.pump(const Duration(milliseconds: 50));
}

void main() {
  group('model', () {
    test('parses the listing columns from the view', () {
      final e = Event.fromMap(_row());
      expect(e.isListing, isTrue);
      expect(e.organiserName, 'Sepang International Circuit');
      expect(e.sourceUrl, 'https://www.sepangcircuit.com/motogp');
      expect(e.officialPage.toString(), 'https://www.sepangcircuit.com/motogp');
      expect(e.listingHost, 'Sepang International Circuit');
      expect(e.listingLine, 'Public event · by Sepang International Circuit');
    });

    test('a normal event (or an older view without the columns)', () {
      final e = Event.fromMap(_row(listing: false));
      expect(e.isListing, isFalse);
      expect(e.organiserName, isNull);
      expect(e.sourceUrl, isNull);
      expect(e.officialPage, isNull);
    });

    test('no name: "Public event"; only web links open', () {
      final e = Event.fromMap(_row(organiser: '  ', url: 'javascript:alert(1)'));
      expect(e.listingHost, 'Public event');
      expect(e.listingLine, 'Public event');
      expect(e.officialPage, isNull);
      expect(Event.fromMap(_row(organiser: null, url: null)).officialPage, isNull);
    });
  });

  group('lists and map', () {
    test('a listing is a big pin with a PUBLIC badge, whoever listed it', () {
      // TiTi isn't an approved organizer: the listing is still big.
      expect(pinTierOf(Event.fromMap({..._row(), 'host_is_organizer': false})), PinTier.major);
      expect(pinTierOf(Event.fromMap({..._row(listing: false), 'host_is_organizer': false})), PinTier.minor);
      expect(HostBadge.of(_event()), isNotNull);
      final badge = HostBadge.of(_event())!;
      expect(badge.text, 'PUBLIC');
    });

    test("TiTi's tour of a listing: Going and the official page, no host QR", () {
      final k = EventGuideKeys();
      final g = eventGuide(k, attending: false, listing: true, officialPage: true);
      expect(g.steps.map((s) => s.target), [k.rsvp, k.officialPage]);
      expect(g.steps.first.body, "Tap Going so friends see you're there.");
      final live = eventGuide(k, attending: true, live: true, chat: true, listing: true, officialPage: true);
      expect(live.steps.map((s) => s.target), [k.officialPage, k.checkIn, k.chat]);
      final words = [...g.steps, ...live.steps].map((s) => s.body).join(' ');
      expect(words, isNot(contains('QR')));
      expect(words, isNot(contains('host')));
    });
  });

  group('event page', () {
    testWidgets('a listing names the organiser, links the official page', (t) async {
      await _pump(t, event: _event());
      expect(find.text('Public event · by Sepang International Circuit'), findsOneWidget);
      expect(find.text('Listed by TiTi'), findsOneWidget);
      expect(find.text('Official page'), findsOneWidget);
      expect(find.byIcon(AppIcons.arrowSquareOut), findsOneWidget);
      expect(find.textContaining('Organised by'), findsNothing);
      // RSVP reads Going; the type's title stays.
      expect(find.text('Going'), findsOneWidget);
      expect((t.widget<AppBar>(find.byType(AppBar).first).title as Text).data, 'Track day');
      // No verified seal: it's the lister's, not the host's.
      expect(find.byIcon(AppIcons.sealCheck), findsNothing);
    });

    testWidgets('no name: just "Public event"; no link: no button', (t) async {
      await _pump(t, event: _event(organiserName: null, url: null));
      expect(find.text('Public event'), findsOneWidget);
      expect(find.text('Official page'), findsNothing);
    });

    testWidgets('the lister gets no host tools, no QR, no menu', (t) async {
      await _pump(t, event: _event(organizer: 'u-me', live: true), me: 'u-me', role: _host, hub: _hub(big: true));
      // One page, never the big-event tabs.
      expect(find.byKey(const ValueKey('event-tabs')), findsNothing);
      expect(find.byKey(const ValueKey('event-role-switch')), findsNothing);
      expect(find.text('Public event · by Sepang International Circuit'), findsOneWidget);
      // Live: location check-in only.
      expect(find.text("I'm here · check in"), findsOneWidget);
      expect(find.text("Be at the event with location on, then tap I'm here. Earns points."), findsOneWidget);
      expect(find.text('Show check-in QR'), findsNothing);
      expect(find.byIcon(AppIcons.scan), findsNothing);
      expect(find.text('Organizer tools'), findsNothing);
      expect(find.text("Who's here"), findsNothing);
      expect(find.text('Turnout report'), findsNothing);
      expect(find.byIcon(AppIcons.dotsThreeVertical), findsNothing);
      // Members still get directions, share and comments.
      expect(find.text('Directions'), findsOneWidget);
      expect(find.text('Comments (0)'), findsOneWidget);
    });

    testWidgets('a member: report only, no block or end', (t) async {
      await _pump(t, event: _event(live: true));
      await t.tap(find.byIcon(AppIcons.dotsThreeVertical));
      await t.pump();
      await t.pump(const Duration(milliseconds: 400));
      expect(find.text('Report event'), findsOneWidget);
      expect(find.textContaining('Block'), findsNothing);
      expect(find.byKey(const ValueKey('menu-close-event')), findsNothing);
    });

    testWidgets('a normal event is unchanged', (t) async {
      await _pump(t, event: _event(listing: false, organizer: 'u-me', live: true), me: 'u-me', role: _host);
      expect(find.textContaining('Public event'), findsNothing);
      expect(find.text('Official page'), findsNothing);
      expect(find.textContaining('Listed by'), findsNothing);
      expect(find.text('Show check-in QR'), findsOneWidget);
      expect(find.text('Organizer tools'), findsOneWidget);
      expect(find.text('Turnout report'), findsOneWidget);
      expect(find.byIcon(AppIcons.dotsThreeVertical), findsOneWidget);
    });

    testWidgets('a normal event for a member still says Join', (t) async {
      await _pump(t, event: _event(listing: false));
      expect(find.text('Join'), findsOneWidget);
      expect(find.byKey(const ValueKey('listing-host')), findsNothing);
    });

    testWidgets('no overflow at text scale 1.3', (t) async {
      final long = _event(organiserName: 'Sepang International Circuit Sdn Bhd and the Federation Internationale de Motocyclisme', live: true);
      await _pump(t, event: long, scale: 1.3);
      expect(t.takeException(), isNull);
      await _pump(t, event: _event(), scale: 1.3);
      expect(t.takeException(), isNull);
    });
  });
}
