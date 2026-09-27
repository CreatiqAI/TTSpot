import 'package:flutter/material.dart';

import '../../../../core/theme/app_art.dart';
import '../../../../core/theme/app_icons.dart';
import '../../../../core/theme/app_theme.dart';

/// Slim strip on my profile while a sealed box is waiting.
class BoxNudge extends StatelessWidget {
  const BoxNudge({super.key, required this.count, required this.onTap});
  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
        child: Material(
          color: AppColors.brand,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(AppRadius.lg),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 12, 10),
              child: Row(
                children: [
                  const ArtIcon(AppArt.gift, size: 30),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      count == 1 ? 'A blind box is waiting for you' : '$count blind boxes are waiting for you',
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: Colors.white),
                    ),
                  ),
                  const Text('Open', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: Colors.white)),
                  const SizedBox(width: 4),
                  const Icon(AppIcons.caretRight, size: 14, color: Colors.white),
                ],
              ),
            ),
          ),
        ),
      );
}
