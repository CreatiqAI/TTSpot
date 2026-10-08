import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:car_meet/core/push/in_app_notice.dart';
import 'package:car_meet/core/supabase/supabase_client.dart';
import 'package:car_meet/core/theme/app_icons.dart';
import 'package:car_meet/core/theme/app_theme.dart';
import 'package:car_meet/core/widgets/user_avatar.dart';
import 'package:car_meet/features/auth/data/auth_repository.dart';
import 'package:car_meet/features/auth/domain/profile.dart';
import 'package:car_meet/features/friends/application/friends_providers.dart';
import 'package:car_meet/features/safety/data/safety_repository.dart';
import 'package:car_meet/features/settings/application/settings_providers.dart';
import 'package:car_meet/features/settings/presentation/settings_screen.dart';
import 'package:car_meet/features/social/application/chat_providers.dart';
import 'package:car_meet/features/social/data/comment_repository.dart';
import 'package:car_meet/features/social/domain/chat.dart';
import 'package:car_meet/features/social/domain/comment_thread.dart';
import 'package:car_meet/features/social/domain/notification.dart';
import 'package:car_meet/features/social/presentation/activity_screen.dart';
import 'package:car_meet/features/social/presentation/comments/comment_composer.dart';
import 'package:car_meet/features/social/presentation/comments/comment_list.dart';
import 'package:car_meet/features/social/presentation/comments/comments_controller.dart';

// Comment replies, comment likes, @mentions and pings from clubs you follow
// (0.3.53, supabase/migrations/20261005000102_comments_mentions.sql).

Profile _p(String id, String handle, [String? name]) => Profile(id: id, username: handle, displayName: name, createdAt: DateTime(2026));

final _me = _p('me', 'titi_onboard1', 'TiTi Tester');
final _keith = _p('u-keith', 'keith_ek9', 'Keith Lim');
final _aiman = _p('u-aiman', 'aiman88', 'Aiman');
final _kenny = _p('u-kenny', 'kenny_fd2', 'Kenny Tan');
final _blocked = _p('u-blocked', 'kevin_bad', 'Kevin');
final _long = _p('u-long', 'a_really_long_handle', 'Muhammad Aiman Hakimi bin Abdul Rahman');

CommentItem _c(String id, Profile who, String body, {String? parent, int likes = 0, bool liked = false, int minute = 0}) => CommentItem(
      id: id,
      postId: 'p1',
      userId: who.id,
      body: body,
      createdAt: DateTime(2026, 10, 5, 9, minute),
      parentId: parent,
      author: who,
      likeCount: likes,
      likedByMe: liked,
    );

/// Comments kept in memory; threads replies like the server does.
class _FakeComments extends CommentRepository {
  // Never reaches the network; no token refresh timer left running.
  _FakeComments(this.items) : super(SupabaseClient('http://localhost', 'test-key', authOptions: const AuthClientOptions(autoRefreshToken: false)));

  final List<CommentItem> items;
  final added = <({String body, String? parentId})>[];
  final likes = <String>[];
  final unlikes = <String>[];
  final searched = <String>[];
  List<Profile> people = const [];
  bool failLikes = false;

  @override
  Future<List<CommentItem>> fetch(String postId, String? me) async => List.of(items);

  @override
  Future<void> add({required String postId, required String me, required String body, String? parentId}) async {
    added.add((body: body, parentId: parentId));
    String? top;
    if (parentId != null) {
      final parent = items.firstWhere((c) => c.id == parentId);
      top = parent.parentId ?? parent.id;
    }
    items.add(CommentItem(id: 'new${added.length}', postId: postId, userId: me, body: body, createdAt: DateTime(2026, 10, 5, 10, added.length), parentId: top, replyToId: parentId, author: _me));
  }

  @override
  Future<void> delete(String id) async => items.removeWhere((c) => c.id == id || c.parentId == id);

  @override
  Future<void> like(String commentId, String me) async {
    if (failLikes) throw Exception('No connection');
    likes.add(commentId);
  }

