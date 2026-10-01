import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'glass.dart';

/// Red main action with a loading spinner. Squeezes while pressed.
class PrimaryButton extends StatelessWidget {
  const PrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.loading = false,
    this.icon,
    this.onLongPress,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool loading;
  final IconData? icon;
  /// e.g. Directions: long-press always shows the app chooser.
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    const spinner = SizedBox(
      width: 20,
      height: 20,
      child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.white),
    );
    return PressScale(
      enabled: onPressed != null && !loading,
      child: icon == null || loading
          ? FilledButton(onPressed: loading ? null : onPressed, onLongPress: loading ? null : onLongPress, child: loading ? spinner : Text(label))
          : FilledButton.icon(onPressed: onPressed, onLongPress: onLongPress, icon: Icon(icon, size: 18, color: Colors.white), label: Text(label)),
    );
  }
}

/// Gray secondary action. Squeezes while pressed.
class SecondaryButton extends StatelessWidget {
  const SecondaryButton({super.key, required this.label, required this.onPressed, this.icon, this.onLongPress});

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  /// e.g. Directions: long-press always shows the app chooser.
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final button = icon == null
        ? ElevatedButton(onPressed: onPressed, onLongPress: onLongPress, child: Text(label))
        : ElevatedButton.icon(
            onPressed: onPressed,
            onLongPress: onLongPress,
            icon: Icon(icon, size: 18, color: AppColors.textPrimary),
            label: Text(label),
          );
    return PressScale(enabled: onPressed != null, child: button);
  }
}
