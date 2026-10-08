import 'package:car_meet/core/supabase/supabase_client.dart';
import 'package:car_meet/core/theme/app_icons.dart';
import 'package:car_meet/core/theme/app_theme.dart';
import 'package:car_meet/features/auth/domain/profile.dart';
import 'package:car_meet/features/events/application/my_events_provider.dart';
import 'package:car_meet/features/friends/application/friends_providers.dart';
import 'package:car_meet/features/friends/application/nicknames.dart';
import 'package:car_meet/features/profile/application/profile_providers.dart';
import 'package:car_meet/features/profile/domain/car.dart';
import 'package:car_meet/features/safety/data/safety_repository.dart';
import 'package:car_meet/features/social/application/community_providers.dart';
import 'package:car_meet/features/social/application/social_providers.dart';
import 'package:car_meet/features/social/data/social_repository.dart';
import 'package:car_meet/features/social/data/tags_repository.dart';
import 'package:car_meet/features/social/domain/club.dart';
import 'package:car_meet/features/social/domain/post.dart';
import 'package:car_meet/features/social/domain/tags.dart';
import 'package:car_meet/features/social/presentation/create_post_screen.dart';
import 'package:car_meet/features/social/presentation/search_screen.dart';
import 'package:car_meet/features/social/presentation/tag_screen.dart';
import 'package:car_meet/features/social/presentation/widgets/caption_suggestions.dart';
import 'package:car_meet/features/social/presentation/widgets/masonry_grid.dart';
import 'package:car_meet/features/social/presentation/widgets/post_card.dart';
import 'package:car_meet/features/social/presentation/widgets/rich_caption.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// ------------------------------------------------------------- fakes ---

SupabaseClient _offline() => SupabaseClient('http://localhost', 'test-key', authOptions: const AuthClientOptions(autoRefreshToken: false));

const _me = 'u-me';

final _keith = Profile(id: 'u-keith', username: 'keith_ek9', displayName: 'Keith Lim', createdAt: DateTime(2026));
final _amir = Profile(id: 'u-amir', username: 'amir_gti', displayName: 'Amir', createdAt: DateTime(2026));
// Long names: the tile row and the caption have to fit at 360 dp.
final _longName = Profile(id: 'u-long', username: 'a_very_long_handle_x', displayName: 'Someone With A Long Name', createdAt: DateTime(2026));
final _myProfile = Profile(id: _me, username: 'my_own_long_handle_', displayName: 'Me', createdAt: DateTime(2026));

/// 45 #myvi posts; p0 is mine. No photos, so no network images.
final _posts = {
  for (var i = 0; i < 45; i++)
    'p$i': Post(
      id: 'p$i',
      authorId: i == 0 ? _me : _longName.id,
      author: i == 0 ? _myProfile : _longName,
      kind: PostKind.post,
      caption: 'Weekend run number $i with the crew #myvi #ttdi @keith_ek9',
      photoUrls: const [],
      coverAspect: 1,
      createdAt: DateTime(2026, 10, 1),
      likeCount: 12345,
      commentCount: 3,
      voteCount: 0,
    ),
};

class _FakeTags extends TagsRepository {
  _FakeTags() : super(_offline());
  final tagCalls = <(String, int)>[];
  final searchCalls = <(String, int)>[];
  final tagSearches = <String>[];
  final statsAsked = <String>[];

  static const _all = [TagCount(tag: 'myvi', posts: 12), TagCount(tag: 'myvi_gen3', posts: 4), TagCount(tag: 'jdm', posts: 40)];

  @override
  Future<({List<String> ids, int? total})> tagPosts(String tag, {int limit = 30, int offset = 0}) async {
    tagCalls.add((tag, offset));
    if (tag != 'myvi') return (ids: <String>[], total: offset == 0 ? 0 : null);
    final ids = [for (var i = offset; i < 45 && i < offset + limit; i++) 'p$i'];
    return (ids: ids, total: ids.isEmpty ? null : 45);
  }

  @override
  Future<List<String>> searchPosts(String q, {int limit = 30, int offset = 0}) async {
    searchCalls.add((q, offset));
    if (!'myvi'.startsWith(q.toLowerCase())) return const [];
    return [for (var i = offset; i < 6 && i < offset + limit; i++) 'p$i'];
  }

  @override
  Future<List<TagCount>> searchTags(String q, {int limit = 8}) async {
    tagSearches.add(q);
    return [for (final t in _all) if (t.tag.startsWith(q.toLowerCase())) t];
  }

