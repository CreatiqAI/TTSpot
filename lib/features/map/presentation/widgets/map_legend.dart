import 'package:flutter/material.dart';

import '../../../../core/theme/app_icons.dart';
import '../../../../core/widgets/glass.dart';
import '../../../../core/theme/app_theme.dart';
import '../../application/map_providers.dart';
import 'car_marker.dart';
import 'map_glyphs.dart';

/// Small key on the left of the map: which shape means what on this layer.
/// Tap the header to fold it down to a single "Key" pill.
class MapLegend extends StatefulWidget {
  const MapLegend({super.key, required this.mode, required this.light});
  final MapMode mode;
  final bool light;

  @override
  State<MapLegend> createState() => _MapLegendState();
}

class _MapLegendState extends State<MapLegend> {
  static bool _open = true; // remembered for the session

  @override
  Widget build(BuildContext context) {
    final p = MapPalette(light: widget.light, child: const SizedBox.shrink());
    final rows = switch (widget.mode) {
      MapMode.now => const [
          _Item(_Glyph.flag, 'TT session'),
          _Item(_Glyph.balloon, 'Event'),
          _Item(_Glyph.officialEvent, 'Official club'),
          _Item(_Glyph.partnerEvent, 'Partner event'),
          _Item(_Glyph.moment, 'Moment'),
          _Item(_Glyph.partner, 'Partner shop'),
          _Item(_Glyph.me, 'You'),
          _Item(_Glyph.friend, 'Friend'),
          _Item(_Glyph.club, 'Club'),
          _Item(_Glyph.nearby, 'Nearby'),
        ],
      MapMode.upcoming => const [
          _Item(_Glyph.balloon, 'Event'),
          _Item(_Glyph.officialEvent, 'Official club'),
          _Item(_Glyph.partnerEvent, 'Partner event'),
          _Item(_Glyph.flag, 'TT session'),
          _Item(_Glyph.partner, 'Partner shop'),
          _Item(_Glyph.me, 'You'),
        ],
      MapMode.spots => const [
          _Item(_Glyph.topSpot, 'Top spot'),
          _Item(_Glyph.spot, 'Spot'),
          _Item(_Glyph.partner, 'Partner shop'),
          _Item(_Glyph.me, 'You'),
        ],
    };

    return GlassPanel(
      dark: !widget.light,
      radius: 12,
      blur: 14,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => setState(() => _open = !_open),
        child: AnimatedSize(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          alignment: Alignment.topLeft,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 6, 10, 6),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(_open ? AppIcons.caretDown : AppIcons.caretRight, size: 11, color: p.text2),
                    const SizedBox(width: 4),
                    Text('KEY', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 1, color: p.text2)),
                  ],
                ),
                if (_open) ...[
                  const SizedBox(height: 4),
                  Text('Zoom in for shapes', style: TextStyle(fontSize: 9.5, color: p.text2)),
                  for (final r in rows)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(width: 22, height: 22, child: CustomPaint(painter: _GlyphPainter(r.glyph))),
                          const SizedBox(width: 6),
                          Text(r.label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: p.text)),
                        ],
                      ),
                    ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

enum _Glyph { balloon, officialEvent, partnerEvent, flag, spot, topSpot, partner, moment, me, friend, club, nearby }

class _Item {
  const _Item(this.glyph, this.label);
  final _Glyph glyph;
  final String label;
}

class _GlyphPainter extends CustomPainter {
  const _GlyphPainter(this.glyph);
  final _Glyph glyph;

  @override
  void paint(Canvas c, Size s) {
    final centre = Offset(s.width / 2, s.height / 2);
    switch (glyph) {
      case _Glyph.balloon:
        paintBalloon(c, Offset(centre.dx - 13 * 0.6, 1), scale: 0.6);
      case _Glyph.officialEvent:
        paintBalloon(c, Offset(centre.dx - 13 * 0.6, 1), scale: 0.6, color: kGold, glyph: AppIcons.crown);
      case _Glyph.partnerEvent:
        paintBalloon(c, Offset(centre.dx - 13 * 0.6, 1), scale: 0.6, color: kInk, glyph: AppIcons.storefront);
      case _Glyph.flag:
        paintFlag(c, Offset(centre.dx - 12 * 0.6, 0), scale: 0.6);
      case _Glyph.spot:
        paintSpotBadge(c, Offset(centre.dx - 11 * 0.75, centre.dy - 11 * 0.75), scale: 0.75);
      case _Glyph.topSpot:
        paintSpotBadge(c, Offset(centre.dx - 11 * 0.75, centre.dy - 11 * 0.75), scale: 0.75, recommended: true);
      case _Glyph.partner:
        final box = Rect.fromCenter(center: centre.translate(0, -1), width: 15, height: 15);
        c.drawRRect(RRect.fromRectAndRadius(box.inflate(1.5), const Radius.circular(5)), Paint()..color = Colors.white);
        c.drawRRect(RRect.fromRectAndRadius(box, const Radius.circular(4)), Paint()..color = const Color(0xFF101010));
        c.drawPath(Path()..moveTo(centre.dx - 3, box.bottom + 1)..lineTo(centre.dx + 3, box.bottom + 1)..lineTo(centre.dx, box.bottom + 4.5)..close(), Paint()..color = Colors.white);
        c.drawCircle(Offset(box.right - 2, box.bottom - 2), 4, Paint()..color = Colors.white);
        c.drawCircle(Offset(box.right - 2, box.bottom - 2), 3, Paint()..color = const Color(0xFFE00008));
      case _Glyph.moment:
        c.save();
        c.translate(centre.dx, centre.dy);
        c.rotate(-0.14);
        const frame = Rect.fromLTWH(-7.5, -8, 15, 17);
        c.drawRRect(RRect.fromRectAndRadius(frame, const Radius.circular(2)), Paint()..color = Colors.white);
        c.drawRRect(RRect.fromRectAndRadius(frame, const Radius.circular(2)), Paint()..style = PaintingStyle.stroke..strokeWidth = 0.8..color = const Color(0xFFCFD3DA));
        c.drawRect(const Rect.fromLTWH(-6, -6.5, 12, 12), Paint()..color = const Color(0xFF9AA0A6));
        c.restore();
      case _Glyph.me:
        paintDot(c, centre, r: 4.5, color: kRelationMe);
      case _Glyph.friend:
        paintDot(c, centre, r: 4.5, color: kRelationFriend);
      case _Glyph.club:
        paintDot(c, centre, r: 4.5, color: kRelationClub);
      case _Glyph.nearby:
        paintDot(c, centre, r: 4.5, color: kRelationStranger);
    }
  }

  @override
  bool shouldRepaint(_GlyphPainter old) => old.glyph != glyph;
}
