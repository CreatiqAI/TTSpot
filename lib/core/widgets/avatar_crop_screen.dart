import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';

import '../theme/app_theme.dart';

/// Turns the cropped square into upload bytes. The default makes a JPEG.
typedef AvatarEncoder = Future<Uint8List> Function(ui.Image square);

/// Profile photo crop: the picked photo under a round mask; pinch to zoom,
/// drag to move, double-tap to start over. It zooms out until the whole
/// picture fits inside the circle; any space around it is filled with the
/// picture's own background colour (its edge colour), on screen and in the
/// saved file. "Use photo" returns a square JPEG ([AvatarCrop.outputSide] px)
/// of exactly the circle's bounding square, ready for the avatar upload.
/// Null when cancelled. [dark] is the onboarding look; otherwise it follows
/// the app theme.
Future<Uint8List?> cropAvatar(BuildContext context, Uint8List bytes, {bool dark = false}) {
  return Navigator.of(context, rootNavigator: true).push<Uint8List>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => AvatarCropScreen(bytes: bytes, dark: dark),
    ),
  );
}

/// The crop geometry, kept apart from the widget so it can be tested.
/// Positions are in screen pixels with the circle's bounding square at
/// (0, 0) and [d] wide; `offset` is where the photo's top-left corner sits.
abstract final class AvatarCrop {
  static const outputSide = 512;

  /// How far past "just covers the circle" a pinch may zoom in.
  static const maxZoom = 5.0;

  /// Wider or taller than this (and on a plain background) opens fitted
  /// inside the circle instead of covering it: a logo, not a photo.
  static const fitAspect = 1.2;

  /// Screen pixels per photo pixel when the photo just covers the circle's
  /// square (the short side fills it). Zoom 1.
  static double coverScale(Size image, double d) => math.max(d / image.width, d / image.height);

  /// The smallest zoom: the whole picture inside the circle (its diagonal
  /// is the circle's diameter), so not even a corner is cut.
  static double minScale(Size image, double d) => d / math.sqrt(image.width * image.width + image.height * image.height);

  /// Where the crop opens. Cover for photos and anything close to square;
  /// fitted inside the circle for a wide or tall picture on a plain
  /// background (a logo, a banner), so nothing of it is cut.
  static double initialScale(Size image, double d, {required bool plainEdges}) {
    final aspect = image.width / image.height;
    final nearSquare = aspect <= fitAspect && aspect >= 1 / fitAspect;
    return plainEdges && !nearSquare ? minScale(image, d) : coverScale(image, d);
  }

  /// The photo centred on the circle at [scale].
  static Offset centred(Size image, double scale, double d) => Offset((d - image.width * scale) / 2, (d - image.height * scale) / 2);

  /// Bigger than the circle's square on an axis: no edge of the photo inside
  /// it. Smaller: the photo stays inside it.
  static Offset clamp(Offset offset, Size image, double scale, double d) {
    final gx = d - image.width * scale, gy = d - image.height * scale;
    return Offset(offset.dx.clamp(math.min(0.0, gx), math.max(0.0, gx)), offset.dy.clamp(math.min(0.0, gy), math.max(0.0, gy)));
  }

  /// The part of the photo (in photo pixels) under the circle's square.
  static Rect sourceRect(Offset offset, double scale, double d, Size image) => Rect.fromLTRB(
        math.max(0.0, -offset.dx / scale),
        math.max(0.0, -offset.dy / scale),
        math.min(image.width, (d - offset.dx) / scale),
        math.min(image.height, (d - offset.dy) / scale),
      );

