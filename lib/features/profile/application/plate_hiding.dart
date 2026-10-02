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

export '../domain/car_photo_storage.dart' show CarPhotoSave;

// "Hide my number plate" for every photo in a car form (onboarding's car
// step, Add car, Edit car): photos picked just now and photos already saved
// on the car. The switch on blurs the plate on each one right away (the
// thumbnails show it), off shows the originals again, and Save uploads the
// blurred copies (replacing saved originals, which move to the private
// car-originals bucket). Check the plate edits the boxes and can show a
// blurred photo's kept original again (see PlateEditorScreen).

/// One photo in a car form: picked just now ([CarFormPhoto.picked], bytes
/// only) or already on the car ([CarFormPhoto.saved], a URL).
class CarFormPhoto {
  /// [scan] is the recogniser's answer for this photo when it already ran
  /// (it says where the plate is).
  CarFormPhoto.picked(Uint8List bytes, {CarRecognition? scan})
      : url = null,
        originalPath = null,
        _original = bytes,
        _found = scan == null ? null : [if (scan.plate != null) blurBoxFromDetection(scan.plate!)];

  /// [originalPath]: where its original is kept (car-originals) when the
  /// photo went up blurred since 2 Oct 2026 (`Car.photoOriginals`).
  CarFormPhoto.saved(String this.url, {String? originalPath}) : originalPath = isPlateBlurredUrl(url) ? originalPath : null;

  /// Set for a photo already on the car.
  final String? url;

  /// The private original of a saved blurred photo, when it was kept.
  final String? originalPath;

  /// Showing the kept original instead of the saved blurred copy ("Show
  /// original"): Save puts the original back (or a new blur of it).
  bool _restored = false;

  /// Restored by turning the switch off (not in Check the plate): turning
  /// it back on goes back to the saved blurred copy.
  bool _restoredBySwitch = false;

  /// The saved blurred copy's bytes and size while [restored], to go back.
  Uint8List? _savedCopy;
  (int, int)? _savedCopySize;

  /// The kept original, once downloaded.
  Uint8List? _kept;

  /// A saved photo that went up with its plate blurred (and isn't showing
  /// its original): nothing to hide. Turning the switch off keeps it blurred
  /// unless its original was kept and the member asks for it.
  bool get savedBlurred => url != null && isPlateBlurredUrl(url!) && !_restored;

  /// A saved blurred photo whose original is kept: "Show original" can take
  /// the blur off.
  bool get canShowOriginal => savedBlurred && originalPath != null;

  /// A saved blurred photo whose original was deleted (blurred before
  /// 2 Oct 2026): it stays blurred.
  bool get originalLost => url != null && isPlateBlurredUrl(url!) && originalPath == null;

