import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/titi.dart';
import '../../../core/utils/friendly_error.dart';
import '../../../core/utils/open_external.dart' show confirmSheet;
import '../../../core/widgets/primary_button.dart';
import '../../map/presentation/widgets/car_marker.dart' show kCarColorLabels;
import '../../settings/application/settings_providers.dart';
import '../application/car_colour_guess.dart';
import '../application/garage_providers.dart';
import '../application/plate_hiding.dart';
import '../application/profile_providers.dart';
import '../application/toy_providers.dart';
import '../data/profile_repository.dart';
import '../domain/car.dart';
import '../domain/car_recognition.dart';
import '../domain/car_toy.dart';
import 'widgets/car_color_picker.dart';
import 'widgets/car_papers_fields.dart';
import 'widgets/car_scan_widgets.dart';
import 'widgets/plate_editor.dart';

/// Add or edit a car. Pass [carId] to edit.
///
/// Adding is a short wizard: Photos (the first one goes through the
/// recogniser, like onboarding) → Your car (make, model, year, specs, paint
/// colour, all prefilled from the photo) → Papers (road tax, insurance,
/// PUSPAKOM; Skip for now) → Park it (summary + garage look). Going back
/// keeps everything. Editing is one form; a new paint colour repaints the
/// toy car when it is saved (migration 0110), within the daily cap.
///
/// Photos go up as picked unless "Hide my number plate" is on: then every
/// photo, saved ones too, shows its plate blurred right away, a tap opens
/// Check the plate, and Save swaps saved photos for their blurred copies
/// (the originals are kept privately, so the blur can come off again).
class CarFormScreen extends ConsumerStatefulWidget {
  const CarFormScreen({super.key, this.carId});
  final String? carId;

  @override
  ConsumerState<CarFormScreen> createState() => _CarFormScreenState();
}

/// The Add car steps.
enum _Step {
  photos('Photos'),
  car('Your car'),
  papers('Papers'),
  park('Park it');

  const _Step(this.label);
  final String label;
}

class _CarFormScreenState extends ConsumerState<CarFormScreen> {
  final _make = TextEditingController();
  final _model = TextEditingController();
  final _year = TextEditingController();
  String? _color;
  /// The colour was picked from the photo (recogniser or our own look), not
  /// by the member.
  bool _colorFromPhoto = false;
  /// The member tapped a swatch on this form (a saved colour says neither).
  bool _colorPicked = false;
  final _description = TextEditingController();
  /// The car's photos in order: saved ones first, then new picks.
  final _photos = <CarFormPhoto>[];
  bool _loaded = false;
  Car? _loadedCar;
  /// Toy renders left today for the car being edited (null: not known).
  ToyQuota? _quota;
  /// Garage look: 'auto' (cut-out) or 'card'.
  String _garageStyle = 'auto';

  // "Hide my number plate": off unless the member turned it on before.
  late bool _hidePlate = ref.read(settingsProvider).hidePlate;
  bool get _hiding => _photos.any((p) => p.working);

  // recognition
  bool _recognizing = false;
  /// The photo being scanned, shown in the scanning card.
  Uint8List? _scanBytes;
  DateTime? _scanStart;
  /// The recogniser is back; the status rows go green before the reveal.
  bool _scanDone = false;
  /// A scan ran and found nothing it was sure of.
  bool _scanMissed = false;
  CarRecognition? _guess;
  bool _guessed = false;

  // Add car wizard
  _Step _step = _Step.photos;
  /// Going forward (the next step slides in from the right) or back.
  bool _forward = true;
  /// Next was tapped on Your car: show what's missing.
  bool _validate = false;
  final _papers = CarPapersDraft();
  /// Saving the papers after the car (the car itself shows its own spinner).
  bool _savingPapers = false;

  bool get _isEdit => widget.carId != null;

  @override
  void dispose() {
    _make.dispose();
    _model.dispose();
    _year.dispose();
    _description.dispose();
    _papers.dispose();
    super.dispose();
  }

