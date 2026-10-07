import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../../core/theme/app_icons.dart';
import '../../../../core/theme/app_images.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/titi.dart';
import '../../../../core/utils/dates.dart';
import '../../../../core/utils/friendly_error.dart';
import '../../../../core/widgets/user_avatar.dart';
import '../../../events/application/event_providers.dart';
import '../../../share/share_card_renderer.dart';
import '../../application/organizer_providers.dart';
import '../../domain/organizer_models.dart';

/// The member's lucky-draw card on a meet page: "you're in", "check in to
/// enter", "you won, show this QR", "not this time". Draws nothing when the
/// meet has no draw.
class LuckyDrawCard extends ConsumerStatefulWidget {
  const LuckyDrawCard({super.key, required this.eventId});
  final String eventId;

  @override
  ConsumerState<LuckyDrawCard> createState() => _LuckyDrawCardState();
}

class _LuckyDrawCardState extends ConsumerState<LuckyDrawCard> {
  Timer? _tick;
  int _secs = 0;

  @override
  void initState() {
    super.initState();
    // Countdown every second; refetch every 20 s while something is about to change.
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      _secs++;
      final draws = ref.read(myDrawStatusProvider(widget.eventId)).value ?? const <MyDraw>[];
      final live = draws.any((d) =>
          (d.status == DrawStatus.scheduled && d.drawAt.difference(DateTime.now()).inMinutes < 60) || (d.win?.isOpen ?? false) || (d.win?.onStandby ?? false));
      if (live && _secs % 20 == 0) ref.invalidate(myDrawStatusProvider(widget.eventId));
      if (draws.any((d) => d.win?.isOpen ?? false) || draws.any((d) => d.status == DrawStatus.scheduled)) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final draws = ref.watch(myDrawStatusProvider(widget.eventId)).value ?? const <MyDraw>[];
    if (draws.isEmpty) return const SizedBox.shrink();
    return Column(
      children: [
        for (final d in draws)
          Padding(padding: const EdgeInsets.only(bottom: 8), child: _DrawCard(draw: d, eventId: widget.eventId)),
      ],
    );
  }
}

class _DrawCard extends StatelessWidget {
  const _DrawCard({required this.draw, required this.eventId});
  final MyDraw draw;
  final String eventId;

