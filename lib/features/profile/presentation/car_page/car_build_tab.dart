import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../core/theme/app_icons.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/thumbnails.dart';
import '../../domain/car_mod.dart';
import 'car_page_model.dart';

/// The Build tab: the mods log (tile, title, "Category · Shop · date", the
/// price for the owner), or, once there are three things to tell, the whole
/// history as a timeline: mods, meets the car went to, the day it was parked.
class CarBuildTab extends StatelessWidget {
  const CarBuildTab({
    super.key,
    required this.data,
    required this.history,
    required this.onHistory,
    required this.onAddMod,
    required this.onOpenMod,
    required this.onModPhotos,
    required this.onPartner,
    required this.onMeet,
    required this.imageFor,
  });

  final CarPageData data;

  /// Showing the timeline instead of the list.
  final bool history;
  final ValueChanged<bool> onHistory;
  final VoidCallback onAddMod;
  final ValueChanged<CarMod> onOpenMod;
  final ValueChanged<CarMod> onModPhotos;
  final ValueChanged<String> onPartner;
  final ValueChanged<String> onMeet;
  final CarImageResolver imageFor;

  @override
  Widget build(BuildContext context) {
    final mods = data.mods;
    if (mods == null) return const _Loading();
    final mine = data.mine;
    final events = carHistory(data.car, mods: mods, meets: data.meets ?? const [], showPrices: mine);
    final canHistory = events.length >= 3;
    final showTimeline = canHistory && history;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (canHistory)
            Padding(
              padding: const EdgeInsets.only(top: 6, bottom: 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      showTimeline ? '${events.length} moments' : modsSummary(mods),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textSecondary),
                    ),
                  ),
                  const SizedBox(width: 8),
                  _ListHistoryToggle(history: history, onChanged: onHistory),
                ],
              ),
            ),
          if (showTimeline)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: CarTimeline(
                items: events,
                imageFor: imageFor,
                onTap: (e) {
                  if (e.mod != null) {
                    data.mine || e.mod!.photo == null ? onOpenMod(e.mod!) : onModPhotos(e.mod!);
                  } else if (e.meet != null) {
                    onMeet(e.meet!.eventId);
                  }
                },
              ),
            )
          else if (mods.isEmpty)
            mine
                ? CarEmptyCard(
                    title: 'STOCK AND PROUD?',
                    body: 'Log your first mod: wheels, exhaust, tint, anything. Prices stay private.',
                    action: 'Log a mod',
                    onAction: onAddMod,
                  )
                : const SizedBox.shrink()
          else ...[
            for (final m in mods)
              CarModRow(
                mod: m,
                mine: mine,
                onTap: mine ? () => onOpenMod(m) : (m.photo == null ? null : () => onModPhotos(m)),
                onPhotos: m.photo == null ? null : () => onModPhotos(m),
                onPartner: m.vendorId == null ? null : () => onPartner(m.vendorId!),
              ),
            if (mine) ...[
              const SizedBox(height: 12),
              DashedButton(label: '+ Add a mod', onTap: onAddMod),
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(AppIcons.lock, size: 13, color: AppColors.textSecondary),
                  const SizedBox(width: 6),
                  Expanded(child: Text('Prices are only visible to you.', style: TextStyle(fontSize: 12, color: AppColors.textSecondary))),
                ],
              ),
            ],
          ],
        ],
      ),
    );
  }
}

class _Loading extends StatelessWidget {
  const _Loading();

  @override
  Widget build(BuildContext context) => const Padding(
        padding: EdgeInsets.symmetric(vertical: 32),
        child: Center(child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))),
      );
}

/// List ⇄ History.
class _ListHistoryToggle extends StatelessWidget {
  const _ListHistoryToggle({required this.history, required this.onChanged});
  final bool history;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    Widget seg(String label, IconData icon, bool on, bool value) => Semantics(
          button: true,
          selected: on,
          label: label,
          excludeSemantics: true,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => onChanged(value),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(color: on ? AppColors.textPrimary : Colors.transparent, borderRadius: BorderRadius.circular(AppRadius.pill)),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 14, color: on ? AppColors.onInk : AppColors.textPrimary),
                  const SizedBox(width: 5),
                  Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: on ? AppColors.onInk : AppColors.textPrimary)),
                ],
              ),
            ),
          ),
        );
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(color: AppColors.surfaceGray, borderRadius: BorderRadius.circular(AppRadius.pill)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          seg('List', AppIcons.list, !history, false),
          seg('History', AppIcons.clockCounterClockwise, history, true),
        ],
      ),
    );
  }
}

