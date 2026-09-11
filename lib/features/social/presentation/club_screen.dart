import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../../core/supabase/supabase_client.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/friendly_error.dart';
import '../../../core/widgets/event_list_tile.dart';
import '../../../core/widgets/primary_button.dart';
import '../../../core/widgets/user_avatar.dart';
import '../application/community_providers.dart';
import '../application/social_providers.dart';
import '../domain/post.dart';
import 'widgets/masonry_grid.dart';

class ClubScreen extends ConsumerWidget {
  const ClubScreen({super.key, required this.clubId});
  final String clubId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final club = ref.watch(clubProvider(clubId));
    final me = ref.watch(currentUserIdProvider);
    final isMember = ref.watch(isClubMemberProvider(clubId)).value ?? false;
    final members = ref.watch(clubMembersProvider(clubId)).value ?? const [];
    final events = ref.watch(clubEventsProvider(clubId)).value ?? const [];
    final posts = ref.watch(postsWhereProvider((column: 'club_id', value: clubId))).value ?? const <FeedPost>[];

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(AppIcons.arrowLeft), onPressed: () => context.pop()),
        title: Text(club.value?.handle == null ? '' : '@${club.value!.handle}'),
      ),
      body: club.when(
        loading: () => const Center(child: CircularProgressIndicator(strokeWidth: 2)),
        error: (e, _) => Center(child: Text(friendlyError(e))),
        data: (c) {
          if (c == null) return const Center(child: Text('This club no longer exists.'));
          final isOwner = c.ownerId == me;
          return RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(clubProvider(clubId));
              ref.invalidate(clubMembersProvider(clubId));
              ref.invalidate(clubEventsProvider(clubId));
              ref.invalidate(postsWhereProvider((column: 'club_id', value: clubId)));
              await ref.read(clubProvider(clubId).future);
            },
            child: ListView(
              padding: const EdgeInsets.only(bottom: 32),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          UserAvatar(url: c.avatarUrl, name: c.name, size: 86),
                          const SizedBox(width: 20),
                          Expanded(
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceAround,
                              children: [
                                _Stat(value: c.memberCount, label: 'members'),
                                _Stat(value: events.length, label: 'meets'),
                                _Stat(value: posts.length, label: 'posts'),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(c.name, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                      if ((c.description ?? '').trim().isNotEmpty) ...[const SizedBox(height: 3), Text(c.description!.trim(), style: const TextStyle(fontSize: 14, height: 1.4))],
                      if ((c.homeState ?? '').isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Row(children: [const Icon(AppIcons.mapPin, size: 15, color: AppColors.textSecondary), const SizedBox(width: 4), Text(c.homeState!, style: const TextStyle(fontSize: 13, color: AppColors.textSecondary))]),
                      ],
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Expanded(
                            child: isOwner
                                ? SecondaryButton(label: 'Owner', onPressed: null)
                                : isMember
                                    ? SecondaryButton(
                                        label: 'Joined',
                                        onPressed: () => _toggle(context, ref, isMember: true),
                                      )
                                    : PrimaryButton(label: 'Join club', onPressed: () => _toggle(context, ref, isMember: false)),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: SecondaryButton(
                              label: 'Post',
                              icon: AppIcons.cameraPlus,
                              onPressed: isMember || isOwner ? () => context.push(Routes.createPost(PostKind.post, clubId: clubId)) : null,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                if (members.isNotEmpty) ...[
                  const _Section('MEMBERS'),
                  SizedBox(
                    height: 84,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      children: [
                        for (final m in members)
                          GestureDetector(
                            onTap: () => context.push(Routes.profile(m.id)),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 6),
                              child: Column(
                                children: [
                                  UserAvatar(url: m.avatarUrl, name: m.displayName ?? m.username, size: 54),
                                  const SizedBox(height: 4),
                                  SizedBox(width: 60, child: Text(m.username ?? '', maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: const TextStyle(fontSize: 11))),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
                const _Section('MEETS'),
                if (events.isEmpty)
                  const Padding(padding: EdgeInsets.fromLTRB(16, 0, 16, 8), child: Text('No meets tagged to this club yet.', style: TextStyle(color: AppColors.textSecondary)))
                else
                  for (final e in events) EventListTile(event: e, onTap: () => context.push(Routes.event(e.id)), isOrganiser: e.organizerId == me),
                const _Section('POSTS'),
                if (posts.isEmpty)
                  const Padding(padding: EdgeInsets.fromLTRB(16, 0, 16, 8), child: Text('No posts yet.', style: TextStyle(color: AppColors.textSecondary)))
                else
                  MasonryGrid(items: posts),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _toggle(BuildContext context, WidgetRef ref, {required bool isMember}) async {
    try {
      await ref.read(communityActionsProvider).toggleClubMembership(clubId, isMember: isMember);
    } catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e))));
    }
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label});
  final int value;
  final String label;
  @override
  Widget build(BuildContext context) => Column(children: [Text('$value', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)), Text(label, style: const TextStyle(fontSize: 13))]);
}

class _Section extends StatelessWidget {
  const _Section(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Text(text, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 1, color: AppColors.textSecondary)),
      );
}
