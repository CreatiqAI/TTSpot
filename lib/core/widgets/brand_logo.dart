import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// The TT Spot logo. Dark mode uses a copy with white ink instead of black
/// (assets/brand/logo_dark.png) so the left T and the wordmark stay visible.
class BrandLogo extends StatelessWidget {
  const BrandLogo({super.key, required this.height});
  final double height;

  @override
  Widget build(BuildContext context) => Image.asset(
        AppColors.dark ? 'assets/brand/logo_dark.png' : 'assets/brand/logo.png',
        height: height,
        filterQuality: FilterQuality.medium,
      );
}