  void _prefill(Car c) {
    if (_loaded) return;
    _loaded = true;
    _loadedCar = c;
    _make.text = c.make;
    _model.text = c.model;
    _year.text = c.year?.toString() ?? '';
    _color = c.color;
    _description.text = c.description ?? '';
    _photos.addAll([for (final u in c.photoUrls) CarFormPhoto.saved(u, originalPath: c.photoOriginals[u])]);
    _garageStyle = c.garageStyle;
    // Already on: the saved photos show their plate blurred straight away.
    if (_hidePlate) WidgetsBinding.instance.addPostFrameCallback((_) => _hideAll());
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  /// The switch. Off, with saved photos whose original is kept: offers to
  /// show those originals again (the blur comes off on Save). On again:
  /// those go back to their blurred copies, and every photo gets checked.
  Future<void> _setHidePlate(bool v) async {
    setState(() => _hidePlate = v);
    ref.read(settingsActionsProvider).patch({'hide_plate': v}).catchError((_) {});
    final hider = ref.read(plateHiderProvider);
    if (v) {
      hider.blurAgain(_photos);
      _hideAll();
      return;
    }
    final kept = _photos.where((p) => p.canShowOriginal).toList();
    if (kept.isEmpty) return;
    final n = kept.length;
    final yes = await confirmSheet(
      context,
      icon: AppIcons.eye,
      title: n == 1 ? 'Show the original for 1 blurred photo?' : 'Show originals for $n blurred photos?',
      body: n == 1 ? 'It goes back on your car without the blur when you save.' : 'They go back on your car without the blur when you save.',
      confirm: 'Yes',
      cancel: 'Keep blurred',
    );
    if (!yes || !mounted || _hidePlate) return;
    final run = hider.showOriginals(kept);
    setState(() {}); // the shimmer on each one
    final ok = await run;
    if (!mounted) return;
    setState(() {});
    if (!ok) _snack('Couldn\'t load every original. Those photos stay blurred; try again from the photo.');
  }

  /// With the switch on, blurs the plate on every photo, saved ones too; each
  /// thumbnail shows its blurred copy as soon as it is ready. False when a
  /// photo couldn't be loaded or blurred.
  Future<bool> _hideAll() async {
    if (!_hidePlate || _photos.isEmpty) return true;
    final hider = ref.read(plateHiderProvider);
    final runs = [
      for (final p in List.of(_photos))
        hider.prepare(p).then((ok) {
          if (mounted) setState(() {});
          return ok;
        }),
    ];
    if (mounted) setState(() {}); // the shimmer on each photo being worked on
    return (await Future.wait(runs)).every((ok) => ok);
  }

  /// Check the plate, full screen. Blurring a plate there turns the switch
  /// on: that's what the member asked for.
  Future<void> _checkPlate(CarFormPhoto photo) async {
    final changed = await showPlateEditor(context, photo);
    if (!mounted) return;
    if (changed && !_hidePlate && photo.boxes.isNotEmpty) {
      _setHidePlate(true);
      _snack('Hide my number plate is on.');
    }
    setState(() {});
  }

  Future<void> _addPhoto() async {
    if (_photos.length >= 5) {
      _snack('Up to 5 photos per car.');
      return;
    }
    final source = await showModalBottomSheet<ImageSource>(
      useRootNavigator: true, // above the shell tab bar
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(leading: const Icon(AppIcons.images), title: const Text('Choose from library'), onTap: () => Navigator.pop(ctx, ImageSource.gallery)),
            ListTile(leading: const Icon(AppIcons.camera), title: const Text('Take photo'), onTap: () => Navigator.pop(ctx, ImageSource.camera)),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (source == null) return;
    Uint8List bytes;
    try {
      final f = await pickCarPhoto(source);
      if (f == null) return;
      bytes = await f.readAsBytes();
    } catch (e) {
      if (mounted) _snack(friendlyError(e));
      return;
    }
    if (!mounted) return;

    // Nothing typed yet (or only our earlier guess, and no photo left) → let
    // the photo fill the form in. Never overwrite what the member typed.
    final blank = _make.text.trim().isEmpty && _model.text.trim().isEmpty;
    final untouchedGuess = _guessed && _guess!.matches(_make.text, _model.text) && _photos.isEmpty;
    if (_isEdit || !(blank || untouchedGuess)) {
      setState(() => _photos.add(CarFormPhoto.picked(bytes)));
      _hideAll();
      _colourFromPhoto(bytes);
      return;
    }
    final started = DateTime.now();
    setState(() {
      _recognizing = true;
      _scanBytes = bytes;
      _scanStart = started;
      _scanDone = false;
    });
    final prepared = await prepareCarPhoto(ref.read(profileRepositoryProvider), bytes);
    if (!mounted) return;
    // Let the status rows finish ticking before the reveal, like onboarding.
    setState(() => _scanDone = true);
    final left = kCarScanHold - DateTime.now().difference(started);
    await Future<void>.delayed((left.isNegative ? Duration.zero : left) + const Duration(milliseconds: 450));
    if (!mounted) return;
    _photos.add(CarFormPhoto.picked(prepared.bytes, scan: prepared.guess));
    _hideAll(); // the scan already says where the plate is
    setState(() {
      _recognizing = false;
      _scanBytes = null;
      // The member may have typed while TiTi was looking: keep their words.
      final untouched = (_make.text.trim().isEmpty && _model.text.trim().isEmpty) || (_guessed && _guess!.matches(_make.text, _model.text));
      if (!untouched) return;
      final g = prepared.guess;
      if (g != null && g.confident) {
        _guess = g;
        _guessed = true;
        _scanMissed = false;
        _make.text = g.make;
        _model.text = g.model;
        _year.text = g.year?.toString() ?? '';
        if (g.color != null && (_color == null || _colorFromPhoto)) {
          _color = g.color;
          _colorFromPhoto = true;
        }
      } else {
        if (_guessed) {
          _make.clear();
          _model.clear();
          _year.clear();
        }
        _guess = null;
        _guessed = false;
        _scanMissed = true;
      }
    });
    _colourFromPhoto(prepared.bytes);
  }

  /// No colour yet (the recogniser didn't say): take the photo's dominant
  /// paint colour, when it's clear enough.
  Future<void> _colourFromPhoto(Uint8List bytes) async {
    if (_color != null || _photos.length > 1) return; // only from the cover
    final c = await guessCarColour(bytes);
    if (!mounted || c == null || _color != null) return;
    setState(() {
      _color = c;
      _colorFromPhoto = true;
    });
  }

  /// Saves the car (and on Add, its papers). Returns its id, or null when
  /// something stopped it (the error shows as a snack).
  Future<String?> _saveCar() async {
    FocusScope.of(context).unfocus();
    // With the switch on, never upload a photo whose plate couldn't be checked.
    if (_hidePlate && !await _hideAll()) {
      if (mounted) _snack('Couldn\'t hide the plate on every photo. Check your connection, or turn off Hide my number plate.');
      return null;
    }
    if (!mounted) return null;
    // Spec line / body style only while they still describe this make + model.
    String? specs;
    String? bodyStyle;
    final g = _guess;
    if (g != null && g.matches(_make.text, _model.text)) {
      specs = g.specLine;
      bodyStyle = g.bodyStyle;
    } else if (_loadedCar != null && _loadedCar!.make.trim().toLowerCase() == _make.text.trim().toLowerCase() && _loadedCar!.model.trim().toLowerCase() == _model.text.trim().toLowerCase()) {
      specs = _loadedCar!.specs;
      bodyStyle = _loadedCar!.bodyStyle;
    }
    return ref.read(carFormControllerProvider.notifier).save(
          carId: widget.carId,
          make: _make.text,
          model: _model.text,
          yearText: _year.text,
          description: _description.text,
          color: _color,
          photos: [for (final p in _photos) p.plan(hidePlate: _hidePlate)],
          specs: specs,
          bodyStyle: bodyStyle,
          garageStyle: _garageStyle,
        );
  }

  Future<void> _saveEdit() async {
    // What Save does to the toy, worked out before the car changes under us.
    final repaint = _repaints && paintKeyOf(_color) != _loadedCar?.paint;
    final quota = repaint ? _quota : null;
    final label = _color == null ? null : (kCarColorLabels[_color] ?? _color);
    final id = await _saveCar();
    if (id == null || !mounted) return;
    if (repaint) {
      ref.invalidate(carToyQuotaProvider(id));
      final text = quota != null && !quota.enabled
          ? 'Saved. Toy cars are taking a break, so the repaint waits.'
          : quota != null && quota.capped
              ? 'Saved. ${toyCapMessage(quota)}'
              : 'Repainting your toy car${label == null ? '' : ' $label'}. About 2 minutes; it swaps in on its own.';
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(text)));
    }
    context.pop();
  }

