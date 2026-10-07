import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/app_router.dart';
import '../../../../core/theme/app_icons.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/titi.dart';
import '../../../../core/utils/dates.dart';
import '../../../../core/utils/friendly_error.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/primary_button.dart';
import '../../expo_routes.dart';
import '../application/stamps_providers.dart';
import '../domain/stamps_models.dart';
import 'widgets/hand_over_card.dart';

/// Members: my booth stamps, the rally goal and reward, freebies to collect.
/// `?freebie=<exhibitorId>` (from a booth scan) opens that hand-over card.
class StampsScreen extends ConsumerStatefulWidget {
  const StampsScreen({super.key, required this.eventId});
  final String eventId;

  @override
  ConsumerState<StampsScreen> createState() => _StampsScreenState();
}

class _StampsScreenState extends ConsumerState<StampsScreen> {
  bool _handledFreebieParam = false;

  String? _freebieParam() {
    try {
      return GoRouterState.of(context).uri.queryParameters['freebie'];
    } catch (_) {
      return null; // not under go_router (tests)
    }
  }

  void _maybeOpenFromScan(StampCard card) {
    if (_handledFreebieParam) return;
    _handledFreebieParam = true;
    final id = _freebieParam();
    if (id == null) return;
    final stop = card.stop(id);
    if (stop == null || stop.freebieState != FreebieState.available) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _openFreebie(stop);
    });
  }

  Future<void> _openFreebie(StampStop stop) => showHandOverSheet(
        context,
        HandOverCard(
          kind: 'FREEBIE',
          item: stop.freebie ?? 'Freebie',
          from: [stop.name, boothLabel(stop.booths)].where((s) => s.isNotEmpty).join(' · '),
          redeemedAt: stop.freebieRedeemedAt,
          onRedeem: () => ref.read(stampsActionsProvider).redeemFreebie(eventId: widget.eventId, exhibitorId: stop.id),
        ),
      );

  Future<void> _openRally(StampCard card) => showHandOverSheet(
        context,
        HandOverCard(
          kind: 'STAMP RALLY',
          item: (card.reward ?? '').isEmpty ? 'Stamp rally reward' : card.reward!,
          from: '${card.goal ?? card.stamped} stamps collected',
          showTo: 'Show this at the counter',
          redeemedAt: card.rallyRedeemedAt,
          onRedeem: () => ref.read(stampsActionsProvider).redeemRally(widget.eventId),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(myStampsProvider(widget.eventId));
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(AppIcons.arrowLeft), onPressed: () => context.pop()),
        title: const Text('Stamps'),
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: PrimaryButton(label: 'Scan a booth', icon: AppIcons.scan, onPressed: () => context.push(Routes.scan)),
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator(strokeWidth: 2)),
        error: (e, _) => Center(child: Padding(padding: const EdgeInsets.all(32), child: Text(friendlyError(e), textAlign: TextAlign.center))),
        data: (card) {
          _maybeOpenFromScan(card);
          if (card.stops.isEmpty) {
            return const EmptyState(
              titi: TitiPose.clipboard,
              title: 'No stamp stops yet',
              subtitle: "The organizer hasn't set up booth stamps for this event.",
            );
          }
          return RefreshIndicator(
            onRefresh: () => ref.refresh(myStampsProvider(widget.eventId).future),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              children: [
                if (!card.checkedIn) ...[
                  _Note(icon: AppIcons.mapPin, text: 'Check in at the door to start collecting stamps.'),
                  const SizedBox(height: 12),
                ],
                _ProgressHeader(card: card, onCollect: () => _openRally(card)),
                const SizedBox(height: 20),
                const _SectionTitle('Stamp stops'),
                const SizedBox(height: 10),
                _StampGrid(eventId: widget.eventId, stops: card.stops),
                if (card.freebies.isNotEmpty) ...[
                  const SizedBox(height: 22),
                  const _SectionTitle('Freebies'),
                  const SizedBox(height: 10),
                  for (final s in card.freebies)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _FreebieRow(stop: s, onOpen: () => _openFreebie(s), onFind: () => context.push(ExpoRoutes.floorplanAt(widget.eventId, s.id))),
                    ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

/// The hand-over card in a tall sheet over everything.
Future<void> showHandOverSheet(BuildContext context, Widget card) => showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              card,
              const SizedBox(height: 8),
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
            ],
          ),
        ),
      ),
    );

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Text(text, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800));
}

