import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_icons.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../events/application/event_providers.dart';
import '../../../floorplan/presentation/floorplan_screen.dart' show FloorplanRoutes;
import '../../expo_routes.dart';
import '../application/door_providers.dart';
import '../domain/door_models.dart';
import 'registration_sheet.dart';

/// One tile on the hub card.
class HubTileData {
  const HubTileData({required this.icon, required this.label, required this.route, this.badge});
  final IconData icon;
  final String label;
  final String route;

  /// "#0427", "12", "3/8".
  final String? badge;
}

/// The tiles worth showing for [h], in order. Only tiles with data.
/// [pass] / [booths]: include my pass and the booths I staff.
List<HubTileData> hubTiles(String eventId, EventHub h, {bool pass = true, bool booths = true}) => [
      if (pass && h.checkedIn) HubTileData(icon: AppIcons.ticket, label: 'Pass', route: ExpoRoutes.pass(eventId), badge: h.entry),
      if (h.levels > 0) HubTileData(icon: AppIcons.mapTrifold, label: 'Floor plan', route: FloorplanRoutes.view(eventId)),
      if (h.exhibitors > 0) HubTileData(icon: AppIcons.storefront, label: 'Exhibitors', route: ExpoRoutes.exhibitors(eventId), badge: '${h.exhibitors}'),
      if (h.agenda > 0) HubTileData(icon: AppIcons.calendarBlank, label: 'Schedule', route: ExpoRoutes.schedule(eventId)),
      if (h.stampStops > 0) HubTileData(icon: AppIcons.stamp, label: 'Stamps', route: ExpoRoutes.stamps(eventId), badge: '${h.myStamps}/${h.stampTarget}'),
      if (h.contestId != null) HubTileData(icon: AppIcons.trophy, label: 'Vote', route: ExpoRoutes.vote(eventId, contestId: h.contestId)),
      if (booths)
        for (final b in h.myBooths)
        HubTileData(icon: AppIcons.identificationBadge, label: h.myBooths.length == 1 ? 'My booth' : b.name, route: ExpoRoutes.leads(eventId, b.id)),
    ];

/// Event page: Pass, Floor plan, Exhibitors, Schedule, Stamps, Vote, My booth.
/// Shows only when there's something to show; brings its own bottom spacing.
class EventHubCard extends ConsumerWidget {
  const EventHubCard({super.key, required this.eventId});
  final String eventId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final h = ref.watch(eventHubProvider(eventId)).value;
    if (h == null || !h.hasAnything) return const SizedBox.shrink();
    final tiles = hubTiles(eventId, h);
    final going = ref.watch(eventDetailProvider(eventId)).value?.isAttending ?? false;
    final nudge = h.registration.open && h.registration.required && (h.checkedIn || going);

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (nudge) ...[
            RegistrationNudge(eventId: eventId, questions: h.registration.questions),
            const SizedBox(height: 8),
          ],
          if (tiles.isNotEmpty) HubTileGrid(tiles: tiles),
        ],
      ),
    );
  }
}

/// Tiles in even columns (4 across, 3 on narrow phones). Labels wrap to two
/// lines at most, so big text never overflows.
class HubTileGrid extends StatelessWidget {
  const HubTileGrid({super.key, required this.tiles});
  final List<HubTileData> tiles;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        const gap = 8.0;
        final cols = c.maxWidth >= 340 ? 4 : 3;
        final w = ((c.maxWidth - gap * (cols - 1)) / cols).floorToDouble();
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [for (final t in tiles) SizedBox(width: w, child: _HubTile(t))],
        );
      },
    );
  }
}

class _HubTile extends StatelessWidget {
  const _HubTile(this.t);
  final HubTileData t;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surfaceGray,
      borderRadius: BorderRadius.circular(AppRadius.lg),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        onTap: () => context.push(t.route),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(6, 10, 6, 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(t.icon, size: 22, color: AppColors.textPrimary),
              const SizedBox(height: 4),
              Text(
                t.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
              ),
              if (t.badge != null) ...[
                const SizedBox(height: 3),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(AppRadius.pill)),
                  child: Text(
                    t.badge!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: AppColors.textSecondary),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// "Finish registration": a row that opens the form.
class RegistrationNudge extends StatelessWidget {
  const RegistrationNudge({super.key, required this.eventId, this.questions = 0});
  final String eventId;
  final int questions;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.brand.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(AppRadius.lg),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        onTap: () => showRegistrationSheet(context, eventId),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
          child: Row(
            children: [
              const Icon(AppIcons.clipboardText, size: 22, color: AppColors.brand),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Finish registration', style: TextStyle(fontWeight: FontWeight.w800)),
                    Text(
                      questions <= 0 ? 'The organizer needs a few answers.' : '$questions quick question${questions == 1 ? '' : 's'} for the organizer.',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
              Icon(AppIcons.caretRight, size: 18, color: AppColors.textMuted),
            ],
          ),
        ),
      ),
    );
  }
}
