import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/http_bytes.dart';
import '../../../core/utils/plate_blur.dart';
import '../data/profile_repository.dart';
import '../domain/car_photo_storage.dart';
import '../domain/car_recognition.dart';
import '../domain/plate_geometry.dart';

// "Hide my number plate" for every photo in a car form (onboarding's car
// step, Add car, Edit car): photos picked just now and photos already saved
// on the car. The switch on blurs the plate on each one right away (the
// thumbnails show it), off shows the originals again, and Save uploads the
// blurred copies (replacing saved originals). Check the plate edits the
// boxes (see PlateEditorScreen).

/// One photo in a car form: picked just now ([CarFormPhoto.picked], bytes
/// only) or already on the car ([CarFormPhoto.saved], a URL).
class CarFormPhoto {
  /// [scan] is the recogniser's answer for this photo when it already ran
  /// (it says where the plate is).
  CarFormPhoto.picked(Uint8List bytes, {CarRecognition? scan})
      : url = null,
        savedBlurred = false,
        _original = bytes,
        _found = scan == null ? null : [if (scan.plate != null) blurBoxFromDetection(scan.plate!)];

  CarFormPhoto.saved(String this.url) : savedBlurred = isPlateBlurredUrl(url);

  /// Set for a photo already on the car.
  final String? url;

  /// A saved photo that went up with its plate blurred: nothing to hide, and
  /// its original is gone, so turning the switch off keeps it blurred.
  final bool savedBlurred;

  Uint8List? _original;
  (int, int)? _size;
  List<PlateBox>? _found;
  bool _guessed = false;
  List<PlateBox>? _boxes;
  bool _edited = false;
  Uint8List? _blurred;
  Future<bool>? _pending;
  bool _failed = false;

  bool get isSaved => url != null;

  /// Loading, looking for the plate or blurring right now.
  bool get working => _pending != null;

  /// Couldn't be loaded or blurred (offline, say).
  bool get failed => _failed;

  /// The recogniser couldn't be asked, so the blur sits where a plate
  /// usually is until the member checks it.
  bool get guessed => _guessed && !_edited;

  /// The photo's bytes and size once loaded (a saved photo is downloaded).
  Uint8List? get original => _original;
  (int, int)? get size => _size;

  /// Width / height, 4:3 until loaded.
  double get aspect => _size == null || _size!.$2 == 0 ? 4 / 3 : _size!.$1 / _size!.$2;

  /// Where the recogniser put the plate (padded), or null when it hasn't
  /// looked. Reset in Check the plate goes back to this.
  List<PlateBox>? get found => _found == null ? null : List.unmodifiable(_found!);

  /// What gets blurred.
  List<PlateBox> get boxes => List.unmodifiable(_boxes ?? const <PlateBox>[]);

  /// What Check the plate opens with: the boxes so far, else what the
  /// recogniser found.
  List<PlateBox> get editorBoxes => List.of(_boxes ?? _found ?? const <PlateBox>[]);

  /// We know what to blur (maybe nothing) and the blurred copy is ready.
  bool get checked => savedBlurred || (_boxes != null && (_boxes!.isEmpty || _blurred != null));

  /// A new blurred copy is ready.
  bool get hasBlur => _blurred != null && (_boxes?.isNotEmpty ?? false);

  /// The plate is hidden on what shows with the switch at [hidePlate].
  bool plateHidden({required bool hidePlate}) => savedBlurred || (hidePlate && hasBlur);

  /// Checked and nothing to blur: the recogniser saw no plate.
  bool get noPlate => !savedBlurred && _boxes != null && _boxes!.isEmpty;

  /// What shows with the switch at [hidePlate]: the blurred copy, else the
  /// original. [width] decodes it smaller (thumbnails).
  ImageProvider image({required bool hidePlate, int? width}) {
    final ImageProvider p = hidePlate && hasBlur ? MemoryImage(_blurred!) : (url != null ? CachedNetworkImageProvider(url!) : MemoryImage(_original!));
    return width == null ? p : ResizeImage.resizeIfNeeded(width, null, p);
  }

  /// What Save does with this photo. Switch on: the blurred copy goes up (a
  /// saved one is replaced). Switch off: new photos go up as picked, saved
  /// ones stay as they are (blurred ones stay blurred).
  CarPhotoSave plan({required bool hidePlate}) {
    if (hidePlate && hasBlur) return CarPhotoSave.upload(_blurred!, plateBlurred: true, replaces: url);
    if (url != null) return CarPhotoSave.keep(url!);
    return CarPhotoSave.upload(_original!);
  }
}

/// One photo in a save, in order: keep a URL, or upload bytes (replacing a
/// saved photo when [replaces] is set).
class CarPhotoSave {
  const CarPhotoSave.keep(String this.url)
      : bytes = null,
        plateBlurred = false,
        replaces = null;
  const CarPhotoSave.upload(Uint8List this.bytes, {this.plateBlurred = false, this.replaces}) : url = null;

  final String? url;
  final Uint8List? bytes;
  final bool plateBlurred;

