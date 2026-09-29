import 'package:flutter/material.dart';

import '../theme/app_icons.dart';
import '../theme/app_theme.dart';

/// Title row for a tall bottom sheet: the title on the left and a round close
/// button on the right. Tall sheets leave no backdrop to tap, and not everyone
/// knows to swipe down, so every tall sheet gets a visible way out.
class SheetHeader extends StatelessWidget {
  const SheetHeader({super.key, required this.title, this.style, this.onClose});
  final String title;
  final TextStyle? style;
  /// Defaults to closing the sheet.
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Expanded(child: Text(title, style: style ?? const TextStyle(fontSize: 20, fontWeight: FontWeight.w800))),
          const SizedBox(width: 8),
          Semantics(
            label: 'Close',
            button: true,
            child: Material(
              color: AppColors.surfaceGray,
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: onClose ?? () => Navigator.of(context).maybePop(),
                child: SizedBox(width: 36, height: 36, child: Icon(AppIcons.x, size: 18, color: AppColors.textPrimary)),
              ),
            ),
          ),
        ],
      );
}
