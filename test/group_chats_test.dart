import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import 'package:car_meet/core/supabase/supabase_client.dart';
import 'package:car_meet/core/theme/app_theme.dart';
import 'package:car_meet/core/widgets/user_avatar.dart';
import 'package:car_meet/features/auth/data/auth_repository.dart';
import 'package:car_meet/features/auth/domain/profile.dart';
import 'package:car_meet/features/friends/application/friends_providers.dart';
import 'package:car_meet/features/friends/application/nicknames.dart';
import 'package:car_meet/features/friends/domain/friend.dart';
import 'package:car_meet/features/safety/data/safety_repository.dart';
import 'package:car_meet/features/settings/application/settings_providers.dart';
import 'package:car_meet/features/social/application/chat_providers.dart';
import 'package:car_meet/features/social/application/community_providers.dart';
import 'package:car_meet/features/social/application/group_chat_providers.dart';
import 'package:car_meet/features/social/application/notification_providers.dart';
import 'package:car_meet/features/social/application/social_providers.dart';
import 'package:car_meet/features/social/data/chat_repository.dart';
import 'package:car_meet/features/social/domain/chat.dart';
import 'package:car_meet/features/social/domain/group_chat.dart';
import 'package:car_meet/features/social/domain/post.dart';
import 'package:car_meet/features/social/presentation/chat_info_screen.dart';
import 'package:car_meet/features/social/presentation/chat_screen.dart';
import 'package:car_meet/features/social/presentation/inbox_screen.dart';
import 'package:car_meet/features/social/presentation/new_group_screen.dart';

// Group chats (0.3.53): friends' groups and club members chats,
// supabase/migrations/20261005000100_group_chats.sql.

const _me = 'me-1';
Profile _p(String id, String name, String handle) => Profile(id: id, displayName: name, username: handle, createdAt: DateTime(2026));
final _meP = _p(_me, 'Me Myself', 'me_myself');
final _aiman = _p('u-aiman', 'Aiman Hakim', 'aiman88');
final _bala = _p('u-bala', 'Bala', 'bala_kl');
final _chong = _p('u-chong', 'Chong Wei Liang', 'chongwl');
final _dina = _p('u-dina', 'Dina', 'dina_drift');
// A long one, for the 360 dp phone at 1.3.
final _long = _p('u-long', 'Muhammad Hafiz bin Abdul Rahman Shah', 'a_really_long_handle_here');

Message _msg(String id, String sender, String body, {Profile? profile, String conv = 'g1', int minutesAgo = 0}) =>
    Message(id: id, conversationId: conv, senderId: sender, body: body, createdAt: DateTime.now().subtract(Duration(minutes: minutesAgo)), sender: profile);

Conversation _group({String id = 'g1', String? name, Message? last, int unread = 0, bool admin = true, bool muted = false, List<Profile>? members}) => Conversation(
      id: id,
      kind: 'group',
      members: members ?? [_meP, _aiman, _bala, _chong],
      unread: unread,
      lastMessage: last,
      groupName: name,
      memberCount: (members ?? [_meP, _aiman, _bala, _chong]).length,
      adminIds: admin ? {_me} : {_aiman.id},
      createdBy: admin ? _me : _aiman.id,
      selfId: _me,
      mutedAt: muted ? DateTime(2026) : null,
    );

Conversation _clubChat({Message? last, int count = 12}) => Conversation(
      id: 'k-chat',
      kind: 'club',
      members: const [],
      unread: 0,
      lastMessage: last,
      clubId: 'k1',
      entityName: 'Persatuan Kereta Myvi Lembah Klang Selangor',
      memberCount: count,
      selfId: _me,
    );

List<GroupMember> _members({String? adminId = _me}) => [
      for (final p in [_meP, _aiman, _bala, _chong, _long]) GroupMember(profile: p, isAdmin: p.id == adminId),
    ];