  /// Park it in my garage: the car, then its papers (only when something
  /// was filled in), then the car page.
  Future<void> _park() async {
    final id = await _saveCar();
    if (id == null || !mounted) return;
    final docs = _papers.documentsFor(id);
    if (docs != null) {
      setState(() => _savingPapers = true);
      try {
        await ref.read(garageActionsProvider).saveDocuments(docs);
      } catch (e) {
        if (mounted) _snack('Your car is parked, but the papers didn\'t save. Add them from the car page.');
      }
      if (!mounted) return;
      setState(() => _savingPapers = false);
    }
    HapticFeedback.lightImpact();
    context.pushReplacement(Routes.car(id));
  }

  // ── wizard ──

  void _goTo(_Step s) {
    FocusScope.of(context).unfocus();
    setState(() {
      _forward = s.index > _step.index;
      _step = s;
    });
  }

  void _next() {
    switch (_step) {
      case _Step.photos:
        _goTo(_Step.car);
      case _Step.car:
        if (_make.text.trim().isEmpty || _model.text.trim().isEmpty) {
          // The fields say "Required" (a snack would sit on the Next button).
          setState(() => _validate = true);
          HapticFeedback.mediumImpact();
          return;
        }
        _goTo(_Step.papers);
      case _Step.papers:
        _goTo(_Step.park);
      case _Step.park:
        _park();
    }
  }

