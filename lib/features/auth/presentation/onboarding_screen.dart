import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/constants/malaysian_states.dart';
import '../../../core/legal/legal_text.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/titi.dart';
import '../../../core/utils/friendly_error.dart';
import '../../../core/widgets/glass.dart';
import '../../../core/widgets/photo_picker_sheet.dart';
import '../../../core/widgets/primary_button.dart';
import '../../../core/widgets/titi_avatar_grid.dart';
import '../../../core/widgets/user_avatar.dart' show DefaultAvatars;
import '../../cards/application/cards_providers.dart';
import '../../cards/domain/cards.dart';
import '../../profile/application/profile_providers.dart';
import '../../profile/data/profile_repository.dart';
import '../../profile/domain/car_recognition.dart';
import '../../profile/presentation/widgets/car_color_picker.dart';
import '../../profile/presentation/widgets/car_scan_widgets.dart';
import '../../settings/presentation/settings_screen.dart' show LegalScreen;
import '../application/account_basics.dart';
import '../application/auth_controller.dart';
import '../application/onboarding_controller.dart';
import '../data/auth_repository.dart';
import 'widgets/username_field.dart';

/// First-run setup, guided by TiTi. One route, three pages switched here
/// (TiTi's welcome is the app's front door now, before sign-in: see
/// WelcomeScreen):
/// 1. your ride: one photo; the recogniser guesses make, model, year and
///    colour (all editable).
/// 2. you: avatar, name, handle, state, phone, Terms.
/// 3. a gift: the first blind box, when one is waiting.
/// An existing member who only lacks a car, or a phone + Terms, lands on
/// that step alone: no road, no gift.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _formKey = GlobalKey<FormState>();
  /// One road across pages: the same element survives the page switch, so
  /// TiTi rolls to the next checkpoint instead of jumping.
  final _roadKey = GlobalKey();
  final _username = TextEditingController();
  final _displayName = TextEditingController();
  final _referral = TextEditingController();
  final _phone = TextEditingController();
  bool _acceptedTerms = false;
  String? _homeState;
  XFile? _avatar;
  /// A picked TiTi default avatar (0..7); saved as its public URL.
  int? _preset;
  bool _prefilled = false;
  bool _validate = false;
  bool _showReferral = false;
  bool _allStates = false;
  /// Looking for the first blind box after the profile saved.
  bool _giftChecking = false;
  CardBox? _gift;

  // step 1 — the car
  final _make = TextEditingController();
  final _model = TextEditingController();
  final _year = TextEditingController();
  String? _carColor;
  /// The file just picked, shown while the recogniser is still looking.
  XFile? _pickedFile;
  /// What gets uploaded.
  Uint8List? _carBytes;
  bool _carPreparing = false;
  /// The recogniser is back; the last status row goes green.
  bool _scanDone = false;
  DateTime? _scanStart;
  CarRecognition? _guess;
  bool _guessed = false;
  bool _carSaved = false;
  bool _carValidate = false;
  bool _editingCar = false;

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

  Future<void> _pickCarPhoto([ImageSource? source]) async {
    final files = await pickPhotos(context, max: 1, multi: false, source: source);
    if (files.isEmpty || !mounted) return;
    final file = files.first;
    final started = DateTime.now();
    setState(() {
      _pickedFile = file;
      _carBytes = null;
      _carPreparing = true;
      _scanDone = false;
      _scanStart = started;
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
    if (!mounted || _scanStart != started) return;
    // Let the status rows finish ticking before the reveal.
    setState(() => _scanDone = true);
    final left = kCarScanHold - DateTime.now().difference(started);
    await Future<void>.delayed((left.isNegative ? Duration.zero : left) + const Duration(milliseconds: 450));
    if (!mounted || _scanStart != started) return; // a newer pick took over
    setState(() {
      _carPreparing = false;
      _carBytes = prepared.bytes;
      // Only touch the fields when they are empty or hold an earlier guess;
      // never overwrite what the member typed.
      final untouched = _guessed || (_make.text.trim().isEmpty && _model.text.trim().isEmpty);
      if (untouched) {
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
      }
      _editingCar = !_guessed;
    });
  }

  Future<void> _submitCar() async {
    FocusScope.of(context).unfocus();
    setState(() => _carValidate = true);
    if (_carPreparing) return;
    if (_make.text.trim().isEmpty || _model.text.trim().isEmpty) {
      setState(() => _editingCar = true);
      return;
    }
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
      HapticFeedback.lightImpact();
      setState(() => _carSaved = true);
      ref.invalidate(currentProfileProvider); // carCount updates → step 2, or the router moves on
    }
  }

  Future<void> _pickAvatar(String? existingUrl) async {
    final selected = _avatar != null ? null : (_preset ?? DefaultAvatars.indexOfUrl(existingUrl));
    final choice = await showModalBottomSheet<Object>(
      useRootNavigator: true, // above the shell tab bar
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TitiAvatarGrid(selected: selected, onPick: (i) => Navigator.pop(ctx, i)),
            const Divider(height: 16),
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
            if (_avatar != null || _preset != null)
              ListTile(
                leading: const Icon(AppIcons.trash, color: AppColors.danger),
                title: const Text('Remove current picture', style: TextStyle(color: AppColors.danger)),
                onTap: () {
                  Navigator.pop(ctx);
                  setState(() {
                    _avatar = null;
                    _preset = null;
                  });
                },
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (choice is int) {
      setState(() {
        _preset = choice;
        _avatar = null;
      });
      return;
    }
    if (choice is! ImageSource) return;
    try {
      final file = await pickAvatarImage(choice);
      if (file != null) {
        setState(() {
          _avatar = file;
          _preset = null;
        });
      }
    } catch (e) {
      if (mounted) _snack(friendlyError(e));
    }
  }

  Future<void> _submit({required bool existing}) async {
    FocusScope.of(context).unfocus();
    setState(() => _validate = true);
    final formOk = _formKey.currentState!.validate();
    if (!formOk || _homeState == null) return;
    // The profile is refreshed here, not in the controller, so a new member
    // sees TiTi's gift before the router moves on.
    await ref.read(onboardingControllerProvider.notifier).submit(
          username: _username.text,
          displayName: _displayName.text,
          homeState: _homeState!,
          avatar: _avatar,
          presetAvatarUrl: _preset == null ? null : DefaultAvatars.publicUrl(_preset!),
          referralCode: _referral.text,
          phone: _phone.text,
          acceptedTerms: _acceptedTerms,
          refreshProfile: false,
        );
    if (!mounted || ref.read(onboardingControllerProvider).hasError) return;
    await _afterSubmit(existing: existing);
  }

  /// The profile is saved. A new member gets the first blind box (granted by
  /// the database the moment the username is set); everyone else moves on.
  Future<void> _afterSubmit({required bool existing}) async {
    if (existing) {
      ref.invalidate(currentProfileProvider);
      return;
    }
    setState(() => _giftChecking = true);
    CardBox? box;
    try {
      ref.invalidate(myBoxesProvider);
      final boxes = await ref.read(myBoxesProvider.future);
      box = boxes.where((b) => b.sealed).firstOrNull;
    } catch (_) {
      box = null;
    }
    if (!mounted) return;
    if (box == null) {
      setState(() => _giftChecking = false);
      ref.invalidate(currentProfileProvider); // the router moves on
      return;
    }
    HapticFeedback.lightImpact();
    setState(() {
      _gift = box;
      _giftChecking = false;
    });
  }

  void _signOut() => ref.read(authControllerProvider.notifier).signOut();

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
    final busy = ref.watch(onboardingControllerProvider).isLoading || _giftChecking;

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

    if (_gift != null) return _giftPage(_gift!);

    // No car yet → step 1. Once it is parked, the profile step (or, for a
    // member whose profile is already complete, the router moves on).
    if (profile != null && profile.needsCar && !_carSaved) {
      return _ridePage(
        busy: ref.watch(carFormControllerProvider).isLoading || _carPreparing,
        existing: existing,
        onlyStep: existing && basicsDone,
      );
    }
    return _youPage(busy: busy, existing: existing, avatarUrl: profile?.avatarUrl);
  }

  // ─────────────────────────────────────────────────────────── 1. your ride ──

  Widget _ridePage({required bool busy, required bool existing, required bool onlyStep}) {
    final Widget body;
    if (_carPreparing && _pickedFile != null) {
      body = _rideScanning(existing: existing);
    } else if (_carBytes != null) {
      body = _rideFound(busy: busy, existing: existing);
    } else {
      body = _rideEmpty(busy: busy, existing: existing);
    }
    return Scaffold(body: body);
  }

  /// The road for a new member; existing members just get the step name.
  Widget _stepHeader({required bool existing, required int step, required int done, bool light = false, String? title}) {
    if (!existing) return _Road(key: _roadKey, step: step, done: done, light: light);
    return Padding(
      padding: const EdgeInsets.only(top: 6, bottom: 6),
      child: Text(title ?? _Road.labels[step], style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.2, color: light ? Colors.white : AppColors.textSecondary)),
    );
  }

  Widget _rideEmpty({required bool busy, required bool existing}) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _TopBar(onSignOut: busy ? null : _signOut),
            _stepHeader(existing: existing, step: 0, done: 0),
            const SizedBox(height: 20),
            const TitiSays('Show me your ride. I\'ll work out what it is.', pose: TitiPose.camera),
            const SizedBox(height: 22),
            const _Headline('WHAT DO YOU DRIVE?'),
            const SizedBox(height: 16),
            _DropZone(onTap: busy ? null : _pickCarPhoto, onCamera: busy ? null : () => _pickCarPhoto(ImageSource.camera), onGallery: busy ? null : () => _pickCarPhoto(ImageSource.gallery)),
            const SizedBox(height: 14),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 1),
                  child: Icon(AppIcons.lock, size: 16, color: AppColors.textSecondary),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Your car is your profile on the map and at meets. You can add more cars later.',
                    style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary, height: 1.4),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            const PrimaryButton(label: 'Park it in my garage', onPressed: null),
          ],
        ),
      ),
    );
  }

  Widget _rideScanning({required bool existing}) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _TopBar(onSignOut: null),
            _stepHeader(existing: existing, step: 0, done: 0),
            const SizedBox(height: 20),
            CarScanningCard(image: FileImage(File(_pickedFile!.path)), startedAt: _scanStart ?? DateTime.now(), done: _scanDone),
            const SizedBox(height: 18),
            Text(
              'Usually under 5 seconds. You can correct anything after.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary, height: 1.4),
            ),
          ],
        ),
      ),
    );
  }

  Widget _rideFound({required bool busy, required bool existing}) {
    final topPad = MediaQuery.paddingOf(context).top;
    final make = _make.text.trim();
    final model = _model.text.trim();
    final year = _year.text.trim().isNotEmpty ? _year.text.trim() : (_guess?.yearRange ?? '');
    final tiles = carSpecTiles(_guess, make, model);
    final colourFromPhoto = _guessed && _carColor != null && _guess?.color == _carColor;
    final colourText = carColourNote(_carColor, fromPhoto: colourFromPhoto);
    final missing = _carValidate && (make.isEmpty || model.isEmpty);

    return SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Photo, edge to edge, fading into the page.
          SizedBox(
            height: 330,
            child: Stack(
              fit: StackFit.expand,
              children: [
                Image.memory(_carBytes!, fit: BoxFit.cover, gaplessPlayback: true),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  height: 84,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [AppColors.bg.withValues(alpha: 0), AppColors.bg],
                      ),
                    ),
                  ),
                ),
                // A touch of shade up top so the white road reads on a bright sky.
                Positioned(
                  left: 0,
                  right: 0,
                  top: 0,
                  height: topPad + 120,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Colors.black.withValues(alpha: 0.45), Colors.black.withValues(alpha: 0)],
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: 20,
                  right: 20,
                  top: topPad,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _TopBar(onSignOut: busy ? null : _signOut, light: true),
                      _stepHeader(existing: existing, step: 0, done: 0, light: true),
                    ],
                  ),
                ),
                Positioned(
                  right: 20,
                  bottom: 16,
                  child: _Pill(icon: AppIcons.camera, label: 'Change photo', onTap: busy ? null : _pickCarPhoto, filled: false),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    TitiAvatar(_guessed ? TitiPose.thumbsUp : TitiPose.sad, size: 44),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _guessed
                            ? 'Found it. Clean ${_guess!.model}. Check the details below, then I\'ll park it.'
                            : 'I couldn\'t tell what this is. Type it in below and I\'ll park it.',
                        style: TextStyle(fontSize: 14.5, height: 1.35, color: AppColors.textPrimary),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                CarFoundTitle(
                  make: make,
                  model: model,
                  year: year,
                  trailing: _Pill(
                    icon: _editingCar ? AppIcons.check : AppIcons.pencilSimple,
                    label: _editingCar ? 'Done' : 'Edit',
                    onTap: busy ? null : () => setState(() => _editingCar = !_editingCar),
                    filled: _editingCar,
                  ),
                ),
                AnimatedSize(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutCubic,
                  alignment: Alignment.topCenter,
                  child: _editingCar
                      ? Padding(
                          padding: const EdgeInsets.only(top: 14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              TextField(
                                controller: _make,
                                textInputAction: TextInputAction.next,
                                textCapitalization: TextCapitalization.words,
                                decoration: InputDecoration(labelText: 'Make', hintText: 'Perodua, Honda, Toyota…', errorText: _carValidate && make.isEmpty ? 'Required' : null),
                                onChanged: (_) => setState(() {}),
                              ),
                              const SizedBox(height: 12),
                              TextField(
                                controller: _model,
                                textInputAction: TextInputAction.next,
                                textCapitalization: TextCapitalization.words,
                                decoration: InputDecoration(labelText: 'Model', hintText: 'Myvi, Civic, GR86…', errorText: _carValidate && model.isEmpty ? 'Required' : null),
                                onChanged: (_) => setState(() {}),
                              ),
                              const SizedBox(height: 12),
                              TextField(
                                controller: _year,
                                keyboardType: TextInputType.number,
                                maxLength: 4,
                                decoration: InputDecoration(labelText: 'Year (optional)', hintText: _guess?.yearRange == null ? null : 'Our guess: ${_guess!.yearRange}', counterText: ''),
                                onChanged: (_) => setState(() {}),
                              ),
                            ],
                          ),
                        )
                      : const SizedBox(width: double.infinity),
                ),
                if (missing && !_editingCar)
                  const Padding(
                    padding: EdgeInsets.only(top: 6),
                    child: Text('Make and model are required.', style: TextStyle(fontSize: 12.5, color: AppColors.danger)),
                  ),
                if (tiles.isNotEmpty) ...[
                  const SizedBox(height: 18),
                  CarSpecGrid(tiles: tiles),
                ],
                const SizedBox(height: 22),
                Text('COLOUR', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.2, color: AppColors.textSecondary)),
                const SizedBox(height: 3),
                Text(colourText, style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
                const SizedBox(height: 10),
                CarColorPicker(value: _carColor, onChanged: busy ? null : (v) => setState(() => _carColor = v)),
                const SizedBox(height: 26),
                PrimaryButton(label: 'Park it in my garage', loading: busy, onPressed: busy ? null : _submitCar),
                const SizedBox(height: 4),
                TextButton(
                  onPressed: busy ? null : _pickCarPhoto,
                  child: Text('Not your car? Try another photo', style: TextStyle(color: AppColors.textSecondary, fontWeight: FontWeight.w600)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────── 2. you ──

  Widget _youPage({required bool busy, required bool existing, String? avatarUrl}) {
    // Where most members are, first; the rest behind More.
    const popular = ['Selangor', 'Kuala Lumpur', 'Johor', 'Penang', 'Perak', 'Negeri Sembilan'];
    final first = [for (final p in popular) if (malaysianStates.contains(p)) p];
    final showAll = _allStates || (_homeState != null && !first.contains(_homeState));
    final states = showAll ? malaysianStates : first;

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
          child: Form(
            key: _formKey,
            autovalidateMode: _validate ? AutovalidateMode.always : AutovalidateMode.disabled,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _TopBar(onSignOut: busy ? null : _signOut),
                if (existing) ...[
                  Container(
                    margin: const EdgeInsets.only(bottom: 18),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: AppColors.surfaceGray, borderRadius: BorderRadius.circular(AppRadius.md)),
                    child: Text(
                      'Two quick things every member needs: a phone number and a tick on the Terms. Then you are back on the map.',
                      style: TextStyle(fontSize: 13, color: AppColors.textSecondary, height: 1.4),
                    ),
                  ),
                  const _Headline('COMPLETE YOUR ACCOUNT'),
                ] else ...[
                  _Road(key: _roadKey, step: 1, done: 1),
                  const SizedBox(height: 20),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      _AvatarPicker(file: _avatar, preset: _preset, existingUrl: avatarUrl, onTap: busy ? null : () => _pickAvatar(avatarUrl)),
                      const SizedBox(width: 12),
                      const Flexible(child: TitiBubble('Now you. What do your friends call you?')),
                    ],
                  ),
                  const SizedBox(height: 22),
                  const _Headline('WHO\'S DRIVING?'),
                ],
                const SizedBox(height: 6),

                const _Label('NAME'),
                TextFormField(
                  controller: _displayName,
                  textInputAction: TextInputAction.next,
                  textCapitalization: TextCapitalization.words,
                  maxLength: 40,
                  decoration: const InputDecoration(hintText: 'Your name', counterText: ''),
                  validator: (v) => (v?.trim().length ?? 0) < 2 ? 'Enter your name' : null,
                ),
                const _Label('HANDLE'),
                UsernameField(controller: _username, textInputAction: TextInputAction.next),
                const _Label('HOME STATE'),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final s in states)
                      _StateChip(
                        label: s,
                        selected: _homeState == s,
                        onTap: busy ? null : () => setState(() => _homeState = s),
                      ),
                    if (!showAll)
                      _StateChip(label: 'More…', selected: false, onTap: busy ? null : () => setState(() => _allStates = true)),
                  ],
                ),
                if (_validate && _homeState == null)
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Text('Choose your state', style: TextStyle(fontSize: 12.5, color: AppColors.danger)),
                  ),
                const _Label('PHONE'),
                TextFormField(
                  controller: _phone,
                  keyboardType: TextInputType.phone,
                  textInputAction: TextInputAction.next,
                  autofillHints: const [AutofillHints.telephoneNumber],
                  inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9+\-\s]')), MyPhoneFormatter()],
                  decoration: const InputDecoration(
                    hintText: '+60 12-345 6789',
                    prefixIcon: Icon(AppIcons.phone, size: 20),
                    helperText: 'Private. Malaysian numbers can skip the +60.',
                  ),
                  validator: (v) => normalizePhone(v ?? '') == null ? 'Enter a valid phone number' : null,
                ),
                if (!existing) ...[
                  const SizedBox(height: 14),
                  if (!_showReferral)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: GestureDetector(
                        onTap: busy ? null : () => setState(() => _showReferral = true),
                        behavior: HitTestBehavior.opaque,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text('Have a referral code?', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: AppColors.textPrimary, decoration: TextDecoration.underline)),
                            const SizedBox(width: 4),
                            Icon(AppIcons.caretDown, size: 14, color: AppColors.textSecondary),
                          ],
                        ),
                      ),
                    )
                  else ...[
                    const _Label('REFERRAL CODE', top: 0),
                    TextFormField(
                      controller: _referral,
                      autocorrect: false,
                      autofocus: true,
                      maxLength: 20,
                      textCapitalization: TextCapitalization.characters,
                      // Codes are 6 letters and numbers; an old invite may still be a username.
                      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9_]')), _UppercaseFormatter()],
                      decoration: const InputDecoration(
                        hintText: 'e.g. K7XP4M',
                        helperText: 'From a friend, an event or a partner. You both get points after your first check-in.',
                        helperMaxLines: 2,
                        counterText: '',
                      ),
                    ),
                  ],
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
                PrimaryButton(label: existing ? 'Done' : 'Continue', loading: busy, onPressed: busy ? null : () => _submit(existing: existing)),
                const SizedBox(height: 14),
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

  // ──────────────────────────────────────────────────────────── 3. a gift ──

  Widget _giftPage(CardBox box) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: AppColors.ink,
        body: SafeArea(
          child: _FillScroll(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _Road(key: _roadKey, step: 2, done: 3, light: true),
                const SizedBox(height: 12),
                SizedBox(
                  height: 262,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      const Align(alignment: Alignment.bottomCenter, child: Titi(TitiPose.gift, height: 250)),
                      const Positioned(
                        right: 0,
                        top: 6,
                        child: TitiBubble('A little gift for the road ahead.', dark: false, maxWidth: 170),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 22),
                const Text('YOUR FIRST BLIND BOX', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.5, color: Color(0xFFFF7A80))),
                const SizedBox(height: 8),
                const Text(
                  'SEVEN TITI CARDS.\nONE IS A SECRET.',
                  style: TextStyle(fontFamily: AppFonts.display, fontSize: 44, height: 0.96, fontWeight: FontWeight.w800, letterSpacing: -0.5, color: Colors.white),
                ),
                const SizedBox(height: 12),
                Text(
                  'Collect them at meets, trade with friends, swap for real prizes from partners.',
                  style: TextStyle(fontSize: 15, height: 1.4, color: Colors.white.withValues(alpha: 0.72)),
                ),
                const Spacer(),
                const SizedBox(height: 20),
                Center(
                  child: Image.asset(
                    'assets/titi/box_closed.png',
                    height: 170,
                    fit: BoxFit.contain,
                    filterQuality: FilterQuality.medium,
                    errorBuilder: (_, _, _) => SizedBox(
                      height: 170,
                      child: Icon(AppIcons.gift, size: 120, color: Colors.white.withValues(alpha: 0.35)),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                PressScale(
                  child: FilledButton(
                    style: FilledButton.styleFrom(backgroundColor: Colors.white, foregroundColor: AppColors.ink),
                    onPressed: () => context.go(Routes.openBox(box.id)),
                    child: const Text('Open my box'),
                  ),
                ),
                const SizedBox(height: 4),
                TextButton(
                  onPressed: () => ref.invalidate(currentProfileProvider),
                  child: Text('Keep it for later · it waits in Cards', style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontWeight: FontWeight.w600)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────── helpers ──

/// Scroll view whose content fills the viewport at least, so a `Spacer`
/// pushes the actions to the bottom on tall phones and the page still
/// scrolls on short ones.
class _FillScroll extends StatelessWidget {
  const _FillScroll({required this.child, required this.padding});
  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (_, c) => SingleChildScrollView(
          padding: padding,
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: math.max(0, c.maxHeight - padding.vertical)),
            child: IntrinsicHeight(child: child),
          ),
        ),
      );
}

/// A slim row with the sign-out cross on the right. Every page keeps one so
/// nobody is ever stuck here.
class _TopBar extends StatelessWidget {
  const _TopBar({required this.onSignOut, this.light = false});
  final VoidCallback? onSignOut;
  final bool light;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 40,
        child: Align(
          alignment: Alignment.centerRight,
          child: IconButton(
            tooltip: 'Sign out',
            visualDensity: VisualDensity.compact,
            icon: Icon(AppIcons.x, size: 22, color: light ? Colors.white : AppColors.textPrimary),
            onPressed: onSignOut,
          ),
        ),
      );
}

class _Headline extends StatelessWidget {
  const _Headline(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: TextStyle(fontFamily: AppFonts.display, fontSize: 38, height: 0.98, fontWeight: FontWeight.w800, letterSpacing: -0.3, color: AppColors.textPrimary),
      );
}

/// Small uppercase field label.
class _Label extends StatelessWidget {
  const _Label(this.text, {this.top = 14});
  final String text;
  final double top;

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.only(top: top, bottom: 6),
        child: Text(text, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.2, color: AppColors.textSecondary)),
      );
}

