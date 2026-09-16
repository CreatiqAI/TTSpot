import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../../core/supabase/supabase_client.dart';
import '../../../core/theme/app_art.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/dates.dart';
import '../../../core/utils/friendly_error.dart';
import '../../../core/widgets/empty_state.dart';
import '../../auth/data/auth_repository.dart';
import '../application/social_providers.dart';
import '../domain/post.dart';
import 'story_viewer_screen.dart';

/// Every moment I ever posted, live or not. Only I can see this. Tap to play,
/// long-press to add to an album.
class MyMomentsScreen extends ConsumerWidget {
  const MyMomentsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(currentUserIdProvider);
    if (me == null) return const Scaffold();
    final all = ref.watch(myMomentsArchiveProvider);
    final profile = ref.watch(currentProfileProvider).value;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(AppIcons.arrowLeft), onPressed: () => context.pop()),
        title: const Text('My moments'),
        actions: [IconButton(tooltip: 'New album', icon: const Icon(AppIcons.images), onPressed: () => context.push(Routes.newAlbum))],
      ),
      body: all.when(
        loading: () => const Center(child: CircularProgressIndicator(strokeWidth: 2)),
        error: (e, _) => Center(child: Text(friendlyError(e))),
        data: (list) {
          if (list.isEmpty) {
            return EmptyState(art: AppArt.camera, title: 'No moments yet', subtitle: 'Snap one at a meet or a spot. Every moment you post is kept here for you.', actionLabel: 'New moment', onAction: () => context.push(Routes.createMoment()));
          }
          final live = list.where((s) => s.isLive).length;
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
                child: Row(
                  children: [
                    Text('${list.length} moment${list.length == 1 ? '' : 's'}', style: const TextStyle(fontWeight: FontWeight.w700)),
                    if (live > 0) ...[
                      const SizedBox(width: 8),
                      Container(width: 7, height: 7, decoration: const BoxDecoration(color: AppColors.brand, shape: BoxShape.circle)),
                      const SizedBox(width: 4),
                      Text('$live live', style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppColors.brand)),
                    ],
                    const Spacer(),
                    Text('Only you see this', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                  ],
                ),
              ),
              Expanded(
                child: GridView.builder(
                  padding: const EdgeInsets.fromLTRB(2, 0, 2, 24),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, mainAxisSpacing: 2, crossAxisSpacing: 2, childAspectRatio: 0.8),
                  itemCount: list.length,
                  itemBuilder: (_, i) {
                    final m = list[i];
                    return GestureDetector(
                      onTap: () {
                        if (profile == null) return;
                        context.push(Routes.stories, extra: StoryViewerArgs(groups: [StoryGroup(author: profile, stories: list, allSeen: true, label: 'My moments')], initialGroup: 0, initialIndex: i));
                      },
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          Image.network(m.photoUrl, fit: BoxFit.cover, errorBuilder: (_, _, _) => ColoredBox(color: AppColors.surfaceGray)),
                          if (m.isLive)
                            Positioned(left: 6, top: 6, child: Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), decoration: BoxDecoration(color: AppColors.brand, borderRadius: BorderRadius.circular(6)), child: const Text('LIVE', style: TextStyle(color: Colors.white, fontSize: 9.5, fontWeight: FontWeight.w800, letterSpacing: 0.5)))),
                          Positioned(
                            left: 6,
                            right: 6,
                            bottom: 6,
                            child: Text(m.whereLabel ?? relativeShort(m.createdAt), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 10.5, fontWeight: FontWeight.w700, shadows: [Shadow(blurRadius: 6, color: Colors.black)])),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
