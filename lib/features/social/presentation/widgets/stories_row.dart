import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/app_router.dart';
import '../../../../core/supabase/supabase_client.dart';
import '../../../../core/theme/app_icons.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/dates.dart';
import '../../../../core/widgets/glass.dart';
import '../../../../core/widgets/user_avatar.dart';
import '../../../auth/data/auth_repository.dart';
import '../../application/social_providers.dart';
import '../../domain/post.dart';
import '../story_viewer_screen.dart';

/// Moments shelf: tall photo cards (the moment itself is the face of the
/// card, not a ring around an avatar). Yours first, with a + to add.
class StoriesRow extends ConsumerWidget {
  const StoriesRow({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final groups = ref.watch(storiesProvider).value ?? const <StoryGroup>[];
    final me = ref.watch(currentUserIdProvider);
    final myProfile = ref.watch(currentProfileProvider).value;
    final mineIndex = groups.indexWhere((g) => g.author.id == me);
    final others = [for (var i = 0; i < groups.length; i++) if (i != mineIndex) i];

    return SizedBox(
      height: 132,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        children: [
          if (mineIndex >= 0)
            _MomentCard(
              photoUrl: groups[mineIndex].stories.last.photoUrl,
              video: groups[mineIndex].stories.last.isVideo,
              avatarUrl: myProfile?.avatarUrl,
              name: 'You',
              avatarName: myProfile?.displayName ?? myProfile?.username,
              when: groups[mineIndex].stories.last.createdAt,
              unseen: !groups[mineIndex].allSeen,
              mine: true,
              count: groups[mineIndex].stories.length,
              onTap: () => context.push(Routes.stories, extra: StoryViewerArgs(groups: groups, initialGroup: mineIndex)),
              onAdd: () => context.push(Routes.createStory),
            )
          else
            _AddCard(onTap: () => context.push(Routes.createStory)),
          for (final i in others)
            _MomentCard(
              photoUrl: groups[i].stories.last.photoUrl,
              video: groups[i].stories.last.isVideo,
              avatarUrl: groups[i].author.avatarUrl,
              name: (groups[i].author.displayName ?? groups[i].author.username ?? '').split(' ').first,
              avatarName: groups[i].author.displayName ?? groups[i].author.username,
              when: groups[i].stories.last.createdAt,
              unseen: !groups[i].allSeen,
              count: groups[i].stories.length,
              onTap: () => context.push(Routes.stories, extra: StoryViewerArgs(groups: groups, initialGroup: i)),
            ),
        ],
      ),
    );
  }
}

/// Compact "+" card when you have no live moment.
class _AddCard extends StatelessWidget {
  const _AddCard({required this.onTap});
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(right: 10),
        child: PressScale(
          scale: 0.95,
          child: GestureDetector(
            onTap: onTap,
            child: Container(
              width: 72,
              height: 116,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                color: AppColors.surfaceGray,
                border: Border.all(color: AppColors.border, width: 0.5),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: const BoxDecoration(color: AppColors.brand, shape: BoxShape.circle),
                    child: const Icon(AppIcons.plus, size: 18, color: Colors.white),
                  ),
                  const SizedBox(height: 8),
                  Text('Moment', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                ],
              ),
            ),
          ),
        ),
      );
}

class _MomentCard extends StatelessWidget {
  const _MomentCard({
    required this.photoUrl,
    this.video = false,
    required this.avatarUrl,
    required this.name,
    required this.avatarName,
    required this.when,
    required this.unseen,
    required this.onTap,
    this.mine = false,
    this.onAdd,
    this.count = 1,
  });
  final String? photoUrl;
  final bool video;
  final String? avatarUrl;
  final String name;
  final String? avatarName;
  final DateTime? when;
  final bool unseen;
  final bool mine;
  final int count;
  final VoidCallback onTap;
  final VoidCallback? onAdd;

  @override
  Widget build(BuildContext context) {
    const w = 84.0, h = 116.0;
    final empty = photoUrl == null;
    return Padding(
      padding: const EdgeInsets.only(right: 10),
      child: PressScale(
        scale: 0.95,
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            width: w,
            height: h,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              color: AppColors.surfaceGray,
              border: unseen ? Border.all(color: AppColors.brand, width: 2) : Border.all(color: AppColors.border, width: 0.5),
            ),
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (!empty) Image.network(photoUrl!, fit: BoxFit.cover),
                if (!empty)
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0x33000000), Color(0x00000000), Color(0xAA000000)], stops: [0, 0.45, 1]),
                    ),
                  ),
                // who
                Positioned(
                  left: 8,
                  top: 8,
                  child: Container(
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(shape: BoxShape.circle, color: empty ? AppColors.surfaceGray : Colors.white),
                    child: UserAvatar(url: avatarUrl, name: avatarName, size: 22),
                  ),
                ),
                if (video)
                  const Positioned(
                    right: 8,
                    bottom: 30,
                    child: Icon(AppIcons.play, size: 14, color: Colors.white),
                  ),
                if (when != null)
                  Positioned(
                    left: 8,
                    top: 34,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                      decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.45), borderRadius: BorderRadius.circular(999)),
                      child: Text(count > 1 ? '$count · ${timeAgo(when!)}' : timeAgo(when!), style: const TextStyle(color: Colors.white, fontSize: 9.5, fontWeight: FontWeight.w700)),
                    ),
                  ),
                // name
                Positioned(
                  left: 10,
                  right: 10,
                  bottom: 10,
                  child: Text(
                    empty ? 'Add a moment' : name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: empty ? AppColors.textPrimary : Colors.white, fontSize: 11.5, fontWeight: FontWeight.w800, height: 1.15),
                  ),
                ),
                if (empty)
                  Center(child: Icon(AppIcons.cameraPlus, size: 30, color: AppColors.textSecondary)),
                if (mine && !empty)
                  Positioned(
                    right: 8,
                    bottom: 8,
                    child: GestureDetector(
                      onTap: onAdd,
                      child: Container(
                        width: 22,
                        height: 22,
                        decoration: BoxDecoration(color: AppColors.brand, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 2)),
                        child: const Icon(AppIcons.plus, size: 12, color: Colors.white),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
