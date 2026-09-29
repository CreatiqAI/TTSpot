import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_icons.dart';
import '../../../../core/widgets/glass.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../settings/application/settings_providers.dart';
import '../../application/map_providers.dart';
import 'car_marker.dart';
import 'map_glyphs.dart';

/// The map key: a round button on the right edge (same look as the
/// visibility and locate buttons above it). Tapping it opens "What's on the
/// map", which explains every kind of pin in plain words, the ones drawn
/// right now ([present]) first. A small red dot on the button until the key
/// has been opened once.
class MapLegend extends ConsumerWidget {
  const MapLegend({super.key, required this.mode, required this.light, required this.present});
  final MapMode mode;
  /// White button on the day map.
  final bool light;
  /// Pin kinds currently on the map.
  final Set<LegendGlyph> present;

  static const double size = 46;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final seen = ref.watch(settingsProvider.select((s) => s.mapKeySeen));
    void open() {
      if (!seen) ref.read(settingsActionsProvider).patch({'map_key_seen': true}).ignore();
      showMapKeySheet(context, mode: mode, present: present);
    }

    return Tooltip(
      message: 'What\'s on the map',
      child: PressScale(
        child: GlassPanel(
          circle: true,
          dark: !light,
          child: Material(
            color: Colors.transparent,
            shape: const CircleBorder(),
            child: InkWell(
              onTap: open,
              customBorder: const CircleBorder(),
              child: SizedBox(
                width: size,
                height: size,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Icon(AppIcons.info, color: light ? AppColors.ink : Colors.white, size: 22),
                    if (!seen)
                      Positioned(
                        right: 10,
                        top: 10,
                        child: Container(
                          width: 9,
                          height: 9,
                          decoration: BoxDecoration(color: AppColors.brand, shape: BoxShape.circle, border: Border.all(color: light ? Colors.white : AppColors.mapSurface, width: 1.5)),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// "What's on the map": each kind of pin as it really looks, with one plain
/// line on what it means. Kinds drawn right now come first, grouped; the
/// rest follow, greyed, under "Not on the map right now".
Future<void> showMapKeySheet(BuildContext context, {required MapMode mode, required Set<LegendGlyph> present}) {
  return showModalBottomSheet<void>(
    useRootNavigator: true, // above the shell tab bar
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (_) => _MapKeySheet(mode: mode, present: present),
  );
}

enum _Section {
  people('You and friends'),
  events('Events'),
  spots('Spots'),
  partners('Partners');

  const _Section(this.title);
  final String title;
}

/// One row of the key: the glyph, its name, what it looks like and means,
/// and which layers draw it.
class _KeyItem {
  const _KeyItem(this.glyph, this.section, this.name, this.meaning, this.layers);
  final LegendGlyph glyph;
  final _Section section;
  final String name;
  final String meaning;
  final Set<MapMode> layers;
}

const _all = {MapMode.now, MapMode.upcoming, MapMode.spots};
const _events = {MapMode.now, MapMode.upcoming};
const _nowOnly = {MapMode.now};

List<_KeyItem> _items(MapMode mode) => [
      const _KeyItem(LegendGlyph.me, _Section.people, 'You', 'Red dot with a soft glow. Zoom in and it becomes your car.', _all),
      const _KeyItem(LegendGlyph.friend, _Section.people, 'Friend', 'Blue dot, or the colour you gave them. Up close, their car and name.', _nowOnly),
      const _KeyItem(LegendGlyph.club, _Section.people, 'Clubmate', 'Purple dot. Someone from one of your clubs.', _nowOnly),
      const _KeyItem(LegendGlyph.nearby, _Section.people, 'Nearby driver', 'Grey dot. A car person close by who shares their spot.', _nowOnly),
      const _KeyItem(LegendGlyph.moment, _Section.people, 'Moment', 'Photo card. A photo posted here in the last 24 hours.', _nowOnly),
      _KeyItem(LegendGlyph.flag, _Section.events, 'TT session', mode == MapMode.now ? 'Red flag. A TT session happening now. Tap to join.' : 'Red flag. A TT session, a quick meet-up.', _events),
      _KeyItem(LegendGlyph.balloon, _Section.events, 'Event', mode == MapMode.now ? 'Red pin. A meet, convoy or track day on right now.' : 'Red pin. A meet, convoy or track day coming up.', _events),
      const _KeyItem(LegendGlyph.officialEvent, _Section.events, 'Official club event', 'Gold pin with a crown. Run by an official club.', _events),
      const _KeyItem(LegendGlyph.partnerEvent, _Section.events, 'Partner event', 'Black pin with a shop. Hosted by a partner shop.', _events),
      const _KeyItem(LegendGlyph.savedSpot, _Section.spots, 'Saved spot', 'Any badge with a black bookmark. A spot you saved. It stays on your map on every layer, wherever you are.', _all),
      const _KeyItem(LegendGlyph.topSpot, _Section.spots, 'Top spot', 'Any badge with a red star. One of the best places around, like a top car café.', _all),
      const _KeyItem(LegendGlyph.cafe, _Section.spots, 'Car café', 'Orange cup. A café where car people meet.', _all),
      const _KeyItem(LegendGlyph.mamak, _Section.spots, 'Mamak', 'Teal glass. A mamak, the late-night hangout.', _all),
      const _KeyItem(LegendGlyph.carpark, _Section.spots, 'Carpark', 'Blue P. A carpark where meets happen.', _all),
      const _KeyItem(LegendGlyph.route, _Section.spots, 'Route', 'Green road. A good road for a drive.', _all),
      const _KeyItem(LegendGlyph.circuit, _Section.spots, 'Circuit', 'Chequered flag. A race track.', _all),
      const _KeyItem(LegendGlyph.mall, _Section.spots, 'Mall', 'Pink bag. A mall with a car scene.', _all),
      const _KeyItem(LegendGlyph.workshop, _Section.spots, 'Workshop', 'Grey spanner. A workshop or car service.', _all),
      const _KeyItem(LegendGlyph.spot, _Section.spots, 'Other spot', 'Grey pin. Any other place car people go.', _all),
      const _KeyItem(LegendGlyph.partner, _Section.partners, 'Partner shop', 'Shop logo with a red tag. A TT Spot partner. Tap for its page.', _all),
    ];

String _layerNames(Set<MapMode> layers) => MapMode.values.where(layers.contains).map((m) => m.label).join(' and ');

class _MapKeySheet extends StatelessWidget {
  const _MapKeySheet({required this.mode, required this.present});
  final MapMode mode;
  final Set<LegendGlyph> present;

  @override
  Widget build(BuildContext context) {
    final items = _items(mode);
    final shown = items.where((i) => present.contains(i.glyph)).toList();
    final rest = items.where((i) => !present.contains(i.glyph)).toList();

    List<Widget> grouped(List<_KeyItem> list, {required bool dim}) => [
          for (final s in _Section.values)
            if (list.any((i) => i.section == s)) ...[
              _SectionLabel(s.title, dim: dim),
              for (final i in list.where((i) => i.section == s))
                _KeyRow(
                  item: i,
                  dim: dim,
                  // Greyed rows that this layer never draws say where to find them.
                  note: dim && !i.layers.contains(mode) ? 'On ${_layerNames(i.layers)}' : null,
                ),
            ],
        ];

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.85),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('What\'s on the map', style: TextStyle(fontFamily: AppFonts.display, fontSize: 26, fontWeight: FontWeight.w700, height: 1)),
              const SizedBox(height: 4),
              Text(
                shown.isEmpty ? 'Nothing on this part of the map yet. Here is what could show up.' : 'On the ${mode.label} layer right now.',
                style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
              ),
              const SizedBox(height: 6),
              ...grouped(shown, dim: false),
              if (rest.isNotEmpty) ...[
                const SizedBox(height: 14),
                Divider(height: 1, color: AppColors.divider),
                const SizedBox(height: 12),
                Text('Not on the map right now', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.textSecondary)),
                ...grouped(rest, dim: true),
              ],
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: AppColors.surfaceGray, borderRadius: BorderRadius.circular(12)),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(AppIcons.magnifyingGlass, size: 18, color: AppColors.textSecondary),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Zoomed far out, every pin shrinks to a small dot in the same colour. Zoom in to see the full shapes, names and cars. '
                        'Spots show on every layer; the Spots layer shows them bigger, with names and check-ins.',
                        style: TextStyle(fontSize: 12.5, height: 1.35, color: AppColors.textSecondary),
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

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text, {required this.dim});
  final String text;
  final bool dim;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 14, bottom: 4),
        child: Text(
          text.toUpperCase(),
          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1, color: dim ? AppColors.textMuted : AppColors.textSecondary),
        ),
      );
}

class _KeyRow extends StatelessWidget {
  const _KeyRow({required this.item, required this.dim, this.note});
  final _KeyItem item;
  final bool dim;
  final String? note;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: dim ? 0.5 : 1,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          children: [
            // The glyph as the map draws it, on a map-grey tile so the white
            // outlines read the way they do over the streets.
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(color: AppColors.surfaceGray, borderRadius: BorderRadius.circular(10)),
              alignment: Alignment.center,
              child: Transform.scale(
                scale: 1.35,
                child: SizedBox(width: 22, height: 22, child: CustomPaint(painter: LegendGlyphPainter(item.glyph))),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(child: Text(item.name, style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700, color: AppColors.textPrimary))),
                      if (note != null) ...[
                        const SizedBox(width: 8),
                        Text(note!, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: AppColors.textMuted)),
                      ],
                    ],
                  ),
                  const SizedBox(height: 1),
                  Text(item.meaning, style: TextStyle(fontSize: 12.5, height: 1.3, color: AppColors.textSecondary)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

enum LegendGlyph { balloon, officialEvent, partnerEvent, flag, spot, topSpot, savedSpot, cafe, mamak, carpark, route, circuit, mall, workshop, partner, moment, me, friend, club, nearby }

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
        paintSpotBadge(c, Offset(centre.dx - 12 * 0.75, centre.dy - 12 * 0.75), scale: 0.75);
      case LegendGlyph.topSpot:
        paintSpotBadge(c, Offset(centre.dx - 12 * 0.75, centre.dy - 12 * 0.75), scale: 0.75, recommended: true, kind: SpotKind.cafe);
      case LegendGlyph.savedSpot:
        paintSpotBadge(c, Offset(centre.dx - 12 * 0.75, centre.dy - 12 * 0.75), scale: 0.75, saved: true, kind: SpotKind.mamak);
      case LegendGlyph.cafe:
        paintSpotBadge(c, Offset(centre.dx - 12 * 0.75, centre.dy - 12 * 0.75), scale: 0.75, kind: SpotKind.cafe);
      case LegendGlyph.mamak:
        paintSpotBadge(c, Offset(centre.dx - 12 * 0.75, centre.dy - 12 * 0.75), scale: 0.75, kind: SpotKind.mamak);
      case LegendGlyph.carpark:
        paintSpotBadge(c, Offset(centre.dx - 12 * 0.75, centre.dy - 12 * 0.75), scale: 0.75, kind: SpotKind.carpark);
      case LegendGlyph.route:
        paintSpotBadge(c, Offset(centre.dx - 12 * 0.75, centre.dy - 12 * 0.75), scale: 0.75, kind: SpotKind.route);
      case LegendGlyph.circuit:
        paintSpotBadge(c, Offset(centre.dx - 12 * 0.75, centre.dy - 12 * 0.75), scale: 0.75, kind: SpotKind.circuit);
      case LegendGlyph.mall:
        paintSpotBadge(c, Offset(centre.dx - 12 * 0.75, centre.dy - 12 * 0.75), scale: 0.75, kind: SpotKind.mall);
      case LegendGlyph.workshop:
        paintSpotBadge(c, Offset(centre.dx - 12 * 0.75, centre.dy - 12 * 0.75), scale: 0.75, kind: SpotKind.workshop);
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
