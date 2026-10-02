import 'package:car_meet/core/theme/app_icons.dart';
import 'package:car_meet/core/theme/app_theme.dart';
import 'package:car_meet/features/profile/presentation/widgets/profile_header.dart';
import 'package:car_meet/features/social/domain/post.dart';
import 'package:car_meet/features/social/presentation/widgets/seen_tracker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _pump(WidgetTester t, Widget child, {double scale = 1}) async {
  t.view.physicalSize = const Size(1080, 2340); // a 393 x 851 phone
  t.view.devicePixelRatio = 2.75;
  addTearDown(t.view.reset);
  await t.pumpWidget(MaterialApp(
    theme: AppTheme.current,
    builder: (context, c) => MediaQuery(data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)), child: c!),
    home: Scaffold(body: child),
  ));
}

FeedPost _feed(String? reason) => FeedPost(
      post: Post(id: 'p', authorId: 'a', kind: PostKind.post, photoUrls: const [], coverAspect: 1, createdAt: DateTime(2026), likeCount: 0, commentCount: 0, voteCount: 0),
      likedByMe: false,
      savedByMe: false,
      reason: reason,
    );

void main() {
  for (final scale in [1.0, 1.3]) {
    testWidgets('profile tabs: labels centred in the strip and the whole strip is tappable (text x$scale)', (t) async {
      var selected = 0;
      late StateSetter set;
      await _pump(
        t,
        StatefulBuilder(builder: (context, setState) {
          set = setState;
          return CustomScrollView(slivers: [
            const SliverToBoxAdapter(child: SizedBox(height: 100)),
            SliverPersistentHeader(
              pinned: true,
              delegate: ProfileTabBar(tabs: const [(AppIcons.squaresFour, 'Posts'), (AppIcons.cards, 'Cards')], selected: selected, onSelect: (i) => set(() => selected = i)),
            ),
          ]);
        }),
        scale: scale,
      );
      expect(t.takeException(), isNull);
      final strip = t.getRect(find.byType(InkWell).last);
      expect(strip.height, closeTo(ProfileTabBar.height, 0.5), reason: 'the tap target is the full strip, not just the label');
      final label = t.getRect(find.text('Cards'));
      expect((label.center.dy - strip.center.dy).abs(), lessThan(2), reason: 'label sits in the middle (0.3.50 had it at the top)');

      // A thumb near the bottom edge, just above the underline, still switches.
      await t.tapAt(Offset(strip.center.dx, strip.bottom - 6));
      await t.pumpAndSettle();
      expect(selected, 1);
      await t.tapAt(Offset(t.getRect(find.byType(InkWell).first).center.dx, strip.top + 4));
      await t.pumpAndSettle();
      expect(selected, 0);
    });
  }

  test('why you are seeing this', () {
    expect(_feed(null).reasonText, isNull);
    expect(_feed('friend').reasonText, 'Posted by your friend');
    expect(_feed('club').reasonText, 'From your club');
    expect(_feed('nearby').reasonText, 'Near you');
    expect(_feed('make:honda').reasonText, 'You like Honda posts');
    expect(_feed('make:').reasonText, 'Suggested for you');
    expect(_feed('popular').reasonText, 'Popular with drivers right now');
    expect(_feed('for_you').reasonText, 'Suggested for you');
    // copyWith keeps it (likes patch the post in place).
    expect(_feed('nearby').copyWith(likedByMe: true).reasonText, 'Near you');
  });

  testWidgets('seen tracker counts posts that came on screen, once each', (t) async {
    final seen = <String>[];
    final scope = GlobalKey<SeenScopeState>();
    final scroll = ScrollController();
    addTearDown(scroll.dispose);
    await _pump(
      t,
      SeenScope(
        key: scope,
        onSeen: seen.addAll,
        child: ListView.builder(
          controller: scroll,
          itemCount: 40,
          itemBuilder: (_, i) => SeenMarker(postId: 'p$i', child: SizedBox(height: 200, child: Text('post $i'))),
        ),
      ),
    );
    await t.pump(const Duration(milliseconds: 500));
    // 851 px tall: 0-3 fully, 4 is 51 of 200 px (not half) -> not yet.
    expect(seen, ['p0', 'p1', 'p2', 'p3']);

    scroll.jumpTo(1000); // 5 .. 9 on screen
    await t.pump();
    await t.pump(const Duration(milliseconds: 500));
    expect(seen.toSet().containsAll(['p5', 'p6', 'p7', 'p8']), isTrue);
    expect(seen.contains('p20'), isFalse);

    scroll.jumpTo(0);
    await t.pump();
    await t.pump(const Duration(milliseconds: 500));
    expect(seen.where((id) => id == 'p0').length, 1, reason: 'once per feed session');

    scope.currentState!.reset(); // pull to refresh
    scroll.jumpTo(1);
    await t.pump();
    await t.pump(const Duration(milliseconds: 500));
    expect(seen.where((id) => id == 'p0').length, 2);
  });
}
