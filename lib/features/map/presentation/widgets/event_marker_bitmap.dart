import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../../../core/utils/dates.dart';
import '../../../events/domain/event.dart';

/// A rendered marker plus where its tail tip sits (as a fraction of the image).
class EventMarkerBitmap {
  const EventMarkerBitmap(this.descriptor, this.anchor);
  final BitmapDescriptor descriptor;
  final Offset anchor;
}

/// Draws Instagram-style photo pins: rounded photo card with a coloured
/// border and pointed tail, and a dark label chip ("Sunway Night Meet · 2d").
/// Results are cached per event + label so re-renders are cheap.
class EventMarkerFactory {
  EventMarkerFactory({required this.devicePixelRatio});
  final double devicePixelRatio;

  final _cache = <String, EventMarkerBitmap>{};
  final _images = <String, ui.Image?>{};

  // Logical sizes (scaled by devicePixelRatio when rasterised).
  static const _cardW = 60.0;
  static const _cardH = 74.0;
  static const _radius = 14.0;
  static const _border = 3.0;
  static const _tailW = 14.0;
  static const _tailH = 9.0;
  static const _gap = 4.0;
  static const _chipPadH = 8.0;
  static const _chipPadV = 5.0;
  static const _maxTitleChars = 16;

  Future<EventMarkerBitmap> forEvent(Event e, {DateTime? now, String? label}) async {
    label ??= relativeShort(e.startsAt, now: now);
    final key = '${e.id}|$label|${e.coverUrl ?? ''}';
    final cached = _cache[key];
    if (cached != null) return cached;
    final image = e.coverUrl == null ? null : await _image(e.coverUrl!);
    final art = image == null ? await _asset(e.type.art) : null;
    final built = await _render(e, label, image, art);
    _cache[key] = built;
    return built;
  }

  Future<ui.Image?> _image(String url) async {
    if (_images.containsKey(url)) return _images[url];
    ui.Image? img;
    try {
      final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
      final req = await client.getUrl(Uri.parse(url));
      final res = await req.close();
      if (res.statusCode == 200) {
        final bytes = await _collect(res);
        final codec = await ui.instantiateImageCodec(bytes, targetWidth: (_cardW * devicePixelRatio * 1.5).round());
        img = (await codec.getNextFrame()).image;
      }
      client.close();
    } catch (_) {
      img = null;
    }
    _images[url] = img;
    return img;
  }

  static Future<Uint8List> _collect(HttpClientResponse res) async {
    final builder = BytesBuilder(copy: false);
    await for (final chunk in res) {
      builder.add(chunk);
    }
    return builder.takeBytes();
  }

  final _assets = <String, ui.Image?>{};

  Future<ui.Image?> _asset(String path) async {
    if (_assets.containsKey(path)) return _assets[path];
    ui.Image? img;
    try {
      final data = await rootBundle.load(path);
      final codec = await ui.instantiateImageCodec(data.buffer.asUint8List(), targetWidth: (96 * devicePixelRatio).round());
      img = (await codec.getNextFrame()).image;
    } catch (_) {
      img = null;
    }
    _assets[path] = img;
    return img;
  }

  Future<EventMarkerBitmap> _render(Event e, String label, ui.Image? image, ui.Image? art) async {
    final dpr = devicePixelRatio;

    // Label chip text: bold title + light time.
    var title = e.title.trim();
    if (title.length > _maxTitleChars) title = '${title.substring(0, _maxTitleChars - 1)}…';
    final titlePainter = TextPainter(
      text: TextSpan(
        text: title,
        style: const TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.w700, height: 1.1),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    final timePainter = TextPainter(
      text: TextSpan(
        text: label,
        style: const TextStyle(color: Color(0xFFB4BAC4), fontSize: 11, fontWeight: FontWeight.w500, height: 1.1),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();

    const between = 5.0;
    final chipW = titlePainter.width + between + timePainter.width + _chipPadH * 2;
    final chipH = math.max(titlePainter.height, timePainter.height) + _chipPadV * 2;

    final cardOuterW = _cardW + _border * 2;
    final cardOuterH = _cardH + _border * 2;
    final totalW = math.max(cardOuterW, chipW) + 4;
    final totalH = cardOuterH + _tailH + _gap + chipH + 2;
    final cx = totalW / 2;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder)..scale(dpr);

    // Card border + tail (same colour, drawn first so the photo sits on top).
    final borderPaint = Paint()..color = e.type.color;
    final outer = RRect.fromRectAndRadius(
      Rect.fromLTWH(cx - cardOuterW / 2, 1, cardOuterW, cardOuterH),
      const Radius.circular(_radius + _border),
    );
    canvas.drawRRect(outer, borderPaint);
    final tailTop = 1 + cardOuterH - 1;
    final tail = Path()
      ..moveTo(cx - _tailW / 2, tailTop)
      ..lineTo(cx + _tailW / 2, tailTop)
      ..lineTo(cx, tailTop + _tailH + 1)
      ..close();
    canvas.drawPath(tail, borderPaint);

    // Photo (cover-fit) or fallback tile.
    final cardRect = Rect.fromLTWH(cx - _cardW / 2, 1 + _border, _cardW, _cardH);
    final cardRRect = RRect.fromRectAndRadius(cardRect, const Radius.circular(_radius));
    canvas.save();
    canvas.clipRRect(cardRRect);
    if (image != null) {
      final iw = image.width.toDouble(), ih = image.height.toDouble();
      final scale = math.max(_cardW / iw, _cardH / ih);
      final sw = _cardW / scale, sh = _cardH / scale;
      final src = Rect.fromLTWH((iw - sw) / 2, (ih - sh) / 2, sw, sh);
      canvas.drawImageRect(image, src, cardRect, Paint()..filterQuality = FilterQuality.high);
    } else {
      canvas.drawRect(cardRect, Paint()..color = const Color(0xFF1C1F26));
      if (art != null) {
        const s = 40.0;
        final dst = Rect.fromCenter(center: cardRect.center, width: s, height: s);
        canvas.drawImageRect(art, Rect.fromLTWH(0, 0, art.width.toDouble(), art.height.toDouble()), dst, Paint()..filterQuality = FilterQuality.high);
      }
    }
    canvas.restore();

    // Label chip.
    final chipTop = 1 + cardOuterH + _tailH + _gap;
    final chipRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(cx - chipW / 2, chipTop, chipW, chipH),
      const Radius.circular(8),
    );
    canvas.drawRRect(chipRect, Paint()..color = const Color(0xF21C1F26));
    canvas.drawRRect(
      chipRect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = Colors.white.withValues(alpha: 0.10),
    );
    final textY = chipTop + _chipPadV;
    titlePainter.paint(canvas, Offset(cx - chipW / 2 + _chipPadH, textY));
    timePainter.paint(canvas, Offset(cx - chipW / 2 + _chipPadH + titlePainter.width + between, textY + 0.5));

    final picture = recorder.endRecording();
    final img = await picture.toImage((totalW * dpr).ceil(), (totalH * dpr).ceil());
    final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
    img.dispose();

    final descriptor = BitmapDescriptor.bytes(bytes!.buffer.asUint8List(), imagePixelRatio: dpr);
    final anchorY = (1 + cardOuterH + _tailH) / totalH;
    return EventMarkerBitmap(descriptor, Offset(0.5, anchorY));
  }

  void dispose() {
    for (final img in _images.values) {
      img?.dispose();
    }
    for (final img in _assets.values) {
      img?.dispose();
    }
    _assets.clear();
    _images.clear();
    _cache.clear();
  }
}
