import 'package:flutter/material.dart';

import '../../../../core/theme/app_icons.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/user_avatar.dart';
import '../../../auth/domain/profile.dart';
import '../garage/garage_body.dart' show compactMoney;
import 'car_page_model.dart';

/// Under the studio: the real specs as chips, the description, whose car it
/// is (visitors), the numbers in one compact row, then the buttons: the
/// owner edits, makes it today's car (or posts) and opens the menu; a
/// visitor messages the owner or opens the menu (report).
class CarSummary extends StatelessWidget {
  const CarSummary({
    super.key,
    required this.data,
    required this.onEdit,
    required this.onMakeToday,
    required this.onPost,
    required this.onMore,
    required this.onMessage,
    required this.onOwner,
  });

  final CarPageData data;
  final VoidCallback onEdit;
  final VoidCallback onMakeToday;
  final VoidCallback onPost;
  final VoidCallback? onMore;
  final VoidCallback onMessage;
  final VoidCallback onOwner;

  @override
  Widget build(BuildContext context) {
    final d = data;
    final specs = carSpecs(d.car);
    final description = (d.car.description ?? '').trim();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (specs.isNotEmpty) ...[
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final s in specs)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(color: AppColors.surfaceGray, borderRadius: BorderRadius.circular(AppRadius.pill)),
                    child: Text(s.value, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                  ),
              ],
            ),
            const SizedBox(height: 12),
          ],
          if (description.isNotEmpty) ...[
            Text(description, style: TextStyle(fontSize: 15, height: 1.45, color: AppColors.textPrimary)),
            const SizedBox(height: 14),
          ],
          if (!d.mine) ...[
            CarOwnerRow(ownerId: d.car.ownerId, owner: d.owner, onTap: onOwner),
            const SizedBox(height: 12),
          ],
          CarStatsCard(data: d),
          const SizedBox(height: 12),
          Row(
            children: d.mine
                ? [
                    Expanded(child: _PageButton(label: 'Edit car', icon: AppIcons.pencilSimple, filled: true, onTap: onEdit)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: d.car.isDefault
                          ? _PageButton(label: 'Post about it', onTap: onPost)
                          : _PageButton(label: 'Make today\'s car', onTap: onMakeToday),
                    ),
                    if (onMore != null) ...[
                      const SizedBox(width: 8),
                      _SquareButton(icon: AppIcons.dotsThree, label: 'More', onTap: onMore!),
                    ],
                  ]
                : [
                    Expanded(
                      child: _PageButton(
                        label: 'Message owner',
                        icon: AppIcons.chatCircle,
                        brand: true,
                        onTap: d.messaging ? null : onMessage,
                      ),
                    ),
                    if (onMore != null) ...[
                      const SizedBox(width: 8),
                      _SquareButton(icon: AppIcons.dotsThree, label: 'More', onTap: onMore!),
                    ],
                  ],
          ),
        ],
      ),
    );
  }
}

/// A 46 px button: ink (filled), brand red, or grey. A long label shrinks.
class _PageButton extends StatelessWidget {
  const _PageButton({required this.label, required this.onTap, this.icon, this.filled = false, this.brand = false});
  final String label;
  final VoidCallback? onTap;
  final IconData? icon;
  final bool filled;
  final bool brand;

  @override
  Widget build(BuildContext context) {
    final bg = brand ? AppColors.brand : (filled ? AppColors.textPrimary : AppColors.surfaceGray);
    final fg = brand ? Colors.white : (filled ? AppColors.onInk : AppColors.textPrimary);
    return Semantics(
      button: true,
      enabled: onTap != null,
      child: Material(
        color: onTap == null ? bg.withValues(alpha: 0.6) : bg,
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 46),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Center(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (icon != null) ...[Icon(icon, size: 17, color: fg), const SizedBox(width: 6)],
                      Text(label, maxLines: 1, softWrap: false, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: fg)),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The grey square ⋯ next to the buttons.
class _SquareButton extends StatelessWidget {
  const _SquareButton({required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: label,
        excludeSemantics: true,
        child: Tooltip(
          message: label,
          child: Material(
            color: AppColors.surfaceGray,
            borderRadius: BorderRadius.circular(12),
            clipBehavior: Clip.antiAlias,
            child: InkWell(onTap: onTap, child: SizedBox(width: 46, height: 46, child: Icon(icon, size: 20, color: AppColors.textPrimary))),
          ),
        ),
      );
}

/// Mods · Spent (owner only) · Meets · Posts, in one compact row.
class CarStatsCard extends StatelessWidget {
  const CarStatsCard({super.key, required this.data});
  final CarPageData data;

  @override
  Widget build(BuildContext context) {
    final mods = data.mods;
    final spent = mods?.fold<double>(0, (s, m) => s + (m.cost ?? 0));
    final cells = <(String?, String)>[
      (mods?.length.toString(), 'Mods'),
      if (data.mine) (spent == null ? null : (spent > 0 ? 'RM ${compactMoney(spent)}' : '–'), 'Spent'),
      (data.meets?.length.toString(), 'Meets'),
      (data.posts?.length.toString(), 'Posts'),
    ];
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(color: AppColors.surfaceGray, borderRadius: BorderRadius.circular(14)),
      child: IntrinsicHeight(
        child: Row(
          children: [
            for (var i = 0; i < cells.length; i++) ...[
              if (i > 0) VerticalDivider(width: 1, thickness: 1, color: AppColors.border),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          cells[i].$1 ?? '–',
                          maxLines: 1,
                          style: TextStyle(fontFamily: AppFonts.display, fontSize: 21, fontWeight: FontWeight.w700, height: 1.1, color: AppColors.textPrimary),
                        ),
                      ),
                      const SizedBox(height: 1),
                      Text(cells[i].$2, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Whose car it is, for visitors: avatar, @name, and the way to their profile.
class CarOwnerRow extends StatelessWidget {
  const CarOwnerRow({super.key, required this.ownerId, required this.owner, required this.onTap});
  final String ownerId;
  final Profile? owner;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final o = owner;
    final name = o?.username == null ? (o?.displayName ?? '…') : '@${o!.username}';
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: [
              UserAvatar(url: o?.avatarUrl, name: o?.displayName ?? o?.username, seed: ownerId, size: 40),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                    Text('In their garage', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary)),
                  ],
                ),
              ),
              Icon(AppIcons.caretRight, size: 16, color: AppColors.textMuted),
            ],
          ),
        ),
      ),
    );
  }
}
