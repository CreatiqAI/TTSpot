import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/app_router.dart';
import '../../../../core/theme/app_icons.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/dates.dart';
import '../../../../core/utils/friendly_error.dart';
import '../../../../core/widgets/user_avatar.dart';
import '../../../events/domain/event.dart';
import '../../../social/application/chat_providers.dart';
import '../../application/vendors_providers.dart';
import '../../domain/vendor.dart';

/// Plan status for the partner overview: RM 69 / month + 1 % of every voucher bill.
class PartnerPlanCard extends StatelessWidget {
  const PartnerPlanCard({super.key, required this.vendor});
  final Vendor vendor;

  @override
  Widget build(BuildContext context) {
    final until = vendor.planUntil;
    final active = until != null && until.isAfter(DateTime.now());
    final daysLeft = until == null ? 0 : until.difference(DateTime.now()).inDays;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 14, 16, 0),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: active ? AppColors.success.withValues(alpha: 0.1) : AppColors.brand.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Row(
        children: [
          Icon(active ? AppIcons.checkCircle : AppIcons.warning, color: active ? AppColors.success : AppColors.brand),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(active ? 'Partner plan active' : 'Partner plan not active', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5)),
                Text(
                  active
                      ? 'Until ${formatDate(until)}${daysLeft <= 7 ? ' · $daysLeft day${daysLeft == 1 ? '' : 's'} left' : ''}. RM 69 / month + 1 % of each voucher bill.'
                      : 'RM 69 / month + 1 % of each voucher bill. Message TT Spot to renew.',
                  style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary, height: 1.35),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Upcoming meets a partner might sponsor or advertise at. Message the host.
class SponsorEventsSection extends ConsumerWidget {
  const SponsorEventsSection({super.key});

  Future<void> _message(BuildContext context, WidgetRef ref, Event e) async {
    try {
      final id = await ref.read(chatActionsProvider).openVendorDmWith(e.organizerId);
      if (context.mounted) context.push(Routes.chat(id));
    } catch (err) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(err))));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final events = ref.watch(sponsorEventsProvider).value ?? const <Event>[];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 22, 16, 6),
          child: Text('MEETS TO SPONSOR · ${events.length}', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 1, color: AppColors.textSecondary)),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
          child: Text('Every upcoming meet in the next 30 days. Message the host about sponsorship, banners or a booth.', style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary, height: 1.35)),
        ),
        if (events.isEmpty)
          Padding(padding: const EdgeInsets.fromLTRB(16, 4, 16, 8), child: Text('Nothing scheduled yet.', style: TextStyle(fontSize: 13, color: AppColors.textSecondary)))
        else
          for (final e in events.take(6))
            ListTile(
              dense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 16),
              leading: Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: AppColors.surfaceGray, borderRadius: BorderRadius.circular(12)),
                child: Icon(e.type == EventType.tt ? AppIcons.coffee : AppIcons.flagCheckered, size: 20),
              ),
              title: Text(e.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
              subtitle: Text('${formatEventDateFriendly(e.startsAt)} · ${e.attendeeCount} going${e.clubName == null ? '' : ' · ${e.clubName}'}', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
              trailing: TextButton(style: TextButton.styleFrom(visualDensity: VisualDensity.compact), onPressed: () => _message(context, ref, e), child: const Text('Message host')),
              onTap: () => context.push(Routes.event(e.id)),
            ),
      ],
    );
  }
}

/// Every car club on TT Spot with size and what they drive.
class ClubInsightsSection extends ConsumerWidget {
  const ClubInsightsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final clubs = ref.watch(vendorClubInsightsProvider).value ?? const <VendorClubInsight>[];
    final members = clubs.fold(0, (a, c) => a + c.members);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 22, 16, 6),
          child: Text('CAR CLUBS ON TT SPOT · ${clubs.length}', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 1, color: AppColors.textSecondary)),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
          child: Text('$members club memberships. Tap a club to see its page and members.', style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary, height: 1.35)),
        ),
        for (final c in clubs)
          ListTile(
            dense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 16),
            leading: UserAvatar(url: c.avatarUrl, name: c.name, size: 40),
            title: Row(
              children: [
                Flexible(child: Text(c.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14))),
                if (c.tier == 'official') ...[const SizedBox(width: 6), const Icon(AppIcons.sealCheck, size: 14, color: Color(0xFFB8860B))],
              ],
            ),
            subtitle: Text(
              '${c.members} member${c.members == 1 ? '' : 's'}${c.homeState == null ? '' : ' · ${c.homeState}'}${c.topMakes.isEmpty ? '' : ' · ${c.topMakes.map((m) => '${m.$1} ×${m.$2}').join(', ')}'}',
              maxLines: 2,
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
            trailing: Icon(AppIcons.caretRight, size: 16, color: AppColors.textMuted),
            onTap: () => context.push(Routes.club(c.id)),
          ),
      ],
    );
  }
}
