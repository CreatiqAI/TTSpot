import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/titi.dart';
import '../../../core/utils/dates.dart';
import '../../../core/utils/friendly_error.dart';
import '../../../core/utils/open_external.dart' show confirmSheet;
import '../../../core/widgets/primary_button.dart';
import '../application/organizer_providers.dart';
import '../domain/organizer_models.dart';

/// The meet's lucky draws (usually one): set one up, edit it, open the stage.
class LuckyDrawsScreen extends ConsumerWidget {
  const LuckyDrawsScreen({super.key, required this.eventId});
  final String eventId;

  Future<void> _cancel(BuildContext context, WidgetRef ref, LuckyDraw d) async {
    final ok = await confirmSheet(context, title: 'Cancel ${d.title}?', body: 'Members see it as cancelled. This can\'t be undone.', confirm: 'Cancel draw', cancel: 'Keep', icon: AppIcons.xCircle);
    if (!ok || !context.mounted) return;
    try {
      await ref.read(organizerActionsProvider).cancelDraw(eventId, d.id);
    } catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e))));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final draws = ref.watch(eventDrawsProvider(eventId));
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(AppIcons.arrowLeft), onPressed: () => context.pop()),
        title: const Text('Lucky draw'),
      ),
      body: draws.when(
        loading: () => const Center(child: CircularProgressIndicator(strokeWidth: 2)),
        error: (e, _) => Center(child: Padding(padding: const EdgeInsets.all(32), child: Text(friendlyError(e), textAlign: TextAlign.center))),
        data: (list) {
          final active = list.where((d) => d.status != DrawStatus.cancelled).toList();
          return RefreshIndicator(
            onRefresh: () => ref.refresh(eventDrawsProvider(eventId).future),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
              children: [
                if (active.isEmpty) ...[
                  const SizedBox(height: 12),
                  const Center(child: Titi(TitiPose.gift, height: 150)),
                  const SizedBox(height: 12),
                  Text('Give back to the people who showed up', textAlign: TextAlign.center, style: TextStyle(fontFamily: AppFonts.display, fontSize: 26, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                  const SizedBox(height: 6),
                  Text(
                    'Free entry for everyone who checks in. Winners are picked on our server at the time you set, get a push and a claim QR, and collect at your stage.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppColors.textSecondary, height: 1.4),
                  ),
                  const SizedBox(height: 20),
                ],
                for (final d in list) _DrawTile(eventId: eventId, draw: d, onCancel: () => _cancel(context, ref, d)),
                const SizedBox(height: 12),
                PrimaryButton(label: active.isEmpty ? 'Set up a lucky draw' : 'Add another draw', onPressed: () => context.push(Routes.eventDrawNew(eventId))),
                const SizedBox(height: 10),
                Text(
                  'Free to enter. TT Spot provides the platform; prizes are provided by you, the organizer. Never sell entries or give extra entries for points, cards or purchases.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: AppColors.textMuted, height: 1.35),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _DrawTile extends StatelessWidget {
  const _DrawTile({required this.eventId, required this.draw, required this.onCancel});
  final String eventId;
  final LuckyDraw draw;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final d = draw;
    final (String status, Color color) = switch (d.status) {
      DrawStatus.scheduled => ('Scheduled · ${formatEventDate(d.drawAt)}', AppColors.brand),
      DrawStatus.drawn => ('Drawn · ${d.entrantCount ?? 0} entries', AppColors.success),
      DrawStatus.cancelled => ('Cancelled', AppColors.textMuted),
    };
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(color: AppColors.surfaceGray, borderRadius: BorderRadius.circular(AppRadius.lg)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ListTile(
            leading: Icon(AppIcons.gift, color: d.status == DrawStatus.cancelled ? AppColors.textMuted : AppColors.textPrimary),
            title: Text(d.title, style: const TextStyle(fontWeight: FontWeight.w800)),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(status, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: color)),
                const SizedBox(height: 2),
                Text(
                  [
                    d.prizes.map((p) => '${p.quantity}× ${p.name}').join(', '),
                    if (d.cutoffAt.isBefore(d.drawAt)) 'entries close ${formatTime(d.cutoffAt)}',
                    d.mustBePresent ? 'claim within ${d.claimMinutes} min' : 'no need to be present',
                  ].where((s) => s.isNotEmpty).join(' · '),
                  style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary, height: 1.35),
                ),
              ],
            ),
          ),
          if (d.status != DrawStatus.cancelled)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
              child: Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () => context.push(Routes.drawStage(eventId, d.id)),
                      icon: const Icon(AppIcons.cornersOut, size: 18),
                      label: Text(d.status == DrawStatus.drawn ? 'Results & stage' : 'Stage screen'),
                    ),
                  ),
                  if (d.status == DrawStatus.scheduled) ...[
                    const SizedBox(width: 8),
                    IconButton.filledTonal(tooltip: 'Edit', onPressed: () => context.push(Routes.eventDrawEdit(eventId, d.id)), icon: const Icon(AppIcons.pencilSimple)),
                    IconButton(tooltip: 'Cancel draw', onPressed: onCancel, icon: Icon(AppIcons.trash, color: AppColors.textSecondary)),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }
}
