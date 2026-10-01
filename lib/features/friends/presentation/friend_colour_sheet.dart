import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/friendly_error.dart';
import '../../map/presentation/widgets/car_marker.dart';
import '../application/friends_providers.dart';

/// Pick the colour a friend's car and dot use on the map (only for you): a
/// compact sheet with their name and twelve swatches. One tap applies it at
/// once (the map recolours behind the closing sheet) and saves it; a failed
/// save puts the old colour back with a message.
///
/// Reached by long-pressing their pin on the map, from the dot on their row
/// in the map's "On the map" list, and from their profile's ⋯ menu.
/// [defaultColor] is the colour "Default" goes back to (clubmate purple or
/// friend blue).
Future<void> showFriendColourSheet(BuildContext context, WidgetRef ref, {required String userId, required String name, Color? defaultColor}) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  final picked = await showModalBottomSheet<_Pick>(
    useRootNavigator: true, // above the shell tab bar
    context: context,
    showDragHandle: true,
    builder: (_) => _ColourSheet(userId: userId, name: name, defaultColor: defaultColor ?? kRelationFriend),
  );
  if (picked == null) return;
  try {
    await ref.read(friendTagsProvider.notifier).set(userId, picked.key);
  } catch (e) {
    messenger?.showSnackBar(SnackBar(content: Text('Couldn\'t save the colour. ${friendlyError(e)}')));
  }
}

/// The sheet's answer: a colour key, or null for the default.
class _Pick {
  const _Pick(this.key);
  final String? key;
}

class _ColourSheet extends ConsumerWidget {
  const _ColourSheet({required this.userId, required this.name, required this.defaultColor});
  final String userId;
  final String name;
  final Color defaultColor;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(friendTagsProvider).value?[userId];
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '$name on the map',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: AppColors.textPrimary),
            ),
            const SizedBox(height: 2),
            Text('Only you see this colour.', style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary)),
            const SizedBox(height: 14),
            // Six a row: two rows of swatches, sized to the sheet's width.
            LayoutBuilder(
              builder: (context, box) {
                const gap = 10.0;
                final side = ((box.maxWidth - gap * 5) / 6).clamp(32.0, 52.0);
                return Wrap(
                  spacing: gap,
                  runSpacing: gap,
                  children: [
                    for (final e in kTagColors.entries)
                      _Swatch(
                        color: e.value,
                        side: side,
                        selected: current == e.key,
                        tooltip: kTagColorLabels[e.key] ?? e.key,
                        onTap: () => Navigator.pop(context, _Pick(e.key)),
                      ),
                  ],
                );
              },
            ),
            const SizedBox(height: 12),
            // Back to the relationship's own colour.
            InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () => Navigator.pop(context, const _Pick(null)),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                child: Row(
                  children: [
                    Container(
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(
                        color: defaultColor,
                        shape: BoxShape.circle,
                        border: Border.all(color: current == null ? AppColors.textPrimary : AppColors.border, width: 2),
                      ),
                      child: current == null ? const Icon(AppIcons.check, size: 12, color: Colors.white) : null,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Default colour',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch({required this.color, required this.side, required this.selected, required this.tooltip, required this.onTap});
  final Color color;
  final double side;
  final bool selected;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        selected: selected,
        label: tooltip,
        child: GestureDetector(
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width: side,
            height: side,
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: selected ? AppColors.textPrimary : Colors.transparent, width: 2.5),
            ),
            child: DecoratedBox(
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              child: selected ? Icon(AppIcons.check, color: Colors.white, size: side * 0.42) : null,
            ),
          ),
        ),
      ),
    );
  }
}
