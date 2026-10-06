import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/friendly_error.dart';
import '../../../core/widgets/primary_button.dart';
import '../../../core/widgets/sheet_header.dart';
import '../application/badges_providers.dart';
import '../domain/badges.dart';
import 'tier_badge_image.dart';

/// "Choose for profile": which of my badges (up to three, in tap order) show
/// in the honour row. [showAllLink] adds a way to the full badges page (from
/// the profile; the badges page itself leaves it out).
Future<void> showHonourPicker(BuildContext context, {required String userId, bool showAllLink = true}) {
  return showModalBottomSheet<void>(
    useRootNavigator: true, // above the shell tab bar
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheet) => HonourPickerSheet(
      userId: userId,
      onAll: showAllLink
          ? () {
              Navigator.pop(sheet);
              if (context.mounted) context.push(Routes.badges(userId));
            }
          : null,
    ),
  );
}

class HonourPickerSheet extends ConsumerStatefulWidget {
  const HonourPickerSheet({super.key, required this.userId, this.onAll});
  final String userId;
  final VoidCallback? onAll;

  @override
  ConsumerState<HonourPickerSheet> createState() => _HonourPickerSheetState();
}

class _HonourPickerSheetState extends ConsumerState<HonourPickerSheet> {
  List<String>? _picked;
  bool _saving = false;

  void _toggle(String id) {
    final picked = [...?_picked];
    if (picked.contains(id)) {
      picked.remove(id);
    } else if (picked.length < kHonourMax) {
      picked.add(id);
    } else {
      return;
    }
    setState(() => _picked = picked);
  }

  Future<void> _save(List<String> ids) async {
    setState(() => _saving = true);
    try {
      await ref.read(badgeActionsProvider).setHonour(ids);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final progress = ref.watch(badgeProgressProvider(widget.userId));
    final honour = ref.watch(honourBadgesProvider(widget.userId)).value;
    final earned = (progress.value ?? const <BadgeProgress>[]).where((b) => b.earned).toList();
    // Start from what the profile shows now, once both have loaded.
    if (_picked == null && honour != null && progress.hasValue) {
      _picked = honour.map((h) => h.id).where((id) => earned.any((b) => b.id == id)).toList();
    }
    final picked = _picked ?? const <String>[];

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.85),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SheetHeader(title: 'Choose for profile'),
              const SizedBox(height: 4),
              Text(
                'Up to 3. They show on your profile in the order you pick them.',
                style: TextStyle(fontSize: 13, color: AppColors.textSecondary, height: 1.35),
              ),
              const SizedBox(height: 10),
              Flexible(
                child: progress.isLoading && !progress.hasValue
                    ? const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator(strokeWidth: 2)))
                    : earned.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        child: Text('No badges yet. Your first post, meet or check-in earns one.', style: TextStyle(color: AppColors.textSecondary)),
                      )
                    : ListView(
                        shrinkWrap: true,
                        children: [
                          for (final b in earned)
                            _PickTile(
                              badge: b,
                              order: picked.indexOf(b.id),
                              full: picked.length >= kHonourMax,
                              onTap: _saving ? null : () => _toggle(b.id),
                            ),
                        ],
                      ),
              ),
              const SizedBox(height: 12),
              PrimaryButton(label: 'Save', loading: _saving, onPressed: _saving || earned.isEmpty || _picked == null ? null : () => _save(picked)),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Flexible(
                    child: TextButton(
                      onPressed: _saving || earned.isEmpty ? null : () => _save(const []),
                      child: const Text('Show my latest 3', maxLines: 1, overflow: TextOverflow.ellipsis),
                    ),
                  ),
                  if (widget.onAll != null)
                    Flexible(
                      child: TextButton(
                        onPressed: widget.onAll,
                        child: const Text('All badges', maxLines: 1, overflow: TextOverflow.ellipsis),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PickTile extends StatelessWidget {
  const _PickTile({required this.badge, required this.order, required this.full, required this.onTap});
  final BadgeProgress badge;

  /// Position in my pick (0-based), -1 when not picked.
  final int order;

  /// Three picked already: the others can't be added.
  final bool full;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final on = order >= 0;
    final blocked = !on && full;
    return InkWell(
      onTap: blocked ? null : onTap,
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: Opacity(
        opacity: blocked ? 0.45 : 1,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            children: [
              TierBadgeImage(id: badge.id, tier: badge.tier, size: 40),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(badge.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                    Text(badgeTierName(badge.tier), maxLines: 1, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: badgeTierColor(badge.tier))),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                width: 26,
                height: 26,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: on ? AppColors.textPrimary : Colors.transparent,
                  border: Border.all(color: on ? AppColors.textPrimary : AppColors.border, width: 1.5),
                ),
                child: on
                    ? Text('${order + 1}', textScaler: TextScaler.noScaling, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: AppColors.onInk))
                    : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
