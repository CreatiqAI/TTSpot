import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/app_router.dart';
import '../../../../core/supabase/supabase_client.dart';
import '../../../../core/theme/app_icons.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/friendly_error.dart';
import '../../../../core/utils/image_source.dart';
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
                        ? ColoredBox(color: AppColors.surfaceGray, child: Icon(AppIcons.shoppingBag, color: AppColors.textSecondary))
                        : Image(image: imageFor(product.photoUrls.first), fit: BoxFit.cover),
                  ),
                  if (voucherCount > 0)
                    Positioned(
                      left: 6,
                      top: 6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                        decoration: BoxDecoration(color: AppColors.brand, borderRadius: BorderRadius.circular(999)),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(AppIcons.ticket, size: 11, color: Colors.white),
                            SizedBox(width: 3),
                            Text('Voucher', style: TextStyle(color: Colors.white, fontSize: 10.5, fontWeight: FontWeight.w800)),
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

/// Full product view: photos, price, variants (each may switch the photo and
/// the price), what it is, vouchers that apply, and a Message button. With
/// [preview] the partner sees exactly this but nothing is tappable.
Future<void> showProductSheet(BuildContext context, {required Product product, required PublicVendor vendor, bool preview = false}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    useSafeArea: true,
    builder: (ctx) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.9,
      maxChildSize: 0.95,
      minChildSize: 0.5,
      builder: (ctx, scroll) => _ProductBody(product: product, vendor: vendor, scroll: scroll, preview: preview),
    ),
  );
}

class _ProductBody extends ConsumerStatefulWidget {
  const _ProductBody({required this.product, required this.vendor, required this.scroll, required this.preview});
  final Product product;
  final PublicVendor vendor;
  final ScrollController scroll;
  final bool preview;
  @override
  ConsumerState<_ProductBody> createState() => _ProductBodyState();
}

class _ProductBodyState extends ConsumerState<_ProductBody> {
  final _pages = PageController();
  int _page = 0;
  final _picked = <String, VariantOption>{};
  bool _busy = false;

  /// Product photos first, then every option photo that is not already there.
  late final List<String> _gallery = () {
    final g = [...widget.product.photoUrls];
    for (final v in widget.product.variants) {
      for (final o in v.options) {
        if (o.photoUrl != null && !g.contains(o.photoUrl)) g.add(o.photoUrl!);
      }
    }
    return g;
  }();

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  /// The first picked option with its own price wins; otherwise the base price.
  String get _priceLabel {
    for (final v in widget.product.variants) {
      final o = _picked[v.name];
      if (o?.price != null) return rm(o!.price!);
    }
    return widget.product.priceLabel;
  }

  bool get _askPrice {
    for (final v in widget.product.variants) {
      if (_picked[v.name]?.price != null) return false;
    }
    return widget.product.price == null;
  }

  void _pick(ProductVariant group, VariantOption o) {
    setState(() => _picked[group.name] = o);
    final i = o.photoUrl == null ? -1 : _gallery.indexOf(o.photoUrl!);
    if (i >= 0 && _pages.hasClients) _pages.animateToPage(i, duration: const Duration(milliseconds: 260), curve: Curves.easeOut);
  }

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
    final vouchers = widget.preview ? const <Voucher>[] : (ref.watch(shopVouchersProvider).value ?? const <Voucher>[]).where((v) => v.productId == p.id).toList();
    return Column(
      children: [
        if (widget.preview)
          Container(
            margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(color: AppColors.surfaceGray, borderRadius: BorderRadius.circular(999)),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(AppIcons.eye, size: 15, color: AppColors.textSecondary),
                SizedBox(width: 6),
                Text('Preview · this is what members see', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: AppColors.textSecondary)),
              ],
            ),
          ),
        Expanded(
          child: ListView(
            controller: widget.scroll,
            padding: EdgeInsets.zero,
            children: [
              if (_gallery.isNotEmpty)
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
                            controller: _pages,
                            onPageChanged: (i) => setState(() => _page = i),
                            children: [for (final u in _gallery) Image(image: imageFor(u), fit: BoxFit.cover)],
                          ),
                          if (_gallery.length > 1)
                            Positioned(
                              bottom: 10,
                              left: 0,
                              right: 0,
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  for (var i = 0; i < _gallery.length; i++)
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
                    Text(_priceLabel, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: _askPrice ? AppColors.textSecondary : AppColors.brand)),
                    const SizedBox(height: 4),
                    GestureDetector(
                      onTap: widget.preview
                          ? null
                          : () {
                              Navigator.pop(context);
                              context.push(Routes.partner(widget.vendor.id));
                            },
                      child: Row(
                        children: [
                          Icon(AppIcons.storefront, size: 14, color: AppColors.textSecondary),
                          const SizedBox(width: 5),
                          Text(widget.vendor.name, style: TextStyle(fontSize: 13, color: AppColors.textSecondary, fontWeight: FontWeight.w600)),
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
                      Text(g.name.toUpperCase(), style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, letterSpacing: 1, color: AppColors.textSecondary)),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final o in g.options) _OptionChip(option: o, selected: _picked[g.name] == o, onTap: () => _pick(g, o)),
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
                Padding(
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
                    trailing: Icon(AppIcons.caretRight, size: 16, color: AppColors.textMuted),
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
              PrimaryButton(label: 'Message ${widget.vendor.name}', loading: _busy, onPressed: widget.preview || widget.vendor.ownerIsMe(me) || _busy ? null : _message),
              const SizedBox(height: 6),
              Text('Ask about stock, fitment or price. Ordering happens with the shop directly.', textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
            ],
          ),
        ),
      ],
    );
  }
}

/// One variant choice: a chip with an optional thumbnail and its own price.
class _OptionChip extends StatelessWidget {
  const _OptionChip({required this.option, required this.selected, required this.onTap});
  final VariantOption option;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding: EdgeInsets.fromLTRB(option.photoUrl == null ? 12 : 4, 4, 12, 4),
          decoration: BoxDecoration(
            color: selected ? AppColors.textPrimary : Colors.white,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: selected ? AppColors.textPrimary : AppColors.border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (option.photoUrl != null) ...[
                ClipOval(child: Image(image: imageFor(option.photoUrl!), width: 28, height: 28, fit: BoxFit.cover)),
                const SizedBox(width: 8),
              ],
              Text(option.label, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: selected ? Colors.white : AppColors.textPrimary)),
              if (option.price != null) ...[
                const SizedBox(width: 6),
                Text(rm(option.price!), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: selected ? Colors.white70 : AppColors.textSecondary)),
              ],
            ],
          ),
        ),
      );
}
