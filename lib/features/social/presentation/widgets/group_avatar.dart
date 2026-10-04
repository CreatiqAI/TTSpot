import 'package:flutter/material.dart';

import '../../../../core/theme/app_icons.dart';
import '../../../../core/theme/app_images.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/user_avatar.dart';
import '../../domain/chat.dart';

/// A group chat's picture: a club chat shows the club logo (its crest when
/// there's none), a friends' group its photo, else two members' faces
/// stacked, else a people icon.
class GroupAvatar extends StatelessWidget {
  const GroupAvatar({super.key, required this.conv, this.size = 48});
  final Conversation conv;
  final double size;

  @override
  Widget build(BuildContext context) {
    final clubId = conv.clubId;
    if (conv.isClubChat) return UserAvatar(url: conv.entityLogo, name: conv.title, size: size, fallbackAsset: clubId == null ? null : crestAsset(clubId));
    final photo = conv.photoUrl;
    if (photo != null && photo.isNotEmpty) return UserAvatar(url: photo, name: conv.title, size: size);
    final faces = conv.others.take(2).toList();
    if (faces.length < 2) {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(color: AppColors.surfaceGray, shape: BoxShape.circle, border: Border.all(color: AppColors.border, width: 0.5)),
        child: Icon(AppIcons.usersThree, size: size * 0.46, color: AppColors.textSecondary),
      );
    }
    final small = size * 0.68;
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        children: [
          Positioned(top: 0, right: 0, child: UserAvatar(url: faces[0].avatarUrl, name: faces[0].displayName ?? faces[0].username, seed: faces[0].id, size: small)),
          Positioned(left: 0, bottom: 0, child: UserAvatar(url: faces[1].avatarUrl, name: faces[1].displayName ?? faces[1].username, seed: faces[1].id, size: small, borderColor: AppColors.bg)),
        ],
      ),
    );
  }
}
