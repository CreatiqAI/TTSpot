import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/dates.dart';
import '../../events/domain/event.dart';
import '../../events/presentation/end_event.dart';
import '../../events/presentation/whos_here_sheet.dart';
import '../../expo/expo_routes.dart';
import '../../floorplan/presentation/floorplan_screen.dart' show FloorplanRoutes;
import '../domain/organizer_models.dart';

/// The organizer tools, in five groups. The organizer view of a big event
/// shows one tab per group; the Organizer tools screen lists them as
/// sections.
enum OrganizerGroup {
  dashboard('Dashboard', AppIcons.presentationChart),
  door('Door', AppIcons.qrCode),
  program('Program', AppIcons.calendarBlank),
  exhibitors('Exhibitors', AppIcons.storefront),
  team('Team', AppIcons.usersThree);

  const OrganizerGroup(this.label, this.icon);
  final String label;
  final IconData icon;
}

/// The groups my role opens. Crew run the door; the host circle (host,
/// co-hosts, club officers, admins) gets everything.
List<OrganizerGroup> organizerGroupsFor(EventRole r) {
  if (r.isHostCircle) return OrganizerGroup.values;
  if (r.onTeam) return const [OrganizerGroup.door];
  return const [];
}

/// One row: opens a route, or runs [action] (a sheet).
class OrganizerTool {
  const OrganizerTool({required this.id, required this.icon, required this.title, required this.subtitle, this.route, this.action, this.danger = false});
  final String id;
  final IconData icon;
  final String title;
  final String subtitle;
  final String? route;
  final void Function(BuildContext context)? action;

  /// Can't be undone (end / cancel): drawn in red.
  final bool danger;

  bool get enabled => route != null || action != null;
}

