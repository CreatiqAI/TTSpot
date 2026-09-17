import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_icons.dart';
import '../../../../core/widgets/glass.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../settings/application/settings_providers.dart';
import '../../application/map_providers.dart';
import 'car_marker.dart';
import 'map_glyphs.dart';

/// Small key on the left of the map: which shape means what on this layer,
/// listing only the kinds that are drawn right now (`present`). Open the
/// first time you see the map; folded to a "Key" pill after that.
class MapLegend extends ConsumerStatefulWidget {
  const MapLegend({super.key, required this.mode, required this.light, required this.present});
  final MapMode mode;
  final bool light;
  /// Glyph kinds currently on the map. Empty = nothing to explain, key hidden.
  final Set<LegendGlyph> present;

  @override
  ConsumerState<MapLegend> createState() => _MapLegendState();
}

class _MapLegendState extends ConsumerState<MapLegend> {
  static bool? _open; // remembered for the session

  void _markSeen() {
    if (!ref.read(settingsProvider).mapKeySeen) ref.read(settingsActionsProvider).patch({'map_key_seen': true}).ignore();
  }

  void _toggle() {
    setState(() => _open = !(_open ?? true));
    _markSeen();
  }

  @override
  void initState() {
    super.initState();
    _open ??= !ref.read(settingsProvider).mapKeySeen;
    // Seen it open once: next launch starts folded.
    if (_open!) {
      Future.delayed(const Duration(seconds: 8), () {
        if (mounted) _markSeen();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final open = _open ?? true;
    final p = MapPalette(light: widget.light, child: const SizedBox.shrink());
    final all = switch (widget.mode) {
      MapMode.now => const [
          _Item(LegendGlyph.flag, 'TT session'),
          _Item(LegendGlyph.balloon, 'Event'),
          _Item(LegendGlyph.officialEvent, 'Official club'),
          _Item(LegendGlyph.partnerEvent, 'Partner event'),
          _Item(LegendGlyph.moment, 'Moment'),
          _Item(LegendGlyph.partner, 'Partner shop'),
          _Item(LegendGlyph.me, 'You'),
          _Item(LegendGlyph.friend, 'Friend'),
          _Item(LegendGlyph.club, 'Club'),
          _Item(LegendGlyph.nearby, 'Nearby'),
        ],
      MapMode.upcoming => const [
          _Item(LegendGlyph.balloon, 'Event'),
          _Item(LegendGlyph.officialEvent, 'Official club'),
          _Item(LegendGlyph.partnerEvent, 'Partner event'),
          _Item(LegendGlyph.flag, 'TT session'),
          _Item(LegendGlyph.partner, 'Partner shop'),
          _Item(LegendGlyph.me, 'You'),
        ],
      MapMode.spots => const [
          _Item(LegendGlyph.topSpot, 'Top spot'),
          _Item(LegendGlyph.spot, 'Spot'),
          _Item(LegendGlyph.partner, 'Partner shop'),
          _Item(LegendGlyph.me, 'You'),
        ],
    };
    final rows = all.where((r) => widget.present.contains(r.glyph)).toList();
    if (rows.isEmpty) return const SizedBox.shrink();

    return GlassPanel(
      dark: !widget.light,
      radius: 12,
      blur: 14,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: _toggle,
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
                    Icon(open ? AppIcons.caretDown : AppIcons.caretRight, size: 11, color: p.text2),
                    const SizedBox(width: 4),
                    Text('KEY', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 1, color: p.text2)),
                  ],
                ),
                if (open) ...[
                  const SizedBox(height: 4),
                  Text('Zoom in for shapes', style: TextStyle(fontSize: 9.5, color: p.text2)),
                  for (final r in rows)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(width: 22, height: 22, child: CustomPaint(painter: LegendGlyphPainter(r.glyph))),
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

enum LegendGlyph { balloon, officialEvent, partnerEvent, flag, spot, topSpot, partner, moment, me, friend, club, nearby }

class _Item {
  const _Item(this.glyph, this.label);
  final LegendGlyph glyph;
  final String label;
}

class LegendGlyphPainter extends CustomPainter {
  const LegendGlyphPainter(this.glyph);
  final LegendGlyph glyph;

  @override
  void paint(Canvas c, Size s) {
    final centre = Offset(s.width / 2, s.height / 2);
    switch (glyph) {
      case LegendGlyph.balloon:
        paintBalloon(c, Offset(centre.dx - 13 * 0.6, 1), scale: 0.6);
      case LegendGlyph.officialEvent:
        paintBalloon(c, Offset(centre.dx - 13 * 0.6, 1), scale: 0.6, color: kGold, glyph: AppIcons.crown);
      case LegendGlyph.partnerEvent:
        paintBalloon(c, Offset(centre.dx - 13 * 0.6, 1), scale: 0.6, color: kInk, glyph: AppIcons.storefront);
      case LegendGlyph.flag:
        paintFlag(c, Offset(centre.dx - 12 * 0.6, 0), scale: 0.6);
      case LegendGlyph.spot:
        paintSpotBadge(c, Offset(centre.dx - 11 * 0.75, centre.dy - 11 * 0.75), scale: 0.75);
      case LegendGlyph.topSpot:
        paintSpotBadge(c, Offset(centre.dx - 11 * 0.75, centre.dy - 11 * 0.75), scale: 0.75, recommended: true);
      case LegendGlyph.partner:
        final box = Rect.fromCenter(center: centre.translate(0, -1), width: 15, height: 15);
        c.drawRRect(RRect.fromRectAndRadius(box.inflate(1.5), const Radius.circular(5)), Paint()..color = Colors.white);
        c.drawRRect(RRect.fromRectAndRadius(box, const Radius.circular(4)), Paint()..color = const Color(0xFF101010));
        c.drawPath(Path()..moveTo(centre.dx - 3, box.bottom + 1)..lineTo(centre.dx + 3, box.bottom + 1)..lineTo(centre.dx, box.bottom + 4.5)..close(), Paint()..color = Colors.white);
        c.drawCircle(Offset(box.right - 2, box.bottom - 2), 4, Paint()..color = Colors.white);
        c.drawCircle(Offset(box.right - 2, box.bottom - 2), 3, Paint()..color = const Color(0xFFE00008));
      case LegendGlyph.moment:
        c.save();
        c.translate(centre.dx, centre.dy);
        c.rotate(-0.14);
        const frame = Rect.fromLTWH(-7.5, -8, 15, 17);
        c.drawRRect(RRect.fromRectAndRadius(frame, const Radius.circular(2)), Paint()..color = Colors.white);
        c.drawRRect(RRect.fromRectAndRadius(frame, const Radius.circular(2)), Paint()..style = PaintingStyle.stroke..strokeWidth = 0.8..color = const Color(0xFFCFD3DA));
        c.drawRect(const Rect.fromLTWH(-6, -6.5, 12, 12), Paint()..color = const Color(0xFF9AA0A6));
        c.restore();
      case LegendGlyph.me:
        paintDot(c, centre, r: 4.5, color: kRelationMe);
      case LegendGlyph.friend:
        paintDot(c, centre, r: 4.5, color: kRelationFriend);
      case LegendGlyph.club:
        paintDot(c, centre, r: 4.5, color: kRelationClub);
      case LegendGlyph.nearby:
        paintDot(c, centre, r: 4.5, color: kRelationStranger);
    }
  }

  @override
  bool shouldRepaint(LegendGlyphPainter old) => old.glyph != glyph;
}
