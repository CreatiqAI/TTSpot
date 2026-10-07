import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/app_router.dart';
import '../../../../core/supabase/supabase_client.dart';
import '../../../../core/theme/app_icons.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/titi.dart';
import '../../../../core/utils/friendly_error.dart';
import '../../../../core/utils/open_external.dart' show confirmSheet;
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/primary_button.dart';
import '../../../../core/widgets/user_avatar.dart';
import '../../../profile/application/profile_providers.dart';
import '../../../profile/domain/car.dart';
import '../application/contest_providers.dart';
import '../domain/contest.dart';
import 'contest_widgets.dart';

/// Members: enter my car, vote once, see results.
/// [contestId] null = the event's current vote. A `?entry=<id>` in the route
/// (from a scanned vote QR) opens that car's sheet.
class ContestScreen extends ConsumerWidget {
  const ContestScreen({super.key, required this.eventId, this.contestId});
  final String eventId;
  final String? contestId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final id = contestId;
    final Widget body;
    if (id != null) {
      body = _Board(eventId: eventId, contestId: id);
    } else {
      body = ref.watch(currentContestIdProvider(eventId)).when(
            loading: () => const Center(child: CircularProgressIndicator(strokeWidth: 2)),
            error: (e, _) => _Error(message: friendlyError(e), onRetry: () => ref.invalidate(currentContestIdProvider(eventId))),
            data: (cid) => cid == null
                ? const EmptyState(titi: TitiPose.trophy, title: 'No show car vote yet', subtitle: 'When the organizer opens one, it shows up here.')
                : _Board(eventId: eventId, contestId: cid),
          );
    }
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(AppIcons.arrowLeft), onPressed: () => context.canPop() ? context.pop() : context.go(Routes.event(eventId))),
        title: const Text('Show car vote'),
      ),
      body: body,
    );
  }
}

class _Error extends StatelessWidget {
  const _Error({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(message, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              TextButton(onPressed: onRetry, child: const Text('Try again')),
            ],
          ),
        ),
      );
}

/// The `?entry=` the route was opened with, if any.
String? _entryParam(BuildContext context) {
  try {
    return GoRouterState.of(context).uri.queryParameters['entry'];
  } catch (_) {
    return null; // not under a router (tests)
  }
}

class _Board extends ConsumerStatefulWidget {
  const _Board({required this.eventId, required this.contestId});
  final String eventId;
  final String contestId;

  @override
  ConsumerState<_Board> createState() => _BoardState();
}

class _BoardState extends ConsumerState<_Board> {
  bool _openedEntry = false;
  bool _busy = false;

