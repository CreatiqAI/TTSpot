import 'dart:async';
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
import '../../../core/supabase/supabase_client.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/titi.dart';
import '../../../core/utils/friendly_error.dart';
import '../../../core/widgets/avatar_crop_screen.dart';
import '../../../core/widgets/glass.dart';
import '../../../core/widgets/photo_picker_sheet.dart';
import '../../../core/widgets/picker_field.dart';
import '../../../core/widgets/primary_button.dart';
import '../../../core/widgets/titi_avatar_grid.dart';
import '../../../core/widgets/user_avatar.dart' show DefaultAvatars;
import '../../cards/application/cards_providers.dart';
import '../../cards/domain/cards.dart';
import '../../onboarding/presentation/permissions_screen.dart';
import '../../profile/application/plate_hiding.dart';
import '../../profile/application/profile_providers.dart';
import '../../profile/data/profile_repository.dart';
import '../../profile/domain/car.dart';
import '../../profile/domain/car_recognition.dart';
import '../../profile/presentation/widgets/car_color_picker.dart';
import '../../profile/presentation/widgets/car_scan_widgets.dart';
import '../../profile/presentation/widgets/plate_editor.dart';
import '../../settings/application/settings_providers.dart';
import '../../settings/presentation/settings_screen.dart' show LegalScreen;
import '../application/account_basics.dart';
import '../application/auth_controller.dart';
import '../application/onboarding_controller.dart';
import '../application/username_suggestion.dart';
import '../data/auth_repository.dart';
import 'garage_setup_screen.dart';
import 'widgets/onboarding_progress.dart';
import 'widgets/username_field.dart';

/// First-run setup, guided by TiTi. One route, four pages switched here
/// (TiTi's welcome is the app's front door now, before sign-in: see
/// WelcomeScreen), with a thin progress bar and a back arrow on top:
/// 1. your ride: one photo; the recogniser guesses make, model, year and
///    colour (all editable).
/// 2. you: avatar (cropped round), name, username (suggested from the
///    name), home state, phone, Terms.
///    Then "Building your garage" while the toy render of the car is awaited
///    (new members only; see GarageSetupScreen).
/// 3. permissions: the same page as /location (PermissionsScreen), inside
///    the flow, so the router doesn't show it again this launch.
/// 4. a gift: the first blind box, when one is waiting.
/// An existing member who only lacks a car, or a phone + Terms, lands on
/// that step alone: no bar, no permissions page, no gift.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key, @visibleForTesting this.debugStartAt, @visibleForTesting this.debugGift});

  /// Tests only: open on this page with the profile already saved.
  final OnboardingPage? debugStartAt;
  /// Tests only: the blind box the gift page shows.
  final CardBox? debugGift;

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

/// The pages a new member walks through, in order. "Building your garage"
/// sits between [you] and [permissions] but isn't a step of its own.
enum OnboardingPage { ride, you, permissions, gift }

/// Where the bar stands on [page]: step n of [kOnboardingSteps].
int onboardingStepOf(OnboardingPage page) => page.index + 1;
const kOnboardingSteps = 4;