  /// Showing (and on Save putting back) the kept original.
  bool get restored => _restored;

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
    final ImageProvider p = hidePlate && hasBlur
        ? MemoryImage(_blurred!)
        : (url != null && !_restored ? CachedNetworkImageProvider(url!) : MemoryImage(_original!));
    return width == null ? p : ResizeImage.resizeIfNeeded(width, null, p);
  }

  /// What Save does with this photo (see [planCarPhoto]). Switch on: the
  /// blurred copy goes up (a saved one is replaced) and the original is kept
  /// privately. Switch off: new photos go up as picked, saved ones stay as
  /// they are (blurred ones stay blurred) unless their original was brought
  /// back.
  CarPhotoSave plan({required bool hidePlate}) => planCarPhoto(
        url: url,
        hidePlate: hidePlate,
        original: _original,
        blurred: hasBlur ? _blurred : null,
        restored: _restored,
        originalPath: originalPath,
      );

  /// Swaps the saved blurred copy for its kept original [bytes] ([size]):
  /// [boxes] are what to blur on it now (empty: nothing, the blur comes off;
  /// null: not checked yet, as when the switch was turned off).
  void _useOriginal(Uint8List bytes, (int, int) size, {List<PlateBox>? boxes, required bool bySwitch}) {
    if (!_restored) {
      _savedCopy = _original;
      _savedCopySize = _size;
    }
    _restored = true;
    _restoredBySwitch = bySwitch;
    _original = bytes;
    _size = size;
    _found = boxes == null ? null : const [];
    _boxes = boxes == null ? null : [for (final b in boxes) b.normalized()];
    _edited = boxes != null;
    _guessed = false;
    _blurred = null;
    _failed = false;
  }

  /// Back to the saved blurred copy.
  void _useSavedCopy() {
    if (!_restored) return;
    _restored = false;
    _restoredBySwitch = false;
    _original = _savedCopy;
    _size = _savedCopySize;
    _savedCopy = null;
    _savedCopySize = null;
    _found = const []; // already hidden
    _boxes = null;
    _edited = false;
    _guessed = false;
    _blurred = null;
    _failed = false;
  }
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
    p._restoredBySwitch = false; // worked on by hand: the switch leaves it be
    p._blurred = null;
    p._failed = false;
    if (!await _load(p)) return false;
    return _render(p);
  }

  /// The kept original of a saved blurred photo (car-originals, through a
  /// signed URL: only its owner can), with its size. Null when it couldn't
  /// be loaded or there is none.
  Future<(Uint8List, (int, int))?> loadOriginal(CarFormPhoto p) async {
    final path = p.originalPath;
    if (path == null) return null;
    try {
      final bytes = p._kept ??= await _download('$kCarOriginalsBucket/$path', () => _repo.downloadCarOriginal(path));
      return (bytes, await imageSizeOf(bytes));
    } catch (e) {
      if (kDebugMode) debugPrint('Plate: could not load the original $path: $e');
      return null;
    }
  }

  /// "Show original" done in Check the plate: [p] shows its kept original
  /// with [boxes] blurred on it (none: the blur comes off on Save). False
  /// when the original couldn't be loaded or blurred.
  Future<bool> showOriginal(CarFormPhoto p, List<PlateBox> boxes) async {
    final loaded = await loadOriginal(p);
    if (loaded == null) return false;
    p._useOriginal(loaded.$1, loaded.$2, boxes: boxes, bySwitch: false);
    return _render(p);
  }

  /// The switch turned off with "Show originals": every photo in [photos]
  /// that has a kept original shows it, unblurred. False when one couldn't
  /// be loaded (it stays blurred).
  Future<bool> showOriginals(Iterable<CarFormPhoto> photos) async {
    final runs = <Future<bool>>[
      for (final p in photos)
        if (p.canShowOriginal) _restoreBySwitch(p),
    ];
    return (await Future.wait(runs)).every((ok) => ok);
  }

  Future<bool> _restoreBySwitch(CarFormPhoto p) {
    Future<bool> run() async {
      final loaded = await loadOriginal(p);
      if (loaded == null) {
        p._failed = true;
        return false;
      }
      p._useOriginal(loaded.$1, loaded.$2, bySwitch: true);
      return true;
    }

    return p._pending ??= run().whenComplete(() => p._pending = null);
  }

  /// The switch back on: photos whose original only came back because the
  /// switch went off go back to their saved blurred copy.
  void blurAgain(Iterable<CarFormPhoto> photos) {
    for (final p in photos) {
      if (p._restored && p._restoredBySwitch) p._useSavedCopy();
    }
  }

  /// The saved blurred copy of [p] as it is on the car, with its size: for
  /// Check the plate going back from the original. Null when it couldn't be
  /// loaded.
  Future<(Uint8List, (int, int))?> loadSavedCopy(CarFormPhoto p) async {
    final url = p.url;
    if (url == null) return null;
    try {
      if (!p._restored) {
        if (!await _load(p)) return null;
        return (p._original!, p._size!);
      }
      final bytes = p._savedCopy ??= await _download(url, () => downloadBytes(url));
      final size = p._savedCopySize ??= await imageSizeOf(bytes);
      return (bytes, size);
    } catch (e) {
      if (kDebugMode) debugPrint('Plate: could not load $url: $e');
      return null;
    }
  }

  /// "Keep blurred" in Check the plate after the original was shown: back
  /// to the saved blurred copy, with [boxes] blurred on top of it.
  Future<bool> keepBlurred(CarFormPhoto p, List<PlateBox> boxes) async {
    p._useSavedCopy();
    if (boxes.isEmpty) return true;
    return applyBoxes(p, boxes);
  }

  Future<bool> _load(CarFormPhoto p) async {
    if (p._original != null && p._size != null) return true;
    try {
      p._original ??= await _download(p.url!, () => downloadBytes(p.url!));
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
    // A restored original is looked at as bytes: its URL is the blurred copy.
    final byUrl = p.url != null && !p._restored;
    final known = byUrl ? _plates[p.url] : null;
    if (known != null) {
      p._found = known;
      return;
    }
    try {
      // A saved photo is read from storage by URL; a new one goes up as a
      // data URL, so its original never touches storage.
      final r = byUrl ? await _repo.recognizeCar(photoUrl: p.url) : await _repo.recognizeCar(bytes: p._original);
      p._found = [if (r.plate != null) blurBoxFromDetection(r.plate!)];
      if (byUrl) _plates[p.url!] = p._found!;
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

  /// [key]'s bytes from [fetch], remembered for the session (the last
  /// [_keepBytes] photos).
  Future<Uint8List> _download(String key, Future<Uint8List> Function() fetch) {
    final hit = _bytes.remove(key);
    if (hit != null) return _bytes[key] = hit; // most recent last
    final f = fetch();
    _bytes[key] = f;
    unawaited(f.then<void>((_) {}, onError: (Object _) {
      _bytes.remove(key); // try again next time
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
