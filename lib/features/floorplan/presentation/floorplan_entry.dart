import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_theme.dart';
import '../application/floorplan_providers.dart';
import 'floorplan_screen.dart';

/// "Floorplan" row on the event page. Shows only once the organizer has
/// uploaded at least one level; brings its own bottom spacing.
class FloorplanEntry extends ConsumerWidget {
  const FloorplanEntry({super.key, required this.eventId});
  final String eventId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final levels = (ref.watch(floorLevelsProvider(eventId)).value ?? const []).where((l) => l.hasImage).toList();
    if (levels.isEmpty) return const SizedBox.shrink();
    final mine = ref.watch(myEventPositionProvider(eventId)).value;
    final myLevel = mine == null ? null : levels.where((l) => l.id == mine.levelId).firstOrNull;
    final pins = levels.fold<int>(0, (n, l) => n + l.pins.length);
    final names = levels.map((l) => l.name).join(' · ');
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Material(
        color: AppColors.surfaceGray,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        child: ListTile(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.lg)),
          leading: const Icon(AppIcons.mapTrifold),
          title: const Text('Floorplan', style: TextStyle(fontWeight: FontWeight.w700)),
          subtitle: Text(
            myLevel != null ? 'Your spot: ${myLevel.name}. $names' : '$names${pins > 0 ? ' · $pins places' : ''}. Find booths and set your spot.',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
          ),
          trailing: const Icon(AppIcons.caretRight),
          onTap: () => context.push(FloorplanRoutes.view(eventId)),
        ),
      ),
    );
  }
}
