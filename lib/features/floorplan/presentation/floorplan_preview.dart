import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/titi.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/primary_button.dart';
import '../application/floorplan_providers.dart';
import '../domain/floorplan.dart';
import 'floorplan_canvas.dart';
import 'floorplan_screen.dart' show FloorplanRoutes;

/// The event page's Floor plan tab: a big still picture of a level (pins
/// and my spot on it), a level picker, and "Open floor plan" for the full,
/// zoomable plan (find a booth, set my spot). The plan isn't zoomable in the
/// tab: pinch and pan would fight the page's scroll.
class FloorplanPreview extends ConsumerStatefulWidget {
  const FloorplanPreview({super.key, required this.eventId});
  final String eventId;

  @override
  ConsumerState<FloorplanPreview> createState() => _FloorplanPreviewState();
}

class _FloorplanPreviewState extends ConsumerState<FloorplanPreview> {
  String? _levelId;

  void _open(String? levelId) {
    final base = FloorplanRoutes.view(widget.eventId);
    context.push(levelId == null ? base : '$base?level=$levelId');
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(floorLevelsProvider(widget.eventId));
    final mine = ref.watch(myEventPositionProvider(widget.eventId)).value;
    final all = async.value;
    if (all == null) {
      return async.hasError
          ? EmptyState(icon: AppIcons.wifiSlash, title: "Couldn't load the plan", actionLabel: 'Try again', onAction: () => ref.invalidate(floorLevelsProvider(widget.eventId)))
          : const Padding(padding: EdgeInsets.symmetric(vertical: 48), child: Center(child: CircularProgressIndicator(strokeWidth: 2)));
    }
    final levels = all.where((l) => l.hasImage).toList();
    if (levels.isEmpty) {
      return const EmptyState(titi: TitiPose.clipboard, title: 'No floor plan yet', subtitle: 'The organizer is still putting it up.');
    }
    final myLevel = mine == null ? null : levels.where((l) => l.id == mine.levelId).firstOrNull;
    final level = levels.where((l) => l.id == _levelId).firstOrNull ?? myLevel ?? levels.first;
    final mineHere = mine != null && mine.levelId == level.id && mine.hasPoint;
    final booths = level.pins.where((p) => p.kind == PinKind.booth).length;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (levels.length > 1) ...[
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final l in levels)
                  ChoiceChip(
                    label: Text(l.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                    selected: l.id == level.id,
                    onSelected: (_) => setState(() => _levelId = l.id),
                  ),
              ],
            ),
            const SizedBox(height: 10),
          ],
          Semantics(
            button: true,
            label: 'Open floor plan, ${level.name}',
            child: GestureDetector(
              onTap: () => _open(level.id),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.lg),
                child: AspectRatio(
                  aspectRatio: level.aspect.clamp(0.8, 1.8),
                  child: ColoredBox(
                    color: AppColors.surfaceGray,
                    child: IgnorePointer(
                      child: FloorplanCanvas(
                        level: level,
                        padding: const EdgeInsets.all(8),
                        youAreHere: mineHere ? Offset(mine.x!, mine.y!) : null,
                        selectedPinId: mine?.zonePinId,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Icon(mine == null ? AppIcons.mapPin : AppIcons.navigationArrow, size: 18, color: AppColors.textSecondary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  myLevel != null
                      ? 'Your spot: ${myLevel.name}'
                      : '${level.name}${booths > 0 ? ' · $booths booths' : ''}. Tap the plan to find a booth or set your spot.',
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 13, color: AppColors.textSecondary, height: 1.35),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          PrimaryButton(label: 'Open floor plan', icon: AppIcons.mapTrifold, onPressed: () => _open(level.id)),
        ],
      ),
    );
  }
}
