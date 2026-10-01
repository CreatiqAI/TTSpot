import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// The white-ink TT Spot logo, legible on photos.
const kPortraitWatermarkAsset = 'assets/brand/logo_dark.png';

/// Portraits stay clean in the app (members paid for them); only a copy
/// that leaves the app carries a small TT Spot logo, bottom right.
///
/// Draws [logo] (cropped to its ink, ignoring the transparent padding) at
/// [widthFraction] of the photo's width and [opacity], with a soft dark
/// shadow under it so it reads on light and dark pictures alike. Same size
/// as [photo]; the caller disposes the result.
Future<ui.Image> watermarkPortrait(ui.Image photo, ui.Image logo, {double widthFraction = 0.12, double opacity = 0.85}) async {
  final ink = await _inkBounds(logo);
  final w = photo.width.toDouble();
  final h = photo.height.toDouble();
  final logoW = w * widthFraction;
  final logoH = logoW * ink.height / ink.width;
  final margin = w * 0.035;
  final dst = ui.Rect.fromLTWH(w - margin - logoW, h - margin - logoH, logoW, logoH);
  final quality = ui.FilterQuality.high;

  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  canvas.drawImage(photo, ui.Offset.zero, ui.Paint()..filterQuality = quality);

  // Shadow: the logo's shape in black, blurred, nudged down a hair.
  final sigma = logoW * 0.05;
  final shadow = dst.shift(ui.Offset(0, logoW * 0.015));
  canvas.saveLayer(shadow.inflate(sigma * 3), ui.Paint()..imageFilter = ui.ImageFilter.blur(sigmaX: sigma, sigmaY: sigma));
  canvas.drawImageRect(
    logo,
    ink,
    shadow,
    ui.Paint()
      ..filterQuality = quality
      ..colorFilter = const ui.ColorFilter.mode(ui.Color(0x99000000), ui.BlendMode.srcIn),
  );
  canvas.restore();

  // The logo itself, slightly see-through.
  canvas.saveLayer(dst.inflate(2), ui.Paint()..color = ui.Color.fromRGBO(0, 0, 0, opacity));
  canvas.drawImageRect(logo, ink, dst, ui.Paint()..filterQuality = quality);
  canvas.restore();

  final picture = recorder.endRecording();
  try {
    return await picture.toImage(photo.width, photo.height);
  } finally {
    picture.dispose();
  }
}

/// The logo files carry wide transparent margins; this finds the drawn part
/// (alpha above a faint-halo threshold). Cached per image size, since the
/// same asset comes back every time.
Future<ui.Rect> _inkBounds(ui.Image logo) async {
  final key = (logo.width, logo.height);
  final cached = _inkCache[key];
  if (cached != null) return cached;
  final full = ui.Rect.fromLTWH(0, 0, logo.width.toDouble(), logo.height.toDouble());
  final data = await logo.toByteData(format: ui.ImageByteFormat.rawStraightRgba);
  if (data == null) return full;
  final w = logo.width, h = logo.height;
  bool solid(int x, int y) => data.getUint8((y * w + x) * 4 + 3) > 24;
  bool rowHas(int y) {
    for (var x = 0; x < w; x++) {
      if (solid(x, y)) return true;
    }
    return false;
  }

  var top = 0, bottom = h - 1;
  while (top < h && !rowHas(top)) {
    top++;
  }
  if (top >= h) return full; // nothing drawn
  while (bottom > top && !rowHas(bottom)) {
    bottom--;
  }
  bool colHas(int x) {
    for (var y = top; y <= bottom; y++) {
      if (solid(x, y)) return true;
    }
    return false;
  }

  var left = 0, right = w - 1;
  while (left < right && !colHas(left)) {
    left++;
  }
  while (right > left && !colHas(right)) {
    right--;
  }
  return _inkCache[key] = ui.Rect.fromLTRB(left.toDouble(), top.toDouble(), right + 1.0, bottom + 1.0);
}

final _inkCache = <(int, int), ui.Rect>{};

/// Opens the share sheet with the portrait at [url] as a PNG, logo added.
/// The picture comes from the image cache when it's already on screen.
Future<void> sharePortrait({required String url, required String fileTag, required String text, ui.Rect? origin}) async {
  final photo = await _resolve(CachedNetworkImageProvider(url));
  ui.Image? logo;
  ui.Image? marked;
  try {
    logo = await _decodeAsset(kPortraitWatermarkAsset);
    marked = await watermarkPortrait(photo, logo);
    final data = await marked.toByteData(format: ui.ImageByteFormat.png);
    if (data == null) throw StateError('Could not encode the portrait');
    final dir = await getTemporaryDirectory();
    final tag = fileTag.replaceAll(RegExp(r'[^A-Za-z0-9_-]+'), '_');
    final file = File('${dir.path}/ttspot-portrait-$tag-${DateTime.now().millisecondsSinceEpoch}.png');
    await file.writeAsBytes(data.buffer.asUint8List(), flush: true);
    await SharePlus.instance.share(ShareParams(
      files: [XFile(file.path, mimeType: 'image/png')],
      text: text,
      sharePositionOrigin: origin,
    ));
  } finally {
    photo.dispose();
    logo?.dispose();
    marked?.dispose();
  }
}

Future<ui.Image> _decodeAsset(String asset) async {
  final bytes = await rootBundle.load(asset);
  final codec = await ui.instantiateImageCodec(bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes));
  try {
    return (await codec.getNextFrame()).image;
  } finally {
    codec.dispose();
  }
}

/// The full-size picture behind [provider] (a clone the caller disposes).
Future<ui.Image> _resolve(ImageProvider provider) {
  final done = Completer<ui.Image>();
  final stream = provider.resolve(ImageConfiguration.empty);
  late final ImageStreamListener listener;
  listener = ImageStreamListener(
    (info, _) {
      if (!done.isCompleted) done.complete(info.image.clone());
      info.dispose();
      stream.removeListener(listener);
    },
    onError: (e, st) {
      if (!done.isCompleted) done.completeError(e, st);
      stream.removeListener(listener);
    },
  );
  stream.addListener(listener);
  return done.future.timeout(const Duration(seconds: 45), onTimeout: () {
    stream.removeListener(listener);
    throw TimeoutException('The portrait took too long to load');
  });
}
