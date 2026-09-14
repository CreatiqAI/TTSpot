import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../../core/supabase/supabase_client.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/dates.dart';
import '../../../core/utils/friendly_error.dart';
import '../../../core/widgets/user_avatar.dart';
import '../application/social_providers.dart';
import '../domain/album.dart';

/// Who looked at my moment.
Future<void> showMomentViewers(BuildContext context, String storyId) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (_) => Consumer(
      builder: (ctx, ref, _) {
        final viewers = ref.watch(storyViewersProvider(storyId));
        return SafeArea(
          child: SizedBox(
            height: MediaQuery.sizeOf(ctx).height * 0.5,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                  child: Text(viewers.value == null ? 'Viewers' : 'Viewers · ${viewers.value!.length}', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                ),
                Expanded(
                  child: viewers.when(
                    loading: () => const Center(child: CircularProgressIndicator(strokeWidth: 2)),
                    error: (e, _) => Center(child: Text(friendlyError(e))),
                    data: (list) => list.isEmpty
                        ? const Center(child: Text('No views yet. Friends see it on the Posts tab.', style: TextStyle(color: AppColors.textSecondary)))
                        : ListView.builder(
                            itemCount: list.length,
                            itemBuilder: (_, i) {
                              final v = list[i];
                              return ListTile(
                                leading: UserAvatar(url: v.profile.avatarUrl, name: v.profile.displayName ?? v.profile.username, size: 42),
                                title: Text(v.profile.displayName ?? '@${v.profile.username}', style: const TextStyle(fontWeight: FontWeight.w600)),
                                subtitle: Text('@${v.profile.username ?? ''} · ${timeAgo(v.viewedAt)}', style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                                onTap: () {
                                  Navigator.pop(ctx);
                                  context.push(Routes.profile(v.profile.id));
                                },
                              );
                            },
                          ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    ),
  );
}

/// Tick the albums this moment should be in. "New album" opens the editor.
Future<void> showAddToAlbum(BuildContext context, String storyId) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (_) => _AddToAlbum(storyId: storyId),
  );
}

class _AddToAlbum extends ConsumerWidget {
  const _AddToAlbum({required this.storyId});
  final String storyId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(currentUserIdProvider);
    final albums = me == null ? const <MomentAlbum>[] : (ref.watch(userAlbumsProvider(me)).value ?? const <MomentAlbum>[]);
    final inIds = ref.watch(albumsContainingProvider(storyId)).value ?? const <String>{};
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Padding(padding: EdgeInsets.fromLTRB(20, 0, 20, 8), child: Text('Add to album', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800))),
          if (albums.isEmpty)
            const Padding(padding: EdgeInsets.fromLTRB(20, 0, 20, 8), child: Text('No albums yet. Make one and this moment goes in.', style: TextStyle(color: AppColors.textSecondary))),
          for (final a in albums)
            ListTile(
              leading: SizedBox(
                width: 44,
                height: 44,
                child: ClipOval(child: a.coverUrl == null ? const ColoredBox(color: AppColors.surfaceGray) : Image.network(a.coverUrl!, fit: BoxFit.cover)),
              ),
              title: Text(a.name, style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text('${a.count} moment${a.count == 1 ? '' : 's'}', style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
              trailing: Icon(inIds.contains(a.id) ? AppIcons.checkCircleFill : AppIcons.checkCircle, color: inIds.contains(a.id) ? AppColors.brand : AppColors.textMuted),
              onTap: () async {
                try {
                  await ref.read(socialActionsProvider).toggleInAlbum(a.id, storyId, add: !inIds.contains(a.id));
                } catch (e) {
                  if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e))));
                }
              },
            ),
          ListTile(
            leading: const CircleAvatar(backgroundColor: AppColors.surfaceGray, child: Icon(AppIcons.plus, color: AppColors.textPrimary)),
            title: const Text('New album', style: TextStyle(fontWeight: FontWeight.w600)),
            onTap: () {
              Navigator.pop(context);
              context.push(Routes.newAlbumWith(storyId));
            },
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
