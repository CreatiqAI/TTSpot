import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/app_art.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/dates.dart';
import '../../../core/utils/friendly_error.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/user_avatar.dart';
import '../../accounts/presentation/account_switcher.dart';
import '../../accounts/presentation/account_title.dart';
import '../../social/domain/post.dart';
import '../application/vendors_providers.dart';
import '../domain/vendor.dart';
import 'widgets/hours_editor.dart';
import 'widgets/partner_reach.dart';

/// The partner's overview: who you are, what to finish setting up, the last
/// 30 days in numbers, the four things you do most, and recent redemptions.
/// Products and vouchers have their own tabs.
class VendorDashboardScreen extends ConsumerWidget {
  const VendorDashboardScreen({super.key, this.embedded = false});

  /// Inside the partner tab bar (title is the account switcher, no back).
  final bool embedded;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vendor = ref.watch(myVendorProvider);
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        centerTitle: !embedded,
        titleSpacing: embedded ? 16 : null,
        leading: embedded ? null : IconButton(icon: const Icon(AppIcons.arrowLeft), onPressed: () => context.pop()),
        title: embedded
            ? AccountTitle(text: vendor.value?.name ?? 'Partner', onTap: () => showAccountSwitcher(context, ref))
            : const Text('Overview'),
        actions: [
          if (vendor.value != null) IconButton(tooltip: 'My partner page', icon: const Icon(AppIcons.eye), onPressed: () => context.push(Routes.partner(vendor.value!.id))),
          IconButton(tooltip: 'Statement', icon: const Icon(AppIcons.chartBar), onPressed: () => context.push(Routes.vendorReport)),
        ],
      ),
      body: vendor.when(
        loading: () => const Center(child: CircularProgressIndicator(strokeWidth: 2)),
        error: (e, _) => Center(child: Text(friendlyError(e))),
        data: (v) => v == null
            ? EmptyState(art: AppArt.handshake, title: 'Not a partner yet', subtitle: 'Apply and an admin will review it.', actionLabel: 'Apply', onAction: () => context.pushReplacement(Routes.partnerApply))
            : _Body(vendor: v),
      ),
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({required this.vendor});
  final Vendor vendor;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final products = ref.watch(vendorProductsProvider).value ?? const <Product>[];
    final vouchers = ref.watch(vendorVouchersProvider).value ?? const <Voucher>[];
    final redemptions = (ref.watch(vendorRedemptionsProvider).value ?? const <Redemption>[]).take(5).toList();
    final ratePct = (vendor.commissionRate * 100).toStringAsFixed(vendor.commissionRate * 100 % 1 == 0 ? 0 : 2);
    final status = OpeningHours.fromJson(vendor.hoursJson).status();
    final liveVouchers = vouchers.where((x) => x.active && !x.ended && !x.soldOut).length;

    final steps = <_Step>[
      _Step('Pin your shop on the map', 'Pick the address once', vendor.lat != null, () => context.push(Routes.vendorEdit)),
      _Step('Set opening hours', 'Members see Open now / Closed', !OpeningHours.fromJson(vendor.hoursJson).isEmpty, () => context.push(Routes.vendorEdit)),
      _Step('Add shop photos', 'Shopfront, bays, work you did', vendor.photoUrls.isNotEmpty, () => context.push(Routes.vendorEdit)),
      _Step('Add a product', 'Up to 5, with variants', products.isNotEmpty, () => context.push(Routes.productNew)),
      _Step('Publish a voucher', 'Lands in every member\'s Rewards', vouchers.isNotEmpty, () => context.push(Routes.voucherNew)),
    ];
    final done = steps.where((s) => s.done).length;

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(myVendorProvider);
        ref.invalidate(vendorVouchersProvider);
        ref.invalidate(vendorRedemptionsProvider);
        ref.invalidate(vendorProductsProvider);
        ref.invalidate(sponsorEventsProvider);
        ref.invalidate(vendorClubInsightsProvider);
        await ref.read(myVendorProvider.future);
      },
      child: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          // ---- who you are
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(AppRadius.lg),
                  child: vendor.logoUrl == null
                      ? Container(width: 64, height: 64, color: AppColors.surfaceGray, child: Icon(AppIcons.storefront, color: AppColors.textSecondary, size: 28))
                      : Image(image: CachedNetworkImageProvider(vendor.logoUrl!), width: 64, height: 64, fit: BoxFit.cover),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(vendor.name, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, height: 1.1)),
                      const SizedBox(height: 3),
                      Text(businessTypeLabel(vendor.type), style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
                      if (status != null) ...[
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Container(width: 7, height: 7, decoration: BoxDecoration(shape: BoxShape.circle, color: status.startsWith('Open') ? AppColors.success : AppColors.textMuted)),
                            const SizedBox(width: 6),
                            Text(status, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: status.startsWith('Open') ? AppColors.success : AppColors.textSecondary)),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                IconButton(tooltip: 'Edit shop', icon: const Icon(AppIcons.pencilSimple), onPressed: () => context.push(Routes.vendorEdit)),
              ],
            ),
          ),

          // ---- the four things you do most
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 0),
            child: Row(
              children: [
                _Action(icon: AppIcons.scan, label: 'Scan\nvoucher', primary: true, onTap: () => context.push(Routes.scan)),
                const SizedBox(width: 8),
                _Action(icon: AppIcons.ticket, label: 'New\nvoucher', onTap: () => context.push(Routes.voucherNew)),
                const SizedBox(width: 8),
                _Action(icon: AppIcons.shoppingBag, label: 'Add\nproduct', onTap: products.length >= 5 ? null : () => context.push(Routes.productNew)),
                const SizedBox(width: 8),
                _Action(icon: AppIcons.image, label: 'Post as\nshop', onTap: () => context.push(Routes.createPost(PostKind.post, vendorId: vendor.id))),
              ],
            ),
          ),

          PartnerPlanCard(vendor: vendor),

          // ---- finish setting up (hides itself when everything is done)
          if (done < steps.length)
            Container(
              margin: const EdgeInsets.fromLTRB(16, 18, 16, 0),
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
              decoration: BoxDecoration(color: AppColors.surfaceGray, borderRadius: BorderRadius.circular(AppRadius.lg)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Expanded(child: Text('Finish setting up', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15))),
                      Text('$done of ${steps.length}', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: AppColors.textSecondary)),
                    ],
                  ),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(999),
                    child: LinearProgressIndicator(value: done / steps.length, minHeight: 5, backgroundColor: AppColors.surface, color: AppColors.brand),
                  ),
                  const SizedBox(height: 4),
                  for (final s in steps.where((s) => !s.done))
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(AppIcons.plusCircle, size: 20, color: AppColors.brand),
                      title: Text(s.title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                      subtitle: Text(s.subtitle, style: const TextStyle(fontSize: 12)),
                      trailing: Icon(AppIcons.caretRight, size: 14, color: AppColors.textMuted),
                      onTap: s.onTap,
                    ),
                ],
              ),
            ),

          // ---- last 30 days
          const Padding(padding: EdgeInsets.fromLTRB(16, 22, 16, 8), child: _SectionTitle('LAST 30 DAYS')),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              children: [
                Row(
                  children: [
                    _Stat(label: 'Page views', value: '${vendor.views30d}'),
                    const SizedBox(width: 8),
                    _Stat(label: 'Check-ins', value: '${vendor.checkins30d}'),
                    const SizedBox(width: 8),
                    _Stat(label: 'Claimed', value: '${vendor.claims30d}'),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    _Stat(label: 'Redeemed', value: '${vendor.redemptions30d}'),
                    const SizedBox(width: 8),
                    _Stat(label: 'Bills', value: rm(vendor.bill30d)),
                    const SizedBox(width: 8),
                    _Stat(label: 'Commission $ratePct%', value: rm(vendor.commission30d), highlight: true),
                  ],
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Text(
              '$liveVouchers live voucher${liveVouchers == 1 ? '' : 's'} · ${products.where((p) => p.active).length} product${products.length == 1 ? '' : 's'} on your page. Commission is $ratePct% of each bill you enter at redemption, settled monthly.',
              style: TextStyle(fontSize: 12, color: AppColors.textMuted, height: 1.4),
            ),
          ),

          // ---- reach: who to sponsor, who is out there
          const SponsorEventsSection(),
          const ClubInsightsSection(),

          // ---- recent redemptions
          const Padding(padding: EdgeInsets.fromLTRB(16, 22, 16, 6), child: _SectionTitle('RECENT REDEMPTIONS')),
          if (redemptions.isEmpty)
            Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text('Nothing redeemed yet. Tap Scan voucher when a member shows their QR.', style: TextStyle(color: AppColors.textSecondary)),
            ),
          for (final r in redemptions)
            ListTile(
              dense: true,
              leading: UserAvatar(url: r.avatarUrl, name: r.username, size: 36),
              title: Text('@${r.username ?? ''} · ${r.title}', maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text('${timeAgo(r.createdAt)}${r.note == null ? '' : ' · ${r.note}'}', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
              trailing: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(rm(r.billAmount), style: const TextStyle(fontWeight: FontWeight.w700)),
                  Text('fee ${rm(r.commissionAmount)}', style: TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                ],
              ),
            ),
          if (redemptions.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextButton(onPressed: () => context.push(Routes.vendorReport), child: const Text('See full statement')),
            ),
        ],
      ),
    );
  }
}

