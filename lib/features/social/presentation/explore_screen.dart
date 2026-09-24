import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_art.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/friendly_error.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/utils/geo.dart';
import '../../map/application/map_providers.dart';
import '../../map/presentation/widgets/map_sheet.dart' show SpotRow;
import '../application/community_providers.dart';
import '../application/social_providers.dart';
import '../domain/club.dart';
import '../domain/post.dart';
import 'create_hub_sheet.dart';
import 'widgets/masonry_grid.dart';
import 'widgets/post_card.dart';
import 'widgets/stories_row.dart';
import '../../../core/widgets/brand_logo.dart';

/// Posts tab. "For you" is a RedNote-style grid of everything; "Following" is
/// an Instagram-style card feed of people you follow; "Spots" ranks places
/// worth a check-in. Stories sit on top of the first two.
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
            tabs: [Tab(text: 'For you'), Tab(text: 'Following'), Tab(text: 'Spots')],
          ),
        ),
        body: const TabBarView(children: [_ForYou(), _Following(), _Spots()]),
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

/// Live leader for this week (most-liked car post since Monday) + last week's winner.
class _Spots extends ConsumerWidget {
  const _Spots();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final spots = ref.watch(topSpotsProvider);
    final origin = ref.watch(mapOriginProvider);
    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(topSpotsProvider);
        await ref.read(topSpotsProvider.future);
      },
      child: spots.when(
        loading: () => const Center(child: CircularProgressIndicator(strokeWidth: 2)),
        error: (e, _) => Center(child: Text(friendlyError(e))),
        data: (list) => list.isEmpty
            ? const EmptyState(art: AppArt.pin, title: 'No spots yet', subtitle: 'Post a moment at a place and it becomes a spot.')
            : ListView.separated(
                padding: const EdgeInsets.only(bottom: 24),
                itemCount: list.length + 1,
                separatorBuilder: (_, i) => i == 0 ? const SizedBox.shrink() : const Divider(height: 1, indent: 92),
                itemBuilder: (_, i) {
                  if (i == 0) return _SpotsHeader(top: list.take(4).toList(), origin: origin);
                  final p = list[i - 1];
                  return SpotRow(place: p, distanceKm: distanceKm(origin, p.latLng), onTap: () => context.push(Routes.place(p.id)));
                },
              ),
      ),
    );
  }
}

/// Big cover cards for the top few spots, then the list continues below.
class _SpotsHeader extends StatelessWidget {
  const _SpotsHeader({required this.top, required this.origin});
  final List<Place> top;
  final LatLng origin;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 14, 16, 8),
          child: Text('Where the scene goes', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        ),
        SizedBox(
          height: 190,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: top.length,
            separatorBuilder: (_, _) => const SizedBox(width: 10),
            itemBuilder: (_, i) {
              final p = top[i];
              return GestureDetector(
                onTap: () => context.push(Routes.place(p.id)),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(AppRadius.lg),
                  child: SizedBox(
                    width: 250,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        if (p.coverUrl != null)
                          Image(image: CachedNetworkImageProvider(p.coverUrl!), fit: BoxFit.cover, errorBuilder: (_, _, _) => ColoredBox(color: AppColors.surfaceGray))
                        else
                          ColoredBox(color: AppColors.surfaceGray, child: Center(child: ArtIcon(p.kindArt, size: 64))),
                        const DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.transparent, Color(0xCC000000)]),
                          ),
                        ),
                        Positioned(
                          left: 12,
                          right: 12,
                          bottom: 12,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
                              const SizedBox(height: 2),
                              Text(
                                '${p.totalCheckins} check-ins · ${formatDistance(distanceKm(origin, p.latLng))}',
                                style: const TextStyle(color: Colors.white70, fontSize: 12.5, fontWeight: FontWeight.w500),
                              ),
                            ],
                          ),
                        ),
                        if (p.recommended)
                          Positioned(
                            left: 10,
                            top: 10,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(color: AppColors.warnColor, borderRadius: BorderRadius.circular(999)),
                              child: const Text('★ Recommended', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Colors.white)),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(16, 18, 16, 4),
          child: Text('ALL SPOTS', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 1, color: AppColors.textSecondary)),
        ),
      ],
    );
  }
}