  @override
  Widget build(BuildContext context) {
    final d = draw;
    final w = d.win;
    final dark = w != null && w.hasPrize && w.isOpen;
    final fg = dark ? Colors.white : AppColors.textPrimary;
    final fg2 = dark ? Colors.white70 : AppColors.textSecondary;
    final now = DateTime.now();
    final inPlay = d.status == DrawStatus.scheduled && d.excluded == null;
    // Roll call: checked in, roll call on, still time to confirm.
    final rollCall = inPlay && d.presenceRequired && d.checkedIn && !d.cutoffPassed;
    final rollOpen = rollCall && d.rollCallOpenAt(now);
    final opensAt = d.rollCallOpensAt;

    final (TitiPose pose, String headline, String? line) = switch (d.status) {
      DrawStatus.cancelled => (TitiPose.sad, 'Lucky draw cancelled', null),
      DrawStatus.scheduled when d.excluded != null =>
        (TitiPose.thumbsUp, 'Lucky draw at ${formatTime(d.drawAt)}', 'You\'re ${d.excluded == 'host' ? 'hosting' : 'on the crew'}, so you can\'t enter. Run it from Organizer tools.'),
      DrawStatus.scheduled when d.eligible => (TitiPose.gift, 'Lucky draw at ${formatTime(d.drawAt)} · you\'re in', 'Free entry, one per member. Stay nearby for the draw.'),
      DrawStatus.scheduled when rollCall && !d.presenceConfirmed => (
          TitiPose.bell,
          'Lucky draw at ${formatTime(d.drawAt)}',
          rollOpen
              ? "Roll call is open. Tap 'I'm here' to enter."
              : "Roll call opens at ${opensAt == null ? '' : formatTime(opensAt)}. Be here and tap 'I'm here' to enter."
        ),
      DrawStatus.scheduled when d.cutoffPassed => (TitiPose.sad, 'Lucky draw at ${formatTime(d.drawAt)}', 'Entries closed at ${formatTime(d.cutoffAt)}.'),
      DrawStatus.scheduled when d.checkedIn =>
        (TitiPose.magnifier, 'Lucky draw at ${formatTime(d.drawAt)}', 'Almost in: scan the meet QR at the door, or ask the host or crew to confirm you. Entries close ${formatTime(d.cutoffAt)}.'),
      DrawStatus.scheduled => (TitiPose.mapPin, 'Lucky draw at ${formatTime(d.drawAt)}', 'Check in to enter. Scan the meet QR at the door before ${formatTime(d.cutoffAt)}. Free.'),
      DrawStatus.drawn when w != null && w.hasPrize && w.status == 'claimed' => (TitiPose.celebrate, 'You won ${w.prize ?? 'a prize'}', 'Collected. Enjoy!'),
      DrawStatus.drawn when w != null && w.hasPrize && w.isClosed => (TitiPose.sad, 'You won ${w.prize ?? 'a prize'}', 'The claim window closed, so it passed to the next in line.'),
      DrawStatus.drawn when w != null && w.hasPrize => (
          TitiPose.celebrate,
          'You won ${w.prize ?? 'a prize'}!',
          w.expiresAt == null ? 'Show this QR to the host or crew to collect.' : 'Show this QR at the stage within ${_countdown(w.expiresAt!)}'
        ),
      DrawStatus.drawn when w != null && w.onStandby => (TitiPose.thumbsUp, 'You\'re on standby (#${w.rank})', 'If a winner doesn\'t claim in time, the prize comes to you. Keep your phone on.'),
      DrawStatus.drawn when d.eligible => (TitiPose.sad, 'Not this time', 'The winners are out. Thanks for coming.'),
      DrawStatus.drawn => (TitiPose.gift, 'Lucky draw: winners are out', null),
    };

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: dark ? AppColors.ink : AppColors.surfaceGray,
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TitiAvatar(pose, size: 48, background: dark ? Colors.white : AppColors.surface),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(d.title.toUpperCase(), style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, letterSpacing: 0.8, color: fg2)),
                    const SizedBox(height: 2),
                    Text(headline, style: TextStyle(fontFamily: AppFonts.display, fontSize: 22, height: 1.05, fontWeight: FontWeight.w700, color: fg)),
                    if (line != null) ...[
                      const SizedBox(height: 4),
                      Text(line, style: TextStyle(fontSize: 13, height: 1.35, color: fg2)),
                    ],
                  ],
                ),
              ),
            ],
          ),
          if (d.entryNo != null && d.excluded == null && d.status != DrawStatus.cancelled) ...[
            const SizedBox(height: 12),
            _EntryNumber(entryNo: d.entryNo!, dark: dark, confirmed: d.presenceRequired && d.presenceConfirmed && d.status == DrawStatus.scheduled),
          ],
          if (rollOpen && !d.presenceConfirmed) ...[
            const SizedBox(height: 10),
            _ImHereButton(eventId: eventId, drawId: d.id),
          ] else if (rollCall && !d.presenceConfirmed && opensAt != null && now.isBefore(opensAt)) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Icon(AppIcons.alarm, size: 16, color: fg2),
                const SizedBox(width: 6),
                Expanded(child: Text('Roll call opens at ${formatTime(opensAt)}', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: fg))),
              ],
            ),
          ],
          if (w != null && w.hasPrize && w.isOpen) ...[
            const SizedBox(height: 14),
            Center(
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(AppRadius.md)),
                child: QrImageView(data: w.qrPayload, size: 200, padding: EdgeInsets.zero, backgroundColor: Colors.white, errorCorrectionLevel: QrErrorCorrectLevel.M),
              ),
            ),
            const SizedBox(height: 8),
            Center(child: Text('Claim code ${w.claimCode} · #${w.rank}', style: const TextStyle(fontSize: 12, color: Colors.white70, fontWeight: FontWeight.w600))),
          ],
          if (d.status == DrawStatus.scheduled && d.prizes.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final p in d.prizes)
                  Container(
                    padding: const EdgeInsets.fromLTRB(8, 4, 10, 4),
                    decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(AppRadius.pill)),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Image.asset(prizeAsset(p.name), width: 18, height: 18, filterQuality: FilterQuality.medium),
                        const SizedBox(width: 4),
                        Text('${p.quantity > 1 ? '${p.quantity}× ' : ''}${p.name}', style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 6),
          Row(
            children: [
              TextButton.icon(
                style: TextButton.styleFrom(visualDensity: VisualDensity.compact, foregroundColor: fg, padding: const EdgeInsets.symmetric(horizontal: 6)),
                onPressed: () => showDrawRulesSheet(context, d),
                icon: const Icon(AppIcons.info, size: 16),
                label: const Text('Rules'),
              ),
              if (d.status == DrawStatus.drawn)
                TextButton.icon(
                  style: TextButton.styleFrom(visualDensity: VisualDensity.compact, foregroundColor: fg, padding: const EdgeInsets.symmetric(horizontal: 6)),
                  onPressed: () => showDrawWinnersSheet(context, drawId: d.id, title: d.title),
                  icon: const Icon(AppIcons.trophy, size: 16),
                  label: const Text('Winners'),
                ),
              if (d.status == DrawStatus.drawn && w != null && w.hasPrize && !w.isClosed)
                Consumer(
                  builder: (context, ref, _) => TextButton.icon(
                    style: TextButton.styleFrom(visualDensity: VisualDensity.compact, foregroundColor: fg, padding: const EdgeInsets.symmetric(horizontal: 6)),
                    onPressed: () => showShareCardSheet(
                      context,
                      DrawWinShareSpec(prize: w.prize ?? 'A prize', eventName: ref.read(eventDetailProvider(eventId)).value?.event.title ?? d.title),
                    ),
                    icon: const Icon(AppIcons.shareFat, size: 16),
                    label: const Text('Share'),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  static String _countdown(DateTime until) {
    final left = until.difference(DateTime.now());
    if (left.isNegative) return '0:00';
    final m = left.inMinutes;
    final s = (left.inSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }
}

/// My entry number, big: it's what the stage calls out.
class _EntryNumber extends StatelessWidget {
  const _EntryNumber({required this.entryNo, required this.dark, required this.confirmed});
  final int entryNo;
  final bool dark;
  final bool confirmed;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.fromLTRB(14, 8, 12, 8),
        decoration: BoxDecoration(
          color: dark ? Colors.white.withValues(alpha: 0.1) : AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('YOUR NUMBER', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, letterSpacing: 0.8, color: dark ? Colors.white70 : AppColors.textSecondary)),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      formatEntryNo(entryNo),
                      maxLines: 1,
                      style: TextStyle(fontFamily: AppFonts.display, fontSize: 38, height: 1.05, fontWeight: FontWeight.w800, color: dark ? Colors.white : AppColors.textPrimary),
                    ),
                  ),
                ],
              ),
            ),
            if (confirmed)
              Flexible(
                child: Container(
                  padding: const EdgeInsets.fromLTRB(8, 5, 10, 5),
                  decoration: BoxDecoration(color: AppColors.success.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(AppRadius.pill)),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(AppIcons.checkCircleFill, size: 16, color: AppColors.success),
                      SizedBox(width: 5),
                      Flexible(
                        child: Text('Confirmed', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: AppColors.success)),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      );
}

