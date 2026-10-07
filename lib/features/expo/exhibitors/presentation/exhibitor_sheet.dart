import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/router/app_router.dart';
import '../../../../core/theme/app_icons.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/friendly_error.dart';
import '../../expo_routes.dart';
import '../../stamps/presentation/exhibitor_extras.dart';
import '../application/exhibitors_providers.dart';
import '../domain/exhibitor.dart';
import 'exhibitor_widgets.dart';

/// One exhibitor: booths, about, call / email / website, show on the floor
/// plan, and the partner's shop. [onShowOnPlan] replaces the default "open
/// the floor plan" (used when the plan is already open underneath).
Future<void> showExhibitorSheet(BuildContext context, String eventId, String exhibitorId, {VoidCallback? onShowOnPlan}) {
  return showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) => _ExhibitorSheet(
      eventId: eventId,
      exhibitorId: exhibitorId,
      onShowOnPlan: () {
        Navigator.pop(ctx);
        if (onShowOnPlan != null) {
          onShowOnPlan();
        } else if (context.mounted) {
          context.push(ExpoRoutes.floorplanAt(eventId, exhibitorId));
        }
      },
      onOpenShop: (vendorId) {
        Navigator.pop(ctx);
        if (context.mounted) context.push(Routes.partner(vendorId));
      },
    ),
  );
}

class _ExhibitorSheet extends ConsumerWidget {
  const _ExhibitorSheet({required this.eventId, required this.exhibitorId, required this.onShowOnPlan, required this.onOpenShop});
  final String eventId;
  final String exhibitorId;
  final VoidCallback onShowOnPlan;
  final ValueChanged<String> onOpenShop;

  Future<void> _launch(BuildContext context, Uri? uri) async {
    if (uri == null) return;
    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok && context.mounted) _toast(context, "Couldn't open that.");
    } catch (e) {
      if (context.mounted) _toast(context, friendlyError(e));
    }
  }

  void _toast(BuildContext context, String msg) => ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(msg)));

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(eventExhibitorsProvider(eventId));
    final e = exhibitorById(async.value, exhibitorId);
    final maxH = MediaQuery.sizeOf(context).height * 0.85;

    if (e == null) {
      return SizedBox(
        height: 180,
        child: Center(
          child: async.isLoading
              ? const CircularProgressIndicator(strokeWidth: 2)
              : Text(async.hasError ? friendlyError(async.error!) : 'This exhibitor is gone.', style: TextStyle(color: AppColors.textSecondary)),
        ),
      );
    }

    final meta = [if (e.category != null) e.category!, if (e.country != null) e.country!].join(' · ');
    final actions = <Widget>[
      if (phoneUri(e.phone) != null) _ActionTile(icon: AppIcons.phone, label: 'Call', onTap: () => _launch(context, phoneUri(e.phone))),
      if (emailUri(e.email) != null) _ActionTile(icon: AppIcons.envelope, label: 'Email', onTap: () => _launch(context, emailUri(e.email))),
      if (websiteUri(e.website) != null) _ActionTile(icon: AppIcons.globe, label: 'Website', onTap: () => _launch(context, websiteUri(e.website))),
      if (e.partnerVendorId != null) _ActionTile(icon: AppIcons.storefront, label: 'View shop', gold: true, onTap: () => onOpenShop(e.partnerVendorId!)),
    ];
    final onPlan = e.booths.isNotEmpty || e.pinCount > 0;

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxH),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ExhibitorLogo(exhibitor: e, size: 56),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(e.name, maxLines: 3, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, height: 1.2)),
                        const SizedBox(height: 4),
                        Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            if (e.isPartner) const PartnerTag(),
                            if (e.booths.isNotEmpty)
                              Text(
                                '${e.booths.length == 1 ? 'Booth' : 'Booths'} ${e.boothsLabel}',
                                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                              ),
                          ],
                        ),
                        if (meta.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(meta, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (onPlan)
                FilledButton.icon(
                  onPressed: onShowOnPlan,
                  icon: const Icon(AppIcons.mapTrifold, size: 18),
                  label: const Text('Show on floor plan'),
                ),
              if (actions.isNotEmpty) ...[
                const SizedBox(height: 10),
                Row(
                  children: [
                    for (var i = 0; i < actions.length; i++) ...[
                      if (i > 0) const SizedBox(width: 8),
                      Expanded(child: actions[i]),
                    ],
                  ],
                ),
              ],
              ExhibitorExtras(eventId: eventId, exhibitorId: exhibitorId),
              if (e.about != null) ...[
                const SizedBox(height: 16),
                Text('About', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textSecondary)),
                const SizedBox(height: 4),
                Text(e.about!, style: const TextStyle(fontSize: 14.5, height: 1.4)),
              ],
              if (e.address != null) ...[
                const SizedBox(height: 12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(AppIcons.mapPin, size: 16, color: AppColors.textSecondary),
                    const SizedBox(width: 6),
                    Expanded(child: Text(e.address!, style: TextStyle(fontSize: 13, color: AppColors.textSecondary, height: 1.35))),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({required this.icon, required this.label, required this.onTap, this.gold = false});
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool gold;

  @override
  Widget build(BuildContext context) {
    final fg = gold ? kPartnerGoldDeep : AppColors.textPrimary;
    return Material(
      color: gold ? kPartnerGold.withValues(alpha: 0.16) : AppColors.surfaceGray,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 20, color: fg),
              const SizedBox(height: 4),
              Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: fg)),
            ],
          ),
        ),
      ),
    );
  }
}
