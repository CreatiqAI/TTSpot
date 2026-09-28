import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_art.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/friendly_error.dart';
import '../../../core/widgets/empty_state.dart';
import '../application/social_providers.dart';
import '../domain/post.dart';
import 'widgets/masonry_grid.dart';

/// Posts I kept, liked or commented on. Lives in the Me menu so the profile
/// itself stays about me and my cars.
class SavedPostsScreen extends ConsumerStatefulWidget {
  const SavedPostsScreen({super.key});

  @override
  ConsumerState<SavedPostsScreen> createState() => _SavedPostsScreenState();
}

class _SavedPostsScreenState extends ConsumerState<SavedPostsScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 3, vsync: this);

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
        title: const Text('Saved posts'),
        bottom: TabBar(
          controller: _tabs,
          labelColor: AppColors.textPrimary,
          unselectedLabelColor: AppColors.textSecondary,
          indicatorColor: AppColors.textPrimary,
          indicatorSize: TabBarIndicatorSize.tab,
          indicatorWeight: 1.5,
          dividerColor: AppColors.border,
          labelStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          tabs: const [Tab(text: 'Saved'), Tab(text: 'Liked'), Tab(text: 'Commented')],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          _List(provider: savedPostsProvider, art: AppArt.bookmark, title: 'Nothing saved', subtitle: 'Tap the bookmark on any post to keep it here.'),
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
