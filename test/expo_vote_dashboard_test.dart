import 'package:car_meet/core/supabase/supabase_client.dart';
import 'package:car_meet/core/theme/app_theme.dart';
import 'package:car_meet/features/expo/contest/application/contest_providers.dart';
import 'package:car_meet/features/expo/contest/domain/contest.dart';
import 'package:car_meet/features/expo/contest/presentation/contest_editor_screen.dart';
import 'package:car_meet/features/expo/contest/presentation/contest_screen.dart';
import 'package:car_meet/features/expo/contest/presentation/vote_qr_sheet_screen.dart';
import 'package:car_meet/features/expo/dashboard/domain/csv.dart';
import 'package:car_meet/features/expo/dashboard/domain/dashboard.dart';
import 'package:car_meet/features/expo/dashboard/presentation/expo_dashboard_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _entry(String id, int? number, {String status = 'approved', int? votes, bool mine = false, String make = 'Honda', String model = 'Civic Type R FK8 Championship White'}) => {
      'id': id,
      'number': number,
      'status': status,
      'user_id': 'u-$id',
      'car_id': 'c-$id',
      'username': 'member_with_a_long_handle_$id',
      'display_name': 'Member $id',
      'make': make,
      'model': model,
      'year': 2019,
      'toy_url': null,
      'cover': null,
      'votes': votes,
      'mine': mine,
    };

Map<String, dynamic> _boardMap({bool ended = false, bool host = false, bool counts = false, String? myVote, bool canVote = true, String? reason}) => {
      'contest': {
        'id': 'k1',
        'event_id': 'e1',
        'title': "People's Choice at the Malaysia Autoshow 2026",
        'about': 'Vote for the car you love most. Winner gets a trophy on stage.',
        'opens_at': null,
        'closes_at': '2026-10-08T10:00:00Z',
        'members_enter': true,
        'status': ended ? 'closed' : 'open',
        'ended': ended,
        'not_yet': false,
      },
      'entries': [
        _entry('a', 1, votes: counts ? 5 : null),
        _entry('b', 2, votes: counts ? 9 : null, make: 'Perodua', model: 'Myvi'),
        _entry('c', 3, votes: counts ? 5 : null),
        _entry('d', 4, votes: counts ? 1 : null),
        if (host) _entry('p', null, status: 'pending'),
      ],
      'is_host': host,
      'counts_visible': counts,
      'total_votes': counts ? 20 : null,
      'me': {
        'my_vote_entry_id': myVote,
        'my_entry': {'id': 'm', 'status': 'pending', 'number': null, 'car_id': 'cm', 'make': 'Proton', 'model': 'Saga'},
        'can_vote': canVote,
        'reason': reason,
        'checked_in': true,
        'going': true,
        'can_enter': false,
      },
    };

/// A small Android phone (360 x 740 dp) at [scale] text size.
Future<void> _pump(WidgetTester tester, Widget child, {double scale = 1.3, List overrides = const []}) async {
  tester.view.physicalSize = const Size(1080, 2220);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(
    overrides: [currentUserIdProvider.overrideWithValue('me'), ...overrides.cast()],
    child: MaterialApp(
      theme: AppTheme.current,
      home: Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
          child: child,
        ),
      ),
    ),
  ));
  for (var i = 0; i < 3; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// Scroll down and up, failing on any overflow.
Future<void> _sweep(WidgetTester tester) async {
  expect(tester.takeException(), isNull);
  final list = find.byType(Scrollable).first;
  for (var i = 0; i < 8; i++) {
    await tester.drag(list, const Offset(0, -300), warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 60));
    expect(tester.takeException(), isNull);
  }
}