/// The rows in [group] for [role]. [event] feeds the door list (and its
/// count) and the end / cancel row; [draws] the lucky draw line. [now] is
/// for tests.
List<OrganizerTool> organizerTools(
  OrganizerGroup group, {
  required String eventId,
  required EventRole role,
  Event? event,
  List<LuckyDraw> draws = const [],
  DateTime? now,
}) {
  final host = role.isHostCircle;
  switch (group) {
    case OrganizerGroup.dashboard:
      if (!host) return const [];
      return [
        OrganizerTool(
          id: 'dashboard',
          icon: AppIcons.presentationChart,
          title: 'Live dashboard',
          subtitle: 'Check-ins, registrations, booth visits, leads and votes. Export CSV.',
          route: ExpoRoutes.dashboard(eventId),
        ),
      ];
    case OrganizerGroup.door:
      final e = event;
      return [
        OrganizerTool(
          id: 'checkin-qr',
          icon: AppIcons.qrCode,
          title: 'Check-in QR',
          subtitle: 'Members scan it to check in. It changes every 30 seconds.',
          route: Routes.eventQr(eventId),
        ),
        if (host)
          OrganizerTool(
            id: 'door-qr',
            icon: AppIcons.link,
            title: 'Door QR',
            subtitle: 'Print it at the entrance. Checks members in and brings new people to TT Spot.',
            route: FloorplanRoutes.invite(eventId),
          ),
        OrganizerTool(
          id: 'door-list',
          icon: AppIcons.listChecks,
          title: 'Door list',
          subtitle: e == null ? 'Loading…' : '${e.checkinCount} checked in. Confirm who is really here.',
          action: e == null ? null : (context) => showWhosHereSheet(context, e),
        ),
        OrganizerTool(
          id: 'prize-scan',
          icon: AppIcons.scan,
          title: 'Scan prize claim',
          subtitle: 'Winners show a claim QR. Scan it, hand over the prize.',
          route: Routes.prizeScan,
        ),
        if (host) ...[
          OrganizerTool(
            id: 'checkin-area',
            icon: AppIcons.mapPinArea,
            title: 'Check-in area',
            subtitle: 'How far from the pin people can check in. Big halls need more.',
            route: ExpoRoutes.checkinArea(eventId),
          ),
          OrganizerTool(
            id: 'registration',
            icon: AppIcons.clipboardText,
            title: 'Registration form',
            subtitle: 'Questions after check-in. Export the answers as CSV.',
            route: ExpoRoutes.registrationForm(eventId),
          ),
        ],
      ];
    case OrganizerGroup.program:
      if (!host) return const [];
      final next = draws.where((d) => d.status == DrawStatus.scheduled).firstOrNull;
      return [
        OrganizerTool(
          id: 'schedule',
          icon: AppIcons.calendarBlank,
          title: 'Schedule',
          subtitle: 'Stage times. People get a reminder 10 minutes before.',
          route: ExpoRoutes.scheduleEditor(eventId),
        ),
        OrganizerTool(
          id: 'draws',
          icon: AppIcons.gift,
          title: 'Lucky draw',
          subtitle: next == null
              ? (draws.any((d) => d.status == DrawStatus.drawn) ? 'Drawn. Open the stage screen for results.' : 'Free entry for checked-in members. Set prizes and a time.')
              : '${next.title} at ${formatTime(next.drawAt)} · ${next.winnerCount} winner${next.winnerCount == 1 ? '' : 's'}',
          route: Routes.eventDraws(eventId),
        ),
        OrganizerTool(
          id: 'vote',
          icon: AppIcons.trophy,
          title: 'Show car vote',
          subtitle: "People's Choice. One vote per checked-in member.",
          route: ExpoRoutes.contestEditor(eventId),
        ),
        OrganizerTool(
          id: 'announcements',
          icon: AppIcons.megaphone,
          title: 'Announcements',
          subtitle: 'Message everyone linked to the event, now or at a set time.',
          route: Routes.eventAnnouncements(eventId),
        ),
      ];
    case OrganizerGroup.exhibitors:
      if (!host) return const [];
      return [
        OrganizerTool(
          id: 'exhibitors',
          icon: AppIcons.storefront,
          title: 'Exhibitors',
          subtitle: 'Add or paste a list. Link them to booths on the floor plan.',
          route: ExpoRoutes.exhibitorsEditor(eventId),
        ),
        OrganizerTool(
          id: 'booths',
          icon: AppIcons.stamp,
          title: 'Stamps & booths',
          subtitle: 'Stamp stops, freebies, booth staff and booth QR codes.',
          route: ExpoRoutes.boothSetup(eventId),
        ),
        OrganizerTool(
          id: 'floorplan',
          icon: AppIcons.mapTrifold,
          title: 'Floor plan',
          subtitle: 'Levels, booths, zones and pins for halls and car parks.',
          route: FloorplanRoutes.edit(eventId),
        ),
      ];
    case OrganizerGroup.team:
      if (!host) return const [];
      final e = event;
      final close = e == null ? null : eventCloseAction(e, now ?? DateTime.now());
      return [
        OrganizerTool(
          id: 'crew',
          icon: AppIcons.usersThree,
          title: 'Crew',
          subtitle: 'Co-hosts and check-in crew. Add from friends or by @handle.',
          route: Routes.eventCrew(eventId),
        ),
        OrganizerTool(
          id: 'report',
          icon: AppIcons.chartBar,
          title: 'Turnout report',
          subtitle: 'Verified check-ins, cars by make, arrivals. Share it with sponsors.',
          route: Routes.eventReport(eventId),
        ),
        // Last: end it while it runs, cancel it before the start.
        if (e != null && close != null)
          OrganizerTool(
            id: 'close-event',
            icon: eventCloseIcon(close),
            title: eventCloseLabel(close),
            subtitle: close == EventCloseAction.end ? 'Close it for everyone. Check-ins stop.' : 'Call it off. Everyone who joined gets told.',
            action: (context) => closeEventFlow(context, e),
            danger: true,
          ),
      ];
  }
}

/// One tool row: icon box, title, one-line purpose, caret.
class OrganizerToolTile extends StatelessWidget {
  const OrganizerToolTile({super.key, required this.tool});
  final OrganizerTool tool;

  @override
  Widget build(BuildContext context) {
    final t = tool;
    final fg = t.danger ? AppColors.danger : AppColors.textPrimary;
    return ListTile(
      key: ValueKey('tool-${t.id}'),
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(color: AppColors.surfaceGray, borderRadius: BorderRadius.circular(AppRadius.md)),
        child: Icon(t.icon, size: 21, color: fg),
      ),
      title: Text(t.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: fg)),
      subtitle: Text(t.subtitle, maxLines: 3, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary, height: 1.3)),
      trailing: Icon(AppIcons.caretRight, size: 18, color: AppColors.textMuted),
      onTap: !t.enabled
          ? null
          : () {
              final a = t.action;
              if (a != null) {
                a(context);
              } else {
                context.push(t.route!);
              }
            },
    );
  }
}

/// A group's small caps heading.
class OrganizerGroupHead extends StatelessWidget {
  const OrganizerGroupHead(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 4),
        child: Text(text.toUpperCase(), style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, letterSpacing: 1, color: AppColors.textSecondary)),
      );
}

/// The small print under the tools: the crew's limits, or the draw's rules.
String organizerFootnote(EventRole r) => r.isCrewOnly
    ? "You're on the crew: check people in, confirm arrivals and hand over prizes. You can't enter this event's lucky draw."
    : 'Lucky draws are free to enter, one entry per checked-in member. Prizes are yours to provide; TT Spot provides the platform.';
