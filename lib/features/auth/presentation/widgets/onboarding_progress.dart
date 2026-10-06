import 'package:flutter/material.dart';

import '../../../../core/theme/app_icons.dart';
import '../../../../core/theme/app_theme.dart';

/// The top of every first-run page: a back arrow, a thin bar that fills one
/// step at a time, and the sign-out cross. One fixed-height row of icons and
/// a 4 px bar, no words, so a photo, a narrow phone or big text can never
/// push it around. [dark] draws it white for the ink pages (permissions,
/// the gift); otherwise it follows the theme (ink on white).
class OnboardingProgress extends StatelessWidget {
  const OnboardingProgress({super.key, required this.step, required this.total, this.onBack, this.onClose, this.enabled = true, this.dark = false});

  /// 1-based: step 1 of 4 shows a quarter of the bar filled.
  final int step;
  final int total;

  /// Null hides the arrow (first step, or a step that can't be redone).
  final VoidCallback? onBack;

  /// Sign out. Null hides the cross.
  final VoidCallback? onClose;

  /// False greys the buttons out while something is saving (they stay put).
  final bool enabled;
  final bool dark;

  static const height = 48.0;

  double get value => total <= 0 ? 0 : (step / total).clamp(0.0, 1.0);

  @override
  Widget build(BuildContext context) {
    final fg = dark ? Colors.white : AppColors.textPrimary;
    final track = dark ? Colors.white.withValues(alpha: 0.16) : AppColors.border;
    final still = MediaQuery.disableAnimationsOf(context);
    Widget slot(Widget? child) => SizedBox(width: 44, height: height, child: child);
    return Semantics(
      label: 'Step $step of $total',
      container: true,
      child: SizedBox(
        height: height,
        child: Row(
          children: [
            slot(
              onBack == null
                  ? null
                  : IconButton(
                      key: const ValueKey('onboarding-back'),
                      tooltip: 'Back',
                      padding: EdgeInsets.zero,
                      icon: Icon(AppIcons.arrowLeft, size: 22, color: fg),
                      onPressed: enabled ? onBack : null,
                    ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: SizedBox(
                  height: 4,
                  child: ColoredBox(
                    color: track,
                    child: TweenAnimationBuilder<double>(
                      // Fills on from where the step before left it.
                      tween: Tween(begin: total <= 0 ? 0 : ((step - 1) / total).clamp(0.0, 1.0), end: value),
                      duration: still ? Duration.zero : const Duration(milliseconds: 420),
                      curve: Curves.easeOutCubic,
                      builder: (_, v, _) => FractionallySizedBox(
                        alignment: AlignmentDirectional.centerStart,
                        widthFactor: v,
                        heightFactor: 1,
                        child: ColoredBox(color: fg),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 6),
            slot(
              onClose == null
                  ? null
                  : IconButton(
                      tooltip: 'Sign out',
                      padding: EdgeInsets.zero,
                      icon: Icon(AppIcons.x, size: 22, color: fg),
                      onPressed: enabled ? onClose : null,
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
