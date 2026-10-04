import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/widgets/glass_tab_bar.dart';
import '../../../core/widgets/pinch_zoom.dart';
import '../../../core/router/app_router.dart';
import '../../../core/router/tab_reselect.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_art.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/friendly_error.dart';
import '../../../core/widgets/empty_state.dart';
import '../application/share_ride.dart';
import '../application/social_providers.dart';
import '../domain/post.dart';
import 'widgets/masonry_grid.dart';
import 'widgets/not_interested_sheet.dart';
import 'widgets/post_card.dart';
import 'widgets/seen_tracker.dart';
import 'widgets/share_ride_card.dart';
import '../../../core/widgets/brand_logo.dart';
import '../../profile/presentation/garage_home_tab.dart';

/// Home. "For you" is a RedNote-style ranked grid; "Following" is an
/// Instagram-style card feed of friends, follows and clubs; "Garage" is my
/// cars and today's car. Spots live on the map.
class ExploreScreen extends ConsumerWidget {
  const ExploreScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          centerTitle: false,
          title: const BrandLogo(height: 56),
          actions: [
            IconButton(tooltip: 'Search', icon: const Icon(AppIcons.magnifyingGlass, size: 26), onPressed: () => context.push(Routes.search)),
            const SizedBox(width: 4),
          ],
          bottom: TabBar(
            labelColor: AppColors.textPrimary,
            unselectedLabelColor: AppColors.textSecondary,
            indicatorColor: AppColors.textPrimary,
            indicatorSize: TabBarIndicatorSize.tab,
            indicatorWeight: 1.5,
            dividerColor: AppColors.border,
            labelStyle: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            tabs: [Tab(text: 'Feed'), Tab(text: 'Garage')],
          ),
        ),
        body: const TabBarView(children: [_Feed(), GarageHomeTab()]),
      ),
    );
  }
}

/// One feed with a For you / Following switch (moments live in Chats).
/// For you is the ranked discovery grid (RedNote / Instagram style, loads
/// more as you scroll, long-press for "Not interested"); Following is
/// friends, people you follow and your clubs, newest first, then
/// "You're all caught up" and suggested posts, like Instagram.
class _Feed extends ConsumerStatefulWidget {
  const _Feed();

  @override
  ConsumerState<_Feed> createState() => _FeedState();
}

// Kept alive behind the Garage tab so it keeps its For you / Following choice and its place.
class _FeedState extends ConsumerState<_Feed> with AutomaticKeepAliveClientMixin {
  bool _following = false;
  final _refresh = GlobalKey<RefreshIndicatorState>();
  final _seen = GlobalKey<SeenScopeState>();

  @override
  bool get wantKeepAlive => true;

  /// Home tapped again: Feed tab, scroll to the top, then pull fresh posts.
  Future<void> _backToTop() async {
    final tabs = DefaultTabController.maybeOf(context);
    if (tabs != null && tabs.index != 0) tabs.animateTo(0);
    final scroll = PrimaryScrollController.maybeOf(context);
    if (scroll != null && scroll.hasClients) await scroll.animateTo(0, duration: const Duration(milliseconds: 400), curve: Curves.easeOutCubic);
    if (mounted) _refresh.currentState?.show();
  }

  Future<void> _reload() async {
    _seen.currentState?.reset();
    if (_following) {
      ref.invalidate(followingFeedProvider);
      await ref.read(followingFeedProvider.future);
    } else {
      ref.invalidate(forYouFeedProvider);
      ref.invalidate(shareRideCarProvider); // posted from the create screen meanwhile?
      await ref.read(forYouFeedProvider.future);
    }
  }

  /// Near the end of the grid: rank the next page.
  bool _onScroll(ScrollNotification n) {
    if (!_following && n.metrics.axis == Axis.vertical && n.metrics.extentAfter < 900) ref.read(forYouFeedProvider.notifier).loadMore();
    return false;
  }

  void _notInterested(FeedPost f) => showNotInterestedSheet(context, ref, f);

