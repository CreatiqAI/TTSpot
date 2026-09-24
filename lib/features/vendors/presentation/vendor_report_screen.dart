import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/dates.dart';
import '../../../core/utils/friendly_error.dart';
import '../../../core/widgets/user_avatar.dart';
import '../application/vendors_providers.dart';
import '../domain/vendor.dart';

const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

/// Vendor statement: month by month, then every redemption.
class VendorReportScreen extends ConsumerWidget {
  const VendorReportScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final months = ref.watch(vendorMonthlyProvider(null));
    final redemptions = ref.watch(vendorRedemptionsProvider);
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(AppIcons.arrowLeft), onPressed: () => context.pop()),
        title: const Text('Statement'),
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(vendorMonthlyProvider(null));
          ref.invalidate(vendorRedemptionsProvider);
          await ref.read(vendorRedemptionsProvider.future);
        },
        child: ListView(
          padding: const EdgeInsets.only(bottom: 32),
          children: [
            Padding(padding: EdgeInsets.fromLTRB(16, 16, 16, 6), child: Text('BY MONTH', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 1, color: AppColors.textSecondary))),
            months.when(
              loading: () => const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator(strokeWidth: 2))),
              error: (e, _) => Padding(padding: const EdgeInsets.all(16), child: Text(friendlyError(e))),
              data: (rows) => rows.isEmpty
                  ? Padding(padding: EdgeInsets.fromLTRB(16, 0, 16, 8), child: Text('No redemptions yet.', style: TextStyle(color: AppColors.textSecondary)))
                  : Column(children: [for (final m in rows) _MonthTile(m: m)]),
            ),
            Padding(padding: EdgeInsets.fromLTRB(16, 20, 16, 6), child: Text('ALL REDEMPTIONS', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 1, color: AppColors.textSecondary))),
            redemptions.when(
              loading: () => const SizedBox.shrink(),
              error: (e, _) => Padding(padding: const EdgeInsets.all(16), child: Text(friendlyError(e))),
              data: (list) => Column(
                children: [
                  for (final r in list)
                    ListTile(
                      dense: true,
                      leading: UserAvatar(url: r.avatarUrl, name: r.username, size: 34),
                      title: Text('@${r.username ?? ''} · ${r.title}', maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text('${formatEventDate(r.createdAt)}${r.note == null ? '' : ' · ${r.note}'}', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                      trailing: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(rm(r.billAmount), style: const TextStyle(fontWeight: FontWeight.w700)),
                          Text('fee ${rm(r.commissionAmount)}', style: TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                        ],
                      ),
                      onTap: r.receiptUrl == null
                          ? null
                          : () => showDialog<void>(
                                context: context,
                                builder: (_) => Dialog(child: InteractiveViewer(child: Image(image: CachedNetworkImageProvider(r.receiptUrl!)))),
                              ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MonthTile extends StatelessWidget {
  const _MonthTile({required this.m});
  final MonthRow m;

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.fromLTRB(16, 4, 16, 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(border: Border.all(color: AppColors.border), borderRadius: BorderRadius.circular(AppRadius.md)),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${_months[m.month.month - 1]} ${m.month.year}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                  Text('${m.redemptions} redemption${m.redemptions == 1 ? '' : 's'} · bills ${rm(m.billTotal)}', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(rm(m.commissionTotal), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                Text('commission due', style: TextStyle(fontSize: 11, color: AppColors.textSecondary)),
              ],
            ),
          ],
        ),
      );
}

