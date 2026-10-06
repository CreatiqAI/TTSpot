import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/geo/latlng.dart';
import '../../../../core/theme/app_icons.dart';
import '../../../../core/utils/geo.dart';
import '../../../../core/widgets/glass.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../settings/application/settings_providers.dart';
import '../../application/map_filters.dart' show PinTier;
import 'car_marker.dart';
import 'event_pins.dart';
import 'map_glyphs.dart';

/// The map key: a small glass panel on the left of the map that lists the
/// kinds of pin in view right now ([present]), each drawn exactly as on the
/// map with its name; group headings only when there are three or more.
/// Open the first time you see the map; folded to a "KEY" pill after that.
/// The KEY header folds or unfolds it; the choice holds for the session.
///
/// Every row is a button ([onRow]): the map flies to the nearest pin of
/// that kind and opens it as a tap on the pin would; the same row again
/// steps to the next nearest ([cycle] shows where it is, "2/5").
class MapLegend extends ConsumerStatefulWidget {
  const MapLegend({super.key, required this.light, required this.present, this.tagged = const [], this.onRow, this.cycle});
  /// White glass on the day map.
  final bool light;
  /// Pin kinds currently on the map. Empty = nothing to explain, key hidden.
  final Set<LegendGlyph> present;
  /// Friends in view that I gave a colour, one row per colour: the colour,
  /// its key in kTagColors and their names ("Ali, Ben").
  final List<({Color color, String tag, String names})> tagged;
  /// A row was tapped: [keyRowOf] for a kind, [keyRowOfTag] for a colour.
  final ValueChanged<String>? onRow;
  /// The row whose pins taps are stepping through: the [index]th of [total].
  final ({String row, int index, int total})? cycle;

  @override
  ConsumerState<MapLegend> createState() => _MapLegendState();
}

/// The id [MapLegend.onRow] hands back for a kind of pin...
String keyRowOf(LegendGlyph g) => 'g:${g.name}';

/// ...and for a friend colour row.
String keyRowOfTag(String tag) => 't:$tag';

/// One pin a key row can take you to: where it is and what a tap on its pin
/// does (null for my own pin).
typedef KeyTarget = (LatLng, VoidCallback?);

/// Taps on a key row stepping through its pins: [targets] are the pins of
/// that kind that were in view on the first tap, nearest first; [index] is
/// the one shown now.
class KeyCycle {
  const KeyCycle({required this.row, required this.targets, required this.index, required this.at});
  final String row;
  final List<KeyTarget> targets;
  final int index;
  /// When the row was last tapped.
  final DateTime at;

  KeyTarget get current => targets[index];

  /// How long a row's list holds between taps before it is gathered afresh.
  static const window = Duration(minutes: 2);

  /// A tap on [row] at [now]. The same row again within [window]: the next
  /// pin, round and round. Otherwise the pins from [inView] (asked only
  /// then), sorted nearest to [origin] first. Null when there are none.
  static KeyCycle? tap(KeyCycle? current, String row, DateTime now, {required List<KeyTarget> Function() inView, LatLng? origin}) {
    if (current != null && current.row == row && now.difference(current.at) < window && current.targets.isNotEmpty) {
      return KeyCycle(row: row, targets: current.targets, index: (current.index + 1) % current.targets.length, at: now);
    }
    final found = [...inView()];
    if (found.isEmpty) return null;
    if (origin != null) {
      final LatLng from = origin; // a plain non-null local for the comparator
      found.sort((a, b) => distanceKm(from, a.$1).compareTo(distanceKm(from, b.$1)));
    }
    return KeyCycle(row: row, targets: found, index: 0, at: now);
  }
}

