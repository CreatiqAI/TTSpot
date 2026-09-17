import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/dates.dart';
import '../../../core/utils/friendly_error.dart';
import '../../../core/widgets/user_avatar.dart';
import '../application/vendors_providers.dart';
import '../domain/vendor.dart';

/// Admins only: partner applications, official-club requests, and every
/// active partner's plan (RM 69 / month, extended by hand after payment).
class AdminPartnersScreen extends ConsumerWidget {
  const AdminPartnersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final queue = ref.watch(adminPartnerQueueProvider);
    final official = ref.watch(adminOfficialQueueProvider).value ?? const <OfficialClubRequest>[];
    final partners = ref.watch(adminPartnersListProvider).value ?? const <AdminPartner>[];
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(AppIcons.arrowLeft), onPressed: () => context.pop()),
        title: const Text('Partner applications'),
        actions: [
          IconButton(tooltip: 'Commission report', icon: const Icon(AppIcons.chartBar), onPressed: () => context.push(Routes.adminCommission)),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(adminPartnerQueueProvider);
          ref.invalidate(adminOfficialQueueProvider);
          ref.invalidate(adminPartnersListProvider);
          await ref.read(adminPartnerQueueProvider.future);
        },
        child: queue.when(
          loading: () => const Center(child: CircularProgressIndicator(strokeWidth: 2)),
          error: (e, _) => Center(child: Text(friendlyError(e))),
          data: (list) => ListView(
            padding: const EdgeInsets.only(bottom: 40),
            children: [
              _Head('APPLICATIONS · ${list.length}'),
              if (list.isEmpty)
                const Padding(padding: EdgeInsets.fromLTRB(16, 0, 16, 8), child: Text('No applications waiting.'))
              else
                for (var i = 0; i < list.length; i++) ...[
                  if (i > 0) const Divider(height: 24),
                  _Card(app: list[i]),
                ],
              _Head('OFFICIAL CLUBS · ${official.where((c) => c.tier == 'official').length} · ${official.where((c) => c.tier != 'official').length} WAITING'),
              if (official.isEmpty)
                const Padding(padding: EdgeInsets.fromLTRB(16, 0, 16, 8), child: Text('No clubs asking, none official yet.'))
              else
                for (final c in official) _OfficialRow(c: c),
              _Head('PARTNERS · ${partners.length}'),
              for (final p in partners) _PartnerRow(p: p),
            ],
          ),
        ),
      ),
    );
  }
}

class _Head extends StatelessWidget {
  const _Head(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 8),
        child: Text(text, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, letterSpacing: 1, color: AppColors.textSecondary)),
      );
}

/// A club asking to go official (approve after RM 69.90 is paid), or one that already is.
class _OfficialRow extends ConsumerWidget {
  const _OfficialRow({required this.c});
  final OfficialClubRequest c;

  Future<void> _set(BuildContext context, WidgetRef ref, String tier) async {
    try {
      await ref.read(vendorActionsProvider).setClubTier(c.id, tier);
    } catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e))));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isOfficial = c.tier == 'official';
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      leading: UserAvatar(url: c.avatarUrl, name: c.name, size: 40),
      title: Text(c.name, style: const TextStyle(fontWeight: FontWeight.w700)),
      subtitle: Text(
        isOfficial
            ? 'Official until ${c.officialUntil == null ? '—' : formatDate(c.officialUntil!)} · ${c.members} members · @${c.ownerUsername ?? ''}'
            : 'Asked ${c.requestedAt == null ? '' : timeAgo(c.requestedAt!)} · ${c.members} members · @${c.ownerUsername ?? ''} · RM 69.90 / month',
        style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
      ),
      trailing: isOfficial
          ? TextButton(style: TextButton.styleFrom(visualDensity: VisualDensity.compact), onPressed: () => _set(context, ref, 'official'), child: const Text('+30 days'))
          : FilledButton(style: FilledButton.styleFrom(visualDensity: VisualDensity.compact, minimumSize: const Size(0, 36)), onPressed: () => _set(context, ref, 'official'), child: const Text('Approve 30 d')),
      onTap: () => context.push(Routes.club(c.id)),
      onLongPress: isOfficial ? () => _set(context, ref, 'underground') : null,
    );
  }
}

/// An active partner: plan status, extend after payment.
class _PartnerRow extends ConsumerWidget {
  const _PartnerRow({required this.p});
  final AdminPartner p;