  void _snack(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(m)));
  }

  void _maybeOpenEntry(ContestBoard b) {
    if (_openedEntry) return;
    _openedEntry = true;
    final id = _entryParam(context);
    if (id == null) return;
    final e = b.entry(id);
    if (e == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _openSheet(b, e);
    });
  }

  Future<void> _openSheet(ContestBoard b, ContestEntry e) async {
    final vote = await showModalBottomSheet<bool>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _EntrySheet(board: b, entry: e),
    );
    if (vote == true && mounted) await _vote(e);
  }

  Future<void> _vote(ContestEntry e) async {
    final ok = await confirmSheet(
      context,
      title: 'Vote for #${e.number}?',
      body: '${e.carName}. Your vote is final.',
      confirm: 'Vote',
      icon: AppIcons.heart,
    );
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    try {
      await ref.read(contestActionsProvider).vote(widget.contestId, e.id);
      _snack('Voted for #${e.number}. Thanks!');
    } catch (err) {
      _snack(friendlyError(err));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _enter(ContestBoard b) async {
    final me = ref.read(currentUserIdProvider);
    if (me == null) return;
    final List<Car> cars;
    try {
      cars = await ref.read(userCarsProvider(me).future);
    } catch (e) {
      _snack(friendlyError(e));
      return;
    }
    if (!mounted) return;
    if (cars.isEmpty) {
      _snack('Add a car to your garage first.');
      context.push(Routes.myGarage);
      return;
    }
    final car = cars.length == 1 ? cars.first : await _pickCar(cars);
    if (car == null || !mounted) return;
    setState(() => _busy = true);
    try {
      await ref.read(contestActionsProvider).enter(widget.contestId, car.id);
      _snack('Sent. The organizer will check it.');
    } catch (e) {
      _snack(friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<Car?> _pickCar(List<Car> cars) => showModalBottomSheet<Car>(
        context: context,
        useRootNavigator: true,
        showDragHandle: true,
        isScrollControlled: true,
        builder: (ctx) => SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * 0.7),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
                  child: Text('Which car?', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
                ),
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      for (final c in cars)
                        ListTile(
                          leading: SizedBox(
                            width: 64,
                            child: AspectRatio(
                              aspectRatio: 4 / 3,
                              child: ContestCarImage(
                                entry: ContestEntry(id: c.id, userId: c.ownerId, make: c.make, model: c.model, toyUrl: c.toyUrl, cover: c.cover),
                                radius: AppRadius.sm,
                              ),
                            ),
                          ),
                          title: Text(c.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
                          subtitle: c.isDefault ? Text('Main car', style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary)) : null,
                          onTap: () => Navigator.pop(ctx, c),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );

  Future<void> _withdraw(ContestEntry mine) async {
    final ok = await confirmSheet(context, title: 'Take your car out?', body: 'You can enter again while the vote is open.', confirm: 'Take it out', cancel: 'Keep it');
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    try {
      await ref.read(contestActionsProvider).withdraw(widget.contestId, mine.id);
    } catch (e) {
      _snack(friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(contestBoardProvider(widget.contestId));
    return async.when(
      loading: () => const Center(child: CircularProgressIndicator(strokeWidth: 2)),
      error: (e, _) => _Error(message: friendlyError(e), onRetry: () => ref.invalidate(contestBoardProvider(widget.contestId))),
      data: (b) {
        _maybeOpenEntry(b);
        final approved = b.approved;
        final c = b.contest;
        return RefreshIndicator(
          onRefresh: () => ref.refresh(contestBoardProvider(widget.contestId).future),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
            children: [
              _Header(contest: c, total: approved.length),
              const SizedBox(height: 12),
              _MyCard(board: b, busy: _busy, onEnter: () => _enter(b), onWithdraw: _withdraw, onOpen: (e) => _openSheet(b, e)),
              const SizedBox(height: 16),
              if (approved.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Column(
                    children: [
                      const Titi(TitiPose.binoculars, height: 110),
                      const SizedBox(height: 10),
                      Text('No cars in yet', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: AppColors.textPrimary)),
                      const SizedBox(height: 4),
                      Text('Cars show up here once the organizer approves them.', textAlign: TextAlign.center, style: TextStyle(color: AppColors.textSecondary)),
                    ],
                  ),
                )
              else if (c.ended && !c.cancelled) ...[
                _Podium(ranked: rankEntries(approved), onTap: (e) => _openSheet(b, e)),
                const SizedBox(height: 16),
                for (final r in rankEntries(approved)) _ResultRow(ranked: r, mine: r.entry.id == b.me.myVoteEntryId, onTap: () => _openSheet(b, r.entry)),
              ] else ...[
                Text(
                  b.me.canVote ? 'Tap a car to vote' : 'The cars',
                  style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, letterSpacing: 1, color: AppColors.textSecondary),
                ),
                const SizedBox(height: 8),
                EntryGrid(children: [
                  for (final e in approved) ContestEntryCard(entry: e, myVote: e.id == b.me.myVoteEntryId, onTap: () => _openSheet(b, e)),
                ]),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.contest, required this.total});
  final Contest contest;
  final int total;

  @override
  Widget build(BuildContext context) {
    final c = contest;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(c.title, style: TextStyle(fontFamily: AppFonts.display, fontSize: 30, fontWeight: FontWeight.w800, height: 1.05, color: AppColors.textPrimary)),
        if ((c.about ?? '').isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(c.about!, style: TextStyle(color: AppColors.textSecondary, height: 1.4)),
        ],
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: [
            ContestPill(
              label: contestStatusLine(c),
              color: contestStatusColor(c),
              icon: c.ended ? AppIcons.flagCheckered : (c.notYet ? AppIcons.clock : AppIcons.circle),
            ),
            ContestPill(label: '$total car${total == 1 ? '' : 's'}', color: AppColors.textSecondary, icon: AppIcons.car),
          ],
        ),
      ],
    );
  }
}

/// My vote and my entry.
class _MyCard extends StatelessWidget {
  const _MyCard({required this.board, required this.busy, required this.onEnter, required this.onWithdraw, required this.onOpen});
  final ContestBoard board;
  final bool busy;
  final VoidCallback onEnter;
  final ValueChanged<ContestEntry> onWithdraw;
  final ValueChanged<ContestEntry> onOpen;

  @override
  Widget build(BuildContext context) {
    final me = board.me;
    final c = board.contest;
    final voted = board.myVote;
    final mine = me.myEntry;
    final rows = <Widget>[];

    // ---- my vote
    if (voted != null) {
      rows.add(_Line(
        icon: AppIcons.heartFill,
        color: AppColors.brand,
        title: 'You voted for #${voted.number}',
        subtitle: voted.carName,
        onTap: () => onOpen(voted),
      ));
    } else if (me.myVoteEntryId != null) {
      rows.add(_Line(icon: AppIcons.heartFill, color: AppColors.brand, title: 'You voted', subtitle: 'Votes are final.'));
    } else if (!me.canVote && me.reason != null && !c.cancelled) {
      rows.add(_Line(icon: c.ended ? AppIcons.flagCheckered : AppIcons.info, color: AppColors.textSecondary, title: me.reason!));
    } else if (me.canVote) {
      rows.add(_Line(icon: AppIcons.heart, color: AppColors.brand, title: 'You have one vote', subtitle: 'Pick the car you love most. Votes are final.'));
    }

    // ---- my car
    if (mine != null) {
      final (String title, String sub, Color color, IconData icon) = switch (mine.status) {
        EntryStatus.pending => ('Your car is waiting', 'The organizer will check it soon.', AppColors.textPrimary, AppIcons.hourglass),
        EntryStatus.approved => ("You're in as #${mine.number}", mine.carName, AppColors.success, AppIcons.checkCircleFill),
        EntryStatus.rejected => ('Not picked this time', mine.carName, AppColors.textSecondary, AppIcons.xCircle),
      };
      rows.add(_Line(
        icon: icon,
        color: color,
        title: title,
        subtitle: sub,
        trailing: mine.status != EntryStatus.rejected && !c.ended && !c.cancelled
            ? TextButton(onPressed: busy ? null : () => onWithdraw(mine), child: const Text('Take out'))
            : null,
      ));
    } else if (me.canEnter) {
      rows.add(Padding(
        padding: const EdgeInsets.only(top: 4),
        child: SecondaryButton(label: 'Enter my car', icon: AppIcons.car, onPressed: busy ? null : onEnter),
      ));
    }

    if (rows.isEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      decoration: BoxDecoration(color: AppColors.surfaceGray, borderRadius: BorderRadius.circular(AppRadius.lg)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: rows),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line({required this.icon, required this.color, required this.title, this.subtitle, this.trailing, this.onTap});
  final IconData icon;
  final Color color;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            children: [
              Icon(icon, size: 22, color: color),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800)),
                    if (subtitle != null)
                      Text(subtitle!, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary)),
                  ],
                ),
              ),
              ?trailing,
            ],
          ),
        ),
      );
}

