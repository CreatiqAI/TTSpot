import 'package:flutter/material.dart';

import '../theme/app_art.dart';
import '../theme/app_theme.dart';

/// Instagram-style empty state: a piece of 3D art (or a thin-ring icon), bold
/// title, gray subtitle, blue link.
///
/// Give it [art] (an [AppArt] asset), an [emoji] (mapped to art when we have
/// one), or an [icon].
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.title,
    this.art,
    this.emoji,
    this.icon,
    this.subtitle,
    this.actionLabel,
    this.onAction,
  }) : assert(art != null || emoji != null || icon != null, 'Provide art, an emoji or an icon');

  final String title;
  final String? art;
  final String? emoji;
  final IconData? icon;
  final String? subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final asset = art ?? AppArt.forEmoji(emoji);
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (asset != null)
              Container(
                width: 96,
                height: 96,
                alignment: Alignment.center,
                decoration: const BoxDecoration(shape: BoxShape.circle, color: AppColors.surfaceGray),
                child: ArtIcon(asset, size: 60),
              )
            else
              Container(
                width: 84,
                height: 84,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.textPrimary, width: 2),
                ),
                child: emoji != null
                    ? Text(emoji!, style: const TextStyle(fontSize: 34))
                    : Icon(icon, size: 40, color: AppColors.textPrimary),
              ),
            const SizedBox(height: 18),
            Text(title, textAlign: TextAlign.center, style: AppText.sectionTitle),
            if (subtitle != null) ...[
              const SizedBox(height: 8),
              Text(
                subtitle!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.textSecondary, fontSize: 14, height: 1.4),
              ),
            ],
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 14),
              TextButton(onPressed: onAction, child: Text(actionLabel!)),
            ],
          ],
        ),
      ),
    );
  }
}
