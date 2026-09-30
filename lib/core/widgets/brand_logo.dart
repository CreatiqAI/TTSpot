import 'package:flutter/material.dart';

/// The TT Spot logo. Dark mode uses a copy with white ink instead of black
/// (assets/brand/logo_dark.png) so the left T and the wordmark stay visible.
class BrandLogo extends StatelessWidget {
  const BrandLogo({super.key, required this.height});
  final double height;

  // Follows the theme this widget is built under (not the AppColors flag), so
  // a logo that survives a light/dark switch repaints with the right ink.
  @override
  Widget build(BuildContext context) => Image.asset(
        Theme.of(context).brightness == Brightness.dark ? 'assets/brand/logo_dark.png' : 'assets/brand/logo.png',
        height: height,
        filterQuality: FilterQuality.medium,
        gaplessPlayback: true,
      );
}
