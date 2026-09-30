import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/titi.dart';

/// TiTi's chat, pinned first in the Chats inbox. Opens [Routes.titi].
class TitiInboxTile extends StatelessWidget {
  const TitiInboxTile({super.key});

  @override
  Widget build(BuildContext context) => ListTile(
        leading: const TitiAvatar(TitiPose.chat, size: 48),
        title: Row(
          children: [
            const Text('TiTi', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(color: AppColors.surfaceGray, borderRadius: BorderRadius.circular(999)),
              child: Text('AI', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 0.5, color: AppColors.textSecondary)),
            ),
            const SizedBox(width: 6),
            Icon(AppIcons.pushPin, size: 14, color: AppColors.textMuted),
          ],
        ),
        subtitle: Text('Your pit crew · Ask me anything', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: AppColors.textSecondary)),
        onTap: () => context.push(Routes.titi),
      );
}
