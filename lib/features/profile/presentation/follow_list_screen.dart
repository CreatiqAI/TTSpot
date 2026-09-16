import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/friendly_error.dart';
import '../../../core/widgets/user_avatar.dart';
import '../../social/application/social_providers.dart';

class FollowListScreen extends ConsumerWidget {
  const FollowListScreen({super.key, required this.userId, required this.followers});
  final String userId;
  final bool followers;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = followers ? ref.watch(followersProvider(userId)) : ref.watch(followingListProvider(userId));
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(AppIcons.arrowLeft), onPressed: () => context.pop()),
        title: Text(followers ? 'Followers' : 'Following'),
      ),
      body: list.when(
        loading: () => const Center(child: CircularProgressIndicator(strokeWidth: 2)),
        error: (e, _) => Center(child: Text(friendlyError(e))),
        data: (people) => people.isEmpty
            ? Center(child: Text(followers ? 'No followers yet.' : 'Not following anyone yet.', style: TextStyle(color: AppColors.textSecondary)))
            : ListView.builder(
                itemCount: people.length,
                itemBuilder: (_, i) {
                  final p = people[i];
                  return ListTile(
                    leading: UserAvatar(url: p.avatarUrl, name: p.displayName ?? p.username, size: 44),
                    title: Text(p.username ?? '', style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text(p.displayName ?? ''),
                    onTap: () => context.push(Routes.profile(p.id)),
                  );
                },
              ),
      ),
    );
  }
}
