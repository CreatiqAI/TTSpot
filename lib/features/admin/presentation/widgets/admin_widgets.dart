import 'package:flutter/material.dart';

import '../../../../core/theme/app_icons.dart';
import '../../../../core/theme/app_theme.dart';

/// Section label with an optional trailing action.
class AdminHead extends StatelessWidget {
  const AdminHead(this.text, {super.key, this.action, this.onAction});
  final String text;
  final String? action;
  final VoidCallback? onAction;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 22, 8, 6),
        child: Row(
          children: [
            Expanded(child: Text(text, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, letterSpacing: 1, color: AppColors.textSecondary))),
            if (action != null) TextButton(style: TextButton.styleFrom(visualDensity: VisualDensity.compact), onPressed: onAction, child: Text(action!)),
          ],
        ),
      );
}

/// One number with its label. [delta] is a small green/grey line under it.
class AdminStat extends StatelessWidget {
  const AdminStat({super.key, required this.label, required this.value, this.delta, this.accent = false, this.onTap});
  final String label;
  final String value;
  final String? delta;
  final bool accent;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => Expanded(
        child: Material(
          color: accent ? AppColors.brand : AppColors.surfaceGray,
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(value, style: TextStyle(fontFamily: AppFonts.display, color: accent ? Colors.white : AppColors.textPrimary, fontSize: 30, fontWeight: FontWeight.w700, height: 1)),
                  ),
                  const SizedBox(height: 5),
                  Text(label, style: TextStyle(color: accent ? Colors.white70 : AppColors.textSecondary, fontSize: 11.5, fontWeight: FontWeight.w600)),
                  if (delta != null) Text(delta!, style: TextStyle(color: accent ? Colors.white60 : AppColors.success, fontSize: 10.5, fontWeight: FontWeight.w700)),
                ],
              ),
            ),
          ),
        ),
      );
}

/// Seven small bars for the last seven days, today on the right, with the
/// total on the left. Reads at a glance; no axes.
class AdminTrend extends StatelessWidget {
  const AdminTrend({super.key, required this.label, required this.values, this.color = AppColors.brand});
  final String label;
  final List<int> values;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final max = values.isEmpty ? 0 : values.reduce((a, b) => a > b ? a : b);
    final total = values.fold(0, (a, b) => a + b);
    final today = values.isEmpty ? 0 : values.last;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(color: AppColors.surfaceGray, borderRadius: BorderRadius.circular(14)),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: AppColors.textSecondary)),
                const SizedBox(height: 2),
                Text('$total', style: TextStyle(fontFamily: AppFonts.display, fontSize: 28, fontWeight: FontWeight.w700, height: 1, color: AppColors.textPrimary)),
                Text('$today today', style: TextStyle(fontSize: 11, color: AppColors.textMuted)),
              ],
            ),
          ),
          SizedBox(
            width: 120,
            height: 44,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (var i = 0; i < values.length; i++) ...[
                  Expanded(
                    child: Container(
                      height: max == 0 ? 3 : (3 + 41 * values[i] / max),
                      decoration: BoxDecoration(
                        color: i == values.length - 1 ? color : color.withValues(alpha: 0.35),
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  ),
                  if (i < values.length - 1) const SizedBox(width: 4),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A queue row: icon, title, hint, and a count pill (red when > 0).
class AdminQueueTile extends StatelessWidget {
  const AdminQueueTile({super.key, required this.icon, required this.title, required this.hint, required this.count, required this.onTap});
  final IconData icon;
  final String title;
  final String hint;
  final int count;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16),
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(color: count > 0 ? AppColors.brand.withValues(alpha: 0.1) : AppColors.surfaceGray, borderRadius: BorderRadius.circular(12)),
          child: Icon(icon, size: 20, color: count > 0 ? AppColors.brand : AppColors.textSecondary),
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5)),
        subtitle: Text(hint, style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
        trailing: count == 0
            ? Icon(AppIcons.caretRight, size: 16, color: AppColors.textMuted)
            : Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(color: AppColors.brand, borderRadius: BorderRadius.circular(999)),
                child: Text('$count', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 12.5)),
              ),
        onTap: onTap,
      );
}

/// Label on the left, value on the right, in a card list.
class AdminFactRow extends StatelessWidget {
  const AdminFactRow(this.label, this.value, {super.key, this.onTap});
  final String label;
  final String value;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            children: [
              Expanded(child: Text(label, style: const TextStyle(fontSize: 14))),
              Text(value, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
              if (onTap != null) ...[const SizedBox(width: 6), Icon(AppIcons.caretRight, size: 14, color: AppColors.textMuted)],
            ],
          ),
        ),
      );
}

/// Grouped rows in one rounded card.
class AdminCard extends StatelessWidget {
  const AdminCard({super.key, required this.children});
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(color: AppColors.surface, border: Border.all(color: AppColors.border), borderRadius: BorderRadius.circular(14)),
        child: Column(
          children: [
            for (var i = 0; i < children.length; i++) ...[
              if (i > 0) Divider(height: 0.5, indent: 14, endIndent: 14, color: AppColors.border),
              children[i],
            ],
          ],
        ),
      );
}