  /// The circle's square as a [side] x [side] picture (dart:ui only):
  /// [fill] first, then the photo where it sits on screen.
  static Future<ui.Image> render(ui.Image image, {required Offset offset, required double scale, required double d, required Color fill, int side = outputSide}) {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final k = side / d;
    canvas.drawRect(Rect.fromLTWH(0, 0, side.toDouble(), side.toDouble()), Paint()..color = fill);
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      Rect.fromLTWH(offset.dx * k, offset.dy * k, image.width * scale * k, image.height * scale * k),
      Paint()..filterQuality = FilterQuality.high,
    );
    return recorder.endRecording().toImage(side, side);
  }

  /// The picture's background colour from its outer [ring] px (RGBA bytes,
  /// [w] x [h]): the most common edge colour, averaged within its bucket.
  /// See-through pixels count as on white. [plain] when most of the edge
  /// is that one colour (a logo or graphic rather than a photo).
  static ({Color fill, bool plain}) edgeColour(Uint8List rgba, int w, int h, {int ring = 2}) {
    final buckets = <int, List<int>>{}; // key -> [count, r, g, b]
    final px = <int>[];
    void add(int x, int y) {
      final i = (y * w + x) * 4;
      final a = rgba[i + 3] / 255;
      final r = (rgba[i] * a + 255 * (1 - a)).round();
      final g = (rgba[i + 1] * a + 255 * (1 - a)).round();
      final b = (rgba[i + 2] * a + 255 * (1 - a)).round();
      px.add((r << 16) | (g << 8) | b);
      final s = buckets.putIfAbsent(((r >> 4) << 8) | ((g >> 4) << 4) | (b >> 4), () => [0, 0, 0, 0]);
      s[0]++;
      s[1] += r;
      s[2] += g;
      s[3] += b;
    }

    final t = math.min(ring, math.min(w, h));
    for (var y = 0; y < h; y++) {
      if (y < t || y >= h - t) {
        for (var x = 0; x < w; x++) {
          add(x, y);
        }
      } else {
        for (var x = 0; x < t; x++) {
          add(x, y);
          if (w - 1 - x >= t) add(w - 1 - x, y);
        }
      }
    }
    if (px.isEmpty) return (fill: Colors.white, plain: false);
    final top = buckets.values.reduce((a, b) => b[0] > a[0] ? b : a);
    final r = (top[1] / top[0]).round(), g = (top[2] / top[0]).round(), b = (top[3] / top[0]).round();
    // Plain: nearly all the edge within a small step of that colour (JPEG noise, anti-aliasing).
    var near = 0;
    for (final c in px) {
      if (((c >> 16) - r).abs() <= 24 && (((c >> 8) & 0xFF) - g).abs() <= 24 && ((c & 0xFF) - b).abs() <= 24) near++;
    }
    return (fill: Color.fromARGB(255, r, g, b), plain: near >= px.length * 0.85);
  }

  /// [edgeColour] of a small decode of [bytes] (fast for any photo size).
  static Future<({Color fill, bool plain})> sampleEdges(Uint8List bytes) async {
    final codec = await ui.instantiateImageCodec(bytes, targetWidth: 160);
    final img = (await codec.getNextFrame()).image;
    codec.dispose();
    try {
      final data = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (data == null) return (fill: Colors.white, plain: false);
      return edgeColour(data.buffer.asUint8List(), img.width, img.height);
    } finally {
      img.dispose();
    }
  }

  /// JPEG through flutter_image_compress; PNG if that isn't available.
  static Future<Uint8List> encodeJpeg(ui.Image square) async {
    final png = await square.toByteData(format: ui.ImageByteFormat.png);
    if (png == null) throw StateError('encode');
    final pngBytes = png.buffer.asUint8List();
    try {
      return await FlutterImageCompress.compressWithList(pngBytes, minWidth: square.width, minHeight: square.height, quality: 88, format: CompressFormat.jpeg);
    } catch (e) {
      if (kDebugMode) debugPrint('Avatar JPEG failed, keeping PNG: $e');
      return pngBytes;
    }
  }
}

class AvatarCropScreen extends StatefulWidget {
  const AvatarCropScreen({super.key, required this.bytes, this.dark = false, this.encoder});
  final Uint8List bytes;
  final bool dark;

