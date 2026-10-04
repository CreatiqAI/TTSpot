import 'dart:io';

import 'package:car_meet/core/theme/app_theme.dart';
import 'package:car_meet/features/auth/domain/profile.dart';
import 'package:car_meet/features/events/domain/event.dart';
import 'package:car_meet/features/friends/application/nicknames.dart';
import 'package:car_meet/features/friends/domain/friend.dart';
import 'package:car_meet/features/profile/application/profile_meets_provider.dart';
import 'package:car_meet/features/profile/domain/car.dart';
import 'package:car_meet/features/profile/domain/profile_meets.dart';
import 'package:car_meet/features/profile/presentation/widgets/profile_header.dart';
import 'package:car_meet/features/profile/presentation/widgets/profile_meets_sheet.dart';
import 'package:car_meet/features/social/domain/post.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// The profile's "Meets": meets and TT sessions joined, checked in at or
/// hosted, once started and not cancelled (SQL went_event_ids). Tapping the
/// number lists them, and says how many more are private.

const _migration = 'supabase/migrations/20261005000104_presence_admin_fixes.sql';
const _me = 'u-demo';

Event _event(String id, String title, {String organizer = 'u-host', EventType type = EventType.meet, bool instant = false}) => Event(
      id: id,
      organizerId: organizer,
      title: title,
      type: type,
      startsAt: DateTime(2026, 9, 15, 14, 53),
      venueName: 'Wheels Cafe Bangsar',
      lat: 3.13,
      lng: 101.67,
      status: EventStatus.active,
      attendeeCount: 12,
      createdAt: DateTime(2026, 9, 15),
      isInstant: instant,
    );

final _meets = ProfileMeets(
  events: [
    _event('e1', 'TT now @ nadayu28', type: EventType.tt, instant: true),
    _event('e2', 'Friday night mamak run'),
    _event('e3', 'Civic owners Sunday breakfast', organizer: _me),
  ],
  checkedIn: const {'e2'},
);

