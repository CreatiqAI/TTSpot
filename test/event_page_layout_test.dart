import 'dart:async';

import 'package:car_meet/core/geo/latlng.dart';
import 'package:car_meet/core/guide/guide.dart';
import 'package:car_meet/core/guide/guide_store.dart';
import 'package:car_meet/core/router/app_router.dart' show Routes;
import 'package:car_meet/core/router/pop_or_home.dart';
import 'package:car_meet/core/supabase/supabase_client.dart';
import 'package:car_meet/core/theme/app_theme.dart';
import 'package:car_meet/core/utils/dates.dart';
import 'package:car_meet/features/auth/data/auth_repository.dart';
import 'package:car_meet/features/auth/domain/profile.dart';
import 'package:car_meet/features/events/application/event_providers.dart';
import 'package:car_meet/features/events/application/event_view.dart';
import 'package:car_meet/features/events/domain/event.dart';
import 'package:car_meet/features/events/domain/event_detail.dart';
import 'package:car_meet/features/events/domain/event_kind.dart';
import 'package:car_meet/features/events/presentation/event_details_screen.dart';
import 'package:car_meet/features/expo/contest/application/contest_providers.dart';
import 'package:car_meet/features/expo/dashboard/application/dashboard_providers.dart';
import 'package:car_meet/features/expo/dashboard/domain/dashboard.dart';
import 'package:car_meet/features/expo/door/application/door_providers.dart';
import 'package:car_meet/features/expo/door/domain/door_models.dart';
import 'package:car_meet/features/expo/exhibitors/application/exhibitors_providers.dart';
import 'package:car_meet/features/expo/exhibitors/domain/exhibitor.dart';
import 'package:car_meet/features/expo/schedule/application/agenda_providers.dart';
import 'package:car_meet/features/expo/schedule/domain/agenda.dart';
import 'package:car_meet/features/expo/stamps/application/stamps_providers.dart';
import 'package:car_meet/features/expo/stamps/domain/stamps_models.dart';
import 'package:car_meet/features/floorplan/application/floorplan_providers.dart';
import 'package:car_meet/features/floorplan/domain/floorplan.dart';
import 'package:car_meet/features/guides/map_guides.dart';
import 'package:car_meet/features/map/application/map_providers.dart';
import 'package:car_meet/features/organizer/application/organizer_providers.dart';
import 'package:car_meet/features/organizer/domain/organizer_models.dart';
import 'package:car_meet/features/organizer/presentation/organizer_groups.dart';
import 'package:car_meet/features/organizer/presentation/organizer_tools_screen.dart';
import 'package:car_meet/features/social/application/social_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

// The event page redesign for big, official events: the proper title, the
// module tabs, the role switch, the organizer groups and the back fallback.

const _id = 'e1';

Event _event({
  EventType type = EventType.meet,
  DateTime? start,
  DateTime? end,
  String? clubTier,
  bool instant = false,
  String organizer = 'u-host',
  String title = 'MIAPEX 2025',
}) =>
    Event(
      id: _id,
      organizerId: organizer,
      title: title,
      type: type,
      startsAt: start ?? DateTime.now().add(const Duration(days: 2)),
      endsAt: end,
      venueName: 'Malaysia International Trade and Exhibition Centre, Halls 1 to 4',
      lat: 3.17,
      lng: 101.66,
      status: EventStatus.active,
      attendeeCount: 0,
      createdAt: DateTime(2026),
      clubTier: clubTier,
      isInstant: instant,
      description: 'Malaysia International Automotive Parts Expo. Parts, tyres, audio, wraps and more.',
    );

EventDetail _detail(Event e) => EventDetail(
      event: e,
      organizer: Profile(id: e.organizerId, username: 'bigboss_with_a_long_handle', displayName: 'Big Boss Events Sdn Bhd', createdAt: DateTime(2026)),
      attendeesPreview: const [],
      isAttending: false,
    );