  /// Stands in for the JPEG step in tests.
  final AvatarEncoder? encoder;

  @override
  State<AvatarCropScreen> createState() => AvatarCropScreenState();
}

@visibleForTesting
class AvatarCropScreenState extends State<AvatarCropScreen> {
  ui.Image? _image;
  double _d = 0; // circle diameter
  double _scale = 1; // screen px per photo px
  Offset _offset = Offset.zero; // photo top-left, relative to the circle's square
  double _scale0 = 1;
  Offset _focal0 = Offset.zero;
  Offset _offset0 = Offset.zero;
  bool _busy = false;
  // The picture's own background colour, behind it in the circle and the file.
  Color _fill = Colors.white;
  bool _plainEdges = false;

  Size get _imageSize => Size(_image!.width.toDouble(), _image!.height.toDouble());
  double get _minScale => AvatarCrop.minScale(_imageSize, _d);
  double get _maxScale => AvatarCrop.coverScale(_imageSize, _d) * AvatarCrop.maxZoom;

  /// The photo pixels the circle covers now (tests read it).
  @visibleForTesting
  Rect? get sourceRect => _image == null || _d == 0 ? null : AvatarCrop.sourceRect(_offset, _scale, _d, _imageSize);

  /// 1 = the photo just covers the circle; below 1 the fill shows around it.
  @visibleForTesting
  double get zoom => _image == null || _d == 0 ? 1 : _scale / AvatarCrop.coverScale(_imageSize, _d);

  @visibleForTesting
  Color get fill => _fill;

  @override
  void initState() {
    super.initState();
    _decode();
  }

  @override
  void dispose() {
    _image?.dispose();
    super.dispose();
  }

  Future<void> _decode() async {
    try {
      final codec = await ui.instantiateImageCodec(widget.bytes);
      final frame = await codec.getNextFrame();
      codec.dispose();
      ({Color fill, bool plain})? edges;
      try {
        edges = await AvatarCrop.sampleEdges(widget.bytes);
      } catch (_) {} // white, and opens covering the circle
      if (!mounted) {
        frame.image.dispose();
        return;
      }
      setState(() {
        _image = frame.image;
        if (edges != null) {
          _fill = edges.fill;
          _plainEdges = edges.plain;
        }
      });
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(const SnackBar(content: Text('Couldn\'t open that photo. Try another.')));
      Navigator.of(context).pop();
    }
  }

  void _reset() {
    _scale = AvatarCrop.initialScale(_imageSize, _d, plainEdges: _plainEdges);
    _offset = AvatarCrop.centred(_imageSize, _scale, _d);
  }

  /// The circle's size for this area; the first time (or after a resize)
  /// the photo starts centred, covering it (or fitted inside, for a logo).
  void _layout(double d) {
    if (_image == null || d <= 0 || d == _d) return;
    _d = d;
    _reset();
  }

