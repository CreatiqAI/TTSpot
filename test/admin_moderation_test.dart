import 'package:car_meet/core/supabase/supabase_client.dart';
import 'package:car_meet/core/theme/app_theme.dart';
import 'package:car_meet/features/admin/application/admin_moderation.dart';
import 'package:car_meet/features/admin/application/admin_providers.dart';
import 'package:car_meet/features/admin/presentation/admin_moderation_screen.dart';
import 'package:car_meet/features/admin/presentation/admin_queues_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

const _pub = 'https://x.supabase.co/storage/v1/object/public/post-photos/u-1';

/// What admin_moderation_queue returns: one flagged post (two photos) and one moment.
final _rows = <Map<String, dynamic>>[
  {
    'kind': 'post',
    'id': 'post-1',
    'author_id': 'u-1',
    'username': 'shah_alam_drifter_with_a_long_name',
    'display_name': 'Drifter',
    'avatar_url': null,
    'photo_urls': ['$_pub/posts/1.jpg', '$_pub/posts/2.jpg'],
    'is_video': false,
    'title': null,
    'caption': 'Night run with the boys, long caption so it has to wrap on a small phone at a bigger text size',
    'reason': 'Flagged: violence/graphic 0.81 (photo 2)',
    'categories': {
      'hits': ['violence/graphic'],
      'scores': {'violence/graphic': 0.81},
      'checked': 3,
      'failed': 0,
    },
    'created_at': '2026-10-05T01:00:00Z',
    'moderated_at': '2026-10-05T01:00:03Z',
  },
  {
    'kind': 'moment',
    'id': 'story-1',
    'author_id': 'u-2',
    'username': 'kl_nights',
    'display_name': null,
    'avatar_url': null,
    'photo_urls': ['$_pub/stories/1.jpg'],
    'is_video': true,
    'title': null,
    'caption': null,
    'reason': 'Flagged: sexual 0.77 (photo)',
    'categories': {
      'hits': ['sexual'],
    },
    'created_at': '2026-10-05T02:00:00Z',
    'moderated_at': '2026-10-05T02:00:02Z',
  },
];

class _FakeActions extends AdminModerationActions {
  _FakeActions(super.ref);
  final decisions = <String>[];
  @override
  Future<String?> decide(FlaggedItem item, {required bool approve}) async {
    decisions.add('${item.kind}:${item.id}:${approve ? 'ok' : 'removed'}');
    return approve ? 'ok' : 'removed';
  }
}

Future<void> _pump(WidgetTester t, Widget home, {required double scale, required List<Override> overrides}) async {
  t.view.physicalSize = const Size(1080, 2400); // 360 dp wide
  t.view.devicePixelRatio = 3;
  addTearDown(t.view.reset);
  await t.pumpWidget(ProviderScope(
    key: UniqueKey(),
    overrides: [currentUserIdProvider.overrideWith((ref) => 'admin-1'), ...overrides],
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

void main() {
  test('rows from admin_moderation_queue', () {
    final items = [for (final r in _rows) FlaggedItem.fromMap(r)];
    expect(items.first.isPost, isTrue);
    expect(items.first.photoUrls.length, 2);
    expect(items.first.hits, ['violence/graphic']);
    expect(items.last.kind, 'moment');
    expect(items.last.isVideo, isTrue);
    expect(items.last.createdAt.isUtc, isFalse);
  });

  for (final scale in const [1.0, 1.3]) {
    testWidgets('lists flagged posts and moments, photos blurred, no overflow ($scale)', (t) async {
      await _pump(t, const AdminModerationScreen(), scale: scale, overrides: [
        adminFlaggedProvider.overrideWith((ref) async => [for (final r in _rows) FlaggedItem.fromMap(r)]),
      ]);
      expect(find.text('Flagged posts'), findsOneWidget);
      expect(find.text('@shah_alam_drifter_with_a_long_name'), findsOneWidget);
      expect(find.text('Flagged: violence/graphic 0.81 (photo 2)'), findsOneWidget);
      expect(find.text('violence/graphic'), findsOneWidget);
      // Both photos of the first card start blurred.
      expect(find.descendant(of: find.byType(FlaggedCard).first, matching: find.text('Tap to show')), findsNWidgets(2));
      expect(find.text('Approve'), findsWidgets);
      expect(find.text('Remove'), findsWidgets);
      expect(t.takeException(), isNull);

      // Tap a photo: the card's photos show unblurred.
      await t.tap(find.byKey(const Key('flagged-photo-post-1-0')));
      await t.pump();
      expect(find.descendant(of: find.byType(FlaggedCard).first, matching: find.text('Tap to show')), findsNothing);
      await t.ensureVisible(find.text('@kl_nights'));
      await t.pump(const Duration(milliseconds: 100));
      expect(find.textContaining('Video moment'), findsOneWidget);
      expect(t.takeException(), isNull);
    });

    testWidgets('Approve and Remove (after confirming) go to admin_moderate ($scale)', (t) async {
      late _FakeActions actions;
      await _pump(t, const AdminModerationScreen(), scale: scale, overrides: [
        adminFlaggedProvider.overrideWith((ref) async => [for (final r in _rows) FlaggedItem.fromMap(r)]),
        adminModerationActionsProvider.overrideWith((ref) => actions = _FakeActions(ref)),
      ]);
      await t.tap(find.byKey(const Key('flagged-approve-post-1')));
      await t.pump(const Duration(milliseconds: 100));
      expect(actions.decisions, ['post:post-1:ok']);
      expect(find.text('Approved. Everyone can see it again.'), findsOneWidget);
      t.state<ScaffoldMessengerState>(find.byType(ScaffoldMessenger)).removeCurrentSnackBar();
      await t.pumpAndSettle();

      await t.ensureVisible(find.byKey(const Key('flagged-remove-story-1')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('flagged-remove-story-1')));
      await t.pumpAndSettle();
      expect(find.text('Remove this moment?'), findsOneWidget);
      // The sheet's red action, not the card's button behind it.
      await t.tap(find.descendant(of: find.byType(BottomSheet), matching: find.text('Remove')));
      await t.pump(const Duration(milliseconds: 400));
      expect(actions.decisions, ['post:post-1:ok', 'moment:story-1:removed']);
      expect(t.takeException(), isNull);
    });

    testWidgets('empty queue ($scale)', (t) async {
      await _pump(t, const AdminModerationScreen(), scale: scale, overrides: [adminFlaggedProvider.overrideWith((ref) async => const [])]);
      expect(find.text('Nothing flagged'), findsOneWidget);
      expect(t.takeException(), isNull);
    });

    testWidgets('Queues shows the flagged count first ($scale)', (t) async {
      await _pump(t, const AdminQueuesScreen(), scale: scale, overrides: [
        adminFlaggedProvider.overrideWith((ref) async => [for (final r in _rows) FlaggedItem.fromMap(r)]),
        adminStatsProvider.overrideWith((ref) async => const AdminStats({})),
        adminReportsProvider.overrideWith((ref) async => const []),
      ]);
      expect(find.text('Flagged posts and moments'), findsOneWidget);
      final row = find.ancestor(of: find.text('Flagged posts and moments'), matching: find.byType(ListTile));
      expect(find.descendant(of: row, matching: find.text('2')), findsOneWidget);
      expect(t.takeException(), isNull);
    });
  }
}