  void _skipPapers() {
    setState(_papers.clear);
    _goTo(_Step.park);
  }

  void _back() {
    if (_step == _Step.photos) {
      context.pop();
    } else {
      _goTo(_Step.values[_step.index - 1]);
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(carFormControllerProvider, (_, next) {
      if (next.hasError && !next.isLoading) _snack(friendlyError(next.error!));
    });
    final saving = ref.watch(carFormControllerProvider).isLoading || _recognizing || _savingPapers;
    final busy = saving || _hiding;

    if (_isEdit) {
      // Toy renders left today, for the paint field's note.
      _quota = ref.watch(carToyQuotaProvider(widget.carId!)).value;
      final car = ref.watch(carProvider(widget.carId!));
      if (car.value == null && !car.hasError) {
        return Scaffold(appBar: AppBar(), body: const Center(child: CircularProgressIndicator(strokeWidth: 2)));
      }
      if (car.value != null) _prefill(car.value!);
      return _editForm(saving: saving, busy: busy);
    }
    return _wizard(saving: saving, busy: busy);
  }

  // ─────────────────────────────────────────────────────────── edit car ──

  Widget _editForm({required bool saving, required bool busy}) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(AppIcons.x), onPressed: busy ? null : () => context.pop()),
        title: const Text('Edit car'),
        actions: [
          busy
              ? const Padding(
                  padding: EdgeInsets.only(right: 20),
                  child: Center(child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))),
                )
              : TextButton(onPressed: _saveEdit, child: const Text('Save')),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          children: [
            ..._photoStrip(saving: saving, busy: busy),
            const SizedBox(height: 12),
            ..._carFields(),
          ],
        ),
      ),
    );
  }

  // ───────────────────────────────────────────────────────────── add car ──

  Widget _wizard({required bool saving, required bool busy}) {
    final last = _step == _Step.park;
    final nextLabel = switch (_step) {
      _Step.photos => _photos.isEmpty ? 'Next without a photo' : 'Next',
      _Step.papers => _papers.isEmpty ? 'Skip for now' : 'Next',
      _Step.park => 'Park it in my garage',
      _ => 'Next',
    };
    return PopScope(
      canPop: _step == _Step.photos && !busy,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !busy && _step != _Step.photos) _back();
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            tooltip: _step == _Step.photos ? 'Close' : 'Back',
            icon: Icon(_step == _Step.photos ? AppIcons.x : AppIcons.arrowLeft),
            onPressed: busy ? null : _back,
          ),
          title: const Text('Add car'),
        ),
        body: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(padding: const EdgeInsets.fromLTRB(16, 4, 16, 6), child: _WizardProgress(step: _step)),
              Expanded(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 260),
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeInCubic,
                  transitionBuilder: (child, anim) {
                    final incoming = child.key == ValueKey(_step);
                    final dx = (incoming == _forward) ? 0.12 : -0.12;
                    return FadeTransition(
                      opacity: anim,
                      child: SlideTransition(position: Tween(begin: Offset(dx, 0), end: Offset.zero).animate(anim), child: child),
                    );
                  },
                  child: KeyedSubtree(
                    key: ValueKey(_step),
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
                      children: switch (_step) {
                        _Step.photos => _photosStep(saving: saving, busy: busy),
                        _Step.car => _carStep(),
                        _Step.papers => _papersStep(busy: busy),
                        _Step.park => _parkStep(busy: busy),
                      },
                    ),
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                decoration: BoxDecoration(color: AppColors.bg, border: Border(top: BorderSide(color: AppColors.border, width: 0.5))),
                child: Row(
                  children: [
                    if (_step != _Step.photos) ...[
                      Expanded(flex: 2, child: SecondaryButton(label: 'Back', onPressed: busy ? null : _back)),
                      const SizedBox(width: 10),
                    ],
                    Expanded(
                      flex: 3,
                      child: PrimaryButton(
                        label: nextLabel,
                        icon: last ? AppIcons.garage : null,
                        loading: last && busy,
                        onPressed: busy ? null : _next,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _photosStep({required bool saving, required bool busy}) {
    if (_recognizing && _scanBytes != null) {
      return [
        CarScanningCard(image: MemoryImage(_scanBytes!), startedAt: _scanStart ?? DateTime.now(), done: _scanDone),
        const SizedBox(height: 18),
        Text(
          'Usually under 5 seconds. You can correct anything after.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary, height: 1.4),
        ),
      ];
    }
    final cover = _photos.firstOrNull;
    if (cover == null) {
      return [
        _StepIntro(pose: TitiPose.camera, title: 'Show me your ride', body: 'Snap or pick a photo of your car. I\'ll work out what it is and fill the rest in for you.'),
        const SizedBox(height: 18),
        GestureDetector(
          onTap: busy ? null : _addPhoto,
          child: AspectRatio(
            aspectRatio: 4 / 3,
            child: Container(
              decoration: BoxDecoration(
                color: AppColors.surfaceRaised,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: AppColors.border),
              ),
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(AppIcons.cameraPlus, size: 40, color: AppColors.textSecondary),
                      const SizedBox(height: 10),
                      Text('Add a photo', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
                      const SizedBox(height: 4),
                      Text('The first photo is the cover', textAlign: TextAlign.center, style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary)),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        HidePlateSwitch(value: _hidePlate, onChanged: saving ? null : _setHidePlate),
      ];
    }
    final model = _model.text.trim();
    return [
      GestureDetector(
        onTap: saving || cover.working ? null : () => _checkPlate(cover),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: AspectRatio(
            aspectRatio: 4 / 3,
            child: Stack(
              fit: StackFit.expand,
              children: [
                Image(image: cover.image(hidePlate: _hidePlate), fit: BoxFit.cover, gaplessPlayback: true),
                if (_hidePlate && cover.working) const PhotoShimmer(),
                if (cover.plateHidden(hidePlate: _hidePlate)) const Positioned(left: 12, bottom: 12, child: PlateHiddenBadge()),
              ],
            ),
          ),
        ),
      ),
      const SizedBox(height: 14),
      Row(
        children: [
          TitiAvatar(_guessed ? TitiPose.thumbsUp : (_scanMissed ? TitiPose.sad : TitiPose.camera), size: 44),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _guessed && model.isNotEmpty
                  ? 'Found it. Clean $model. Add more angles if you like, then Next.'
                  : _scanMissed
                      ? 'I couldn\'t tell what this is. You can type it in on the next step.'
                      : 'Nice. Add more angles if you like, then Next.',
              style: TextStyle(fontSize: 14.5, height: 1.35, color: AppColors.textPrimary),
            ),
          ),
        ],
      ),
      const SizedBox(height: 18),
      ..._photoStrip(saving: saving, busy: busy),
    ];
  }

  List<Widget> _carStep() {
    final make = _make.text.trim();
    final model = _model.text.trim();
    final tiles = carSpecTiles(_guess, make, model);
    return [
      CarFoundTitle(make: make, model: model, year: _year.text.trim().isNotEmpty ? _year.text.trim() : (_guess?.yearRange ?? '')),
      if (_guessed) ...[
        const SizedBox(height: 8),
        CarGuessNote(),
      ],
      if (tiles.isNotEmpty) ...[
        const SizedBox(height: 14),
        CarSpecGrid(tiles: tiles),
      ],
      const SizedBox(height: 18),
      ..._carFields(),
    ];
  }

  List<Widget> _papersStep({required bool busy}) {
    return [
      _StepIntro(
        pose: TitiPose.calendar,
        title: 'Papers, if you have them handy',
        body: 'Road tax, insurance and PUSPAKOM dates. We remind you 30, 7 and 1 day before road tax or insurance runs out. Only you can see this.',
      ),
      const SizedBox(height: 6),
      CarPapersFields(draft: _papers, enabled: !busy, onChanged: () => setState(() {})),
      const SizedBox(height: 18),
      Text(
        'Policy number, sum insured and the next service can go in later from the car page.',
        style: TextStyle(fontSize: 12.5, height: 1.4, color: AppColors.textSecondary),
      ),
      if (!_papers.isEmpty) ...[
        const SizedBox(height: 10),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: busy ? null : _skipPapers,
            icon: const Icon(AppIcons.arrowRight, size: 16),
            label: const Text('Skip for now (clear these)'),
          ),
        ),
      ],
    ];
  }

  List<Widget> _parkStep({required bool busy}) {
    final cover = _photos.firstOrNull;
    final make = _make.text.trim();
    final model = _model.text.trim();
    final colour = _color == null ? null : kCarColorLabels[_color];
    final docs = _papers.documentsFor('draft');
    return [
      if (cover != null) ...[
        ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: AspectRatio(
            aspectRatio: 16 / 10,
            child: Stack(
              fit: StackFit.expand,
              children: [
                Image(image: cover.image(hidePlate: _hidePlate), fit: BoxFit.cover, gaplessPlayback: true),
                if (_hidePlate && cover.working) const PhotoShimmer(),
                if (cover.plateHidden(hidePlate: _hidePlate)) const Positioned(left: 12, bottom: 12, child: PlateHiddenBadge()),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
      ],
      CarFoundTitle(make: make, model: model, year: _year.text.trim()),
      const SizedBox(height: 14),
      _SummaryRow(
        leading: MapCarPreview(color: _color, size: 40),
        title: colour == null ? 'No paint colour picked' : '$colour paint',
        subtitle: colour == null ? 'Your toy car keeps the colour of your photo.' : 'Your toy car is made in this colour.',
        onEdit: busy ? null : () => _goTo(_Step.car),
      ),
      const SizedBox(height: 10),
      _SummaryRow(
        leading: _SummaryIcon(AppIcons.shieldCheck),
        title: docs == null ? 'Papers skipped' : 'Papers saved with the car',
        subtitle: docs == null
            ? 'Add road tax and insurance later from the car page.'
            : docs.dues.isEmpty
                ? 'Insurance details'
                : docs.dues.map((d) => d.text).join('\n'),
        onEdit: busy ? null : () => _goTo(_Step.papers),
      ),
      const SizedBox(height: 10),
      _SummaryRow(
        leading: _SummaryIcon(_hidePlate ? AppIcons.eyeSlash : AppIcons.eye),
        title: _photos.isEmpty ? 'No photos' : (_photos.length == 1 ? '1 photo' : '${_photos.length} photos'),
        subtitle: _photos.isEmpty ? 'Your garage shows a drawing of the car until you add one.' : (_hidePlate ? 'Number plate hidden' : 'Number plate showing'),
        onEdit: busy ? null : () => _goTo(_Step.photos),
      ),
    ];
  }

  // ─────────────────────────────────────────────────────── shared parts ──

  List<Widget> _photoStrip({required bool saving, required bool busy}) {
    final checked = _photos.where((p) => p.checked).toList();
    return [
      Text('PHOTOS', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 1, color: AppColors.textSecondary)),
      const SizedBox(height: 8),
      SizedBox(
        height: 96,
        child: ListView(
          scrollDirection: Axis.horizontal,
          children: [
            for (final p in _photos)
              _Thumb(
                photo: p,
                hidePlate: _hidePlate,
                onRemove: busy ? null : () => setState(() => _photos.remove(p)),
                onTap: saving || p.working ? null : () => _checkPlate(p),
              ),
            if (_photos.length < 5)
              GestureDetector(
                onTap: busy ? null : _addPhoto,
                child: Container(
                  width: 96,
                  height: 96,
                  decoration: BoxDecoration(
                    color: AppColors.surfaceRaised,
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Icon(AppIcons.cameraPlus, color: AppColors.textSecondary),
                ),
              ),
          ],
        ),
      ),
      const SizedBox(height: 6),
      Text(
        _recognizing ? 'Looking at your car…' : '${_photos.length} of 5 · first photo is the cover',
        style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
      ),
      const SizedBox(height: 4),
      HidePlateSwitch(
        value: _hidePlate,
        onChanged: saving ? null : _setHidePlate,
        working: _hiding,
        failed: _photos.any((p) => p.failed),
        photos: checked.length,
        blurred: checked.where((p) => p.plateHidden(hidePlate: true)).length,
        guessed: checked.where((p) => p.guessed && p.hasBlur).length,
        stillBlurred: _photos.where((p) => p.savedBlurred).length,
        restoring: _photos.where((p) => p.restored && !p.plateHidden(hidePlate: _hidePlate)).length,
      ),
    ];
  }

  List<Widget> _carFields() {
    final yearHint = _guess?.yearRange;
    final missingMake = _validate && _make.text.trim().isEmpty;
    final missingModel = _validate && _model.text.trim().isEmpty;
    final paint = _paintNote();
    return [
      TextField(
        controller: _make,
        textCapitalization: TextCapitalization.words,
        textInputAction: TextInputAction.next,
        maxLength: 40,
        decoration: InputDecoration(labelText: 'Make', hintText: 'e.g. Perodua', counterText: '', errorText: missingMake ? 'Required' : null),
        onChanged: (_) => setState(() {}),
      ),
      const SizedBox(height: 14),
      TextField(
        controller: _model,
        textCapitalization: TextCapitalization.words,
        textInputAction: TextInputAction.next,
        maxLength: 60,
        decoration: InputDecoration(labelText: 'Model', hintText: 'e.g. Myvi 1.5 AV', counterText: '', errorText: missingModel ? 'Required' : null),
        onChanged: (_) => setState(() {}),
      ),
      const SizedBox(height: 14),
      TextField(
        controller: _year,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(4)],
        decoration: InputDecoration(labelText: 'Year (optional)', hintText: yearHint == null ? 'e.g. 2019' : 'Our guess: $yearHint'),
        onChanged: (_) => setState(() {}),
      ),
      const SizedBox(height: 14),
      TextField(
        controller: _description,
        maxLength: 500,
        minLines: 3,
        maxLines: 6,
        textCapitalization: TextCapitalization.sentences,
        decoration: const InputDecoration(
          labelText: 'Specs & mods (optional)',
          hintText: 'Turbo, coilovers, wheels, exhaust… or bone stock, that\'s fine too.',
          alignLabelWithHint: true,
          counterText: '',
        ),
      ),
      // The paint only goes into a car's first toy (one toy per car), so a
      // car that has its toy no longer offers it.
      if (!_isEdit || _loadedCar?.toyUrl == null) ...[
        const SizedBox(height: 18),
        CarMapColourSection(
          value: _color,
          hint: 'Your toy car is made in this colour.',
          note: paint.text,
          noteColor: paint.warn ? const Color(0xFFB45309) : null,
          onChanged: (v) => setState(() {
            _color = v;
            _colorFromPhoto = false;
            _colorPicked = true;
          }),
        ),
      ],
    ];
  }

  /// The paint the saved car's toy wears now: the paint it was made in, or
  /// (no toy yet) the saved colour.
  String? get _toyPaintNow {
    final c = _loadedCar;
    if (c == null) return null;
    return c.toyUrl != null ? c.toyPaint : c.paint;
  }

  /// Editing, with a toy to repaint: the picked paint differs from the one
  /// the toy wears, so saving repaints it.
  bool get _repaints => _isEdit && _loadedCar?.photoCover != null && _photos.isNotEmpty && paintKeyOf(_color) != _toyPaintNow;

  ({String? text, bool warn}) _paintNote() => paintFieldNote(
        color: _color,
        editing: _isEdit,
        repaints: _repaints,
        repainting: _isEdit && (_loadedCar?.toyRepainting ?? false) && paintKeyOf(_color) == _loadedCar?.paint,
        picked: _colorPicked,
        fromPhoto: _colorFromPhoto,
        quota: _quota,
      );
}

/// The line under "Your toy car is (re)painted in this colour.": where the
/// colour came from, or what Save does to the toy ([repaints]: the picked
/// paint differs from the one the toy wears), in amber ([warn]) when the
/// daily cap or a pause holds the repaint back.
({String? text, bool warn}) paintFieldNote({
  required String? color,
  required bool editing,
  required bool repaints,
  required bool picked,
  required bool fromPhoto,
  bool repainting = false,
  ToyQuota? quota,
  DateTime? now,
}) {
  if (color == null) {
    return (text: editing ? 'Now it keeps the colour of your photo. Pick one to repaint it.' : 'Pick the closest colour below.', warn: false);
  }
  final label = kCarColorLabels[color] ?? color;
  if (repainting) return (text: '$label · your toy is being repainted now, about 2 minutes', warn: false);
  if (repaints) {
    if (quota != null && !quota.enabled) return (text: 'Toy cars are taking a break, so the repaint waits. The colour still saves.', warn: true);
    if (quota != null && quota.capped) return (text: toyCapMessage(quota, now: now), warn: true);
    return (text: '$label · your toy is repainted when you save, about 2 minutes', warn: false);
  }
  if (editing && !picked) return (text: '$label · your toy\'s paint now', warn: false);
  return (text: carColourNote(color, fromPhoto: fromPhoto), warn: false);
}

/// Four segments and "Step 2 of 4 · Your car".
class _WizardProgress extends StatelessWidget {
  const _WizardProgress({required this.step});
  final _Step step;

  @override
  Widget build(BuildContext context) {
    final n = _Step.values.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            for (var i = 0; i < n; i++) ...[
              if (i > 0) const SizedBox(width: 6),
              Expanded(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 260),
                  height: 4,
                  decoration: BoxDecoration(color: i <= step.index ? AppColors.brand : AppColors.border, borderRadius: BorderRadius.circular(2)),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 8),
        Text.rich(
          TextSpan(
            children: [
              TextSpan(text: 'Step ${step.index + 1} of $n · ', style: TextStyle(color: AppColors.textSecondary)),
              TextSpan(text: step.label, style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w800)),
              if (step == _Step.papers) TextSpan(text: ' · optional', style: TextStyle(color: AppColors.textSecondary)),
            ],
          ),
          style: const TextStyle(fontSize: 12.5),
        ),
      ],
    );
  }
}

