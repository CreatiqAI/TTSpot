import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/app_router.dart';
import '../../../../core/supabase/supabase_client.dart';
import '../../../../core/theme/app_icons.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/user_avatar.dart';
import '../../../auth/data/auth_repository.dart';
import '../../application/social_providers.dart';
import '../story_viewer_screen.dart';

/// Moments strip: "Your moment" first, then friends with live moments.
class StoriesRow extends ConsumerWidget {
  const StoriesRow({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final groups = ref.watch(storiesProvider).value ?? const [];
    final me = ref.watch(currentUserIdProvider);
    final myProfile = ref.watch(currentProfileProvider).value;
    final mineIndex = groups.indexWhere((g) => g.author.id == me);
    final others = [for (var i = 0; i < groups.length; i++) if (i != mineIndex) i];

    return SizedBox(
      height: 104,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        children: [
          _StoryBubble(
            label: 'You',
            avatarUrl: myProfile?.avatarUrl,
            name: myProfile?.displayName ?? myProfile?.username,
            ring: mineIndex >= 0 ? (groups[mineIndex].allSeen ? _Ring.seen : _Ring.unseen) : _Ring.none,
            showPlus: mineIndex < 0,
            onTap: () {
              if (mineIndex >= 0) {
                context.push(Routes.stories, extra: StoryViewerArgs(groups: groups, initialGroup: mineIndex));
              } else {
                context.push(Routes.createStory);
              }
            },
          ),
          for (final i in others)
            _StoryBubble(
              label: groups[i].author.username ?? '',
              avatarUrl: groups[i].author.avatarUrl,
              name: groups[i].author.displayName ?? groups[i].author.username,
              ring: groups[i].allSeen ? _Ring.seen : _Ring.unseen,
              onTap: () => context.push(Routes.stories, extra: StoryViewerArgs(groups: groups, initialGroup: i)),
            ),
        ],
      ),
    );
  }
}

enum _Ring { none, unseen, seen }

class _StoryBubble extends StatelessWidget {
  const _StoryBubble({required this.label, required this.avatarUrl, required this.name, required this.ring, required this.onTap, this.showPlus = false});
  final String label;
  final String? avatarUrl;
  final String? name;
  final _Ring ring;
  final VoidCallback onTap;
  final bool showPlus;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.only(right: 14),
        child: Column(
          children: [
            Stack(
              children: [
                Container(
                  width: 66,
                  height: 66,
                  padding: const EdgeInsets.all(2.5),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: ring == _Ring.unseen ? AppColors.storyGradient : null,
                    color: ring == _Ring.seen ? AppColors.border : (ring == _Ring.none ? Colors.transparent : null),
                  ),
                  child: Container(
                    padding: const EdgeInsets.all(2),
                    decoration: const BoxDecoration(shape: BoxShape.circle, color: AppColors.bg),
                    child: UserAvatar(url: avatarUrl, name: name, size: 56),
                  ),
                ),
                if (showPlus)
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: Container(
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(color: AppColors.primary, shape: BoxShape.circle, border: Border.all(color: AppColors.bg, width: 2)),
                      child: const Icon(AppIcons.plus, size: 14, color: Colors.white),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 5),
            SizedBox(
              width: 68,
              child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: const TextStyle(fontSize: 11.5)),
            ),
          ],
        ),
      ),
    );
  }
}
