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
  });

  final String label;
  final VoidCallback? onPressed;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return PressScale(
      enabled: onPressed != null && !loading,
      child: FilledButton(
        onPressed: loading ? null : onPressed,
        child: loading
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.white),
              )
            : Text(label),
      ),
    );
  }
}

/// Gray secondary action. Squeezes while pressed.
class SecondaryButton extends StatelessWidget {
  const SecondaryButton({super.key, required this.label, required this.onPressed, this.icon});

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final button = icon == null
        ? ElevatedButton(onPressed: onPressed, child: Text(label))
        : ElevatedButton.icon(
            onPressed: onPressed,
            icon: Icon(icon, size: 18, color: AppColors.textPrimary),
            label: Text(label),
          );
    return PressScale(enabled: onPressed != null, child: button);
  }
}
