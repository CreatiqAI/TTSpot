import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/app_router.dart';
import '../../../../core/supabase/supabase_client.dart';
import '../../../../core/theme/app_icons.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/friendly_error.dart';
import '../../../../core/widgets/primary_button.dart';
import '../../../social/application/chat_providers.dart';
import '../../application/vendors_providers.dart';
import '../../domain/vendor.dart';

/// A product card for a partner page or a grid: cover photo, name, price.
class ProductCard extends StatelessWidget {
  const ProductCard({super.key, required this.product, required this.onTap, this.voucherCount = 0});
  final Product product;
  final VoidCallback onTap;
  final int voucherCount;

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 1,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    child: product.photoUrls.isEmpty
                        ? const ColoredBox(color: AppColors.surfaceGray, child: Icon(AppIcons.shoppingBag, color: AppColors.textSecondary))
                        : Image.network(product.photoUrls.first, fit: BoxFit.cover),
                  ),
                  if (voucherCount > 0)
                    Positioned(
                      left: 6,
                      top: 6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                        decoration: BoxDecoration(color: AppColors.brand, borderRadius: BorderRadius.circular(999)),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(AppIcons.ticket, size: 11, color: Colors.white),
                            const SizedBox(width: 3),
                            Text('Voucher', style: const TextStyle(color: Colors.white, fontSize: 10.5, fontWeight: FontWeight.w800)),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            Text(product.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, height: 1.25)),
            const SizedBox(height: 2),
            Text(product.priceLabel, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: product.price == null ? AppColors.textSecondary : AppColors.textPrimary)),
          ],
        ),
      );
}

/// Full product view: photos, price, variants, what it is, vouchers that
/// apply, and a Message button (no ordering in-app yet).
Future<void> showProductSheet(BuildContext context, {required Product product, required PublicVendor vendor}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    useSafeArea: true,
    builder: (ctx) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.88,
      maxChildSize: 0.95,
      minChildSize: 0.5,
      builder: (ctx, scroll) => _ProductBody(product: product, vendor: vendor, scroll: scroll),
    ),
  );
}

class _ProductBody extends ConsumerStatefulWidget {
  const _ProductBody({required this.product, required this.vendor, required this.scroll});
  final Product product;
  final PublicVendor vendor;
  final ScrollController scroll;
  @override
  ConsumerState<_ProductBody> createState() => _ProductBodyState();
}

class _ProductBodyState extends ConsumerState<_ProductBody> {
  int _page = 0;
  final _picked = <String, String>{};
  bool _busy = false;

  Future<void> _message() async {
    setState(() => _busy = true);
    try {
      final id = await ref.read(chatActionsProvider).openVendorDm(widget.vendor.id);
      if (!mounted) return;
      Navigator.pop(context);
      context.push(Routes.chat(id));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.product;
    final me = ref.watch(currentUserIdProvider);
    final vouchers = (ref.watch(shopVouchersProvider).value ?? const <Voucher>[]).where((v) => v.productId == p.id).toList();
    return Column(
      children: [
        Expanded(
          child: ListView(
            controller: widget.scroll,
            padding: EdgeInsets.zero,
            children: [
              if (p.photoUrls.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(AppRadius.lg),
                    child: AspectRatio(
                      aspectRatio: 4 / 3,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          PageView(
                            onPageChanged: (i) => setState(() => _page = i),
                            children: [for (final u in p.photoUrls) Image.network(u, fit: BoxFit.cover)],
                          ),
                          if (p.photoUrls.length > 1)
                            Positioned(
                              bottom: 10,
                              left: 0,
                              right: 0,
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  for (var i = 0; i < p.photoUrls.length; i++)
                                    Container(
                                      width: 6,
                                      height: 6,
                                      margin: const EdgeInsets.symmetric(horizontal: 2),
                                      decoration: BoxDecoration(shape: BoxShape.circle, color: i == _page ? Colors.white : Colors.white54),
                                    ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(p.name, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, height: 1.2)),
                    const SizedBox(height: 4),
                    Text(p.priceLabel, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: p.price == null ? AppColors.textSecondary : AppColors.brand)),
                    const SizedBox(height: 4),
                    GestureDetector(
                      onTap: () {
                        Navigator.pop(context);
                        context.push(Routes.partner(widget.vendor.id));
                      },
                      child: Row(
                        children: [
                          const Icon(AppIcons.storefront, size: 14, color: AppColors.textSecondary),
                          const SizedBox(width: 5),
                          Text(widget.vendor.name, style: const TextStyle(fontSize: 13, color: AppColors.textSecondary, fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              for (final g in p.variants)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(g.name.toUpperCase(), style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, letterSpacing: 1, color: AppColors.textSecondary)),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final o in g.options)
                            ChoiceChip(
                              label: Text(o),
                              selected: _picked[g.name] == o,
                              onSelected: (_) => setState(() => _picked[g.name] = o),
                              showCheckmark: false,
                              selectedColor: AppColors.textPrimary,
                              labelStyle: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: _picked[g.name] == o ? Colors.white : AppColors.textPrimary),
                              side: BorderSide(color: _picked[g.name] == o ? AppColors.textPrimary : AppColors.border),
                              backgroundColor: Colors.white,
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              if ((p.description ?? '').trim().isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                  child: Text(p.description!.trim(), style: const TextStyle(fontSize: 14.5, height: 1.5)),
                ),
              if (vouchers.isNotEmpty) ...[
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 20, 16, 6),
                  child: Text('VOUCHERS FOR THIS', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, letterSpacing: 1, color: AppColors.textSecondary)),
                ),
                for (final v in vouchers)
                  ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                    leading: Container(
                      width: 44,
                      height: 44,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(color: AppColors.brand.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(AppRadius.sm)),
                      child: const Icon(AppIcons.ticket, color: AppColors.brand),
                    ),
                    title: Text('${v.headline} · ${v.title}', style: const TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: Text(v.pointsCost == 0 ? 'Free to claim in Rewards' : '${v.pointsCost} points in Rewards', style: const TextStyle(fontSize: 12.5)),
                    trailing: const Icon(AppIcons.caretRight, size: 16, color: AppColors.textMuted),
                    onTap: () {
                      Navigator.pop(context);
                      context.push(Routes.rewards);
                    },
                  ),
              ],
              const SizedBox(height: 16),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              PrimaryButton(label: 'Message ${widget.vendor.name}', loading: _busy, onPressed: widget.vendor.ownerIsMe(me) || _busy ? null : _message),
              const SizedBox(height: 6),
              const Text('Ask about stock, fitment or price. Ordering happens with the shop directly.', textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
            ],
          ),
        ),
      ],
    );
  }
}
