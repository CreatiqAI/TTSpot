import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/app_art.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/friendly_error.dart';
import '../../../core/utils/image_source.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/primary_button.dart';
import '../application/vendors_providers.dart';
import '../domain/vendor.dart';

/// Partner tab: the mini store. Up to 5 products, tap to edit.
class VendorProductsScreen extends ConsumerWidget {
  const VendorProductsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final products = ref.watch(vendorProductsProvider);
    final vouchers = ref.watch(vendorVouchersProvider).value ?? const <Voucher>[];
    final count = products.value?.length ?? 0;
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        centerTitle: false,
        titleSpacing: 16,
        title: const Text('Products'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Center(child: Text('$count of 5', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textSecondary))),
          ),
        ],
      ),
      body: products.when(
        loading: () => const Center(child: CircularProgressIndicator(strokeWidth: 2)),
        error: (e, _) => Center(child: Text(friendlyError(e))),
        data: (list) => RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(vendorProductsProvider);
            await ref.read(vendorProductsProvider.future);
          },
          child: list.isEmpty
              ? ListView(children: const [
                  SizedBox(height: 80),
                  EmptyState(art: AppArt.ticket, title: 'Nothing on the shelf yet', subtitle: 'Show up to 5 things you sell. Members see them on your page and message you about them.'),
                ])
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                  itemCount: list.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (_, i) => _ProductRow(p: list[i], voucherCount: vouchers.where((v) => v.productId == list[i].id).length),
                ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: PrimaryButton(label: count >= 5 ? 'All 5 slots used' : 'Add product', onPressed: count >= 5 ? null : () => context.push(Routes.productNew)),
        ),
      ),
    );
  }
}

class _ProductRow extends StatelessWidget {
  const _ProductRow({required this.p, required this.voucherCount});
  final Product p;
  final int voucherCount;

  @override
  Widget build(BuildContext context) {
    final facts = <String>[
      p.priceLabel,
      if (p.variants.isNotEmpty) '${p.variants.map((v) => v.options.length).fold(0, (a, b) => a + b)} options',
      if (voucherCount > 0) '$voucherCount voucher${voucherCount == 1 ? '' : 's'}',
    ];
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(AppRadius.lg),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        onTap: () => context.push(Routes.productEdit(p.id)),
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(border: Border.all(color: AppColors.border), borderRadius: BorderRadius.circular(AppRadius.lg)),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.md),
                child: SizedBox(
                  width: 72,
                  height: 72,
                  child: p.photoUrls.isEmpty
                      ? ColoredBox(color: AppColors.surfaceGray, child: Icon(AppIcons.shoppingBag, color: AppColors.textSecondary))
                      : Opacity(opacity: p.active ? 1 : 0.5, child: Image(image: imageFor(p.photoUrls.first), fit: BoxFit.cover)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(child: Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15))),
                        if (!p.active)
                          Container(
                            margin: const EdgeInsets.only(left: 6),
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(color: AppColors.surfaceGray, borderRadius: BorderRadius.circular(999)),
                            child: Text('Hidden', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: AppColors.textSecondary)),
                          ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(facts.join(' · '), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary)),
                    if ((p.description ?? '').trim().isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(p.description!.trim(), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.5, color: AppColors.textMuted)),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Icon(AppIcons.caretRight, size: 16, color: AppColors.textMuted),
            ],
          ),
        ),
      ),
    );
  }
}
