import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Round avatar with a network image, or initials on gray when there's none.
class UserAvatar extends StatelessWidget {
  const UserAvatar({super.key, this.url, this.name, this.size = 36, this.borderColor});

  final String? url;
  final String? name;
  final double size;
  final Color? borderColor;

  @override
  Widget build(BuildContext context) {
    final initial = (name ?? '').trim().isEmpty ? '?' : name!.trim()[0].toUpperCase();
    final hasUrl = url != null && url!.isNotEmpty;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: AppColors.surfaceGray,
        border: Border.all(color: borderColor ?? AppColors.border, width: borderColor == null ? 0.5 : 2),
        image: hasUrl ? DecorationImage(image: CachedNetworkImageProvider(url!), fit: BoxFit.cover) : null,
      ),
      alignment: Alignment.center,
      child: hasUrl
          ? null
          : Text(
              initial,
              style: TextStyle(
                fontSize: size * 0.42,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary,
              ),
            ),
    );
  }
}

/// Overlapping row of avatars, Instagram "liked by" style.
class AvatarStack extends StatelessWidget {
  const AvatarStack({super.key, required this.urls, required this.names, this.size = 28, this.max = 4});

  final List<String?> urls;
  final List<String?> names;
  final double size;
  final int max;

  @override
  Widget build(BuildContext context) {
    final count = urls.length.clamp(0, max);
    if (count == 0) return const SizedBox.shrink();
    final overlap = size * 0.32;
    return SizedBox(
      width: size + (count - 1) * (size - overlap),
      height: size,
      child: Stack(
        children: [
          for (var i = 0; i < count; i++)
            Positioned(
              left: i * (size - overlap),
              child: UserAvatar(url: urls[i], name: names[i], size: size, borderColor: AppColors.bg),
            ),
        ],
      ),
    );
  }
}
