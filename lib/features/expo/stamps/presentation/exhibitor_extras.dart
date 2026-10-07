import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_icons.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/dates.dart';
import '../../expo_routes.dart';
import '../application/stamps_providers.dart';
import '../application/stamps_scan.dart';
import '../domain/stamps_models.dart';

/// Inside the exhibitor sheet: stamp status, freebie, leads for staff.
/// Draws nothing when none of that applies.
class ExhibitorExtras extends ConsumerWidget {
  const ExhibitorExtras({super.key, required this.eventId, required this.exhibitorId});
  final String eventId;
  final String exhibitorId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final info = ref.watch(exhibitorExtrasProvider(exhibitorId)).value;
    if (info == null || info.isEmpty) return const SizedBox.shrink();
    return ExhibitorExtrasView(
      info: info,
      onStamps: () => context.push(ExpoRoutes.stamps(eventId)),
      onFreebie: () => context.push(stampsRouteAfterScan(eventId, exhibitorId)),
      onLeads: () => context.push(ExpoRoutes.leads(eventId, exhibitorId)),
    );
  }
}

/// The rows themselves, split out so they can be tested without a server.
class ExhibitorExtrasView extends StatelessWidget {
  const ExhibitorExtrasView({super.key, required this.info, this.onStamps, this.onFreebie, this.onLeads});
  final ExhibitorExtrasInfo info;
  final VoidCallback? onStamps;
  final VoidCallback? onFreebie;
  final VoidCallback? onLeads;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[
      if (info.stampStop)
        info.stampedAt != null
            ? _Line(icon: AppIcons.checkCircleFill, color: AppColors.success, text: 'Stamped · ${formatTime(info.stampedAt!)}', onTap: onStamps)
            : _Line(icon: AppIcons.stamp, text: 'Scan the booth QR to get a stamp', onTap: onStamps),
      if (info.freebieState != FreebieState.none && (info.freebie ?? '').isNotEmpty)
        _Line(
          icon: AppIcons.gift,
          color: info.freebieState == FreebieState.available ? AppColors.brand : null,
          text: switch (info.freebieState) {
            FreebieState.available => '${freeLabel(info.freebie!)} · ready, tap to collect',
            FreebieState.redeemed => '${freeLabel(info.freebie!)} · collected',
            FreebieState.out => '${freeLabel(info.freebie!)} · all gone',
            _ => '${freeLabel(info.freebie!)} · stamp to unlock',
          },
          onTap: info.freebieState == FreebieState.available ? onFreebie : null,
        ),
      if (info.amStaff) _Line(icon: AppIcons.addressBook, text: 'Leads (${info.leadCount ?? 0})', onTap: onLeads, chevron: true),
    ];
    if (rows.isEmpty) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(color: AppColors.surfaceGray, borderRadius: BorderRadius.circular(AppRadius.lg)),
      child: Column(mainAxisSize: MainAxisSize.min, children: rows),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line({required this.icon, required this.text, this.color, this.onTap, this.chevron = false});
  final IconData icon;
  final String text;
  final Color? color;
  final VoidCallback? onTap;
  final bool chevron;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          child: Row(
            children: [
              Icon(icon, size: 20, color: color ?? AppColors.textPrimary),
              const SizedBox(width: 10),
              Expanded(
                child: Text(text, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
              ),
              if (chevron) Icon(AppIcons.caretRight, size: 16, color: AppColors.textSecondary),
            ],
          ),
        ),
      );
}
