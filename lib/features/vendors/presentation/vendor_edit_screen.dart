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
  bool _busy = false;
  bool _filled = false;

  @override
  void dispose() {
    _address.dispose();
    _phone.dispose();
    _desc.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    try {
      await ref.read(vendorActionsProvider).updateShop(address: _address.text, phone: _phone.text, description: _desc.text, logo: _logo);
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
                  onPicked: (d) => _address.text = d.address.isEmpty ? d.name : '${d.name}, ${d.address}',
                ),
                const SizedBox(height: 12),
                TextField(controller: _phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Phone / WhatsApp')),
                const SizedBox(height: 12),
                TextField(controller: _desc, maxLines: 3, maxLength: 300, textCapitalization: TextCapitalization.sentences, decoration: const InputDecoration(labelText: 'About the place')),
                const SizedBox(height: 16),
                PrimaryButton(label: 'Save', loading: _busy, onPressed: _save),
              ],
            ),
    );
  }
}
