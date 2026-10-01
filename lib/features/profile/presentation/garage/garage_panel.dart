import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../../../../core/theme/app_icons.dart';
import '../../../../core/theme/app_theme.dart';
import '../../domain/car.dart';
import '../../domain/car_documents.dart';
import '../../domain/car_mod.dart';
import '../car_page/car_page_model.dart' show formatRinggit, formatShortDay;
import '../car_page/car_papers_tab.dart' show DocChipData, docChips;
import 'collector_card.dart';

// The garage's slim panel: a dark glass sheet over the bottom of the bay.
// Collapsed it names the car and holds the main buttons; pulled up it shows
// the numbers, the papers and the latest mods. Always the night palette, so
// it reads the same in light and dark mode.

/// The panel's own night colours (on top of [GarageColors]).
abstract final class PanelColors {
  static const fill = Color(0xD9101216);
  static const edge = Color(0x1FFFFFFF);
  static const card = Color(0x14FFFFFF);
  static const divider = Color(0x1AFFFFFF);
  static const muted = Color(0xFF6E7480);
  static const danger = Color(0xFFFF8A8A);
  static const dangerFill = Color(0x33E00008);
}

/// What the panel knows about the car in the bay. Null while it loads.
class GarageFacts {
  const GarageFacts({this.mods, this.meets, this.posts, this.papers, this.papersLoaded = false});

  /// Newest first. Prices only come back for the owner.
  final List<CarMod>? mods;
  final int? meets;
  final int? posts;

  /// The owner's papers; null when none are saved (see [papersLoaded]).
  final CarDocuments? papers;
  final bool papersLoaded;

  double? get spent => mods?.fold<double>(0, (s, m) => s + (m.cost ?? 0));
}

/// RM 850 · RM 12.5k · RM 1.2m: fits a quarter of a phone width.
String compactMoney(double v) {
  String trim(double x) => x.toStringAsFixed(x >= 100 || x == x.roundToDouble() ? 0 : 1);
  if (v >= 1000000) return '${trim(v / 1000000)}m';
  if (v >= 10000) return '${trim(v / 1000)}k';
  final s = v.toStringAsFixed(0);
  return s.replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');
}

/// The line under the name: the spec line, else body style and colour.
String carSubline(Car c) {
  final spec = c.specLine;
  if (spec != null) return spec;
  String cap(String s) => s.length <= 3 ? s.toUpperCase() : s[0].toUpperCase() + s.substring(1);
  final parts = [
    if ((c.bodyStyle ?? '').trim().isNotEmpty) cap(c.bodyStyle!.trim()),
    if ((c.color ?? '').trim().isNotEmpty) cap(c.color!.trim()),
  ];
  return parts.isEmpty ? 'No specs yet' : parts.join(' · ');
}

TextStyle _kicker(double k) => TextStyle(fontSize: 11.5 * k, fontWeight: FontWeight.w700, letterSpacing: 2.2, color: GarageColors.textSoft, height: 1.25);
TextStyle _title(double k) => TextStyle(fontFamily: AppFonts.display, fontSize: 34 * k, fontWeight: FontWeight.w800, height: 1.05, color: GarageColors.text);
TextStyle _soft(double k) => TextStyle(fontSize: 13.5 * k, height: 1.3, color: GarageColors.textSoft);

/// The sheet itself: frosted night glass with a hairline top edge.
class PanelGlass extends StatelessWidget {
  const PanelGlass({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    const radius = BorderRadius.vertical(top: Radius.circular(26));
    return DecoratedBox(
      decoration: const BoxDecoration(
        borderRadius: radius,
        boxShadow: [BoxShadow(color: Color(0x66000000), blurRadius: 24, offset: Offset(0, -4))],
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
          child: DecoratedBox(
            decoration: const BoxDecoration(
              color: PanelColors.fill,
              borderRadius: radius,
              border: Border(top: BorderSide(color: PanelColors.edge)),
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0x14FFFFFF), Color(0x00FFFFFF)],
                stops: [0, 0.35],
              ),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

/// The grab handle (tap it to open or close the panel) and the bay dots.
class PanelHandle extends StatelessWidget {
  const PanelHandle({super.key, required this.count, required this.index, required this.onDot, required this.expanded, this.onToggle});
  final int count;
  final int index;
  final ValueChanged<int> onDot;
  final bool expanded;
  final VoidCallback? onToggle;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Semantics(
          button: onToggle != null,
          label: onToggle == null ? null : (expanded ? 'Show less' : 'Show more'),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onToggle,
            child: SizedBox(
              width: 120,
              height: 18,
              child: Center(
                child: Container(
                  width: 38,
                  height: 4,
                  decoration: BoxDecoration(color: Colors.white.withValues(alpha: onToggle == null ? 0.14 : 0.32), borderRadius: BorderRadius.circular(2)),
                ),
              ),
            ),
          ),
        ),
        if (count >= 2) GarageDots(count: count, index: index, onTap: onDot) else const SizedBox(height: 4),
      ],
    );
  }
}

