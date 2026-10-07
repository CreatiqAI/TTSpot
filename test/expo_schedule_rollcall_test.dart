import 'package:car_meet/core/theme/app_theme.dart';
import 'package:car_meet/features/expo/schedule/application/agenda_providers.dart';
import 'package:car_meet/features/expo/schedule/domain/agenda.dart';
import 'package:car_meet/features/expo/schedule/presentation/schedule_editor_screen.dart';
import 'package:car_meet/features/expo/schedule/presentation/schedule_screen.dart';
import 'package:car_meet/features/floorplan/application/floorplan_providers.dart';
import 'package:car_meet/features/floorplan/domain/floorplan.dart';
import 'package:car_meet/features/organizer/application/organizer_providers.dart';
import 'package:car_meet/features/organizer/domain/organizer_models.dart';
import 'package:car_meet/features/organizer/presentation/lucky_draw_stage_screen.dart';
import 'package:car_meet/features/organizer/presentation/lucky_draws_screen.dart';
import 'package:car_meet/features/organizer/presentation/widgets/lucky_draw_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

const _event = 'e1';

Map<String, dynamic> _row(String id, String title, DateTime start, {DateTime? end, String? place, String? kind, String? level, bool on = false, String? about, int? count}) => {
      'id': id,
      'event_id': _event,
      'title': title,
      'about': about,
      'starts_at': start.toUtc().toIso8601String(),
      'ends_at': end?.toUtc().toIso8601String(),
      'pin_id': kind == null ? null : 'pin-$id',
      'place_label': kind == null ? place : null,
      'place': place,
      'pin_kind': kind,
      'pin_level_id': level,
      'reminder_on': on,
      'reminder_count': count,
    };

List<AgendaItem> _items(DateTime now) => [
      AgendaItem.fromMap(_row('a', 'Opening ceremony', now.subtract(const Duration(hours: 2)), end: now.subtract(const Duration(hours: 1)), place: 'Main stage', kind: 'stage', level: 'L1')),
      AgendaItem.fromMap(_row('b', 'Drift show with a very long title that should wrap nicely on small phones', now.subtract(const Duration(minutes: 10)),
          end: now.add(const Duration(minutes: 20)), place: 'Outdoor arena behind Hall 4', kind: 'zone', level: 'L1', about: 'Tandem runs by the national champions. Bring ear plugs.')),
      AgendaItem.fromMap(_row('c', 'Talk: wraps and PPF', now.add(const Duration(minutes: 40)), place: 'Hall B lounge', on: true, count: 12)),
      AgendaItem.fromMap(_row('d', 'Lucky draw', now.add(const Duration(hours: 3)), place: 'Main stage', kind: 'stage', level: 'L1')),
      AgendaItem.fromMap(_row('e', 'Day two opening', now.add(const Duration(days: 1)))),
    ];

Future<void> _pump(WidgetTester t, Widget home, {required double scale, List<Override> overrides = const []}) async {
  t.view.physicalSize = const Size(1080, 2400); // 360 dp wide
  t.view.devicePixelRatio = 3;
  addTearDown(t.view.reset);
  await t.pumpWidget(ProviderScope(
    key: UniqueKey(),
    overrides: overrides,
    child: MaterialApp(
      theme: AppTheme.current,
      builder: (context, child) => MediaQuery(data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)), child: child!),
      home: home,
    ),
  ));
  for (var i = 0; i < 4; i++) {
    await t.pump(const Duration(milliseconds: 50));
  }
}

/// Unmounts the screen so its periodic timers stop.
Future<void> _done(WidgetTester t) async {
  expect(t.takeException(), isNull);
  await t.pumpWidget(const SizedBox());
}

Map<String, dynamic> _myDraw({
  required DateTime drawAt,
  int? presence = 15,
  bool confirmed = false,
  bool eligible = false,
  int? entryNo = 427,
  String status = 'scheduled',
}) =>
    {
      'id': 'd1',
      'title': 'Grand draw',
      'draw_at': drawAt.toUtc().toIso8601String(),
      'cutoff_at': drawAt.toUtc().toIso8601String(),
      'must_be_present': true,
      'claim_minutes': 15,
      'status': status,
      'prizes': [
        {'name': 'Ceramic coating', 'quantity': 1},
      ],
      'checked_in': true,
      'entry_no': entryNo,
      'eligible': eligible,
      'excluded': null,
      'presence_required': presence != null,
      'presence_minutes': presence,
      'presence_open': false,
      'presence_confirmed': confirmed,
      'win': null,
    };

