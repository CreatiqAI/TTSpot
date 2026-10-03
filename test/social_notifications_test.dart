import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:car_meet/core/push/in_app_notice.dart';
import 'package:car_meet/core/theme/app_icons.dart';
import 'package:car_meet/core/theme/app_theme.dart';
import 'package:car_meet/core/utils/dates.dart';
import 'package:car_meet/features/auth/domain/profile.dart';
import 'package:car_meet/features/settings/application/settings_providers.dart';
import 'package:car_meet/features/settings/presentation/settings_screen.dart';
import 'package:car_meet/features/social/application/chat_providers.dart';
import 'package:car_meet/features/social/domain/chat.dart';
import 'package:car_meet/features/social/domain/notification.dart';
import 'package:car_meet/features/social/presentation/activity_screen.dart';

// Social pings (0.3.52): friend_post, friend_tt, club_member and follow rows,
// written by supabase/migrations/20261003000097_social_notifications.sql.

final _actor = Profile(id: 'u1', username: 'aiman88', displayName: 'Aiman', createdAt: DateTime(2026));

AppNotification _n(NotificationType type, {String? body, String? postId, String? eventId, String? venue, DateTime? starts, bool instant = false, String? clubId, String? clubName}) => AppNotification(
      id: 'n1',
      type: type,
      actor: _actor,
      body: body,
      postId: postId,
      eventId: eventId,
      eventVenue: venue,
      eventStartsAt: starts,
      eventInstant: instant,
      clubId: clubId,
      clubName: clubName,
      read: false,
      createdAt: DateTime.now(),
    );

class _FakeSettings extends SettingsNotifier {
  _FakeSettings(this.initial);
  final Map<String, dynamic> initial;
  @override
  AppSettings build() => AppSettings(initial);
}

class _FakeActions extends SettingsActions {
  _FakeActions(this.ref) : super(ref);
  final Ref ref;
  final saved = <Map<String, dynamic>>[];
  @override
  Future<void> patch(Map<String, dynamic> patch) async {
    saved.add(patch);
    ref.read(settingsProvider.notifier).apply(patch);
  }
}