class _Note extends StatelessWidget {
  const _Note({required this.icon, required this.text});
  final IconData icon;
  final String text;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: AppColors.surfaceGray, borderRadius: BorderRadius.circular(AppRadius.lg)),
        child: Row(
          children: [
            Icon(icon, size: 20, color: AppColors.textPrimary),
            const SizedBox(width: 10),
            Expanded(child: Text(text, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600))),
          ],
        ),
      );
}

class _ProgressHeader extends StatelessWidget {
  const _ProgressHeader({required this.card, required this.onCollect});
  final StampCard card;
  final VoidCallback onCollect;

  @override
  Widget build(BuildContext context) {
    final reward = (card.reward ?? '').isEmpty ? 'the reward' : card.reward!;
    final line = !card.hasRally
        ? 'Scan the QR at each booth. +2 points per new booth.'
        : switch (card.rally) {
            RallyState.none => 'Collect ${card.goal} for $reward.',
            RallyState.done => 'Done! Collect $reward at the counter.',
            RallyState.redeemed => 'Reward collected${card.rallyRedeemedAt == null ? '' : ' · ${formatTime(card.rallyRedeemedAt!)}'}.',
          };
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: AppColors.surfaceGray, borderRadius: BorderRadius.circular(AppRadius.lg)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              SizedBox(
                width: 76,
                height: 76,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    CircularProgressIndicator(
                      value: card.progress,
                      strokeWidth: 8,
                      strokeCap: StrokeCap.round,
                      backgroundColor: AppColors.surface,
                      color: card.rally == RallyState.none ? AppColors.brand : AppColors.success,
                    ),
                    Center(
                      child: FittedBox(
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Icon(card.rally == RallyState.none ? AppIcons.stamp : AppIcons.trophyFill,
                              size: 28, color: card.rally == RallyState.none ? AppColors.brand : AppColors.success),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${card.stamped} of ${card.target} stamps',
                      style: const TextStyle(fontFamily: AppFonts.display, fontSize: 26, height: 1.05, fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 4),
                    Text(line, style: TextStyle(fontSize: 13.5, height: 1.35, color: AppColors.textSecondary)),
                  ],
                ),
              ),
            ],
          ),
          if (card.rally == RallyState.done) ...[
            const SizedBox(height: 12),
            PrimaryButton(label: 'Collect $reward', icon: AppIcons.gift, onPressed: onCollect),
          ],
        ],
      ),
    );
  }
}

class _StampGrid extends StatelessWidget {
  const _StampGrid({required this.eventId, required this.stops});
  final String eventId;
  final List<StampStop> stops;

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, c) {
        const gap = 10.0;
        final cols = c.maxWidth >= 520 ? 4 : 3;
        final w = ((c.maxWidth - gap * (cols - 1)) / cols).floorToDouble();
        return Wrap(
          spacing: gap,
          runSpacing: 14,
          children: [
            for (final s in stops)
              SizedBox(width: w, child: StampTile(stop: s, onTap: () => context.push(ExpoRoutes.floorplanAt(eventId, s.id)))),
          ],
        );
      });
}

/// One "passport" stamp: in colour with the time when stamped, faded with the
/// booth code when not.
class StampTile extends StatelessWidget {
  const StampTile({super.key, required this.stop, required this.onTap});
  final StampStop stop;
  final VoidCallback onTap;

  String get _initials {
    final words = stop.name.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    if (words.isEmpty) return '?';
    return words.take(2).map((w) => w.characters.first.toUpperCase()).join();
  }