/// TiTi, a title and a line at the top of a step.
class _StepIntro extends StatelessWidget {
  const _StepIntro({required this.pose, required this.title, required this.body});
  final TitiPose pose;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TitiAvatar(pose, size: 48),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TextStyle(fontFamily: AppFonts.display, fontSize: 26, height: 1.05, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
                const SizedBox(height: 4),
                Text(body, style: TextStyle(fontSize: 13.5, height: 1.4, color: AppColors.textSecondary)),
              ],
            ),
          ),
        ],
      );
}

/// One line of the Park it summary, with Edit to jump back to its step.
class _SummaryRow extends StatelessWidget {
  const _SummaryRow({required this.leading, required this.title, required this.subtitle, required this.onEdit});
  final Widget leading;
  final String title;
  final String subtitle;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
        decoration: BoxDecoration(color: AppColors.surfaceGray, borderRadius: BorderRadius.circular(AppRadius.md)),
        child: Row(
          children: [
            leading,
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                  const SizedBox(height: 2),
                  Text(subtitle, style: TextStyle(fontSize: 12.5, height: 1.35, color: AppColors.textSecondary)),
                ],
              ),
            ),
            TextButton(onPressed: onEdit, child: const Text('Edit')),
          ],
        ),
      );
}

class _SummaryIcon extends StatelessWidget {
  const _SummaryIcon(this.icon);
  final IconData icon;

