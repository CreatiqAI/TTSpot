import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/supabase/supabase_client.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/friendly_error.dart';
import '../../../core/utils/image_source.dart';
import '../../../core/widgets/photo_picker_sheet.dart';
import '../../../core/widgets/primary_button.dart';
import '../application/vendors_providers.dart';
import '../domain/vendor.dart';
import 'widgets/product_sheet.dart';

/// Add or edit one product: photos, name, price, what it is, and up to three
/// variant groups. Each option can carry its own price and photo. The eye in
/// the corner previews the sheet members will see. Display only — members
/// message the shop.
class ProductFormScreen extends ConsumerStatefulWidget {
  const ProductFormScreen({super.key, this.productId});
  final String? productId;

  @override
  ConsumerState<ProductFormScreen> createState() => _ProductFormScreenState();
}

class _OptionDraft {
  _OptionDraft({String label = '', double? price, this.photoUrl}) : label = TextEditingController(text: label), price = TextEditingController(text: price == null ? '' : _money(price));
  final TextEditingController label;
  final TextEditingController price;
  String? photoUrl; // already uploaded
  XFile? photo; // picked now
  String? get photoSrc => photo?.path ?? photoUrl;
  void dispose() {
    label.dispose();
    price.dispose();
  }
}

class _VariantDraft {
  _VariantDraft([String name = '']) : name = TextEditingController(text: name);
  final TextEditingController name;
  final options = <_OptionDraft>[];
  void dispose() {
    name.dispose();
    for (final o in options) {
      o.dispose();
    }
  }
}

