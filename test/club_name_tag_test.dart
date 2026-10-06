import 'package:car_meet/core/supabase/supabase_client.dart';
import 'package:car_meet/core/theme/app_theme.dart';
import 'package:car_meet/features/auth/domain/profile.dart';
import 'package:car_meet/features/friends/application/nicknames.dart';
import 'package:car_meet/features/friends/presentation/nickname_sheet.dart' show ProfileNameLines;
import 'package:car_meet/features/safety/data/safety_repository.dart';
import 'package:car_meet/features/social/data/club_tag_repository.dart';
import 'package:car_meet/features/social/data/comment_repository.dart';
import 'package:car_meet/features/social/data/tags_repository.dart';
import 'package:car_meet/features/social/domain/club.dart';
import 'package:car_meet/features/social/domain/club_tag.dart';
import 'package:car_meet/features/social/domain/comment_thread.dart';
import 'package:car_meet/features/social/domain/post.dart';
import 'package:car_meet/features/social/domain/tags.dart';
import 'package:car_meet/features/social/presentation/comments/comment_list.dart';
import 'package:car_meet/features/social/presentation/comments/comments_controller.dart';
import 'package:car_meet/features/social/presentation/widgets/club_name_tag.dart';
import 'package:car_meet/features/social/presentation/widgets/club_tag_switch.dart';
import 'package:car_meet/features/social/presentation/widgets/post_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// The official club tag beside names (0.3.55, migration 0109; rules changed
// in 0.3.56, migration 0111). The server decides who wears one
// (club_tag_of): every member of an official club picks one of their clubs
// or none; a president who never picked wears their own; underground clubs
// never. These tests feed the widgets what the server answers in each case
// and check what shows, at text x1.0 and x1.3, light and dark.

SupabaseClient _offline() => SupabaseClient('http://localhost', 'test-key', authOptions: const AuthClientOptions(autoRefreshToken: false));

const _crewId = 'club-crew';

/// What `club_tag` holds for the president of an official club.
const _presidentJson = {'club_id': _crewId, 'name': 'TT Spot Crew', 'handle': 'ttspot_crew', 'avatar_url': null, 'role': 'owner'};

/// ... and for a member who opted in.
const _memberJson = {'club_id': _crewId, 'name': 'TT Spot Crew', 'handle': 'ttspot_crew', 'avatar_url': null, 'role': 'member'};

Profile _person(String id, String handle, {Map<String, dynamic>? tag, String? name}) =>
    Profile.fromMap({'id': id, 'username': handle, 'display_name': name, 'created_at': '2026-09-01T00:00:00Z', 'club_tag': ?tag});

/// The server's club_tag_of: who wears which tag. 'u-me' is me.
class _FakeTags extends ClubTagRepository {
  _FakeTags(Map<String, ClubTag?> tags) : tags = {...tags}, super(_offline());
  final Map<String, ClubTag?> tags;
  final sets = <(String, bool)>[];

  @override
  Future<ClubTag?> tagOf(String userId) async => tags[userId];

  @override
  Future<void> setWearing(String clubId, bool show) async {
    sets.add((clubId, show));
    // Taking off the tag that shows leaves none (0111).
    if (show) {
      tags['u-me'] = ClubTag(clubId: clubId, name: 'TT Spot Crew', role: tags['u-me']?.role ?? 'member');
    } else if (tags['u-me']?.clubId == clubId) {
      tags['u-me'] = null;
    }
  }
}

class _NoStats extends TagsRepository {
  _NoStats() : super(_offline());
  @override
  Future<Map<String, MyPostStats>> myPostStats(List<String> ids) async => const {};
}

class _FakeComments extends CommentRepository {
  _FakeComments(this.items) : super(_offline());
  final List<CommentItem> items;
  @override
  Future<List<CommentItem>> fetch(String postId, String? me) async => items;
}

Club _club({bool official = true}) => Club(
      id: _crewId,
      name: 'TT Spot Crew',
      handle: 'ttspot_crew',
      ownerId: 'u-boss',
      createdAt: DateTime(2026, 9, 1),
      memberCount: 2,
      tier: official ? 'official' : 'underground',
    );

