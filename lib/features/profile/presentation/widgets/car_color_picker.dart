import 'package:flutter/material.dart';

import '../../../../core/theme/app_icons.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../map/presentation/widgets/car_marker.dart';

/// Swatches for the nine map colours (kCarColors). Shared by Add car and
/// onboarding.
class CarColorPicker extends StatelessWidget {
  const CarColorPicker({super.key, required this.value, required this.onChanged});
  final String? value;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        for (final e in kCarColors.entries)
          GestureDetector(
            onTap: onChanged == null ? null : () => onChanged!(e.key),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: e.value,
                    shape: BoxShape.circle,
                    border: Border.all(color: value == e.key ? AppColors.textPrimary : AppColors.border, width: value == e.key ? 3 : 1),
                  ),
                  child: value == e.key ? Icon(AppIcons.check, size: 18, color: e.value.computeLuminance() > 0.5 ? AppColors.ink : Colors.white) : null,
                ),
                const SizedBox(height: 4),
                Text(kCarColorLabels[e.key]!, style: TextStyle(fontSize: 10.5, fontWeight: value == e.key ? FontWeight.w800 : FontWeight.w500)),
              ],
            ),
          ),
      ],
    );
  }
}

/// "We guessed this, fix anything wrong" once the recogniser has filled a
/// car form in.
class CarGuessNote extends StatelessWidget {
  const CarGuessNote({super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(AppIcons.sparkle, size: 16, color: AppColors.textSecondary),
        const SizedBox(width: 6),
        Expanded(
          child: Text('We guessed this from the photo, fix anything wrong.', style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary)),
        ),
      ],
    );
  }
}
