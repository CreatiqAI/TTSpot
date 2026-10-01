import 'package:flutter/material.dart';

import '../../../../core/theme/app_icons.dart';
import 'chat_media.dart' show fmtMs;

/// "This is a video" on a post tile: a play mark and, when known, the length
/// ("0:42"). [compact]: the mark only, for small square tiles.
class VideoBadge extends StatelessWidget {
  const VideoBadge({super.key, this.ms, this.compact = false});
  final int? ms;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final showTime = !compact && ms != null && ms! > 0;
    return Semantics(
      label: showTime ? 'Video, ${fmtMs(ms!)}' : 'Video',
      excludeSemantics: true,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: showTime ? 7 : 5, vertical: showTime ? 3 : 5),
        decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.55), borderRadius: BorderRadius.circular(999)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(AppIcons.playFill, size: 11, color: Colors.white),
            if (showTime) ...[
              const SizedBox(width: 3),
              Text(
                fmtMs(ms!),
                maxLines: 1,
                softWrap: false,
                style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700, fontFeatures: [FontFeature.tabularFigures()]),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
