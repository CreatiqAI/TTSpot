import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/friendly_error.dart';
import '../../../core/widgets/photo_picker_sheet.dart';
import '../../../core/widgets/primary_button.dart';
import '../application/vendors_providers.dart';
import '../domain/vendor.dart';

/// Add or edit one product: photos, name, price, what it is, and up to three
/// variant groups ("Size: S, M, L"). Display only — members message the shop.
class ProductFormScreen extends ConsumerStatefulWidget {
  const ProductFormScreen({super.key, this.productId});
  final String? productId;

  @override
  ConsumerState<ProductFormScreen> createState() => _ProductFormScreenState();
}

class _VariantDraft {
  _VariantDraft([String name = '', String options = '']) : name = TextEditingController(text: name), options = TextEditingController(text: options);
  final TextEditingController name;
  final TextEditingController options;
  void dispose() {
    name.dispose();
    options.dispose();
  }
}

class _ProductFormScreenState extends ConsumerState<ProductFormScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _desc = TextEditingController();
  final _price = TextEditingController();
  bool _askPrice = false;
  bool _active = true;
  final _variants = <_VariantDraft>[];
  final _kept = <String>[];
  final _newPhotos = <XFile>[];
  bool _busy = false;
  bool _loaded = false;

  @override
  void dispose() {
    _name.dispose();
    _desc.dispose();
    _price.dispose();
    for (final v in _variants) {
      v.dispose();
    }
    super.dispose();
  }

  void _fill(Product p) {
    _name.text = p.name;
    _desc.text = p.description ?? '';
    _askPrice = p.price == null;
    _price.text = p.price == null ? '' : (p.price! % 1 == 0 ? '${p.price!.toInt()}' : p.price!.toStringAsFixed(2));
    _active = p.active;
    _kept.addAll(p.photoUrls);
    for (final v in p.variants) {
      _variants.add(_VariantDraft(v.name, v.options.join(', ')));
    }
    _loaded = true;
  }

  List<ProductVariant> _variantValues() => [
        for (final v in _variants)
          if (v.name.text.trim().isNotEmpty)
            ProductVariant(
              name: v.name.text.trim(),
              options: v.options.text.split(RegExp(r'[,\n]')).map((s) => s.trim()).where((s) => s.isNotEmpty).take(8).toList(),
            ),
      ];

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    if (_kept.isEmpty && _newPhotos.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Add at least one photo so members know what it looks like.')));
      return;
    }
    for (final v in _variantValues()) {
      if (v.options.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Add options for "${v.name}", separated by commas.')));
        return;
      }
    }
    setState(() => _busy = true);
    try {
      await ref.read(vendorActionsProvider).saveProduct(
            id: widget.productId,
            name: _name.text.trim(),
            description: _desc.text.trim(),
            price: _askPrice ? null : double.tryParse(_price.text.trim().replaceAll(',', '')),
            keptPhotos: _kept,
            newPhotos: _newPhotos,
            variants: _variantValues(),
            active: _active,
          );
      if (mounted) context.pop();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove this product?'),
        content: const Text('Vouchers tied to it will apply to the whole shop instead.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep')),
          FilledButton(style: FilledButton.styleFrom(backgroundColor: AppColors.danger), onPressed: () => Navigator.pop(ctx, true), child: const Text('Remove')),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busy = true);
    try {
      await ref.read(vendorActionsProvider).deleteProduct(widget.productId!);
      if (mounted) context.pop();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.productId != null;
    if (editing && !_loaded) {
      final existing = ref.watch(vendorProductsProvider).value?.where((p) => p.id == widget.productId).firstOrNull;
      if (existing != null) _fill(existing);
    }
    final photoCount = _kept.length + _newPhotos.length;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(AppIcons.arrowLeft), onPressed: () => context.pop()),
        title: Text(editing ? 'Edit product' : 'New product'),
        actions: [if (editing) IconButton(tooltip: 'Remove', icon: const Icon(AppIcons.trash), onPressed: _busy ? null : _delete)],
      ),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            const _Label('PHOTOS · UP TO 4'),
            const SizedBox(height: 8),
            SizedBox(
              height: 104,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  for (var i = 0; i < _kept.length; i++) _PhotoTile(image: NetworkImage(_kept[i]), cover: i == 0, onRemove: () => setState(() => _kept.removeAt(i))),
                  for (var i = 0; i < _newPhotos.length; i++)
                    _PhotoTile(image: FileImage(File(_newPhotos[i].path)), cover: _kept.isEmpty && i == 0, onRemove: () => setState(() => _newPhotos.removeAt(i))),
                  if (photoCount < 4)
                    GestureDetector(
                      onTap: () async {
                        final files = await pickPhotos(context, max: 4 - photoCount, multi: true);
                        if (files.isNotEmpty) setState(() => _newPhotos.addAll(files));
                      },
                      child: Container(
                        width: 104,
                        height: 104,
                        decoration: BoxDecoration(color: AppColors.surfaceGray, borderRadius: BorderRadius.circular(AppRadius.md), border: Border.all(color: AppColors.border)),
                        child: const Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [Icon(AppIcons.cameraPlus, color: AppColors.textSecondary), SizedBox(height: 4), Text('Add', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textSecondary))],
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            const Text('First photo is the cover.', style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
            const SizedBox(height: 16),
            TextFormField(
              controller: _name,
              maxLength: 60,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Product name', hintText: 'e.g. Project Mu brake pads', counterText: ''),
              validator: (v) => (v ?? '').trim().length < 2 ? 'Give it a name' : null,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _price,
                    enabled: !_askPrice,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
                    decoration: InputDecoration(labelText: 'Price', prefixText: 'RM ', hintText: _askPrice ? 'Members ask you' : '0.00'),
                    validator: (v) {
                      if (_askPrice) return null;
                      final n = double.tryParse((v ?? '').trim().replaceAll(',', ''));
                      return n == null || n < 0 ? 'Enter a price, or switch to "Ask for price"' : null;
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    const Text('Ask for price', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
                    Switch.adaptive(value: _askPrice, onChanged: (v) => setState(() => _askPrice = v)),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _desc,
              maxLength: 300,
              minLines: 2,
              maxLines: 5,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'What is it?', hintText: 'Fitment, brand, what is included…'),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                const Expanded(child: _Label('VARIANTS')),
                if (_variants.length < 3)
                  TextButton.icon(
                    style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                    onPressed: () => setState(() => _variants.add(_VariantDraft())),
                    icon: const Icon(AppIcons.plus, size: 16),
                    label: Text(_variants.isEmpty ? 'Add' : 'Add another'),
                  ),
              ],
            ),
            if (_variants.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 4),
                child: Text('Optional. Sizes, colours, fitments — e.g. "Size" with "S, M, L".', style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary)),
              ),
            for (var i = 0; i < _variants.length; i++)
              Container(
                margin: const EdgeInsets.only(top: 10),
                padding: const EdgeInsets.fromLTRB(12, 10, 6, 12),
                decoration: BoxDecoration(color: AppColors.surfaceGray, borderRadius: BorderRadius.circular(AppRadius.md)),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _variants[i].name,
                            maxLength: 30,
                            textCapitalization: TextCapitalization.sentences,
                            decoration: const InputDecoration(labelText: 'Group', hintText: 'Size', counterText: '', filled: true, fillColor: Colors.white),
                            validator: (v) => (v ?? '').trim().isEmpty ? 'Name this group' : null,
                          ),
                        ),
                        IconButton(
                          tooltip: 'Remove group',
                          icon: const Icon(AppIcons.x, size: 18),
                          onPressed: () => setState(() => _variants.removeAt(i).dispose()),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: TextFormField(
                        controller: _variants[i].options,
                        textCapitalization: TextCapitalization.sentences,
                        decoration: const InputDecoration(labelText: 'Options', hintText: 'S, M, L', helperText: 'Separate with commas. Up to 8.', filled: true, fillColor: Colors.white),
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 20),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: const Text('Show on my page', style: TextStyle(fontWeight: FontWeight.w700)),
              subtitle: const Text('Turn off to hide it without removing it.', style: TextStyle(fontSize: 12.5)),
              value: _active,
              onChanged: (v) => setState(() => _active = v),
            ),
            const SizedBox(height: 16),
            PrimaryButton(label: editing ? 'Save' : 'Add product', loading: _busy, onPressed: _busy ? null : _save),
          ],
        ),
      ),
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Text(text, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, letterSpacing: 1, color: AppColors.textSecondary));
}

class _PhotoTile extends StatelessWidget {
  const _PhotoTile({required this.image, required this.onRemove, this.cover = false});
  final ImageProvider image;
  final VoidCallback onRemove;
  final bool cover;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(right: 8),
        child: Stack(
          children: [
            ClipRRect(borderRadius: BorderRadius.circular(AppRadius.md), child: Image(image: image, width: 104, height: 104, fit: BoxFit.cover)),
            if (cover)
              Positioned(
                left: 6,
                bottom: 6,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(6)),
                  child: const Text('Cover', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700)),
                ),
              ),
            Positioned(
              right: 4,
              top: 4,
              child: GestureDetector(
                onTap: onRemove,
                child: Container(padding: const EdgeInsets.all(3), decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle), child: const Icon(AppIcons.x, size: 14, color: Colors.white)),
              ),
            ),
          ],
        ),
      );
}
