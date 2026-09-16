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
      height: 158,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
        children: [
          _MomentCard(
            photoUrl: mineIndex >= 0 ? groups[mineIndex].stories.last.photoUrl : null,
            avatarUrl: myProfile?.avatarUrl,
            name: 'You',
            avatarName: myProfile?.displayName ?? myProfile?.username,
            when: mineIndex >= 0 ? groups[mineIndex].stories.last.createdAt : null,
            unseen: mineIndex >= 0 && !groups[mineIndex].allSeen,
            mine: true,
            onTap: () => mineIndex >= 0
                ? context.push(Routes.stories, extra: StoryViewerArgs(groups: groups, initialGroup: mineIndex))
                : context.push(Routes.createStory),
            onAdd: () => context.push(Routes.createStory),
          ),
          for (final i in others)
            _MomentCard(
              photoUrl: groups[i].stories.last.photoUrl,
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

class _MomentCard extends StatelessWidget {
  const _MomentCard({
    required this.photoUrl,
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
    const w = 98.0, h = 140.0;
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
              borderRadius: BorderRadius.circular(18),
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
                    child: UserAvatar(url: avatarUrl, name: avatarName, size: 26),
                  ),
                ),
                if (when != null)
                  Positioned(
                    right: 8,
                    top: 10,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.45), borderRadius: BorderRadius.circular(999)),
                      child: Text(count > 1 ? '$count · ${timeAgo(when!)}' : timeAgo(when!), style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700)),
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
                    style: TextStyle(color: empty ? AppColors.textPrimary : Colors.white, fontSize: 12.5, fontWeight: FontWeight.w800, height: 1.15),
                  ),
                ),
                if (empty)
                  const Center(child: Icon(AppIcons.cameraPlus, size: 30, color: AppColors.textSecondary)),
                if (mine && !empty)
                  Positioned(
                    right: 8,
                    bottom: 8,
                    child: GestureDetector(
                      onTap: onAdd,
                      child: Container(
                        width: 26,
                        height: 26,
                        decoration: BoxDecoration(color: AppColors.brand, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 2)),
                        child: const Icon(AppIcons.plus, size: 14, color: Colors.white),
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
