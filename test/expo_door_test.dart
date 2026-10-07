import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'package:car_meet/core/theme/app_theme.dart';
import 'package:car_meet/features/auth/data/auth_repository.dart';
import 'package:car_meet/features/auth/domain/profile.dart';
import 'package:car_meet/features/events/application/event_providers.dart';
import 'package:car_meet/features/expo/door/application/door_providers.dart';
import 'package:car_meet/features/expo/door/application/door_scan.dart';
import 'package:car_meet/features/expo/door/domain/door_models.dart';
import 'package:car_meet/features/expo/door/domain/registration_csv.dart';
import 'package:car_meet/features/expo/door/presentation/door_welcome_banner.dart';
import 'package:car_meet/features/expo/door/presentation/event_hub_card.dart';
import 'package:car_meet/features/expo/door/presentation/checkin_area_screen.dart';
import 'package:car_meet/features/expo/door/presentation/event_pass_screen.dart';
import 'package:car_meet/features/expo/door/presentation/registration_form_editor_screen.dart';
import 'package:car_meet/features/expo/door/presentation/registration_sheet.dart';
import 'package:car_meet/features/organizer/application/organizer_providers.dart';
import 'package:car_meet/features/organizer/domain/organizer_models.dart';

// Expo mode, track A (door & pass): supabase/migrations/20261008000119_expo_door.sql.

const _ev = 'ev1';

final _form = RegistrationForm.fromMap({
  'event_id': _ev,
  'questions': [
    {'id': 'q1', 'label': 'You are a', 'type': 'one', 'options': ['Trade buyer', 'Car owner', 'Workshop owner or mechanic'], 'required': true},
    {'id': 'q2', 'label': 'What are you looking for at the show today?', 'type': 'many', 'options': ['Tyres', 'Audio', 'Paint protection film', 'Wraps']},
    {'id': 'q3', 'label': 'Company', 'type': 'text'},
  ],
  'consent_text': null,
  'ask_contact': true,
  'required': true,
});

Map<String, dynamic> _hubMap({bool checkedIn = true, bool formDone = false, bool required = true}) => {
      'checked_in': checkedIn,
      'entry_no': checkedIn ? 427 : null,
      'pass_code': checkedIn ? 'abc123def4567890' : null,
      'share_contact': false,
      'checked_in_at': checkedIn ? '2026-10-08T02:05:00+00:00' : null,
      'live': true,
      'registration': {'has_form': true, 'required': required, 'questions': 3, 'done': formDone},
      'levels': 2,
      'exhibitors': 214,
      'agenda': 6,
      'stamp_stops': 12,
      'my_stamps': 3,
      'stamp_goal': 8,
      'contest': {'id': 'c1', 'title': "People's Choice"},
      'my_booths': [
        {'id': 'x1', 'name': 'Very Long Exhibitor Name Sdn Bhd Booth A019'},
      ],
      'is_host': false,
      'car': null,
    };

Widget _wrap(Widget child, {required EventHub? hub, double scale = 1.3}) => ProviderScope(
      overrides: [
        eventHubProvider(_ev).overrideWith((ref) async => hub),
        eventDetailProvider(_ev).overrideWith((ref) async => null),
        currentProfileProvider.overrideWith((ref) async => Profile(id: 'u1', username: 'keanechai_with_a_long_handle', displayName: 'Keane Chai Wei Ming', createdAt: DateTime(2026))),
        myDrawStatusProvider(_ev).overrideWith((ref) async => const <MyDraw>[]),
        registrationFormProvider(_ev).overrideWith((ref) async => _form),
        myRegistrationProvider(_ev).overrideWith((ref) async => null),
        checkinRadiusProvider(_ev).overrideWith((ref) async => 2000),
      ],
      child: MaterialApp(
        theme: AppTheme.light,
        builder: (context, app) => MediaQuery(data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)), child: app!),
        home: child,
      ),
    );

