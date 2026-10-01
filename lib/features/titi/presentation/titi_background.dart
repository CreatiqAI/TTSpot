import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';

/// TiTi's own chat background: his workshop by day (light) and a pit garage
/// at night (dark), faded so the chat reads on top. Pinned to the bottom like
/// the chat wallpapers, so TiTi on his tyre stack sits just above the
/// composer. Art: tool/art_titi_ai_bg.py, preview: design/wallpapers/titi_ai.jpg.
///
/// Everything on it has a solid fill: TiTi's bubbles, cards and chips use
/// [AppColors.surface], the member's bubbles [mineFill].
class TitiBackground extends StatelessWidget {
  const TitiBackground({super.key, required this.child});
  final Widget child;

  static String asset({required bool dark}) => 'assets/wallpapers/titi_ai_${dark ? 'dark' : 'light'}.webp';

  /// Under the picture (and while it loads): the colour its top fades into.
  /// Mirrors GROUND in tool/art_titi_ai_bg.py.
  static Color ground({required bool dark}) => dark ? const Color(0xFF0D0F13) : const Color(0xFFF7F4F0);

  /// The member's bubbles: in light mode a cool grey that stands off the
  /// warm workshop (the app's surfaceGray melts into it).
  static Color get mineFill => AppColors.dark ? AppColors.surfaceGray : const Color(0xFFE1E4EA);

  /// Pills sitting straight on the picture (the day divider).
  static Color get pillFill => AppColors.surface.withValues(alpha: AppColors.dark ? 0.9 : 0.92);

  @override
  Widget build(BuildContext context) {
    final dark = AppColors.dark;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: ground(dark: dark),
        image: DecorationImage(
          image: AssetImage(asset(dark: dark)),
          fit: BoxFit.cover,
          alignment: Alignment.bottomCenter,
          filterQuality: FilterQuality.medium,
        ),
      ),
      child: child,
    );
  }
}
