import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_art.dart';
import '../../../../core/theme/app_icons.dart';
import '../../../../core/theme/app_theme.dart';
import '../../expo_routes.dart';
import '../application/door_providers.dart';
import 'registration_sheet.dart';

/// Opens the registration form once, right after a door check-in, when the
/// event has one I haven't answered. Call after the first frame.
void openPendingRegistration(BuildContext context, WidgetRef ref, String eventId) {
  if (!ref.read(pendingRegistrationProvider.notifier).take(eventId)) return;
  showRegistrationSheet(context, eventId);
}

/// Top of the floor plan right after a door check-in: "You're in · #0427",
/// with "Your pass" and, while the form isn't done, "Register". Dismissible.
class DoorWelcomeBanner extends ConsumerStatefulWidget {
  const DoorWelcomeBanner({super.key, required this.eventId});
  final String eventId;

  @override
  ConsumerState<DoorWelcomeBanner> createState() => _DoorWelcomeBannerState();
}

class _DoorWelcomeBannerState extends ConsumerState<DoorWelcomeBanner> {
  bool _dismissed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) openPendingRegistration(context, ref, widget.eventId);
    });
  }

  @override
  Widget build(BuildContext context) {
    final h = ref.watch(eventHubProvider(widget.eventId)).value;
    if (_dismissed || h == null || !h.checkedIn) return const SizedBox.shrink();
    final reg = h.registration;
    final buttonStyle = FilledButton.styleFrom(
      visualDensity: VisualDensity.compact,
      minimumSize: const Size(0, 38),
      padding: const EdgeInsets.symmetric(horizontal: 14),
      textStyle: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
    );

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
      decoration: BoxDecoration(
        color: AppColors.ink,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 12, offset: Offset(0, 4))],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(padding: EdgeInsets.only(top: 2), child: ArtIcon(AppArt.confetti, size: 34)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  h.entry == null ? "You're in" : "You're in · ${h.entry}",
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontFamily: AppFonts.display, fontSize: 24, height: 1.05, fontWeight: FontWeight.w700, color: Colors.white),
                ),
                if (reg.open) ...[
                  const SizedBox(height: 2),
                  Text(
                    reg.questions <= 0 ? 'A few quick questions for the organizer.' : 'Answer ${reg.questions} quick question${reg.questions == 1 ? '' : 's'}.',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12.5, color: Colors.white70),
                  ),
                ],
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    FilledButton(
                      style: buttonStyle.copyWith(
                        backgroundColor: const WidgetStatePropertyAll(Colors.white),
                        foregroundColor: const WidgetStatePropertyAll(AppColors.ink),
                      ),
                      onPressed: () => context.push(ExpoRoutes.pass(widget.eventId)),
                      child: const Text('Your pass'),
                    ),
                    if (reg.open)
                      FilledButton(
                        style: buttonStyle,
                        onPressed: () => showRegistrationSheet(context, widget.eventId),
                        child: const Text('Register'),
                      ),
                  ],
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Close',
            visualDensity: VisualDensity.compact,
            icon: const Icon(AppIcons.x, size: 18, color: Colors.white70),
            onPressed: () => setState(() => _dismissed = true),
          ),
        ],
      ),
    );
  }
}