/// The top three, second-first-third, on steps.
class _Podium extends StatelessWidget {
  const _Podium({required this.ranked, required this.onTap});
  final List<RankedEntry> ranked;
  final ValueChanged<ContestEntry> onTap;

  static const _gold = Color(0xFFE0A100);
  static const _silver = Color(0xFF9AA0A8);
  static const _bronze = Color(0xFFB4693C);

  @override
  Widget build(BuildContext context) {
    final top = ranked.take(3).toList();
    // Display order: 2nd, 1st, 3rd.
    final slots = <int>[if (top.length > 1) 1, 0, if (top.length > 2) 2];
    const steps = [64.0, 44.0, 30.0];
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 14, 10, 0),
      decoration: BoxDecoration(color: AppColors.surfaceGray, borderRadius: BorderRadius.circular(AppRadius.lg)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (final i in slots)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: GestureDetector(
                  onTap: () => onTap(top[i].entry),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(top[i].place == 1 ? AppIcons.crownFill : AppIcons.medal, size: top[i].place == 1 ? 26 : 20, color: [_gold, _silver, _bronze][(top[i].place - 1).clamp(0, 2)]),
                      const SizedBox(height: 4),
                      AspectRatio(
                        aspectRatio: 1,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            ContestCarImage(entry: top[i].entry, radius: AppRadius.md),
                            Positioned(left: 4, top: 4, child: EntryNumberBadge(number: top[i].entry.number, size: 13)),
                          ],
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(top[i].entry.carName, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
                      Text(
                        '${top[i].entry.votes ?? 0} vote${(top[i].entry.votes ?? 0) == 1 ? '' : 's'}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                      ),
                      const SizedBox(height: 6),
                      Container(
                        height: steps[(top[i].place - 1).clamp(0, 2)],
                        decoration: BoxDecoration(
                          color: [_gold, _silver, _bronze][(top[i].place - 1).clamp(0, 2)].withValues(alpha: 0.85),
                          borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ResultRow extends StatelessWidget {
  const _ResultRow({required this.ranked, required this.mine, required this.onTap});
  final RankedEntry ranked;
  final bool mine;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final e = ranked.entry;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            SizedBox(
              width: 34,
              child: Text('${ranked.place}', textAlign: TextAlign.center, style: TextStyle(fontFamily: AppFonts.display, fontSize: 22, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
            ),
            SizedBox(width: 64, child: AspectRatio(aspectRatio: 4 / 3, child: ContestCarImage(entry: e, radius: AppRadius.sm))),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('#${e.number} · ${e.carName}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800)),
                  Text(
                    [e.handle.isEmpty ? e.ownerName : e.handle, if (mine) 'your vote'].join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12.5, color: mine ? AppColors.brand : AppColors.textSecondary),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text('${e.votes ?? 0}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            const SizedBox(width: 3),
            Icon(AppIcons.heartFill, size: 14, color: AppColors.brand),
          ],
        ),
      ),
    );
  }
}

/// One car, big. Pops true when the member taps Vote.
class _EntrySheet extends StatelessWidget {
  const _EntrySheet({required this.board, required this.entry});
  final ContestBoard board;
  final ContestEntry entry;

  @override
  Widget build(BuildContext context) {
    final e = entry;
    final me = board.me;
    final isMyVote = me.myVoteEntryId == e.id;
    final Widget action;
    if (isMyVote) {
      action = const _SheetNote(icon: AppIcons.heartFill, text: 'Your vote');
    } else if (e.mine) {
      action = const _SheetNote(icon: AppIcons.car, text: 'This is your car');
    } else if (me.canVote && e.status == EntryStatus.approved) {
      action = PrimaryButton(label: 'Vote for #${e.number}', icon: AppIcons.heart, onPressed: () => Navigator.pop(context, true));
    } else if (me.reason != null && !board.contest.ended) {
      action = _SheetNote(icon: AppIcons.info, text: me.reason!);
    } else {
      action = const SizedBox.shrink();
    }
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            AspectRatio(
              aspectRatio: 4 / 3,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ContestCarImage(entry: e),
                  Positioned(left: 10, top: 10, child: EntryNumberBadge(number: e.number, size: 26)),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Text(
              [e.carName, if (e.year != null) '${e.year}'].join(' · '),
              style: TextStyle(fontFamily: AppFonts.display, fontSize: 28, fontWeight: FontWeight.w800, height: 1.05, color: AppColors.textPrimary),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                UserAvatar(url: e.avatarUrl, name: e.ownerName, seed: e.userId, size: 28),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    [e.ownerName, if (e.handle.isNotEmpty && e.displayName != null) e.handle].join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: AppColors.textSecondary, fontWeight: FontWeight.w600),
                  ),
                ),
                if (e.votes != null) ...[
                  Text('${e.votes}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                  const SizedBox(width: 3),
                  Icon(AppIcons.heartFill, size: 14, color: AppColors.brand),
                ],
              ],
            ),
            const SizedBox(height: 16),
            action,
          ],
        ),
      ),
    );
  }
}

class _SheetNote extends StatelessWidget {
  const _SheetNote({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(color: AppColors.surfaceGray, borderRadius: BorderRadius.circular(AppRadius.md)),
        child: Row(
          children: [
            Icon(icon, size: 20, color: AppColors.brand),
            const SizedBox(width: 10),
            Expanded(child: Text(text, style: const TextStyle(fontWeight: FontWeight.w700))),
          ],
        ),
      );
}
