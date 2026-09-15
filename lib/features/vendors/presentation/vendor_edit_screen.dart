import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/theme/app_icons.dart';
import '../../../core/widgets/place_search_field.dart';
import '../../map/application/map_providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/friendly_error.dart';
import '../../../core/widgets/photo_picker_sheet.dart';
import '../../../core/widgets/primary_button.dart';
import '../application/vendors_providers.dart';
import '../domain/vendor.dart';

/// Vendor edits the public details of the shop (name and type are fixed at approval).
class VendorEditScreen extends ConsumerStatefulWidget {
  const VendorEditScreen({super.key});

  @override
  ConsumerState<VendorEditScreen> createState() => _VendorEditScreenState();
}

class _VendorEditScreenState extends ConsumerState<VendorEditScreen> {
  final _address = TextEditingController();
  final _phone = TextEditingController();
  final _desc = TextEditingController();
  XFile? _logo;
  double? _lat, _lng;
  final _hours = TextEditingController();
  List<String> _kept = [];
  final List<XFile> _newPhotos = [];
  bool _photosLoaded = false;
  bool _busy = false;
  bool _filled = false;

  @override
  void dispose() {
    _address.dispose();
    _hours.dispose();
    _phone.dispose();
    _desc.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    try {
      await ref.read(vendorActionsProvider).updateShop(address: _address.text, phone: _phone.text, description: _desc.text, logo: _logo, lat: _lat, lng: _lng, hours: _hours.text, keptPhotos: _kept, newPhotos: _newPhotos);
      if (mounted) context.pop();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final here = ref.watch(userLocationProvider).value;
    final vendor = ref.watch(myVendorProvider).value;
    if (vendor != null && !_filled) {
      _address.text = vendor.address ?? '';
      _hours.text = vendor.hours ?? '';
      if (!_photosLoaded) {
        _kept = [...vendor.photoUrls];
        _photosLoaded = true;
      }
      _phone.text = vendor.phone ?? '';
      _desc.text = vendor.description ?? '';
      _filled = true;
    }
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(AppIcons.arrowLeft), onPressed: () => context.pop()),
        title: const Text('Edit shop'),
      ),
      body: vendor == null
          ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
              children: [
                Row(
                  children: [
                    GestureDetector(
                      onTap: () async {
                        final files = await pickPhotos(context, max: 1, multi: false);
                        if (files.isNotEmpty) setState(() => _logo = files.first);
                      },
                      child: Container(
                        width: 72,
                        height: 72,
                        decoration: BoxDecoration(
                          color: AppColors.surfaceGray,
                          borderRadius: BorderRadius.circular(AppRadius.md),
                          image: _logo != null
                              ? DecorationImage(image: FileImage(File(_logo!.path)), fit: BoxFit.cover)
                              : vendor.logoUrl != null
                                  ? DecorationImage(image: NetworkImage(vendor.logoUrl!), fit: BoxFit.cover)
                                  : null,
                        ),
                        child: _logo == null && vendor.logoUrl == null ? const Icon(AppIcons.storefront, size: 28, color: AppColors.textSecondary) : null,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(vendor.name, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                          Text(businessTypeLabel(vendor.type), style: const TextStyle(fontSize: 13, color: AppColors.textSecondary)),
                          const Text('Tap the logo to change it', style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                PlaceSearchField(
                  controller: _address,
                  label: 'Address',
                  hint: 'Search your shop on Google',
                  icon: AppIcons.storefront,
                  near: here == null ? null : (here.latitude, here.longitude),
                  onPicked: (d) {
                    _address.text = d.address.isEmpty ? d.name : '${d.name}, ${d.address}';
                    _lat = d.lat;
                    _lng = d.lng;
                  },
                ),
                const SizedBox(height: 6),
                Text(
                  vendor.lat == null && _lat == null ? 'Pick the address from the list once, and your shop appears on the map.' : 'On the map. Pick a new address to move it.',
                  style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
                ),
                const SizedBox(height: 12),
                TextField(controller: _hours, decoration: const InputDecoration(labelText: 'Opening hours', hintText: 'e.g. Mon–Sat 10am–7pm, Sun closed')),
                const SizedBox(height: 12),
                TextField(controller: _phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Phone / WhatsApp')),
                const SizedBox(height: 16),
                const Text('PHOTOS', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, letterSpacing: 1, color: AppColors.textSecondary)),
                const SizedBox(height: 8),
                SizedBox(
                  height: 96,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: [
                      for (var i = 0; i < _kept.length; i++) _PhotoTile(image: NetworkImage(_kept[i]), onRemove: () => setState(() => _kept.removeAt(i))),
                      for (var i = 0; i < _newPhotos.length; i++) _PhotoTile(image: FileImage(File(_newPhotos[i].path)), onRemove: () => setState(() => _newPhotos.removeAt(i))),
                      if (_kept.length + _newPhotos.length < 6)
                        GestureDetector(
                          onTap: () async {
                            final files = await pickPhotos(context, max: 6 - _kept.length - _newPhotos.length, multi: true);
                            if (files.isNotEmpty) setState(() => _newPhotos.addAll(files));
                          },
                          child: Container(
                            width: 96,
                            height: 96,
                            decoration: BoxDecoration(color: AppColors.surfaceGray, borderRadius: BorderRadius.circular(AppRadius.md), border: Border.all(color: AppColors.border)),
                            child: const Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(AppIcons.cameraPlus, size: 24, color: AppColors.textSecondary),
                                SizedBox(height: 4),
                                Text('Add', style: TextStyle(fontSize: 12, color: AppColors.textSecondary, fontWeight: FontWeight.w600)),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 4),
                const Text('Shopfront, workshop bay, cars you worked on. Up to 6.', style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
                const SizedBox(height: 12),
                TextField(controller: _desc, maxLines: 3, maxLength: 300, textCapitalization: TextCapitalization.sentences, decoration: const InputDecoration(labelText: 'About the place')),
                const SizedBox(height: 16),
                PrimaryButton(label: 'Save', loading: _busy, onPressed: _save),
              ],
            ),
    );
  }
}


class _PhotoTile extends StatelessWidget {
  const _PhotoTile({required this.image, required this.onRemove});
  final ImageProvider image;
  final VoidCallback onRemove;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(right: 8),
        child: Stack(
          children: [
            ClipRRect(borderRadius: BorderRadius.circular(AppRadius.md), child: Image(image: image, width: 96, height: 96, fit: BoxFit.cover)),
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
