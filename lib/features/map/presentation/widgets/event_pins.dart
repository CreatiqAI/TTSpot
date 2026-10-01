import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../../../core/theme/app_icons.dart';
import '../../../events/domain/event.dart';
import '../../application/map_filters.dart';
import 'map_glyphs.dart' show kEventRed, kGold, kInk;
import 'map_pins.dart';

/// The ring colour of an event pin by tier: gold for official clubs and
/// approved organizers, ink for partners, red for TT sessions and the rest.
Color tierRingColor(PinTier t) => switch (t) {
      PinTier.major => kGold,
      PinTier.partner => kInk,
      PinTier.minor => kEventRed,
    };

/// The small white mark in an event pin's corner badge: what kind of event.
IconData eventTypeGlyph(Event e) {
  if (e.type == EventType.tt || e.isInstant) return AppIcons.flagPennantFill;
  return switch (e.type) {
    EventType.trackday => AppIcons.flagCheckeredFill,
    EventType.convoy => AppIcons.carFill,
    EventType.charity => AppIcons.heartFill,
    EventType.official => AppIcons.crownFill,
    _ => e.isOfficialClubEvent ? AppIcons.crownFill : (e.vendorId != null ? AppIcons.storefrontFill : AppIcons.flagFill),
  };
}

/// Paints one event pin's head and pointer at [o] (top-left of a box
/// [side] wide): a round picture in a [ring] of the tier's colour inside a
/// white outline, a pointer under it whose tip is the event's spot, a badge
/// with [glyph] on the lower right and, when [live], a red LIVE tab on top.
/// [image] is null in the key (a plain disc of the ring colour). Shared by
/// the markers and the key so both always look the same.
void paintEventPin(
  Canvas c,
  Offset o, {
  required double side,
  required Color ring,
  required IconData glyph,
  ui.Image? image,
  bool crest = false,
  bool live = false,
  bool badge = true,
}) {
  final r = side / 2;
  final centre = o + Offset(r, r);
  final outline = math.max(1.5, side * 0.04);
  final ringW = math.max(2.0, side * 0.06);
  final tailH = eventPinTail(side);
  final tailW = side * 0.36;

  // Shadow under head and pointer.
  final shadow = Paint()
    ..color = Colors.black.withValues(alpha: 0.30)
    ..maskFilter = MaskFilter.blur(BlurStyle.normal, math.max(1.5, side * 0.05));
  final pointer = Path()
    ..moveTo(centre.dx - tailW / 2, centre.dy + r * 0.62)
    ..lineTo(centre.dx + tailW / 2, centre.dy + r * 0.62)
    ..lineTo(centre.dx, centre.dy + r + tailH)
    ..close();
  c.drawCircle(centre.translate(0, 1.5), r, shadow);
  c.drawPath(pointer.shift(const Offset(0, 1.5)), shadow);

  // White outline, then the ring colour, pointer first so the head covers its top.
  final white = Paint()..color = Colors.white;
  final ringPaint = Paint()..color = ring;
  c.drawPath(pointer, white..style = PaintingStyle.stroke..strokeWidth = outline * 2..strokeJoin = StrokeJoin.round);
  white.style = PaintingStyle.fill;
  c.drawPath(pointer, ringPaint);
  c.drawCircle(centre, r, white);
  c.drawCircle(centre, r - outline, ringPaint);

  // The picture.
  final inner = r - outline - ringW;
  final photo = Rect.fromCircle(center: centre, radius: inner);
  c.save();
  c.clipPath(Path()..addOval(photo));
  if (image == null) {
    c.drawCircle(centre, inner, ringPaint);
  } else if (crest) {
    // An emblem with see-through edges: fitted on white with a little room.
    c.drawCircle(centre, inner, white);
    _drawFit(c, image, photo.deflate(inner * 0.22));
  } else {
    _drawCover(c, image, photo);
  }
  c.restore();
  // No picture (the key): a solid disc of the tier's colour with the mark.
  if (image == null) _glyph(c, glyph, centre, (r - outline) * 1.1);

  // Type badge, lower right on the ring.
  if (badge) {
    final b = math.max(6.5, side * 0.15);
    final bc = centre + Offset(r * 0.70, r * 0.70);
    c.drawCircle(bc, b + 1.5, Paint()..color = Colors.white);
    c.drawCircle(bc, b, ringPaint);
    _glyph(c, glyph, bc, b * 1.25);
  }

  if (live) {
    final tp = TextPainter(
      text: TextSpan(text: 'LIVE', style: TextStyle(fontSize: math.max(7.5, side * 0.17), fontWeight: FontWeight.w900, color: Colors.white, height: 1, letterSpacing: 0.4)),
      textDirection: TextDirection.ltr,
    )..layout();
    final w = tp.width + 8, h = tp.height + 4;
    final tab = RRect.fromRectAndRadius(Rect.fromCenter(center: Offset(centre.dx, o.dy + 1), width: w, height: h), Radius.circular(h / 2));
    c.drawRRect(tab.inflate(1.5), Paint()..color = Colors.white);
    c.drawRRect(tab, Paint()..color = kEventRed);
    tp.paint(c, Offset(centre.dx - tp.width / 2, o.dy + 1 - tp.height / 2));
  }
}

/// The pointer's length under a head [side] across.
double eventPinTail(double side) => math.max(6.0, side * 0.2);

/// Room the LIVE tab needs above the head (it overlaps the top of the ring).
double eventPinLiveRoom(double side) => math.max(7.5, side * 0.17) / 2 + 4;

void _glyph(Canvas c, IconData g, Offset centre, double size) {
  final tp = TextPainter(
    text: TextSpan(text: String.fromCharCode(g.codePoint), style: TextStyle(fontFamily: g.fontFamily, fontSize: size, color: Colors.white, height: 1)),
    textDirection: TextDirection.ltr,
  )..layout();
  tp.paint(c, centre - Offset(tp.width / 2, tp.height / 2));
}

