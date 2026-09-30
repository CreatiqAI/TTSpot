import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/friendly_error.dart';
import '../../../core/widgets/photo_picker_sheet.dart';
import '../../../core/widgets/picker_field.dart';
import '../../../core/widgets/thumb_image.dart';
import '../../vendors/application/vendors_providers.dart';
import '../../vendors/domain/vendor.dart';
import '../application/garage_providers.dart';
import '../domain/car_documents.dart';
import '../domain/car_mod.dart';

/// Add a mod to a car's log, or edit one ([modId]). One photo, a category,
/// an optional price only the owner sees, the shop (free text, or a TT Spot
/// partner picked from the suggestions) and an "Only me" switch.
class CarModFormScreen extends ConsumerStatefulWidget {
  const CarModFormScreen({super.key, required this.carId, this.modId});
  final String carId;
  final String? modId;

  @override
  ConsumerState<CarModFormScreen> createState() => _CarModFormScreenState();
}

class _CarModFormScreenState extends ConsumerState<CarModFormScreen> {
  final _title = TextEditingController();
  final _notes = TextEditingController();
  final _cost = TextEditingController();
  final _shop = TextEditingController();
  final _shopFocus = FocusNode();
  ModCategory? _category;
  DateTime _date = DateTime.now();
  String? _vendorId;
  bool _private = false;

  /// What the mod already had; kept unless a new photo is picked or removed.
  List<String> _keptPhotos = const [];
  Uint8List? _newPhoto;

  CarMod? _editing;
  bool _loaded = false;
  bool _busy = false;

  bool get _isEdit => widget.modId != null;

  @override
  void initState() {
    super.initState();
    if (_isEdit) {
      _load();
    } else {
      _loaded = true;
    }
  }

  Future<void> _load() async {
    try {
      final mods = await ref.read(carModsProvider(widget.carId).future);
      final m = mods.where((m) => m.id == widget.modId).firstOrNull;
      if (!mounted) return;
      setState(() {
        _loaded = true;
        _editing = m;
        if (m == null) return;
        _category = m.category;
        _title.text = m.title;
        _date = m.doneOn;
        _cost.text = m.cost == null ? '' : m.cost!.toStringAsFixed(m.cost! == m.cost!.roundToDouble() ? 0 : 2);
        _shop.text = m.shopName ?? '';
        _vendorId = m.vendorId;
        _notes.text = m.description ?? '';
        _keptPhotos = m.photoUrls;
        _private = m.isPrivate;
      });
    } catch (e) {
      if (mounted) setState(() => _loaded = true);
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _notes.dispose();
    _cost.dispose();
    _shop.dispose();
    _shopFocus.dispose();
    super.dispose();
  }

  void _snack(String msg) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  Future<void> _pickPhoto() async {
    final files = await pickPhotos(context, max: 1, multi: false);
    if (files.isEmpty) return;
    final bytes = await files.first.readAsBytes();
    if (mounted) setState(() => _newPhoto = bytes);
  }

  Future<void> _save() async {
    FocusScope.of(context).unfocus();
    if (_category == null) return _snack('Pick a category.');
    if (_title.text.trim().length < 2) return _snack('Name the mod, e.g. BC Racing coilovers.');
    final costText = _cost.text.trim();
    final cost = costText.isEmpty ? null : double.tryParse(costText);
    if (costText.isNotEmpty && cost == null) return _snack('Check the price.');
    setState(() => _busy = true);
    try {
      await ref.read(garageActionsProvider).saveMod(
            id: widget.modId,
            carId: widget.carId,
            category: _category!,
            title: _title.text,
            doneOn: _date,
            cost: cost,
            shop: _shop.text,
            vendorId: _vendorId,
            description: _notes.text,
            keptPhotos: _keptPhotos,
            newPhoto: _newPhoto,
            isPrivate: _private,
          );
      if (mounted) context.pop();
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        _snack(friendlyError(e));
      }
    }
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete "${_title.text.trim()}"?'),
        content: const Text('It comes off the car\'s mods log.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete', style: TextStyle(color: AppColors.danger))),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await ref.read(garageActionsProvider).deleteMod(widget.carId, widget.modId!);
      if (mounted) context.pop();
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        _snack(friendlyError(e));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(AppIcons.x), onPressed: _busy ? null : () => context.pop()),
        title: Text(_isEdit ? 'Edit mod' : 'Add a mod'),
        actions: [
          _busy
              ? const Padding(padding: EdgeInsets.only(right: 20), child: Center(child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))))
              : TextButton(onPressed: _loaded && !(_isEdit && _editing == null) ? _save : null, child: Text(_isEdit ? 'Save' : 'Add')),
        ],
      ),
      body: !_loaded
          ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
          : _isEdit && _editing == null
          ? Center(child: Text('This mod is gone.', style: TextStyle(color: AppColors.textSecondary)))
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
              children: [
                _PhotoBox(
                  newPhoto: _newPhoto,
                  keptUrl: _keptPhotos.firstOrNull,
                  onPick: _busy ? null : _pickPhoto,
                  onRemove: () => setState(() {
                    _newPhoto = null;
                    _keptPhotos = const [];
                  }),
                ),
                const SizedBox(height: 16),
                PickerField<ModCategory>(
                  label: 'Category',
                  hint: 'Engine, exhaust, wheels…',
                  value: _category,
                  options: [for (final c in ModCategory.values) (c, c.label)],
                  onChanged: (c) => setState(() => _category = c),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _title,
                  maxLength: 80,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(labelText: 'Part or brand', hintText: 'e.g. BC Racing BR coilovers', counterText: ''),
                ),
                const SizedBox(height: 14),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: InkWell(
                        onTap: () async {
                          FocusScope.of(context).unfocus();
                          final d = await showDatePicker(context: context, initialDate: _date, firstDate: DateTime(1980), lastDate: DateTime.now(), helpText: 'Installed on');
                          if (d != null) setState(() => _date = d);
                        },
                        borderRadius: BorderRadius.circular(AppRadius.md),
                        child: InputDecorator(
                          decoration: InputDecoration(labelText: 'Installed', suffixIcon: Icon(AppIcons.calendarBlank, size: 18, color: AppColors.textSecondary)),
                          child: Text(formatDay(_date), style: const TextStyle(fontSize: 15)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: _cost,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
                        decoration: const InputDecoration(labelText: 'Price (optional)', prefixText: 'RM ', helperText: 'Only you see this'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                _ShopField(
                  controller: _shop,
                  focusNode: _shopFocus,
                  vendorId: _vendorId,
                  onPartner: (v) => setState(() {
                    _vendorId = v?.id;
                    if (v != null) _shop.text = v.name;
                  }),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _notes,
                  maxLength: 500,
                  minLines: 2,
                  maxLines: 5,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(labelText: 'Notes (optional)', hintText: 'Spec, setup, how it feels', alignLabelWithHint: true, counterText: ''),
                ),
                const SizedBox(height: 6),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  secondary: Icon(_private ? AppIcons.lock : AppIcons.eye, color: AppColors.textPrimary),
                  title: const Text('Only me', style: TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text(_private ? 'Hidden from everyone else.' : 'Everyone can see this mod on your car.', style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary)),
                  value: _private,
                  onChanged: (v) => setState(() => _private = v),
                ),
                if (_isEdit) ...[
                  const SizedBox(height: 20),
                  Center(
                    child: TextButton(
                      onPressed: _busy ? null : _delete,
                      child: const Text('Delete mod', style: TextStyle(color: AppColors.danger)),
                    ),
                  ),
                ],
              ],
            ),
    );
  }
}

