import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/titi.dart';
import '../../../core/utils/dates.dart';
import '../../../core/utils/friendly_error.dart';
import '../../../core/widgets/primary_button.dart';
import '../../events/application/event_providers.dart';
import '../../events/presentation/whos_here_sheet.dart';
import '../application/organizer_providers.dart';
import '../domain/organizer_models.dart';

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

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(AppIcons.arrowLeft), onPressed: () => context.pop()),
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
          final next = draws.where((d) => d.status == DrawStatus.scheduled).firstOrNull;
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
                const _Head('AT THE DOOR'),
                _Row(
                  icon: AppIcons.qrCode,
                  title: 'Check-in QR',
                  subtitle: 'Members scan it to check in. It changes every 30 seconds.',
                  onTap: () => context.push(Routes.eventQr(eventId)),
                ),
                _Row(
                  icon: AppIcons.listChecks,
                  title: 'Door list',
                  subtitle: event == null ? 'Loading…' : '${event.checkinCount} checked in. Confirm who is really here.',
                  onTap: event == null ? null : () => showWhosHereSheet(context, event),
                ),
                _Row(
                  icon: AppIcons.scan,
                  title: 'Scan prize claim',
                  subtitle: 'Winners show a claim QR at the stage. Scan it, hand over the prize.',
                  onTap: () => context.push(Routes.prizeScan),
                ),
                if (r.isHostCircle) ...[
                  const _Head('RUN THE MEET'),
                  _Row(
                    icon: AppIcons.gift,
                    title: 'Lucky draw',
                    subtitle: next == null
                        ? (draws.any((d) => d.status == DrawStatus.drawn) ? 'Drawn. Open the stage screen for results.' : 'Free entry for checked-in members. Set prizes and a time.')
                        : '${next.title} at ${formatTime(next.drawAt)} · ${next.winnerCount} winner${next.winnerCount == 1 ? '' : 's'}',
                    onTap: () => context.push(Routes.eventDraws(eventId)),
                  ),
                  _Row(
                    icon: AppIcons.megaphone,
                    title: 'Announcements',
                    subtitle: 'Message everyone linked to the meet, now or at a set time.',
                    onTap: () => context.push(Routes.eventAnnouncements(eventId)),
                  ),
                  _Row(
                    icon: AppIcons.usersThree,
                    title: 'Crew',
                    subtitle: 'Co-hosts and check-in crew. Add from friends or by @handle.',
                    onTap: () => context.push(Routes.eventCrew(eventId)),
                  ),
                  _Row(
                    icon: AppIcons.link,
                    title: 'Invite QR',
                    subtitle: 'A code new people scan to join TT Spot through your meet.',
                    onTap: () => context.push('/event/$eventId/invite'),
                  ),
                  _Row(
                    icon: AppIcons.mapTrifold,
                    title: 'Floorplan',
                    subtitle: 'Levels, zones and pins for car parks and halls.',
                    onTap: () => context.push('/event/$eventId/floorplan/edit'),
                  ),
                  _Row(
                    icon: AppIcons.chartBar,
                    title: 'Turnout report',
                    subtitle: 'Verified check-ins, cars by make, arrivals. Share it with sponsors.',
                    onTap: () => context.push(Routes.eventReport(eventId)),
                  ),
                ],
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
                  child: Text(
                    r.isCrewOnly
                        ? 'You\'re on the crew: check people in, confirm arrivals and hand over prizes. You can\'t enter this meet\'s lucky draw.'
                        : 'Lucky draws are free to enter, one entry per checked-in member. Prizes are yours to provide; TT Spot provides the platform.',
                    style: TextStyle(fontSize: 12, color: AppColors.textMuted, height: 1.4),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _Head extends StatelessWidget {
  const _Head(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 4),
        child: Text(text, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, letterSpacing: 1, color: AppColors.textSecondary)),
      );
}

class _Row extends StatelessWidget {
  const _Row({required this.icon, required this.title, required this.subtitle, required this.onTap});
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => ListTile(
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(color: AppColors.surfaceGray, borderRadius: BorderRadius.circular(AppRadius.md)),
          child: Icon(icon, size: 21, color: AppColors.textPrimary),
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
        subtitle: Text(subtitle, style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary, height: 1.3)),
        trailing: Icon(AppIcons.caretRight, size: 18, color: AppColors.textMuted),
        onTap: onTap,
      );
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