  @override
  Widget build(BuildContext context, WidgetRef ref) => ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16),
        leading: ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: SizedBox(width: 40, height: 40, child: p.logoUrl == null ? ColoredBox(color: AppColors.surfaceGray, child: Icon(AppIcons.storefront, size: 18, color: AppColors.textSecondary)) : Image.network(p.logoUrl!, fit: BoxFit.cover)),
        ),
        title: Text(p.name, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text(
          '${p.planActive ? 'Plan until ${formatDate(p.planUntil!)}' : 'Plan NOT active'} · ${p.state ?? '—'} · ${p.liveVouchers} live · ${p.redemptions30d} redeemed / 30 d',
          style: TextStyle(fontSize: 12, color: p.planActive ? AppColors.textSecondary : AppColors.brand),
        ),
        trailing: TextButton(
          style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
          onPressed: () async {
            try {
              await ref.read(vendorActionsProvider).setVendorPlan(p.id, 30);
            } catch (e) {
              if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e))));
            }
          },
          child: const Text('+30 days'),
        ),
        onTap: () => context.push(Routes.partner(p.id)),
      );
}

class _Card extends ConsumerStatefulWidget {
  const _Card({required this.app});
  final PartnerApplication app;

  @override
  ConsumerState<_Card> createState() => _CardState();
}

class _CardState extends ConsumerState<_Card> {
  bool _busy = false;

  Future<void> _decide(bool approve) async {
    String? note;
    if (!approve) {
      final c = TextEditingController();
      note = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Reject application'),
          content: TextField(controller: c, autofocus: true, maxLines: 2, decoration: const InputDecoration(hintText: 'Reason the applicant will see')),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(ctx, c.text.trim()), child: const Text('Reject')),
          ],
        ),
      );
      if (note == null) return;
    }
    setState(() => _busy = true);
    try {
      await ref.read(vendorActionsProvider).reviewApplication(widget.app.id, approve: approve, note: note?.isEmpty ?? true ? null : note);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.app;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              GestureDetector(
                onTap: a.userId == null ? null : () => context.push(Routes.profile(a.userId!)),
                child: UserAvatar(url: a.avatarUrl, name: a.username, size: 36),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('@${a.username ?? ''}', style: const TextStyle(fontWeight: FontWeight.w700)),
                    Text('applied ${timeAgo(a.createdAt)}', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.md),
                child: a.logoUrl == null
                    ? Container(width: 64, height: 64, color: AppColors.surfaceGray, child: Icon(a.kind == ApplicationKind.club ? AppIcons.usersThree : AppIcons.storefront, color: AppColors.textSecondary))
                    : Image.network(a.logoUrl!, width: 64, height: 64, fit: BoxFit.cover),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(child: Text(a.businessName, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16))),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: a.kind == ApplicationKind.club ? AppColors.warnColor : AppColors.surfaceGray,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(a.kind == ApplicationKind.club ? 'CAR CLUB' : 'VENDOR', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, letterSpacing: 0.6, color: a.kind == ApplicationKind.club ? Colors.white : AppColors.textPrimary)),
                        ),
                      ],
                    ),
                    Text(businessTypeLabel(a.businessType), style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
                    if (a.address != null) Text(a.address!, style: const TextStyle(fontSize: 13)),
                    if (a.phone != null) Text(a.phone!, style: const TextStyle(fontSize: 13)),
                    if (a.ssmNo != null) Text('SSM ${a.ssmNo}${a.state == null ? '' : ' · ${a.state}'}', style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
                  ],
                ),
              ),
            ],
          ),
          if (a.description != null) ...[
            const SizedBox(height: 8),
            Text(a.description!, style: const TextStyle(fontSize: 13, height: 1.35)),
          ],
          if (a.shopPhotoUrl != null) ...[
            const SizedBox(height: 10),
            ClipRRect(borderRadius: BorderRadius.circular(AppRadius.md), child: Image.network(a.shopPhotoUrl!, height: 150, width: double.infinity, fit: BoxFit.cover)),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _busy ? null : () => _decide(false),
                  icon: const Icon(AppIcons.xCircle, size: 18, color: AppColors.danger),
                  label: const Text('Reject', style: TextStyle(color: AppColors.danger)),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.icon(
                  onPressed: _busy ? null : () => _decide(true),
                  icon: const Icon(AppIcons.checkCircle, size: 18),
                  label: const Text('Approve'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