/// One photo: the picked one, else the one the mod already has, else a
/// dashed "Add a photo" box.
class _PhotoBox extends StatelessWidget {
  const _PhotoBox({required this.newPhoto, required this.keptUrl, required this.onPick, required this.onRemove});
  final Uint8List? newPhoto;
  final String? keptUrl;
  final VoidCallback? onPick;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final has = newPhoto != null || keptUrl != null;
    return AspectRatio(
      aspectRatio: 16 / 9,
      child: Material(
        color: AppColors.surfaceGray,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPick,
          child: !has
              ? Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(AppIcons.cameraPlus, size: 28, color: AppColors.textSecondary),
                    const SizedBox(height: 6),
                    Text('Add a photo', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
                  ],
                )
              : Stack(
                  fit: StackFit.expand,
                  children: [
                    newPhoto != null ? Image.memory(newPhoto!, fit: BoxFit.cover) : ThumbImage(keptUrl!),
                    Positioned(
                      top: 8,
                      right: 8,
                      child: GestureDetector(
                        onTap: onRemove,
                        child: Container(
                          width: 28,
                          height: 28,
                          decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                          child: const Icon(AppIcons.x, size: 16, color: Colors.white),
                        ),
                      ),
                    ),
                    Positioned(
                      left: 8,
                      bottom: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(AppRadius.pill)),
                        child: const Text('Change', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.white)),
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

/// Free-text shop with TT Spot partners suggested as you type. Picking one
/// links the mod to the partner's page; typing something else unlinks it.
class _ShopField extends ConsumerWidget {
  const _ShopField({required this.controller, required this.focusNode, required this.vendorId, required this.onPartner});
  final TextEditingController controller;
  final FocusNode focusNode;
  final String? vendorId;
  final ValueChanged<PublicVendor?> onPartner;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final partners = ref.watch(partnersDirectoryProvider).value ?? const <PublicVendor>[];
    return RawAutocomplete<PublicVendor>(
      textEditingController: controller,
      focusNode: focusNode,
      displayStringForOption: (v) => v.name,
      optionsBuilder: (value) {
        final q = value.text.trim().toLowerCase();
        if (q.isEmpty || vendorId != null) return const Iterable<PublicVendor>.empty();
        return partners.where((v) => v.name.toLowerCase().contains(q)).take(5);
      },
      onSelected: onPartner,
      fieldViewBuilder: (context, ctrl, focus, onSubmit) => TextField(
        controller: ctrl,
        focusNode: focus,
        maxLength: 80,
        textCapitalization: TextCapitalization.words,
        onChanged: (_) {
          if (vendorId != null) onPartner(null);
        },
        decoration: InputDecoration(
          labelText: 'Shop (optional)',
          hintText: 'Who did the work',
          counterText: '',
          suffixIcon: vendorId == null ? null : Tooltip(message: 'TT Spot partner', child: Icon(AppIcons.storefront, size: 18, color: AppColors.textPrimary)),
        ),
      ),
      optionsViewBuilder: (context, onSelected, options) => Align(
        alignment: Alignment.topLeft,
        child: Material(
          elevation: 4,
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.md),
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: 240, maxWidth: MediaQuery.sizeOf(context).width - 32),
            child: ListView(
              padding: EdgeInsets.zero,
              shrinkWrap: true,
              children: [
                for (final v in options)
                  ListTile(
                    dense: true,
                    leading: Icon(AppIcons.storefront, size: 18, color: AppColors.textPrimary),
                    title: Text(v.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text('TT Spot partner${(v.address ?? '').isEmpty ? '' : ' · ${v.address}'}', maxLines: 1, overflow: TextOverflow.ellipsis),
                    onTap: () => onSelected(v),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