/// A mod's square: its category code on the category's tint, and a small
/// photo mark when there is a picture to see.
class ModCodeTile extends StatelessWidget {
  const ModCodeTile({super.key, required this.category, this.size = 46, this.hasPhoto = false, this.onPhoto});
  final ModCategory category;
  final double size;
  final bool hasPhoto;
  final VoidCallback? onPhoto;

  @override
  Widget build(BuildContext context) {
    final tint = modTint(category);
    return GestureDetector(
      onTap: onPhoto,
      child: SizedBox(
        width: size,
        height: size,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              width: size,
              height: size,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: tint.bg, borderRadius: BorderRadius.circular(size * 0.26)),
              child: Text(
                category.code,
                textScaler: TextScaler.noScaling, // a badge, sized to its tile
                style: TextStyle(fontFamily: AppFonts.display, fontSize: size * 0.33, fontWeight: FontWeight.w800, letterSpacing: 1, color: tint.fg),
              ),
            ),
            if (hasPhoto)
              Positioned(
                right: -3,
                bottom: -3,
                child: Container(
                  width: 18,
                  height: 18,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: AppColors.textPrimary, shape: BoxShape.circle, border: Border.all(color: AppColors.bg, width: 2)),
                  child: Icon(AppIcons.image, size: 9, color: AppColors.onInk),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// One mod in the list.
class CarModRow extends StatelessWidget {
  const CarModRow({super.key, required this.mod, required this.mine, this.onTap, this.onPhotos, this.onPartner});
  final CarMod mod;
  final bool mine;
  final VoidCallback? onTap;
  final VoidCallback? onPhotos;
  final VoidCallback? onPartner;

  @override
  Widget build(BuildContext context) {
    final m = mod;
    final shop = m.shopName;
    final secondary = TextStyle(fontSize: 12.5, height: 1.3, color: AppColors.textSecondary);
    final description = (m.description ?? '').trim();
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.divider))),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ModCodeTile(category: m.category, hasPhoto: m.photo != null, onPhoto: onPhotos),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Flexible(
                        child: Text(m.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, height: 1.25, color: AppColors.textPrimary)),
                      ),
                      if (m.isPrivate)
                        Padding(
                          padding: const EdgeInsets.only(left: 6, top: 2),
                          child: Tooltip(message: 'Only you', child: Icon(AppIcons.lock, size: 14, color: AppColors.textMuted)),
                        ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text('${m.category.label} · ', style: secondary),
                      if (shop != null) ...[
                        GestureDetector(
                          onTap: onPartner,
                          child: Text(
                            shop,
                            style: onPartner == null ? secondary : secondary.copyWith(fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                          ),
                        ),
                        Text(' · ', style: secondary),
                      ],
                      Text(formatShortDay(m.doneOn), style: secondary),
                    ],
                  ),
                  if (description.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(description, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13.5, height: 1.35, color: AppColors.textPrimary)),
                  ],
                ],
              ),
            ),
            // Prices never leave the owner's phone (the server hides them from everyone else).
            if (mine && m.cost != null) ...[
              const SizedBox(width: 10),
              Text('RM ${formatRinggit(m.cost!)}', style: TextStyle(fontFamily: AppFonts.display, fontSize: 18, fontWeight: FontWeight.w700, height: 1.2, color: AppColors.textPrimary)),
            ],
          ],
        ),
      ),
    );
  }
}

/// The car's story top to bottom: a dot per moment on a thin line, and a
/// card with what happened.
class CarTimeline extends StatelessWidget {
  const CarTimeline({super.key, required this.items, required this.onTap, required this.imageFor});
  final List<CarHistoryItem> items;
  final void Function(CarHistoryItem item) onTap;
  final CarImageResolver imageFor;

  static const _dot = 40.0;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned(
          left: _dot / 2 - 1,
          top: 10,
          bottom: 10,
          width: 2,
          child: ColoredBox(color: AppColors.divider),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [for (final e in items) _TimelineEntry(item: e, onTap: e.kind == CarHistoryKind.parked ? null : () => onTap(e), imageFor: imageFor)],
        ),
      ],
    );
  }
}