void main() {
  group('rows from the database', () {
    test('the new kinds parse', () {
      expect(NotificationType.fromDb('friend_post'), NotificationType.friendPost);
      expect(NotificationType.fromDb('friend_tt'), NotificationType.friendTt);
      expect(NotificationType.fromDb('club_member'), NotificationType.clubMember);
      expect(NotificationType.fromDb('follow'), NotificationType.follow);
      expect(NotificationType.fromDb('something_newer'), NotificationType.unknown);
    });

    test('a TT row carries the venue, start and TT now flag; a video post its poster', () {
      final tt = AppNotification.fromMap({
        'id': 'n1',
        'type': 'friend_tt',
        'event_id': 'e1',
        'body': 'Mamak Bistro',
        'events': {'title': 'TT at Mamak', 'venue_name': 'Mamak Bistro', 'starts_at': '2026-10-04T13:30:00Z', 'is_instant': false},
        'read_at': null,
        'created_at': '2026-10-03T14:00:00Z',
      });
      expect(tt.eventVenue, 'Mamak Bistro');
      expect(tt.eventStartsAt, DateTime.utc(2026, 10, 4, 13, 30).toLocal());
      expect(tt.eventInstant, isFalse);

      final video = AppNotification.fromMap({
        'id': 'n2',
        'type': 'friend_post',
        'post_id': 'p1',
        'body': 'video:',
        'posts': {'photo_urls': <String>[], 'video_poster_url': 'https://x/poster.jpg'},
        'read_at': '2026-10-03T14:00:00Z',
        'created_at': '2026-10-03T14:00:00Z',
      });
      expect(video.postCover, 'https://x/poster.jpg');
      expect(video.read, isTrue);
      expect(AppNotification.fromMap({...{'posts': {'photo_urls': ['https://x/a.jpg'], 'video_poster_url': null}}, 'id': 'n3', 'type': 'friend_post', 'created_at': '2026-10-03T14:00:00Z'}).postCover, 'https://x/a.jpg');
    });
  });

  group('wording (same as the push function)', () {
    test('friend posts', () {
      expect(friendPostText('photo:Sunday drive to Genting'), 'posted: Sunday drive to Genting');
      expect(friendPostText('photo:'), 'posted a new photo.');
      expect(friendPostText('video:'), 'posted a new video.');
      expect(friendPostText('poll:'), 'posted a new poll.');
      expect(friendPostText('poll:Which wheels?'), 'posted: Which wheels?');
      expect(friendPostText('guide:'), 'shared a new guide.');
      expect(friendPostText('spotted:'), 'spotted a car.');
      expect(friendPostText('spotted:R34 at Bangsar'), 'spotted a car: R34 at Bangsar');
      expect(friendPostText('photo:a: b'), 'posted: a: b');
      expect(friendPostText(null), 'posted a new photo.');
    });

    test('when a planned session starts', () {
      final now = DateTime(2026, 10, 3, 22); // Sat 3 Oct, 10 pm
      expect(formatWhenInline(DateTime(2026, 10, 3, 23, 30), now: now), 'today 11:30 PM');
      expect(formatWhenInline(DateTime(2026, 10, 4, 0, 30), now: now), 'tomorrow 12:30 AM');
      expect(formatWhenInline(DateTime(2026, 10, 6, 9), now: now), 'Tue 9:00 AM');
      expect(formatWhenInline(DateTime(2026, 10, 11, 20), now: now), '11 Oct 8:00 PM');
      expect(formatWhenInline(DateTime(2026, 10, 1, 20), now: now), '1 Oct 8:00 PM'); // already past
    });
  });

  group('Activity text and where a tap goes', () {
    final now = DateTime(2026, 10, 3, 22);
    test('friend posted', () {
      expect(activityText(_n(NotificationType.friendPost, body: 'photo:Sunday drive', postId: 'p1')), ('posted: Sunday drive', '/post/p1'));
      expect(activityText(_n(NotificationType.friendPost, body: 'video:', postId: 'p2')), ('posted a new video.', '/post/p2'));
      expect(activityText(_n(NotificationType.friendPost, body: 'photo:')).$2, isNull);
    });
    test('friend planned a TT / is at a TT now', () {
      expect(
        activityText(_n(NotificationType.friendTt, eventId: 'e1', venue: 'Mamak Bistro', starts: DateTime(2026, 10, 4, 21, 30)), now: now),
        ('planned a TT at Mamak Bistro, tomorrow 9:30 PM.', '/event/e1'),
      );
      expect(
        activityText(_n(NotificationType.friendTt, eventId: 'e2', venue: 'Bangsar', starts: DateTime(2026, 10, 3, 22), instant: true), now: now),
        ('is at Bangsar for a TT now.', '/event/e2'),
      );
      // the session is gone (no event row): the stored venue still reads
      expect(activityText(_n(NotificationType.friendTt, body: 'SS2 mamak')).$1, 'is at SS2 mamak for a TT now.');
    });
    test('new club member', () {
      expect(activityText(_n(NotificationType.clubMember, clubId: 'k1', clubName: 'Myvi Klang')), ('joined Myvi Klang.', '/club/k1'));
      expect(activityText(_n(NotificationType.clubMember)), ('joined your club.', null));
    });
    test('new follower opens their profile', () {
      expect(activityText(_n(NotificationType.follow)), ('started following you.', '/profile/u1'));
    });
  });

  group('in-app banner', () {
    test('badges and tap targets for the new kinds', () {
      final post = InAppNotice.fromPush({'kind': 'friend_post', 'title': 'Aiman', 'body': 'posted: Sunday drive', 'route': '/post/p1', 'sender_id': 'u1'})!;
      expect(post.badge, AppIcons.image);
      expect(post.route, '/post/p1');
      expect(post.isChat, isFalse);
      final tt = InAppNotice.fromPush({'kind': 'friend_tt', 'title': 'Aiman', 'body': 'planned a TT at Mamak Bistro, tomorrow 9:30 PM.', 'route': '/event/e1'})!;
      expect(tt.badge, AppIcons.coffee);
      expect(tt.route, '/event/e1');
      final club = InAppNotice.fromPush({'kind': 'club_member', 'title': 'Aiman', 'body': 'joined Myvi Klang.', 'route': '/club/k1'})!;
      expect(club.badge, AppIcons.usersThree);
      expect(club.route, '/club/k1');
      final follow = InAppNotice.fromPush({'kind': 'follow', 'title': 'Aiman', 'body': 'started following you.', 'route': '/profile/u1'})!;
      expect(follow.badge, AppIcons.userPlus);
      expect(follow.route, '/profile/u1');
    });
  });

  group('Settings switches', () {
    test('four new switches, on by default, each with its own key', () {
      const keys = {
        PushKind.friendPosts: 'notif_friend_posts',
        PushKind.friendTt: 'notif_friend_tt',
        PushKind.clubMembers: 'notif_club_members',
        PushKind.followers: 'notif_followers',
      };
      keys.forEach((k, key) {
        expect(k.key, key);
        expect(k.isOn(const AppSettings({})), isTrue, reason: '$key defaults on');
        expect(k.isOn(AppSettings({key: false})), isFalse, reason: '$key off');
        // switching one off leaves the others alone
        for (final other in PushKind.values.where((o) => o != k)) {
          expect(other.isOn(AppSettings({key: false})), isTrue, reason: '${other.key} untouched by $key');
        }
      });
      expect(PushKind.values.map((k) => k.key).toSet().length, PushKind.values.length);
      expect(PushKind.friends.subtitle.contains('follows'), isFalse); // follows have their own switch now
    });
  });

  group('widgets', () {
    tearDown(() => AppColors.dark = false);

    Future<void> pumpRows(WidgetTester tester, List<AppNotification> rows, {double scale = 1.0, double width = 320}) async {
      tester.view.physicalSize = Size(width * 3, 780 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final router = GoRouter(routes: [
        GoRoute(path: '/', builder: (_, _) => Scaffold(body: ListView(children: [for (final n in rows) ActivityRow(n: n, badges: const [], me: 'me')]))),
        for (final p in ['post', 'event', 'club', 'profile'])
          GoRoute(path: '/$p/:id', builder: (_, s) => Scaffold(body: Text('$p page ${s.pathParameters['id']}'))),
      ]);
      await tester.pumpWidget(ProviderScope(
        child: MaterialApp.router(
          theme: AppTheme.current,
          routerConfig: router,
          builder: (context, child) => MediaQuery(data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)), child: child!),
        ),
      ));
      await tester.pumpAndSettle();
    }

    final longName = Profile(id: 'u2', username: 'a_really_long_handle_for_a_small_phone_screen', createdAt: DateTime(2026));
    List<AppNotification> rows() => [
          _n(NotificationType.friendPost, body: 'photo:Sunday drive to Genting with the boys, who is coming along?…', postId: 'p1'),
          _n(NotificationType.friendTt, eventId: 'e1', venue: 'Restoran Nasi Kandar Pelita Bangsar Utama', starts: DateTime.now().add(const Duration(days: 1))),
          _n(NotificationType.clubMember, clubId: 'k1', clubName: 'Persatuan Kereta Myvi Lembah Klang Selangor'),
          AppNotification(id: 'n9', type: NotificationType.follow, actor: longName, read: true, createdAt: DateTime.now()),
        ];

    for (final dark in [false, true]) {
      for (final scale in [1.0, 1.3]) {
        testWidgets('new rows fit at 320 wide (${dark ? 'dark' : 'light'}, font ×$scale)', (tester) async {
          AppColors.dark = dark;
          await pumpRows(tester, rows(), scale: scale);
          expect(find.byType(ActivityRow), findsNWidgets(4));
          expect(find.textContaining('posted: Sunday drive', findRichText: true), findsOneWidget);
          expect(find.textContaining('planned a TT at Restoran', findRichText: true), findsOneWidget);
          expect(find.textContaining('joined Persatuan', findRichText: true), findsOneWidget);
          expect(find.textContaining('started following you.', findRichText: true), findsOneWidget);
          expect(tester.takeException(), isNull);
        });
      }
    }

    testWidgets('each new row opens its page', (tester) async {
      for (final (i, page) in [(0, 'post page p1'), (1, 'event page e1'), (2, 'club page k1'), (3, 'profile page u2')]) {
        await pumpRows(tester, rows());
        await tester.tap(find.byType(ActivityRow).at(i), warnIfMissed: false);
        await tester.pumpAndSettle();
        expect(find.text(page), findsOneWidget, reason: 'row $i');
      }
    });

    for (final scale in [1.0, 1.3]) {
      testWidgets('Push notifications screen: the new switches show, fit and save (font ×$scale)', (tester) async {
        tester.view.physicalSize = const Size(320 * 3, 700 * 3);
        tester.view.devicePixelRatio = 3;
        addTearDown(tester.view.reset);
        late _FakeActions actions;
        await tester.pumpWidget(ProviderScope(
          overrides: [
            settingsProvider.overrideWith(() => _FakeSettings(const {})),
            settingsActionsProvider.overrideWith((ref) => actions = _FakeActions(ref)),
            inboxProvider.overrideWith((ref) async => const <Conversation>[]),
          ],
          child: MaterialApp(
            theme: AppTheme.current,
            builder: (context, child) => MediaQuery(data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)), child: child!),
            home: const PushSettingsScreen(),
          ),
        ));
        await tester.pumpAndSettle();

        for (final k in [PushKind.friendTt, PushKind.friendPosts, PushKind.followers, PushKind.clubMembers]) {
          final title = find.text(k.title);
          await tester.scrollUntilVisible(title, 120, scrollable: find.byType(Scrollable).first);
          await tester.pumpAndSettle();
          expect(find.text(k.subtitle), findsOneWidget);
          final tile = find.ancestor(of: title, matching: find.byType(SwitchListTile));
          expect(tester.widget<SwitchListTile>(tile).value, isTrue, reason: '${k.key} starts on');
          await tester.tap(title);
          await tester.pumpAndSettle();
          expect(actions.saved.last, {k.key: false});
          expect(tester.widget<SwitchListTile>(tile).value, isFalse, reason: '${k.key} now off');
        }
        expect(tester.takeException(), isNull);
      });
    }
  });
}
