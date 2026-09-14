import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/friendly_error.dart';
import '../application/vendors_providers.dart';
import '../domain/vendor.dart';

const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

/// Admins only: commission owed per partner for a month.
class AdminCommissionScreen extends ConsumerStatefulWidget {
  const AdminCommissionScreen({super.key});

  @override
  ConsumerState<AdminCommissionScreen> createState() => _AdminCommissionScreenState();
}

class _AdminCommissionScreenState extends ConsumerState<AdminCommissionScreen> {
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);

  void _shift(int by) => setState(() => _month = DateTime(_month.year, _month.month + by));

  @override
  Widget build(BuildContext context) {
    final rows = ref.watch(adminCommissionProvider(_month));
    final isCurrent = _month.year == DateTime.now().year && _month.month == DateTime.now().month;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(AppIcons.arrowLeft), onPressed: () => context.pop()),
        title: const Text('Commission'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Row(
              children: [
                IconButton(icon: const Icon(AppIcons.caretLeft), onPressed: () => _shift(-1)),
                Expanded(child: Text('${_months[_month.month - 1]} ${_month.year}', textAlign: TextAlign.center, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800))),
                IconButton(icon: const Icon(AppIcons.caretRight), onPressed: isCurrent ? null : () => _shift(1)),
              ],
            ),
          ),
          Expanded(
            child: rows.when(
              loading: () => const Center(child: CircularProgressIndicator(strokeWidth: 2)),
              error: (e, _) => Center(child: Text(friendlyError(e))),
              data: (list) {
                final total = list.fold<double>(0, (s, r) => s + r.commissionTotal);
                final bills = list.fold<double>(0, (s, r) => s + r.billTotal);
                final count = list.fold<int>(0, (s, r) => s + r.redemptions);
                return ListView(
                  padding: const EdgeInsets.only(bottom: 32),
                  children: [
                    Container(
                      margin: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(color: AppColors.warnColor, borderRadius: BorderRadius.circular(AppRadius.lg)),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(rm(total), style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800, height: 1, color: Colors.white)),
                                const SizedBox(height: 4),
                                const Text('commission this month', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.white70)),
                              ],
                            ),
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text('$count redemptions', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.white)),
                              Text('bills ${rm(bills)}', style: const TextStyle(fontSize: 12, color: Colors.white70)),
                            ],
                          ),
                        ],
                      ),
                    ),
                    if (list.isEmpty) const Padding(padding: EdgeInsets.all(16), child: Text('No partners yet.', style: TextStyle(color: AppColors.textSecondary))),
                    for (final r in list) _Row(r: r),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.r});
  final VendorCommissionRow r;

  @override
  Widget build(BuildContext context) => ListTile(
        leading: Container(
          width: 40,
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: AppColors.surfaceGray, borderRadius: BorderRadius.circular(AppRadius.sm)),
          child: const Icon(AppIcons.storefront, size: 20),
        ),
        title: Text(r.vendorName, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text('@${r.ownerUsername ?? ''} · ${r.redemptions} redemption${r.redemptions == 1 ? '' : 's'} · bills ${rm(r.billTotal)}', style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
        trailing: Text(rm(r.commissionTotal), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
      );
}