/// Roll call: one strong button. Gets a location fix and confirms I'm here.
class _ImHereButton extends ConsumerStatefulWidget {
  const _ImHereButton({required this.eventId, required this.drawId});
  final String eventId;
  final String drawId;

  @override
  ConsumerState<_ImHereButton> createState() => _ImHereButtonState();
}

class _ImHereButtonState extends ConsumerState<_ImHereButton> {
  bool _busy = false;

  Future<void> _tap() async {
    setState(() => _busy = true);
    try {
      await ref.read(organizerActionsProvider).confirmPresence(widget.eventId, widget.drawId);
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(const SnackBar(content: Text("Confirmed. You're in the draw.")));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(friendlyError(e))));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => SizedBox(
        width: double.infinity,
        child: FilledButton.icon(
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.brand,
            foregroundColor: Colors.white,
            minimumSize: const Size.fromHeight(52),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.pill)),
          ),
          onPressed: _busy ? null : _tap,
          icon: _busy
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Icon(AppIcons.handWaving),
          label: Text(_busy ? 'Checking your location…' : "I'm here", maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
        ),
      );
}

/// The official rules for one draw (Apple 5.3 / Google Play need them in-app).
Future<void> showDrawRulesSheet(BuildContext context, MyDraw d) {
  final prizes = d.prizes.map((p) => '${p.quantity}× ${p.name}').join(', ');
  final lines = <(IconData, String)>[
    (AppIcons.gift, 'Free to enter. TT Spot provides the platform; prizes are provided by the organizer. Apple is not a sponsor.'),
    (AppIcons.prohibit, 'Nothing buys an entry: no points, cards, purchases or tickets. One entry per member.'),
    (AppIcons.checkCircle, 'Who is in: members who check in by scanning the meet QR, or whom the host or crew confirm, by ${formatEventDate(d.cutoffAt)}. The host, co-hosts and crew can\'t enter.'),
    if (d.presenceRequired && d.rollCallOpensAt != null)
      (
        AppIcons.handWaving,
        "Roll call: from ${formatTime(d.rollCallOpensAt!)}, tap 'I'm here' while inside the event area. Only members who confirm before entries close are in."
      ),
    (AppIcons.calendarBlank, 'Draw: ${formatEventDate(d.drawAt)}. ${d.winnerCount} winner${d.winnerCount == 1 ? '' : 's'}${prizes.isEmpty ? '' : ': $prizes'}.'),
    (AppIcons.shieldCheck, 'How winners are picked: at the draw the entry list is frozen and winners are picked at random on TT Spot\'s server, with 3 ranked alternates. Every step is logged. Odds depend on how many members are eligible.'),
    (
      AppIcons.timer,
      d.mustBePresent
          ? 'Winners must be present: show your claim QR at the stage within ${d.claimMinutes} minutes, or the prize passes to the next alternate.'
          : 'Winners don\'t need to be present. The organizer arranges the handover; show your claim QR to collect.'
    ),
    (AppIcons.handshake, 'Prizes are the organizer\'s to deliver. Questions about a prize go to the host through the meet chat.'),
  ];
  return showModalBottomSheet<void>(
    useRootNavigator: true,
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) => SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * 0.85),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          children: [
            Text('${d.title}: rules', style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
            const SizedBox(height: 14),
            for (final l in lines)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(l.$1, size: 20, color: AppColors.textSecondary),
                    const SizedBox(width: 12),
                    Expanded(child: Text(l.$2, style: const TextStyle(fontSize: 14, height: 1.4))),
                  ],
                ),
              ),
          ],
        ),
      ),
    ),
  );
}