  @override
  Future<Map<String, MyPostStats>> myPostStats(List<String> ids) async {
    statsAsked.addAll(ids);
    // The server answers for the author's own posts only.
    return {
      for (final id in ids)
        if (_posts[id]?.authorId == _me) id: const MyPostStats(views: 1234, saves: 12, likes: 40, comments: 3, shares: 3),
    };
  }
}

class _FakeSocial extends SocialRepository {
  _FakeSocial() : super(_offline());

  @override
  Future<List<Post>> fetchByIds(List<String> ids) async => [for (final id in ids) if (_posts.containsKey(id)) _posts[id]!];

  @override
  Future<List<FeedPost>> attachViewerState(List<Post> posts, String? me) async => [for (final p in posts) FeedPost(post: p, likedByMe: false, savedByMe: false)];

  @override
  Future<List<Profile>> searchProfiles(String query, {int limit = 20}) async =>
      [for (final p in [_keith, _amir]) if ((p.username ?? '').contains(query.toLowerCase())) p];

  @override
  Future<void> logViews(List<String> ids) async {}
}

/// Seen posts go nowhere (no 3 s upload timer left running).
class _NoSignals extends FeedSignals {
  _NoSignals(super.ref);
  @override
  void seen(Iterable<String> ids) {}
}

List _overrides(_FakeTags tags) => [
      nicknamesProvider.overrideWithValue(const <String, String>{}),
      currentUserIdProvider.overrideWithValue(_me),
      blockedUserIdsProvider.overrideWith((ref) async => <String>{}),
      tagsRepositoryProvider.overrideWithValue(tags),
      socialRepositoryProvider.overrideWithValue(_FakeSocial()),
      feedSignalsProvider.overrideWith(_NoSignals.new),
      clubsProvider.overrideWith((ref, q) async => const <Club>[]),
      placeSearchProvider.overrideWith((ref, q) async => const <Place>[]),
      userCarsProvider(_me).overrideWith((ref) async => [Car(id: 'c1', ownerId: _me, make: 'Perodua', model: 'Myvi', photoUrls: const [], createdAt: DateTime(2026))]),
      friendsProvider.overrideWith((ref) async => [_keith]),
    ];

/// A 360 x 800 phone (the narrowest we design for) at [scale], with a router
/// so pages can open tag pages.
Future<GoRouter> _pumpRouter(WidgetTester t, _FakeTags tags, String initial, {double scale = 1}) async {
  t.view.physicalSize = const Size(1080, 2400);
  t.view.devicePixelRatio = 3;
  addTearDown(t.view.reset);
  final router = GoRouter(initialLocation: initial, routes: [
    GoRoute(path: '/search', builder: (_, _) => const SearchScreen()),
    GoRoute(path: '/tag/:tag', builder: (_, s) => TagScreen(tag: s.pathParameters['tag']!)),
    GoRoute(path: '/post/:id', builder: (_, s) => Scaffold(body: Text('post ${s.pathParameters['id']}'))),
  ]);
  addTearDown(router.dispose);
  await t.pumpWidget(ProviderScope(
    retry: (_, _) => null,
    overrides: _overrides(tags).cast(),
    child: MaterialApp.router(
      theme: AppTheme.current,
      routerConfig: router,
      builder: (context, c) => MediaQuery(data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)), child: c!),
    ),
  ));
  return router;
}

Future<void> _pumpHome(WidgetTester t, _FakeTags tags, Widget home, {double scale = 1}) async {
  t.view.physicalSize = const Size(1080, 2400);
  t.view.devicePixelRatio = 3;
  addTearDown(t.view.reset);
  await t.pumpWidget(ProviderScope(
    retry: (_, _) => null,
    overrides: _overrides(tags).cast(),
    child: MaterialApp(
      theme: AppTheme.current,
      builder: (context, c) => MediaQuery(data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)), child: c!),
      home: home,
    ),
  ));
}