EventHub _hub({bool big = true, bool checkedIn = false, List<Map<String, String>> booths = const []}) => EventHub.fromMap({
      'checked_in': checkedIn,
      'entry_no': checkedIn ? 427 : null,
      'pass_code': checkedIn ? 'abc123' : null,
      'live': false,
      'registration': {'has_form': false, 'required': false, 'questions': 0, 'done': false},
      'levels': big ? 1 : 0,
      'exhibitors': big ? 170 : 0,
      'agenda': big ? 4 : 0,
      'stamp_stops': big ? 3 : 0,
      'my_stamps': 0,
      'stamp_goal': null,
      'contest': big ? {'id': 'k1', 'title': "People's Choice"} : null,
      'my_booths': booths,
      'is_host': false,
      'car': null,
    });

const _host = EventRole(role: 'host', tools: true, hostVerified: true);
const _crew = EventRole(role: 'crew', tools: true, hostVerified: true);

/// A 360 wide phone, tall enough that the tabs' content is built (slivers
/// build lazily).
void _phone(WidgetTester t, {double height = 1800}) {
  t.view.physicalSize = Size(1080, height * 3);
  t.view.devicePixelRatio = 3;
  addTearDown(t.view.reset);
}

Future<void> _pump(
  WidgetTester t, {
  required Event event,
  EventHub? hub,
  EventRole role = EventRole.none,
  double scale = 1.0,
  double height = 1800,
  List<Exhibitor> exhibitors = const [],
}) async {
  _phone(t, height: height);
  debugEventPageMaps = false;
  addTearDown(() => debugEventPageMaps = true);
  await t.pumpWidget(ProviderScope(
    key: UniqueKey(),
    overrides: [
      currentUserIdProvider.overrideWith((ref) => 'u-me'),
      currentProfileProvider.overrideWith((ref) async => Profile(id: 'u-me', username: 'me', createdAt: DateTime(2026))),
      guideStoreProvider.overrideWithValue(MemoryGuideStore(seen: const [GuideIds.event])),
      mapOriginProvider.overrideWith((ref) => const LatLng(3.15, 101.7)),
      eventDetailProvider(_id).overrideWith((ref) async => _detail(event)),
      eventHubProvider(_id).overrideWith((ref) async => hub),
      myEventRoleProvider(_id).overrideWith((ref) async => role),
      isOrganizerProvider.overrideWith((ref, id) async => false),
      myDrawStatusProvider(_id).overrideWith((ref) async => const <MyDraw>[]),
      eventDrawsProvider(_id).overrideWith((ref) async => const <LuckyDraw>[]),
      eventCommentsProvider(_id).overrideWith((ref) async => const <EventComment>[]),
      eventMomentsProvider(_id).overrideWith((ref) async => const []),
      postsWhereProvider.overrideWith((ref, key) async => const []),
      myCheckinsProvider.overrideWith((ref) async => const <String>{}),
      eventCheckedInProvider(_id).overrideWith((ref) async => const <Profile>[]),
      floorLevelsProvider(_id).overrideWith((ref) async => const <FloorLevel>[]),
      myEventPositionProvider(_id).overrideWith((ref) async => null),
      isMeetHostProvider(_id).overrideWith((ref) async => false),
      eventExhibitorsProvider(_id).overrideWith((ref) async => exhibitors),
      eventAgendaProvider(_id).overrideWith((ref) async => const <AgendaItem>[]),
      myStampsProvider(_id).overrideWith((ref) async => const StampCard()),
      currentContestIdProvider(_id).overrideWith((ref) async => null),
      // The dashboard stays loading: the numbers have their own tests.
      expoDashboardProvider(_id).overrideWith((ref) => Completer<ExpoDashboard>().future),
      exhibitorLeadsProvider.overrideWith((ref, id) async => const <Lead>[]),
      myStaffBoothsProvider(_id).overrideWith((ref) async => const <StaffBooth>[]),
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

String _appBarTitle(WidgetTester t) {
  final bar = t.widget<AppBar>(find.byType(AppBar).first);
  return (bar.title as Text).data ?? '';
}

Future<void> _tapTab(WidgetTester t, String id) async {
  final tab = find.byKey(ValueKey('tab-$id'));
  await t.ensureVisible(tab);
  await t.pump();
  await t.tap(tab);
  await t.pump();
  await t.pump(const Duration(milliseconds: 400));
}

void main() {
  group('title and kind', () {
    test('by kind', () {
      expect(eventPageTitle(_event(), big: true), 'Event');
      expect(eventKindOf(_event(), big: true).badge, 'Expo');
      expect(eventPageTitle(_event(clubTier: 'official')), 'Official event');
      expect(eventPageTitle(_event(type: EventType.official)), 'Official event');
      expect(eventPageTitle(_event(type: EventType.tt)), 'TT session');
      expect(eventPageTitle(_event(instant: true)), 'TT session');
      expect(eventPageTitle(_event()), 'Meet');
      expect(eventPageTitle(_event(type: EventType.convoy)), 'Convoy');
      expect(eventPageTitle(_event(type: EventType.trackday)), 'Track day');
      expect(eventPageTitle(_event(type: EventType.charity)), 'Charity drive');
      // Big wins over official: it gets the module layout.
      expect(eventPageTitle(_event(clubTier: 'official'), big: true), 'Event');
    });

    test('multi-day dates read as a range', () {
      final now = DateTime(2026, 10, 7, 9);
      expect(formatEventSpan(DateTime(2026, 10, 7, 14, 25), DateTime(2026, 10, 31, 23), now: now), '7–31 Oct · from 2:25 PM');
      expect(formatEventSpan(DateTime(2026, 10, 28, 10), DateTime(2026, 11, 2, 18), now: now), '28 Oct – 2 Nov · from 10:00 AM');
      expect(formatEventSpan(DateTime(2027, 3, 1, 10), DateTime(2027, 3, 3, 18), now: now), '1–3 Mar 2027 · from 10:00 AM');
      expect(formatEventSpan(DateTime(2026, 12, 30, 10), DateTime(2027, 1, 2, 18), now: now), '30 Dec 2026 – 2 Jan 2027 · from 10:00 AM');
      // One day, or a night out past midnight: the usual line.
      expect(formatEventSpan(DateTime(2026, 10, 7, 14, 25), DateTime(2026, 10, 7, 22), now: now), 'Today · 2:25 PM');
      expect(formatEventSpan(DateTime(2026, 10, 7, 21), DateTime(2026, 10, 8, 2), now: now), 'Today · 9:00 PM');
      expect(formatEventSpan(DateTime(2026, 10, 8, 21), null, now: now), 'Tomorrow · 9:00 PM');
    });

    testWidgets('app bar title per kind', (t) async {
      await _pump(t, event: _event(), hub: _hub(big: false));
      expect(_appBarTitle(t), 'Meet');
      await _pump(t, event: _event(type: EventType.convoy), hub: _hub(big: false));
      expect(_appBarTitle(t), 'Convoy');
      await _pump(t, event: _event(clubTier: 'official'), hub: _hub(big: false));
      expect(_appBarTitle(t), 'Official event');
      expect(find.text('Official event'), findsNWidgets(2)); // title + kind badge
      await _pump(t, event: _event(), hub: _hub());
      expect(_appBarTitle(t), 'Event');
      expect(find.text('Expo'), findsOneWidget);
    });
  });

  group('layout', () {
    testWidgets('big event: module tabs, only those with data', (t) async {
      await _pump(t, event: _event(), hub: _hub());
      expect(find.byKey(const ValueKey('event-tabs')), findsOneWidget);
      for (final m in EventModule.values) {
        expect(find.byKey(ValueKey('tab-${m.name}')), findsOneWidget, reason: m.label);
      }
      // Overview: how to check in (not checked in, not on yet), Join.
      expect(find.byKey(const ValueKey('how-to-check-in')), findsOneWidget);
      expect(find.text('Join'), findsOneWidget);
      // No organizer row or role switch for a plain visitor.
      expect(find.byKey(const ValueKey('event-role-switch')), findsNothing);
      expect(find.text('Organizer tools'), findsNothing);

      final some = EventHub.fromMap({'levels': 0, 'exhibitors': 12, 'agenda': 0, 'stamp_stops': 0});
      expect(eventModulesFor(some), [EventModule.overview, EventModule.exhibitors]);
      expect(some.isBig, isTrue);
      expect(_hub(big: false).isBig, isFalse);
    });

    testWidgets('checked in: the pass card with my number', (t) async {
      await _pump(t, event: _event(), hub: _hub(checkedIn: true));
      expect(find.byKey(const ValueKey('pass-strip')), findsOneWidget);
      expect(find.text('#0427'), findsOneWidget);
      expect(find.text('Show pass'), findsOneWidget);
    });

    testWidgets('normal meet: one page, no tabs', (t) async {
      await _pump(t, event: _event(), hub: _hub(big: false));
      expect(find.byKey(const ValueKey('event-tabs')), findsNothing);
      expect(find.byKey(const ValueKey('event-role-switch')), findsNothing);
      expect(find.text('Comments (0)'), findsOneWidget);
    });

    testWidgets('normal meet still loads without a hub', (t) async {
      await _pump(t, event: _event(), hub: null);
      expect(_appBarTitle(t), 'Meet');
      expect(find.byKey(const ValueKey('event-tabs')), findsNothing);
    });

    testWidgets('on a real phone the tabs pin under the app bar', (t) async {
      final many = [for (var i = 0; i < 40; i++) Exhibitor(id: 'x$i', eventId: _id, name: 'Exhibitor $i', booths: ['A${100 + i}'])];
      await _pump(t, event: _event(), hub: _hub(), height: 800, exhibitors: many);
      await _tapTab(t, 'exhibitors');
      await t.drag(find.byType(CustomScrollView).first, const Offset(0, -1500));
      await t.pump();
      final tabs = find.byKey(const ValueKey('event-tabs'));
      expect(t.getTopLeft(tabs).dy, lessThan(120));
      expect(find.text('Exhibitor 0'), findsNothing); // scrolled under
      // Another tab starts at its own top, not halfway down.
      await _tapTab(t, 'schedule');
      expect(find.text('No schedule yet'), findsOneWidget);
      await _tapTab(t, 'exhibitors');
      expect(find.text('Exhibitor 0'), findsOneWidget);
      expect(t.takeException(), isNull);
    });

    testWidgets('switching tabs shows each module', (t) async {
      await _pump(t, event: _event(), hub: _hub());
      await _tapTab(t, 'exhibitors');
      expect(find.text('No exhibitors yet'), findsOneWidget);
      await _tapTab(t, 'schedule');
      expect(find.text('No schedule yet'), findsOneWidget);
      await _tapTab(t, 'activities');
      expect(find.text('No stamp stops yet'), findsOneWidget);
      expect(find.text("People's Choice"), findsOneWidget);
      await _tapTab(t, 'floorPlan');
      expect(find.text('No floor plan yet'), findsOneWidget);
      expect(t.takeException(), isNull);
    });
  });

  group('role switch', () {
    test('only for hosts, crew or booth staff', () {
      final staff = _hub(booths: [
        {'id': 'x1', 'name': 'Brembo'},
      ]);
      expect(eventViewsFor(role: EventRole.none, hub: _hub()), [EventView.attendee]);
      expect(eventViewsFor(role: _host, hub: _hub()), [EventView.attendee, EventView.organizer]);
      expect(eventViewsFor(role: _crew, hub: _hub()), [EventView.attendee, EventView.organizer]);
      expect(eventViewsFor(role: EventRole.none, hub: staff), [EventView.attendee, EventView.booth]);
      expect(eventViewsFor(role: _host, hub: staff), EventView.values);
      // Tools off: the host still gets in (to the "get verified" pitch); crew don't.
      expect(eventViewsFor(role: const EventRole(role: 'host'), hub: _hub()), contains(EventView.organizer));
      expect(eventViewsFor(role: const EventRole(role: 'crew'), hub: _hub()), [EventView.attendee]);
      // A picked view I no longer have falls back to attendee.
      expect(currentEventView({_id: EventView.booth}, _id, [EventView.attendee, EventView.organizer]), EventView.attendee);
      expect(currentEventView({_id: EventView.organizer}, _id, [EventView.attendee, EventView.organizer]), EventView.organizer);
    });

    testWidgets('a visitor sees no switch', (t) async {
      await _pump(t, event: _event(), hub: _hub());
      expect(find.byKey(const ValueKey('event-role-switch')), findsNothing);
    });

    testWidgets('host: Attendee · Organizer, organizer tabs by group', (t) async {
      await _pump(t, event: _event(organizer: 'u-me'), hub: _hub(), role: _host);
      expect(find.byKey(const ValueKey('event-role-switch')), findsOneWidget);
      expect(find.byKey(const ValueKey('view-attendee')), findsOneWidget);
      expect(find.byKey(const ValueKey('view-organizer')), findsOneWidget);
      expect(find.byKey(const ValueKey('view-booth')), findsNothing);
      await t.tap(find.byKey(const ValueKey('view-organizer')));
      await t.pump();
      await t.pump(const Duration(milliseconds: 100));
      for (final g in OrganizerGroup.values) {
        expect(find.byKey(ValueKey('tab-${g.name}')), findsOneWidget, reason: g.label);
      }
      await _tapTab(t, 'door');
      expect(find.byKey(const ValueKey('tool-checkin-qr')), findsOneWidget);
      expect(find.byKey(const ValueKey('tool-door-qr')), findsOneWidget);
      expect(find.byKey(const ValueKey('tool-door-list')), findsOneWidget);
      await _tapTab(t, 'program');
      expect(find.byKey(const ValueKey('tool-schedule')), findsOneWidget);
      expect(find.byKey(const ValueKey('tool-draws')), findsOneWidget);
      await _tapTab(t, 'team');
      expect(find.byKey(const ValueKey('tool-crew')), findsOneWidget);
      // Back to attendee: the visitor's tabs again.
      await t.tap(find.byKey(const ValueKey('view-attendee')));
      await t.pump();
      expect(find.byKey(const ValueKey('tab-overview')), findsOneWidget);
      expect(t.takeException(), isNull);
    });

    testWidgets('crew: only the door tools, no tab bar', (t) async {
      await _pump(t, event: _event(), hub: _hub(), role: _crew);
      await t.tap(find.byKey(const ValueKey('view-organizer')));
      await t.pump();
      expect(find.byKey(const ValueKey('event-tabs')), findsNothing);
      expect(find.byKey(const ValueKey('tool-checkin-qr')), findsOneWidget);
      expect(find.byKey(const ValueKey('tool-door-list')), findsOneWidget);
      expect(find.byKey(const ValueKey('tool-prize-scan')), findsOneWidget);
      expect(find.byKey(const ValueKey('tool-door-qr')), findsNothing);
      expect(find.byKey(const ValueKey('tool-crew')), findsNothing);
    });

    testWidgets('booth staff: Attendee · Booth, scan a pass', (t) async {
      await _pump(t, event: _event(), hub: _hub(booths: [
        {'id': 'x1', 'name': 'Brembo Malaysia'},
      ]));
      expect(find.byKey(const ValueKey('view-booth')), findsOneWidget);
      expect(find.byKey(const ValueKey('view-organizer')), findsNothing);
      await t.tap(find.byKey(const ValueKey('view-booth')));
      await t.pump();
      await t.pump(const Duration(milliseconds: 100));
      expect(find.text('Scan a pass'), findsOneWidget);
      expect(find.text('No leads yet'), findsOneWidget);
    });
  });

  group('organizer groups', () {
    List<String> ids(OrganizerGroup g, EventRole r) => organizerTools(g, eventId: _id, role: r, event: _event()).map((t) => t.id).toList();

    test('host gets every group, crew the door', () {
      expect(organizerGroupsFor(_host), OrganizerGroup.values);
      expect(organizerGroupsFor(const EventRole(role: 'cohost', tools: true)), OrganizerGroup.values);
      expect(organizerGroupsFor(_crew), [OrganizerGroup.door]);
      expect(organizerGroupsFor(EventRole.none), isEmpty);
    });

    test('what sits in each group', () {
      expect(ids(OrganizerGroup.dashboard, _host), ['dashboard']);
      expect(ids(OrganizerGroup.door, _host), ['checkin-qr', 'door-qr', 'door-list', 'prize-scan', 'checkin-area', 'registration']);
      expect(ids(OrganizerGroup.program, _host), ['schedule', 'draws', 'vote', 'announcements']);
      expect(ids(OrganizerGroup.exhibitors, _host), ['exhibitors', 'booths', 'floorplan']);
      expect(ids(OrganizerGroup.team, _host), ['crew', 'report']);
      expect(ids(OrganizerGroup.door, _crew), ['checkin-qr', 'door-list', 'prize-scan']);
      for (final g in [OrganizerGroup.dashboard, OrganizerGroup.program, OrganizerGroup.exhibitors, OrganizerGroup.team]) {
        expect(ids(g, _crew), isEmpty, reason: g.label);
      }
    });
  });

  testWidgets('Organizer tools screen lists the same groups', (t) async {
    _phone(t);
    await t.pumpWidget(ProviderScope(
      overrides: [
        currentUserIdProvider.overrideWith((ref) => 'u-me'),
        eventDetailProvider(_id).overrideWith((ref) async => _detail(_event())),
        myEventRoleProvider(_id).overrideWith((ref) async => _host),
        eventDrawsProvider(_id).overrideWith((ref) async => const <LuckyDraw>[]),
      ],
      child: MaterialApp(
        theme: AppTheme.light,
        builder: (context, app) => MediaQuery(data: MediaQuery.of(context).copyWith(textScaler: const TextScaler.linear(1.3)), child: app!),
        home: const OrganizerToolsScreen(eventId: _id),
      ),
    ));
    await t.pump();
    await t.pump(const Duration(milliseconds: 50));
    expect(find.byKey(const ValueKey('tool-checkin-qr')), findsOneWidget);
    for (final g in OrganizerGroup.values) {
      await t.scrollUntilVisible(find.text(g.label.toUpperCase()), 300, scrollable: find.byType(Scrollable).first);
      expect(find.text(g.label.toUpperCase()), findsOneWidget, reason: g.label);
    }
    await t.scrollUntilVisible(find.byKey(const ValueKey('tool-report')), 300, scrollable: find.byType(Scrollable).first);
    expect(t.takeException(), isNull);
  });

  group('back', () {
    Widget page() => HomeOnBack(child: Scaffold(appBar: AppBar(leading: const AppBackButton(), title: const Text('EVENT'))));

    GoRouter router(String initial) => GoRouter(
          initialLocation: initial,
          routes: [
            GoRoute(path: Routes.map, builder: (_, _) => const Scaffold(body: Text('MAP'))),
            GoRoute(path: '/event/:id', builder: (_, _) => page()),
          ],
        );

    testWidgets('nothing to pop (deep link, push, QR): back goes to the map', (t) async {
      final r = router('/event/x');
      await t.pumpWidget(MaterialApp.router(routerConfig: r));
      expect(r.canPop(), isFalse);
      await t.tap(find.byTooltip('Back'));
      await t.pumpAndSettle();
      expect(find.text('MAP'), findsOneWidget);
      expect(find.text('EVENT'), findsNothing);
    });

    testWidgets('something under it: back pops', (t) async {
      final r = router(Routes.map);
      await t.pumpWidget(MaterialApp.router(routerConfig: r));
      r.push('/event/x');
      await t.pumpAndSettle();
      expect(r.canPop(), isTrue);
      await t.tap(find.byTooltip('Back'));
      await t.pumpAndSettle();
      expect(find.text('MAP'), findsOneWidget);
      expect(r.canPop(), isFalse);
    });

    testWidgets('Android system back on a root-level page goes to the map', (t) async {
      final r = router('/event/x');
      await t.pumpWidget(MaterialApp.router(routerConfig: r));
      final handled = await t.binding.handlePopRoute();
      await t.pumpAndSettle();
      expect(handled, isTrue);
      expect(find.text('MAP'), findsOneWidget);
    });

    testWidgets('the event page back with nothing under it', (t) async {
      _phone(t);
      debugEventPageMaps = false;
      addTearDown(() => debugEventPageMaps = true);
      final r = GoRouter(
        initialLocation: '/event/$_id',
        routes: [
          GoRoute(path: Routes.map, builder: (_, _) => const Scaffold(body: Text('MAP'))),
          GoRoute(path: '/event/:id', builder: (_, s) => EventDetailsScreen(eventId: s.pathParameters['id']!)),
        ],
      );
      await t.pumpWidget(ProviderScope(
        overrides: [
          currentUserIdProvider.overrideWith((ref) => 'u-me'),
          currentProfileProvider.overrideWith((ref) async => Profile(id: 'u-me', createdAt: DateTime(2026))),
          guideStoreProvider.overrideWithValue(MemoryGuideStore(seen: const [GuideIds.event])),
          mapOriginProvider.overrideWith((ref) => const LatLng(3.15, 101.7)),
          eventDetailProvider(_id).overrideWith((ref) async => _detail(_event())),
          eventHubProvider(_id).overrideWith((ref) async => _hub()),
          myEventRoleProvider(_id).overrideWith((ref) async => EventRole.none),
          isOrganizerProvider.overrideWith((ref, id) async => false),
          myDrawStatusProvider(_id).overrideWith((ref) async => const <MyDraw>[]),
        ],
        child: MaterialApp.router(theme: AppTheme.light, routerConfig: r),
      ));
      await t.pump();
      await t.pump(const Duration(milliseconds: 50));
      await t.tap(find.byTooltip('Back'));
      await t.pumpAndSettle();
      expect(find.text('MAP'), findsOneWidget);
    });
  });

  group('no overflow at text scale 1.3 on a 360 wide phone', () {
    testWidgets('big event, every attendee tab', (t) async {
      await _pump(t, event: _event(start: DateTime.now().add(const Duration(days: 1)), end: DateTime.now().add(const Duration(days: 20))), hub: _hub(), scale: 1.3);
      expect(t.takeException(), isNull);
      for (final m in EventModule.values.reversed) {
        await _tapTab(t, m.name);
        expect(t.takeException(), isNull, reason: m.label);
      }
    });

    testWidgets('checked in pass card and the role switch with all three', (t) async {
      await _pump(
        t,
        event: _event(),
        hub: _hub(checkedIn: true, booths: [
          {'id': 'x1', 'name': 'Very Long Exhibitor Name Sdn Bhd Booth A019'},
        ]),
        role: _host,
        scale: 1.3,
      );
      expect(find.byKey(const ValueKey('view-booth')), findsOneWidget);
      expect(t.takeException(), isNull);
      await t.tap(find.byKey(const ValueKey('view-organizer')));
      await t.pump();
      for (final g in OrganizerGroup.values.reversed) {
        await _tapTab(t, g.name);
        expect(t.takeException(), isNull, reason: g.label);
      }
      await t.tap(find.byKey(const ValueKey('view-booth')));
      await t.pump();
      await t.pump(const Duration(milliseconds: 100));
      expect(t.takeException(), isNull);
    });

    testWidgets('normal meet', (t) async {
      await _pump(t, event: _event(type: EventType.charity), hub: _hub(big: false), scale: 1.3);
      expect(_appBarTitle(t), 'Charity drive');
      expect(t.takeException(), isNull);
    });

    testWidgets('normal meet on now', (t) async {
      await _pump(t, event: _event(start: DateTime.now().subtract(const Duration(minutes: 30))), hub: _hub(big: false), scale: 1.3);
      expect(find.text('Live now · 0 here'), findsOneWidget);
      expect(t.takeException(), isNull);
    });

    testWidgets('big event on now: the check-in card', (t) async {
      await _pump(
        t,
        event: _event(start: DateTime.now().subtract(const Duration(hours: 2)), end: DateTime.now().add(const Duration(days: 3))),
        hub: _hub(),
        scale: 1.3,
      );
      expect(find.text('Scan the QR at the entrance with TT Spot. You get your pass and a lucky draw number.'), findsOneWidget);
      expect(t.takeException(), isNull);
    });
  });

  test('TiTi words a big event as an event', () {
    final k = EventGuideKeys();
    final big = eventGuide(k, attending: false, chat: true, big: true);
    expect(big.steps.map((s) => s.target), [k.rsvp, null, k.chat]);
    expect(big.steps.map((s) => s.title), contains('Event chat'));
    expect(big.steps.map((s) => s.body).join(' '), isNot(contains('meet')));
    final live = eventGuide(k, attending: true, live: true, big: true);
    expect(live.steps.single.target, k.checkIn);
  });
}