/// The public winners list for a drawn draw.
Future<void> showDrawWinnersSheet(BuildContext context, {required String drawId, required String title}) {
  return showModalBottomSheet<void>(
    useRootNavigator: true,
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) => SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * 0.8),
        child: Consumer(
          builder: (ctx, ref, _) {
            final results = ref.watch(drawResultsProvider(drawId));
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                  child: Text('$title: winners', style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
                ),
                Flexible(
                  child: results.when(
                    loading: () => const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator(strokeWidth: 2))),
                    error: (e, _) => Padding(padding: const EdgeInsets.all(20), child: Text(friendlyError(e))),
                    data: (list) => list.isEmpty
                        ? Padding(padding: const EdgeInsets.all(20), child: Text('No winners: nobody was eligible.', style: TextStyle(color: AppColors.textSecondary)))
                        : ListView(
                            shrinkWrap: true,
                            children: [
                              for (final r in list)
                                ListTile(
                                  leading: UserAvatar(url: r.avatarUrl, name: r.displayName, seed: r.userId, size: 40),
                                  title: Text(r.displayName, style: const TextStyle(fontWeight: FontWeight.w700)),
                                  subtitle: Text(
                                    [if (r.entryNo != null) formatEntryNo(r.entryNo!), r.prize].join(' · '),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
                                  ),
                                  trailing: Text(
                                    switch (r.status) { 'claimed' => 'Collected', 'expired' => 'Missed', 'forfeited' => 'Passed on', _ => '#${r.rank}' },
                                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: r.status == 'claimed' ? AppColors.success : AppColors.textSecondary),
                                  ),
                                ),
                            ],
                          ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
                  child: Text('Free to enter. TT Spot provides the platform; prizes are provided by the organizer. Apple is not a sponsor.',
                      style: TextStyle(fontSize: 11.5, color: AppColors.textSecondary, height: 1.35)),
                ),
              ],
            );
          },
        ),
      ),
    ),
  );
}
