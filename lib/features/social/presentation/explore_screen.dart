import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/widgets/glass_tab_bar.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_art.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/friendly_error.dart';
import '../../../core/widgets/empty_state.dart';
import '../application/social_providers.dart';
import '../domain/post.dart';
import 'create_hub_sheet.dart';
import 'widgets/masonry_grid.dart';
import 'widgets/post_card.dart';
import '../../../core/widgets/brand_logo.dart';
import '../../profile/presentation/garage_home_tab.dart';

/// Home. "For you" is a RedNote-style grid of everything; "Following" is
/// an Instagram-style card feed of people you follow; "Garage" is my cars
/// and today's car. Stories sit on top of the first two. Spots live on the map.
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
            IconButton(tooltip: 'Create', icon: const Icon(AppIcons.plusCircle, size: 26), onPressed: () => showCreateHub(context, ref)),
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

/// One feed with a For you / Following switch (moments live in Chats). For you is
/// the discovery grid; Following is the people you follow, full width.
class _Feed extends ConsumerStatefulWidget {
  const _Feed();

  @override
  ConsumerState<_Feed> createState() => _FeedState();
}

class _FeedState extends ConsumerState<_Feed> {
  bool _following = false;

  @override
  Widget build(BuildContext context) {
    final forYou = ref.watch(exploreFeedProvider);
    final following = ref.watch(followingFeedProvider);
    final feed = _following ? following : forYou;
    return RefreshIndicator(
      onRefresh: () async {
        if (_following) {
          ref.invalidate(followingFeedProvider);
          await ref.read(followingFeedProvider.future);
        } else {
          ref.invalidate(exploreFeedProvider);
          await ref.read(exploreFeedProvider.future);
        }
      },
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
              child: Row(
                children: [
                  _FeedChip(label: 'For you', selected: !_following, onTap: () => setState(() => _following = false)),
                  const SizedBox(width: 8),
                  _FeedChip(label: 'Following', selected: _following, onTap: () => setState(() => _following = true)),
                ],
              ),
            ),
          ),
          feed.when(
            loading: () => const SliverFillRemaining(hasScrollBody: false, child: Center(child: CircularProgressIndicator(strokeWidth: 2))),
            error: (e, _) => SliverFillRemaining(hasScrollBody: false, child: Center(child: Text(friendlyError(e)))),
            data: (list) {
              if (list.isEmpty) {
                return SliverFillRemaining(
                  hasScrollBody: false,
                  child: _following
                      ? EmptyState(
                          art: AppArt.hug,
                          title: 'Follow some drivers',
                          subtitle: 'Posts from people you follow show up here.',
                          actionLabel: 'Find people',
                          onAction: () => context.push(Routes.search),
                        )
                      : EmptyState(
                          art: AppArt.camera,
                          title: 'Nothing here yet',
                          subtitle: 'Be the first to post your ride or spot one in the wild.',
                          actionLabel: 'Create a post',
                          onAction: () => context.push(Routes.createPost(PostKind.post)),
                        ),
                );
              }
              if (!_following) return SliverToBoxAdapter(child: MasonryGrid(items: list));
              return SliverList.separated(
                itemCount: list.length,
                separatorBuilder: (_, _) => const Divider(),
                itemBuilder: (_, i) => PostCard(feed: list[i], onOpen: () => context.push(Routes.post(list[i].post.id))),
              );
            },
          ),
          // Clear of the floating tab bar.
          SliverToBoxAdapter(child: SizedBox(height: GlassTabBar.clearance(context))),
        ],
      ),
    );
  }
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
