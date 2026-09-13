import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/app_art.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/dates.dart';
import '../../../core/utils/friendly_error.dart';
import '../../../core/widgets/photo_picker_sheet.dart';
import '../../../core/widgets/primary_button.dart';
import '../application/vendors_providers.dart';
import '../domain/vendor.dart';

/// "Become a partner": any member can apply; an admin approves in the app.
/// Shows the latest application's status instead of the form when one exists.
class PartnerApplyScreen extends ConsumerStatefulWidget {
  const PartnerApplyScreen({super.key});

  @override
  ConsumerState<PartnerApplyScreen> createState() => _PartnerApplyScreenState();
}

class _PartnerApplyScreenState extends ConsumerState<PartnerApplyScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _address = TextEditingController();
  final _phone = TextEditingController();
  final _ssm = TextEditingController();
  final _desc = TextEditingController();
  String _type = 'cafe';
  XFile? _logo;
  bool _busy = false;
  bool _reapply = false;

  @override
  void dispose() {
    _name.dispose();
    _address.dispose();
    _phone.dispose();
    _ssm.dispose();
    _desc.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      await ref.read(vendorActionsProvider).apply(
            name: _name.text.trim(),
            type: _type,
            address: _address.text.trim(),
            phone: _phone.text.trim(),
            description: _desc.text.trim(),
            ssmNo: _ssm.text.trim(),
            logo: _logo,
          );
      if (mounted) setState(() => _reapply = false);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = ref.watch(myPartnerApplicationProvider);
    final vendor = ref.watch(myVendorProvider).value;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(AppIcons.arrowLeft), onPressed: () => context.pop()),
        title: const Text('Become a partner'),
      ),
      body: app.when(
        loading: () => const Center(child: CircularProgressIndicator(strokeWidth: 2)),
        error: (e, _) => Center(child: Text(friendlyError(e))),
        data: (a) {
          if (vendor != null) return _Approved(vendor: vendor);
          if (a != null && !_reapply && (a.status == ApplicationStatus.pending || a.status == ApplicationStatus.rejected)) {
            return _Status(app: a, onReapply: a.status == ApplicationStatus.rejected ? () => setState(() => _reapply = true) : null);
          }
          return _buildForm();
        },
      ),
    );
  }

  Widget _buildForm() {
    return Form(
      key: _form,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: AppColors.surfaceGray, borderRadius: BorderRadius.circular(AppRadius.md)),
            child: const Row(
              children: [
                ArtIcon(AppArt.handshake, size: 40),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Run a café, workshop, or shop that car people love? Partners publish vouchers in the Rewards shop, scan them at the counter, and get a monthly statement. The platform keeps 1% of each redeemed bill.',
                    style: TextStyle(fontSize: 13, height: 1.4),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
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
                    image: _logo == null ? null : DecorationImage(image: FileImage(File(_logo!.path)), fit: BoxFit.cover),
                  ),
                  child: _logo == null ? const Icon(AppIcons.storefront, size: 28, color: AppColors.textSecondary) : null,
                ),
              ),
              const SizedBox(width: 14),
              const Expanded(child: Text('Logo or shopfront photo (optional)', style: TextStyle(color: AppColors.textSecondary, fontSize: 13))),
            ],
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _name,
            textCapitalization: TextCapitalization.words,
            maxLength: 80,
            decoration: const InputDecoration(labelText: 'Business name', counterText: ''),
            validator: (v) => (v ?? '').trim().length < 2 ? 'Enter your business name' : null,
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _type,
            decoration: const InputDecoration(labelText: 'Type of business'),
            items: [for (final t in kBusinessTypes) DropdownMenuItem(value: t.$1, child: Text(t.$2))],
            onChanged: (v) => setState(() => _type = v ?? 'other'),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _address,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(labelText: 'Address'),
            validator: (v) => (v ?? '').trim().length < 5 ? 'Where can members find you?' : null,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _phone,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(labelText: 'Phone / WhatsApp'),
            validator: (v) => (v ?? '').trim().length < 8 ? 'Enter a phone number we can reach' : null,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _ssm,
            decoration: const InputDecoration(labelText: 'SSM registration no. (optional)'),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _desc,
            maxLines: 3,
            maxLength: 300,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(labelText: 'Tell us about the place', hintText: 'What do you do, and what would you offer TT Spot members?'),
          ),
          const SizedBox(height: 20),
          PrimaryButton(label: 'Send application', loading: _busy, onPressed: _submit),
          const SizedBox(height: 10),
          const Text(
            'We usually reply within a few days. You keep using TT Spot as normal in the meantime.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: AppColors.textMuted),
          ),
        ],
      ),
    );
  }
}

class _Status extends StatelessWidget {
  const _Status({required this.app, this.onReapply});
  final PartnerApplication app;
  final VoidCallback? onReapply;

  @override
  Widget build(BuildContext context) {
    final pending = app.status == ApplicationStatus.pending;
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 40, 24, 32),
      children: [
        ArtIcon(pending ? AppArt.stopwatch : AppArt.prohibited, size: 80),
        const SizedBox(height: 18),
        Text(
          pending ? 'Application received' : 'Not approved this time',
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        Text(
          pending
              ? '${app.businessName} is waiting for review. Sent ${timeAgo(app.createdAt)}. We\'ll notify you here when it\'s decided.'
              : (app.reason == null || app.reason!.isEmpty ? 'No reason was given.' : app.reason!),
          textAlign: TextAlign.center,
          style: const TextStyle(color: AppColors.textSecondary, height: 1.4),
        ),
        const SizedBox(height: 24),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(border: Border.all(color: AppColors.border), borderRadius: BorderRadius.circular(AppRadius.md)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(app.businessName, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
              Text(businessTypeLabel(app.businessType), style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
              if (app.address != null) ...[const SizedBox(height: 6), Text(app.address!, style: const TextStyle(fontSize: 13))],
              if (app.phone != null) Text(app.phone!, style: const TextStyle(fontSize: 13)),
            ],
          ),
        ),
        if (onReapply != null) ...[
          const SizedBox(height: 20),
          PrimaryButton(label: 'Apply again', onPressed: onReapply),
        ],
      ],
    );
  }
}

class _Approved extends StatelessWidget {
  const _Approved({required this.vendor});
  final Vendor vendor;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 40, 24, 32),
      children: [
        const ArtIcon(AppArt.party, size: 80),
        const SizedBox(height: 18),
        Text('${vendor.name} is a partner', textAlign: TextAlign.center, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        const Text(
          'Publish vouchers, scan them at the counter, and see your statement in the partner dashboard.',
          textAlign: TextAlign.center,
          style: TextStyle(color: AppColors.textSecondary, height: 1.4),
        ),
        const SizedBox(height: 24),
        PrimaryButton(label: 'Open partner dashboard', onPressed: () => context.pushReplacement(Routes.vendor)),
      ],
    );
  }
}
