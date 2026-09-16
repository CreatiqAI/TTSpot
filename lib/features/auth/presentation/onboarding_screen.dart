import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/constants/malaysian_states.dart';
import '../../../core/theme/app_art.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/widgets/picker_field.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/friendly_error.dart';
import '../../../core/widgets/photo_picker_sheet.dart';
import '../../../core/widgets/primary_button.dart';
import '../../profile/application/profile_providers.dart';
import '../application/auth_controller.dart';
import '../application/account_basics.dart';
import '../application/onboarding_controller.dart';
import 'widgets/username_field.dart';
import '../../../core/legal/legal_text.dart';
import '../../settings/presentation/settings_screen.dart' show LegalScreen;
import '../data/auth_repository.dart';

/// First-run setup in two steps, laid out like Instagram's "Edit profile":
/// 1. who you are (avatar, name, username, state)
/// 2. your ride (make, model, at least one photo) — every member has a car.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _formKey = GlobalKey<FormState>();
  final _username = TextEditingController();
  final _displayName = TextEditingController();
  final _referral = TextEditingController();
  final _phone = TextEditingController();
  bool _acceptedTerms = false;
  String? _homeState;
  XFile? _avatar;
  bool _prefilled = false;
  bool _validate = false;

  // step 2
  final _make = TextEditingController();
  final _model = TextEditingController();
  final _year = TextEditingController();
  final List<XFile> _carPhotos = [];
  bool _carValidate = false;

  @override
  void dispose() {
    _username.dispose();
    _displayName.dispose();
    _referral.dispose();
    _phone.dispose();
    _make.dispose();
    _model.dispose();
    _year.dispose();
    super.dispose();
  }

  Future<void> _pickCarPhotos() async {
    final files = await pickPhotos(context, max: 5 - _carPhotos.length, multi: true);
    if (files.isEmpty) return;
    setState(() => _carPhotos.addAll(files.take(5 - _carPhotos.length)));
  }

  Future<void> _submitCar() async {
    FocusScope.of(context).unfocus();
    setState(() => _carValidate = true);
    if (_make.text.trim().isEmpty || _model.text.trim().isEmpty) return;
    if (_carPhotos.isEmpty) {
      _snack('Add at least one photo of your car.');
      return;
    }
    final id = await ref.read(carFormControllerProvider.notifier).save(
          make: _make.text,
          model: _model.text,
          yearText: _year.text,
          description: '',
          keptPhotoUrls: const [],
          newPhotos: _carPhotos,
        );
    if (id != null) ref.invalidate(currentProfileProvider); // carCount updates → router moves on
  }

  Future<void> _pickAvatar() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(AppIcons.images),
              title: const Text('Choose from library'),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
            ListTile(
              leading: const Icon(AppIcons.camera),
              title: const Text('Take photo'),
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
            if (_avatar != null)
              ListTile(
                leading: const Icon(AppIcons.trash, color: AppColors.danger),
                title: const Text('Remove current picture', style: TextStyle(color: AppColors.danger)),
                onTap: () {
                  Navigator.pop(ctx);
                  setState(() => _avatar = null);
                },
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (source == null) return;
    try {
      final file = await pickAvatarImage(source);
      if (file != null) setState(() => _avatar = file);
    } catch (e) {
      if (mounted) _snack(friendlyError(e));
    }
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    setState(() => _validate = true);
    if (!_formKey.currentState!.validate()) return;
    await ref.read(onboardingControllerProvider.notifier).submit(
          username: _username.text,
          displayName: _displayName.text,
          homeState: _homeState!,
          avatar: _avatar,
          referralCode: _referral.text,
          phone: _phone.text,
          acceptedTerms: _acceptedTerms,
        );
    // On success currentProfileProvider refreshes and the router redirects to the map.
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(onboardingControllerProvider, (_, next) {
      if (next.hasError && !next.isLoading) _snack(friendlyError(next.error!));
    });
    ref.listen(carFormControllerProvider, (_, next) {
      if (next.hasError && !next.isLoading) _snack(friendlyError(next.error!));
    });
    final busy = ref.watch(onboardingControllerProvider).isLoading;

    // Pre-fill from the profile row (Google name, or an existing member who
    // only needs to add a phone / accept the Terms).
    final profile = ref.watch(currentProfileProvider).value;
    final basics = ref.watch(accountBasicsProvider).value;
    if (!_prefilled && profile != null) {
      _prefilled = true;
      _displayName.text = profile.displayName ?? '';
      _username.text = profile.username ?? '';
      _homeState = profile.homeState;
      if (basics?.phone != null) _phone.text = prettyPhone(basics!.phone!);
    }
    final existing = profile?.isOnboarded ?? false;
    final basicsDone = basics?.complete ?? false;

    // Profile + basics done, car missing → step 2.
    if (profile != null && existing && basicsDone) {
      return _carStep(context, busy: ref.watch(carFormControllerProvider).isLoading);
    }

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Sign out',
          icon: const Icon(AppIcons.x),
          onPressed: busy ? null : () => ref.read(authControllerProvider.notifier).signOut(),
        ),
        title: Text(existing ? 'Complete your account' : 'Step 1 of 2 · You'),
        actions: [
          busy
              ? const Padding(
                  padding: EdgeInsets.only(right: 20),
                  child: Center(
                    child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                  ),
                )
              : TextButton(onPressed: _submit, child: const Text('Done')),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
          child: Form(
            key: _formKey,
            autovalidateMode: _validate ? AutovalidateMode.always : AutovalidateMode.disabled,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (existing)
                  Container(
                    margin: const EdgeInsets.only(bottom: 18),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: AppColors.surfaceGray, borderRadius: BorderRadius.circular(AppRadius.md)),
                    child: Text(
                      'Two quick things every member needs: a phone number and a tick on the Terms. Then you are back on the map.',
                      style: TextStyle(fontSize: 13, color: AppColors.textSecondary, height: 1.4),
                    ),
                  ),
                Center(
                  child: _AvatarPicker(
                    file: _avatar,
                    existingUrl: profile?.avatarUrl,
                    onTap: busy ? null : _pickAvatar,
                  ),
                ),
                const SizedBox(height: 28),

                TextFormField(
                  controller: _displayName,
                  textInputAction: TextInputAction.next,
                  textCapitalization: TextCapitalization.words,
                  maxLength: 40,
                  decoration: const InputDecoration(labelText: 'Name', counterText: ''),
                  validator: (v) => (v?.trim().length ?? 0) < 2 ? 'Enter your name' : null,
                ),
                const SizedBox(height: 14),
                UsernameField(controller: _username, textInputAction: TextInputAction.next),
                const SizedBox(height: 14),
                PickerField<String>(
                  label: 'Home state',
                  hint: 'Where do you usually TT?',
                  icon: AppIcons.mapPin,
                  value: _homeState,
                  enabled: !busy,
                  options: [for (final s in malaysianStates) (s, s)],
                  onChanged: (v) => setState(() => _homeState = v),
                  validator: (v) => v == null ? 'Choose your state' : null,
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _phone,
                  keyboardType: TextInputType.phone,
                  textInputAction: TextInputAction.next,
                  autofillHints: const [AutofillHints.telephoneNumber],
                  inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9+\-\s]')), MyPhoneFormatter()],
                  decoration: const InputDecoration(
                    labelText: 'Phone number',
                    hintText: '+60 12-345 6789',
                    prefixIcon: Icon(AppIcons.phone, size: 20),
                    helperText: 'Private. Malaysian numbers can skip the +60.',
                  ),
                  validator: (v) => normalizePhone(v ?? '') == null ? 'Enter a valid phone number' : null,
                ),
                if (!existing) ...[
                const SizedBox(height: 14),
                TextFormField(
                  controller: _referral,
                  autocorrect: false,
                  maxLength: 20,
                  inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9_]')), _LowercaseFormatter()],
                  decoration: const InputDecoration(
                    labelText: 'Referral code (optional)',
                    prefixText: '@',
                    helperText: 'A friend\'s username. You both get points after your first check-in.',
                    counterText: '',
                  ),
                ),
                ],
                const SizedBox(height: 20),
                _TermsRow(
                  value: _acceptedTerms,
                  error: _validate && !_acceptedTerms,
                  onChanged: busy ? null : (v) => setState(() => _acceptedTerms = v),
                  onOpen: (title, body) => Navigator.of(context, rootNavigator: true).push(
                    MaterialPageRoute<void>(builder: (_) => LegalScreen(title: title, body: body)),
                  ),
                ),
                const SizedBox(height: 20),

                Text(
                  'Your name, username and home state are visible to everyone. Your phone number is private. You can change them any time.',
                  style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary, height: 1.4),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _carStep(BuildContext context, {required bool busy}) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Sign out',
          icon: const Icon(AppIcons.x),
          onPressed: busy ? null : () => ref.read(authControllerProvider.notifier).signOut(),
        ),
        title: const Text('Step 2 of 2 · Your ride'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const ArtIcon(AppArt.car, size: 44),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'What do you drive? Everyone on TT Spot has a car in the garage, and it needs a photo.',
                      style: TextStyle(fontSize: 14, color: AppColors.textSecondary, height: 1.4),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 22),
              Text('PHOTOS', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 1, color: AppColors.textSecondary)),
              const SizedBox(height: 8),
              SizedBox(
                height: 110,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    for (var i = 0; i < _carPhotos.length; i++)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: Stack(
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(AppRadius.md),
                              child: Image.file(File(_carPhotos[i].path), width: 110, height: 110, fit: BoxFit.cover),
                            ),
                            Positioned(
                              right: 4,
                              top: 4,
                              child: GestureDetector(
                                onTap: busy ? null : () => setState(() => _carPhotos.removeAt(i)),
                                child: Container(
                                  padding: const EdgeInsets.all(3),
                                  decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                                  child: const Icon(AppIcons.x, size: 14, color: Colors.white),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    if (_carPhotos.length < 5)
                      GestureDetector(
                        onTap: busy ? null : _pickCarPhotos,
                        child: Container(
                          width: 110,
                          height: 110,
                          decoration: BoxDecoration(
                            color: AppColors.surfaceRaised,
                            borderRadius: BorderRadius.circular(AppRadius.md),
                            border: Border.all(color: _carValidate && _carPhotos.isEmpty ? AppColors.danger : AppColors.border),
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(AppIcons.cameraPlus, size: 26, color: AppColors.textSecondary),
                              const SizedBox(height: 6),
                              Text(_carPhotos.isEmpty ? 'Add photo' : 'Add more', style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary, fontWeight: FontWeight.w600)),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              if (_carValidate && _carPhotos.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: 6),
                  child: Text('At least one photo is required.', style: TextStyle(fontSize: 12.5, color: AppColors.danger)),
                ),
              const SizedBox(height: 18),
              TextField(
                controller: _make,
                textInputAction: TextInputAction.next,
                textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(labelText: 'Make', hintText: 'Perodua, Honda, Toyota…', errorText: _carValidate && _make.text.trim().isEmpty ? 'Required' : null),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _model,
                textInputAction: TextInputAction.next,
                textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(labelText: 'Model', hintText: 'Myvi, Civic, GR86…', errorText: _carValidate && _model.text.trim().isEmpty ? 'Required' : null),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _year,
                keyboardType: TextInputType.number,
                maxLength: 4,
                decoration: const InputDecoration(labelText: 'Year (optional)', counterText: ''),
              ),
              const SizedBox(height: 26),
              PrimaryButton(label: 'Park it in my garage', loading: busy, onPressed: busy ? null : _submitCar),
              const SizedBox(height: 10),
              Text(
                'You can add more cars, mods and a build log later from your garage.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary, height: 1.4),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TermsRow extends StatelessWidget {
  const _TermsRow({required this.value, required this.error, required this.onChanged, required this.onOpen});
  final bool value;
  final bool error;
  final ValueChanged<bool>? onChanged;
  final void Function(String title, String body) onOpen;

  @override
  Widget build(BuildContext context) {
    final link = TextStyle(fontWeight: FontWeight.w700, color: AppColors.textPrimary, decoration: TextDecoration.underline);
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 12, 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: error ? AppColors.danger : AppColors.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 24,
            height: 24,
            child: Checkbox(
              value: value,
              onChanged: onChanged == null ? null : (v) => onChanged!(v ?? false),
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: VisualDensity.compact,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: GestureDetector(
              onTap: onChanged == null ? null : () => onChanged!(!value),
              behavior: HitTestBehavior.opaque,
              child: Text.rich(
                TextSpan(
                  style: TextStyle(fontSize: 13, color: AppColors.textSecondary, height: 1.45),
                  children: [
                    const TextSpan(text: 'I am 18 or older and I agree to the '),
                    TextSpan(text: 'Terms of Use', style: link, recognizer: TapGestureRecognizer()..onTap = () => onOpen('Terms of Use', kTerms)),
                    const TextSpan(text: ' and '),
                    TextSpan(text: 'Privacy Policy', style: link, recognizer: TapGestureRecognizer()..onTap = () => onOpen('Privacy Policy', kPrivacyPolicy)),
                    const TextSpan(text: '. No street racing.'),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AvatarPicker extends StatelessWidget {
  const _AvatarPicker({required this.file, required this.existingUrl, required this.onTap});
  final XFile? file;
  final String? existingUrl;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    ImageProvider? image;
    if (file != null) {
      image = FileImage(File(file!.path));
    } else if (existingUrl != null && existingUrl!.isNotEmpty) {
      image = NetworkImage(existingUrl!);
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: onTap,
          child: Container(
            width: 96,
            height: 96,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.surfaceGray,
              border: Border.all(color: AppColors.border, width: 0.5),
              image: image == null ? null : DecorationImage(image: image, fit: BoxFit.cover),
            ),
            child: image == null
                ? Icon(AppIcons.userFill, size: 56, color: AppColors.textMuted)
                : null,
          ),
        ),
        const SizedBox(height: 10),
        TextButton(
          onPressed: onTap,
          style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4)),
          child: const Text('Edit picture'),
        ),
      ],
    );
  }
}

class _LowercaseFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) =>
      newValue.copyWith(text: newValue.text.toLowerCase());
}
