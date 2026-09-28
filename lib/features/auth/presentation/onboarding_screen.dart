import 'package:cached_network_image/cached_network_image.dart';
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
import '../../profile/data/profile_repository.dart';
import '../../profile/domain/car_recognition.dart';
import '../../profile/presentation/widgets/car_color_picker.dart';
import '../application/auth_controller.dart';
import '../application/account_basics.dart';
import '../application/onboarding_controller.dart';
import 'widgets/username_field.dart';
import '../../../core/legal/legal_text.dart';
import '../../settings/presentation/settings_screen.dart' show LegalScreen;
import '../data/auth_repository.dart';

/// First-run setup in two steps, car first:
/// 1. your ride — one photo; the recogniser guesses make, model, year and
///    colour (all editable) and blurs the number plate before upload.
/// 2. who you are (avatar, name, username, state, phone, Terms).
/// An existing member who only lacks one of the two lands on that step alone.
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

  // step 1 — the car
  final _make = TextEditingController();
  final _model = TextEditingController();
  final _year = TextEditingController();
  String? _carColor;
  /// The file just picked, shown while the recogniser is still looking.
  XFile? _pickedFile;
  /// What gets uploaded: the plate blurred when one was seen.
  Uint8List? _carBytes;
  bool _carPreparing = false;
  CarRecognition? _guess;
  bool _guessed = false;
  bool _plateBlurred = false;
  bool _carSaved = false;
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

  Future<void> _pickCarPhoto() async {
    final files = await pickPhotos(context, max: 1, multi: false);
    if (files.isEmpty || !mounted) return;
    final file = files.first;
    setState(() {
      _pickedFile = file;
      _carBytes = null;
      _carPreparing = true;
      _plateBlurred = false;
    });
    Uint8List bytes;
    try {
      bytes = await file.readAsBytes();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _carPreparing = false;
        _pickedFile = null;
      });
      _snack(friendlyError(e));
      return;
    }
    final prepared = await prepareCarPhoto(ref.read(profileRepositoryProvider), bytes);
    if (!mounted) return;
    setState(() {
      _carPreparing = false;
      _carBytes = prepared.bytes;
      _plateBlurred = prepared.plateBlurred;
      // Only touch the fields when they are empty or hold an earlier guess;
      // never overwrite what the member typed.
      final untouched = _guessed || (_make.text.trim().isEmpty && _model.text.trim().isEmpty);
      if (!untouched) return;
      final g = prepared.guess;
      if (g != null && g.confident) {
        _guess = g;
        _guessed = true;
        _make.text = g.make;
        _model.text = g.model;
        _year.text = g.year?.toString() ?? '';
        _carColor = g.color ?? _carColor;
      } else if (_guessed) {
        _guess = null;
        _guessed = false;
        _make.clear();
        _model.clear();
        _year.clear();
      }
    });
  }

  Future<void> _submitCar() async {
    FocusScope.of(context).unfocus();
    setState(() => _carValidate = true);
    if (_carPreparing) return;
    if (_make.text.trim().isEmpty || _model.text.trim().isEmpty) return;
    final bytes = _carBytes;
    if (bytes == null) {
      _snack('Add a photo of your car.');
      return;
    }
    // Spec line / body style only while they still describe this make + model.
    final g = _guess;
    final keepGuess = g != null && g.matches(_make.text, _model.text);
    final id = await ref.read(carFormControllerProvider.notifier).save(
          make: _make.text,
          model: _model.text,
          yearText: _year.text,
          description: '',
          color: _carColor,
          keptPhotoUrls: const [],
          newPhotos: [bytes],
          specs: keepGuess ? g.specLine : null,
          bodyStyle: keepGuess ? g.bodyStyle : null,
        );
    if (id != null && mounted) {
      setState(() => _carSaved = true);
      ref.invalidate(currentProfileProvider); // carCount updates → step 2, or the router moves on
    }
  }

  Future<void> _pickAvatar() async {
    final source = await showModalBottomSheet<ImageSource>(
      useRootNavigator: true, // above the shell tab bar
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

    // No car yet → step 1. Once it is parked, the profile step (or, for a
    // member whose profile is already complete, the router moves on).
    if (profile != null && profile.needsCar && !_carSaved) {
      return _carStep(
        context,
        busy: ref.watch(carFormControllerProvider).isLoading || _carPreparing,
        onlyStep: existing && basicsDone,
      );
    }

    // Step 2 header: the car just parked (or the one already in the garage).
    ImageProvider? rideImage;
    String? rideTitle;
    if (_carBytes != null) {
      rideImage = MemoryImage(_carBytes!);
      rideTitle = '${_make.text.trim()} ${_model.text.trim()}'.trim();
    } else if (profile != null && !existing) {
      final car = ref.watch(userCarsProvider(profile.id)).value?.firstOrNull;
      if (car?.cover != null) rideImage = CachedNetworkImageProvider(car!.cover!);
      rideTitle = car?.title;
    }

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Sign out',
          icon: const Icon(AppIcons.x),
          onPressed: busy ? null : () => ref.read(authControllerProvider.notifier).signOut(),
        ),
        title: Text(existing ? 'Complete your account' : 'Step 2 of 2 · You'),
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
                  )
                else if (rideImage != null)
                  _RideBanner(image: rideImage, title: rideTitle ?? ''),
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

  Widget _carStep(BuildContext context, {required bool busy, required bool onlyStep}) {
    final yearHint = _guess?.yearRange;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Sign out',
          icon: const Icon(AppIcons.x),
          onPressed: busy ? null : () => ref.read(authControllerProvider.notifier).signOut(),
        ),
        title: Text(onlyStep ? 'Your ride' : 'Step 1 of 2 · Your ride'),
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
                      'Show us your ride. One photo is enough: we work out what it is and blur the number plate for you.',
                      style: TextStyle(fontSize: 14, color: AppColors.textSecondary, height: 1.4),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 22),
              _CarPhotoPicker(
                bytes: _carBytes,
                file: _pickedFile,
                preparing: _carPreparing,
                error: _carValidate && _carBytes == null && !_carPreparing,
                onTap: busy ? null : _pickCarPhoto,
              ),
              if (_carValidate && _carBytes == null && !_carPreparing)
                const Padding(
                  padding: EdgeInsets.only(top: 6),
                  child: Text('A photo of your car is required.', style: TextStyle(fontSize: 12.5, color: AppColors.danger)),
                ),
              if (_plateBlurred || _guessed) ...[
                const SizedBox(height: 12),
                if (_plateBlurred)
                  Padding(
                    padding: EdgeInsets.only(bottom: _guessed ? 6 : 0),
                    child: Row(
                      children: [
                        Icon(AppIcons.shieldCheck, size: 16, color: AppColors.textSecondary),
                        const SizedBox(width: 6),
                        Expanded(child: Text('Number plate blurred before upload.', style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary))),
                      ],
                    ),
                  ),
                if (_guessed) const CarGuessNote(),
              ],
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
                decoration: InputDecoration(labelText: 'Year (optional)', hintText: yearHint == null ? null : 'Our guess: $yearHint', counterText: ''),
              ),
              const SizedBox(height: 18),
              Text('COLOUR', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1, color: AppColors.textSecondary)),
              const SizedBox(height: 4),
              Text('Shows as your car on the map.', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
              const SizedBox(height: 10),
              CarColorPicker(value: _carColor, onChanged: busy ? null : (v) => setState(() => _carColor = v)),
              const SizedBox(height: 26),
              PrimaryButton(label: 'Park it in my garage', loading: busy, onPressed: busy ? null : _submitCar),
              const SizedBox(height: 10),
              Text(
                'You can add more photos, cars, mods and a build log later from your garage.',
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

/// One big photo tile: empty prompt, the picked photo dimmed with "Looking at
/// your car…" while the recogniser runs, then the final (plate-blurred) image.
class _CarPhotoPicker extends StatelessWidget {
  const _CarPhotoPicker({required this.bytes, required this.file, required this.preparing, required this.error, required this.onTap});
  final Uint8List? bytes;
  final XFile? file;
  final bool preparing;
  final bool error;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    ImageProvider? image;
    if (bytes != null) {
      image = MemoryImage(bytes!);
    } else if (file != null) {
      image = FileImage(File(file!.path));
    }
    return GestureDetector(
      onTap: preparing ? null : onTap,
      child: AspectRatio(
        aspectRatio: 16 / 10,
        child: Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: AppColors.surfaceRaised,
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(color: error ? AppColors.danger : AppColors.border),
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (image != null) Image(image: image, fit: BoxFit.cover),
              if (image == null)
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(AppIcons.cameraPlus, size: 36, color: AppColors.textSecondary),
                    const SizedBox(height: 10),
                    Text('Add a photo of your car', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                    const SizedBox(height: 4),
                    Text('Camera or gallery', style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary)),
                  ],
                ),
              if (preparing)
                Container(
                  color: Colors.black.withValues(alpha: 0.45),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.white)),
                      const SizedBox(height: 12),
                      const Text('Looking at your car…', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Colors.white)),
                      const SizedBox(height: 4),
                      Text('Reading the model and hiding the plate', style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.8))),
                    ],
                  ),
                ),
              if (image != null && !preparing)
                Positioned(
                  right: 10,
                  bottom: 10,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.55), borderRadius: BorderRadius.circular(999)),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(AppIcons.camera, size: 14, color: Colors.white),
                        SizedBox(width: 6),
                        Text('Change', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.white)),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Step 2 header: the car parked in step 1.
class _RideBanner extends StatelessWidget {
  const _RideBanner({required this.image, required this.title});
  final ImageProvider image;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 22),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: AppColors.surfaceGray, borderRadius: BorderRadius.circular(AppRadius.md)),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.sm),
            child: Image(image: image, width: 64, height: 64, fit: BoxFit.cover),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('PARKED', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, letterSpacing: 1.2, color: AppColors.textSecondary)),
                const SizedBox(height: 2),
                Text(title.isEmpty ? 'Your ride' : title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                const SizedBox(height: 2),
                Text('Now a bit about you.', style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary)),
              ],
            ),
          ),
          Icon(AppIcons.checkCircleFill, size: 22, color: AppColors.brand),
        ],
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
      image = CachedNetworkImageProvider(existingUrl!);
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
