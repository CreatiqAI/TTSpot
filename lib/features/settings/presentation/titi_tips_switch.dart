import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/friendly_error.dart';
import '../application/settings_providers.dart';

/// Settings › "TiTi tips": TiTi's own short heads-up (rain, a meet today,
/// road tax due…), up to three a day, in his chat and as a push. On by
/// default; off means the `titi-nudge` function skips me altogether
/// (profiles.settings.titi_tips = false).
class TitiTipsSwitch extends ConsumerWidget {
  const TitiTipsSwitch({super.key});

  static const title = 'TiTi tips';
  static const subtitle = 'Short heads-ups from TiTi, up to 3 a day';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final on = ref.watch(settingsProvider).titiTips;
    return SwitchListTile.adaptive(
      key: const Key('settings-titi-tips'),
      value: on,
      onChanged: (v) async {
        try {
          await ref.read(settingsActionsProvider).patch({'titi_tips': v});
        } catch (e) {
          if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e))));
        }
      },
      activeTrackColor: AppColors.brand,
      secondary: Icon(AppIcons.sparkle, color: AppColors.textPrimary),
      title: const Text(title, style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14.5)),
      subtitle: Text(subtitle, style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
    );
  }
}
