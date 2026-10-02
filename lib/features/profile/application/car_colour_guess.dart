import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';

import '../domain/car_colour.dart';

/// The car's map colour from its photo when the recogniser didn't give one
/// (see [dominantCarColour]); null when unsure or the photo can't be read.
/// Decodes a 48 px wide copy, so it's quick.
Future<String?> guessCarColour(Uint8List bytes) async {
  try {
    final codec = await ui.instantiateImageCodec(bytes, targetWidth: 48);
    final frame = await codec.getNextFrame();
    codec.dispose();
    final image = frame.image;
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (data == null) return null;
      return dominantCarColour(data.buffer.asUint8List(), image.width, image.height);
    } finally {
      image.dispose();
    }
  } catch (e) {
    if (kDebugMode) debugPrint('Car colour: could not read the photo: $e');
    return null;
  }
}
