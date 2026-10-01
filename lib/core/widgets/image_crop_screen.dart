import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:path_provider/path_provider.dart';

import '../theme/app_icons.dart';
import '../theme/app_theme.dart';

/// Full-screen crop: the photo fills a fixed frame of [aspect] (width /
/// height); drag to move it, pinch to zoom. "Use photo" renders the framed
/// part to a JPEG in the temp folder and returns it as an [XFile], so the
/// existing upload code takes it like any picked photo. [round] draws a
/// circle guide (club logos show as circles) but still crops a square.
/// Returns null when cancelled.
Future<XFile?> cropImage(
  BuildContext context,
  XFile source, {
  double aspect = 16 / 9,
  int outputWidth = 1600,
  bool round = false,
  String title = 'Move and scale',
}) async {
  final bytes = await source.readAsBytes();
  if (!context.mounted) return null;
  return Navigator.of(context, rootNavigator: true).push<XFile>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => ImageCropScreen(bytes: bytes, aspect: aspect, outputWidth: outputWidth, round: round, title: title),
    ),
  );
}

class ImageCropScreen extends StatefulWidget {
  const ImageCropScreen({super.key, required this.bytes, this.aspect = 16 / 9, this.outputWidth = 1600, this.round = false, this.title = 'Move and scale'});
  final Uint8List bytes;
  final double aspect;
  final int outputWidth;
  final bool round;
  final String title;

  @override
  State<ImageCropScreen> createState() => _ImageCropScreenState();
}

