import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/profile/application/toy_providers.dart';
import '../../features/settings/application/settings_providers.dart';
import '../../features/settings/presentation/settings_screen.dart' show LegalScreen;
import '../legal/legal_text.dart';
import '../theme/app_icons.dart';
import '../theme/app_theme.dart';
import '../theme/titi.dart';
import '../utils/friendly_error.dart';
import '../widgets/primary_button.dart';

/// The three places TT Spot sends a member's data to a third-party AI
/// (Apple 5.1.2(i): say so clearly and ask first). Each OK is stored as a
/// date in `profiles.settings.ai_consent.<key>`.
enum AiConsentKind {
  /// TiTi: messages, photos and app context go to OpenAI (edge functions
  /// `titi` and `titi-nudge`).
  titi('titi'),

  /// Toy car: the car's photo goes to Kie.ai (edge function `car-toy`).
  toy('toy'),

  /// Safety check: post and moment photos and text go to OpenAI moderation
  /// (edge function `moderate-content`).
  safety('safety');

  const AiConsentKind(this.key);
  final String key;
}

/// What a consent sheet says. Short on purpose.
class AiConsentCopy {
  const AiConsentCopy({required this.pose, required this.title, required this.lines, required this.agree, this.decline = 'Not now'});
  final TitiPose pose;
  final String title;

  /// What is sent, to whom and why; the last line is always the training one.
  final List<(IconData, String)> lines;
  final String agree;
  final String decline;
}

const _noTraining = (AppIcons.shieldCheck, "It isn't used to train their models.");

const kAiConsentCopy = <AiConsentKind, AiConsentCopy>{
  AiConsentKind.titi: AiConsentCopy(
    pose: TitiPose.chat,
    title: 'Chat with TiTi?',
    lines: [
      (AppIcons.chatCircle, 'TiTi runs on OpenAI. Your messages and any photos you send go to OpenAI so TiTi can answer.'),
      (AppIcons.user, 'So do your name, cars, points and nearby meets, so answers and tips fit you.'),
      _noTraining,
    ],
    agree: 'Agree',
  ),
  AiConsentKind.toy: AiConsentCopy(
    pose: TitiPose.wrench,
    title: 'Use AI on your car photos?',
    lines: [
      (AppIcons.magnifyingGlass, 'OpenAI reads your car photo to fill in the make and model and find the plate.'),
      (AppIcons.car, 'Kie.ai turns it into your toy car, and a portrait if you order one.'),
      _noTraining,
    ],
    agree: 'Agree',
  ),
  AiConsentKind.safety: AiConsentCopy(
    pose: TitiPose.magnifier,
    title: 'Automatic safety check',
    lines: [
      (AppIcons.shield, 'Posts are checked by an automated safety filter (OpenAI) to keep TT Spot safe.'),
      (AppIcons.image, 'Photos and text you post, and spot check-in photos, go through the check.'),
      _noTraining,
    ],
    agree: 'OK',
  ),
};

/// Asks for the member's OK before [kind] sends anything to a third-party AI.
/// True = Agree; false = "Not now" or dismissed. Records nothing itself
/// (see [ensureAiConsent]).
Future<bool> showAiConsentSheet(BuildContext context, AiConsentKind kind) async {
  final ok = await showModalBottomSheet<bool>(
    useRootNavigator: true, // above the shell tab bar
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) => AiConsentSheet(
      kind: kind,
      onAgree: () => Navigator.pop(ctx, true),
      onDecline: () => Navigator.pop(ctx, false),
    ),
  );
  return ok ?? false;
}

/// True when the member has already agreed to [kind]; otherwise shows the
/// sheet and, on Agree, records it (toy cars through `allow_toy_cars`, which
/// also books the toys). False = not agreed, or it couldn't be saved (a
/// snack says why).
Future<bool> ensureAiConsent(BuildContext context, WidgetRef ref, AiConsentKind kind) async {
  if (hasAiConsent(ref.read(settingsProvider), kind)) return true;
  final ok = await showAiConsentSheet(context, kind);
  if (!ok) return false;
  try {
    if (kind == AiConsentKind.toy) {
      await ref.read(toyActionsProvider).allowToyCars();
    } else {
      await ref.read(settingsActionsProvider).recordAiConsent(kind.key);
    }
    return true;
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.maybeOf(context)
        ?..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(friendlyError(e))));
    }
    return false;
  }
}

/// Whether [s] holds an OK for [kind].
bool hasAiConsent(AppSettings s, AiConsentKind kind) => switch (kind) {
      AiConsentKind.titi => s.titiConsent,
      AiConsentKind.toy => s.toyConsent,
      AiConsentKind.safety => s.safetyConsent,
    };

/// The sheet's body: TiTi, a title, what is sent where, the Privacy Policy
/// link and the two buttons. Scrolls when the text is large.
class AiConsentSheet extends StatelessWidget {
  const AiConsentSheet({super.key, required this.kind, required this.onAgree, required this.onDecline, this.onPrivacy});

  final AiConsentKind kind;
  final VoidCallback onAgree;
  final VoidCallback onDecline;

  /// Defaults to the in-app Privacy Policy page.
  final VoidCallback? onPrivacy;

  void _openPrivacy(BuildContext context) => Navigator.of(context, rootNavigator: true).push(
        MaterialPageRoute<void>(builder: (_) => const LegalScreen(title: 'Privacy Policy', body: kPrivacyPolicy)),
      );

  @override
  Widget build(BuildContext context) {
    final copy = kAiConsentCopy[kind]!;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(child: Titi(copy.pose, height: 88)),
            const SizedBox(height: 10),
            Text(
              copy.title,
              key: const ValueKey('ai-consent-title'),
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, height: 1.25, color: AppColors.textPrimary),
            ),
            const SizedBox(height: 14),
            for (final (icon, text) in copy.lines)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(padding: const EdgeInsets.only(top: 1), child: Icon(icon, size: 18, color: AppColors.textSecondary)),
                    const SizedBox(width: 10),
                    Expanded(child: Text(text, style: TextStyle(fontSize: 14, height: 1.4, color: AppColors.textPrimary))),
                  ],
                ),
              ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                key: const ValueKey('ai-consent-privacy'),
                onPressed: onPrivacy ?? () => _openPrivacy(context),
                style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 4), minimumSize: Size.zero, tapTargetSize: MaterialTapTargetSize.padded),
                child: Text('Privacy Policy', style: AppText.link.copyWith(decoration: TextDecoration.underline, decorationColor: AppColors.primary)),
              ),
            ),
            const SizedBox(height: 12),
            PrimaryButton(key: const ValueKey('ai-consent-agree'), label: copy.agree, onPressed: onAgree),
            const SizedBox(height: 8),
            SecondaryButton(key: const ValueKey('ai-consent-decline'), label: copy.decline, onPressed: onDecline),
          ],
        ),
      ),
    );
  }
}