/// A narrow phone: 320 x 900 logical pixels.
void _phone(WidgetTester tester, {double width = 320}) {
  tester.view.devicePixelRatio = 3;
  tester.view.physicalSize = Size(width * 3, 900 * 3);
  addTearDown(tester.view.reset);
}

void main() {
  group('models', () {
    test('entry number is zero-padded to 4', () {
      expect(entryLabel(1), '#0001');
      expect(entryLabel(427), '#0427');
      expect(entryLabel(10000), '#10000');
    });

    test('pass QR payload parses back as a pass code', () {
      expect(passPayload('e1', 'abc'), 'ttspot://pass/e1/abc');
    });

    test('metres read short', () {
      expect(formatMetres(300), '300 m');
      expect(formatMetres(1000), '1 km');
      expect(formatMetres(1500), '1.5 km');
      expect(formatMetres(100000), '100 km');
    });

    test('hub parses and knows when it has something to show', () {
      final h = EventHub.fromMap(_hubMap());
      expect(h.entry, '#0427');
      expect(h.registration.open, isTrue);
      expect(h.stampTarget, 8);
      expect(h.contestId, 'c1');
      expect(h.myBooths.single.id, 'x1');
      expect(h.hasAnything, isTrue);

      final plain = EventHub.fromMap({'checked_in': false, 'registration': null, 'my_booths': []});
      expect(plain.hasAnything, isFalse);
      expect(plain.registration.open, isFalse);
    });

    test('hub tiles: only what has data, in order', () {
      final h = EventHub.fromMap(_hubMap());
      final tiles = hubTiles(_ev, h);
      expect(tiles.map((t) => t.label), ['Pass', 'Floor plan', 'Exhibitors', 'Schedule', 'Stamps', 'Vote', 'My booth']);
      expect(tiles.first.badge, '#0427');
      expect(tiles[4].badge, '3/8');
      expect(tiles.last.route, '/event/$_ev/booth/x1/leads');
      expect(tiles.first.route, '/event/$_ev/pass');
      expect(hubTiles(_ev, h, pass: false, booths: false).map((t) => t.label), ['Floor plan', 'Exhibitors', 'Schedule', 'Stamps', 'Vote']);

      final none = EventHub.fromMap({'checked_in': true, 'entry_no': 5});
      expect(hubTiles(_ev, none).map((t) => t.label), ['Pass']);
    });

    test('door result: welcome on the floor plan, else the pass', () {
      final withPlan = DoorResult.fromMap({'event_id': 'e', 'live': true, 'new': true, 'entry_no': 427, 'points': 10, 'has_floorplan': true});
      final o = doorOutcome(withPlan);
      expect(o.title, "You're in · #0427");
      expect(o.points, 10);
      expect(o.checkinEventId, 'e');
      expect(o.route, '/event/e/floorplan?welcome=1');

      final noPlan = DoorResult.fromMap({'event_id': 'e', 'live': true, 'new': true, 'entry_no': 3, 'points': 0, 'has_floorplan': false});
      expect(doorOutcome(noPlan).route, '/event/e/pass');

      final notLive = DoorResult.fromMap({'event_id': 'e', 'live': false});
      expect(notLive.live, isFalse);
      expect(DoorResult.fromMap({'event_id': 'e', 'live': true, 'need_location': true}).needLocation, isTrue);
    });

    test('form questions round-trip and validate', () {
      final f = RegistrationForm.fromMap({
        'event_id': 'e',
        'questions': [
          {'id': 'q1', 'label': 'You are a', 'type': 'one', 'options': ['Trade buyer', 'Car owner'], 'required': true},
          {'id': 'q2', 'label': 'Company', 'type': 'text'},
        ],
        'consent_text': null,
        'ask_contact': true,
        'required': false,
      });
      expect(f.questions.first.type, QuestionType.one);
      expect(f.questions.last.toMap(), {'id': 'q2', 'label': 'Company', 'type': 'text', 'required': false});
      expect(f.consent, kDefaultConsent);
      expect(validateForm(f.questions), isNull);
      expect(validateForm([const FormQuestion(id: 'q1', label: ' ')]), 'Question 1 needs a question.');
      expect(validateForm([const FormQuestion(id: 'q1', label: 'Pick', type: QuestionType.many, options: ['A'])]), 'Question 1 needs at least 2 options.');
      expect(validateForm([const FormQuestion(id: 'q1', label: 'Pick', type: QuestionType.one, options: ['A', 'A'])]), 'Question 1 has the same option twice.');
      expect(validateForm(List.generate(9, (i) => FormQuestion(id: 'q$i', label: 'Q'))), 'Up to 8 questions.');
      expect(nextQuestionId(['q1', 'q3']), 'q2');
      expect(nextQuestionId([]), 'q1');
    });

    test('pending registration opens once', () {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      final n = c.read(pendingRegistrationProvider.notifier);
      expect(n.take('e'), isFalse);
      n.add('e');
      expect(n.take('e'), isTrue);
      expect(n.take('e'), isFalse);
    });
  });

  group('CSV', () {
    test('cells are escaped', () {
      expect(csvCell(null), '');
      expect(csvCell('plain'), 'plain');
      expect(csvCell('a,b'), '"a,b"');
      expect(csvCell('say "hi"'), '"say ""hi"""');
      expect(csvCell('two\nlines'), '"two\nlines"');
      expect(csvCell(42), '42');
    });

    test('formulas are defused, phone numbers are not', () {
      expect(csvCell('=SUM(A1)'), "'=SUM(A1)");
      expect(csvCell('@cmd'), "'@cmd");
      expect(csvCell('+cmd|calc'), "'+cmd|calc");
      expect(csvCell('-2+3'), "'-2+3");
      expect(csvCell('+60123456789'), '+60123456789');
      expect(csvCell('+60 12-345 6789'), '+60 12-345 6789');
      expect(csvCell('=a,b'), '"\'=a,b"');
    });

    test('registrations: fixed columns then one per question', () {
      const qs = [
        FormQuestion(id: 'q1', label: 'You are a', type: QuestionType.one, options: ['Trade buyer', 'Car owner']),
        FormQuestion(id: 'q2', label: 'Interests, any', type: QuestionType.many, options: ['Tyres', 'Audio']),
        FormQuestion(id: 'q3', label: 'Company'),
      ];
      final rows = [
        RegistrationExportRow(
          entryNo: 7,
          name: 'Keane',
          username: 'keanechai',
          phone: '+60162617638',
          email: 'k@example.com',
          state: 'Kuala Lumpur',
          car: 'Pagani Huayra',
          checkedInAt: DateTime(2026, 10, 8, 14, 5),
          answers: const {'q1': 'Car owner', 'q2': ['Tyres', 'Audio'], 'q3': 'ACME, "Best" Sdn Bhd', 'gone': 'x'},
        ),
        const RegistrationExportRow(name: 'Sean', username: 'lalazai', answers: {'q1': 'Trade buyer'}),
      ];
      final csv = buildRegistrationCsv(questions: qs, rows: rows);
      final lines = csv.split('\r\n');
      expect(lines[0], 'Entry,Name,Username,Phone,Email,State,Car,Checked in,You are a,"Interests, any",Company');
      expect(lines[1], '#0007,Keane,keanechai,+60162617638,k@example.com,Kuala Lumpur,Pagani Huayra,2026-10-08 14:05,Car owner,Tyres; Audio,"ACME, ""Best"" Sdn Bhd"');
      expect(lines[2], ',Sean,lalazai,,,,,,Trade buyer,,');
      expect(lines[3], '');
      expect(lines.length, 4);
    });
  });

  group('widgets at text scale 1.3 on a narrow phone', () {
    testWidgets('hub card shows the tiles and the registration nudge', (tester) async {
      _phone(tester);
      await tester.pumpWidget(_wrap(const Scaffold(body: SingleChildScrollView(child: EventHubCard(eventId: _ev))), hub: EventHub.fromMap(_hubMap())));
      await tester.pumpAndSettle();
      expect(find.text('Pass'), findsOneWidget);
      expect(find.text('#0427'), findsOneWidget);
      expect(find.text('3/8'), findsOneWidget);
      expect(find.text('My booth'), findsOneWidget);
      expect(find.text('Finish registration'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('hub card hides on a plain meet', (tester) async {
      _phone(tester);
      await tester.pumpWidget(_wrap(const Scaffold(body: EventHubCard(eventId: _ev)), hub: EventHub.fromMap({'checked_in': false})));
      await tester.pumpAndSettle();
      expect(find.byType(HubTileGrid), findsNothing);
    });

    testWidgets('welcome banner: number, pass, register; dismissible', (tester) async {
      _phone(tester);
      await tester.pumpWidget(_wrap(const Scaffold(body: DoorWelcomeBanner(eventId: _ev)), hub: EventHub.fromMap(_hubMap())));
      await tester.pumpAndSettle();
      expect(find.text("You're in · #0427"), findsOneWidget);
      expect(find.text('Your pass'), findsOneWidget);
      expect(find.text('Register'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.byTooltip('Close'));
      await tester.pump();
      expect(find.text("You're in · #0427"), findsNothing);
    });

    testWidgets('welcome banner without an open form has no Register', (tester) async {
      _phone(tester);
      await tester.pumpWidget(_wrap(const Scaffold(body: DoorWelcomeBanner(eventId: _ev)), hub: EventHub.fromMap(_hubMap(formDone: true))));
      await tester.pumpAndSettle();
      expect(find.text('Register'), findsNothing);
    });

    testWidgets('pass: number, QR and the share switch', (tester) async {
      _phone(tester);
      await tester.pumpWidget(_wrap(const EventPassScreen(eventId: _ev), hub: EventHub.fromMap(_hubMap())));
      await tester.pumpAndSettle();
      expect(find.text('#0427'), findsWidgets);
      expect(find.byType(QrImageView), findsOneWidget);
      expect(find.text('Booths scan this to save your contact.'), findsOneWidget);
      expect(find.text('Share my phone and email with booths I let scan me'), findsOneWidget);
      expect(find.text('Fill in', skipOffstage: false), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('registration sheet: questions, consent, contact tick', (tester) async {
      _phone(tester);
      await tester.pumpWidget(_wrap(
        Scaffold(body: Builder(builder: (ctx) => TextButton(onPressed: () => showRegistrationSheet(ctx, _ev), child: const Text('open')))),
        hub: null,
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('Trade buyer'), findsOneWidget);
      expect(find.text(kDefaultConsent), findsOneWidget);
      expect(find.text('Share my phone and email with the organizer', skipOffstage: false), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('form editor loads the questions', (tester) async {
      _phone(tester);
      await tester.pumpWidget(_wrap(const RegistrationFormEditorScreen(eventId: _ev), hub: null));
      await tester.pumpAndSettle();
      expect(find.text('QUESTION 1'), findsOneWidget);
      expect(find.text('Workshop owner or mechanic'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.byTooltip('Delete').first);
      await tester.pumpAndSettle();
      expect(find.text('Workshop owner or mechanic'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('check-in area: presets and the current value', (tester) async {
      _phone(tester);
      await tester.pumpWidget(_wrap(const CheckinAreaScreen(eventId: _ev), hub: null));
      await tester.pumpAndSettle();
      expect(find.text('2 km'), findsWidgets);
      expect(find.text('300 m'), findsOneWidget);
      expect(find.text('Custom'), findsNothing); // not an admin
      await tester.tap(find.text('5 km'));
      await tester.pump();
      expect(find.text('Now 2 km. Save to change.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('pass when not checked in: how to check in + Scan', (tester) async {
      _phone(tester);
      await tester.pumpWidget(_wrap(const EventPassScreen(eventId: _ev), hub: EventHub.fromMap(_hubMap(checkedIn: false))));
      await tester.pumpAndSettle();
      expect(find.text('No pass yet'), findsOneWidget);
      expect(find.text('Scan'), findsOneWidget);
      expect(find.byType(QrImageView), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  });
}