class _FakeSettings extends SettingsNotifier {
  @override
  AppSettings build() => AppSettings(const {});
}

class _FakeChatActions extends ChatActions {
  _FakeChatActions(super.ref);
  @override
  Future<void> markRead(String conversationId) async {}
}

class _FakeGroupActions extends GroupChatActions {
  _FakeGroupActions(super.ref);
  List<String>? createdWith;
  String? createdName;
  String? renamed;
  String? removed;
  (String, bool)? admin;
  String? left;
  List<String>? added;
  String? deleted;

  @override
  Future<void> deleteMessage(String conversationId, String messageId) async => deleted = messageId;

  @override
  Future<String> create({required List<String> memberIds, String? name, XFile? photo}) async {
    createdWith = memberIds;
    createdName = name;
    return 'g-new';
  }

  @override
  Future<void> rename(String conversationId, String? name) async => renamed = name;
  @override
  Future<void> removeMember(String conversationId, String userId) async => removed = userId;
  @override
  Future<void> setAdmin(String conversationId, String userId, bool admin) async => this.admin = (userId, admin);
  @override
  Future<void> leave(String conversationId) async => left = conversationId;
  @override
  Future<int> addMembers(String conversationId, List<String> userIds) async {
    added = userIds;
    return userIds.length;
  }
}

/// A 360 dp wide phone at [scale]; [initial] is the first route, the rest are placeholders.
Future<void> _pump(WidgetTester t, {required double scale, required List<RouteBase> routes, required String initial, List overrides = const []}) async {
  t.view.physicalSize = const Size(1080, 2400);
  t.view.devicePixelRatio = 3;
  addTearDown(t.view.reset);
  final router = GoRouter(initialLocation: initial, routes: [
    ...routes,
    for (final p in ['/chat/:id', '/chat/:id/add', '/new-group', '/search', '/chats', '/profile/:id', '/club/:id'])
      if (!routes.any((r) => r is GoRoute && r.path == p)) GoRoute(path: p, builder: (_, s) => Scaffold(body: Text('page ${s.uri}'))),
  ]);
  await t.pumpWidget(ProviderScope(
    overrides: [
      currentUserIdProvider.overrideWithValue(_me),
      nicknamesProvider.overrideWithValue(const {'u-aiman': 'Boss'}),
      settingsProvider.overrideWith(_FakeSettings.new),
      blockedUserIdsProvider.overrideWith((ref) async => <String>{}),
      ...overrides.cast(),
    ],
    child: MaterialApp.router(
      theme: AppTheme.current,
      routerConfig: router,
      builder: (context, child) => MediaQuery(data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)), child: child!),
    ),
  ));
  await t.pumpAndSettle();
}

