import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../../core/supabase/supabase_client.dart';
import '../../../core/theme/app_art.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/dates.dart';
import '../../../core/utils/friendly_error.dart';
import '../../../core/utils/open_external.dart';
import '../../../core/widgets/primary_button.dart';
import '../../events/domain/event.dart';
import '../../social/application/chat_providers.dart';
import '../application/vendors_providers.dart';
import '../domain/vendor.dart';
import '../../social/application/social_providers.dart';
import '../../social/domain/post.dart';
import 'widgets/hours_editor.dart';

/// A partner's page for members: logo, what they do, where, hours, photos,
/// their vouchers, their upcoming events, and a Message button.
class PartnerScreen extends ConsumerWidget {
  const PartnerScreen({super.key, required this.vendorId});
  final String vendorId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vendor = ref.watch(vendorPublicProvider(vendorId));
    final me = ref.watch(currentUserIdProvider);
    return Scaffold(
      body: vendor.when(
        loading: () => const Center(child: CircularProgressIndicator(strokeWidth: 2)),
        error: (e, _) => Center(child: Text(friendlyError(e))),
        data: (v) => v == null ? const Center(child: Text('This partner is no longer on TT Spot.')) : _Body(v: v, me: me),
      ),
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({required this.v, required this.me});
  final PublicVendor v;
  final String? me;

  Future<void> _message(BuildContext context, WidgetRef ref) async {
    try {
      final id = await ref.read(chatActionsProvider).openVendorDm(v.id);
      if (context.mounted) context.push(Routes.chat(id));
    } catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e))));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(partnerViewedProvider(v.id));
    final hours = OpeningHours.fromJson(v.hoursJson);
    final status = hours.status();
    final posts = ref.watch(postsWhereProvider((column: 'vendor_id', value: v.id))).value ?? const <FeedPost>[];
    final vouchers = (ref.watch(shopVouchersProvider).value ?? const <Voucher>[]).where((x) => x.vendorId == v.id).toList();
    final events = ref.watch(vendorEventsProvider(v.id)).value ?? const <Event>[];
    final hasLocation = v.lat != null && v.lng != null;
    final digits = (v.phone ?? '').replaceAll(RegExp(r'[^0-9]'), '');

    return CustomScrollView(
      slivers: [
        SliverAppBar(
          pinned: true,
          expandedHeight: v.photoUrls.isEmpty ? null : 220,
          leading: IconButton(icon: const Icon(AppIcons.arrowLeft), onPressed: () => context.pop()),
          title: Text(v.name),
          flexibleSpace: v.photoUrls.isEmpty
              ? null
              : FlexibleSpaceBar(
                  background: PageView(
                    children: [for (final u in v.photoUrls) Image.network(u, fit: BoxFit.cover)],
                  ),
                ),
        ),
        SliverList.list(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(18),
                  child: SizedBox(
                    width: 72,
                    height: 72,
                    child: v.logoUrl == null
                        ? const ColoredBox(color: AppColors.surfaceGray, child: Icon(AppIcons.storefront, size: 30, color: AppColors.textSecondary))
                        : Image.network(v.logoUrl!, fit: BoxFit.cover),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(v.name, style: const TextStyle(fontFamily: AppFonts.display, fontSize: 30, fontWeight: FontWeight.w700, height: 1)),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          _Chip(icon: AppIcons.storefront, text: businessTypeLabel(v.type)),
                          const _Chip(icon: AppIcons.sealCheck, text: 'TT Spot partner', red: true),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if ((v.description ?? '').trim().isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
              child: Text(v.description!.trim(), style: const TextStyle(fontSize: 14.5, height: 1.5)),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
            child: Row(
              children: [
                Expanded(child: PrimaryButton(label: 'Message', onPressed: v.ownerIsMe(me) ? null : () => _message(context, ref))),
                if (digits.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  Expanded(child: SecondaryButton(label: 'WhatsApp', icon: AppIcons.whatsappLogo, onPressed: () => openExternal(context, 'whatsapp://send?phone=$digits', fallbackUrl: 'https://wa.me/$digits'))),
                ],
              ],
            ),
          ),

          const _Head('WHERE & WHEN'),
          if (v.address != null) _Info(icon: AppIcons.mapPin, text: v.address!),
          if (!hours.isEmpty)
            Theme(
              data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                tilePadding: const EdgeInsets.symmetric(horizontal: 16),
                childrenPadding: const EdgeInsets.fromLTRB(44, 0, 16, 8),
                leading: Icon(AppIcons.clock, size: 18, color: status!.startsWith('Open') ? AppColors.success : AppColors.textSecondary),
                title: Text(status, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: status.startsWith('Open') ? AppColors.success : AppColors.textSecondary)),
                subtitle: Text(hours.summary, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary)),
                children: [
                  for (final d in kDays)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Row(
                        children: [
                          SizedBox(width: 44, child: Text(kDayLabels[d]!, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5))),
                          Text(hours.days[d] == null ? 'Closed' : '${OpeningHours.fmt(hours.days[d]!.open)} – ${OpeningHours.fmt(hours.days[d]!.close)}', style: TextStyle(fontSize: 13.5, color: hours.days[d] == null ? AppColors.textSecondary : AppColors.textPrimary)),
                        ],
                      ),
                    ),
                ],
              ),
            )
          else
            const _Info(icon: AppIcons.clock, text: 'Hours not listed yet'),
          if (hasLocation)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Row(
                children: [
                  Expanded(child: SecondaryButton(label: 'Waze', icon: AppIcons.navigationArrow, onPressed: () => openExternal(context, 'waze://?ll=${v.lat},${v.lng}&navigate=yes', fallbackUrl: wazeUrl(v.lat!, v.lng!)))),
                  const SizedBox(width: 8),
                  Expanded(child: SecondaryButton(label: 'Maps', icon: AppIcons.mapTrifold, onPressed: () => openExternal(context, googleMapsUrl(v.lat!, v.lng!)))),
                  if (v.placeId != null) ...[
                    const SizedBox(width: 8),
                    Expanded(child: SecondaryButton(label: 'Check in', onPressed: () => context.push(Routes.place(v.placeId!)))),
                  ],
                ],
              ),
            ),

          _Head('VOUCHERS · ${vouchers.length}'),
          if (vouchers.isEmpty)
            const Padding(padding: EdgeInsets.fromLTRB(16, 0, 16, 4), child: Text('No vouchers right now. Check back after the next meet.', style: TextStyle(fontSize: 13, color: AppColors.textSecondary)))
          else
            for (final x in vouchers)
              ListTile(
                leading: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(color: AppColors.surfaceGray, borderRadius: BorderRadius.circular(12)),
                  child: const Center(child: ArtIcon(AppArt.ticket, size: 26)),
                ),
                title: Text(x.title, style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text(x.pointsCost == 0 ? 'Free to claim' : '${x.pointsCost} points', style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary)),
                trailing: const Icon(AppIcons.caretRight, size: 16, color: AppColors.textMuted),
                onTap: () => context.push(Routes.rewards),
              ),

          if (posts.isNotEmpty) ...[
            _Head('POSTS · ${posts.length}'),
            for (final f in posts.take(5))
              ListTile(
                leading: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: SizedBox(width: 48, height: 48, child: f.post.photoUrls.isEmpty ? const ColoredBox(color: AppColors.surfaceGray, child: Icon(AppIcons.image, color: AppColors.textSecondary)) : Image.network(f.post.photoUrls.first, fit: BoxFit.cover)),
                ),
                title: Text(f.post.title ?? f.post.caption ?? 'Post', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text(timeAgo(f.post.createdAt), style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary)),
                onTap: () => context.push(Routes.post(f.post.id)),
              ),
          ],
          _Head('EVENTS · ${events.length}'),
          if (events.isEmpty)
            const Padding(padding: EdgeInsets.fromLTRB(16, 0, 16, 4), child: Text('Nothing planned here yet.', style: TextStyle(fontSize: 13, color: AppColors.textSecondary)))
          else
            for (final e in events)
              ListTile(
                leading: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: SizedBox(width: 48, height: 48, child: e.coverUrl == null ? ColoredBox(color: AppColors.surfaceGray, child: Center(child: ArtIcon(e.type.art, size: 26))) : Image.network(e.coverUrl!, fit: BoxFit.cover)),
                ),
                title: Text(e.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text('${formatEventDateFriendly(e.startsAt)} · ${e.venueName}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary)),
                onTap: () => context.push(Routes.event(e.id)),
              ),
          const SizedBox(height: 32),
        ]),
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.icon, required this.text, this.red = false});
  final IconData icon;
  final String text;
  final bool red;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(color: red ? AppColors.brand.withValues(alpha: 0.1) : AppColors.surfaceGray, borderRadius: BorderRadius.circular(999)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: red ? AppColors.brand : AppColors.textSecondary),
            const SizedBox(width: 5),
            Text(text, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: red ? AppColors.brand : AppColors.textSecondary)),
          ],
        ),
      );
}

class _Info extends StatelessWidget {
  const _Info({required this.icon, required this.text});
  final IconData icon;
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 18, color: AppColors.textSecondary),
            const SizedBox(width: 10),
            Expanded(child: Text(text, style: const TextStyle(fontSize: 14, height: 1.4))),
          ],
        ),
      );
}

class _Head extends StatelessWidget {
  const _Head(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 22, 16, 6),
        child: Text(text, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, letterSpacing: 1, color: AppColors.textSecondary)),
      );
}