/// One dot per bay, the current one a red bar.
class GarageDots extends StatelessWidget {
  const GarageDots({super.key, required this.count, required this.index, required this.onTap});
  final int count;
  final int index;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < count; i++)
          Semantics(
            button: true,
            label: 'Bay ${i + 1}',
            selected: i == index,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => onTap(i),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(3, 4, 3, 8),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeOut,
                  width: i == index ? 22 : 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: i == index ? AppColors.brand : Colors.white.withValues(alpha: 0.28),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Collapsed: make and year, today's car, the name, one line of specs and
/// the main buttons (Open car, then today's car / Edit and More for mine).
class GarageCarPeek extends StatelessWidget {
  const GarageCarPeek({
    super.key,
    required this.car,
    required this.mine,
    required this.today,
    required this.k,
    required this.onOpen,
    this.onMakeToday,
    this.onEdit,
    this.onMore,
  });

  final Car car;
  final bool mine;
  final bool today;
  final double k;
  final VoidCallback onOpen;
  final VoidCallback? onMakeToday;
  final VoidCallback? onEdit;
  final VoidCallback? onMore;

  @override
  Widget build(BuildContext context) {
    final c = car;
    final make = [c.make.toUpperCase(), if (c.year != null) '${c.year}'].join(' · ');
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          _KickerRow(text: make, k: k, tag: today ? (mine ? 'TODAY\'S CAR' : 'DAILY') : null),
          const SizedBox(height: 2),
          Text(c.model, maxLines: 1, overflow: TextOverflow.ellipsis, style: _title(k)),
          const SizedBox(height: 2),
          Text(carSubline(c), maxLines: 1, overflow: TextOverflow.ellipsis, style: _soft(k)),
          SizedBox(height: 12 * k),
          if (mine)
            Row(
              children: [
                Expanded(child: PanelButton(label: 'Open car', onTap: onOpen, k: k)),
                const SizedBox(width: 8),
                Expanded(
                  child: today
                      ? PanelButton(label: 'Edit', icon: AppIcons.pencilSimple, onTap: onEdit ?? () {}, k: k, filled: false)
                      : PanelButton(label: 'Make today\'s car', onTap: onMakeToday ?? () {}, k: k, filled: false),
                ),
                const SizedBox(width: 8),
                PanelIconButton(icon: AppIcons.dotsThree, tooltip: 'More', onTap: onMore ?? () {}, size: 46 * k),
              ],
            )
          else
            PanelButton(label: 'Open car', onTap: onOpen, k: k),
        ],
      ),
    );
  }
}

/// Pulled up: Mods / Spent (mine) / Meets / Posts, the papers (mine), the
/// latest mods, then Open car again.
class GarageCarMore extends StatelessWidget {
  const GarageCarMore({super.key, required this.car, required this.mine, required this.facts, required this.k, required this.onOpen, this.onPapers});

  final Car car;
  final bool mine;
  final GarageFacts facts;
  final double k;
  final VoidCallback onOpen;
  final VoidCallback? onPapers;