String _money(double v) => v % 1 == 0 ? '${v.toInt()}' : v.toStringAsFixed(2);
double? _parseMoney(String s) => double.tryParse(s.trim().replaceAll(',', ''));

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
    _price.text = p.price == null ? '' : _money(p.price!);
    _active = p.active;
    _kept.addAll(p.photoUrls);
    for (final v in p.variants) {
      final d = _VariantDraft(v.name);
      for (final o in v.options) {
        d.options.add(_OptionDraft(label: o.label, price: o.price, photoUrl: o.photoUrl));
      }
      _variants.add(d);
    }
    _loaded = true;
  }

  /// Variants as they stand, with local photo paths (for the preview) or
  /// uploaded URLs (after [_uploadOptionPhotos]).
  List<ProductVariant> _variantValues() => [
        for (final v in _variants)
          if (v.name.text.trim().isNotEmpty)
            ProductVariant(
              name: v.name.text.trim(),
              options: [
                for (final o in v.options)
                  if (o.label.text.trim().isNotEmpty) VariantOption(label: o.label.text.trim(), price: _parseMoney(o.price.text), photoUrl: o.photoSrc),
              ],
            ),
      ];

  String? _validate() {
    if (!_form.currentState!.validate()) return 'Check the highlighted fields.';
    if (_kept.isEmpty && _newPhotos.isEmpty) return 'Add at least one photo so members know what it looks like.';
    for (final v in _variantValues()) {
      if (v.options.isEmpty) return 'Add at least one option under "${v.name}".';
    }
    return null;
  }

  Future<void> _uploadOptionPhotos() async {
    final actions = ref.read(vendorActionsProvider);
    for (final v in _variants) {
      for (final o in v.options) {
        if (o.photo != null) {
          o.photoUrl = await actions.upload(o.photo!);
          o.photo = null;
        }
      }
    }
  }

  Future<void> _save() async {
    final problem = _validate();
    if (problem != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(problem)));
      return;
    }
    setState(() => _busy = true);
    try {
      await _uploadOptionPhotos();
      await ref.read(vendorActionsProvider).saveProduct(
            id: widget.productId,
            name: _name.text.trim(),
            description: _desc.text.trim(),
            price: _askPrice ? null : _parseMoney(_price.text),
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

  /// Show the member-side sheet for what is typed right now, unsaved.
  void _preview() {
    final vendor = ref.read(myVendorProvider).value;
    if (vendor == null) return;
    final product = Product(
      id: widget.productId ?? 'preview',
      vendorId: vendor.id,
      name: _name.text.trim().isEmpty ? 'Product name' : _name.text.trim(),
      active: _active,
      description: _desc.text.trim(),
      price: _askPrice ? null : _parseMoney(_price.text),
      photoUrls: [..._kept, ..._newPhotos.map((f) => f.path)],
      variants: _variantValues(),
    );
    final pv = PublicVendor(id: vendor.id, name: vendor.name, type: vendor.type, logoUrl: vendor.logoUrl, ownerId: ref.read(currentUserIdProvider));
    showProductSheet(context, product: product, vendor: pv, preview: true);
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

  Future<void> _pickOptionPhoto(_OptionDraft o) async {
    final files = await pickPhotos(context, max: 1, multi: false);
    if (files.isNotEmpty) setState(() => o.photo = files.first);
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
        actions: [
          IconButton(tooltip: 'Preview as a member', icon: const Icon(AppIcons.eye), onPressed: _preview),
          if (editing) IconButton(tooltip: 'Remove', icon: const Icon(AppIcons.trash), onPressed: _busy ? null : _delete),
        ],
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
                  for (var i = 0; i < _kept.length; i++) _PhotoTile(src: _kept[i], cover: i == 0, onRemove: () => setState(() => _kept.removeAt(i))),
                  for (var i = 0; i < _newPhotos.length; i++) _PhotoTile(src: _newPhotos[i].path, cover: _kept.isEmpty && i == 0, onRemove: () => setState(() => _newPhotos.removeAt(i))),
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
                    decoration: InputDecoration(labelText: _variants.isEmpty ? 'Price' : 'Base price', prefixText: 'RM ', hintText: _askPrice ? 'Members ask you' : '0.00'),
                    validator: (v) {
                      if (_askPrice) return null;
                      final n = _parseMoney(v ?? '');
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
            if (_variants.isNotEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 4),
                child: Text('Options with their own price override this.', style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
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
                    onPressed: () => setState(() => _variants.add(_VariantDraft()..options.add(_OptionDraft()))),
                    icon: const Icon(AppIcons.plus, size: 16),
                    label: Text(_variants.isEmpty ? 'Add' : 'Add another'),
                  ),
              ],
            ),
            if (_variants.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 4),
                child: Text('Optional. Sizes, colours, compounds. Each option can have its own price and photo.', style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary)),
              ),
            for (var i = 0; i < _variants.length; i++) _groupCard(i),
            const SizedBox(height: 20),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: const Text('Show on my page', style: TextStyle(fontWeight: FontWeight.w700)),
              subtitle: const Text('Turn off to hide it without removing it.', style: TextStyle(fontSize: 12.5)),
              value: _active,
              onChanged: (v) => setState(() => _active = v),
            ),
            const SizedBox(height: 8),
            SecondaryButton(label: 'Preview as a member', icon: AppIcons.eye, onPressed: _preview),
            const SizedBox(height: 10),
            PrimaryButton(label: editing ? 'Save' : 'Add product', loading: _busy, onPressed: _busy ? null : _save),
          ],
        ),
      ),
    );
  }

  Widget _groupCard(int i) {
    final g = _variants[i];
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      decoration: BoxDecoration(color: AppColors.surfaceGray, borderRadius: BorderRadius.circular(AppRadius.md)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  controller: g.name,
                  maxLength: 30,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(labelText: 'Group', hintText: 'Size, Colour, Compound…', counterText: '', filled: true, fillColor: Colors.white),
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
          const SizedBox(height: 10),
          for (var k = 0; k < g.options.length; k++) _optionRow(g, k),
          if (g.options.length < 8)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                onPressed: () => setState(() => g.options.add(_OptionDraft())),
                icon: const Icon(AppIcons.plus, size: 15),
                label: const Text('Add option'),
              ),
            ),
        ],
      ),
    );
  }

  Widget _optionRow(_VariantDraft g, int k) {
    final o = g.options[k];
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          GestureDetector(
            onTap: () => _pickOptionPhoto(o),
            onLongPress: o.photoSrc == null ? null : () => setState(() { o.photo = null; o.photoUrl = null; }),
            child: Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(AppRadius.sm), border: Border.all(color: AppColors.border)),
              clipBehavior: Clip.antiAlias,
              child: o.photoSrc == null ? const Icon(AppIcons.cameraPlus, size: 18, color: AppColors.textSecondary) : Image(image: imageFor(o.photoSrc!), fit: BoxFit.cover),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 5,
            child: TextFormField(
              controller: o.label,
              maxLength: 30,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(hintText: 'Option', isDense: true, counterText: '', filled: true, fillColor: Colors.white, contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 13)),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 4,
            child: TextFormField(
              controller: o.price,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
              decoration: const InputDecoration(hintText: 'Price', prefixText: 'RM ', isDense: true, filled: true, fillColor: Colors.white, contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 13)),
            ),
          ),
          IconButton(
            tooltip: 'Remove option',
            visualDensity: VisualDensity.compact,
            icon: const Icon(AppIcons.x, size: 16),
            onPressed: g.options.length == 1 ? null : () => setState(() => g.options.removeAt(k).dispose()),
          ),
        ],
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
  const _PhotoTile({required this.src, required this.onRemove, this.cover = false});
  final String src;
  final VoidCallback onRemove;
  final bool cover;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(right: 8),
        child: Stack(
          children: [
            ClipRRect(borderRadius: BorderRadius.circular(AppRadius.md), child: Image(image: imageFor(src), width: 104, height: 104, fit: BoxFit.cover)),
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