Future<void> _pump(WidgetTester t, Widget body, {double scale = 1.0, bool dark = false, _FakeTags? tags, List<CommentItem> comments = const []}) async {
  AppColors.dark = dark;
  t.view.physicalSize = const Size(360 * 3, 760 * 3);
  t.view.devicePixelRatio = 3;
  addTearDown(t.view.reset);
  final router = GoRouter(routes: [
    GoRoute(path: '/', builder: (_, _) => Scaffold(body: SingleChildScrollView(child: body))),
    GoRoute(path: '/club/:id', builder: (_, s) => Scaffold(body: Text('club ${s.pathParameters['id']}'))),
    GoRoute(path: '/profile/:id', builder: (_, s) => Scaffold(body: Text('profile ${s.pathParameters['id']}'))),
  ]);
  addTearDown(router.dispose);
  await t.pumpWidget(ProviderScope(
    retry: (_, _) => null,
    overrides: [
      currentUserIdProvider.overrideWithValue('u-me'),
      nicknamesProvider.overrideWithValue(const <String, String>{}),
      blockedUserIdsProvider.overrideWith((ref) async => <String>{}),
      clubTagRepositoryProvider.overrideWithValue(tags ?? _FakeTags(const {})),
      tagsRepositoryProvider.overrideWithValue(_NoStats()),
      commentRepositoryProvider.overrideWithValue(_FakeComments(comments)),
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
  tearDown(() => AppColors.dark = false);

  group('ClubTag', () {
    test('reads the server json', () {
      final tag = ClubTag.fromJson(_presidentJson)!;
      expect(tag.clubId, _crewId);
      expect(tag.name, 'TT Spot Crew');
      expect(tag.isPresident, isTrue);
      expect(ClubTag.fromJson(_memberJson)!.isPresident, isFalse);
    });

    test('no tag, or not a tag: null', () {
      expect(ClubTag.fromJson(null), isNull);
      expect(ClubTag.fromJson('x'), isNull);
      expect(ClubTag.fromJson({'club_id': _crewId}), isNull);
      expect(ClubTag.fromJson({'club_id': _crewId, 'name': '  '}), isNull);
    });

    test('a profile row carries it only when the select asked for club_tag', () {
      expect(_person('u-boss', 'bigboss', tag: _presidentJson).clubTag?.name, 'TT Spot Crew');
      expect(_person('u-x', 'someone').clubTag, isNull);
      expect(_person('u-boss', 'bigboss', tag: _presidentJson).copyWith(bio: 'hi').clubTag, isNotNull);
    });
  });

  for (final dark in const [false, true]) {
    for (final scale in const [1.0, 1.3]) {
      final mode = '${dark ? 'dark' : 'light'}, x$scale';

      testWidgets('profile name line: official president shows the tag, others none ($mode)', (t) async {
        final boss = _person('u-boss', 'bigboss', name: 'Muhammad Aiman Hakimi bin Abdul Rahman');
        final member = _person('u-member', 'member_not_opted');
        final underground = _person('u-ug', 'underground_president');
        final tags = _FakeTags({'u-boss': ClubTag.fromJson(_presidentJson), 'u-member': null, 'u-ug': null});
        await _pump(
          t,
          Column(
            children: [
              for (final p in [boss, member, underground]) ProfileNameLines(profile: p, isMe: false, trailing: ClubNameTagFor(userId: p.id)),
            ],
          ),
          scale: scale,
          dark: dark,
          tags: tags,
        );
        expect(find.byKey(const ValueKey('club-tag-$_crewId')), findsOneWidget);
        expect(find.text('TT Spot Crew'), findsOneWidget);
        expect(t.takeException(), isNull);
      });

      testWidgets('post card author line: the tag beside the name, none without one ($mode)', (t) async {
        Post post(String id, Profile author) => Post(
              id: id,
              authorId: author.id,
              author: author,
              kind: PostKind.post,
              caption: 'Sunday run',
              photoUrls: const [],
              coverAspect: 1,
              createdAt: DateTime(2026, 10, 1),
              likeCount: 1,
              commentCount: 0,
              voteCount: 0,
            );
        final tagged = _person('u-boss', 'a_really_long_handle_for_a_president', tag: _presidentJson);
        final plain = _person('u-x', 'plain_member');
        await _pump(
          t,
          Column(
            children: [
              PostCard(feed: FeedPost(post: post('p1', tagged), likedByMe: false, savedByMe: false), expanded: true),
              PostCard(feed: FeedPost(post: post('p2', plain), likedByMe: false, savedByMe: false)),
            ],
          ),
          scale: scale,
          dark: dark,
        );
        expect(find.byKey(const ValueKey('club-tag-$_crewId')), findsOneWidget);
        expect(t.takeException(), isNull);
      });

      testWidgets('comments: the tag after the handle ($mode)', (t) async {
        CommentItem c(String id, Profile who) => CommentItem(id: id, postId: 'p1', userId: who.id, body: 'Clean build, see you Saturday at the meet', createdAt: DateTime(2026, 10, 5, 9), author: who);
        final ctrl = CommentsController();
        addTearDown(ctrl.dispose);
        await _pump(
          t,
          Padding(padding: const EdgeInsets.all(16), child: CommentList(postId: 'p1', controller: ctrl)),
          scale: scale,
          dark: dark,
          comments: [c('c1', _person('u-member', 'member_who_opted_in', tag: _memberJson)), c('c2', _person('u-x', 'plain_member'))],
        );
        expect(find.byKey(const ValueKey('club-tag-$_crewId')), findsOneWidget);
        expect(t.takeException(), isNull);
      });

      testWidgets('club page: a member opts in; the switch saves it ($mode)', (t) async {
        final tags = _FakeTags(const {});
        await _pump(t, ClubTagSwitch(club: _club(), isOwner: false), scale: scale, dark: dark, tags: tags);
        final tile = find.byKey(const Key('club-tag-switch'));
        expect(tile, findsOneWidget);
        expect(find.text('Show club tag on my name'), findsOneWidget);
        expect(t.widget<SwitchListTile>(tile).value, isFalse);
        await t.tap(tile);
        await t.pumpAndSettle();
        expect(tags.sets, [(_crewId, true)]);
        expect(t.widget<SwitchListTile>(tile).value, isTrue);
        expect(find.text('TT Spot Crew\'s tag now shows beside your name.'), findsOneWidget);
        expect(t.takeException(), isNull);
      });
    }
  }

  testWidgets('club page: a member who wears it can take it off', (t) async {
    final tags = _FakeTags({'u-me': ClubTag.fromJson(_memberJson)});
    await _pump(t, ClubTagSwitch(club: _club(), isOwner: false), tags: tags);
    final tile = find.byKey(const Key('club-tag-switch'));
    expect(t.widget<SwitchListTile>(tile).value, isTrue);
    await t.tap(tile);
    await t.pumpAndSettle();
    expect(tags.sets, [(_crewId, false)]);
    expect(t.widget<SwitchListTile>(tile).value, isFalse);
  });

  testWidgets('club page: wearing another club\'s tag, this switch is off', (t) async {
    final tags = _FakeTags({'u-me': const ClubTag(clubId: 'club-other', name: 'Other Official', role: 'member')});
    await _pump(t, ClubTagSwitch(club: _club(), isOwner: false), tags: tags);
    expect(t.widget<SwitchListTile>(find.byKey(const Key('club-tag-switch'))).value, isFalse);
  });

  // 0.3.56: the president is no longer forced to wear their club's tag.
  testWidgets('club page: the president wears it by default and can switch it off', (t) async {
    final tags = _FakeTags({'u-me': ClubTag.fromJson(_presidentJson)});
    await _pump(t, ClubTagSwitch(club: _club(), isOwner: true), tags: tags);
    final tile = find.byKey(const Key('club-tag-switch'));
    expect(tile, findsOneWidget);
    expect(find.byKey(const Key('club-tag-president')), findsNothing);
    expect(t.widget<SwitchListTile>(tile).value, isTrue);
    await t.tap(tile);
    await t.pumpAndSettle();
    expect(tags.sets, [(_crewId, false)]);
    expect(t.widget<SwitchListTile>(tile).value, isFalse);
    expect(find.text('Club tag off. No tag shows beside your name.'), findsOneWidget);
  });

  testWidgets('club page: underground clubs have no tag to wear', (t) async {
    await _pump(t, Column(children: [ClubTagSwitch(club: _club(official: false), isOwner: false), ClubTagSwitch(club: _club(official: false), isOwner: true)]));
    expect(find.byKey(const Key('club-tag-switch')), findsNothing);
    expect(find.text('Show club tag on my name'), findsNothing);
  });

  testWidgets('no tag: draws nothing', (t) async {
    await _pump(t, const Row(children: [Text('someone'), ClubNameTag(tag: null)]));
    expect(find.byType(GestureDetector), findsNothing);
  });

  testWidgets('tap the tag: what it means, and View club', (t) async {
    await _pump(t, Row(children: [const Text('bigboss'), ClubNameTag(tag: ClubTag.fromJson(_presidentJson))]));
    await t.tap(find.byKey(const ValueKey('club-tag-$_crewId')));
    await t.pumpAndSettle();
    expect(find.text('Official club · President'), findsOneWidget);
    await t.tap(find.text('View club'));
    await t.pumpAndSettle();
    expect(find.text('club $_crewId'), findsOneWidget);
  });

  testWidgets('a member\'s tag says Member', (t) async {
    await _pump(t, Row(children: [const Text('someone'), ClubNameTag(tag: ClubTag.fromJson(_memberJson))]));
    await t.tap(find.byKey(const ValueKey('club-tag-$_crewId')));
    await t.pumpAndSettle();
    expect(find.text('Official club · Member'), findsOneWidget);
  });
}
