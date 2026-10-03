import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_icons.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/friendly_error.dart';
import '../../../../core/widgets/primary_button.dart';
import '../../application/social_providers.dart';
import '../../domain/follow.dart';

/// Tap on Follow / Following, Instagram style: Follow follows at once;
/// Following asks "Unfollow [name]?" in a small sheet first. Either way the
/// button flips straight away and flips back if the server says no.
Future<void> tapFollow(BuildContext context, WidgetRef ref, FollowTarget target, {required String name}) async {
  final following = ref.read(followProvider(target)).value;
  if (following == null) return;
  if (following) {
    final ok = await confirmUnfollow(context, name: name);
    if (!ok || !context.mounted) return;
  }
  try {
    await ref.read(followProvider(target).notifier).toggle();
  } catch (e) {
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e))));
  }
}

/// "Unfollow [name]?" with Unfollow on top and Cancel under it. True when
/// the member chose Unfollow.
Future<bool> confirmUnfollow(BuildContext context, {required String name}) async {
  final ok = await showModalBottomSheet<bool>(
    useRootNavigator: true, // above the shell tab bar
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Unfollow $name?', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
            const SizedBox(height: 6),
            Text('Their posts leave your Following feed.', style: TextStyle(fontSize: 14, color: AppColors.textSecondary, height: 1.4)),
            const SizedBox(height: 20),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: AppColors.danger, foregroundColor: Colors.white),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Unfollow'),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              style: TextButton.styleFrom(minimumSize: const Size.fromHeight(48)),
              child: Text('Cancel', style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
            ),
          ],
        ),
      ),
    ),
  );
  return ok == true;
}

/// Follow (grey, or red with [primary]) / Following (grey, with a tick) for a
/// club or partner page. Greyed out until we know which it is.
class FollowButton extends ConsumerWidget {
  const FollowButton({super.key, required this.target, required this.name, this.primary = false});
  final FollowTarget target;

  /// For the unfollow sheet: "Unfollow [name]?".
  final String name;

  /// Follow in brand red, as the page's main action.
  final bool primary;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final following = ref.watch(followProvider(target)).value;
    final onPressed = following == null ? null : () => tapFollow(context, ref, target, name: name);
    if (following == true) return SecondaryButton(label: 'Following', icon: AppIcons.check, onPressed: onPressed);
    return primary
        ? PrimaryButton(label: 'Follow', icon: AppIcons.plus, onPressed: onPressed)
        : SecondaryButton(label: 'Follow', icon: AppIcons.plus, onPressed: onPressed);
  }
}
