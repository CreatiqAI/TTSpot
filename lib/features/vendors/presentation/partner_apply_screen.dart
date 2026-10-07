import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/constants/malaysian_states.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/widgets/picker_field.dart';
import '../../../core/places/place_label.dart';
import '../../../core/widgets/place_search_field.dart';
import '../../map/application/map_providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/titi.dart';
import '../../../core/utils/dates.dart';
import '../../../core/utils/friendly_error.dart';
import '../../../core/widgets/photo_picker_sheet.dart';
import '../../../core/widgets/primary_button.dart';
import '../../auth/application/account_basics.dart' show MyPhoneFormatter;
import '../../auth/data/auth_repository.dart';
import '../../social/application/community_providers.dart' show kClubLogoHint;
import '../../social/presentation/widgets/club_logo.dart';
import '../application/vendors_providers.dart';
import '../domain/vendor.dart';

/// One form, two kinds of application, both reviewed by an admin:
/// * vendor  – parts / accessories / workshop partners who publish vouchers
/// * club    – members who want to run a car club (invite, share location)
///
/// Laid out like the organizer application: TiTi says what approval gets
/// you, four benefit rows, then the form.
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
  double? _lat, _lng;
  final _phone = TextEditingController();
  final _ssm = TextEditingController();
  final _desc = TextEditingController();
  String _type = 'accessories';
  String? _state;
  XFile? _logo;
  XFile? _shopPhoto;
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
      if (!_club && _shopPhoto == null) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Add a photo of your shop so we can verify it.')));
        return;
      }
      if (!_club && _state == null) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Pick the state your shop is in.')));
        return;
      }
      if (!_club && _address.text.trim().length < 5) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Search and pick your shop address so members can find you.')));
        return;
      }
      await ref.read(vendorActionsProvider).apply(
            kind: widget.kind,
            name: _name.text.trim(),
            type: _club ? 'club' : _type,
            address: _club ? _state : _address.text.trim(),
            phone: _phone.text.trim(),
            description: _desc.text.trim(),
            ssmNo: _club ? null : _ssm.text.trim(),
            logo: _logo,
            lat: _club ? null : _lat,
            lng: _club ? null : _lng,
            state: _club ? null : _state,
            shopPhoto: _club ? null : _shopPhoto,
          );
      if (mounted) setState(() => _reapply = false);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _retry() {
    ref.invalidate(myPartnerApplicationProvider(widget.kind));
    if (!_club) ref.invalidate(myVendorProvider);
  }

  @override
  Widget build(BuildContext context) {
    final app = ref.watch(myPartnerApplicationProvider(widget.kind));
    // Partners land on "already a partner" (with the way to the dashboard),
    // so the form waits until we know whether I am one.
    final vendorState = _club ? const AsyncValue<Vendor?>.data(null) : ref.watch(myVendorProvider);
    final clubOwner = ref.watch(currentProfileProvider).value?.canRunClubs ?? false;
    final failed = app.hasError ? app.error : (vendorState.hasError && !vendorState.hasValue ? vendorState.error : null);
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(AppIcons.arrowLeft), onPressed: () => context.pop()),
        title: Text(_club ? 'Run a car club' : 'Become a partner'),
      ),
      body: _body(app, vendorState, failed, clubOwner),
    );
  }

  Widget _body(AsyncValue<PartnerApplication?> app, AsyncValue<Vendor?> vendorState, Object? failed, bool clubOwner) {
    // A failed load shows at once with Retry, also while Riverpod quietly
    // retries in the background (that reads as loading, which used to keep
    // the spinner going for half a minute).
    if (failed != null && !(app.hasValue && vendorState.hasValue)) return _LoadError(error: failed, onRetry: _retry);
    if (!app.hasValue || !vendorState.hasValue) return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    final a = app.value;
    final vendor = vendorState.value;
    if (!_club && vendor != null) return _Approved(kind: widget.kind, name: vendor.name);
    if (_club && clubOwner) return _Approved(kind: widget.kind, name: a?.businessName ?? 'Your club');
    if (a != null && !_reapply && (a.status == ApplicationStatus.pending || a.status == ApplicationStatus.rejected)) {
      return _Status(app: a, onReapply: a.status == ApplicationStatus.rejected ? () => setState(() => _reapply = true) : null);
    }
    return _buildForm();
  }

  Widget _buildForm() {
    final here = ref.watch(userLocationProvider).value;
    return Form(
      key: _form,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          _club
              ? TitiSays(
                  'Got a crew? Run it on TT Spot. Approved clubs get their own page, clubmates on the map, and admins who post and host meets as the club.',
                  pose: TitiPose.flag,
                )
              : TitiSays(
                  'Car people need what you sell. Approved partners get a shop page and a pin on the map, vouchers members claim in Rewards, and a mini store.',
                  pose: TitiPose.wrench,
                ),
          const SizedBox(height: 18),
          for (final f in _club
              ? const [
                  (AppIcons.usersThree, 'Club page', 'Your own page. Invite friends and approve join requests.'),
                  (AppIcons.mapPin, 'Club map', 'Clubmates see each other on the map. Each member can hide any time.'),
                  (AppIcons.shieldCheck, 'Club admins', 'Make members Vice President or Secretary to help you run it.'),
                  (AppIcons.flagCheckered, 'Post and host', 'Post and schedule meets as the club. Members see them on the club page.'),
                ]
              : const [
                  (AppIcons.storefront, 'Shop on the map', 'A partner page with photos and opening hours, pinned on the map as a spot.'),
                  (AppIcons.ticket, 'Vouchers', 'Members claim them in Rewards. Scan their QR at the counter to redeem.'),
                  (AppIcons.shoppingBag, 'Mini store', 'Show up to 5 products on your page. Members message you about them.'),
                  (AppIcons.chartBar, 'Posts, events, stats', 'Post and host events as the shop. See page views and check-ins.'),
                ])
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(f.$1, size: 22, color: AppColors.textPrimary),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text.rich(TextSpan(children: [
                      TextSpan(text: '${f.$2}. ', style: const TextStyle(fontWeight: FontWeight.w700)),
                      TextSpan(text: f.$3, style: TextStyle(color: AppColors.textSecondary)),
                    ]), style: const TextStyle(fontSize: 14, height: 1.35)),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 10),
          Row(
            children: [
              GestureDetector(
                onTap: () async {
                  // Clubs: a required, round logo (square crop).
                  if (_club) {
                    final f = await pickClubLogo(context);
                    if (f != null) setState(() => _logo = f);
                    return;
                  }
                  final files = await pickPhotos(context, max: 1, multi: false, small: true);
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
              Expanded(
                child: _club
                    ? Text('Club logo (required)\n$kClubLogoHint', style: TextStyle(color: _logo == null ? AppColors.textPrimary : AppColors.textSecondary, fontSize: 13, height: 1.35))
                    : Text('Logo or shopfront photo (optional)', style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
              ),
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
            PlaceSearchField(
              controller: _address,
              label: 'Shop address',
              hint: 'Search your shop on Google',
              icon: AppIcons.storefront,
              near: here == null ? null : (here.latitude, here.longitude),
              onPicked: (d) {
                _address.text = placeLabel(d.name, d.address);
                _lat = d.lat;
                _lng = d.lng;
              },
            ),
          ],
          const SizedBox(height: 12),
          TextFormField(
            controller: _phone,
            keyboardType: TextInputType.phone,
            inputFormatters: [MyPhoneFormatter()],
            decoration: const InputDecoration(labelText: 'Phone / WhatsApp', hintText: '+60 12-345 6789'),
            validator: (v) => (v ?? '').trim().length < 8 ? 'Enter a phone number we can reach' : null,
          ),
          if (!_club) ...[
            const SizedBox(height: 12),
            PickerField<String>(
              label: 'State',
              hint: 'Johor, Penang or Kuala Lumpur',
              icon: AppIcons.mapPin,
              value: _state,
              options: const [('Johor', 'Johor'), ('Penang', 'Penang'), ('Kuala Lumpur', 'Kuala Lumpur')],
              onChanged: (v) => setState(() => _state = v),
            ),
            const SizedBox(height: 4),
            Text('Partners need a shop in Johor, Penang or Kuala Lumpur for now.', style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
            const SizedBox(height: 12),
            TextFormField(
              controller: _ssm,
              decoration: const InputDecoration(labelText: 'SSM registration no.'),
              validator: (v) => (v ?? '').trim().length < 6 ? 'Enter your SSM number' : null,
            ),
            const SizedBox(height: 12),
            Text('SHOP PHOTO', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, letterSpacing: 1, color: AppColors.textSecondary)),
            const SizedBox(height: 6),
            GestureDetector(
              onTap: () async {
                final files = await pickPhotos(context, max: 1, multi: false);
                if (files.isNotEmpty) setState(() => _shopPhoto = files.first);
              },
              child: Container(
                height: 150,
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(color: AppColors.surfaceGray, borderRadius: BorderRadius.circular(AppRadius.md), border: Border.all(color: AppColors.border)),
                child: _shopPhoto == null
                    ? Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(AppIcons.storefront, size: 30, color: AppColors.textSecondary),
                          const SizedBox(height: 6),
                          Text('Photo of the shopfront', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textSecondary)),
                          Text('So we can verify it is real', style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
                        ],
                      )
                    : Image.file(File(_shopPhoto!.path), fit: BoxFit.cover, width: double.infinity),
              ),
            ),
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
          // A club can't apply without its logo.
          PrimaryButton(label: _club && _logo == null ? 'Add your club logo first' : 'Send application', loading: _busy, onPressed: _club && _logo == null ? null : _submit),
          const SizedBox(height: 10),
          Text(
            _club
                ? 'We usually reply within a few days. Once approved, you set up the club page and invite your members.'
                : 'We usually reply within a few days. TT Spot keeps 1% of each redeemed voucher bill, on a monthly statement.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: AppColors.textMuted, height: 1.35),
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
      padding: const EdgeInsets.fromLTRB(24, 32, 24, 32),
      children: [
        Center(child: Titi(pending ? TitiPose.phone : TitiPose.sad, height: 150)),
        const SizedBox(height: 16),
        Text(pending ? 'Application received' : 'Not approved this time', textAlign: TextAlign.center, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        Text(
          pending
              ? "${app.businessName} is waiting for review. Sent ${timeAgo(app.createdAt)}. We'll let you know in Activity."
              : (app.reason == null || app.reason!.isEmpty ? 'No reason was given.' : app.reason!),
          textAlign: TextAlign.center,
          style: TextStyle(color: AppColors.textSecondary, height: 1.4),
        ),
        const SizedBox(height: 24),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(border: Border.all(color: AppColors.border), borderRadius: BorderRadius.circular(AppRadius.md)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(app.businessName, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
              Text(businessTypeLabel(app.businessType), style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
              if (app.address != null) ...[const SizedBox(height: 6), Text(app.address!, style: const TextStyle(fontSize: 13))],
              if (app.phone != null) Text(app.phone!, style: const TextStyle(fontSize: 13)),
            ],
          ),
        ),
        if (onReapply != null) ...[
          const SizedBox(height: 24),
          PrimaryButton(label: 'Apply again', onPressed: onReapply),
        ],
      ],
    );
  }
}

/// Couldn't load the application (offline, server trouble): say so, with Retry.
class _LoadError extends StatelessWidget {
  const _LoadError({required this.error, required this.onRetry});
  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 32, 24, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Titi(TitiPose.sad, height: 150),
              const SizedBox(height: 16),
              const Text("Couldn't load this page", textAlign: TextAlign.center, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              Text(friendlyError(error), textAlign: TextAlign.center, style: TextStyle(color: AppColors.textSecondary, height: 1.4)),
              const SizedBox(height: 24),
              SecondaryButton(label: 'Try again', icon: AppIcons.arrowsClockwise, onPressed: onRetry),
            ],
          ),
        ),
      );
}

class _Approved extends StatelessWidget {
  const _Approved({required this.kind, required this.name});
  final ApplicationKind kind;
  final String name;

  @override
  Widget build(BuildContext context) {
    final club = kind == ApplicationKind.club;
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 32, 24, 32),
      children: [
        const Center(child: Titi(TitiPose.celebrate, height: 160)),
        const SizedBox(height: 16),
        Text(club ? 'You can run car clubs' : '$name is a partner', textAlign: TextAlign.center, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        Text(
          club
              ? 'Create your club page, invite members, and members will see each other on the map.'
              : 'Publish vouchers, scan them at the counter, and see your statement in the partner dashboard.',
          textAlign: TextAlign.center,
          style: TextStyle(color: AppColors.textSecondary, height: 1.4),
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