class _ImageCropScreenState extends State<ImageCropScreen> {
  ui.Image? _image;
  Size _frame = Size.zero;
  double _zoom = 1; // on top of the "cover" fit
  Offset _offset = Offset.zero; // image top-left inside the frame
  // gesture start
  double _zoom0 = 1;
  Offset _focal0 = Offset.zero;
  Offset _offset0 = Offset.zero;
  bool _busy = false;

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
      if (!mounted) {
        frame.image.dispose();
        return;
      }
      setState(() => _image = frame.image);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Couldn\'t open that photo. Try another.')));
        Navigator.of(context).pop();
      }
    }
  }

  double get _baseScale {
    final img = _image!;
    return math.max(_frame.width / img.width, _frame.height / img.height);
  }

  double get _scale => _baseScale * _zoom;

  /// Keeps the frame covered: no empty edge ever shows.
  Offset _clamp(Offset o) {
    final img = _image!;
    final w = img.width * _scale, h = img.height * _scale;
    return Offset(o.dx.clamp(_frame.width - w, 0.0), o.dy.clamp(_frame.height - h, 0.0));
  }

  void _layout(Size frame) {
    if (frame == _frame || _image == null) return;
    final first = _frame == Size.zero;
    _frame = frame;
    if (first) {
      // Centre the photo in the frame.
      final img = _image!;
      _offset = Offset((frame.width - img.width * _scale) / 2, (frame.height - img.height * _scale) / 2);
    }
    _offset = _clamp(_offset);
  }

  Future<void> _done() async {
    final img = _image;
    if (img == null || _frame == Size.zero) return;
    setState(() => _busy = true);
    try {
      final s = _scale;
      final src = Rect.fromLTWH(-_offset.dx / s, -_offset.dy / s, _frame.width / s, _frame.height / s);
      // Never upscale past the photo's own pixels.
      final outW = math.min(widget.outputWidth, src.width.round()).clamp(1, 1 << 14);
      final outH = (outW / widget.aspect).round().clamp(1, 1 << 14);
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      canvas.drawImageRect(img, src, Rect.fromLTWH(0, 0, outW.toDouble(), outH.toDouble()), Paint()..filterQuality = FilterQuality.high);
      final out = await recorder.endRecording().toImage(outW, outH);
      final png = await out.toByteData(format: ui.ImageByteFormat.png);
      out.dispose();
      if (png == null) throw StateError('encode');
      final pngBytes = png.buffer.asUint8List();
      Uint8List bytes;
      var ext = 'jpg';
      try {
        bytes = await FlutterImageCompress.compressWithList(pngBytes, minWidth: outW, minHeight: outH, quality: 88, format: CompressFormat.jpeg);
      } catch (e) {
        if (kDebugMode) debugPrint('Crop JPEG failed, keeping PNG: $e');
        bytes = pngBytes;
        ext = 'png';
      }
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/crop_${DateTime.now().microsecondsSinceEpoch}.$ext');
      await file.writeAsBytes(bytes, flush: true);
      if (mounted) Navigator.of(context).pop(XFile(file.path, mimeType: ext == 'jpg' ? 'image/jpeg' : 'image/png'));
    } catch (_) {
      if (mounted) {
        setState(() => _busy = false);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Couldn\'t crop that photo. Try another.')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final img = _image;
    return Scaffold(
      backgroundColor: AppColors.ink,
      appBar: AppBar(
        backgroundColor: AppColors.ink,
        foregroundColor: Colors.white,
        leading: IconButton(icon: const Icon(AppIcons.x, color: Colors.white), tooltip: 'Cancel', onPressed: _busy ? null : () => Navigator.of(context).pop()),
        title: Text(widget.title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 17)),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: img == null
                  ? const Center(child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : LayoutBuilder(
                      builder: (context, c) {
                        // The biggest frame of the right shape that fits with a margin.
                        var w = c.maxWidth - 32;
                        var h = w / widget.aspect;
                        if (h > c.maxHeight - 32) {
                          h = c.maxHeight - 32;
                          w = h * widget.aspect;
                        }
                        _layout(Size(w, h));
                        final s = _scale;
                        return Center(
                          child: GestureDetector(
                            onScaleStart: (d) {
                              _zoom0 = _zoom;
                              _focal0 = d.localFocalPoint;
                              _offset0 = _offset;
                            },
                            onScaleUpdate: (d) {
                              setState(() {
                                final before = _baseScale * _zoom0;
                                _zoom = (_zoom0 * d.scale).clamp(1.0, 5.0);
                                final after = _scale;
                                // Keep the photo point under the fingers where it was.
                                final p = (_focal0 - _offset0) / before;
                                _offset = _clamp(d.localFocalPoint - p * after);
                              });
                            },
                            child: SizedBox(
                              width: w,
                              height: h,
                              child: Stack(
                                clipBehavior: Clip.none,
                                children: [
                                  Positioned.fill(
                                    child: ClipRect(
                                      child: Stack(
                                        children: [
                                          Positioned(
                                            left: _offset.dx,
                                            top: _offset.dy,
                                            width: img.width * s,
                                            height: img.height * s,
                                            child: RawImage(image: img, fit: BoxFit.fill),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                  Positioned.fill(child: IgnorePointer(child: CustomPaint(painter: _GuidePainter(round: widget.round)))),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text('Drag to move, pinch to zoom', textAlign: TextAlign.center, style: TextStyle(color: Colors.white70, fontSize: 12.5, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 10),
                  FilledButton(
                    onPressed: img == null || _busy ? null : _done,
                    style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
                    child: _busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Text('Use photo'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Thirds grid and a white edge; a circle for logos.
class _GuidePainter extends CustomPainter {
  _GuidePainter({required this.round});
  final bool round;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final line = Paint()
      ..color = Colors.white.withValues(alpha: 0.35)
      ..strokeWidth = 1;
    for (var i = 1; i < 3; i++) {
      canvas.drawLine(Offset(size.width * i / 3, 0), Offset(size.width * i / 3, size.height), line);
      canvas.drawLine(Offset(0, size.height * i / 3), Offset(size.width, size.height * i / 3), line);
    }
    if (round) {
      // Dim the corners the circle leaves out.
      final path = Path()
        ..fillType = PathFillType.evenOdd
        ..addRect(rect)
        ..addOval(rect);
      canvas.drawPath(path, Paint()..color = Colors.black.withValues(alpha: 0.5));
      canvas.drawOval(rect.deflate(1), Paint()
        ..style = PaintingStyle.stroke
        ..color = Colors.white
        ..strokeWidth = 2);
    } else {
      canvas.drawRect(rect.deflate(1), Paint()
        ..style = PaintingStyle.stroke
        ..color = Colors.white
        ..strokeWidth = 2);
    }
  }

  @override
  bool shouldRepaint(_GuidePainter old) => old.round != round;
}
