import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
import '../../application/auth_controller.dart';
import '../../data/auth_repository.dart';

/// Asks before logging out, then logs out. Returns true when it did.
///
/// The danger button sits on top and Cancel at the bottom, so a second tap
/// in the same spot (e.g. on the tab bar's profile icon, where menus end)
/// lands on Cancel, never on Log out.
Future<bool> confirmLogout(BuildContext context, WidgetRef ref) async {
  final handle = ref.read(currentProfileProvider).value?.username;
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
            Text(
              handle == null || handle.isEmpty ? 'Log out?' : 'Log out of @$handle?',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.textPrimary),
            ),
            const SizedBox(height: 6),
            Text(
              'You\'ll need your password or Apple sign-in to come back.',
              style: TextStyle(fontSize: 14, color: AppColors.textSecondary, height: 1.4),
            ),
            const SizedBox(height: 20),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: AppColors.danger, foregroundColor: Colors.white),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Log out'),
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
  if (ok != true) return false;
  await ref.read(authControllerProvider.notifier).signOut();
  return true;
}