/// A few frames without waiting for spinners to stop.
Future<void> _settle(WidgetTester t) async {
  for (var i = 0; i < 6; i++) {
    await t.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  for (final scale in [1.0, 1.3]) {
    testWidgets('tag page: "#myvi · 45 posts", ranked grid, more on scroll, my view count (text x$scale)', (t) async {
      final tags = _FakeTags();
      await _pumpRouter(t, tags, '/tag/Myvi', scale: scale);
      await _settle(t);
      expect(t.takeException(), isNull);

      expect(find.text('#myvi'), findsOneWidget);
      expect(find.text(' · 45 posts'), findsOneWidget);
      expect(tags.tagCalls, [('myvi', 0)]);
      expect(find.byType(PostTile, skipOffstage: false), findsNWidgets(30));

      // Only my own post (p0) has the eye; nobody else's numbers are asked for.
      expect(find.byIcon(AppIcons.eye), findsOneWidget);
      expect(find.text('1.2k views'), findsOneWidget);
      expect(tags.statsAsked, ['p0']);

      await t.drag(find.byType(CustomScrollView), const Offset(0, -30000));
      await _settle(t);
      expect(tags.tagCalls, [('myvi', 0), ('myvi', 30)]);
      expect(find.byType(PostTile, skipOffstage: false), findsNWidgets(45));
      expect(find.byType(CircularProgressIndicator), findsNothing, reason: 'all 45 loaded: no more spinner');
      expect(t.takeException(), isNull);
    });

    testWidgets('search: debounced, matching tags open the tag page, Posts grid (text x$scale)', (t) async {
      final tags = _FakeTags();
      await _pumpRouter(t, tags, '/search', scale: scale);
      await _settle(t);
      // Nothing typed: popular tags to browse.
      expect(find.text('POPULAR TAGS'), findsOneWidget);
      expect(find.text('#jdm'), findsOneWidget);

      // Typing fast asks once, for what settled.
      await t.enterText(find.byType(TextField), 'm');
      await t.pump(const Duration(milliseconds: 100));
      await t.enterText(find.byType(TextField), 'my');
      await t.pump(const Duration(milliseconds: 100));
      await t.enterText(find.byType(TextField), 'myv');
      await t.pump(const Duration(milliseconds: 100));
      expect(tags.searchCalls, isEmpty);
      await t.pump(const Duration(milliseconds: 300));
      await _settle(t);
      expect(tags.searchCalls, [('myv', 0)]);
      expect(tags.tagSearches.where((q) => q.isNotEmpty), ['myv']);
      expect(t.takeException(), isNull);

      expect(find.text('TAGS'), findsOneWidget);
      expect(find.text('#myvi'), findsOneWidget);
      expect(find.text('12 posts'), findsOneWidget);
      expect(find.text('#myvi_gen3'), findsOneWidget);
      expect(find.text('POSTS'), findsOneWidget);
      expect(find.byType(PostTile, skipOffstage: false), findsNWidgets(6));
      expect(find.text('No results.'), findsNothing);

      await t.tap(find.text('#myvi'));
      await _settle(t);
      expect(find.text(' · 45 posts'), findsOneWidget, reason: 'the tag page opened');
      expect(t.takeException(), isNull);
    });

    testWidgets('search with no match says so (text x$scale)', (t) async {
      final tags = _FakeTags();
      await _pumpRouter(t, tags, '/search', scale: scale);
      await _settle(t);
      await t.enterText(find.byType(TextField), 'zzz');
      await t.pump(const Duration(milliseconds: 350));
      await _settle(t);
      expect(find.text('No results.'), findsOneWidget);
      expect(find.text('POSTS'), findsNothing);
      expect(t.takeException(), isNull);
    });

    testWidgets('composer: # suggests my cars then popular tags, @ suggests friends first; a tap completes (text x$scale)', (t) async {
      final tags = _FakeTags();
      final ctrl = TextEditingController();
      addTearDown(ctrl.dispose);
      await _pumpHome(
        t,
        tags,
        Scaffold(
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              CaptionAssist(
                controller: ctrl,
                child: TextField(controller: ctrl, maxLines: 6, minLines: 3, scrollPadding: kCaptionAssistScrollPadding),
              ),
            ],
          ),
        ),
        scale: scale,
      );
      await t.pump();

      await t.enterText(find.byType(TextField), 'Hello #');
      await t.pump(const Duration(milliseconds: 300));
      await _settle(t);
      expect(t.takeException(), isNull);
      // My Myvi first, then what others use.
      final chips = [
        for (final e in find.byWidgetPredicate((w) => w is Text && (w.data ?? '').startsWith('#')).evaluate()) (e.widget as Text).data,
      ];
      expect(chips, ['#perodua', '#myvi', '#myvi_gen3', '#jdm']);
      // Just above the keyboard (none in tests: the bottom of the screen).
      expect(t.getRect(find.text('#jdm')).bottom, greaterThan(740));

      await t.enterText(find.byType(TextField), 'Hello #my');
      await t.pump(const Duration(milliseconds: 300));
      await _settle(t);
      expect(find.text('#myvi'), findsOneWidget);
      expect(find.text('#myvi_gen3'), findsOneWidget);
      expect(find.text('#perodua'), findsNothing);
      expect(find.text('#jdm'), findsNothing);

      await t.tap(find.text('#myvi_gen3'));
      await t.pump();
      expect(ctrl.text, 'Hello #myvi_gen3 ');
      expect(ctrl.selection.baseOffset, ctrl.text.length);
      await _settle(t);
      expect(find.text('#myvi'), findsNothing, reason: 'the row goes once the word is done');

      await t.enterText(find.byType(TextField), 'Hello #myvi_gen3 with @');
      await t.pump(const Duration(milliseconds: 300));
      await _settle(t);
      expect(find.text('@keith_ek9'), findsOneWidget, reason: 'friends show before anything is typed');
      await t.enterText(find.byType(TextField), 'Hello #myvi_gen3 with @k');
      await t.pump(const Duration(milliseconds: 300));
      await _settle(t);
      expect(find.text('@keith_ek9'), findsOneWidget);
      await t.enterText(find.byType(TextField), 'Hello #myvi_gen3 with @a');
      await t.pump(const Duration(milliseconds: 300));
      await _settle(t);
      // Amir isn't a friend: he comes from the search once typing settles.
      expect(find.text('@amir_gti'), findsOneWidget);
      await t.tap(find.text('@amir_gti'));
      await t.pump();
      expect(ctrl.text, 'Hello #myvi_gen3 with @amir_gti ');
      expect(t.takeException(), isNull);
    });

    testWidgets('my own post page shows views, saves, shares; nobody else gets them (text x$scale)', (t) async {
      final tags = _FakeTags();
      final mine = FeedPost(post: _posts['p0']!, likedByMe: false, savedByMe: false);
      final theirs = FeedPost(post: _posts['p1']!, likedByMe: false, savedByMe: false);
      await _pumpHome(
        t,
        tags,
        Scaffold(
          body: SingleChildScrollView(
            child: Column(children: [PostCard(feed: mine, expanded: true), PostCard(feed: theirs, expanded: true), PostCard(feed: mine)]),
          ),
        ),
        scale: scale,
      );
      await _settle(t);
      expect(t.takeException(), isNull);
      expect(find.text('1,234 views · 12 saves · 3 shares'), findsOneWidget, reason: 'my post page only, not the feed card');
      expect(tags.statsAsked, ['p0']);
      // Captions are rich: the tag and the mention are links.
      expect(find.byType(RichCaption), findsNWidgets(3));
    });

    testWidgets('profile grid: an eye and the count on my tile only (text x$scale)', (t) async {
      final tags = _FakeTags();
      await _pumpHome(
        t,
        tags,
        Scaffold(
          body: SingleChildScrollView(
            child: MasonryGrid(items: [for (final id in ['p0', 'p1', 'p2', 'p3']) FeedPost(post: _posts[id]!, likedByMe: false, savedByMe: false)]),
          ),
        ),
        scale: scale,
      );
      await _settle(t);
      expect(t.takeException(), isNull);
      expect(find.byIcon(AppIcons.eye), findsOneWidget);
      expect(find.text('1.2k views'), findsOneWidget);
      expect(find.text('12345'), findsNWidgets(4), reason: 'likes still show on every tile');
      expect(tags.statsAsked, ['p0']);
    });
  }

  for (final scale in [1.0, 1.3]) {
    testWidgets('create post: the caption field suggests tags and people (text x$scale)', (t) async {
      final tags = _FakeTags();
      t.view.physicalSize = const Size(1080, 2400);
      t.view.devicePixelRatio = 3;
      addTearDown(t.view.reset);
      await t.pumpWidget(ProviderScope(
        retry: (_, _) => null,
        overrides: [
          ..._overrides(tags).cast(),
          myEventsProvider.overrideWith((ref) async => const MyEvents(upcoming: [], past: [])),
          myClubsProvider.overrideWith((ref) async => const <Club>[]),
        ],
        child: MaterialApp(
          theme: AppTheme.current,
          builder: (context, c) => MediaQuery(data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)), child: c!),
          // A poll: the only kind that doesn't open the photo picker first.
          home: const CreatePostScreen(kind: PostKind.poll),
        ),
      ));
      await _settle(t);
      expect(t.takeException(), isNull);
      final caption = find.byWidgetPredicate((w) => w is TextField && w.decoration?.labelText == 'Caption');
      expect(find.ancestor(of: caption, matching: find.byType(CaptionAssist)), findsOneWidget);
      expect(t.widget<TextField>(caption).scrollPadding, kCaptionAssistScrollPadding);

      await t.enterText(caption, 'Which exhaust? #my');
      await t.pump(const Duration(milliseconds: 300));
      await _settle(t);
      expect(find.text('#myvi'), findsOneWidget);
      await t.tap(find.text('#myvi'));
      await t.pump();
      expect(t.widget<TextField>(caption).controller!.text, 'Which exhaust? #myvi ');

      await t.enterText(caption, 'Which exhaust? #myvi ask @kei');
      await t.pump(const Duration(milliseconds: 300));
      await _settle(t);
      await t.tap(find.text('@keith_ek9'));
      await t.pump();
      expect(t.widget<TextField>(caption).controller!.text, 'Which exhaust? #myvi ask @keith_ek9 ');
      expect(t.takeException(), isNull);
    });
  }

  for (final scale in [1.0, 1.3]) {
    testWidgets('a tag with no posts invites the first one; a 30-letter tag fits (text x$scale)', (t) async {
      final tags = _FakeTags();
      const long = 'abcdefghijklmnopqrstuvwxyz1234';
      await _pumpRouter(t, tags, '/tag/$long', scale: scale);
      await _settle(t);
      expect(find.text('No #$long posts yet'), findsOneWidget);
      expect(find.text(' · 0 posts'), findsOneWidget);
      expect(t.takeException(), isNull);
    });
  }

  // Return: the search key runs the search at once and closes the keyboard;
  // the caption's return closes it instead of adding a line.
  bool typing() => FocusManager.instance.primaryFocus?.context?.findAncestorWidgetOfExactType<EditableText>() != null;

  testWidgets('search: the search key runs it now and closes the keyboard', (t) async {
    final tags = _FakeTags();
    await _pumpRouter(t, tags, '/search');
    await _settle(t);
    await t.enterText(find.byType(TextField), 'myv');
    expect(t.widget<TextField>(find.byType(TextField)).textInputAction, TextInputAction.search);
    await t.testTextInput.receiveAction(TextInputAction.search);
    await _settle(t);
    expect(tags.searchCalls, [('myv', 0)], reason: 'no wait for the debounce');
    expect(typing(), isFalse);
    expect(t.testTextInput.hasAnyClients, isFalse);
    await t.pump(const Duration(milliseconds: 400));
    expect(tags.searchCalls, [('myv', 0)], reason: 'the debounce was dropped, not run twice');
    expect(t.takeException(), isNull);
  });

  testWidgets('create post: return on the caption closes the keyboard, no new line', (t) async {
    final tags = _FakeTags();
    t.view.physicalSize = const Size(1080, 2400);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    await t.pumpWidget(ProviderScope(
      retry: (_, _) => null,
      overrides: [
        ..._overrides(tags).cast(),
        myEventsProvider.overrideWith((ref) async => const MyEvents(upcoming: [], past: [])),
        myClubsProvider.overrideWith((ref) async => const <Club>[]),
      ],
      child: MaterialApp(theme: AppTheme.current, home: const CreatePostScreen(kind: PostKind.poll)),
    ));
    await _settle(t);
    final caption = find.byWidgetPredicate((w) => w is TextField && w.decoration?.labelText == 'Caption');
    final field = t.widget<TextField>(caption);
    expect(field.textInputAction, TextInputAction.done);
    expect(field.keyboardType, TextInputType.text);
    expect(field.maxLines, greaterThan(1), reason: 'long captions still wrap onto more lines');

    await t.enterText(caption, 'Which exhaust for the weekend run?');
    await t.testTextInput.receiveAction(TextInputAction.done);
    await t.pump();
    expect(typing(), isFalse);
    expect(t.testTextInput.hasAnyClients, isFalse);
    expect(t.widget<TextField>(caption).controller!.text, 'Which exhaust for the weekend run?');
    expect(t.takeException(), isNull);
  });
}
