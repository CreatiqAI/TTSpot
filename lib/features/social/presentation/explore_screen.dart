import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

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
import 'widgets/stories_row.dart';
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
      length: 3,
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
            tabs: [Tab(text: 'For you'), Tab(text: 'Following'), Tab(text: 'Garage')],
          ),
        ),
        body: const TabBarView(children: [_ForYou(), _Following(), GarageHomeTab()]),
      ),
    );
  }
}

class _ForYou extends ConsumerWidget {
  const _ForYou();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final feed = ref.watch(exploreFeedProvider);
    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(exploreFeedProvider);
        ref.invalidate(storiesProvider);
        await ref.read(exploreFeedProvider.future);
      },
      child: CustomScrollView(
        slivers: [
          const SliverToBoxAdapter(child: StoriesRow()),
          const SliverToBoxAdapter(child: Divider()),
          feed.when(
            loading: () => const SliverFillRemaining(hasScrollBody: false, child: Center(child: CircularProgressIndicator(strokeWidth: 2))),
            error: (e, _) => SliverFillRemaining(hasScrollBody: false, child: Center(child: Text(friendlyError(e)))),
            data: (list) => list.isEmpty
                ? SliverFillRemaining(
                    hasScrollBody: false,
                    child: EmptyState(
                      art: AppArt.camera,
                      title: 'Nothing here yet',
                      subtitle: 'Be the first to post your ride or spot one in the wild.',
                      actionLabel: 'Create a post',
                      onAction: () => context.push(Routes.createPost(PostKind.post)),
                    ),
                  )
                : SliverToBoxAdapter(child: MasonryGrid(items: list)),
          ),
        ],
      ),
    );
  }
}

class _Following extends ConsumerWidget {
  const _Following();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final feed = ref.watch(followingFeedProvider);
    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(followingFeedProvider);
        ref.invalidate(storiesProvider);
        await ref.read(followingFeedProvider.future);
      },
      child: CustomScrollView(
        slivers: [
          const SliverToBoxAdapter(child: StoriesRow()),
          const SliverToBoxAdapter(child: Divider()),
          feed.when(
            loading: () => const SliverFillRemaining(hasScrollBody: false, child: Center(child: CircularProgressIndicator(strokeWidth: 2))),
            error: (e, _) => SliverFillRemaining(hasScrollBody: false, child: Center(child: Text(friendlyError(e)))),
            data: (list) => list.isEmpty
                ? SliverFillRemaining(
                    hasScrollBody: false,
                    child: EmptyState(
                      art: AppArt.hug,
                      title: 'Follow some drivers',
                      subtitle: 'Posts from people you follow show up here.',
                      actionLabel: 'Find people',
                      onAction: () => context.push(Routes.search),
                    ),
                  )
                : SliverList.separated(
                    itemCount: list.length,
                    separatorBuilder: (_, _) => const Divider(),
                    itemBuilder: (_, i) => PostCard(feed: list[i], onOpen: () => context.push(Routes.post(list[i].post.id))),
                  ),
          ),
        ],
      ),
    );
  }
}