  @override
  Widget build(BuildContext context) {
    final f = facts;
    final spent = f.spent;
    final mods = f.mods;
    final chips = f.papers == null ? const <DocChipData>[] : docChips(f.papers!);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: EdgeInsets.symmetric(vertical: 12 * k),
            decoration: BoxDecoration(color: PanelColors.card, borderRadius: BorderRadius.circular(16), border: Border.all(color: PanelColors.divider)),
            child: Row(
              children: [
                _Stat(value: mods?.length.toString(), label: 'Mods', k: k),
                const _StatDivider(),
                if (mine) ...[
                  _Stat(value: spent == null ? null : 'RM ${compactMoney(spent)}', label: 'Spent', k: k),
                  const _StatDivider(),
                ],
                _Stat(value: f.meets?.toString(), label: 'Meets', k: k),
                const _StatDivider(),
                _Stat(value: f.posts?.toString(), label: 'Posts', k: k),
              ],
            ),
          ),
          if (mine) ...[
            SizedBox(height: 18 * k),
            Text('PAPERS', style: _kicker(k)),
            const SizedBox(height: 8),
            if (!f.papersLoaded)
              Text('Checking your papers…', style: _soft(k))
            else
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  if (chips.isEmpty) _PaperChip(icon: AppIcons.plus, text: 'Add road tax and insurance dates', onTap: onPapers),
                  for (final d in chips) _PaperChip(icon: d.icon, text: d.text, urgent: d.urgent, onTap: onPapers),
                ],
              ),
          ],
          SizedBox(height: 18 * k),
          Row(
            children: [
              Expanded(child: Text('RECENT MODS', maxLines: 1, overflow: TextOverflow.ellipsis, style: _kicker(k))),
              if (mods != null && mods.length > 3)
                Text('${mods.length} in all', style: TextStyle(fontSize: 12 * k, fontWeight: FontWeight.w600, color: GarageColors.textSoft)),
            ],
          ),
          const SizedBox(height: 6),
          if (mods == null)
            Text('Loading…', style: _soft(k))
          else if (mods.isEmpty)
            Text(mine ? 'No mods logged yet. Add them on the car page.' : 'No mods shared yet.', style: _soft(k))
          else
            for (final m in mods.take(3)) _ModRow(mod: m, showPrice: mine, k: k, onTap: onOpen),
          SizedBox(height: 16 * k),
          PanelButton(label: 'Open car', icon: AppIcons.arrowRight, onTap: onOpen, k: k),
        ],
      ),
    );
  }
}

/// Collapsed, on the empty bay: what it's for and the Add button. Same shape
/// as a car's, so the panel keeps its height between bays.
class GarageAddPeek extends StatelessWidget {
  const GarageAddPeek({super.key, required this.k, required this.onAdd});
  final double k;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            _KickerRow(text: 'EMPTY BAY', k: k),
            const SizedBox(height: 2),
            Text('Park another car', maxLines: 1, overflow: TextOverflow.ellipsis, style: _title(k)),
            const SizedBox(height: 2),
            Text('Your daily, your project, your weekend toy.', maxLines: 1, overflow: TextOverflow.ellipsis, style: _soft(k)),
            SizedBox(height: 12 * k),
            PanelButton(label: 'Add a car', icon: AppIcons.plus, onTap: onAdd, k: k),
          ],
        ),
      );
}

/// The small caps line over the name, with room for a tag whether or not
/// there is one, so every bay's panel is the same height.
class _KickerRow extends StatelessWidget {
  const _KickerRow({required this.text, required this.k, this.tag});
  final String text;
  final double k;
  final String? tag;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Flexible(child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: _kicker(k))),
          const SizedBox(width: 8),
          Visibility(
            visible: tag != null,
            maintainSize: true,
            maintainAnimation: true,
            maintainState: true,
            child: PanelTag(text: tag ?? 'DAILY'),
          ),
        ],
      );
}

/// TODAY'S CAR, in brand red.
class PanelTag extends StatelessWidget {
  const PanelTag({super.key, required this.text});
  final String text;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(color: AppColors.brand, borderRadius: BorderRadius.circular(AppRadius.pill)),
        child: Text(
          text,
          maxLines: 1,
          textScaler: MediaQuery.textScalerOf(context).clamp(maxScaleFactor: 1.2),
          style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, letterSpacing: 0.6, color: Colors.white, height: 1.3),
        ),
      );
}

/// A panel button: white on the night glass (filled), or a hairline outline.
/// A long label shrinks to fit rather than cutting off.
class PanelButton extends StatelessWidget {
  const PanelButton({super.key, required this.label, required this.onTap, required this.k, this.icon, this.filled = true});
  final String label;
  final VoidCallback onTap;
  final double k;
  final IconData? icon;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final fg = filled ? AppColors.ink : GarageColors.text;
    final label = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[Icon(icon, size: 17, color: fg), const SizedBox(width: 6)],
        Text(this.label, maxLines: 1, softWrap: false, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: fg)),
      ],
    );
    return Semantics(
      button: true,
      child: Material(
        color: filled ? Colors.white : Colors.white.withValues(alpha: 0.06),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: filled ? BorderSide.none : BorderSide(color: Colors.white.withValues(alpha: 0.24)),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          splashColor: (filled ? AppColors.ink : Colors.white).withValues(alpha: 0.10),
          child: SizedBox(
            height: 46 * k,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Center(child: FittedBox(fit: BoxFit.scaleDown, child: label)),
            ),
          ),
        ),
      ),
    );
  }
}

