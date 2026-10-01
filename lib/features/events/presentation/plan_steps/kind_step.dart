import 'package:flutter/material.dart';

import '../../../../core/theme/app_art.dart';
import '../../../../core/theme/app_icons.dart';
import '../../../../core/theme/app_theme.dart';
import '../../application/plan_draft.dart';
import '../../domain/event.dart';
import 'wizard_parts.dart';

/// Hosted meets only, first step: what kind of meet (it picks the map icon
/// and the default cover).
class KindStep extends StatelessWidget {
  const KindStep({super.key, required this.draft, this.hostName});
  final PlanDraft draft;
  final String? hostName;

  static String blurb(EventType t) => switch (t) {
        EventType.meet => 'Park up, hang out, show the cars.',
        EventType.convoy => 'Drive together from A to B.',
        EventType.trackday => 'Laps at a circuit or a closed course.',
        _ => '',
      };

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: draft,
      builder: (context, _) => ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        children: [
          const StepHeading('What kind of meet?', subtitle: 'It sets the icon on the map and the starting cover.'),
          if (hostName != null) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(color: AppColors.surfaceGray, borderRadius: BorderRadius.circular(AppRadius.md)),
              child: Row(
                children: [
                  const Icon(AppIcons.shieldCheck, size: 18),
                  const SizedBox(width: 8),
                  Expanded(child: Text('Hosting as $hostName', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5))),
                ],
              ),
            ),
            const SizedBox(height: 14),
          ],
          for (final t in EventType.pickable) ...[
            ChoiceCard(
              key: Key('plan-kind-${t.db}'),
              selected: draft.type == t,
              leading: ArtIcon(t.art, size: 34),
              title: t.label,
              subtitle: blurb(t),
              onTap: () => draft.setType(t),
            ),
            const SizedBox(height: 10),
          ],
        ],
      ),
    );
  }
}