class _Step {
  const _Step(this.title, this.subtitle, this.done, this.onTap);
  final String title;
  final String subtitle;
  final bool done;
  final VoidCallback onTap;
}

class _Action extends StatelessWidget {
  const _Action({required this.icon, required this.label, required this.onTap, this.primary = false});
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final fg = primary ? Colors.white : (onTap == null ? AppColors.textMuted : AppColors.textPrimary);
    return Expanded(
      child: Material(
        color: primary ? AppColors.brand : AppColors.surfaceGray,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.md),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: Column(
              children: [
                Icon(icon, size: 24, color: fg),
                const SizedBox(height: 6),
                Text(label, textAlign: TextAlign.center, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, height: 1.15, color: fg)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value, this.highlight = false});
  final String label;
  final String value;
  final bool highlight;

  @override
  Widget build(BuildContext context) => Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
          decoration: BoxDecoration(
            color: highlight ? AppColors.brand : AppColors.surfaceGray,
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text(value, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: highlight ? Colors.white : AppColors.textPrimary))),
              const SizedBox(height: 2),
              Text(label, style: TextStyle(fontSize: 11, color: highlight ? Colors.white70 : AppColors.textSecondary)),
            ],
          ),
        ),
      );
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Text(text, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 1, color: AppColors.textSecondary));
}
