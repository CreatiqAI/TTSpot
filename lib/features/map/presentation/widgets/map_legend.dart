import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_icons.dart';
import '../../../../core/widgets/glass.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../settings/application/settings_providers.dart';
import 'car_marker.dart';
import 'map_glyphs.dart';

/// The map key: a small glass panel on the left of the map that lists the
/// kinds of pin in view right now ([present]), each drawn exactly as on the
/// map with its name; group headings only when there are three or more. Open the first time you see the map; folded to a "KEY"
/// pill after that. Tap it to fold or unfold; the choice holds for the session.
class MapLegend extends ConsumerStatefulWidget {
  const MapLegend({super.key, required this.light, required this.present});
  /// White glass on the day map.
  final bool light;
  /// Pin kinds currently on the map. Empty = nothing to explain, key hidden.
  final Set<LegendGlyph> present;

  @override
  ConsumerState<MapLegend> createState() => _MapLegendState();
}

class _MapLegendState extends ConsumerState<MapLegend> {
  static bool? _open; // remembered for the session
  Timer? _seenTimer;

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
  }

  @override
  void dispose() {
    _seenTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final rows = _items.where((i) => widget.present.contains(i.glyph)).toList();
    if (rows.isEmpty) return const SizedBox.shrink();
    final open = _open ?? true;
    // Seen it open for a while: next launch starts folded.
    if (open) {
      _seenTimer ??= Timer(const Duration(seconds: 8), () {
        if (mounted) _markSeen();
      });
    }
    final p = MapPalette(light: widget.light, child: const SizedBox.shrink());
    final screen = MediaQuery.sizeOf(context);

    // Not even room for the pill (a short landscape screen under banners): hide.
    return LayoutBuilder(
      builder: (context, room) => room.maxHeight < 40 ? const SizedBox.shrink() : _panel(open, rows, p, screen),
    );
  }

  Widget _panel(bool open, List<_KeyItem> rows, MapPalette p, Size screen) {
    final sections = [for (final s in _Section.values) if (rows.any((i) => i.section == s)) s];
    return ConstrainedBox(
      // Compact: under half the width. The map screen also stops it above the bottom chrome.
      constraints: BoxConstraints(maxWidth: screen.width * 0.45, maxHeight: screen.height * 0.6),
      child: GlassPanel(
        dark: !widget.light,
        radius: 14,
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: _toggle,
            borderRadius: BorderRadius.circular(14),
            child: AnimatedSize(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOut,
              alignment: Alignment.topLeft,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: EdgeInsets.fromLTRB(10, 7, 12, open ? 3 : 7),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(open ? AppIcons.caretDown : AppIcons.caretRight, size: 13, color: p.text2),
                        const SizedBox(width: 5),
                        Text('KEY', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, letterSpacing: 1.2, color: p.text)),
                      ],
                    ),
                  ),
                  if (open)
                    // A long list (a busy Now layer) scrolls inside the panel.
                    Flexible(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(10, 0, 12, 8),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            for (final s in sections) ...[
                              // Headings only once there is enough to sort.
                              if (sections.length > 2)
                                Padding(
                                  padding: const EdgeInsets.only(top: 5, bottom: 1),
                                  child: Text(s.title.toUpperCase(), style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w700, letterSpacing: 0.6, color: p.text2.withValues(alpha: 0.8))),
                                ),
                              for (final i in rows.where((i) => i.section == s)) _KeyRow(item: i, palette: p),
                            ],
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

enum _Section {
  people('You and friends'),
  events('Events'),
  spots('Spots'),
  partners('Partners'),
  groups('Grouped');

  const _Section(this.title);
  final String title;
}

/// One row of the key: the glyph and a short name.
class _KeyItem {
  const _KeyItem(this.glyph, this.section, this.label);
  final LegendGlyph glyph;
  final _Section section;
  final String label;
}