  @override
  Widget build(BuildContext context) {
    final on = stop.stamped;
    final ink = on ? AppColors.brand : AppColors.textMuted;
    final booth = boothLabel(stop.booths);
    final seal = Container(
      width: 76,
      height: 76,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: ink, width: 3)),
      child: Container(
        alignment: Alignment.center,
        decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: ink, width: 1.2), color: AppColors.surface),
        child: ClipOval(
          child: on && stop.logoUrl != null
              ? CachedNetworkImage(imageUrl: stop.logoUrl!, width: 60, height: 60, fit: BoxFit.cover, errorWidget: (_, _, _) => _initialsText(ink))
              : _initialsText(ink),
        ),
      ),
    );
    return Semantics(
      button: true,
      label: '${stop.name}, ${on ? 'stamped' : 'not stamped'}',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  on ? Transform.rotate(angle: -0.16, child: seal) : Opacity(opacity: 0.5, child: seal),
                  if (on)
                    Positioned(
                      right: -2,
                      bottom: -2,
                      child: Container(
                        padding: const EdgeInsets.all(3),
                        decoration: BoxDecoration(color: AppColors.success, shape: BoxShape.circle, border: Border.all(color: AppColors.bg, width: 2)),
                        child: const Icon(AppIcons.check, size: 12, color: Colors.white),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                stop.name,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12.5, height: 1.2, fontWeight: FontWeight.w700, color: on ? AppColors.textPrimary : AppColors.textSecondary),
              ),
              Text(
                on ? formatTime(stop.stampedAt!) : (booth.isEmpty ? 'Not yet' : booth),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11.5, color: AppColors.textSecondary, fontWeight: on ? FontWeight.w500 : FontWeight.w700),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _initialsText(Color ink) => Padding(
        padding: const EdgeInsets.all(6),
        child: FittedBox(
          child: Text(_initials, style: TextStyle(fontFamily: AppFonts.display, fontSize: 24, fontWeight: FontWeight.w800, color: ink)),
        ),
      );
}

class _FreebieRow extends StatelessWidget {
  const _FreebieRow({required this.stop, required this.onOpen, required this.onFind});
  final StampStop stop;
  final VoidCallback onOpen;
  final VoidCallback onFind;

  @override
  Widget build(BuildContext context) {
    final (String status, Color color) = switch (stop.freebieState) {
      FreebieState.available => ('Ready to collect', AppColors.success),
      FreebieState.redeemed => ('Collected${stop.freebieRedeemedAt == null ? '' : ' · ${formatTime(stop.freebieRedeemedAt!)}'}', AppColors.textSecondary),
      FreebieState.out => ('All gone', AppColors.textSecondary),
      FreebieState.locked => (stop.freebieLeft == null ? 'Stamp the booth to unlock' : 'Stamp the booth to unlock · ${stop.freebieLeft} left', AppColors.textSecondary),
      FreebieState.none => ('', AppColors.textSecondary),
    };
    final available = stop.freebieState == FreebieState.available;
    return Material(
      color: AppColors.surfaceGray,
      borderRadius: BorderRadius.circular(AppRadius.lg),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        onTap: available ? onOpen : (stop.freebieState == FreebieState.locked ? onFind : null),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: available ? AppColors.brand : AppColors.surface, shape: BoxShape.circle),
                child: Icon(stop.freebieState == FreebieState.redeemed ? AppIcons.check : AppIcons.gift, size: 22, color: available ? Colors.white : AppColors.textPrimary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(stop.freebie ?? '', maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 2),
                    Text(stop.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary)),
                    const SizedBox(height: 2),
                    Text(status, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: color)),
                  ],
                ),
              ),
              if (available) ...[
                const SizedBox(width: 8),
                FilledButton(
                  style: FilledButton.styleFrom(minimumSize: const Size(0, 40), padding: const EdgeInsets.symmetric(horizontal: 16)),
                  onPressed: onOpen,
                  child: const Text('Open'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
