import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_art.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../events/domain/event.dart';
import '../../application/map_providers.dart';

/// Opens the filter sheet (date range + event types).
Future<void> showMapFilterSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: MapPalette.of(context).surface,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (_) => const _FilterSheet(),
  );
}

class _FilterSheet extends ConsumerWidget {
  const _FilterSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filters = ref.watch(mapFiltersProvider);
    final notifier = ref.read(mapFiltersProvider.notifier);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  'Filters',
                  style: TextStyle(color: MapPalette.of(context).text, fontSize: 20, fontWeight: FontWeight.w700),
                ),
                const Spacer(),
                if (!filters.isDefault)
                  TextButton(
                    onPressed: notifier.clear,
                    child: Text('Clear', style: TextStyle(color: MapPalette.of(context).text2)),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            const _SectionLabel('WHEN'),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final r in DateRange.values)
                  _Chip(
                    label: r.label,
                    selected: filters.range == r,
                    onTap: () => notifier.setRange(r),
                  ),
              ],
            ),
            const SizedBox(height: 22),
            const _SectionLabel('TYPE'),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final t in EventType.values)
                  _Chip(
                    art: t.art,
                    label: t.label,
                    selected: filters.types.contains(t),
                    onTap: () => notifier.toggleType(t),
                  ),
              ],
            ),
            const SizedBox(height: 26),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Show meets'),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        color: MapPalette.of(context).text2,
        fontSize: 12,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.2,
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.selected, required this.onTap, this.art});
  final String label;
  final String? art;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: selected ? MapPalette.of(context).accentBg : MapPalette.of(context).tile,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (art != null) ...[ArtIcon(art!, size: 18), const SizedBox(width: 6)],
            Text(
              label,
              style: TextStyle(
                color: selected ? MapPalette.of(context).accentFg : MapPalette.of(context).text,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