  @override
  Widget build(BuildContext context) => Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(color: AppColors.surface, shape: BoxShape.circle, border: Border.all(color: AppColors.border)),
        child: Icon(icon, size: 19, color: AppColors.textPrimary),
      );
}

class _Thumb extends StatelessWidget {
  const _Thumb({required this.photo, required this.hidePlate, required this.onRemove, this.onTap});
  final CarFormPhoto photo;
  final bool hidePlate;
  final VoidCallback? onRemove;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final hidden = photo.plateHidden(hidePlate: hidePlate);
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: SizedBox(
        width: 96,
        height: 96,
        child: Stack(
          children: [
            GestureDetector(
              onTap: onTap,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.md),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Image(image: photo.image(hidePlate: hidePlate, width: (96 * dpr * 1.5).round()), fit: BoxFit.cover, gaplessPlayback: true),
                    if (photo.working) const PhotoShimmer(),
                  ],
                ),
              ),
            ),
            // Top left, clear of the plate (low on the car) and the X. A
            // photo getting its original back says so.
            if (hidden || photo.restored)
              Positioned(
                left: 4,
                right: 30,
                top: 5,
                child: IgnorePointer(child: Align(alignment: Alignment.topLeft, child: PlateHiddenBadge(compact: true, original: !hidden))),
              ),
            Positioned(
              top: 4,
              right: 4,
              child: GestureDetector(
                onTap: onRemove,
                child: Container(
                  width: 22,
                  height: 22,
                  decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                  child: const Icon(AppIcons.x, size: 14, color: Colors.white),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
