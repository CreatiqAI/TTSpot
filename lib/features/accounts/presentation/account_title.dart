import 'package:flutter/material.dart';

import '../../../core/theme/app_icons.dart';

/// App-bar title on the Me tab: the handle with a small caret. Tap to switch
/// between personal, club and partner accounts.
class AccountTitle extends StatelessWidget {
  const AccountTitle({super.key, required this.text, required this.onTap});
  final String text;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis)),
              const SizedBox(width: 4),
              const Icon(AppIcons.caretDown, size: 14),
            ],
          ),
        ),
      );
}