void main() {
  group('names and rules', () {
    test('an unnamed group is titled by its people, like WhatsApp', () {
      expect(groupAutoName(const []), 'Group chat');
      expect(groupAutoName(const ['Aiman']), 'Aiman');
      expect(groupAutoName(const ['Aiman', 'Bala']), 'Aiman and Bala');
      expect(groupAutoName(const ['Aiman', 'Bala', 'Chong']), 'Aiman, Bala and Chong');
      expect(groupAutoName(const ['Aiman', 'Bala', 'Chong', 'Dina', 'Ezra']), 'Aiman, Bala, Chong and 2 more');
      expect(shortNameOf(_chong), 'Chong');
      expect(shortNameOf(Profile(id: 'x', username: 'keith', createdAt: DateTime(2026))), '@keith');
    });

    test('the title: my nicknames for an unnamed group, its own name, the club for a club chat', () {
      expect(conversationTitle(_group(), const {'u-aiman': 'Boss'}), 'Boss, Bala and Chong');
      expect(_group().title, 'Aiman, Bala and Chong');
      expect(conversationTitle(_group(name: '  Sunday Convoy '), const {'u-aiman': 'Boss'}), 'Sunday Convoy');
      final club = _clubChat();
      expect(conversationTitle(club, const {}), 'Persatuan Kereta Myvi Lembah Klang Selangor');
      expect(club.isMulti && club.isGroup && club.isClubChat, isTrue);
      expect(club.showEntity, isFalse, reason: 'a club chat is not the club account talking');
      expect(club.otherGone, isFalse);
      expect(club.size, 12);
    });

    test('a club chat lives in my own Chats, never in the club account inbox', () {
      final club = _clubChat();
      expect(const InboxScope.personal(managedClubs: {'k1'}).includes(club), isTrue);
      expect(const InboxScope.club('k1').includes(club), isFalse);
      // A "message the club" DM still goes to the club inbox.
      final dm = Conversation(id: 'd1', kind: 'dm', members: [_aiman], unread: 0, clubId: 'k1', entityName: 'Myvi KL');
      expect(const InboxScope.personal(managedClubs: {'k1'}).includes(dm), isFalse);
      expect(const InboxScope.club('k1').includes(dm), isTrue);
    });

    test("the inbox summary's last message (to_jsonb + its sender) parses", () {
      // The shape my_chat_summaries() returns for last_message.
      final m = Message.fromMap({
        'id': 'm1',
        'conversation_id': 'g1',
        'sender_id': 'u-aiman',
        'body': 'Otw',
        'created_at': '2026-10-05T12:34:56.123456+00:00',
        'audio_wave': [10, 50, 90],
        'audio_ms': 1200,
        'as_club': null,
        'profiles': {'id': 'u-aiman', 'username': 'aiman88', 'display_name': 'Aiman Hakim', 'avatar_url': null, 'created_at': '2026-09-01T00:00:00+00:00'},
      });
      expect(m.sender?.displayName, 'Aiman Hakim');
      expect(m.createdAt.toUtc(), DateTime.utc(2026, 10, 5, 12, 34, 56, 123, 456));
      expect(m.audioWave, [10, 50, 90]);
      final c = _group(last: m);
      expect(c.lastMessage?.body, 'Otw');
    });

    test('admin flags', () {
      expect(_group().amGroupAdmin, isTrue);
      expect(_group(admin: false).amGroupAdmin, isFalse);
      expect(_clubChat().amGroupAdmin, isFalse, reason: 'club chats are moderated by the club officers');
    });
  });

  for (final scale in const [1.0, 1.3]) {
    testWidgets('New group: pick 2+ friends, name it, create (font x$scale)', (t) async {
      late _FakeGroupActions actions;
      await _pump(t, scale: scale, initial: '/new-group', routes: [
        GoRoute(path: '/new-group', builder: (_, _) => const NewGroupScreen()),
      ], overrides: [
        friendsProvider.overrideWith((ref) async => [_aiman, _bala, _chong, _long]),
        groupChatActionsProvider.overrideWith((ref) => actions = _FakeGroupActions(ref)),
      ]);
      expect(find.text('New group'), findsOneWidget);
      expect(find.text('Pick at least 2 friends'), findsOneWidget);
      TextButton next() => t.widget<TextButton>(find.byKey(const Key('new-group-next')));
      expect(next().onPressed, isNull);

      // My nickname for Aiman shows in the list.
      expect(find.text('Boss'), findsOneWidget);
      await t.tap(find.byKey(const Key('friend-pick-u-aiman')));
      await t.pump();
      expect(next().onPressed, isNull, reason: 'one friend is not a group');

      // Search narrows the list.
      await t.enterText(find.byKey(const Key('friend-picker-search')), 'chong');
      await t.pump();
      expect(find.byKey(const Key('friend-pick-u-bala')), findsNothing);
      expect(find.byKey(const Key('friend-pick-u-chong')), findsOneWidget);
      await t.tap(find.byKey(const Key('friend-pick-u-chong')));
      await t.enterText(find.byKey(const Key('friend-picker-search')), '');
      await t.pump();
      await t.tap(find.byKey(const Key('friend-pick-u-long')));
      await t.pumpAndSettle();
      expect(find.text('3 picked'), findsOneWidget);
      expect(next().onPressed, isNotNull);
      expect(t.takeException(), isNull);

      await t.tap(find.byKey(const Key('new-group-next')));
      await t.pumpAndSettle();
      expect(find.text('Name the group'), findsOneWidget);
      expect(find.text('MEMBERS · 4'), findsOneWidget);
      await t.enterText(find.byKey(const Key('new-group-name')), 'Sunday Convoy');
      await t.pump();
      expect(t.takeException(), isNull);
      await t.ensureVisible(find.byKey(const Key('new-group-create')));
      await t.tap(find.byKey(const Key('new-group-create')));
      await t.pumpAndSettle();
      expect(actions.createdWith, ['u-aiman', 'u-chong', 'u-long']);
      expect(actions.createdName, 'Sunday Convoy');
      expect(find.text('page /chat/g-new'), findsOneWidget, reason: 'opens the new group');
    });

    testWidgets('New group: with under 2 friends it says to add some (font x$scale)', (t) async {
      await _pump(t, scale: scale, initial: '/new-group', routes: [
        GoRoute(path: '/new-group', builder: (_, _) => const NewGroupScreen()),
      ], overrides: [
        friendsProvider.overrideWith((ref) async => [_aiman]),
      ]);
      expect(find.text('Add friends first'), findsOneWidget);
      expect(t.takeException(), isNull);
    });

    testWidgets('Group chat: names and faces on the first bubble of a run, nicknames first (font x$scale)', (t) async {
      final messages = [
        // Came in live: no sender profile, so the name comes from the member list.
        _msg('m1', _aiman.id, 'Otw, 10 min', minutesAgo: 5),
        _msg('m2', _aiman.id, 'Parking at the back', profile: _aiman, minutesAgo: 4),
        _msg('m3', _long.id, 'Same, see you there. Bring the GoPro for the run up Genting please', profile: _long, minutesAgo: 3),
        _msg('m4', _me, 'Coming!', profile: _meP, minutesAgo: 2),
      ];
      await _pump(t, scale: scale, initial: '/chat/g1', routes: [
        GoRoute(path: '/chat/:id', builder: (_, s) => ChatScreen(conversationId: s.pathParameters['id']!)),
      ], overrides: [
        conversationProvider('g1').overrideWith((ref) async => _group(name: 'Sunday Convoy', admin: false, members: [_meP, _aiman, _bala, _chong, _long])),
        messagesProvider('g1').overrideWith((ref) => Stream.value(messages)),
        groupMembersProvider('g1').overrideWith((ref) async => _members(adminId: _aiman.id)),
        chatActionsProvider.overrideWith(_FakeChatActions.new),
      ]);
      expect(find.text('Sunday Convoy'), findsOneWidget);
      expect(find.text('5 members'), findsOneWidget);
      // Aiman's run: one name (my nickname), one face, two bubbles.
      expect(find.text('Boss'), findsOneWidget);
      expect(find.text('Muhammad Hafiz bin Abdul Rahman Shah'), findsOneWidget);
      expect(find.text('Me Myself'), findsNothing, reason: 'my own bubbles carry no name');
      final list = find.byType(ListView);
      expect(find.descendant(of: list, matching: find.byType(UserAvatar)), findsNWidgets(2), reason: 'one face per run, none on mine');
      expect(t.takeException(), isNull);

      // Not an admin: delete for everyone on my own message only.
      await t.longPress(find.textContaining('Parking at the back', findRichText: true));
      await t.pumpAndSettle();
      expect(find.text('Reply'), findsOneWidget);
      expect(find.byKey(const Key('message-delete')), findsNothing);
      await t.tapAt(const Offset(10, 10));
      await t.pumpAndSettle();
      await t.longPress(find.textContaining('Coming!', findRichText: true));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('message-delete')), findsOneWidget);
      expect(t.takeException(), isNull);
    });

    testWidgets('Group chat: an admin can delete anyone, and an empty group says hi (font x$scale)', (t) async {
      final controller = StreamController<List<Message>>();
      addTearDown(controller.close);
      controller.add(const []); // buffered until the chat listens
      late _FakeGroupActions actions;
      await _pump(t, scale: scale, initial: '/chat/g1', routes: [
        GoRoute(path: '/chat/:id', builder: (_, s) => ChatScreen(conversationId: s.pathParameters['id']!)),
      ], overrides: [
        conversationProvider('g1').overrideWith((ref) async => _group()),
        messagesProvider('g1').overrideWith((ref) => controller.stream),
        groupMembersProvider('g1').overrideWith((ref) async => _members()),
        chatActionsProvider.overrideWith(_FakeChatActions.new),
        groupChatActionsProvider.overrideWith((ref) => actions = _FakeGroupActions(ref)),
      ]);
      expect(find.text('Boss, Bala and Chong'), findsOneWidget, reason: 'unnamed: its people, by my nicknames');
      expect(find.text('Say hi to the group'), findsOneWidget);
      expect(t.takeException(), isNull);

      controller.add([_msg('m1', _bala.id, 'Anyone up for a TT?', profile: _bala)]);
      await t.pumpAndSettle();
      await t.longPress(find.textContaining('Anyone up for a TT?', findRichText: true));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('message-delete')), findsOneWidget, reason: 'admins delete for everyone');
      await t.tap(find.byKey(const Key('message-delete')));
      await t.pumpAndSettle();
      expect(find.text('Delete for everyone?'), findsOneWidget);
      await t.tap(find.byKey(const Key('message-delete-confirm')));
      await t.pumpAndSettle();
      expect(actions.deleted, 'm1');
      expect(t.takeException(), isNull);
    });

    testWidgets('Inbox: group rows with picture, "Name: text", unread, mute; compose opens New group (font x$scale)', (t) async {
      final inbox = [
        _group(name: 'Sunday Convoy Genting Highlands Midnight Run', last: _msg('m1', _aiman.id, 'Otw, 10 min, wait for me at the petrol station', profile: _aiman), unread: 2, muted: true),
        _group(id: 'g2', last: _msg('m2', _me, 'See you all', conv: 'g2', profile: _meP)),
        _clubChat(),
        Conversation(id: 'd1', kind: 'dm', other: _dina, members: [_meP, _dina], unread: 0, lastMessage: _msg('m3', _dina.id, 'Hi!', conv: 'd1', profile: _dina), selfId: _me),
      ];
      await _pump(t, scale: scale, initial: '/chats', routes: [
        GoRoute(path: '/chats', builder: (_, _) => const InboxScreen()),
      ], overrides: [
        inboxProvider.overrideWith((ref) async => inbox),
        friendsProvider.overrideWith((ref) async => [_aiman, _dina]),
        friendPinsProvider.overrideWith((ref) => Stream.value(const <FriendPin>[])),
        storiesProvider.overrideWith((ref) async => const <StoryGroup>[]),
        currentProfileProvider.overrideWith((ref) async => _meP),
        unreadNotificationsProvider.overrideWith((ref) => Stream.value(0)),
      ]);
      expect(find.text('Sunday Convoy Genting Highlands Midnight Run'), findsOneWidget);
      expect(find.text('Boss: Otw, 10 min, wait for me at the petrol station'), findsOneWidget);
      expect(find.text('You: See you all'), findsOneWidget);
      expect(find.text('Boss, Bala and Chong'), findsOneWidget);
      expect(find.text('Persatuan Kereta Myvi Lembah Klang Selangor'), findsOneWidget);
      expect(find.text('Club chat · 12 members'), findsOneWidget, reason: 'a club chat shows before anyone writes');
      expect(find.text('Hi!'), findsOneWidget, reason: 'DM rows stay as they were');
      // Aiman is in a group with me but not in a DM: still "not chatted yet".
      expect(find.text('NOT CHATTED YET'), findsOneWidget);
      expect(t.takeException(), isNull);

      await t.tap(find.byKey(const Key('inbox-compose')));
      await t.pumpAndSettle();
      expect(find.text('New message'), findsOneWidget);
      await t.tap(find.byKey(const Key('compose-new-group')));
      await t.pumpAndSettle();
      expect(find.text('page /new-group'), findsOneWidget);
    });

    testWidgets('Group info (admin): rename, members, remove, add, leave (font x$scale)', (t) async {
      late _FakeGroupActions actions;
      await _pump(t, scale: scale, initial: '/chat/g1/info', routes: [
        GoRoute(path: '/chat/:id/info', builder: (_, s) => ChatInfoScreen(conversationId: s.pathParameters['id']!)),
      ], overrides: [
        conversationProvider('g1').overrideWith((ref) async => _group(name: 'Sunday Convoy', members: [_meP, _aiman, _bala, _chong, _long])),
        groupMembersProvider('g1').overrideWith((ref) async => _members()),
        sharedInChatProvider('g1').overrideWith((ref) async => const <Message>[]),
        groupChatActionsProvider.overrideWith((ref) => actions = _FakeGroupActions(ref)),
      ]);
      expect(find.text('Group info'), findsOneWidget);
      expect(find.text('Sunday Convoy'), findsOneWidget);
      expect(find.text('Group · 5 members'), findsOneWidget);
      expect(find.text('MEMBERS · 5'), findsOneWidget);
      expect(find.text('Admin'), findsOneWidget);
      expect(find.text('You'), findsOneWidget);
      expect(t.takeException(), isNull);

      // Rename.
      await t.tap(find.byKey(const Key('group-rename')));
      await t.pumpAndSettle();
      await t.enterText(find.byKey(const Key('group-rename-field')), 'Weekend Run');
      await t.tap(find.byKey(const Key('group-rename-save')));
      await t.pumpAndSettle();
      expect(actions.renamed, 'Weekend Run');

      // A member: make admin, then remove.
      await t.scrollUntilVisible(find.byKey(const Key('group-member-u-bala')), 120, scrollable: find.byType(Scrollable).first);
      await t.tap(find.byKey(const Key('group-member-u-bala')));
      await t.pumpAndSettle();
      expect(find.text('Make group admin'), findsOneWidget);
      await t.tap(find.byKey(const Key('group-member-admin')));
      await t.pumpAndSettle();
      expect(actions.admin, ('u-bala', true));
      await t.tap(find.byKey(const Key('group-member-u-bala')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('group-member-remove')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('group-member-remove-confirm')));
      await t.pumpAndSettle();
      expect(actions.removed, 'u-bala');
      expect(t.takeException(), isNull);

      // Leave.
      await t.scrollUntilVisible(find.byKey(const Key('group-leave')), 200, scrollable: find.byType(Scrollable).first);
      await t.tap(find.byKey(const Key('group-leave')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('group-leave-confirm')));
      await t.pumpAndSettle();
      expect(actions.left, 'g1');
      expect(find.text('page /chats'), findsOneWidget);
    });

    testWidgets('Group info (member): no rename, no remove; Add members opens the picker (font x$scale)', (t) async {
      await _pump(t, scale: scale, initial: '/chat/g1/info', routes: [
        GoRoute(path: '/chat/:id/info', builder: (_, s) => ChatInfoScreen(conversationId: s.pathParameters['id']!)),
      ], overrides: [
        conversationProvider('g1').overrideWith((ref) async => _group(admin: false)),
        groupMembersProvider('g1').overrideWith((ref) async => _members(adminId: _aiman.id)),
        sharedInChatProvider('g1').overrideWith((ref) async => const <Message>[]),
      ]);
      expect(find.byKey(const Key('group-rename')), findsNothing);
      await t.tap(find.byKey(const Key('group-member-u-chong')));
      await t.pumpAndSettle();
      expect(find.text('View profile'), findsOneWidget);
      expect(find.byKey(const Key('group-member-remove')), findsNothing);
      await t.tapAt(const Offset(10, 10));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('group-add-members')));
      await t.pumpAndSettle();
      expect(find.text('page /chat/g1/add'), findsOneWidget);
      expect(t.takeException(), isNull);
    });

    testWidgets('Club chat info: club roles, no leave, points to the club (font x$scale)', (t) async {
      await _pump(t, scale: scale, initial: '/chat/k-chat/info', routes: [
        GoRoute(path: '/chat/:id/info', builder: (_, s) => ChatInfoScreen(conversationId: s.pathParameters['id']!)),
      ], overrides: [
        conversationProvider('k-chat').overrideWith((ref) async => _clubChat(count: 5)),
        groupMembersProvider('k-chat').overrideWith((ref) async => _members(adminId: null)),
        sharedInChatProvider('k-chat').overrideWith((ref) async => const <Message>[]),
        clubMemberRolesProvider('k1').overrideWith((ref) async => {_aiman.id: 'owner', _bala.id: 'vp', _me: 'member'}),
      ]);
      expect(find.text('Persatuan Kereta Myvi Lembah Klang Selangor'), findsOneWidget);
      expect(find.text('Club chat · 5 members'), findsOneWidget);
      expect(find.text('President'), findsOneWidget);
      expect(find.text('VP'), findsOneWidget);
      expect(find.byKey(const Key('group-rename')), findsNothing);
      expect(find.byKey(const Key('group-add-members')), findsNothing);
      await t.scrollUntilVisible(find.text('Leave the club to leave this chat'), 200, scrollable: find.byType(Scrollable).first);
      expect(find.byKey(const Key('group-leave')), findsNothing);
      expect(t.takeException(), isNull);
    });

    testWidgets('Add members: friends already in are shown but not pickable (font x$scale)', (t) async {
      late _FakeGroupActions actions;
      await _pump(t, scale: scale, initial: '/chat/g1/info', routes: [
        GoRoute(path: '/chat/:id/info', builder: (_, s) => Scaffold(body: Builder(builder: (c) => TextButton(onPressed: () => c.push('/chat/g1/add'), child: const Text('open'))))),
        GoRoute(path: '/chat/:id/add', builder: (_, s) => AddGroupMembersScreen(conversationId: s.pathParameters['id']!)),
      ], overrides: [
        conversationProvider('g1').overrideWith((ref) async => _group()),
        groupMembersProvider('g1').overrideWith((ref) async => _members()),
        friendsProvider.overrideWith((ref) async => [_aiman, _bala, _dina, _long]),
        groupChatActionsProvider.overrideWith((ref) => actions = _FakeGroupActions(ref)),
      ]);
      await t.tap(find.text('open'));
      await t.pumpAndSettle();
      expect(find.text('Add members'), findsOneWidget);
      expect(find.text('Already in the group'), findsNWidgets(3));
      expect(find.text('95 spots left'), findsOneWidget);
      await t.tap(find.byKey(const Key('friend-pick-u-bala')));
      await t.pump();
      expect(t.widget<TextButton>(find.byKey(const Key('add-members-confirm'))).onPressed, isNull, reason: 'already in');
      await t.tap(find.byKey(const Key('friend-pick-u-dina')));
      await t.pump();
      expect(find.text('Add 1'), findsOneWidget);
      expect(t.takeException(), isNull);
      await t.tap(find.byKey(const Key('add-members-confirm')));
      await t.pumpAndSettle();
      expect(actions.added, ['u-dina']);
      expect(find.text('open'), findsOneWidget, reason: 'back to the group');
    });
  }
}
