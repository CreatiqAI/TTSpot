import 'package:flutter/material.dart';

import '../domain/badges.dart';

/// A badge at a tier: [badgeArt] (`assets/badges/<id>_<tier>.png`). Until those
/// files exist it falls back to the badge's single art, tinted per tier so
/// bronze, silver, platinum and gold still look different (gold = the art as
/// it is). [tier] 0 = locked: the bronze art, greyed and faded.
class TierBadgeImage extends StatelessWidget {
  const TierBadgeImage({super.key, required this.id, required this.tier, this.size = 48});

  final String id;
  final int tier;
  final double size;

  static const _greyscale = ColorFilter.matrix(<double>[
    0.2126, 0.7152, 0.0722, 0, 0,
    0.2126, 0.7152, 0.0722, 0, 0,
    0.2126, 0.7152, 0.0722, 0, 0,
    0, 0, 0, 1, 0,
  ]);

  // Copper: the red enamel turns brown, the gold rim warm.
  static const _bronze = ColorFilter.matrix(<double>[
    0.50, 0.55, 0.10, 0, 24,
    0.32, 0.40, 0.07, 0, 8,
    0.18, 0.24, 0.05, 0, 0,
    0, 0, 0, 1, 0,
  ]);

  // Bright neutral grey.
  static const _silver = ColorFilter.matrix(<double>[
    0.30, 0.59, 0.11, 0, 28,
    0.30, 0.59, 0.11, 0, 28,
    0.30, 0.59, 0.11, 0, 34,
    0, 0, 0, 1, 0,
  ]);

  // Cool, pale blue-white.
  static const _platinum = ColorFilter.matrix(<double>[
    0.26, 0.52, 0.10, 0, 34,
    0.28, 0.56, 0.11, 0, 46,
    0.32, 0.62, 0.13, 0, 66,
    0, 0, 0, 1, 0,
  ]);

  /// The interim tint for [tier] (null for gold: the art is already gold).
  static ColorFilter? tintFor(int tier) => switch (tier) {
        1 => _bronze,
        2 => _silver,
        3 => _platinum,
        _ => null,
      };

  @override
  Widget build(BuildContext context) {
    final shown = tier.clamp(1, kTopTier);
    final cache = (size * MediaQuery.devicePixelRatioOf(context)).round().clamp(48, 512);
    Widget fallback = Image.asset(
      badgeFallbackArt(id),
      width: size,
      height: size,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.medium,
      cacheWidth: cache,
      errorBuilder: (_, _, _) => SizedBox(width: size, height: size),
    );
    final tint = tintFor(shown);
    if (tint != null) fallback = ColorFiltered(colorFilter: tint, child: fallback);
    Widget child = Image.asset(
      badgeArt(id, shown),
      width: size,
      height: size,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.medium,
      cacheWidth: cache,
      errorBuilder: (_, _, _) => fallback,
    );
    if (tier < 1) child = Opacity(opacity: 0.4, child: ColorFiltered(colorFilter: _greyscale, child: child));
    return SizedBox(width: size, height: size, child: child);
  }
}