void _drawCover(Canvas canvas, ui.Image image, Rect dst) {
  final iw = image.width.toDouble(), ih = image.height.toDouble();
  final scale = math.max(dst.width / iw, dst.height / ih);
  final sw = dst.width / scale, sh = dst.height / scale;
  canvas.drawImageRect(image, Rect.fromLTWH((iw - sw) / 2, (ih - sh) / 2, sw, sh), dst, Paint()..filterQuality = FilterQuality.high);
}

void _drawFit(Canvas canvas, ui.Image image, Rect dst) {
  final iw = image.width.toDouble(), ih = image.height.toDouble();
  final scale = math.min(dst.width / iw, dst.height / ih);
  final w = iw * scale, h = ih * scale;
  canvas.drawImageRect(image, Rect.fromLTWH(0, 0, iw, ih), Rect.fromCenter(center: dst.center, width: w, height: h), Paint()..filterQuality = FilterQuality.high);
}

/// Renders event pins as pictures (see [paintEventPin]), sized by tier.
///
/// Never waits on the network: a pin whose photo is not on the phone yet is
/// drawn at once with its bundled stand-in (the club's crest or the type's
/// cover), the photo downloads in the background through the app's cached
/// network image plumbing, and [onImageReady] fires so the map can redraw
/// (the photo's bitmap then simply replaces the stand-in's). Bitmaps are
/// cached per picture, size and look; pictures per URL in [pins].
class EventPinFactory {
  EventPinFactory({required this.devicePixelRatio, required this.pins});
  final double devicePixelRatio;
  final MapPinFactory pins;

  /// A photo that a pin was drawn without has arrived: redraw. Set by the map.
  VoidCallback? onImageReady;

  final _cache = <String, MapPin>{};
  final _painting = <String, Future<MapPin>>{};
  final _fetching = <String>{};

  /// Pictures are decoded at most this wide (logical px): the biggest head.
  static const _imageWidth = 112;

  /// [e]'s pin at its [tier]'s size. [label] and [sub] add the name chip
  /// under it; [live] the LIVE tab.
  Future<MapPin> event(Event e, {required PinTier tier, bool live = false, String? label, String? sub}) async {
    final art = eventPinArt(e);
    final url = art.url;
    var src = art.asset;
    var crest = art.assetIsCrest;
    if (url != null) {
      // Bundled (assets/...) or already downloaded: use it straight away.
      if (url.startsWith('assets/') || pins.isLoaded(url)) {
        final img = await pins.image(url, targetWidth: _imageWidth);
        if (img != null) {
          src = url;
          crest = false;
        }
      } else {
        _fetch(url);
      }
    }
    final side = tierRule(tier).side;
    final ring = tierRingColor(tier);
    final glyph = eventTypeGlyph(e);
    final k = 'ev|$src|$crest|$side|${ring.toARGB32()}|${glyph.codePoint}|$live|$label|$sub';
    final cached = _cache[k];
    if (cached != null) return cached;
    // A block body: an arrow returning the removed future would make
    // whenComplete wait on itself.
    return _painting[k] ??= _paint(k, src, crest, side, ring, glyph, live, label, sub).whenComplete(() {
      _painting.remove(k);
    });
  }

  void _fetch(String url) {
    if (!_fetching.add(url)) return;
    pins.image(url, targetWidth: _imageWidth).then((img) {
      _fetching.remove(url);
      if (img != null) onImageReady?.call();
    });
  }

  Future<MapPin> _paint(String k, String src, bool crest, double side, Color ring, IconData glyph, bool live, String? label, String? sub) async {
    final image = await pins.image(src, targetWidth: _imageWidth);
    TextPainter? title, time;
    if (label != null && label.isNotEmpty) {
      title = pins.text(label.length > 18 ? '${label.substring(0, 17)}…' : label, 11, FontWeight.w700, Colors.white);
      if (sub != null && sub.isNotEmpty) time = pins.text(sub, 10.5, FontWeight.w500, const Color(0xFFB4BAC4));
    }
    const pad = 3.0, gap = 3.0;
    final top = live ? eventPinLiveRoom(side) : pad;
    final tail = eventPinTail(side);
    final chipW = title == null ? 0.0 : title.width + (time == null ? 0 : time.width + 5) + 14;
    final chipH = title == null ? 0.0 : math.max(title.height, time?.height ?? 0) + 8;
    // A little side room for the shadow and the badge's white edge.
    final w = math.max(side + 8, chipW + pad * 2);
    final tipY = top + side + tail;
    final h = tipY + (title == null ? 0 : gap + chipH) + pad + 2;
    final left = (w - side) / 2;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder)..scale(devicePixelRatio);
    paintEventPin(canvas, Offset(left, top), side: side, ring: ring, glyph: glyph, image: image, crest: crest, live: live);
    if (title != null) {
      final chipTop = tipY + gap;
      final rect = RRect.fromRectAndRadius(Rect.fromLTWH((w - chipW) / 2, chipTop, chipW, chipH), const Radius.circular(7));
      canvas.drawRRect(rect, Paint()..color = const Color(0xF21C1F26));
      title.paint(canvas, Offset((w - chipW) / 2 + 7, chipTop + 4));
      time?.paint(canvas, Offset((w - chipW) / 2 + 7 + title.width + 5, chipTop + 4.5));
    }
    final pin = await pins.finish(recorder, w, h, anchorY: tipY / h);
    return _cache[k] = pin;
  }

  void dispose() {
    onImageReady = null;
    _cache.clear();
    _painting.clear();
    _fetching.clear();
  }
}
