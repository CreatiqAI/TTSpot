import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/titi.dart';
import '../../../core/widgets/primary_button.dart';

/// The front door: every signed-out cold start lands here. TiTi waves, the
/// three steps of sign-up are laid out, and the two ways in are Get started
/// (sign-up) and I already have an account (log in).
class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final display = TextStyle(fontFamily: AppFonts.display, fontSize: 46, height: 44 / 46, fontWeight: FontWeight.w800, letterSpacing: -0.5, color: AppColors.textPrimary);
    return Scaffold(
      body: SafeArea(
        child: _FillScroll(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Text.rich(
                    TextSpan(
                      style: TextStyle(fontFamily: AppFonts.display, fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: 0.5, color: AppColors.textPrimary, height: 1),
                      children: const [
                        TextSpan(text: 'TT', style: TextStyle(color: AppColors.brand)),
                        TextSpan(text: 'SPOT'),
                      ],
                    ),
                  ),
                  const Spacer(),
                  Text('MALAYSIA\'S CAR COMMUNITY', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.5, color: AppColors.textSecondary)),
                ],
              ),
              const SizedBox(height: 18),
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    height: 316,
                    decoration: BoxDecoration(color: AppColors.surfaceGray, borderRadius: BorderRadius.circular(28)),
                    alignment: Alignment.center,
                    child: const Titi(TitiPose.wave, height: 300),
                  ),
                  const Positioned(
                    left: 14,
                    bottom: -22,
                    child: TitiBubble('Hi, I\'m TiTi. Two minutes and you\'re on the road with us.', maxWidth: 270),
                  ),
                ],
              ),
              const SizedBox(height: 44),
              Text.rich(
                TextSpan(
                  style: display,
                  children: const [
                    TextSpan(text: 'DRIVE.\nCONNECT.\n'),
                    TextSpan(text: 'EXPLORE.', style: TextStyle(color: AppColors.brand)),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Meets, TT sessions and good spots on one map. Your car is your profile.',
                style: TextStyle(fontSize: 15, color: AppColors.textSecondary, height: 1.4),
              ),
              const Spacer(),
              const SizedBox(height: 24),
              const Wrap(
                spacing: 14,
                runSpacing: 8,
                children: [
                  _StepBadge(1, 'YOUR RIDE'),
                  _StepBadge(2, 'YOU'),
                  _StepBadge(3, 'A GIFT'),
                ],
              ),
              const SizedBox(height: 16),
              PrimaryButton(
                label: 'Get started',
                onPressed: () {
                  HapticFeedback.lightImpact();
                  context.push(Routes.signUp);
                },
              ),
              const SizedBox(height: 4),
              TextButton(
                onPressed: () => context.push(Routes.signIn),
                child: Text('I already have an account', style: TextStyle(color: AppColors.textSecondary, fontWeight: FontWeight.w600)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Scroll view whose content fills the viewport at least, so a `Spacer`
/// pushes the actions to the bottom on tall phones and the page still
/// scrolls on short ones.
class _FillScroll extends StatelessWidget {
  const _FillScroll({required this.child, required this.padding});
  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (_, c) => SingleChildScrollView(
          padding: padding,
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: math.max(0, c.maxHeight - padding.vertical)),
            child: IntrinsicHeight(child: child),
          ),
        ),
      );
}

/// Numbered badge: "1 YOUR RIDE".
class _StepBadge extends StatelessWidget {
  const _StepBadge(this.n, this.label);
  final int n;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 20,
            height: 20,
            alignment: Alignment.center,
            decoration: const BoxDecoration(color: AppColors.brand, shape: BoxShape.circle),
            child: Text('$n', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Colors.white, height: 1)),
          ),
          const SizedBox(width: 6),
          Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1, color: AppColors.textPrimary)),
        ],
      );
}
