import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../../core/theme/app_icons.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/thumb_image.dart';
import '../domain/contest.dart';

/// The car: its die-cast toy on a soft card when there is one, else the cover
/// photo. Fills its parent (give it an AspectRatio).
class ContestCarImage extends StatelessWidget {
  const ContestCarImage({super.key, required this.entry, this.radius = AppRadius.lg});
  final ContestEntry entry;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final src = entry.image;
    final fallback = Center(child: Icon(AppIcons.car, size: 36, color: AppColors.textMuted));
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [AppColors.surfaceGray, AppColors.surfaceRaised],
          ),
        ),
        child: src == null
            ? fallback
            : entry.imageIsToy
                ? Padding(
                    padding: const EdgeInsets.all(8),
                    child: CachedNetworkImage(imageUrl: src, fit: BoxFit.contain, errorWidget: (_, _, _) => fallback),
                  )
                : ThumbImage(src, error: fallback),
      ),
    );
  }
}

/// "#7" in a dark pill.
class EntryNumberBadge extends StatelessWidget {
  const EntryNumberBadge({super.key, required this.number, this.size = 16, this.color});
  final int? number;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) => Container(
        padding: EdgeInsets.symmetric(horizontal: size * 0.5, vertical: size * 0.12),
        decoration: BoxDecoration(color: color ?? AppColors.ink, borderRadius: BorderRadius.circular(AppRadius.pill)),
        child: Text(
          number == null ? '#?' : '#$number',
          style: TextStyle(fontFamily: AppFonts.display, fontSize: size, fontWeight: FontWeight.w800, color: Colors.white, height: 1.15),
        ),
      );
}

/// A grid card: number, car, make/model, @owner (and votes when shown).
class ContestEntryCard extends StatelessWidget {
  const ContestEntryCard({super.key, required this.entry, required this.onTap, this.myVote = false});
  final ContestEntry entry;
  final VoidCallback onTap;
  final bool myVote;

  @override
  Widget build(BuildContext context) {
    final e = entry;
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(AppRadius.lg),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        child: Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(color: myVote ? AppColors.brand : AppColors.border, width: myVote ? 2 : 1),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AspectRatio(
                aspectRatio: 4 / 3,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    ContestCarImage(entry: e, radius: AppRadius.md),
                    Positioned(left: 6, top: 6, child: EntryNumberBadge(number: e.number)),
                    if (myVote)
                      Positioned(
                        right: 6,
                        top: 6,
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: const BoxDecoration(color: AppColors.brand, shape: BoxShape.circle),
                          child: const Icon(AppIcons.check, size: 14, color: Colors.white),
                        ),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 8, 4, 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(e.carName, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
                    const SizedBox(height: 1),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            e.handle.isEmpty ? e.ownerName : e.handle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
                          ),
                        ),
                        if (e.votes != null) ...[
                          const SizedBox(width: 6),
                          Text('${e.votes}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5)),
                          const SizedBox(width: 2),
                          Icon(AppIcons.heartFill, size: 12, color: AppColors.brand),
                        ],
                      ],
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

/// Two cards a row at any width; each card is as tall as its content.
class EntryGrid extends StatelessWidget {
  const EntryGrid({super.key, required this.children, this.spacing = 10});
  final List<Widget> children;
  final double spacing;

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, c) {
        final cols = c.maxWidth >= 640 ? 3 : 2;
        final w = (c.maxWidth - spacing * (cols - 1)) / cols;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [for (final child in children) SizedBox(width: w, child: child)],
        );
      });
}

/// Small rounded status chip.
class ContestPill extends StatelessWidget {
  const ContestPill({super.key, required this.label, required this.color, this.icon});
  final String label;
  final Color color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(AppRadius.pill)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[Icon(icon, size: 14, color: color), const SizedBox(width: 5)],
            Flexible(
              child: Text(label, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: color)),
            ),
          ],
        ),
      );
}

/// Pill color for a contest's state.
Color contestStatusColor(Contest c) => c.cancelled || c.ended ? AppColors.textSecondary : (c.notYet ? AppColors.textPrimary : AppColors.success);
