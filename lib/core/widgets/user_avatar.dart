import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../env.dart';
import '../theme/app_theme.dart';

/// The 8 TiTi default avatars (TiTi in a racing helmet, cap, shades...).
/// Bundled in assets/avatars/ and mirrored publicly in Storage at
/// avatars/defaults/aN.png so a picked one can be saved as avatar_url.
abstract final class DefaultAvatars {
  static const count = 8;

  /// Local asset for index 0..7.
  static String asset(int i) => 'assets/avatars/a${i + 1}.png';

  static List<String> get assets => [for (var i = 0; i < count; i++) asset(i)];

  /// Public Storage URL for index 0..7, saved as a profile's avatar_url.
  static String publicUrl(int i) => '${Env.supabaseUrl}/storage/v1/object/public/avatars/defaults/a${i + 1}.png';

  static final _presetPath = RegExp(r'/storage/v1/object/public/avatars/defaults/a([1-8])\.png$');

  /// Index of a preset avatar URL (so it can be drawn from the bundled asset,
  /// instantly and without egress), or null for any other URL.
  static int? indexOfUrl(String? url) {
    if (url == null || url.isEmpty) return null;
    final m = _presetPath.firstMatch(url.split('?').first);
    return m == null ? null : int.parse(m.group(1)!) - 1;
  }

  /// A stable pick for someone with no picture: the user id, else the name.
  /// Null when there's nothing to seed from.
  static String? forSeed(String? seed, [String? name]) {
    final s = (seed != null && seed.isNotEmpty) ? seed : (name ?? '').trim();
    if (s.isEmpty) return null;
    // FNV-1a, so the pick never changes between runs or platforms.
    var h = 0x811c9dc5;
    for (final c in s.codeUnits) {
      h ^= c;
      h = (h * 0x01000193) & 0xffffffff;
    }
    return asset(h % count);
  }

  /// Image for an avatar_url, falling back to the seeded default. Null only
  /// when there's no url and no seed.
  static ImageProvider? image(String? url, {String? seed, String? name}) {
    final preset = indexOfUrl(url);
    if (preset != null) return AssetImage(asset(preset));
    if (url != null && url.isNotEmpty) return CachedNetworkImageProvider(url);
    final fallback = forSeed(seed, name);
    return fallback == null ? null : AssetImage(fallback);
  }
}

/// Round avatar with a network image, else one of the TiTi defaults picked
/// from [seed] (the user id) or the name, else the initial on gray.
class UserAvatar extends StatelessWidget {
  const UserAvatar({super.key, this.url, this.name, this.seed, this.size = 36, this.borderColor});

  final String? url;
  final String? name;

  /// Stable id (usually the user id) that picks the default avatar.
  final String? seed;
  final double size;
  final Color? borderColor;

  @override
  Widget build(BuildContext context) {
    final initial = (name ?? '').trim().isEmpty ? '?' : name!.trim()[0].toUpperCase();
    final image = DefaultAvatars.image(url, seed: seed, name: name);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: AppColors.surfaceGray,
        border: Border.all(color: borderColor ?? AppColors.border, width: borderColor == null ? 0.5 : 2),
        image: image != null ? DecorationImage(image: image, fit: BoxFit.cover) : null,
      ),
      alignment: Alignment.center,
      child: image != null
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
  const AvatarStack({super.key, required this.urls, required this.names, this.seeds, this.size = 28, this.max = 4});

  final List<String?> urls;
  final List<String?> names;
  final List<String?>? seeds;
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
              child: UserAvatar(url: urls[i], name: names[i], seed: (seeds != null && i < seeds!.length) ? seeds![i] : null, size: size, borderColor: AppColors.bg),
            ),
        ],
      ),
    );
  }
}