  @override
  Future<void> unlike(String commentId, String me) async {
    if (failLikes) throw Exception('No connection');
    unlikes.add(commentId);
  }

  @override
  Future<List<Profile>> searchPeople(String query, {int limit = 8}) async {
    searched.add(query);
    return people.where((p) => p.username!.startsWith(query.toLowerCase())).toList();
  }
}

List<CommentItem> _sample() => [
      _c('c1', _keith, 'Clean build, what wheels?', likes: 2, minute: 1),
      _c('r1', _aiman, '@keith_ek9 TE37s I think', parent: 'c1', minute: 2),
      _c('r2', _me, '@aiman88 yes TE37', parent: 'c1', likes: 1, liked: true, minute: 3),
      _c('c2', _aiman, 'See you at the meet Saturday', minute: 4),
      _c('r3', _keith, 'one', parent: 'c2', minute: 5),
      _c('r4', _kenny, 'two', parent: 'c2', minute: 6),
      _c('r5', _long, 'three, with a long reply that wraps onto a second line on a small phone screen', parent: 'c2', minute: 7),
      // Under a blocked person's comment: hidden with it.
      _c('r6', _keith, 'orphan reply', parent: 'c-gone', minute: 8),
    ];

Future<(_FakeComments, CommentsController)> _pumpComments(
  WidgetTester tester, {
  List<CommentItem>? items,
  String? highlight,
  double scale = 1.0,
  bool dark = false,
  double postHeight = 120,
}) async {
  AppColors.dark = dark;
  tester.view.physicalSize = const Size(360 * 3, 760 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  final repo = _FakeComments(items ?? _sample())..people = [_keith, _kenny, _blocked, _me];
  final controller = CommentsController(highlightId: highlight);
  addTearDown(controller.dispose);
  final router = GoRouter(routes: [
    GoRoute(
      path: '/',
      builder: (_, _) => Scaffold(
        body: Column(
          children: [
            Expanded(
              child: ListView(
                children: [
                  SizedBox(height: postHeight), // the post above the comments
                  Padding(padding: const EdgeInsets.fromLTRB(16, 12, 16, 16), child: CommentList(postId: 'p1', controller: controller)),
                ],
              ),
            ),
            CommentComposer(postId: 'p1', controller: controller),
          ],
        ),
      ),
    ),
    GoRoute(path: '/profile/:id', builder: (_, s) => Scaffold(body: Text('profile ${s.pathParameters['id']}'))),
  ]);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      currentUserIdProvider.overrideWithValue('me'),
      commentRepositoryProvider.overrideWithValue(repo),
      blockedUserIdsProvider.overrideWith((ref) async => {'u-blocked'}),
      friendsProvider.overrideWith((ref) async => [_aiman, _keith, _blocked]),
      currentProfileProvider.overrideWith((ref) async => _me),
    ],
    child: MaterialApp.router(
      theme: AppTheme.current,
      routerConfig: router,
      builder: (context, child) => MediaQuery(data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)), child: child!),
    ),
  ));
  await tester.pumpAndSettle();
  return (repo, controller);
}

