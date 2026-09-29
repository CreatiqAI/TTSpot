import 'package:flutter/material.dart';

import '../theme/app_art.dart';
import '../theme/app_icons.dart';
import '../theme/app_theme.dart';
import '../theme/titi.dart';

/// Instagram-style empty state: a piece of 3D art (or a thin-ring icon), bold
/// title, gray subtitle, blue link.
///
/// Give it [titi] (a TiTi pose, drawn big), [art] (an [AppArt] asset), an
/// [emoji] (mapped to art when we have one), or an [icon]. Common art and
/// icons are swapped for the matching TiTi pose automatically.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.title,
    this.titi,
    this.art,
    this.emoji,
    this.icon,
    this.subtitle,
    this.actionLabel,
    this.onAction,
  }) : assert(titi != null || art != null || emoji != null || icon != null, 'Provide titi, art, an emoji or an icon');

  final String title;
  final TitiPose? titi;
  final String? art;
  final String? emoji;
  final IconData? icon;
  final String? subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;

  /// AppArt assets that TiTi has a pose for.
  static final Map<String, TitiPose> _artPoses = {
    AppArt.camera: TitiPose.camera,
    AppArt.speech: TitiPose.chat,
    AppArt.flag: TitiPose.flag,
    AppArt.coffee: TitiPose.voucher,
    AppArt.ticket: TitiPose.voucher,
    AppArt.hug: TitiPose.heart,
    AppArt.handshake: TitiPose.heart,
    AppArt.trophy: TitiPose.trophy,
    AppArt.prohibited: TitiPose.stop,
    AppArt.map: TitiPose.mapPin,
    AppArt.heartYellow: TitiPose.heart,
    AppArt.check: TitiPose.thumbsUp,
    AppArt.calendar: TitiPose.calendar,
    AppArt.bookmark: TitiPose.magnifier,
    AppArt.bell: TitiPose.bell,
    AppArt.car: TitiPose.camera,
  };

  static TitiPose? _iconPose(IconData? icon) {
    if (icon == AppIcons.wifiSlash) return TitiPose.sad;
    if (icon == AppIcons.lock) return TitiPose.stop;
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final asset = art ?? AppArt.forEmoji(emoji);
    final pose = titi ?? (asset != null ? _artPoses[asset] : _iconPose(icon));
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (pose != null)
              Titi(pose, height: 150)
            else if (asset != null)
              Container(
                width: 96,
                height: 96,
                alignment: Alignment.center,
                decoration: BoxDecoration(shape: BoxShape.circle, color: AppColors.surfaceGray),
                child: ArtIcon(asset, size: 60),
              )
            else
              Container(
                width: 84,
                height: 84,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.textPrimary, width: 2),
                ),
                child: emoji != null
                    ? Text(emoji!, style: const TextStyle(fontSize: 34))
                    : Icon(icon, size: 40, color: AppColors.textPrimary),
              ),
            const SizedBox(height: 18),
            Text(title, textAlign: TextAlign.center, style: AppText.sectionTitle),
            if (subtitle != null) ...[
              const SizedBox(height: 8),
              Text(
                subtitle!,
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textSecondary, fontSize: 14, height: 1.4),
              ),
            ],
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 14),
              TextButton(onPressed: onAction, child: Text(actionLabel!)),
            ],
          ],
        ),
      ),
    );
  }
}
