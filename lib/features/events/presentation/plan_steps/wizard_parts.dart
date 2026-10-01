import 'package:flutter/material.dart';

import '../../../../core/theme/app_icons.dart';
import '../../../../core/theme/app_theme.dart';

/// The big friendly question at the top of each step.
class StepHeading extends StatelessWidget {
  const StepHeading(this.title, {super.key, this.subtitle});
  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: TextStyle(fontFamily: AppFonts.display, fontSize: 36, height: 1.05, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
          if (subtitle != null) ...[
            const SizedBox(height: 6),
            Text(subtitle!, style: TextStyle(fontSize: 14, height: 1.4, color: AppColors.textSecondary)),
          ],
          const SizedBox(height: 18),
        ],
      );
}

class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key, this.trailing});
  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          children: [
            Expanded(child: Text(text, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, letterSpacing: 1, color: AppColors.textSecondary))),
            ?trailing,
          ],
        ),
      );
}

/// Segmented progress: one bar per step, the done and current ones filled.
class WizardProgress extends StatelessWidget {
  const WizardProgress({super.key, required this.index, required this.count, required this.label});
  final int index;
  final int count;
  final String label;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                for (var i = 0; i < count; i++) ...[
                  if (i > 0) const SizedBox(width: 4),
                  Expanded(
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 220),
                      height: 4,
                      decoration: BoxDecoration(
                        color: i <= index ? AppColors.brand : AppColors.surfaceGray,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 6),
            Text('Step ${index + 1} of $count · $label', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textSecondary)),
          ],
        ),
      );
}

/// A big tappable option card (audience, meet kind).
class ChoiceCard extends StatelessWidget {
  const ChoiceCard({super.key, required this.selected, required this.title, this.subtitle, this.icon, this.leading, required this.onTap});
  final bool selected;
  final String title;
  final String? subtitle;
  final IconData? icon;
  final Widget? leading;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final fg = selected ? AppColors.onInk : AppColors.textPrimary;
    return Semantics(
      selected: selected,
      button: true,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: selected ? AppColors.textPrimary : AppColors.surfaceRaised,
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(color: selected ? AppColors.textPrimary : AppColors.border),
          ),
          child: Row(
            children: [
              if (leading != null) ...[leading!, const SizedBox(width: 12)] else if (icon != null) ...[Icon(icon, size: 24, color: fg), const SizedBox(width: 12)],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w800, color: fg)),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(subtitle!, style: TextStyle(fontSize: 12.5, height: 1.3, color: selected ? AppColors.onInk.withValues(alpha: 0.72) : AppColors.textSecondary)),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(selected ? AppIcons.checkCircleFill : AppIcons.checkCircle, size: 22, color: selected ? AppColors.onInk : AppColors.textMuted),
            ],
          ),
        ),
      ),
    );
  }
}

/// A field you tap to open a picker (date, time).
class TapField extends StatelessWidget {
  const TapField({super.key, required this.icon, required this.text, required this.onTap});
  final IconData icon;
  final String text;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: Container(
          constraints: const BoxConstraints(minHeight: 52),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: AppColors.surfaceRaised,
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            children: [
              Icon(icon, size: 20, color: AppColors.textSecondary),
              const SizedBox(width: 10),
              Expanded(child: Text(text, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600))),
            ],
          ),
        ),
      );
}

/// A rounded pill chip (quick times, durations).
class PillChip extends StatelessWidget {
  const PillChip({super.key, required this.label, this.sub, required this.on, required this.onTap});
  final String label;
  final String? sub;
  final bool on;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Semantics(
        selected: on,
        button: true,
        child: GestureDetector(
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            decoration: BoxDecoration(
              color: on ? AppColors.textPrimary : AppColors.surfaceGray,
              borderRadius: BorderRadius.circular(AppRadius.pill),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(label, textAlign: TextAlign.center, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: on ? AppColors.onInk : AppColors.textPrimary)),
                if (sub != null)
                  Text(sub!, textAlign: TextAlign.center, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: on ? AppColors.onInk.withValues(alpha: 0.7) : AppColors.textSecondary)),
              ],
            ),
          ),
        ),
      );
}