void main() {
  group('CSV', () {
    test('quotes commas, quotes and line breaks', () {
      expect(csvCell('plain'), 'plain');
      expect(csvCell('a,b'), '"a,b"');
      expect(csvCell('say "hi"'), '"say ""hi"""');
      expect(csvCell('two\nlines'), '"two\nlines"');
      expect(csvCell(null), '');
      expect(csvCell(42), '42');
    });

    test('guards against spreadsheet formulas', () {
      expect(csvCell('=HYPERLINK("x")'), '"\'=HYPERLINK(""x"")"');
      expect(csvCell('+60123'), "'+60123");
      expect(csvCell('@handle'), "'@handle");
      expect(csvCell(-5), '-5'); // numbers stay numbers
    });

    test('BOM, header and CRLF lines', () {
      final s = buildCsv(['A', 'B'], [
        [1, 'x'],
        [2, null],
      ]);
      expect(s.startsWith(csvBom), isTrue);
      expect(s.substring(1), 'A,B\r\n1,x\r\n2,\r\n');
      expect(buildCsv(['A'], const [], bom: false), 'A\r\n');
    });

    test('check-ins export in Malaysia time', () {
      final s = checkinsCsv([
        {
          'entry_no': 1,
          'name': 'Tan, Ah Kow',
          'username': 'ahkow',
          'state': 'Selangor',
          'car': 'Perodua Myvi',
          'checked_in_at': '2026-10-08T02:05:09.123+00:00',
          'source': 'qr',
        },
        {'entry_no': 2, 'name': null, 'username': null, 'state': null, 'car': null, 'checked_in_at': '2026-10-07T16:30:00Z', 'source': 'manual'},
      ]);
      final lines = s.substring(1).split('\r\n');
      expect(lines[0], 'Entry no,Name,Username,State,Car,Checked in (MYT),Source');
      expect(lines[1], '1,"Tan, Ah Kow",ahkow,Selangor,Perodua Myvi,2026-10-08 10:05:09,qr');
      expect(lines[2], '2,,,,,2026-10-08 00:30:00,manual');
      expect(lines.last, '');
    });

    test('booth visits export', () {
      final s = boothVisitsCsv([
        {'exhibitor': 'Bosch', 'booths': 'A019 A024', 'username': 'lala', 'stamped_at': '2026-10-08T03:00:00Z', 'freebie_redeemed_at': null},
      ]);
      expect(s.substring(1).split('\r\n')[1], "Bosch,A019 A024,lala,2026-10-08 11:00:00,");
    });

    test('slug', () {
      expect(csvSlug('MIAPEX 2026: Hall A!'), 'miapex-2026-hall-a');
      expect(csvSlug('!!!'), 'event');
    });
  });

  group('dashboard', () {
    test('fills empty hours, across midnight', () {
      final out = fillHours([HourCount(DateTime(2026, 10, 8, 22), 3), HourCount(DateTime(2026, 10, 9, 1), 2)]);
      expect(out.map((h) => h.count), [3, 0, 0, 2]);
      expect(out[2].hour, DateTime(2026, 10, 9, 0));
    });

    test('leaves long spans and single hours alone', () {
      final a = [HourCount(DateTime(2026, 10, 8, 10), 1)];
      expect(fillHours(a), a);
      final long = [HourCount(DateTime(2026, 10, 1, 10), 1), HourCount(DateTime(2026, 10, 8, 10), 1)];
      expect(fillHours(long).length, 2);
    });

    test('hour labels', () {
      expect(hourLabel(DateTime(2026, 1, 1, 0)), '12 AM');
      expect(hourLabel(DateTime(2026, 1, 1, 12)), '12 PM');
      expect(hourLabel(DateTime(2026, 1, 1, 15)), '3 PM');
    });

    test('parses the RPC', () {
      final d = ExpoDashboard.fromMap({
        'generated_at': '2026-10-08T02:00:00Z',
        'totals': {'checked_in': 2, 'going': 3, 'registrations': 2, 'contact_ok': 1, 'stamps': 2, 'stampers': 2, 'freebies': 1, 'rally_completed': 1, 'rally_redeemed': 1, 'leads': 1, 'votes': 2, 'exhibitors': 2},
        'arrivals': [
          {'hour': '2026-10-08T10:00:00', 'count': 2},
          {'hour': '2026-10-08T12:00:00', 'count': 5},
        ],
        'makes': [{'label': 'Pagani', 'count': 1}],
        'states': [{'label': 'Kuala Lumpur', 'count': 2}],
        'booths': [{'id': 'x', 'name': 'Bosch', 'booths': ['A019', 'A024'], 'stamp_stop': true, 'stamps': 2, 'freebies': 1, 'leads': 1}],
        'draws': [{'id': 'd', 'title': 'Grand draw', 'status': 'scheduled', 'draw_at': '2026-10-08T12:00:00Z', 'presence_minutes': 15, 'entrants': null, 'confirmed': 1}],
        'contests': [{'id': 'k', 'title': "People's Choice", 'status': 'open', 'ended': false, 'entries': 3, 'pending': 0, 'votes': 2}],
      });
      expect(d.totals.checkedIn, 2);
      expect(d.totals.contactOk, 1);
      expect(d.arrivals.map((h) => h.count), [2, 0, 5]);
      expect(d.arrivals.first.hour, DateTime(2026, 10, 8, 10));
      expect(d.booths.single.booths, ['A019', 'A024']);
      expect(d.draws.single.rollCall, isTrue);
      expect(d.contests.single.votes, 2);
    });
  });

  group('contest', () {
    test('ranks by votes with shared places', () {
      final b = ContestBoard.fromMap(_boardMap(ended: true, counts: true));
      final r = rankEntries(b.entries);
      expect(r.map((e) => e.entry.number), [2, 1, 3, 4]);
      expect(r.map((e) => e.place), [1, 2, 2, 4]);
    });

    test('board parsing and my state', () {
      final b = ContestBoard.fromMap(_boardMap(host: true, counts: true, myVote: 'b'));
      expect(b.approved.length, 4);
      expect(b.pending.length, 1);
      expect(b.myVote?.number, 2);
      expect(b.me.myEntry?.status, EntryStatus.pending);
      expect(b.me.myEntry?.mine, isTrue);
      expect(b.contest.title, startsWith("People's"));
      expect(b.totalVotes, 20);
    });

    test('entry image prefers the toy', () {
      const toy = ContestEntry(id: 'x', userId: 'u', toyUrl: 'https://t/toy.png', cover: 'https://t/c.jpg');
      const cover = ContestEntry(id: 'x', userId: 'u', toyUrl: '', cover: 'https://t/c.jpg');
      expect(toy.image, 'https://t/toy.png');
      expect(toy.imageIsToy, isTrue);
      expect(cover.image, 'https://t/c.jpg');
      expect(cover.imageIsToy, isFalse);
      expect(const ContestEntry(id: 'x', userId: 'u').carName, 'Car');
    });

    test('status line', () {
      final now = DateTime(2026, 10, 8, 12);
      Contest c({bool ended = false, bool notYet = false, String status = 'open', DateTime? opens, DateTime? closes}) =>
          Contest(id: 'k', eventId: 'e', title: 't', status: ContestStatus.parse(status), ended: ended, notYet: notYet, opensAt: opens, closesAt: closes);
      expect(contestStatusLine(c(), now: now), 'Voting open');
      expect(contestStatusLine(c(closes: DateTime(2026, 10, 8, 18)), now: now), 'Voting open · closes 6:00 PM');
      expect(contestStatusLine(c(notYet: true, opens: DateTime(2026, 10, 8, 14)), now: now), 'Opens 2:00 PM');
      expect(contestStatusLine(c(ended: true, status: 'closed'), now: now), 'Closed · results are in');
      expect(contestStatusLine(c(status: 'cancelled'), now: now), 'Cancelled');
    });

    test('vote QR and scan route', () {
      expect(voteQrPayload('abc'), 'ttspot://vote/abc');
      final uri = Uri.parse(voteEntryRoute('e1', 'k1', 'n1'));
      expect(uri.path, '/event/e1/vote');
      expect(uri.queryParameters, {'contest': 'k1', 'entry': 'n1'});
    });
  });

  group('no overflow at text scale 1.3', () {
    testWidgets('member vote screen, open', (tester) async {
      await _pump(
        tester,
        const ContestScreen(eventId: 'e1', contestId: 'k1'),
        overrides: [contestBoardProvider('k1').overrideWith((ref) async => ContestBoard.fromMap(_boardMap(myVote: 'b', canVote: false, reason: 'You voted')))],
      );
      expect(find.text('You voted for #2'), findsOneWidget);
      await _sweep(tester);
    });

    testWidgets('member vote screen, results', (tester) async {
      await _pump(
        tester,
        const ContestScreen(eventId: 'e1', contestId: 'k1'),
        overrides: [contestBoardProvider('k1').overrideWith((ref) async => ContestBoard.fromMap(_boardMap(ended: true, counts: true, canVote: false, reason: 'Voting has closed')))],
      );
      expect(find.text('Closed · results are in'), findsOneWidget);
      await _sweep(tester);
    });

    testWidgets('member vote screen, no vote yet', (tester) async {
      await _pump(
        tester,
        const ContestScreen(eventId: 'e1'),
        overrides: [currentContestIdProvider('e1').overrideWith((ref) async => null)],
      );
      expect(find.text('No show car vote yet'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('host editor', (tester) async {
      await _pump(
        tester,
        const ContestEditorScreen(eventId: 'e1'),
        overrides: [
          currentContestIdProvider('e1').overrideWith((ref) async => 'k1'),
          contestBoardProvider('k1').overrideWith((ref) async => ContestBoard.fromMap(_boardMap(host: true, counts: true))),
        ],
      );
      await tester.scrollUntilVisible(find.text('WAITING (1)'), 200, scrollable: find.byType(Scrollable).first);
      expect(find.text('WAITING (1)'), findsOneWidget);
      await _sweep(tester);
      await tester.pumpWidget(const SizedBox()); // stop the refresh timer
    });

    testWidgets('dash card', (tester) async {
      final e = ContestEntry.fromMap(_entry('a', 127));
      await _pump(tester, Scaffold(body: SingleChildScrollView(child: VoteDashCard(entry: e, contestTitle: "People's Choice", eventTitle: 'Malaysia Autoshow 2026'))));
      expect(find.text('#127'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('dashboard', (tester) async {
      final d = ExpoDashboard.fromMap({
        'generated_at': '2026-10-08T02:00:00Z',
        'totals': {'checked_in': 12345, 'going': 20000, 'registrations': 9876, 'contact_ok': 4321, 'stamps': 54321, 'stampers': 8000, 'freebies': 1200, 'rally_completed': 300, 'rally_redeemed': 120, 'leads': 2345, 'votes': 6789, 'exhibitors': 180},
        'arrivals': [for (var h = 9; h <= 21; h++) {'hour': '2026-10-08T${h.toString().padLeft(2, '0')}:00:00', 'count': (h * 37) % 400}],
        'makes': [for (final m in ['Perodua', 'Proton', 'Honda', 'Toyota', 'Mercedes-Benz', 'BMW', 'Nissan', 'Mitsubishi']) {'label': m, 'count': m.length * 10}],
        'states': [{'label': 'Wilayah Persekutuan Kuala Lumpur', 'count': 4000}, {'label': 'Not set', 'count': 12}],
        'booths': [for (var i = 0; i < 15; i++) {'id': '$i', 'name': 'Exhibitor with a very long company name Sdn Bhd $i', 'booths': ['A0$i', 'B1$i', 'C2$i'], 'stamps': 900 - i, 'freebies': 10, 'leads': 40}],
        'draws': [
          {'id': 'd1', 'title': 'Grand lucky draw with a long name', 'status': 'scheduled', 'draw_at': '2026-10-08T12:00:00Z', 'presence_minutes': 15, 'entrants': null, 'confirmed': 3456},
          {'id': 'd2', 'title': 'Morning draw', 'status': 'drawn', 'draw_at': '2026-10-08T03:00:00Z', 'presence_minutes': null, 'entrants': 8000, 'confirmed': 0},
        ],
        'contests': [{'id': 'k', 'title': "People's Choice", 'status': 'open', 'ended': false, 'entries': 40, 'pending': 12, 'votes': 6789}],
      });
      await _pump(tester, Scaffold(body: DashboardBody(eventId: 'e1', data: d, onExport: (_) {})));
      expect(find.text('12,345'), findsOneWidget);
      await _sweep(tester);
    });
  });
}