/// A round glass button: the panel's More, and the top bar's back / view /
/// add over the bay.
class PanelIconButton extends StatelessWidget {
  const PanelIconButton({super.key, required this.icon, required this.tooltip, required this.onTap, this.size = 44, this.iconSize = 20});
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final double size;
  final double iconSize;

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: tooltip,
        excludeSemantics: true,
        child: Tooltip(
          message: tooltip,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onTap,
            child: ClipOval(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                child: Container(
                  width: size,
                  height: size,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withValues(alpha: 0.12),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
                  ),
                  child: Icon(icon, size: iconSize, color: Colors.white),
                ),
              ),
            ),
          ),
        ),
      );
}

class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label, required this.k});
  final String? value;
  final String label;
  final double k;

  @override
  Widget build(BuildContext context) => Expanded(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Column(
            children: [
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  value ?? '–',
                  maxLines: 1,
                  style: TextStyle(fontFamily: AppFonts.display, fontSize: 24 * k, fontWeight: FontWeight.w700, height: 1.1, color: GarageColors.text),
                ),
              ),
              const SizedBox(height: 2),
              Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12 * k, color: GarageColors.textSoft)),
            ],
          ),
        ),
      );
}

class _StatDivider extends StatelessWidget {
  const _StatDivider();

  @override
  Widget build(BuildContext context) => Container(width: 1, height: 28, color: PanelColors.divider);
}

/// A paper's state: red when it runs out within two weeks (or already has).
class _PaperChip extends StatelessWidget {
  const _PaperChip({required this.icon, required this.text, this.urgent = false, this.onTap});
  final IconData icon;
  final String text;
  final bool urgent;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final fg = urgent ? PanelColors.danger : GarageColors.text;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: urgent ? PanelColors.dangerFill : PanelColors.card,
          borderRadius: BorderRadius.circular(AppRadius.pill),
          border: Border.all(color: urgent ? PanelColors.danger.withValues(alpha: 0.35) : PanelColors.divider),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: fg),
            const SizedBox(width: 5),
            Flexible(child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: fg))),
          ],
        ),
      ),
    );
  }
}

/// One of the latest mods: its category code, name, and when (and, for the
/// owner, what it cost).
class _ModRow extends StatelessWidget {
  const _ModRow({required this.mod, required this.showPrice, required this.k, required this.onTap});
  final CarMod mod;
  final bool showPrice;
  final double k;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final m = mod;
    final sub = [formatShortDay(m.doneOn), if (showPrice && m.cost != null) 'RM ${formatRinggit(m.cost!)}'].join(' · ');
    final tint = _nightTint(m.category);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Container(
              width: 40 * k,
              height: 40 * k,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: tint.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(11)),
              child: Text(
                m.category.code,
                textScaler: TextScaler.noScaling,
                style: TextStyle(fontFamily: AppFonts.display, fontSize: 14 * k, fontWeight: FontWeight.w800, letterSpacing: 0.6, color: tint),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(m.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 14.5 * k, fontWeight: FontWeight.w600, color: GarageColors.text)),
                  const SizedBox(height: 1),
                  Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.5 * k, color: GarageColors.textSoft)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The car page's category colours, the night set (the panel is always dark).
Color _nightTint(ModCategory c) => switch (c) {
      ModCategory.wheels => const Color(0xFF7CA8FF),
      ModCategory.exhaust => const Color(0xFFFF8A8A),
      ModCategory.engine => const Color(0xFFFFA36B),
      ModCategory.intake => const Color(0xFF4FD8C6),
      ModCategory.suspension => const Color(0xFFB9A2FF),
      ModCategory.brakes => const Color(0xFFFF8BA6),
      ModCategory.body => const Color(0xFF6BE09A),
      ModCategory.lighting => const Color(0xFFF7CF4A),
      ModCategory.interior => const Color(0xFFCBD5E1),
      ModCategory.audio => const Color(0xFFF08CFF),
      ModCategory.other => const Color(0xFFD1D5DB),
    };