/// The road: a dashed line with three checkpoints and TiTi rolling along
/// it. [step] is where TiTi stands (0..2); the first [done] checkpoints are
/// ticked. [light] draws it white, for use over a photo or on ink.
class _Road extends StatelessWidget {
  const _Road({super.key, required this.step, required this.done, this.light = false});
  final int step;
  final int done;
  final bool light;

  static const labels = ['YOUR RIDE', 'YOU', 'A GIFT'];

  @override
  Widget build(BuildContext context) {
    final lineColor = light ? Colors.white.withValues(alpha: 0.75) : AppColors.border;
    // Checkpoints sit at 1/6, 1/2 and 5/6 of the width. Each layer is a
    // zero-width anchor with an OverflowBox, so Align lands the centre exactly
    // and nothing here needs a LayoutBuilder (which cannot report intrinsic
    // sizes, and the gift page measures this row inside an IntrinsicHeight).
    Alignment at(int i) => Alignment(-1 + 2 * (2 * i + 1) / 6, 0);
    Widget anchor(Widget child, {required double w, required double h}) =>
        SizedBox(width: 0, height: h, child: OverflowBox(minWidth: w, maxWidth: w, minHeight: h, maxHeight: h, child: child));
    return SizedBox(
      height: 84,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: 0,
            right: 0,
            top: 42,
            height: 2,
            child: FractionallySizedBox(
              alignment: Alignment.center,
              widthFactor: 2 / 3,
              child: CustomPaint(painter: _DashedPainter(color: lineColor, width: 2, dash: 7, gap: 6)),
            ),
          ),
          for (var i = 0; i < 3; i++) ...[
            Positioned(left: 0, right: 0, top: 28, child: Align(alignment: at(i), child: anchor(_checkpoint(i), w: 30, h: 30))),
            Positioned(
              left: 0,
              right: 0,
              top: 66,
              child: Align(
                alignment: at(i),
                child: anchor(
                  Text(
                    labels[i],
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1,
                      color: i == step
                          ? (light ? Colors.white : AppColors.textPrimary)
                          : (light ? Colors.white.withValues(alpha: 0.7) : AppColors.textSecondary),
                    ),
                  ),
                  w: 120,
                  h: 14,
                ),
              ),
            ),
          ],
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            child: AnimatedAlign(
              duration: const Duration(milliseconds: 500),
              curve: Curves.easeOutCubic,
              alignment: at(step),
              child: anchor(const Titi(TitiPose.rolling, height: 34), w: 44, h: 34),
            ),
          ),
        ],
      ),
    );
  }

  Widget _checkpoint(int i) {
    final isDone = i < done;
    final isCurrent = i == step;
    if (isDone || isCurrent) {
      return Container(
        width: 30,
        height: 30,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: AppColors.brand,
          shape: BoxShape.circle,
          boxShadow: [BoxShadow(color: AppColors.brand.withValues(alpha: 0.35), blurRadius: 10, offset: const Offset(0, 3))],
        ),
        child: isDone
            ? const Icon(AppIcons.check, size: 16, color: Colors.white)
            : Container(width: 9, height: 9, decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle)),
      );
    }
    return Container(
      width: 30,
      height: 30,
      decoration: BoxDecoration(
        color: light ? Colors.white.withValues(alpha: 0.25) : AppColors.surfaceGray,
        shape: BoxShape.circle,
        border: Border.all(color: light ? Colors.white.withValues(alpha: 0.7) : AppColors.border, width: 1.5),
      ),
    );
  }
}