const _items = [
  _KeyItem(LegendGlyph.me, _Section.people, 'You'),
  _KeyItem(LegendGlyph.friend, _Section.people, 'Friend'),
  _KeyItem(LegendGlyph.club, _Section.people, 'Clubmate'),
  _KeyItem(LegendGlyph.nearby, _Section.people, 'Nearby driver'),
  _KeyItem(LegendGlyph.moment, _Section.people, 'Moment'),
  _KeyItem(LegendGlyph.flag, _Section.events, 'TT session'),
  _KeyItem(LegendGlyph.balloon, _Section.events, 'Event'),
  _KeyItem(LegendGlyph.officialEvent, _Section.events, 'Official club'),
  _KeyItem(LegendGlyph.partnerEvent, _Section.events, 'Partner event'),
  _KeyItem(LegendGlyph.savedSpot, _Section.spots, 'Saved spot'),
  _KeyItem(LegendGlyph.topSpot, _Section.spots, 'Top spot'),
  _KeyItem(LegendGlyph.cafe, _Section.spots, 'Car café'),
  _KeyItem(LegendGlyph.mamak, _Section.spots, 'Mamak'),
  _KeyItem(LegendGlyph.carpark, _Section.spots, 'Carpark'),
  _KeyItem(LegendGlyph.route, _Section.spots, 'Route'),
  _KeyItem(LegendGlyph.circuit, _Section.spots, 'Circuit'),
  _KeyItem(LegendGlyph.mall, _Section.spots, 'Mall'),
  _KeyItem(LegendGlyph.workshop, _Section.spots, 'Workshop'),
  _KeyItem(LegendGlyph.spot, _Section.spots, 'Other spot'),
  _KeyItem(LegendGlyph.partner, _Section.partners, 'Partner shop'),
  _KeyItem(LegendGlyph.cluster, _Section.groups, 'Group · tap to zoom'),
];

class _KeyRow extends StatelessWidget {
  const _KeyRow({required this.item, required this.palette});
  final _KeyItem item;
  final MapPalette palette;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // The glyph exactly as the map draws it, 18 px wide.
          SizedBox(width: 18, height: 23, child: CustomPaint(painter: LegendGlyphPainter(item.glyph))),
          const SizedBox(width: 7),
          Flexible(
            child: Text(
              item.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, height: 1.1, color: palette.text),
            ),
          ),
        ],
      ),
    );
  }
}

enum LegendGlyph { balloon, officialEvent, partnerEvent, flag, spot, topSpot, savedSpot, cafe, mamak, carpark, route, circuit, mall, workshop, partner, cluster, moment, me, friend, club, nearby }

/// The key row for a place of this kind.
LegendGlyph legendGlyphForSpot(SpotKind k) => switch (k) {
      SpotKind.cafe => LegendGlyph.cafe,
      SpotKind.mamak => LegendGlyph.mamak,
      SpotKind.carpark => LegendGlyph.carpark,
      SpotKind.route => LegendGlyph.route,
      SpotKind.circuit => LegendGlyph.circuit,
      SpotKind.mall => LegendGlyph.mall,
      SpotKind.workshop => LegendGlyph.workshop,
      SpotKind.other => LegendGlyph.spot,
    };

class LegendGlyphPainter extends CustomPainter {
  const LegendGlyphPainter(this.glyph);
  final LegendGlyph glyph;

  @override
  void paint(Canvas c, Size s) {
    final centre = Offset(s.width / 2, s.height / 2);
    // The map's teardrops, [s.height] tall and centred: the same painter, so
    // the key always matches the pins.
    void drop({Color color = kEventRed, Color outline = Colors.white, SpotKind? kind, IconData? glyph}) {
      final k = s.height / teardropSize.height;
      paintTeardrop(c, Offset(centre.dx - teardropTip.dx * k, 0), scale: k, color: color, outline: outline, kind: kind, glyph: glyph);
    }
    void spot(SpotKind k) => drop(color: spotKindColor(k), kind: k);
    switch (glyph) {
      case LegendGlyph.balloon:
        drop(glyph: AppIcons.flagFill);
      case LegendGlyph.officialEvent:
        drop(color: kGold, glyph: AppIcons.crownFill);
      case LegendGlyph.partnerEvent:
        drop(color: kInk, glyph: AppIcons.storefrontFill);
      case LegendGlyph.flag:
        drop(glyph: AppIcons.flagPennantFill);
      case LegendGlyph.spot:
        spot(SpotKind.other);
      // Top and saved are badges on a spot's pin, whatever its kind: the key
      // shows the badge itself.
      case LegendGlyph.topSpot:
        paintStarBadge(c, centre, r: 6);
      case LegendGlyph.savedSpot:
        paintSavedBadge(c, centre, r: 6);
      case LegendGlyph.cluster:
        paintCluster(c, centre, count: 3, scale: s.width / ((clusterRadius + 2.5) * 2));
      case LegendGlyph.cafe:
        spot(SpotKind.cafe);
      case LegendGlyph.mamak:
        spot(SpotKind.mamak);
      case LegendGlyph.carpark:
        spot(SpotKind.carpark);
      case LegendGlyph.route:
        spot(SpotKind.route);
      case LegendGlyph.circuit:
        spot(SpotKind.circuit);
      case LegendGlyph.mall:
        spot(SpotKind.mall);
      case LegendGlyph.workshop:
        spot(SpotKind.workshop);
      case LegendGlyph.partner:
        drop(color: kInk, outline: kEventRed, glyph: AppIcons.storefrontFill);
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
        paintHalo(c, centre, 9);
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
