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

/// "Paint colour": the label, a little car in the picked paint, one line on
/// what it does (the toy car is made, or repainted, in it: migration 0110),
/// and the swatches. Shared by onboarding, Add car and Edit car (members
/// didn't get what "Colour on the map" was for, and nothing they could see
/// changed).
class CarMapColourSection extends StatelessWidget {
  const CarMapColourSection({super.key, required this.value, required this.onChanged, this.note, this.hint = 'Your toy car is made in this colour.', this.noteColor});
  final String? value;
  final ValueChanged<String>? onChanged;

  /// Where the colour came from ("Silver · from the photo") or what saving
  /// does, under the line.
  final String? note;

  /// The one line on what the colour is for.
  final String hint;

  /// The note's colour (a warning reads in amber), else secondary text.
  final Color? noteColor;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('PAINT COLOUR', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.2, color: AppColors.textSecondary)),
        const SizedBox(height: 8),
        Row(
          children: [
            MapCarPreview(color: value),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(hint, style: TextStyle(fontSize: 13.5, height: 1.35, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                  if (note != null) ...[
                    const SizedBox(height: 2),
                    Text(note!, style: TextStyle(fontSize: 12.5, height: 1.35, color: noteColor ?? AppColors.textSecondary)),
                  ],
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        CarColorPicker(value: value, onChanged: onChanged),
      ],
    );
  }
}

/// The car's map marker in [color] (a kCarColors key; grey when none yet)
/// on a little bit of road.
class MapCarPreview extends StatelessWidget {
  const MapCarPreview({super.key, required this.color, this.size = 64});
  final String? color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<Color?>(
      tween: ColorTween(end: carColor(color)),
      duration: const Duration(milliseconds: 220),
      builder: (_, c, _) => Container(
        width: size,
        height: size * 1.15,
        decoration: BoxDecoration(color: AppColors.surfaceGray, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.border)),
        child: CustomPaint(painter: _MapCarPainter(color: c ?? carColor(color), lane: AppColors.border, dim: color == null)),
      ),
    );
  }
}

class _MapCarPainter extends CustomPainter {
  const _MapCarPainter({required this.color, required this.lane, required this.dim});
  final Color color;
  final Color lane;
  final bool dim;

  @override
  void paint(Canvas canvas, Size size) {
    // A dashed lane line behind the car, like a street on the map.
    final dash = Paint()
      ..color = lane
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    for (var y = 4.0; y < size.height - 4; y += 12) {
      canvas.drawLine(Offset(size.width * 0.18, y), Offset(size.width * 0.18, y + 6), dash);
      canvas.drawLine(Offset(size.width * 0.82, y), Offset(size.width * 0.82, y + 6), dash);
    }
    paintCar(canvas, centre: size.center(Offset.zero), size: size.height * 0.82, color: color, dim: dim);
  }

  @override
  bool shouldRepaint(_MapCarPainter old) => old.color != color || old.lane != lane || old.dim != dim;
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
