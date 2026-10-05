import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../domain/car.dart';

// Where the garage's pictures come from: the toy render, the cut-out and the
// member's photo, cached from the network in the app. Widget tests (and the
// TOY_DEMO build) swap the source.

/// Turns a stored URL into an image: cached from the network in the app;
/// widget tests swap in bundled assets (there is no network there).
@visibleForTesting
ImageProvider Function(String url) garageImageFor = (url) => CachedNetworkImageProvider(url);

/// The member's own cover photo (never the AI portrait), else the portrait,
/// decoded at about the size a card shows it.
ImageProvider? garagePhotoProvider(Car car, {int decodeWidth = 820}) {
  final url = car.photoCover ?? car.portraitUrl;
  if (url == null) return null;
  return ResizeImage(garageImageFor(url), width: decodeWidth, policy: ResizeImagePolicy.fit);
}

/// A car's cut-out, as stored (already sized for the garage).
ImageProvider? garageCutoutProvider(Car car) => car.cutoutUrl == null ? null : garageImageFor(car.cutoutUrl!);

/// The car's toy render, when it has one.
ImageProvider? garageToyProvider(Car car) {
  final demo = toyDemoProvider(car);
  if (demo != null) return demo;
  return car.toyUrl == null ? null : garageImageFor(car.toyUrl!);
}

/// "01", "02"…
String bayNumber(int index) => (index + 1).toString().padLeft(2, '0');

// ---- TOY_DEMO (debug builds only) -------------------------------------------
//
// `--dart-define=TOY_DEMO=true` shows the approved toy renders without the
// toy columns in the database: push design/toy_car/*_c.png to the phone as
// /sdcard/Download/toy_demo/{estima,civic,myvi,a911}.png. Today's car gets a
// toy (picked by model name), the other cars show the "building" fallback.
// `TOY_DEMO=all` gives every car a toy, `TOY_DEMO=pending` none (all
// building), `TOY_DEMO=failed` none (plain fallback). Never on in release.

const _toyDemo = String.fromEnvironment('TOY_DEMO');

bool get toyDemoOn => kDebugMode && _toyDemo.isNotEmpty && _toyDemo != 'false';

/// The demo's stand-in for `toy_status`: null when the demo is off.
String? toyDemoStatus(Car car) {
  if (!toyDemoOn) return null;
  return switch (_toyDemo) {
    'all' => 'ready',
    'pending' => 'pending',
    'failed' => 'failed',
    _ => car.isDefault ? 'ready' : 'pending',
  };
}

ImageProvider? toyDemoProvider(Car car) {
  if (toyDemoStatus(car) != 'ready') return null;
  final m = '${car.make} ${car.model}'.toLowerCase();
  final pick = m.contains('estima') || m.contains('alphard') || m.contains('vellfire')
      ? 'estima'
      : m.contains('civic') || m.contains('city') || m.contains('accord')
          ? 'civic'
          : m.contains('myvi') || m.contains('axia') || m.contains('bezza') || m.contains('perodua')
              ? 'myvi'
              : 'a911';
  return FileImage(File('/sdcard/Download/toy_demo/$pick.png'));
}