/// The page after [page] for a new member; null = done (the router moves
/// on). The gift page only shows when a blind box is waiting.
OnboardingPage? onboardingPageAfter(OnboardingPage page, {required bool hasGift}) => switch (page) {
      OnboardingPage.ride => OnboardingPage.you,
      OnboardingPage.you => OnboardingPage.permissions,
      OnboardingPage.permissions => hasGift ? OnboardingPage.gift : null,
      OnboardingPage.gift => null,
    };

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _formKey = GlobalKey<FormState>();
  final _username = TextEditingController();
  final _displayName = TextEditingController();
  final _referral = TextEditingController();
  final _phone = TextEditingController();
  bool _acceptedTerms = false;
  String? _homeState;
  /// The cropped profile photo (a square JPEG), uploaded on Continue.
  Uint8List? _avatar;
  /// A picked TiTi default avatar (0..7); saved as its public URL.
  int? _preset;
  bool _prefilled = false;
  bool _validate = false;
  bool _showReferral = false;
  /// The member typed their own username: no more suggestions.
  bool _usernameTouched = false;
  /// The last username filled in from the name.
  String _autoUsername = '';
  Timer? _suggestTimer;
  int _suggestRun = 0;
  /// Looking for the first blind box after the profile saved.
  bool _giftChecking = false;
  CardBox? _gift;
  /// "Building your garage" is on: the car it shows, and the gift lookup
  /// that runs underneath it meanwhile.
  Car? _building;
  Future<CardBox?>? _giftLookup;
  /// The car parked in step 1 this session (null when it was parked earlier).
  String? _carId;
  /// A page the member went to with the back arrow or past the profile
  /// save; null = the one the profile calls for (ride or you).
  OnboardingPage? _page;
  /// The profile was saved this session (so "you" again just goes on to
  /// permissions, without building the garage twice).
  bool _profileSaved = false;
  /// What the parked car was saved with, to skip a save when nothing changed.
  ({String make, String model, String year, String? color})? _parked;

  // step 1 — the car
  final _make = TextEditingController();
  final _model = TextEditingController();
  final _year = TextEditingController();
  String? _carColor;
  /// The file just picked, shown while the recogniser is still looking.
  XFile? _pickedFile;
  /// The photo that gets uploaded (plate blurred first when [_hidePlate]).
  CarFormPhoto? _carPick;
  /// "Hide my number plate": off unless the member turned it on before.
  late bool _hidePlate = ref.read(settingsProvider).hidePlate;
  bool get _hiding => _carPick?.working ?? false;
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
  void initState() {
    super.initState();
    _username.addListener(_onUsernameChanged);
    if (widget.debugStartAt != null) {
      _page = widget.debugStartAt;
      _profileSaved = widget.debugStartAt!.index > OnboardingPage.you.index;
      _gift = widget.debugGift;
    }
  }

  @override
  void dispose() {
    _suggestTimer?.cancel();
    _username.removeListener(_onUsernameChanged);
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
      _carPick = null;
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
    final pick = CarFormPhoto.picked(prepared.bytes, scan: prepared.guess);
    if (_hidePlate) _hideCarPlate(pick); // the scan already says where the plate is
    setState(() {
      _carPreparing = false;
      _carPick = pick;
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

  void _setHidePlate(bool v) {
    setState(() => _hidePlate = v);
    ref.read(settingsActionsProvider).patch({'hide_plate': v}).catchError((_) {});
    if (v && _carPick != null) _hideCarPlate(_carPick!);
  }

  /// Blurs the plate on [pick] so the photo above shows what goes up. False
  /// when it couldn't be checked.
  Future<bool> _hideCarPlate(CarFormPhoto pick) async {
    final run = ref.read(plateHiderProvider).prepare(pick);
    if (mounted) setState(() {}); // the shimmer while it works
    final ok = await run;
    if (mounted) setState(() {});
    return ok;
  }

  /// Check the plate, full screen. Blurring a plate there turns the switch
  /// on: that's what the member asked for.
  Future<void> _checkCarPlate(CarFormPhoto pick) async {
    final changed = await showPlateEditor(context, pick);
    if (!mounted) return;
    if (changed && !_hidePlate && pick.boxes.isNotEmpty) {
      _setHidePlate(true);
      _snack('Hide my number plate is on.');
    }
    setState(() {});
  }

  /// Back on "your ride" after parking: the car is already saved this
  /// session, so its photo stays and only the details can change.
  bool get _rideParked => _carSaved && _carId != null;

  Future<void> _submitCar() async {
    FocusScope.of(context).unfocus();
    setState(() => _carValidate = true);
    if (_carPreparing) return;
    if (_make.text.trim().isEmpty || _model.text.trim().isEmpty) {
      setState(() => _editingCar = true);
      return;
    }
    if (_rideParked) return _updateParkedCar();
    final pick = _carPick;
    if (pick == null) {
      _snack('Add a photo of your car.');
      return;
    }
    // With the switch on, never upload a photo whose plate couldn't be checked.
    if (_hidePlate && !await _hideCarPlate(pick)) {
      if (mounted) _snack('Couldn\'t hide the plate. Check your connection, or turn off Hide my number plate.');
      return;
    }
    if (!mounted) return;
    // Spec line / body style only while they still describe this make + model.
    final g = _guess;
    final keepGuess = g != null && g.matches(_make.text, _model.text);
    final id = await ref.read(carFormControllerProvider.notifier).save(
          make: _make.text,
          model: _model.text,
          yearText: _year.text,
          description: '',
          color: _carColor,
          photos: [pick.plan(hidePlate: _hidePlate)],
          specs: keepGuess ? g.specLine : null,
          bodyStyle: keepGuess ? g.bodyStyle : null,
        );
    if (id != null && mounted) {
      HapticFeedback.lightImpact();
      setState(() {
        _carSaved = true;
        _carId = id;
        _parked = _carDetails;
      });
      ref.invalidate(currentProfileProvider); // carCount updates → step 2, or the router moves on
    }
  }

  ({String make, String model, String year, String? color}) get _carDetails =>
      (make: _make.text.trim(), model: _model.text.trim(), year: _year.text.trim(), color: _carColor);

  /// The member came back to fix the car's details: save them on the same
  /// car (photo kept as it is), then on to "you" again.
  Future<void> _updateParkedCar() async {
    final now = _carDetails;
    if (now == _parked) {
      setState(() => _page = OnboardingPage.you);
      return;
    }
    final repo = ref.read(profileRepositoryProvider);
    Car? car;
    try {
      car = await repo.fetchCar(_carId!);
    } catch (e) {
      if (mounted) _snack(friendlyError(e));
      return;
    }
    if (!mounted || car == null) return;
    final g = _guess;
    final keepGuess = g != null && g.matches(_make.text, _model.text);
    final id = await ref.read(carFormControllerProvider.notifier).save(
          carId: car.id,
          make: _make.text,
          model: _model.text,
          yearText: _year.text,
          description: car.description ?? '',
          color: _carColor,
          photos: [for (final url in car.photoUrls) CarPhotoSave.keep(url)],
          specs: keepGuess ? g.specLine : car.specs,
          bodyStyle: keepGuess ? g.bodyStyle : car.bodyStyle,
          garageStyle: car.garageStyle,
        );
    if (id != null && mounted) {
      HapticFeedback.lightImpact();
      setState(() {
        _parked = now;
        _page = OnboardingPage.you;
      });
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
      if (file == null || !mounted) return;
      final bytes = await file.readAsBytes();
      if (!mounted) return;
      // Zoom and move it under the circle: that square is what goes up.
      final cropped = await cropAvatar(context, bytes, dark: true);
      if (cropped == null || !mounted) return;
      setState(() {
        _avatar = cropped;
        _preset = null;
      });
    } catch (e) {
      if (mounted) _snack(friendlyError(e));
    }
  }

  // ─────────────────────────────────────────────── username from the name ──

  void _onNameChanged(String name) {
    if (_usernameTouched) return;
    _suggestTimer?.cancel();
    _suggestTimer = Timer(const Duration(milliseconds: 450), () => _suggestUsername(name));
  }

  /// Fills the username from the name ("Aiman Hakim" → aiman_hakim, or
  /// aiman_hakim7 when that one is taken) until the member types their own.
  Future<void> _suggestUsername(String name) async {
    final run = ++_suggestRun;
    final suggestion = await suggestUsername(name, ref.read(usernameAvailabilityProvider));
    if (!mounted || run != _suggestRun || _usernameTouched) return;
    // Nothing usable (a very short name, or one in Chinese): leave the field
    // as it is, unless it still shows an older suggestion.
    if (suggestion == null && _username.text != _autoUsername) return;
    _autoUsername = suggestion ?? '';
    _username.value = TextEditingValue(text: _autoUsername, selection: TextSelection.collapsed(offset: _autoUsername.length));
  }

  void _onUsernameChanged() {
    if (_username.text != _autoUsername) _usernameTouched = true;
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
          avatar: _avatar == null ? null : XFile.fromData(_avatar!, name: 'avatar.jpg', mimeType: 'image/jpeg'),
          presetAvatarUrl: _preset == null ? null : DefaultAvatars.publicUrl(_preset!),
          referralCode: _referral.text,
          phone: _phone.text,
          acceptedTerms: _acceptedTerms,
          refreshProfile: false,
        );
    if (!mounted || ref.read(onboardingControllerProvider).hasError) return;
    if (existing) {
      ref.invalidate(currentProfileProvider);
      return;
    }
    if (_profileSaved) {
      // Back here from permissions: the garage is built already.
      setState(() => _page = OnboardingPage.permissions);
      return;
    }
    _profileSaved = true;
    await _startBuilding();
  }

  /// The profile is saved. A new member watches "Building your garage" for
  /// their car while the first blind box (granted by the database the moment
  /// the username is set) is looked up underneath; then the gift page, or the
  /// router moves on. No car to show (should not happen) → straight to the gift.
  Future<void> _startBuilding() async {
    setState(() => _giftChecking = true);
    Car? car;
    try {
      final repo = ref.read(profileRepositoryProvider);
      if (_carId != null) {
        car = await repo.fetchCar(_carId!);
      } else {
        final me = ref.read(currentUserIdProvider);
        if (me != null) car = (await repo.fetchCars(me)).firstOrNull;
      }
    } catch (_) {
      car = null;
    }
    if (!mounted) return;
    _giftLookup = _findGift();
    if (car == null) return _toPermissions(await _giftLookup!);
    setState(() => _building = car);
  }

  Future<CardBox?> _findGift() async {
    try {
      ref.invalidate(myBoxesProvider);
      final boxes = await ref.read(myBoxesProvider.future);
      return boxes.where((b) => b.sealed).firstOrNull;
    } catch (_) {
      return null;
    }
  }

  /// "Building your garage" is over (toy ready, cap reached or any error).
  Future<void> _buildingDone() async {
    CardBox? box;
    try {
      box = await (_giftLookup ?? _findGift());
    } catch (_) {
      box = null;
    }
    if (!mounted) return;
    _toPermissions(box);
  }

  /// On to the permissions page, with the gift (if any) waiting after it.
  void _toPermissions(CardBox? box) {
    if (!mounted) return;
    setState(() {
      _gift = box;
      _giftChecking = false;
      _building = null;
      _page = OnboardingPage.permissions;
    });
  }

  /// Continue on the permissions page (it has marked the step done for this
  /// launch, so the router won't show /location again): the gift, or the
  /// router moves on.
  void _permissionsDone() {
    if (!mounted) return;
    if (onboardingPageAfter(OnboardingPage.permissions, hasGift: _gift != null) == OnboardingPage.gift) {
      HapticFeedback.lightImpact();
      setState(() => _page = OnboardingPage.gift);
      return;
    }
    ref.invalidate(currentProfileProvider); // the router moves on
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
      // A saved username is the member's own; otherwise suggest one from a
      // name that's already there (an Apple sign-in name, say).
      _autoUsername = profile.username ?? '';
      _username.text = _autoUsername;
      _usernameTouched = _autoUsername.isNotEmpty;
      if (!_usernameTouched && _displayName.text.trim().isNotEmpty) _onNameChanged(_displayName.text);
      _homeState = malaysianStates.contains(profile.homeState) ? profile.homeState : null;
      if (basics?.phone != null) _phone.text = prettyPhone(basics!.phone!);
    }
    final existing = (profile?.isOnboarded ?? false) && !_profileSaved;
    final basicsDone = basics?.complete ?? false;

    if (_building != null) {
      return GarageSetupScreen(
        key: ValueKey(_building!.id),
        car: _building!,
        readCar: ref.read(profileRepositoryProvider).fetchCar,
        onDone: _buildingDone,
      );
    }
    if (_page == OnboardingPage.gift && _gift != null) return _giftPage(_gift!);
    if (_page == OnboardingPage.permissions) return _permissionsPage();

    // No car yet → step 1. Once it is parked, the profile step (or, for a
    // member whose profile is already complete, the router moves on). The
    // back arrow on "you" brings the parked car back here.
    final needsRide = profile != null && profile.needsCar && !_carSaved;
    if (needsRide || (_page == OnboardingPage.ride && _rideParked && _carPick != null)) {
      return _ridePage(
        busy: ref.watch(carFormControllerProvider).isLoading || _carPreparing,
        existing: existing,
        onlyStep: existing && basicsDone,
      );
    }
    return _youPage(busy: busy, existing: existing, avatarUrl: profile?.avatarUrl);
  }

  /// The top of a page: the progress bar for a new member; an existing
  /// member (one missing piece) gets the step's name and the cross.
  Widget _header({required bool existing, required OnboardingPage page, required bool busy, VoidCallback? onBack, String? title}) {
    if (!existing) {
      return OnboardingProgress(
        step: onboardingStepOf(page),
        total: kOnboardingSteps,
        onBack: onBack,
        onClose: _signOut,
        enabled: !busy,
      );
    }
    return SizedBox(
      height: OnboardingProgress.height,
      child: Row(
        children: [
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              title ?? '',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.2, color: AppColors.textSecondary),
            ),
          ),
          IconButton(
            tooltip: 'Sign out',
            icon: Icon(AppIcons.x, size: 22, color: AppColors.textPrimary),
            onPressed: busy ? null : _signOut,
          ),
        ],
      ),
    );
  }

  /// Header pinned on top, the page scrolling under it.
  Widget _frame({required Widget header, required Widget body}) => Scaffold(
        body: SafeArea(
          bottom: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(padding: const EdgeInsets.symmetric(horizontal: 8), child: header),
              Expanded(child: body),
            ],
          ),
        ),
      );

  // ─────────────────────────────────────────────────────────── 1. your ride ──

  Widget _ridePage({required bool busy, required bool existing, required bool onlyStep}) {
    final Widget body;
    if (_carPreparing && _pickedFile != null) {
      body = _rideScanning(existing: existing);
    } else if (_carPick != null) {
      body = _rideFound(busy: busy, existing: existing);
    } else {
      body = _rideEmpty(busy: busy, existing: existing);
    }
    return _frame(
      header: _header(existing: existing, page: OnboardingPage.ride, busy: busy || _carPreparing, title: 'YOUR RIDE'),
      body: body,
    );
  }

  Widget _rideEmpty({required bool busy, required bool existing}) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 12),
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
            const SizedBox(height: 12),
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
    final parked = _rideParked;
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
          // Photo, edge to edge under the bar, fading into the page. Cover-fit
          // in a fixed box, so a tall or wide photo looks the same.
          SizedBox(
            height: 300,
            child: Stack(
              fit: StackFit.expand,
              children: [
                // A tap opens Check the plate (move, resize or add the blur).
                GestureDetector(
                  onTap: !busy && !_hiding && !parked ? () => _checkCarPlate(_carPick!) : null,
                  child: Image(image: _carPick!.image(hidePlate: _hidePlate), fit: BoxFit.cover, gaplessPlayback: true),
                ),
                if (_hidePlate && _hiding) const Positioned.fill(child: PhotoShimmer()),
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
                if (_carPick!.plateHidden(hidePlate: _hidePlate))
                  const Positioned(left: 20, bottom: 20, child: IgnorePointer(child: PlateHiddenBadge())),
                if (!parked)
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
                // Parked already: the toy is being made from this photo and
                // colour, so only the words can change here.
                if (!parked) ...[
                const SizedBox(height: 22),
                CarMapColourSection(value: _carColor, note: colourText, onChanged: busy ? null : (v) => setState(() => _carColor = v)),
                const SizedBox(height: 14),
                HidePlateSwitch(
                  value: _hidePlate,
                  onChanged: busy ? null : _setHidePlate,
                  working: _hiding,
                  failed: _carPick!.failed,
                  photos: _carPick!.checked ? 1 : 0,
                  blurred: _carPick!.plateHidden(hidePlate: true) ? 1 : 0,
                  guessed: _carPick!.guessed && _carPick!.hasBlur ? 1 : 0,
                ),
                ],
                const SizedBox(height: 14),
                PrimaryButton(
                  label: parked ? 'Continue' : 'Park it in my garage',
                  loading: busy || _hiding,
                  onPressed: busy || _hiding ? null : _submitCar,
                ),
                if (!parked) ...[
                  const SizedBox(height: 4),
                  TextButton(
                    onPressed: busy ? null : _pickCarPhoto,
                    child: Text('Not your car? Try another photo', style: TextStyle(color: AppColors.textSecondary, fontWeight: FontWeight.w600)),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────── 2. you ──

  Widget _youPage({required bool busy, required bool existing, String? avatarUrl}) {
    // Back to the car parked this session (its photo is still here).
    final canGoBack = !existing && _rideParked && _carPick != null;
    return _frame(
      header: _header(
        existing: existing,
        page: OnboardingPage.you,
        busy: busy,
        onBack: canGoBack
            ? () {
                FocusScope.of(context).unfocus();
                setState(() => _page = OnboardingPage.ride);
              }
            : null,
      ),
      body: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
          child: Form(
            key: _formKey,
            autovalidateMode: _validate ? AutovalidateMode.always : AutovalidateMode.disabled,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
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
                  const SizedBox(height: 12),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      _AvatarPicker(bytes: _avatar, preset: _preset, existingUrl: avatarUrl, onTap: busy ? null : () => _pickAvatar(avatarUrl)),
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
                  onChanged: _onNameChanged,
                ),
                const _Label('HANDLE'),
                UsernameField(controller: _username, textInputAction: TextInputAction.next),
                const _Label('HOME STATE'),
                // One field; the list opens in a sheet.
                PickerField<String>(
                  key: ValueKey('home-state-$_prefilled'),
                  label: 'Home state',
                  options: [for (final st in malaysianStates) (st, st)],
                  value: _homeState,
                  icon: AppIcons.mapPin,
                  enabled: !busy,
                  onChanged: (v) => setState(() => _homeState = v),
                  validator: (v) => v == null ? 'Choose your state' : null,
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
                            Flexible(
                              child: Text('Have a referral code?', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: AppColors.textPrimary, decoration: TextDecoration.underline)),
                            ),
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
    );
  }

  // ───────────────────────────────────────────────────── 3. permissions ──

  /// The /location page, inside the flow: the same cards and Continue, with
  /// the bar on top. Continue marks the step done for this launch.
  Widget _permissionsPage() => PermissionsScreen(
        key: const ValueKey('onboarding-permissions'),
        header: OnboardingProgress(
          step: onboardingStepOf(OnboardingPage.permissions),
          total: kOnboardingSteps,
          dark: true,
          onBack: () => setState(() => _page = OnboardingPage.you),
        ),
        onDone: _permissionsDone,
      );

  // ──────────────────────────────────────────────────────────── 4. a gift ──

  Widget _giftPage(CardBox box) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: AppColors.ink,
        body: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: OnboardingProgress(
                  step: onboardingStepOf(OnboardingPage.gift),
                  total: kOnboardingSteps,
                  dark: true,
                  onBack: () => setState(() => _page = OnboardingPage.permissions),
                ),
              ),
              Expanded(
                child: _FillScroll(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
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
            ],
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
                // Side by side; one under the other on a narrow phone with big text.
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    _Pill(icon: AppIcons.camera, label: 'Camera', onTap: onCamera, filled: true),
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

/// 72 px dashed circle with a plus; shows the cropped (or existing) picture.
class _AvatarPicker extends StatelessWidget {
  const _AvatarPicker({required this.bytes, required this.preset, required this.existingUrl, required this.onTap});
  final Uint8List? bytes;
  final int? preset;
  final String? existingUrl;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    ImageProvider? image;
    if (bytes != null) {
      image = MemoryImage(bytes!);
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