void main() {
  group('the definition (went_event_ids)', () {
    final sql = File(_migration).readAsStringSync();
    final body = RegExp(r'create or replace function public\.went_event_ids[\s\S]*?\$\$([\s\S]*?)\$\$').firstMatch(sql)!.group(1)!;

    test('joined, checked in at, or hosted', () {
      expect(body, contains('from public.event_attendees a where a.user_id = p_user'));
      expect(body, contains('from public.checkins c where c.user_id = p_user'));
      expect(body, contains('from public.events x where x.organizer_id = p_user'));
      // A union: joined and checked in at the same meet counts once.
      expect(RegExp(r'\bunion\b(?! all)').allMatches(body).length, 2);
    });

    test('started and not cancelled: future RSVPs wait, cancelled meets never count', () {
      expect(body, contains("e.status = 'active'"));
      expect(body, contains('e.starts_at <= now()'));
    });

    test('the profile number and the list use that one definition', () {
      expect(sql, contains('select count(*)::int from public.went_event_ids(p_user)'));
      expect(sql, contains('where v.id in (select public.went_event_ids(p_user))'));
    });
  });

  group('private meets', () {
    test('count minus what I can see, never negative', () {
      expect(_meets.hiddenOf(5), 2);
      expect(_meets.hiddenOf(3), 0);
      expect(_meets.hiddenOf(2), 0, reason: 'a number a little older than the list');
      expect(_meets.hiddenOf(null), 0);
    });

    test('the line under the list', () {
      expect(privateMeetsLine(0), isNull);
      expect(privateMeetsLine(1), 'Plus 1 private meet.');
      expect(privateMeetsLine(2), 'Plus 2 private meets.');
      expect(_meets.hiddenLine(5), 'Plus 2 private meets.');
      expect(_meets.hiddenLine(3), isNull);
    });

    test('a list cut at its limit says "more", not "private"', () {
      final cut = ProfileMeets(events: _meets.events, complete: false);
      expect(cut.hiddenLine(140), 'Plus 137 more.');
    });

    test('what the number counts, in plain words', () {
      expect(meetsExplainer(isMe: true), 'Meets and TT sessions you joined or hosted, counted once they start.');
      expect(meetsExplainer(isMe: false), 'Meets and TT sessions they joined or hosted, counted once they start.');
    });
  });

  group('the sheet', () {
    Future<void> pump(WidgetTester t, Widget child, {double scale = 1, ProfileMeets? meets}) async {
      t.view.physicalSize = const Size(1080, 2400); // 360 x 800
      t.view.devicePixelRatio = 3;
      addTearDown(t.view.reset);
      await t.pumpWidget(ProviderScope(
        retry: (_, _) => null,
        overrides: [
          nicknamesProvider.overrideWithValue(const <String, String>{}),
          profileMeetsProvider(_me).overrideWith((ref) async => meets ?? _meets),
        ],
        child: MaterialApp(
          theme: AppTheme.current,
          builder: (context, c) => MediaQuery(data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)), child: c!),
          home: Scaffold(body: child),
        ),
      ));
      await t.pump();
      await t.pump();
    }

    for (final scale in [1.0, 1.3]) {
      testWidgets('lists them at text $scale: checked in, hosted, and the private remainder', (t) async {
        await pump(t, ProfileMeetsSheet(userId: _me, isMe: true, count: 5, onOpen: (_) {}, onSeeAll: () {}), scale: scale);
        expect(t.takeException(), isNull);
        expect(find.text('Meets · 5'), findsOneWidget);
        expect(find.text('All my meets'), findsOneWidget);
        expect(find.text('TT now @ nadayu28'), findsOneWidget);
        expect(find.text('Friday night mamak run'), findsOneWidget);
        expect(find.text('Civic owners Sunday breakfast'), findsOneWidget);
        expect(find.text('Checked in'), findsOneWidget);
        expect(find.text('Organiser'), findsOneWidget);
        expect(find.text('Plus 2 private meets.'), findsOneWidget);
      });
    }

    testWidgets("someone else's: no link to my meets", (t) async {
      await pump(t, ProfileMeetsSheet(userId: _me, isMe: false, count: 3, onOpen: (_) {}));
      expect(find.text('All my meets'), findsNothing);
      expect(find.textContaining('they joined'), findsOneWidget);
      expect(find.textContaining('private'), findsNothing);
    });

    testWidgets('none yet', (t) async {
      await pump(t, ProfileMeetsSheet(userId: _me, isMe: true, count: 0, onOpen: (_) {}), meets: const ProfileMeets(events: []));
      expect(find.textContaining('No meets yet'), findsOneWidget);
    });

    testWidgets('a tap on a meet opens it', (t) async {
      Event? opened;
      await pump(t, ProfileMeetsSheet(userId: _me, isMe: true, count: 3, onOpen: (e) => opened = e));
      await t.tap(find.text('Friday night mamak run'));
      expect(opened?.id, 'e2');
    });

    for (final scale in [1.0, 1.3]) {
      testWidgets('tapping Meets on a profile opens the sheet (text $scale)', (t) async {
        await pump(
          t,
          SingleChildScrollView(
            child: ProfileHeader(
              profile: Profile(id: _me, username: 'testing', displayName: 'App Review', createdAt: DateTime(2026)),
              isMe: false,
              cars: const <Car>[],
              stats: const ProfileStats(cars: 0, organised: 0, attended: 1, went: 3),
              friendCount: 2,
              points: null,
              moments: const <Story>[],
              friendship: FriendshipStatus.none,
              onMeets: () {},
              onFriends: null,
              onPoints: () {},
              onEdit: () {},
              onRewards: () {},
              onQr: () {},
              onAvatar: () {},
              onGarage: () {},
              onFriendAction: () {},
              onMessage: () {},
            ),
          ),
          scale: scale,
        );
        expect(find.text('3'), findsOneWidget);
        await t.tap(find.text('Meets'));
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
        expect(find.text('Meets · 3'), findsOneWidget);
        expect(find.text('TT now @ nadayu28'), findsOneWidget);
      });
    }
  });
}
