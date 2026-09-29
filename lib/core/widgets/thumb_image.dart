import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/widgets.dart';

import '../utils/image_source.dart';
import '../utils/thumbnails.dart';

/// A photo in a small grid or strip tile: loads its ~480 px thumbnail, and the
/// full photo when there is none (older uploads, other hosts, local files).
/// Full-screen viewers and full-width images use the photo itself.
class ThumbImage extends StatelessWidget {
  const ThumbImage(this.src, {super.key, this.fit = BoxFit.cover, this.width, this.height, this.placeholder, this.error});

  /// Public URL of the full photo, or a local file path.
  final String src;
  final BoxFit fit;
  final double? width;
  final double? height;

  /// Shown until the first frame.
  final Widget? placeholder;

  /// Shown when the full photo fails too.
  final Widget? error;

  /// Photos found to have no thumbnail this session: go straight to the full one.
  static final _missing = <String>{};

  @override
  Widget build(BuildContext context) {
    final thumb = thumbUrl(src);
    if (thumb == src || _missing.contains(src)) return _full();
    return _image(CachedNetworkImageProvider(thumb), (_, _, _) {
      _missing.add(src);
      return _full();
    });
  }

  Widget _full() => _image(imageFor(src), (_, _, _) => error ?? const SizedBox.shrink());

  Widget _image(ImageProvider provider, ImageErrorWidgetBuilder onError) => Image(
        image: provider,
        fit: fit,
        width: width,
        height: height,
        frameBuilder: placeholder == null ? null : (_, child, frame, sync) => frame == null && !sync ? placeholder! : child,
        errorBuilder: onError,
      );
}
