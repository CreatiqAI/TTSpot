import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'user_avatar.dart';

/// "Pick a TiTi": the 8 default avatars in a 4x2 grid, for the avatar sheet
/// in onboarding and Edit profile. [selected] gets a brand-coloured ring.
class TitiAvatarGrid extends StatelessWidget {
  const TitiAvatarGrid({super.key, required this.onPick, this.selected});

  final int? selected;
  final ValueChanged<int> onPick;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Pick a TiTi', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
          const SizedBox(height: 12),
          GridView.count(
            crossAxisCount: 4,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            children: [
              for (var i = 0; i < DefaultAvatars.count; i++)
                GestureDetector(
                  onTap: () => onPick(i),
                  child: Container(
                    padding: const EdgeInsets.all(3),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: i == selected ? AppColors.brand : Colors.transparent, width: 3),
                    ),
                    child: ClipOval(child: Image.asset(DefaultAvatars.asset(i), fit: BoxFit.cover, filterQuality: FilterQuality.medium)),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