void main() {
  group('schedule logic', () {
    test('time range drops the first AM/PM when both match', () {
      expect(agendaTimeRange(DateTime(2026, 10, 8, 10, 30), DateTime(2026, 10, 8, 11)), '10:30 – 11:00 AM');
      expect(agendaTimeRange(DateTime(2026, 10, 8, 11, 30), DateTime(2026, 10, 8, 12, 15)), '11:30 AM – 12:15 PM');
      expect(agendaTimeRange(DateTime(2026, 10, 8, 20), null), '8:00 PM');
    });

    test('now, next, past and later', () {
      final now = DateTime(2026, 10, 8, 15);
      final items = _items(now);
      final p = agendaPhases(items, now);
      expect(p['a'], AgendaPhase.past);
      expect(p['b'], AgendaPhase.now);
      expect(p['c'], AgendaPhase.next);
      expect(p['d'], AgendaPhase.later);
      expect(p['e'], AgendaPhase.later);
      // No end: counts as 30 min.
      final open = AgendaItem.fromMap(_row('x', 'Open', now.subtract(const Duration(minutes: 20))));
      final gone = AgendaItem.fromMap(_row('y', 'Gone', now.subtract(const Duration(minutes: 40))));
      final q = agendaPhases([open, gone], now);
      expect(q['x'], AgendaPhase.now);
      expect(q['y'], AgendaPhase.past);
    });

    test('items with the same next start are all "next"', () {
      final now = DateTime(2026, 10, 8, 15);
      final t = now.add(const Duration(minutes: 30));
      final p = agendaPhases([AgendaItem.fromMap(_row('a', 'A', t)), AgendaItem.fromMap(_row('b', 'B', t))], now);
      expect(p.values.toSet(), {AgendaPhase.next});
    });

    test('grouped by day, in time order', () {
      final now = DateTime(2026, 10, 8, 15);
      final days = groupAgendaByDay(_items(now).reversed.toList());
      expect(days.length, 2);
      expect(days.first.items.map((i) => i.id), ['a', 'b', 'c', 'd']);
      expect(days.last.items.single.id, 'e');
      expect(days.last.day, DateTime(2026, 10, 9));
    });

    test('parses event_agenda_list rows', () {
      final i = AgendaItem.fromMap(_row('a', 'Show', DateTime.utc(2026, 10, 8, 7), place: 'Main stage', kind: 'stage', level: 'L1', on: true, about: '  '));
      expect(i.pinKind, PinKind.stage);
      expect(i.pinLevelId, 'L1');
      expect(i.reminderOn, isTrue);
      expect(i.about, isNull);
      expect(i.startsAt.isUtc, isFalse);
      expect(i.copyWith(reminderOn: false).reminderOn, isFalse);
    });
  });

  group('roll call and entry numbers', () {
    test('entry number format', () {
      expect(formatEntryNo(427), '#0427');
      expect(formatEntryNo(1), '#0001');
      expect(formatEntryNo(12345), '#12345');
    });

    test('masked names for the big screen', () {
      expect(maskName('Ahmad Rizal'), 'Ah*** Ri***');
      expect(maskName('Wei Jie Tan'), 'W** J** T**');
      expect(maskName('@bigboss'), 'bi****');
      expect(maskName('Jo'), 'J*');
      expect(maskName('X'), 'X');
    });

    test('roll call window: draw minus N until entries close', () {
      final draw = DateTime(2026, 10, 8, 16);
      expect(rollCallOpens(draw, null), isNull);
      expect(rollCallOpens(draw, 15), DateTime(2026, 10, 8, 15, 45));
      expect(rollCallOpenNow(draw, draw, 15, DateTime(2026, 10, 8, 15, 44)), isFalse);
      expect(rollCallOpenNow(draw, draw, 15, DateTime(2026, 10, 8, 15, 45)), isTrue);
      expect(rollCallOpenNow(draw, draw, 15, DateTime(2026, 10, 8, 16)), isTrue);
      expect(rollCallOpenNow(draw, draw, 15, DateTime(2026, 10, 8, 16, 1)), isFalse);
      expect(rollCallOpenNow(draw, draw, null, DateTime(2026, 10, 8, 15, 50)), isFalse);
    });

    test('my_draw_status, draw_stage, draw_results and lucky_draws rows', () {
      final drawAt = DateTime.utc(2026, 10, 8, 8);
      final my = MyDraw.fromMap(_myDraw(drawAt: drawAt, confirmed: true));
      expect(my.entryNo, 427);
      expect(my.presenceRequired, isTrue);
      expect(my.presenceConfirmed, isTrue);
      expect(my.rollCallOpensAt, drawAt.toLocal().subtract(const Duration(minutes: 15)));
      expect(my.rollCallOpenAt(drawAt.toLocal().subtract(const Duration(minutes: 5))), isTrue);

      final old = MyDraw.fromMap(_myDraw(drawAt: drawAt, presence: null, entryNo: null)..remove('presence_required'));
      expect(old.presenceRequired, isFalse);
      expect(old.entryNo, isNull);
      expect(old.rollCallOpenAt(drawAt.toLocal()), isFalse);

      final stage = DrawStage.fromMap({
        'id': 'd1',
        'event_id': _event,
        'title': 'Grand draw',
        'status': 'drawn',
        'draw_at': drawAt.toIso8601String(),
        'entrant_count': 38,
        'checked_in': 50,
        'presence_minutes': 15,
        'presence_confirmed': 38,
        'entry_nos': [12, 427, 99],
        'names': ['A'],
        'prizes': [],
        'winners': [
          {'id': 'w1', 'rank': 1, 'prize': 'Rims', 'prize_id': 'p1', 'display_name': 'Ahmad', 'status': 'pending', 'is_alternate': false, 'entry_no': 427},
        ],
      });
      expect(stage.hasRollCall, isTrue);
      expect(stage.presenceConfirmed, 38);
      expect(stage.entryNos, [12, 427, 99]);
      expect(stage.winners.single.entryNo, 427);

      final r = DrawResult.fromMap({'rank': 1, 'prize': 'Rims', 'display_name': 'Ahmad', 'status': 'pending', 'entry_no': 7});
      expect(r.entryNo, 7);

      final d = LuckyDraw.fromMap({
        'id': 'd1',
        'event_id': _event,
        'title': 'Grand draw',
        'draw_at': drawAt.toIso8601String(),
        'cutoff_at': drawAt.toIso8601String(),
        'status': 'scheduled',
        'presence_minutes': 30,
        'lucky_draw_prizes': [],
      });
      expect(d.hasRollCall, isTrue);
      expect(d.rollCallOpensAt, drawAt.toLocal().subtract(const Duration(minutes: 30)));
    });
  });

  for (final scale in const [1.0, 1.3]) {
    group('screens at text scale $scale', () {
      testWidgets('schedule: days, now and next, place link, remind me', (t) async {
        final now = DateTime.now();
        await _pump(t, const ScheduleScreen(eventId: _event), scale: scale, overrides: [
          eventAgendaProvider(_event).overrideWith((ref) async => _items(now)),
          isMeetHostProvider(_event).overrideWith((ref) async => false),
        ]);
        expect(find.text('NOW'), findsOneWidget);
        expect(find.text('NEXT'), findsOneWidget);
        expect(find.text('Outdoor arena behind Hall 4'), findsOneWidget);
        expect(find.textContaining('TODAY'), findsOneWidget);
        await t.scrollUntilVisible(find.text('Reminder on'), 200, scrollable: find.byType(Scrollable).first);
        expect(find.text('Reminder on'), findsOneWidget);
        await t.scrollUntilVisible(find.text('Day two opening'), 200, scrollable: find.byType(Scrollable).first);
        expect(find.text('Remind me'), findsWidgets);
        await _done(t);
      });

      testWidgets('schedule: empty state', (t) async {
        await _pump(t, const ScheduleScreen(eventId: _event), scale: scale, overrides: [
          eventAgendaProvider(_event).overrideWith((ref) async => const <AgendaItem>[]),
          isMeetHostProvider(_event).overrideWith((ref) async => false),
        ]);
        expect(find.text('No schedule yet'), findsOneWidget);
        await _done(t);
      });

      testWidgets('schedule editor: items with reminder counts', (t) async {
        final now = DateTime.now();
        await _pump(t, const ScheduleEditorScreen(eventId: _event), scale: scale, overrides: [
          eventAgendaProvider(_event).overrideWith((ref) async => _items(now)),
        ]);
        expect(find.text('Add item'), findsOneWidget);
        expect(find.text('12'), findsOneWidget);
        expect(find.text('Remind me'), findsNothing);
        await _done(t);
      });

      testWidgets('draw card: number and the I am here button while roll call is open', (t) async {
        final drawAt = DateTime.now().add(const Duration(minutes: 5));
        await _pump(t, const SingleChildScrollView(child: LuckyDrawCard(eventId: _event)), scale: scale, overrides: [
          myDrawStatusProvider(_event).overrideWith((ref) async => [MyDraw.fromMap(_myDraw(drawAt: drawAt))]),
        ]);
        expect(find.text('#0427'), findsOneWidget);
        expect(find.text("I'm here"), findsOneWidget);
        await _done(t);
      });

      testWidgets('draw card: roll call not open yet', (t) async {
        final drawAt = DateTime.now().add(const Duration(minutes: 50));
        await _pump(t, const SingleChildScrollView(child: LuckyDrawCard(eventId: _event)), scale: scale, overrides: [
          myDrawStatusProvider(_event).overrideWith((ref) async => [MyDraw.fromMap(_myDraw(drawAt: drawAt))]),
        ]);
        expect(find.textContaining('Roll call opens at'), findsWidgets);
        expect(find.text("I'm here"), findsNothing);
        await _done(t);
      });

      testWidgets('draw card: confirmed', (t) async {
        final drawAt = DateTime.now().add(const Duration(minutes: 5));
        await _pump(t, const SingleChildScrollView(child: LuckyDrawCard(eventId: _event)), scale: scale, overrides: [
          myDrawStatusProvider(_event).overrideWith((ref) async => [MyDraw.fromMap(_myDraw(drawAt: drawAt, confirmed: true, eligible: true))]),
        ]);
        expect(find.text('Confirmed'), findsOneWidget);
        expect(find.text("I'm here"), findsNothing);
        expect(find.text('#0427'), findsOneWidget);
        await _done(t);
      });

      testWidgets('host list: roll call count while open', (t) async {
        final drawAt = DateTime.now().add(const Duration(minutes: 5));
        final draw = LuckyDraw.fromMap({
          'id': 'd1',
          'event_id': _event,
          'title': 'Grand draw',
          'draw_at': drawAt.toUtc().toIso8601String(),
          'cutoff_at': drawAt.toUtc().toIso8601String(),
          'status': 'scheduled',
          'presence_minutes': 15,
          'lucky_draw_prizes': [
            {'name': 'Ceramic coating', 'quantity': 1, 'sort': 0},
          ],
        });
        await _pump(t, const LuckyDrawsScreen(eventId: _event), scale: scale, overrides: [
          eventDrawsProvider(_event).overrideWith((ref) async => [draw]),
          drawPresenceCountProvider('d1').overrideWith((ref) async => 38),
        ]);
        expect(find.text('38 confirmed'), findsOneWidget);
        expect(find.textContaining('roll call 15 min before'), findsOneWidget);
        await _done(t);
      });

      testWidgets('stage: waiting screen shows the roll call count', (t) async {
        final drawAt = DateTime.now().add(const Duration(minutes: 5));
        await _pump(t, const LuckyDrawStageScreen(eventId: _event, drawId: 'd1'), scale: scale, overrides: [
          myEventRoleProvider(_event).overrideWith((ref) async => const EventRole(role: 'host', tools: true)),
          drawStageProvider('d1').overrideWith((ref) async => DrawStage.fromMap({
                'id': 'd1',
                'event_id': _event,
                'title': 'Grand draw',
                'status': 'scheduled',
                'draw_at': drawAt.toUtc().toIso8601String(),
                'cutoff_at': drawAt.toUtc().toIso8601String(),
                'entrant_count': 38,
                'checked_in': 50,
                'presence_minutes': 15,
                'presence_confirmed': 38,
                'prizes': [],
                'winners': [],
              })),
        ]);
        expect(find.textContaining('38 confirmed here'), findsOneWidget);
        await _done(t);
      });

      testWidgets('stage: reveal lands on the entry number, name masked', (t) async {
        final drawAt = DateTime.now().subtract(const Duration(minutes: 1));
        await _pump(t, const LuckyDrawStageScreen(eventId: _event, drawId: 'd1'), scale: scale, overrides: [
          myEventRoleProvider(_event).overrideWith((ref) async => const EventRole(role: 'host', tools: true)),
          drawStageProvider('d1').overrideWith((ref) async => DrawStage.fromMap({
                'id': 'd1',
                'event_id': _event,
                'title': 'Grand draw',
                'status': 'drawn',
                'draw_at': drawAt.toUtc().toIso8601String(),
                'drawn_at': drawAt.toUtc().toIso8601String(),
                'entrant_count': 3,
                'checked_in': 3,
                'entry_nos': [12, 427, 99],
                'names': ['Ahmad Rizal', 'Mei Ling', 'Kumar'],
                'prizes': [
                  {'id': 'p1', 'name': 'Rims', 'quantity': 1},
                ],
                'winners': [
                  {'id': 'w1', 'rank': 1, 'prize': 'Rims', 'prize_id': 'p1', 'prize_sort': 0, 'display_name': 'Ahmad Rizal', 'username': 'ahmad', 'status': 'pending', 'is_alternate': false, 'entry_no': 427},
                ],
              })),
        ]);
        await t.tap(find.text('Reveal winners'));
        for (var i = 0; i < 80; i++) {
          await t.pump(const Duration(milliseconds: 100));
        }
        expect(find.text('#0427'), findsOneWidget);
        expect(find.text('Ah*** Ri***'), findsOneWidget);
        expect(find.text('Ahmad Rizal'), findsNothing);
        await _done(t);
      });
    });
  }
}