  @override
  Widget build(BuildContext context) {
    super.build(context);
    ref.listen(homeReselectProvider, (_, _) => _backToTop());
    final forYou = ref.watch(forYouFeedProvider);
    return SeenScope(
      key: _seen,
      onSeen: ref.read(feedSignalsProvider).seen,
      child: NotificationListener<ScrollNotification>(
        onNotification: _onScroll,
        child: RefreshIndicator(
          key: _refresh,
          onRefresh: _reload,
          child: CustomScrollView(
            primary: true, // Home-tap and the iOS status-bar tap both scroll it to the top
            physics: const PinchLockScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
                  // Wrap, not Row: never an overflow with very large text.
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _FeedChip(label: 'For you', selected: !_following, onTap: () => setState(() => _following = false)),
                      _FeedChip(label: 'Following', selected: _following, onTap: () => setState(() => _following = true)),
                    ],
                  ),
                ),
              ),
              // "Share your ride" until my first post (hides itself otherwise).
              if (!_following) SliverToBoxAdapter(child: ShareRideNudge()), // not const: it reads AppColors
              if (_following) _followingSlivers(forYou.value?.items ?? const []) else _forYouSlivers(forYou),
              // Clear of the floating tab bar.
              SliverToBoxAdapter(child: SizedBox(height: GlassTabBar.clearance(context))),
            ],
          ),
        ),
      ),
    );
  }

  Widget _forYouSlivers(AsyncValue<ForYouState> feed) {
    return feed.when(
      loading: () => const SliverFillRemaining(hasScrollBody: false, child: Center(child: CircularProgressIndicator(strokeWidth: 2))),
      error: (e, _) => SliverFillRemaining(hasScrollBody: false, child: Center(child: Text(friendlyError(e)))),
      data: (s) {
        if (s.items.isEmpty) {
          return SliverFillRemaining(
            hasScrollBody: false,
            child: EmptyState(
              art: AppArt.camera,
              title: 'Nothing here yet',
              subtitle: 'Be the first to post your ride or spot one in the wild.',
              actionLabel: 'Create a post',
              onAction: () => context.push(Routes.createPost(PostKind.post)),
            ),
          );
        }
        return SliverMainAxisGroup(
          slivers: [
            SliverToBoxAdapter(child: MasonryGrid(items: s.items, padding: const EdgeInsets.fromLTRB(8, 8, 8, 8), onLongPress: _notInterested)),
            SliverToBoxAdapter(
              child: s.done
                  ? const _FeedEnd(title: "You're all caught up", subtitle: 'Pull down for a fresh mix.')
                  : const Padding(padding: EdgeInsets.symmetric(vertical: 20), child: Center(child: CircularProgressIndicator(strokeWidth: 2))),
            ),
          ],
        );
      },
    );
  }

  Widget _followingSlivers(List<FeedPost> suggested) {
    final following = ref.watch(followingFeedProvider);
    return following.when(
      loading: () => const SliverFillRemaining(hasScrollBody: false, child: Center(child: CircularProgressIndicator(strokeWidth: 2))),
      error: (e, _) => SliverFillRemaining(hasScrollBody: false, child: Center(child: Text(friendlyError(e)))),
      data: (list) {
        final shown = {for (final f in list) f.post.id};
        final more = [for (final f in suggested) if (!shown.contains(f.post.id)) f].take(20).toList();
        return SliverMainAxisGroup(
          slivers: [
            if (list.isEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
                  child: EmptyState(
                    art: AppArt.hug,
                    title: 'Add some friends',
                    subtitle: 'Posts from your friends, your clubs and people you follow show up here.',
                    actionLabel: 'Find people',
                    onAction: () => context.push(Routes.search),
                  ),
                ),
              )
            else ...[
              SliverList.separated(
                itemCount: list.length,
                separatorBuilder: (_, _) => const Divider(),
                itemBuilder: (_, i) => SeenMarker(
                  postId: list[i].post.id,
                  child: PostCard(feed: list[i], onOpen: () => context.push(Routes.post(list[i].post.id))),
                ),
              ),
              const SliverToBoxAdapter(child: _FeedEnd(title: "You're all caught up", subtitle: "You've seen the new posts from your friends and clubs.")),
            ],
            if (more.isNotEmpty) ...[
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: Text('Suggested for you', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
                ),
              ),
              SliverToBoxAdapter(child: MasonryGrid(items: more, onLongPress: _notInterested)),
            ],
          ],
        );
      },
    );
  }
}

/// The end of a feed: a tick, a title, one line.
class _FeedEnd extends StatelessWidget {
  const _FeedEnd({required this.title, required this.subtitle});
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
        child: Column(
          children: [
            Icon(AppIcons.checkCircle, size: 36, color: AppColors.brand),
            const SizedBox(height: 8),
            Text(title, textAlign: TextAlign.center, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
            const SizedBox(height: 4),
            Text(subtitle, textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: AppColors.textSecondary, height: 1.35)),
          ],
        ),
      );
}

class _FeedChip extends StatelessWidget {
  const _FeedChip({required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          decoration: BoxDecoration(
            color: selected ? AppColors.textPrimary : AppColors.surfaceGray,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            label,
            style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: selected ? AppColors.bg : AppColors.textPrimary),
          ),
        ),
      );
}
