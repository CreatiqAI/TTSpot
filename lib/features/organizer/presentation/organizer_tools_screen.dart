import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../../core/router/pop_or_home.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/titi.dart';
import '../../../core/utils/dates.dart';
import '../../../core/utils/friendly_error.dart';
import '../../../core/widgets/primary_button.dart';
import '../../events/application/event_providers.dart';
import '../application/organizer_providers.dart';
import '../domain/organizer_models.dart';
import 'organizer_groups.dart';

/// One place for everything a verified organizer (and their crew) runs at a
/// meet. What shows depends on the role: crew get the door tools, the host
/// and co-hosts get everything.
class OrganizerToolsScreen extends ConsumerWidget {
  const OrganizerToolsScreen({super.key, required this.eventId});
  final String eventId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(eventDetailProvider(eventId));
    final role = ref.watch(myEventRoleProvider(eventId));
    final draws = ref.watch(eventDrawsProvider(eventId)).value ?? const <LuckyDraw>[];
    final event = detail.value?.event;

    return HomeOnBack(
      child: Scaffold(
      appBar: AppBar(
        leading: const AppBackButton(),
        title: const Text('Organizer tools'),
      ),
      body: role.when(
        loading: () => const Center(child: CircularProgressIndicator(strokeWidth: 2)),
        error: (e, _) => Center(child: Padding(padding: const EdgeInsets.all(32), child: Text(friendlyError(e), textAlign: TextAlign.center))),
        data: (r) {
          if (!r.onTeam) {
            return _Message(pose: TitiPose.sad, text: 'Only the host and crew of this meet can open its organizer tools.');
          }
          if (!r.tools) {
            return ListView(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
              children: [
                TitiSays('Organizer tools are for verified organizers. Apply once and they unlock on every meet you host.', pose: TitiPose.thumbsUp),
                const SizedBox(height: 20),
                PrimaryButton(label: 'Apply to be an organizer', onPressed: () => context.push(Routes.organizerApply)),
              ],
            );
          }
          return RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(myEventRoleProvider(eventId));
              ref.invalidate(eventDrawsProvider(eventId));
              ref.invalidate(eventDetailProvider(eventId));
            },
            child: ListView(
              padding: const EdgeInsets.only(bottom: 32),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(color: AppColors.surfaceGray, borderRadius: BorderRadius.circular(AppRadius.lg)),
                    child: Row(
                      children: [
                        TitiAvatar(TitiPose.thumbsUp, size: 52, background: AppColors.surface),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(event?.title ?? 'Your meet', maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontFamily: AppFonts.display, fontSize: 22, height: 1.05, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                              const SizedBox(height: 3),
                              Row(
                                children: [
                                  const Icon(AppIcons.sealCheck, size: 15, color: Color(0xFF2B7CFF)),
                                  const SizedBox(width: 4),
                                  Flexible(
                                    child: Text(
                                      '${r.label}${event == null ? '' : ' · ${formatEventDate(event.startsAt)}'}',
                                      style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary, fontWeight: FontWeight.w600),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                for (final g in organizerGroupsFor(r)) ...[
                  OrganizerGroupHead(g.label),
                  for (final t in organizerTools(g, eventId: eventId, role: r, event: event, draws: draws)) OrganizerToolTile(tool: t),
                ],
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
                  child: Text(
                    organizerFootnote(r),
                    style: TextStyle(fontSize: 12, color: AppColors.textMuted, height: 1.4),
                  ),
                ),
              ],
            ),
          );
        },
      ),
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.pose, required this.text});
  final TitiPose pose;
  final String text;
  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Titi(pose, height: 140),
              const SizedBox(height: 14),
              Text(text, textAlign: TextAlign.center, style: TextStyle(color: AppColors.textSecondary, height: 1.4)),
            ],
          ),
        ),
      );
}