class _TimelineEntry extends StatelessWidget {
  const _TimelineEntry({required this.item, required this.onTap, required this.imageFor});
  final CarHistoryItem item;
  final VoidCallback? onTap;
  final CarImageResolver imageFor;

  @override
  Widget build(BuildContext context) {
    final e = item;
    final (code, bg, fg) = switch (e.kind) {
      CarHistoryKind.mod => (e.mod!.category.code, modTint(e.mod!.category).bg, modTint(e.mod!.category).fg),
      CarHistoryKind.meet => ('MEET', modTint(ModCategory.wheels).bg, modTint(ModCategory.wheels).fg),
      CarHistoryKind.parked => ('NEW', AppColors.textPrimary, AppColors.onInk),
    };
    // The tint is see-through: lay it on the page colour so the line doesn't show through.
    final dotBg = Color.alphaBlend(bg, AppColors.bg);
    final image = e.image;
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: CarTimeline._dot,
            height: CarTimeline._dot,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: dotBg, shape: BoxShape.circle, border: Border.all(color: AppColors.bg, width: 3)),
            child: Text(
              code,
              textScaler: TextScaler.noScaling,
              style: TextStyle(fontFamily: AppFonts.display, fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 0.5, color: fg),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Material(
              color: AppColors.surfaceGray,
              borderRadius: BorderRadius.circular(16),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: onTap,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              e.eyebrow,
                              style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, letterSpacing: 1.5, color: e.kind == CarHistoryKind.parked ? AppColors.textPrimary : fg),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(formatShortDay(e.date), style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(e.title, maxLines: 3, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700, height: 1.25, color: AppColors.textPrimary)),
                      if (e.sub.isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Text(e.sub, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
                      ],
                      if (image != null) ...[
                        const SizedBox(height: 8),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: AspectRatio(
                            aspectRatio: 16 / 9,
                            child: Image(
                              image: imageFor(thumbUrl(image)),
                              fit: BoxFit.cover,
                              gaplessPlayback: true,
                              errorBuilder: (_, _, _) => Image(image: imageFor(image), fit: BoxFit.cover, errorBuilder: (_, _, _) => ColoredBox(color: AppColors.border)),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A grey card with a big headline, a line, and one button: what a tab says
/// when there is nothing in it yet.
class CarEmptyCard extends StatelessWidget {
  const CarEmptyCard({super.key, required this.title, required this.body, required this.action, required this.onAction});
  final String title;
  final String body;
  final String action;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(top: 8),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(color: AppColors.surfaceGray, borderRadius: BorderRadius.circular(16)),
        child: Column(
          children: [
            Text(title, textAlign: TextAlign.center, style: TextStyle(fontFamily: AppFonts.display, fontSize: 22, fontWeight: FontWeight.w800, height: 1.1, color: AppColors.textPrimary)),
            const SizedBox(height: 6),
            Text(body, textAlign: TextAlign.center, style: TextStyle(fontSize: 13.5, height: 1.4, color: AppColors.textSecondary)),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: onAction,
              style: FilledButton.styleFrom(
                minimumSize: const Size(0, 44),
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                backgroundColor: AppColors.textPrimary,
                foregroundColor: AppColors.onInk,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
              ),
              child: Text(action),
            ),
          ],
        ),
      );
}

/// A full-width button with a dashed outline ("+ Add a mod").
class DashedButton extends StatelessWidget {
  const DashedButton({super.key, required this.label, required this.onTap, this.minHeight = 48});
  final String label;
  final VoidCallback onTap;
  final double minHeight;

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: CustomPaint(
            painter: _DashedBorder(color: AppColors.border, radius: 14),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: minHeight),
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  child: Text(label, textAlign: TextAlign.center, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                ),
              ),
            ),
          ),
        ),
      );
}

class _DashedBorder extends CustomPainter {
  const _DashedBorder({required this.color, required this.radius});
  final Color color;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    final path = Path()..addRRect(RRect.fromRectAndRadius((Offset.zero & size).deflate(0.75), Radius.circular(radius)));
    for (final m in path.computeMetrics()) {
      var d = 0.0;
      while (d < m.length) {
        canvas.drawPath(m.extractPath(d, math.min(d + 6, m.length)), p);
        d += 10;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBorder old) => old.color != color || old.radius != radius;
}
