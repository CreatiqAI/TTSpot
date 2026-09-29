import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/app_art.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/friendly_error.dart';
import '../../../core/utils/geo.dart';
import '../../../core/widgets/empty_state.dart';
import '../../map/application/map_providers.dart';
import '../../map/presentation/widgets/map_sheet.dart' show SpotRow;
import '../application/community_providers.dart';
import '../application/social_providers.dart';
import '../domain/club.dart';
import '../domain/post.dart';
import 'widgets/masonry_grid.dart';

/// Posts I kept, spots I saved, posts I liked or commented on. Lives in the
/// Me menu so the profile itself stays about me and my cars.
class SavedPostsScreen extends ConsumerStatefulWidget {
  const SavedPostsScreen({super.key});

  @override
  ConsumerState<SavedPostsScreen> createState() => _SavedPostsScreenState();
}

class _SavedPostsScreenState extends ConsumerState<SavedPostsScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 4, vsync: this);

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(AppIcons.arrowLeft), onPressed: () => context.pop()),
        title: const Text('Saved'),
        bottom: TabBar(
          controller: _tabs,
          labelColor: AppColors.textPrimary,
          unselectedLabelColor: AppColors.textSecondary,
          indicatorColor: AppColors.textPrimary,
          indicatorSize: TabBarIndicatorSize.tab,
          indicatorWeight: 1.5,
          dividerColor: AppColors.border,
          labelStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          tabs: const [Tab(text: 'Posts'), Tab(text: 'Spots'), Tab(text: 'Liked'), Tab(text: 'Commented')],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          _List(provider: savedPostsProvider, art: AppArt.bookmark, title: 'Nothing saved', subtitle: 'Tap the bookmark on any post to keep it here.'),
          const _SavedSpots(),
          _List(provider: likedPostsProvider, art: AppArt.heartYellow, title: 'Nothing liked yet', subtitle: 'Double-tap a post to like it. It shows up here.'),
          _List(provider: commentedPostsProvider, art: AppArt.speech, title: 'No comments yet', subtitle: 'Posts you comment on collect here so you can find them again.'),
        ],
      ),
    );
  }
}

class _List extends ConsumerWidget {
  const _List({required this.provider, required this.art, required this.title, required this.subtitle});
  final FutureProvider<List<FeedPost>> provider;
  final String art;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ref.watch(provider).when(
          loading: () => const Center(child: CircularProgressIndicator(strokeWidth: 2)),
          error: (e, _) => Center(child: Text(friendlyError(e))),
          data: (list) => list.isEmpty ? EmptyState(art: art, title: title, subtitle: subtitle) : SingleChildScrollView(child: MasonryGrid(items: list)),
        );
  }
}

/// Spots I saved, newest first. They stay on my map on every layer; tap one
/// for its page, swipe it away or tap the bookmark to unsave.
class _SavedSpots extends ConsumerStatefulWidget {
  const _SavedSpots();

  @override
  ConsumerState<_SavedSpots> createState() => _SavedSpotsState();
}

class _SavedSpotsState extends ConsumerState<_SavedSpots> {
  /// Unsaved here and waiting on the server: hidden at once (a swiped-away
  /// row must leave the list in the same frame).
  final _gone = <String>{};

  Future<void> _unsave(Place p) async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _gone.add(p.id));
    try {
      await ref.read(communityActionsProvider).toggleSavePlace(p.id);
      // Once the fresh list is in (without it), stop hiding it: saving it again elsewhere shows it here.
      ref.read(savedPlacesProvider.future).then((_) {
        if (mounted) setState(() => _gone.remove(p.id));
      }, onError: (_) {});
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text('${p.name} removed from your saved spots.')));
    } catch (e) {
      if (mounted) setState(() => _gone.remove(p.id));
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(friendlyError(e))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final origin = ref.watch(mapOriginProvider);
    return ref.watch(savedPlacesProvider).when(
          loading: () => const Center(child: CircularProgressIndicator(strokeWidth: 2)),
          error: (e, _) => Center(child: Text(friendlyError(e))),
          data: (all) {
            final list = all.where((p) => !_gone.contains(p.id)).toList();
            return list.isEmpty
              ? const EmptyState(art: AppArt.map, title: 'No saved spots', subtitle: 'Tap Save spot on a spot\'s page. It stays on your map wherever you are.')
              : RefreshIndicator(
                  onRefresh: () => ref.refresh(savedPlacesProvider.future),
                  child: ListView.separated(
                    padding: const EdgeInsets.only(bottom: 32),
                    itemCount: list.length,
                    separatorBuilder: (_, _) => Divider(height: 1, indent: 92, color: AppColors.divider),
                    itemBuilder: (_, i) {
                      final p = list[i];
                      return Dismissible(
                        key: ValueKey('saved-spot-${p.id}'),
                        direction: DismissDirection.endToStart,
                        background: Container(
                          color: AppColors.surfaceGray,
                          alignment: Alignment.centerRight,
                          padding: const EdgeInsets.only(right: 24),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(AppIcons.bookmarkSimple, size: 20, color: AppColors.textSecondary),
                              const SizedBox(width: 6),
                              Text('Unsave', style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.textSecondary)),
                            ],
                          ),
                        ),
                        onDismissed: (_) => _unsave(p),
                        child: SpotRow(
                          place: p,
                          distanceKm: distanceKm(origin, p.latLng),
                          saved: true,
                          onTap: () => context.push(Routes.place(p.id)),
                          trailing: IconButton(
                            tooltip: 'Unsave',
                            icon: Icon(AppIcons.bookmarkSimpleFill, color: AppColors.textPrimary),
                            onPressed: () => _unsave(p),
                          ),
                        ),
                      );
                    },
                  ),
                );
          },
        );
  }
}
