import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_icons.dart';

/// Full-screen photos on black: pinch or double-tap to zoom, swipe between
/// them, X or back to close.
Future<void> showPhotoViewer(BuildContext context, List<String> urls, {int initial = 0}) {
  return Navigator.of(context, rootNavigator: true).push(
    PageRouteBuilder<void>(
      pageBuilder: (_, _, _) => PhotoViewer(urls: urls, initial: initial),
      transitionsBuilder: (_, anim, _, child) => FadeTransition(opacity: anim, child: child),
    ),
  );
}

class PhotoViewer extends StatefulWidget {
  const PhotoViewer({super.key, required this.urls, this.initial = 0});
  final List<String> urls;
  final int initial;

  @override
  State<PhotoViewer> createState() => _PhotoViewerState();
}

class _PhotoViewerState extends State<PhotoViewer> {
  late final _pages = PageController(initialPage: widget.initial);
  late int _page = widget.initial;
  // While a photo is zoomed, a sideways drag pans it instead of turning the page.
  bool _zoomed = false;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final many = widget.urls.length > 1;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          children: [
            PageView.builder(
              controller: _pages,
              physics: _zoomed ? const NeverScrollableScrollPhysics() : null,
              itemCount: widget.urls.length,
              onPageChanged: (i) => setState(() => _page = i),
              itemBuilder: (_, i) => _ZoomablePhoto(
                url: widget.urls[i],
                onZoom: (z) {
                  if (z != _zoomed) setState(() => _zoomed = z);
                },
              ),
            ),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Row(
                  children: [
                    // Dark backings so both stay readable over a white photo.
                    DecoratedBox(
                      decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                      child: IconButton(
                        tooltip: 'Close',
                        icon: const Icon(AppIcons.x, color: Colors.white, size: 22),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ),
                    const Spacer(),
                    if (many)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(999)),
                        child: Text('${_page + 1}/${widget.urls.length}', style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
                      ),
                    const SizedBox(width: 8),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ZoomablePhoto extends StatefulWidget {
  const _ZoomablePhoto({required this.url, required this.onZoom});
  final String url;
  final ValueChanged<bool> onZoom;

  @override
  State<_ZoomablePhoto> createState() => _ZoomablePhotoState();
}

class _ZoomablePhotoState extends State<_ZoomablePhoto> {
  final _zoom = TransformationController();
  Offset _tapAt = Offset.zero;
  bool _zoomed = false;

  @override
  void initState() {
    super.initState();
    _zoom.addListener(() {
      final z = _zoom.value.getMaxScaleOnAxis() > 1.01;
      if (z == _zoomed) return;
      _zoomed = z;
      widget.onZoom(z);
    });
  }

  @override
  void dispose() {
    _zoom.dispose();
    super.dispose();
  }

  /// Double-tap: zoom in 2.5x on that spot, or back out.
  void _toggleZoom() {
    if (_zoomed) {
      _zoom.value = Matrix4.identity();
      return;
    }
    const s = 2.5;
    _zoom.value = Matrix4.identity()
      ..translateByDouble(-_tapAt.dx * (s - 1), -_tapAt.dy * (s - 1), 0, 1)
      ..scaleByDouble(s, s, 1, 1);
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
        onDoubleTapDown: (d) => _tapAt = d.localPosition,
        onDoubleTap: _toggleZoom,
        child: InteractiveViewer(
          transformationController: _zoom,
          maxScale: 5,
          child: SizedBox.expand(
            child: Image(
              image: CachedNetworkImageProvider(widget.url),
              fit: BoxFit.contain,
              loadingBuilder: (_, child, prog) => prog == null ? child : const Center(child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)),
              errorBuilder: (_, _, _) => const Center(child: Icon(AppIcons.imageBroken, color: Colors.white54, size: 40)),
            ),
          ),
        ),
      );
}