AppNotification _n(NotificationType type, {String? body, String? postId, String? commentId, String? eventId, String? eventTitle, DateTime? starts, String? clubId, String? clubName, Profile? actor}) =>
    AppNotification(
      id: 'n-${type.name}',
      type: type,
      actor: actor ?? _aiman,
      body: body,
      postId: postId,
      commentId: commentId,
      eventId: eventId,
      eventTitle: eventTitle,
      eventStartsAt: starts,
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
  tearDown(() => AppColors.dark = false);

  group('threads', () {
    test('replies sit under their top-level comment, oldest first; orphans drop', () {
      final threads = buildThreads(_sample().reversed);
      expect(threads.map((t) => t.top.id), ['c1', 'c2']);
      expect(threads[0].replies.map((r) => r.id), ['r1', 'r2']);
      expect(threads[1].replies.map((r) => r.id), ['r3', 'r4', 'r5']);
      expect(threads[0].folds, isFalse, reason: 'two replies show open');
      expect(threads[1].folds, isTrue, reason: 'three fold behind View 3 replies');
      expect(repliesUnder('c2', _sample()), 3);
      expect(repliesUnder('r3', _sample()), 0);
    });

    test('a row from the server', () {
      final c = CommentItem.fromMap({
        'id': 'r9',
        'post_id': 'p1',
        'user_id': 'u-keith',
        'parent_id': 'c1',
        'reply_to_id': 'r1',
        'body': 'hi',
        'created_at': '2026-10-05T01:00:00Z',
        'profiles': {'id': 'u-keith', 'username': 'keith_ek9', 'created_at': '2026-01-01T00:00:00Z'},
        'post_comment_likes': [
          {'count': 4},
        ],
      }, likedByMe: true);
      expect(c.isReply, isTrue);
      expect(c.threadId, 'c1');
      expect(c.replyToId, 'r1');
      expect(c.likeCount, 4);
      expect(c.likedByMe, isTrue);
      expect(c.handle, 'keith_ek9');
      expect(CommentItem.fromMap({'id': 'c1', 'post_id': 'p1', 'user_id': 'u', 'body': 'x', 'created_at': '2026-10-05T01:00:00Z'}).likeCount, 0);
    });

    test('reply prefill: their @handle, nothing for my own comment', () {
      expect(replyPrefill(_c('c1', _keith, 'x'), me: 'me'), '@keith_ek9 ');
      expect(replyPrefill(_c('c1', _me, 'x'), me: 'me'), '');
    });
  });

  group('@ while typing', () {
    test('finds the handle being typed, not emails or links', () {
      expect(mentionAt('@', 1), (start: 0, query: ''));
      expect(mentionAt('hi @ke', 6), (start: 3, query: 'ke'));
      expect(mentionAt('hi @ke there', 6), (start: 3, query: 'ke'));
      expect(mentionAt('(@Keith', 7), (start: 1, query: 'Keith'));
      expect(mentionAt('hi @ke there', 12), isNull, reason: 'cursor past the handle');
      expect(mentionAt('mail keith@gmail', 16), isNull);
      expect(mentionAt('ttspot.my/@keith', 16), isNull);
      expect(mentionAt('@@keith', 7), isNull);
      expect(mentionAt('hi', 9), isNull);
    });

    test('picking someone swaps the typed part for their handle and a space', () {
      expect(insertMention('hi @ke', 3, 6, 'keith_ek9'), (text: 'hi @keith_ek9 ', cursor: 14));
      expect(insertMention('hi @ke there', 3, 6, 'keith_ek9'), (text: 'hi @keith_ek9 there', cursor: 14));
      expect(insertMention('@', 0, 1, 'aiman88'), (text: '@aiman88 ', cursor: 9));
    });
  });

  group('comments on the post page', () {
    for (final dark in [false, true]) {
      for (final scale in [1.0, 1.3]) {
        testWidgets('threads, hearts and the box fit a 360 dp phone (${dark ? 'dark' : 'light'}, font ×$scale)', (tester) async {
          await _pumpComments(tester, scale: scale, dark: dark);
          expect(find.textContaining('Clean build', findRichText: true), findsOneWidget);
          expect(find.textContaining('TE37s I think', findRichText: true), findsOneWidget, reason: 'two replies show open');
          expect(find.textContaining('yes TE37', findRichText: true), findsOneWidget);
          expect(find.text('View 3 replies'), findsOneWidget);
          expect(find.textContaining(RegExp(r'  one$'), findRichText: true), findsNothing, reason: 'three replies fold');
          expect(find.textContaining('orphan reply', findRichText: true), findsNothing);
          expect(find.text('Reply'), findsNWidgets(4));
          expect(tester.takeException(), isNull);

          await tester.ensureVisible(find.text('View 3 replies'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('View 3 replies'));
          await tester.pumpAndSettle();
          expect(find.textContaining('three, with a long reply', findRichText: true), findsOneWidget);
          expect(find.text('Hide replies'), findsOneWidget);
          expect(find.text('Reply'), findsNWidgets(7));

          // reply mode and suggestions at this size too
          await tester.ensureVisible(find.text('Reply').first);
          await tester.pumpAndSettle();
          await tester.tap(find.text('Reply').first);
          await tester.pumpAndSettle();
          await tester.enterText(find.byType(TextField), '@');
          await tester.pumpAndSettle();
          expect(find.text('Replying to @keith_ek9'), findsOneWidget);
          expect(find.byType(MentionSuggestions), findsOneWidget);
          expect(tester.takeException(), isNull);
        });
      }
    }

    testWidgets('a long thread folds behind View N replies and opens again', (tester) async {
      await _pumpComments(tester);
      await tester.ensureVisible(find.text('View 3 replies'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('View 3 replies'));
      await tester.pumpAndSettle();
      for (final t in ['one', 'two']) {
        expect(find.textContaining(RegExp('  $t\$'), findRichText: true), findsOneWidget);
      }
      // replies are indented under their parent
      final topLeft = tester.getTopLeft(find.byType(CommentTile).first).dx;
      final top = tester.widget<CommentTile>(find.byType(CommentTile).first);
      expect(top.comment.isReply, isFalse);
      final replyTile = find.ancestor(of: find.textContaining('  one', findRichText: true), matching: find.byType(CommentTile));
      final avatarX = tester.getTopLeft(find.descendant(of: replyTile, matching: find.byType(UserAvatar))).dx;
      expect(avatarX - topLeft, 44);
      await tester.ensureVisible(find.text('Hide replies'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Hide replies'));
      await tester.pumpAndSettle();
      expect(find.text('View 3 replies'), findsOneWidget);
      expect(find.textContaining('  two', findRichText: true), findsNothing);
    });

    testWidgets('Reply fills in @handle, threads the reply and keeps the thread open', (tester) async {
      final (repo, controller) = await _pumpComments(tester);
      // reply to a reply: the server files it under c1, the ping goes to Aiman
      final aimanReply = find.ancestor(of: find.textContaining('TE37s I think', findRichText: true), matching: find.byType(CommentTile));
      await tester.ensureVisible(aimanReply);
      await tester.pumpAndSettle();
      await tester.tap(find.descendant(of: aimanReply, matching: find.text('Reply')));
      await tester.pumpAndSettle();
      expect(find.text('Replying to @aiman88'), findsOneWidget);
      expect(controller.text.text, '@aiman88 ');
      await tester.enterText(find.byType(TextField), '@aiman88 thanks bro');
      await tester.tap(find.text('Post'));
      await tester.pumpAndSettle();
      expect(repo.added.single, (body: '@aiman88 thanks bro', parentId: 'r1'));
      expect(repo.items.last.parentId, 'c1');
      expect(find.text('Replying to @aiman88'), findsNothing);
      expect(controller.text.text, isEmpty);
      expect(find.textContaining('thanks bro', findRichText: true), findsOneWidget);

      // into the long thread: it opens and stays open with the new reply
      await tester.ensureVisible(find.textContaining('See you at the meet', findRichText: true));
      await tester.pumpAndSettle();
      final c2 = find.ancestor(of: find.textContaining('See you at the meet', findRichText: true), matching: find.byType(CommentTile));
      await tester.tap(find.descendant(of: c2, matching: find.text('Reply')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '@aiman88 count me in');
      await tester.tap(find.text('Post'));
      await tester.pumpAndSettle();
      expect(repo.added.last.parentId, 'c2');
      expect(find.text('Hide replies'), findsNWidgets(2), reason: 'both threads I replied in stay open');
      expect(find.textContaining('count me in', findRichText: true), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('return posts like Post (reply included) and closes the keyboard; an empty box posts nothing', (tester) async {
      final (repo, controller) = await _pumpComments(tester);
      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.textInputAction, TextInputAction.send);
      expect(field.keyboardType, TextInputType.text);

      await tester.enterText(find.byType(TextField), '   ');
      await tester.testTextInput.receiveAction(TextInputAction.send);
      await tester.pumpAndSettle();
      expect(repo.added, isEmpty);

      await tester.tap(find.text('Reply').first);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '@keith_ek9 TE37 for sure');
      await tester.testTextInput.receiveAction(TextInputAction.send);
      await tester.pumpAndSettle();
      expect(repo.added.single, (body: '@keith_ek9 TE37 for sure', parentId: 'c1'));
      expect(controller.text.text, isEmpty);
      expect(controller.focus.hasFocus, isFalse);
      expect(tester.testTextInput.hasAnyClients, isFalse);
      expect(tester.takeException(), isNull);
    });

    testWidgets('cancelling a reply clears an untouched @handle', (tester) async {
      final (repo, controller) = await _pumpComments(tester);
      await tester.tap(find.text('Reply').first);
      await tester.pumpAndSettle();
      expect(controller.text.text, '@keith_ek9 ');
      await tester.tap(find.byTooltip('Cancel reply'));
      await tester.pumpAndSettle();
      expect(controller.text.text, isEmpty);
      expect(find.text('Replying to @keith_ek9'), findsNothing);
      await tester.enterText(find.byType(TextField), 'top level');
      await tester.tap(find.text('Post'));
      await tester.pumpAndSettle();
      expect(repo.added.single, (body: 'top level', parentId: null));
    });

    testWidgets('a heart toggles at once with its count, and goes back if it fails', (tester) async {
      final (repo, _) = await _pumpComments(tester);
      Finder heartOf(String text) => find.descendant(
            of: find.ancestor(of: find.textContaining(text, findRichText: true), matching: find.byType(CommentTile)).first,
            matching: find.byWidgetPredicate((w) => w is Semantics && (w.properties.label ?? '').endsWith('ike comment')),
          );
      Finder countIn(String text, String count) => find.descendant(
            of: find.ancestor(of: find.textContaining(text, findRichText: true), matching: find.byType(CommentTile)).first,
            matching: find.text(count),
          );

      // Keith's comment: 2 likes, not mine yet
      expect(countIn('Clean build', '2'), findsOneWidget);
      await tester.tap(heartOf('Clean build'));
      await tester.pump();
      expect(countIn('Clean build', '3'), findsOneWidget);
      expect(find.descendant(of: heartOf('Clean build'), matching: find.byIcon(AppIcons.heartFill)), findsOneWidget);
      expect(repo.likes, ['c1']);
      await tester.tap(heartOf('Clean build'));
      await tester.pump();
      expect(countIn('Clean build', '2'), findsOneWidget);
      expect(repo.unlikes, ['c1']);

      // my reply was liked by me: unliking drops the count to nothing
      await tester.tap(heartOf('yes TE37'));
      await tester.pump();
      expect(countIn('yes TE37', '1'), findsNothing);
      expect(repo.unlikes, ['c1', 'r2']);

      repo.failLikes = true;
      await tester.tap(heartOf('See you at the meet'));
      await tester.pump();
      await tester.pumpAndSettle();
      expect(countIn('See you at the meet', '1'), findsNothing, reason: 'back to no likes');
      expect(find.byType(SnackBar), findsOneWidget);
    });

    testWidgets('@ suggests friends first, then search; picking one fills the handle', (tester) async {
      final (repo, controller) = await _pumpComments(tester);
      await tester.tap(find.byType(TextField));
      await tester.enterText(find.byType(TextField), 'nice @');
      await tester.pumpAndSettle();
      final list = find.byType(MentionSuggestions);
      expect(list, findsOneWidget);
      // friends only, without the blocked one; no search for a bare "@"
      expect(find.descendant(of: list, matching: find.text('Aiman')), findsOneWidget);
      expect(find.descendant(of: list, matching: find.text('Keith Lim')), findsOneWidget);
      expect(find.descendant(of: list, matching: find.text('Kevin')), findsNothing);
      expect(repo.searched, isEmpty);

      await tester.enterText(find.byType(TextField), 'nice @ke');
      await tester.pump(const Duration(milliseconds: 250));
      await tester.pumpAndSettle();
      // friend Keith first, then Kenny from search; never me or the blocked one
      final names = tester.widgetList<Text>(find.descendant(of: list, matching: find.byType(Text))).map((t) => t.data).toList();
      expect(names, ['Keith Lim', '@keith_ek9', 'Kenny Tan', '@kenny_fd2']);
      expect(repo.searched, ['ke']);

      await tester.tap(find.text('Kenny Tan'));
      await tester.pumpAndSettle();
      expect(controller.text.text, 'nice @kenny_fd2 ');
      expect(find.byType(MentionSuggestions), findsNothing);

      // an email address doesn't open suggestions
      await tester.enterText(find.byType(TextField), 'mail me keith@gm');
      await tester.pumpAndSettle();
      expect(find.byType(MentionSuggestions), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('opened from a notification: the comment shows, its folded thread opens', (tester) async {
      final (_, controller) = await _pumpComments(tester, highlight: 'r5', postHeight: 900);
      expect(find.textContaining('three, with a long reply', findRichText: true), findsOneWidget);
      expect(find.text('Hide replies'), findsOneWidget);
      final tile = find.ancestor(of: find.textContaining('three, with a long reply', findRichText: true), matching: find.byType(CommentTile));
      expect(tester.getRect(tile).overlaps(tester.getRect(find.byType(Scrollable).first)), isTrue, reason: 'scrolled into view');
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
      expect(controller.highlightId, isNull, reason: 'the tint fades');
      expect(find.text('Hide replies'), findsOneWidget, reason: 'and the thread stays open');
    });

    testWidgets('deleting a comment with replies says they go too', (tester) async {
      final (repo, _) = await _pumpComments(tester, items: [
        _c('c9', _me, 'my comment', minute: 1),
        _c('r9', _keith, 'reply one', parent: 'c9', minute: 2),
        _c('r10', _aiman, 'reply two', parent: 'c9', minute: 3),
      ]);
      await tester.longPress(find.textContaining('my comment', findRichText: true));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete comment'));
      await tester.pumpAndSettle();
      expect(find.text('Its 2 replies go too.'), findsOneWidget);
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      expect(repo.items, isEmpty);
      expect(find.text('No comments yet.'), findsOneWidget);
    });
  });

  group('Activity: wording and where a tap goes', () {
    final now = DateTime(2026, 10, 5, 20);
    test('mentions', () {
      expect(activityText(_n(NotificationType.mention, body: 'see you there @titi', postId: 'p1', commentId: 'c1')),
          ('mentioned you in a comment: see you there @titi', '/post/p1?comment=c1'));
      expect(activityText(_n(NotificationType.mention, body: 'Sunday run with @titi', postId: 'p1')), ('mentioned you in a post: Sunday run with @titi', '/post/p1'));
    });
    test('replies and comment likes open the post at the comment', () {
      expect(activityText(_n(NotificationType.commentReply, body: 'thanks!', postId: 'p1', commentId: 'r1')), ('replied to your comment: thanks!', '/post/p1?comment=r1'));
      expect(activityText(_n(NotificationType.commentLike, body: 'Nice car', postId: 'p1', commentId: 'c1')), ('liked your comment: Nice car', '/post/p1?comment=c1'));
      // post comments carry the comment now; older rows don't
      expect(activityText(_n(NotificationType.postComment, body: 'Nice', postId: 'p1', commentId: 'c2')).$2, '/post/p1?comment=c2');
      expect(activityText(_n(NotificationType.postComment, body: 'Nice', postId: 'p1')).$2, '/post/p1');
    });
    test('clubs you follow', () {
      expect(activityText(_n(NotificationType.clubPost, body: 'photo:Club night this Friday', postId: 'p2', clubId: 'k1', clubName: 'Myvi Klang')),
          ('posted: Club night this Friday', '/post/p2'));
      expect(activityText(_n(NotificationType.clubPost, body: 'video:', postId: 'p2')).$1, 'posted a new video.');
      expect(activityText(_n(NotificationType.clubMeet, eventId: 'e1', eventTitle: 'Saturday Night Meet', starts: DateTime(2026, 10, 6, 21, 30), clubId: 'k1'), now: now),
          ('planned Saturday Night Meet, tomorrow 9:30 PM.', '/event/e1'));
      expect(activityText(_n(NotificationType.clubMeet, body: 'Old Meet')).$1, 'planned Old Meet.');
      expect(isClubVoice(_n(NotificationType.clubMeet)), isTrue);
      expect(isClubVoice(_n(NotificationType.mention)), isFalse);
    });
    test('the new kinds parse, with the comment and the club logo', () {
      for (final (db, kind) in [
        ('mention', NotificationType.mention),
        ('comment_reply', NotificationType.commentReply),
        ('comment_like', NotificationType.commentLike),
        ('club_post', NotificationType.clubPost),
        ('club_meet', NotificationType.clubMeet),
      ]) {
        expect(NotificationType.fromDb(db), kind);
      }
      final n = AppNotification.fromMap({
        'id': 'n1',
        'type': 'club_post',
        'post_id': 'p1',
        'club_id': 'k1',
        'comment_id': null,
        'clubs': {'name': 'Myvi Klang', 'avatar_url': 'https://x/logo.png'},
        'created_at': '2026-10-05T01:00:00Z',
      });
      expect(n.clubName, 'Myvi Klang');
      expect(n.clubAvatarUrl, 'https://x/logo.png');
      expect(AppNotification.fromMap({'id': 'n2', 'type': 'comment_like', 'comment_id': 'c1', 'created_at': '2026-10-05T01:00:00Z'}).commentId, 'c1');
    });
  });

  group('Activity rows', () {
    List<AppNotification> rows() => [
          _n(NotificationType.mention, body: '@titi_onboard1 you coming to the Genting run this Sunday morning or not?', postId: 'p1', commentId: 'c1', actor: _long),
          _n(NotificationType.commentReply, body: 'TE37s for sure, the bronze ones look the best on a white car', postId: 'p1', commentId: 'r1'),
          _n(NotificationType.commentLike, body: 'Clean build, what wheels?', postId: 'p1', commentId: 'c2'),
          _n(NotificationType.clubPost, body: 'photo:Club night this Friday at the usual spot, bring your friends along', postId: 'p2', clubId: 'k1', clubName: 'Persatuan Kereta Myvi Lembah Klang Selangor'),
          _n(NotificationType.clubMeet, eventId: 'e1', eventTitle: 'Saturday Night Meet at Restoran Nasi Kandar Pelita', starts: DateTime.now().add(const Duration(days: 1)), clubId: 'k1', clubName: 'Myvi Klang'),
        ];

    Future<void> pumpRows(WidgetTester tester, {double scale = 1.0}) async {
      tester.view.physicalSize = const Size(360 * 3, 760 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final router = GoRouter(routes: [
        GoRoute(path: '/', builder: (_, _) => Scaffold(body: ListView(children: [for (final n in rows()) ActivityRow(n: n, badges: const [], me: 'me')]))),
        for (final p in ['post', 'event', 'club', 'profile'])
          GoRoute(
            path: '/$p/:id',
            builder: (_, s) {
              final where = '$p ${s.pathParameters['id']}${s.uri.queryParameters['comment'] == null ? '' : ' at ${s.uri.queryParameters['comment']}'}';
              return Scaffold(body: Text(where));
            },
          ),
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

    for (final dark in [false, true]) {
      for (final scale in [1.0, 1.3]) {
        testWidgets('new rows fit at 360 wide (${dark ? 'dark' : 'light'}, font ×$scale)', (tester) async {
          AppColors.dark = dark;
          await pumpRows(tester, scale: scale);
          expect(find.byType(ActivityRow), findsNWidgets(5));
          expect(find.textContaining('mentioned you in a comment:', findRichText: true), findsOneWidget);
          expect(find.textContaining('replied to your comment: TE37s', findRichText: true), findsOneWidget);
          expect(find.textContaining('liked your comment: Clean build', findRichText: true), findsOneWidget);
          // club rows lead with the club, not the member who posted
          expect(find.textContaining('Persatuan Kereta Myvi Lembah Klang Selangor posted: Club night', findRichText: true), findsOneWidget);
          expect(find.textContaining('Myvi Klang planned Saturday Night Meet', findRichText: true), findsOneWidget);
          expect(find.textContaining('aiman88 posted', findRichText: true), findsNothing);
          expect(tester.takeException(), isNull);
        });
      }
    }

    testWidgets('each row opens its page (comments scrolled to)', (tester) async {
      final expected = ['post p1 at c1', 'post p1 at r1', 'post p1 at c2', 'post p2', 'event e1'];
      for (var i = 0; i < expected.length; i++) {
        await pumpRows(tester);
        await tester.tap(find.byType(ActivityRow).at(i), warnIfMissed: false);
        await tester.pumpAndSettle();
        expect(find.text(expected[i]), findsOneWidget, reason: 'row $i');
      }
    });

    testWidgets('a club row avatar opens the club', (tester) async {
      await pumpRows(tester);
      final clubRow = find.byType(ActivityRow).at(3);
      await tester.tap(find.descendant(of: clubRow, matching: find.byType(UserAvatar)));
      await tester.pumpAndSettle();
      expect(find.text('club k1'), findsOneWidget);
    });
  });

  group('in-app banner', () {
    test('badges and tap targets', () {
      final cases = {
        'mention': (AppIcons.chatText, '/post/p1?comment=c1'),
        'comment_reply': (AppIcons.arrowBendUpLeft, '/post/p1?comment=r1'),
        'comment_like': (AppIcons.heartFill, '/post/p1?comment=c1'),
        'club_post': (AppIcons.image, '/post/p2'),
        'club_meet': (AppIcons.calendarCheck, '/event/e1'),
      };
      cases.forEach((kind, want) {
        final n = InAppNotice.fromPush({'kind': kind, 'title': 'Aiman', 'body': 'x', 'route': want.$2, 'sender_id': 'u1'})!;
        expect(n.badge, want.$1, reason: kind);
        expect(n.route, want.$2, reason: kind);
        expect(n.isChat, isFalse);
      });
    });
  });

  group('Settings switches', () {
    test('three new switches, on by default, each with its own key', () {
      const keys = {PushKind.mentions: 'notif_mentions', PushKind.replies: 'notif_replies', PushKind.clubFollows: 'notif_club_follows'};
      keys.forEach((k, key) {
        expect(k.key, key);
        expect(k.isOn(const AppSettings({})), isTrue, reason: '$key defaults on');
        expect(k.isOn(AppSettings({key: false})), isFalse, reason: '$key off');
        for (final other in PushKind.values.where((o) => o != k)) {
          expect(other.isOn(AppSettings({key: false})), isTrue, reason: '${other.key} untouched by $key');
        }
      });
      expect(PushKind.values.map((k) => k.key).toSet().length, PushKind.values.length);
      expect(PushKind.mentions.title, 'Mentions');
      expect(PushKind.replies.title, 'Replies and comment likes');
      expect(PushKind.clubFollows.title, 'Clubs you follow');
    });

    for (final scale in [1.0, 1.3]) {
      testWidgets('Push notifications screen: the new switches show, fit and save (font ×$scale)', (tester) async {
        tester.view.physicalSize = const Size(360 * 3, 700 * 3);
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

        for (final k in [PushKind.mentions, PushKind.replies, PushKind.clubFollows]) {
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
