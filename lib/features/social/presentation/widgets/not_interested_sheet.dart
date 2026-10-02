import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/supabase/supabase_client.dart';
import '../../../../core/theme/app_icons.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/friendly_error.dart';
import '../../../safety/data/safety_repository.dart';
import '../../../safety/presentation/report_sheet.dart';
import '../../application/social_providers.dart';
import '../../domain/post.dart';

/// Who a post is from, as its tile shows it (club or partner, else @handle).
String postFace(Post p) => (p.asClub ? p.club?.name : null) ?? (p.asVendor ? p.vendor?.name : null) ?? '@${p.author?.username ?? 'user'}';

/// Long-press on a "For you" tile, like RedNote's "not interested": why the
/// post is there, Not interested, Fewer from this person, Report. Hiding
/// takes the post out at once, with Undo.
Future<void> showNotInterestedSheet(BuildContext context, WidgetRef ref, FeedPost f) async {
  if (f.post.authorId == ref.read(currentUserIdProvider)) return;
  final who = postFace(f.post);
  final why = f.reasonText;
  final choice = await showModalBottomSheet<String>(
    useRootNavigator: true, // above the shell tab bar
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (why != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(padding: const EdgeInsets.only(top: 1), child: Icon(AppIcons.info, size: 16, color: AppColors.textSecondary)),
                  const SizedBox(width: 8),
                  Expanded(child: Text('Why you\'re seeing this: $why', style: TextStyle(fontSize: 13, color: AppColors.textSecondary, height: 1.35))),
                ],
              ),
            ),
          ListTile(
            leading: const Icon(AppIcons.eyeSlash),
            title: const Text('Not interested'),
            subtitle: const Text('Show me fewer posts like this'),
            onTap: () => Navigator.pop(ctx, 'post'),
          ),
          ListTile(
            leading: const Icon(AppIcons.userMinus),
            title: Text('Fewer from $who', maxLines: 1, overflow: TextOverflow.ellipsis),
            onTap: () => Navigator.pop(ctx, 'author'),
          ),
          ListTile(leading: const Icon(AppIcons.flag), title: const Text('Report'), onTap: () => Navigator.pop(ctx, 'report')),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
  if (choice == null || !context.mounted) return;
  if (choice == 'report') {
    await showReportSheet(context, target: ReportTarget.post, targetId: f.post.id);
    return;
  }
  final messenger = ScaffoldMessenger.of(context);
  try {
    final undo = await ref.read(forYouFeedProvider.notifier).hide(f, author: choice == 'author');
    messenger.showSnackBar(SnackBar(
      content: Text(choice == 'author' ? "Got it. You'll see fewer posts from $who." : "Got it. You'll see fewer posts like this."),
      action: SnackBarAction(label: 'Undo', onPressed: () => undo().ignore()),
    ));
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text(friendlyError(e))));
  }
}