  /// The saved photo this upload takes the place of (its original is
  /// deleted after the save).
  final String? replaces;
}

/// Loads, checks and blurs [CarFormPhoto]s. Remembers saved photos' bytes
/// and plates for the session, so opening Edit car again is instant.
class PlateHider {
  PlateHider(this._repo);
  final ProfileRepository _repo;

  final _bytes = <String, Future<Uint8List>>{};
  final _plates = <String, List<PlateBox>>{};
  static const _keepBytes = 10;

  /// Gets [p] ready for the switch: its bytes, where the plate is, and the
  /// blurred copy. When the recogniser can't be asked, the blur goes where a
  /// plate usually is ([CarFormPhoto.guessed]). False when the photo couldn't
  /// be loaded or blurred.
  Future<bool> prepare(CarFormPhoto p) {
    if (p.checked) return Future.value(true);
    return p._pending ??= _prepare(p).whenComplete(() => p._pending = null);
  }

  Future<bool> _prepare(CarFormPhoto p) async {
    p._failed = false;
    if (!await _load(p)) return false;
    await _detect(p);
    p._boxes ??= List.of(p._found!);
    return _render(p);
  }

  /// For Check the plate: the photo's bytes and size, and where the plate
  /// is (the recogniser is asked when nobody has yet). False when it couldn't
  /// be loaded.
  Future<bool> loadForEditor(CarFormPhoto p) async {
    final running = p._pending;
    if (running != null) await running;
    if (!await _load(p)) return false;
    await _detect(p);
    return true;
  }

  /// Done in Check the plate: these boxes get blurred from now on.
  Future<bool> applyBoxes(CarFormPhoto p, List<PlateBox> boxes) async {
    p._boxes = [for (final b in boxes) b.normalized()];
    p._edited = true;
    p._blurred = null;
    p._failed = false;
    if (!await _load(p)) return false;
    return _render(p);
  }

  Future<bool> _load(CarFormPhoto p) async {
    if (p._original != null && p._size != null) return true;
    try {
      p._original ??= await _download(p.url!);
      p._size ??= await imageSizeOf(p._original!);
      return true;
    } catch (e) {
      if (kDebugMode) debugPrint('Plate: could not load ${p.url}: $e');
      p._failed = true;
      return false;
    }
  }

  Future<void> _detect(CarFormPhoto p) async {
    if (p._found != null) return;
    if (p.savedBlurred) {
      p._found = const []; // already hidden
      return;
    }
    final known = p.url == null ? null : _plates[p.url];
    if (known != null) {
      p._found = known;
      return;
    }
    try {
      // A saved photo is read from storage by URL; a new one goes up as a
      // data URL, so its original never touches storage.
      final r = p.url != null ? await _repo.recognizeCar(photoUrl: p.url) : await _repo.recognizeCar(bytes: p._original);
      p._found = [if (r.plate != null) blurBoxFromDetection(r.plate!)];
      if (p.url != null) _plates[p.url!] = p._found!;
    } catch (e) {
      if (kDebugMode) debugPrint('Plate: recogniser failed, guessing: $e');
      p._found = [defaultPlateBox(aspect: p.aspect)];
      p._guessed = true;
    }
  }

  Future<bool> _render(CarFormPhoto p) async {
    final boxes = p._boxes ?? const <PlateBox>[];
    if (boxes.isEmpty) {
      p._blurred = null;
      return true;
    }
    try {
      p._blurred = await blurRegions(p._original!, [for (final b in boxes) (x0: b.x0, y0: b.y0, x1: b.x1, y1: b.y1)]);
      return true;
    } catch (e) {
      if (kDebugMode) debugPrint('Plate: blur failed: $e');
      p._failed = true;
      return false;
    }
  }

  Future<Uint8List> _download(String url) {
    final hit = _bytes.remove(url);
    if (hit != null) return _bytes[url] = hit; // most recent last
    final f = downloadBytes(url);
    _bytes[url] = f;
    unawaited(f.then<void>((_) {}, onError: (Object _) {
      _bytes.remove(url); // try again next time
    }));
    while (_bytes.length > _keepBytes) {
      _bytes.remove(_bytes.keys.first);
    }
    return f;
  }
}

final plateHiderProvider = Provider<PlateHider>((ref) => PlateHider(ref.watch(profileRepositoryProvider)));

/// A blurred copy as it goes up: JPEG (a few hundred KB) rather than the
/// engine's PNG (a few MB), same pixels. The PNG when that fails.
Future<Uint8List> compactBlurredPhoto(Uint8List png) async {
  try {
    // minWidth / minHeight above the photo: re-encode only, never resize.
    final jpg = await FlutterImageCompress.compressWithList(png, minWidth: 8192, minHeight: 8192, quality: 90, format: CompressFormat.jpeg);
    if (jpg.isNotEmpty && jpg.length < png.length) return jpg;
  } catch (e) {
    if (kDebugMode) debugPrint('Plate: JPEG re-encode failed, keeping PNG: $e');
  }
  return png;
}
