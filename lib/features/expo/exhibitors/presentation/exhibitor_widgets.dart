import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../../core/theme/app_icons.dart';
import '../../../../core/theme/app_theme.dart';
import '../domain/exhibitor.dart';

/// TT Spot partner gold (rings, tags).
const kPartnerGold = Color(0xFFD4A20C);
const kPartnerGoldDeep = Color(0xFF8A6A00);

/// Small gold "Partner" tag.
class PartnerTag extends StatelessWidget {
  const PartnerTag({super.key});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration: BoxDecoration(
          color: kPartnerGold.withValues(alpha: 0.16),
          borderRadius: BorderRadius.circular(AppRadius.pill),
          border: Border.all(color: kPartnerGold.withValues(alpha: 0.7)),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(AppIcons.sealCheck, size: 11, color: kPartnerGoldDeep),
            SizedBox(width: 3),
            Text('Partner', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: kPartnerGoldDeep, height: 1.2)),
          ],
        ),
      );
}

/// Round logo, or the name's initials when there is none. Partners get a
/// gold ring.
class ExhibitorLogo extends StatelessWidget {
  const ExhibitorLogo({super.key, required this.exhibitor, this.size = 44});
  final Exhibitor exhibitor;
  final double size;

  @override
  Widget build(BuildContext context) {
    final url = exhibitor.displayLogo;
    final ring = exhibitor.isPartner;
    final inner = size - (ring ? 5 : 0);
    final fallback = Container(
      width: inner,
      height: inner,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: _tint(exhibitor.name), shape: BoxShape.circle),
      child: Text(
        exhibitor.initials,
        style: TextStyle(fontSize: inner * 0.36, fontWeight: FontWeight.w800, color: Colors.white, height: 1),
      ),
    );
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: ring ? kPartnerGold : null,
      ),
      child: ClipOval(
        child: SizedBox(
          width: inner,
          height: inner,
          child: url == null
              ? fallback
              : ColoredBox(
                  color: Colors.white,
                  child: CachedNetworkImage(
                    imageUrl: url,
                    fit: BoxFit.cover,
                    memCacheWidth: (size * 3).round(),
                    placeholder: (_, _) => fallback,
                    errorWidget: (_, _, _) => fallback,
                  ),
                ),
        ),
      ),
    );
  }

  /// A steady colour per name, from a small calm palette.
  static Color _tint(String name) {
    const palette = [Color(0xFF2F6FED), Color(0xFF8B3FD9), Color(0xFF0E9AA7), Color(0xFFE8820C), Color(0xFF1DA750), Color(0xFF5A6270), Color(0xFF1F4FB8), Color(0xFFC2185B)];
    var h = 0;
    for (final c in name.codeUnits) {
      h = (h * 31 + c) & 0x7fffffff;
    }
    return palette[h % palette.length];
  }
}