/// The kind of pin behind a row id, or null for a colour row.
LegendGlyph? glyphOfKeyRow(String row) {
  if (!row.startsWith('g:')) return null;
  final name = row.substring(2);
  for (final g in LegendGlyph.values) {
    if (g.name == name) return g;
  }
  return null;
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
    if (rows.isEmpty && widget.tagged.isEmpty) return const SizedBox.shrink();
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

  /// "2/5" on the row being stepped through, else null.
  String? _step(String row) {
    final c = widget.cycle;
    if (c == null || c.row != row || c.total < 2) return null;
    return '${c.index + 1}/${c.total}';
  }

  Widget _panel(bool open, List<_KeyItem> rows, MapPalette p, Size screen) {
    final sections = [
      for (final s in _Section.values)
        if (rows.any((i) => i.section == s) || (s == _Section.people && widget.tagged.isNotEmpty)) s,
    ];
    final onRow = widget.onRow;
    return ConstrainedBox(
      // Compact: under half the width. The map screen also stops it above the bottom chrome.
      constraints: BoxConstraints(maxWidth: screen.width * 0.45, maxHeight: screen.height * 0.6),
      child: GlassPanel(
        dark: !widget.light,
        radius: 14,
        child: Material(
          type: MaterialType.transparency,
          child: AnimatedSize(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            alignment: Alignment.topLeft,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // The header alone folds and unfolds the key.
                InkWell(
                  key: const ValueKey('map-key-header'),
                  onTap: _toggle,
                  borderRadius: BorderRadius.circular(14),
                  highlightColor: p.text.withValues(alpha: 0.08),
                  splashColor: p.text.withValues(alpha: 0.06),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 36),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(10, 0, 12, 0),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(open ? AppIcons.caretDown : AppIcons.caretRight, size: 13, color: p.text2),
                          const SizedBox(width: 5),
                          Text('KEY', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, letterSpacing: 1.2, color: p.text)),
                        ],
                      ),
                    ),
                  ),
                ),
                if (open)
                  // A long list (a busy Now layer) scrolls inside the panel.
                  Flexible(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: IntrinsicWidth(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            for (final s in sections) ...[
                              // Headings only once there is enough to sort.
                              if (sections.length > 2)
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(10, 4, 12, 0),
                                  child: Text(s.title.toUpperCase(), style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w700, letterSpacing: 0.6, color: p.text2.withValues(alpha: 0.8))),
                                ),
                              for (final i in rows.where((i) => i.section == s))
                                _KeyRow(
                                  key: ValueKey('map-key-${i.glyph.name}'),
                                  label: i.label,
                                  palette: p,
                                  step: _step(keyRowOf(i.glyph)),
                                  onTap: onRow == null ? null : () => onRow(keyRowOf(i.glyph)),
                                  leading: CustomPaint(painter: LegendGlyphPainter(i.glyph, night: !p.light)),
                                ),
                              if (s == _Section.people)
                                for (final t in widget.tagged)
                                  _KeyRow(
                                    key: ValueKey('map-key-tag-${t.tag}'),
                                    label: t.names,
                                    palette: p,
                                    step: _step(keyRowOfTag(t.tag)),
                                    onTap: onRow == null ? null : () => onRow(keyRowOfTag(t.tag)),
                                    leading: CustomPaint(painter: _DotPainter(t.color)),
                                  ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
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
  _KeyItem(LegendGlyph.seen, _Section.people, 'Seen earlier'),
  _KeyItem(LegendGlyph.moment, _Section.people, 'Moment'),
  _KeyItem(LegendGlyph.eventMajor, _Section.events, 'Official event'),
  _KeyItem(LegendGlyph.eventPartner, _Section.events, 'Partner event'),
  _KeyItem(LegendGlyph.eventMinor, _Section.events, 'Club meet · TT'),
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
  _KeyItem(LegendGlyph.cluster, _Section.groups, 'Group · zoom in'),
];

class _DotPainter extends CustomPainter {
  const _DotPainter(this.color);
  final Color color;

  @override
  void paint(Canvas c, Size s) => paintDot(c, Offset(s.width / 2, s.height / 2), r: 4.5, color: color);

  @override
  bool shouldRepaint(_DotPainter old) => old.color != color;
}

/// One row of the key: the glyph exactly as the map draws it (18 px wide),
/// a short name, and a caret (or "2/5" while taps step through its pins).
/// A 44 px tall button that darkens while pressed.
class _KeyRow extends StatelessWidget {
  const _KeyRow({super.key, required this.label, required this.palette, required this.leading, this.onTap, this.step});
  final String label;
  final MapPalette palette;
  final Widget leading;
  final VoidCallback? onTap;
  final String? step;

  @override
  Widget build(BuildContext context) {
    final p = palette;
    final active = step != null;
    return InkWell(
      onTap: onTap,
      highlightColor: p.text.withValues(alpha: 0.10),
      splashColor: p.text.withValues(alpha: 0.08),
      child: Container(
        constraints: const BoxConstraints(minHeight: 44),
        padding: const EdgeInsets.fromLTRB(10, 2, 10, 2),
        color: active ? p.text.withValues(alpha: 0.07) : null,
        child: Row(
          children: [
            SizedBox(width: 18, height: 23, child: leading),
            const SizedBox(width: 7),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, height: 1.1, color: p.text),
              ),
            ),
            const SizedBox(width: 6),
            if (step case final s?)
              Text(s, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: p.text2, fontFeatures: const [FontFeature.tabularFigures()]))
            else if (onTap != null)
              Icon(AppIcons.caretRight, size: 11, color: p.text2.withValues(alpha: 0.75)),
          ],
        ),
      ),
    );
  }
}

/// [friend], [club] and [nearby] are people on the map now (under a minute
/// old); [seen] is anyone whose pin is older (muted, "5 min ago").
enum LegendGlyph { eventMajor, eventPartner, eventMinor, spot, topSpot, savedSpot, cafe, mamak, carpark, route, circuit, mall, workshop, partner, cluster, moment, me, friend, club, nearby, seen }

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
  const LegendGlyphPainter(this.glyph, {this.night = false});
  final LegendGlyph glyph;
  /// On the night map's dark key: my halo is painted for a dark ground.
  final bool night;

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
    void event(PinTier t, double side, IconData glyph) {
      final h = side + eventPinTail(side);
      paintEventPin(c, Offset(centre.dx - side / 2, (s.height - h) / 2), side: side, ring: tierRingColor(t), glyph: glyph, badge: false);
    }
    switch (glyph) {
      // The map's picture pins, smaller as the tier goes down (no photo in
      // the key: the tier's colour with the event mark inside).
      case LegendGlyph.eventMajor:
        event(PinTier.major, s.width, AppIcons.crownFill);
      case LegendGlyph.eventPartner:
        event(PinTier.partner, s.width * 0.84, AppIcons.storefrontFill);
      case LegendGlyph.eventMinor:
        event(PinTier.minor, s.width * 0.7, AppIcons.flagPennantFill);
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
        paintHalo(c, centre, 9, night: night);
        paintDot(c, centre, r: 4.5, color: kRelationMe);
      case LegendGlyph.friend:
        paintDot(c, centre, r: 4.5, color: kRelationFriend);
      case LegendGlyph.club:
        paintDot(c, centre, r: 4.5, color: kRelationClub);
      case LegendGlyph.nearby:
        paintDot(c, centre, r: 4.5, color: kRelationStranger);
      case LegendGlyph.seen:
        // The map's last-seen dot: a friend's blue washed out, a size smaller.
        paintDot(c, centre, r: 3.6, color: seenColor(kRelationFriend), ring: kSeenRing);
    }
  }

  @override
  bool shouldRepaint(LegendGlyphPainter old) => old.glyph != glyph || old.night != night;
}
