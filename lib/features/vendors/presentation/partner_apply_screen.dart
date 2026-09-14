import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/constants/malaysian_states.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_art.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/widgets/picker_field.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/dates.dart';
import '../../../core/utils/friendly_error.dart';
import '../../../core/widgets/photo_picker_sheet.dart';
import '../../../core/widgets/primary_button.dart';
import '../../auth/data/auth_repository.dart';
import '../application/vendors_providers.dart';
import '../domain/vendor.dart';

/// One form, two kinds of application, both reviewed by an admin:
/// * vendor  – parts / accessories / workshop partners who publish vouchers
/// * club    – members who want to run a car club (invite, share location)
class PartnerApplyScreen extends ConsumerStatefulWidget {
  const PartnerApplyScreen({super.key, this.kind = ApplicationKind.vendor});
  final ApplicationKind kind;

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
  String _type = 'accessories';
  String? _state;
  XFile? _logo;
  bool _busy = false;
  bool _reapply = false;

  bool get _club => widget.kind == ApplicationKind.club;

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
            kind: widget.kind,
            name: _name.text.trim(),
            type: _club ? 'club' : _type,
            address: _club ? _state : _address.text.trim(),
            phone: _phone.text.trim(),
            description: _desc.text.trim(),
            ssmNo: _club ? null : _ssm.text.trim(),
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
    final app = ref.watch(myPartnerApplicationProvider(widget.kind));
    final vendor = ref.watch(myVendorProvider).value;
    final clubOwner = ref.watch(currentProfileProvider).value?.canRunClubs ?? false;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(AppIcons.arrowLeft), onPressed: () => context.pop()),
        title: Text(_club ? 'Run a car club' : 'Become a partner'),
      ),
      body: app.when(
        loading: () => const Center(child: CircularProgressIndicator(strokeWidth: 2)),
        error: (e, _) => Center(child: Text(friendlyError(e))),
        data: (a) {
          if (!_club && vendor != null) return _Approved(kind: widget.kind, name: vendor.name);
          if (_club && clubOwner) return _Approved(kind: widget.kind, name: a?.businessName ?? 'Your club');
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
            child: Row(
              children: [
                ArtIcon(_club ? AppArt.racing : AppArt.wrench, size: 40),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _club
                        ? 'Approved club owners get a verified club page, can invite members, and every member can see each other on the map (each member controls their own visibility).'
                        : 'Sell parts, accessories, tyres, tuning, detailing or any service car people need? Partners publish vouchers in the Rewards shop, scan them at the counter, and get a monthly statement. The platform keeps 1% of each redeemed bill.',
                    style: const TextStyle(fontSize: 13, height: 1.4),
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
                    borderRadius: BorderRadius.circular(_club ? 36 : AppRadius.md),
                    image: _logo == null ? null : DecorationImage(image: FileImage(File(_logo!.path)), fit: BoxFit.cover),
                  ),
                  child: _logo == null ? Icon(_club ? AppIcons.usersThree : AppIcons.storefront, size: 28, color: AppColors.textSecondary) : null,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(child: Text(_club ? 'Club logo (optional)' : 'Logo or shopfront photo (optional)', style: const TextStyle(color: AppColors.textSecondary, fontSize: 13))),
            ],
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _name,
            textCapitalization: TextCapitalization.words,
            maxLength: 80,
            decoration: InputDecoration(labelText: _club ? 'Club name' : 'Business name', hintText: _club ? 'e.g. GR86 Owners Malaysia' : 'e.g. Speedworks Autoparts', counterText: ''),
            validator: (v) => (v ?? '').trim().length < 2 ? (_club ? 'Give the club a name' : 'Enter your business name') : null,
          ),
          const SizedBox(height: 12),
          if (_club)
            PickerField<String>(
              label: 'Home state',
              icon: AppIcons.mapPin,
              value: _state,
              options: [for (final s in malaysianStates) (s, s)],
              onChanged: (v) => setState(() => _state = v),
              validator: (v) => v == null ? 'Where is the club based?' : null,
            )
          else ...[
            PickerField<String>(
              label: 'Type of business',
              icon: AppIcons.storefront,
              value: _type,
              options: kBusinessTypes,
              onChanged: (v) => setState(() => _type = v ?? 'other'),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _address,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Shop address'),
              validator: (v) => (v ?? '').trim().length < 5 ? 'Where can members find you?' : null,
            ),
          ],
          const SizedBox(height: 12),
          TextFormField(
            controller: _phone,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(labelText: 'Phone / WhatsApp'),
            validator: (v) => (v ?? '').trim().length < 8 ? 'Enter a phone number we can reach' : null,
          ),
          if (!_club) ...[
            const SizedBox(height: 12),
            TextFormField(controller: _ssm, decoration: const InputDecoration(labelText: 'SSM registration no. (optional)')),
          ],
          const SizedBox(height: 12),
          TextFormField(
            controller: _desc,
            maxLines: 3,
            maxLength: 300,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              labelText: _club ? 'About the club' : 'Tell us about the business',
              hintText: _club ? 'Who it\'s for, how many members, where you usually meet, links to your socials.' : 'What you sell or do, and what you\'d offer TT Spot members.',
            ),
            validator: _club ? (v) => (v ?? '').trim().length < 20 ? 'Tell us a bit more about the club' : null : null,
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
  const _Approved({required this.kind, required this.name});
  final ApplicationKind kind;
  final String name;

  @override
  Widget build(BuildContext context) {
    final club = kind == ApplicationKind.club;
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 40, 24, 32),
      children: [
        const ArtIcon(AppArt.party, size: 80),
        const SizedBox(height: 18),
        Text(club ? 'You can run car clubs' : '$name is a partner', textAlign: TextAlign.center, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        Text(
          club
              ? 'Create your club page, invite members, and members will see each other on the map.'
              : 'Publish vouchers, scan them at the counter, and see your statement in the partner dashboard.',
          textAlign: TextAlign.center,
          style: const TextStyle(color: AppColors.textSecondary, height: 1.4),
        ),
        const SizedBox(height: 24),
        PrimaryButton(
          label: club ? 'Create your club' : 'Open partner dashboard',
          onPressed: () => context.pushReplacement(club ? Routes.createClub : Routes.vendor),
        ),
      ],
    );
  }
}