  Future<void> _use() async {
    final img = _image;
    if (img == null || _d == 0 || _busy) return;
    setState(() => _busy = true);
    try {
      final square = await AvatarCrop.render(img, offset: _offset, scale: _scale, d: _d, fill: _fill);
      final Uint8List bytes;
      try {
        bytes = await (widget.encoder ?? AvatarCrop.encodeJpeg)(square);
      } finally {
        square.dispose();
      }
      if (mounted) Navigator.of(context).pop(bytes);
    } catch (_) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(const SnackBar(content: Text('Couldn\'t crop that photo. Try another.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final dark = widget.dark;
    final bg = dark ? Colors.black : AppColors.bg;
    final fg = dark ? Colors.white : AppColors.textPrimary;
    final fg2 = dark ? Colors.white.withValues(alpha: 0.6) : AppColors.textSecondary;
    final img = _image;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: dark ? SystemUiOverlayStyle.light : AppTheme.systemOverlay,
      child: Scaffold(
        backgroundColor: bg,
        body: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
                child: Text(
                  'Move and scale',
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: fg),
                ),
              ),
              Expanded(
                child: img == null
                    ? Center(child: CircularProgressIndicator(strokeWidth: 2, color: fg))
                    : LayoutBuilder(
                        builder: (context, c) {
                          final d = math.max(0.0, math.min(c.maxWidth, c.maxHeight) - 48);
                          _layout(d);
                          final origin = Offset((c.maxWidth - _d) / 2, (c.maxHeight - _d) / 2);
                          final circle = origin & Size.square(_d);
                          return GestureDetector(
                            key: const ValueKey('avatar-crop-area'),
                            behavior: HitTestBehavior.opaque,
                            onDoubleTap: _busy ? null : () => setState(_reset),
                            onScaleStart: (g) {
                              _scale0 = _scale;
                              _focal0 = g.localFocalPoint - origin;
                              _offset0 = _offset;
                            },
                            onScaleUpdate: _busy
                                ? null
                                : (g) => setState(() {
                                    _scale = (_scale0 * g.scale).clamp(_minScale, _maxScale);
                                    // Keep the photo point under the fingers where it was.
                                    final p = (_focal0 - _offset0) / _scale0;
                                    _offset = AvatarCrop.clamp(g.localFocalPoint - origin - p * _scale, _imageSize, _scale, _d);
                                  }),
                            child: ClipRect(
                              child: Stack(
                                children: [
                                  // The picture's background colour, round like the avatar.
                                  Positioned.fromRect(
                                    rect: circle,
                                    child: DecoratedBox(
                                      key: const ValueKey('avatar-crop-fill'),
                                      decoration: BoxDecoration(color: _fill, shape: BoxShape.circle),
                                    ),
                                  ),
                                  Positioned(
                                    left: origin.dx + _offset.dx,
                                    top: origin.dy + _offset.dy,
                                    width: img.width * _scale,
                                    height: img.height * _scale,
                                    child: RawImage(image: img, fit: BoxFit.fill, filterQuality: FilterQuality.medium),
                                  ),
                                  Positioned.fill(
                                    child: IgnorePointer(
                                      child: CustomPaint(
                                        painter: _MaskPainter(
                                          circle: circle,
                                          dim: dark ? Colors.black.withValues(alpha: 0.62) : bg.withValues(alpha: 0.78),
                                          ring: dark ? Colors.white : AppColors.textPrimary,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
                child: Text(
                  'Pinch to zoom. Drag to move.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, color: fg2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 20, 16),
                child: Row(
                  children: [
                    // Two equal halves: fits any width and text size.
                    Expanded(
                      child: TextButton(
                        onPressed: _busy ? null : () => Navigator.of(context).pop(),
                        style: TextButton.styleFrom(minimumSize: const Size(0, 48), foregroundColor: fg),
                        child: const Text('Cancel', maxLines: 1, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton(
                        onPressed: img == null || _busy ? null : _use,
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(0, 48),
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          backgroundColor: dark ? Colors.white : AppColors.brand,
                          foregroundColor: dark ? AppColors.ink : Colors.white,
                          shape: const StadiumBorder(),
                        ),
                        child: _busy
                            ? SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2, color: dark ? AppColors.ink : Colors.white))
                            : const Text('Use photo', maxLines: 1, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
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
}

/// Dims everything outside the circle and draws a thin ring on it.
class _MaskPainter extends CustomPainter {
  _MaskPainter({required this.circle, required this.dim, required this.ring});
  final Rect circle;
  final Color dim;
  final Color ring;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Offset.zero & size)
      ..addOval(circle);
    canvas.drawPath(path, Paint()..color = dim);
    canvas.drawOval(
      circle.deflate(0.75),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = ring.withValues(alpha: 0.9),
    );
  }

  @override
  bool shouldRepaint(_MaskPainter old) => old.circle != circle || old.dim != dim || old.ring != ring;
}
