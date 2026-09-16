import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/friendly_error.dart';
import '../../map/presentation/widgets/car_marker.dart';
import '../application/friends_providers.dart';

/// Pick the colour a friend's car and dot use on the map (only for you).
/// Reached from the friend's profile ⋯ menu and from the map's friend list.
Future<void> showFriendColourSheet(BuildContext context, WidgetRef ref, {required String userId, required String name}) async {
  final current = ref.read(friendTagsProvider).value?[userId];
  final picked = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('$name on the map', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text('Their car and dot show in this colour, only for you.', style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary)),
            const SizedBox(height: 14),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (final e in kTagColors.entries)
                  GestureDetector(
                    onTap: () => Navigator.pop(ctx, e.key),
                    child: Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(color: e.value, shape: BoxShape.circle, border: Border.all(color: current == e.key ? AppColors.ink : Colors.transparent, width: 3)),
                      child: current == e.key ? const Icon(AppIcons.check, color: Colors.white, size: 20) : null,
                    ),
                  ),
                GestureDetector(
                  onTap: () => Navigator.pop(ctx, ''),
                  child: Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: AppColors.border, width: 2)),
                    child: Icon(AppIcons.x, size: 18, color: AppColors.textSecondary),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
  if (picked == null || !context.mounted) return;
  try {
    await ref.read(friendActionsProvider).setTag(userId, picked.isEmpty ? null : picked);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(picked.isEmpty ? 'Back to the default colour.' : 'Colour saved.')));
    }
  } catch (e) {
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e))));
  }
}