/// Dashes along a path: a line (default), a rounded rectangle ([radius]) or
/// a circle.
class _DashedPainter extends CustomPainter {
  const _DashedPainter({required this.color, required this.width, this.dash = 6, this.gap = 5, this.radius, this.circle = false});
  final Color color;
  final double width;
  final double dash;
  final double gap;
  final double? radius;
  final bool circle;

  Path _path(Size s) {
    final inset = Rect.fromLTWH(width / 2, width / 2, s.width - width, s.height - width);
    if (circle) return Path()..addOval(inset);
    if (radius != null) return Path()..addRRect(RRect.fromRectAndRadius(inset, Radius.circular(radius!)));
    return Path()
      ..moveTo(0, s.height / 2)
      ..lineTo(s.width, s.height / 2);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = width
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    for (final metric in _path(size).computeMetrics()) {
      var d = 0.0;
      while (d < metric.length) {
        canvas.drawPath(metric.extractPath(d, math.min(d + dash, metric.length)), paint);
        d += dash + gap;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedPainter old) =>
      old.color != color || old.width != width || old.dash != dash || old.gap != gap || old.radius != radius || old.circle != circle;
}

/// Big dashed target for the car photo (tap = choose), with Camera and
/// Gallery pills that skip the source sheet.
class _DropZone extends StatelessWidget {
  const _DropZone({required this.onTap, required this.onCamera, required this.onGallery});
  final VoidCallback? onTap;
  final VoidCallback? onCamera;
  final VoidCallback? onGallery;

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: CustomPaint(
          foregroundPainter: _DashedPainter(color: AppColors.border, width: 2, dash: 8, gap: 6, radius: 24),
          child: Container(
            padding: const EdgeInsets.fromLTRB(20, 30, 20, 22),
            decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(24)),
            child: Column(
              children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(color: AppColors.surfaceGray, shape: BoxShape.circle),
                  child: Icon(AppIcons.cameraPlus, size: 30, color: AppColors.textPrimary),
                ),
                const SizedBox(height: 14),
                Text('Add a photo of your car', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
                const SizedBox(height: 6),
                Text(
                  'Front three-quarter angle works best.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary, height: 1.4),
                ),
                const SizedBox(height: 18),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _Pill(icon: AppIcons.camera, label: 'Camera', onTap: onCamera, filled: true),
                    const SizedBox(width: 10),
                    _Pill(icon: AppIcons.images, label: 'Gallery', onTap: onGallery, filled: false),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
}

/// Pill button: ink-filled or white with a border.
class _Pill extends StatelessWidget {
  const _Pill({required this.icon, required this.label, required this.onTap, required this.filled});
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final fg = filled ? Colors.white : AppColors.ink;
    return PressScale(
      enabled: onTap != null,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: BoxDecoration(
            color: filled ? AppColors.ink : Colors.white,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: filled ? AppColors.ink : AppColors.border),
            boxShadow: filled ? null : [BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 8, offset: const Offset(0, 2))],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 15, color: fg),
              const SizedBox(width: 6),
              Text(label, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: fg)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Home-state chip. Selected is unmistakable: brand fill, a tick, white bold
/// text and a small pop. Unselected is white with a thin border. The same
/// chip is used for the short list, "More…" and the full list.
class _StateChip extends StatelessWidget {
  const _StateChip({required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback? onTap;

  static const _duration = Duration(milliseconds: 160);

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: AnimatedScale(
          scale: selected ? 1.06 : 1,
          duration: _duration,
          curve: Curves.easeOutBack,
          child: AnimatedContainer(
            duration: _duration,
            curve: Curves.easeOut,
            padding: EdgeInsets.fromLTRB(selected ? 10 : 14, 9, 14, 9),
            decoration: BoxDecoration(
              color: selected ? AppColors.brand : Colors.white,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: selected ? AppColors.brand : AppColors.border),
              boxShadow: selected ? [BoxShadow(color: AppColors.brand.withValues(alpha: 0.3), blurRadius: 10, offset: const Offset(0, 3))] : null,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (selected) ...[
                  const Icon(AppIcons.check, size: 14, color: Colors.white),
                  const SizedBox(width: 5),
                ],
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                    color: selected ? Colors.white : AppColors.ink,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
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

/// 72 px dashed circle with a plus; shows the picked (or existing) picture.
class _AvatarPicker extends StatelessWidget {
  const _AvatarPicker({required this.file, required this.preset, required this.existingUrl, required this.onTap});
  final XFile? file;
  final int? preset;
  final String? existingUrl;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    ImageProvider? image;
    if (file != null) {
      image = FileImage(File(file!.path));
    } else if (preset != null) {
      image = AssetImage(DefaultAvatars.asset(preset!));
    } else {
      image = DefaultAvatars.image(existingUrl);
    }
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: 72,
        height: 72,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (image == null)
              CustomPaint(painter: _DashedPainter(color: AppColors.border, width: 2, dash: 6, gap: 5, circle: true))
            else
              Container(
                decoration: BoxDecoration(shape: BoxShape.circle, image: DecorationImage(image: image, fit: BoxFit.cover)),
              ),
            Align(
              alignment: image == null ? Alignment.center : Alignment.bottomRight,
              child: Container(
                width: image == null ? 28 : 22,
                height: image == null ? 28 : 22,
                decoration: BoxDecoration(color: image == null ? AppColors.surfaceGray : AppColors.ink, shape: BoxShape.circle),
                child: Icon(image == null ? AppIcons.plus : AppIcons.pencilSimple, size: image == null ? 16 : 12, color: image == null ? AppColors.textPrimary : Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _UppercaseFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) =>
      newValue.copyWith(text: newValue.text.toUpperCase());
}
