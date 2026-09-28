import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/app_router.dart';
import '../../../../core/theme/app_icons.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../events/domain/event.dart';
import '../../application/organizer_providers.dart';

/// The one "Organizer tools" row on a meet page. Shows for the host and the
/// crew of a meet whose host is a verified organizer; a host who is not
/// verified yet gets a pointer to the application instead. Nothing for
/// everyone else.
class OrganizerToolsEntry extends ConsumerWidget {
  const OrganizerToolsEntry({super.key, required this.event});
  final Event event;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final role = ref.watch(myEventRoleProvider(event.id)).value;
    if (role == null || !role.onTeam || event.isCancelled) return const SizedBox.shrink();
    final locked = !role.tools;
    if (locked && !role.isHost) return const SizedBox.shrink();

    final subtitle = locked
        ? 'Get verified to unlock crew, announcements and a free lucky draw.'
        : role.isCrewOnly
            ? 'You\'re on the crew. Check-in QR, door list, scan prize claims.'
            : 'Crew, announcements, lucky draw, turnout report.';
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: AppColors.surfaceGray,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        child: ListTile(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.lg)),
          leading: Icon(locked ? AppIcons.lock : AppIcons.sealCheck, color: locked ? AppColors.textSecondary : const Color(0xFF2B7CFF)),
          title: Row(
            children: [
              const Flexible(child: Text('Organizer tools', style: TextStyle(fontWeight: FontWeight.w700))),
              if (!locked) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(color: AppColors.textPrimary, borderRadius: BorderRadius.circular(AppRadius.pill)),
                  child: Text(role.label.toUpperCase(), style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w800, letterSpacing: 0.6, color: AppColors.onInk)),
                ),
              ],
            ],
          ),
          subtitle: Text(subtitle, style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary)),
          trailing: const Icon(AppIcons.caretRight),
          onTap: () => context.push(locked ? Routes.organizerApply : Routes.eventTools(event.id)),
        ),
      ),
    );
  }
}
