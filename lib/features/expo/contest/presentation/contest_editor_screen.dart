import 'dart:async';

import 'package:flutter/cupertino.dart' show CupertinoDatePickerMode;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/pop_or_home.dart';
import '../../../../core/theme/app_icons.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/titi.dart';
import '../../../../core/utils/dates.dart';
import '../../../../core/utils/friendly_error.dart';
import '../../../../core/utils/open_external.dart' show confirmSheet;
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/primary_button.dart';
import '../../../../core/widgets/user_avatar.dart';
import '../../../../core/widgets/wheel_picker.dart';
import '../../../auth/domain/profile.dart';
import '../../../events/application/event_providers.dart';
import '../../../organizer/data/organizer_repository.dart';
import '../../../profile/application/profile_providers.dart';
import '../../../profile/domain/car.dart';
import '../../expo_routes.dart';
import '../application/contest_providers.dart';
import '../domain/contest.dart';
import 'contest_widgets.dart';
import 'vote_qr_sheet_screen.dart';

/// Host: open a vote, approve entries, print vote QR codes, close it.
class ContestEditorScreen extends ConsumerWidget {
  const ContestEditorScreen({super.key, required this.eventId});
  final String eventId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(currentContestIdProvider(eventId));
    return Scaffold(
      appBar: AppBar(
        leading: const AppBackButton(),
        title: const Text('Show car vote'),
      ),
      body: current.when(
        loading: () => const Center(child: CircularProgressIndicator(strokeWidth: 2)),
        error: (e, _) => Center(child: Padding(padding: const EdgeInsets.all(32), child: Text(friendlyError(e), textAlign: TextAlign.center))),
        data: (id) => id == null ? _Start(eventId: eventId) : _HostBoard(eventId: eventId, contestId: id),
      ),
    );
  }
}

Future<void> _openForm(BuildContext context, String eventId, {Contest? contest}) =>
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => _ContestFormScreen(eventId: eventId, contest: contest)));

class _Start extends StatelessWidget {
  const _Start({required this.eventId});
  final String eventId;

  @override
  Widget build(BuildContext context) => ListView(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 40),
        children: [
          const Center(child: Titi(TitiPose.trophy, height: 150)),
          const SizedBox(height: 12),
          Text("People's Choice", textAlign: TextAlign.center, style: TextStyle(fontFamily: AppFonts.display, fontSize: 28, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
          const SizedBox(height: 6),
          Text(
            'Members enter their car, you approve it, each car gets a number and a QR for its dash. Everyone checked in votes once.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textSecondary, height: 1.4),
          ),
          const SizedBox(height: 20),
          PrimaryButton(label: 'Set up a vote', onPressed: () => _openForm(context, eventId)),
        ],
      );
}

class _HostBoard extends ConsumerStatefulWidget {
  const _HostBoard({required this.eventId, required this.contestId});
  final String eventId;
  final String contestId;

  @override
  ConsumerState<_HostBoard> createState() => _HostBoardState();
}

class _HostBoardState extends ConsumerState<_HostBoard> {
  Timer? _timer;
  final _busy = <String>{};

  @override
  void initState() {
    super.initState();
    // Live counts while the host watches.
    _timer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (!mounted) return;
      final ended = ref.read(contestBoardProvider(widget.contestId)).value?.contest.ended ?? false;
      if (!ended) ref.invalidate(contestBoardProvider(widget.contestId));
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _snack(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(m)));
  }

  Future<void> _run(String key, Future<void> Function() f) async {
    setState(() => _busy.add(key));
    try {
      await f();
    } catch (e) {
      _snack(friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy.remove(key));
    }
  }

  ContestActions get _actions => ref.read(contestActionsProvider);

  Future<void> _review(ContestEntry e, bool approve) => _run(e.id, () async {
        final n = await _actions.review(widget.contestId, e.id, approve: approve);
        if (approve && n != null) _snack('${e.carName} is #$n');
      });

  Future<void> _remove(ContestEntry e) async {
    final ok = await confirmSheet(
      context,
      title: 'Take #${e.number} out?',
      body: '${e.carName}. Votes for it go back to the voters.',
      confirm: 'Take out',
      cancel: 'Keep',
      icon: AppIcons.xCircle,
    );
    if (ok && mounted) await _review(e, false);
  }

  Future<void> _close(Contest c) async {
    final ok = await confirmSheet(context, title: 'Close the vote?', body: 'Voting stops and everyone sees the results.', confirm: 'Close vote', cancel: 'Not yet', icon: AppIcons.flagCheckered);
    if (ok && mounted) await _run('close', () => _actions.close(widget.eventId, c.id));
  }

  Future<void> _cancel(Contest c) async {
    final ok = await confirmSheet(context, title: 'Cancel ${c.title}?', body: "Members won't see it any more. This can't be undone.", confirm: 'Cancel vote', cancel: 'Keep', icon: AppIcons.trash);
    if (ok && mounted) await _run('cancel', () => _actions.cancel(widget.eventId, c.id));
  }

  Future<void> _add() async {
    final p = await showModalBottomSheet<Profile>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const _HandlePicker(),
    );
    if (p == null || !mounted || p.username == null) return;
    await _run('add', () async {
      final cars = await ref.read(userCarsProvider(p.id).future);
      if (cars.isEmpty) throw AppException('@${p.username} has no car in their garage yet.');
      Car? car = cars.length == 1 ? cars.first : null;
      if (car == null) {
        if (!mounted) return;
        car = await _pickCar(cars, p.username!);
        if (car == null) return;
      }
      final n = await _actions.hostAdd(widget.contestId, p.username!, carId: car.id);
      _snack('${car.title} is #${n ?? '?'}');
    });
  }

  Future<Car?> _pickCar(List<Car> cars, String username) => showModalBottomSheet<Car>(
        context: context,
        useRootNavigator: true,
        showDragHandle: true,
        builder: (ctx) => SafeArea(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                  child: Text("Which of @$username's cars?", style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
                ),
                for (final c in cars)
                  ListTile(
                    leading: Icon(AppIcons.car, color: AppColors.textSecondary),
                    title: Text(c.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: c.isDefault ? Text('Main car', style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary)) : null,
                    onTap: () => Navigator.pop(ctx, c),
                  ),
              ],
            ),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(contestBoardProvider(widget.contestId));
    return async.when(
      loading: () => const Center(child: CircularProgressIndicator(strokeWidth: 2)),
      error: (e, _) => Center(child: Padding(padding: const EdgeInsets.all(32), child: Text(friendlyError(e), textAlign: TextAlign.center))),
      data: (b) {
        final c = b.contest;
        final pending = b.pending;
        final ranked = rankEntries(b.approved);
        final byNumber = [...b.approved]..sort((x, y) => (x.number ?? 0).compareTo(y.number ?? 0));
        return RefreshIndicator(
          onRefresh: () => ref.refresh(contestBoardProvider(widget.contestId).future),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
            children: [
              // ---- the vote
              Container(
                padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
                decoration: BoxDecoration(color: AppColors.surfaceGray, borderRadius: BorderRadius.circular(AppRadius.lg)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(c.title, style: TextStyle(fontFamily: AppFonts.display, fontSize: 26, fontWeight: FontWeight.w800, height: 1.05, color: AppColors.textPrimary)),
                        ),
                        if (!c.ended)
                          IconButton(tooltip: 'Edit', onPressed: () => _openForm(context, widget.eventId, contest: c), icon: const Icon(AppIcons.pencilSimple)),
                        PopupMenuButton<String>(
                          icon: const Icon(AppIcons.dotsThreeVertical),
                          onSelected: (v) {
                            if (v == 'cancel') _cancel(c);
                            if (v == 'view') context.push(ExpoRoutes.vote(widget.eventId, contestId: c.id));
                          },
                          itemBuilder: (_) => const [
                            PopupMenuItem(value: 'view', child: Text('See what members see')),
                            PopupMenuItem(value: 'cancel', child: Text('Cancel vote')),
                          ],
                        ),
                      ],
                    ),
                    if ((c.about ?? '').isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Padding(padding: const EdgeInsets.only(right: 8), child: Text(c.about!, style: TextStyle(color: AppColors.textSecondary, height: 1.35))),
                    ],
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        ContestPill(label: contestStatusLine(c), color: contestStatusColor(c)),
                        ContestPill(label: '${b.approved.length} car${b.approved.length == 1 ? '' : 's'}', color: AppColors.textSecondary, icon: AppIcons.car),
                        ContestPill(label: '${b.totalVotes ?? 0} vote${(b.totalVotes ?? 0) == 1 ? '' : 's'}', color: AppColors.brand, icon: AppIcons.heartFill),
                        if (!c.membersEnter) ContestPill(label: 'You pick the cars', color: AppColors.textSecondary),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: c.ended
                          ? PrimaryButton(label: 'Start a new vote', onPressed: () => _openForm(context, widget.eventId))
                          : SecondaryButton(label: 'Close vote and show results', icon: AppIcons.flagCheckered, onPressed: _busy.contains('close') ? null : () => _close(c)),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              _ToolRow(
                icon: AppIcons.qrCode,
                title: 'Vote QR codes',
                subtitle: "A card for each car's dash. Share and print.",
                onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                  builder: (_) => VoteQrSheetScreen(eventId: widget.eventId, contestTitle: c.title, entries: byNumber),
                )),
              ),
              if (!c.ended)
                _ToolRow(
                  icon: AppIcons.userPlus,
                  title: 'Add a car by @handle',
                  subtitle: 'Goes straight in with the next number.',
                  busy: _busy.contains('add'),
                  onTap: _add,
                ),

              // ---- waiting
              if (pending.isNotEmpty) ...[
                const SizedBox(height: 16),
                _Label('WAITING (${pending.length})'),
                for (final e in pending)
                  _EntryRow(
                    entry: e,
                    trailing: _busy.contains(e.id)
                        ? const Padding(padding: EdgeInsets.all(12), child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)))
                        : Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(tooltip: 'Reject', onPressed: () => _review(e, false), icon: Icon(AppIcons.x, color: AppColors.textSecondary)),
                              IconButton.filled(tooltip: 'Approve', onPressed: () => _review(e, true), icon: const Icon(AppIcons.check)),
                            ],
                          ),
                  ),
              ],

              // ---- in the vote, live
              const SizedBox(height: 16),
              _Label(c.ended ? 'RESULTS' : 'IN THE VOTE · LIVE'),
              if (ranked.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    c.membersEnter ? 'No cars yet. Members enter from the vote page, or add one by @handle.' : 'No cars yet. Add them by @handle.',
                    style: TextStyle(color: AppColors.textSecondary),
                  ),
                ),
              for (final r in ranked)
                _EntryRow(
                  entry: r.entry,
                  place: r.place,
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('${r.entry.votes ?? 0}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                      const SizedBox(width: 3),
                      Icon(AppIcons.heartFill, size: 14, color: AppColors.brand),
                      if (!c.ended)
                        _busy.contains(r.entry.id)
                            ? const Padding(padding: EdgeInsets.all(12), child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)))
                            : IconButton(tooltip: 'Take out', onPressed: () => _remove(r.entry), icon: Icon(AppIcons.minus, size: 18, color: AppColors.textSecondary)),
                    ],
                  ),
                ),
              const SizedBox(height: 10),
              Text(
                'Only checked-in members can vote, once each. Members see the counts when you close the vote.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: AppColors.textMuted, height: 1.35),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(text, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, letterSpacing: 1, color: AppColors.textSecondary)),
      );
}

class _ToolRow extends StatelessWidget {
  const _ToolRow({required this.icon, required this.title, required this.subtitle, required this.onTap, this.busy = false});
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool busy;

  @override
  Widget build(BuildContext context) => ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 4),
        leading: Container(
          width: 40,
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: AppColors.surfaceGray, shape: BoxShape.circle),
          child: Icon(icon, size: 20, color: AppColors.textPrimary),
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text(subtitle, style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary)),
        trailing: busy ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : Icon(AppIcons.caretRight, size: 16, color: AppColors.textMuted),
        onTap: busy ? null : onTap,
      );
}

class _EntryRow extends StatelessWidget {
  const _EntryRow({required this.entry, required this.trailing, this.place});
  final ContestEntry entry;
  final Widget trailing;
  final int? place;

  @override
  Widget build(BuildContext context) {
    final e = entry;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          if (place != null)
            SizedBox(
              width: 28,
              child: Text('$place', textAlign: TextAlign.center, style: TextStyle(fontFamily: AppFonts.display, fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.textSecondary)),
            ),
          SizedBox(
            width: 72,
            child: AspectRatio(
              aspectRatio: 4 / 3,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ContestCarImage(entry: e, radius: AppRadius.sm),
                  if (e.number != null) Positioned(left: 3, top: 3, child: EntryNumberBadge(number: e.number, size: 11)),
                ],
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(e.carName, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800)),
                Text(e.handle.isEmpty ? e.ownerName : e.handle, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary)),
              ],
            ),
          ),
          trailing,
        ],
      ),
    );
  }
}

/// Search any @handle.
class _HandlePicker extends ConsumerStatefulWidget {
  const _HandlePicker();

  @override
  ConsumerState<_HandlePicker> createState() => _HandlePickerState();
}

class _HandlePickerState extends ConsumerState<_HandlePicker> {
  final _q = TextEditingController();
  Timer? _debounce;
  List<Profile> _results = const [];
  bool _searching = false;

  @override
  void dispose() {
    _debounce?.cancel();
    _q.dispose();
    super.dispose();
  }

  void _onChanged(String v) {
    _debounce?.cancel();
    if (v.trim().replaceAll('@', '').length < 2) {
      setState(() => _results = const []);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 300), () async {
      if (!mounted) return;
      setState(() => _searching = true);
      try {
        final r = await ref.read(organizerRepositoryProvider).searchUsers(v);
        if (mounted) setState(() => _results = r);
      } catch (_) {
        // keep the last results
      } finally {
        if (mounted) setState(() => _searching = false);
      }
    });
  }

  @override
  Widget build(BuildContext context) => SafeArea(
        child: Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
          child: SizedBox(
            height: MediaQuery.sizeOf(context).height * 0.7,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: TextField(
                    controller: _q,
                    autofocus: true,
                    onChanged: _onChanged,
                    decoration: InputDecoration(
                      hintText: 'Their @handle',
                      prefixIcon: const Icon(AppIcons.magnifyingGlass, size: 20),
                      suffixIcon: _searching ? const Padding(padding: EdgeInsets.all(14), child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))) : null,
                      isDense: true,
                    ),
                  ),
                ),
                Expanded(
                  child: _results.isEmpty
                      ? (_q.text.trim().replaceAll('@', '').length < 2
                          ? Center(child: Text('Type a handle to find them.', style: TextStyle(color: AppColors.textSecondary)))
                          : const EmptyState(titi: TitiPose.binoculars, title: 'No one found.'))
                      : ListView.builder(
                          itemCount: _results.length,
                          itemBuilder: (_, i) {
                            final p = _results[i];
                            return ListTile(
                              leading: UserAvatar(url: p.avatarUrl, name: p.displayName ?? p.username, seed: p.id, size: 40),
                              title: Text(p.displayName ?? '@${p.username}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
                              subtitle: Text('@${p.username ?? ''}', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary)),
                              trailing: Icon(AppIcons.plusCircle, color: AppColors.textPrimary),
                              onTap: () => Navigator.pop(context, p),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        ),
      );
}

/// Create or edit the vote: name, about, when it opens and closes, and
/// whether members can enter their own car.
class _ContestFormScreen extends ConsumerStatefulWidget {
  const _ContestFormScreen({required this.eventId, this.contest});
  final String eventId;
  final Contest? contest;

  @override
  ConsumerState<_ContestFormScreen> createState() => _ContestFormScreenState();
}

class _ContestFormScreenState extends ConsumerState<_ContestFormScreen> {
  late final _title = TextEditingController(text: widget.contest?.title ?? "People's Choice");
  late final _about = TextEditingController(text: widget.contest?.about ?? '');
  late DateTime? _opensAt = widget.contest?.opensAt;
  late DateTime? _closesAt = widget.contest?.closesAt;
  late bool _membersEnter = widget.contest?.membersEnter ?? true;
  bool _busy = false;

  bool get _editing => widget.contest != null;

  @override
  void dispose() {
    _title.dispose();
    _about.dispose();
    super.dispose();
  }

  Future<DateTime?> _pick(DateTime initial, String title) {
    final ev = ref.read(eventDetailProvider(widget.eventId)).value?.event;
    return showWheelPicker(
      context,
      initial: initial,
      mode: CupertinoDatePickerMode.dateAndTime,
      min: DateTime.now(),
      max: ev?.closesAt.add(const Duration(days: 2)),
      title: title,
    );
  }

  Future<void> _save() async {
    final title = _title.text.trim();
    if (title.length < 2) {
      _snack('Give the vote a name.');
      return;
    }
    if (_opensAt != null && _closesAt != null && !_closesAt!.isAfter(_opensAt!)) {
      _snack('The vote has to close after it opens.');
      return;
    }
    setState(() => _busy = true);
    try {
      await ref.read(contestActionsProvider).save(
            eventId: widget.eventId,
            contestId: widget.contest?.id,
            title: title,
            about: _about.text.trim().isEmpty ? null : _about.text.trim(),
            opensAt: _opensAt,
            closesAt: _closesAt,
            membersEnter: _membersEnter,
          );
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      _snack(friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _snack(String m) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(m)));

  @override
  Widget build(BuildContext context) {
    final ev = ref.watch(eventDetailProvider(widget.eventId)).value?.event;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(AppIcons.arrowLeft), onPressed: () => Navigator.of(context).pop()),
        title: Text(_editing ? 'Edit vote' : 'New vote'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
        children: [
          TextField(
            controller: _title,
            maxLength: 80,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(labelText: 'Name', hintText: "e.g. People's Choice", counterText: ''),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _about,
            maxLength: 500,
            maxLines: 3,
            minLines: 1,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(labelText: 'About (optional)', hintText: 'e.g. Winner gets a trophy on stage at 6 PM', counterText: ''),
          ),
          const SizedBox(height: 16),
          const _Label('WHEN'),
          _PickRow(
            icon: AppIcons.play,
            label: 'Voting opens',
            value: _opensAt == null ? 'Now' : formatEventDate(_opensAt!),
            onTap: () async {
              final t = await _pick(_opensAt ?? ev?.startsAt ?? DateTime.now().add(const Duration(minutes: 5)), 'Voting opens');
              if (t != null) setState(() => _opensAt = t);
            },
            onClear: _opensAt == null ? null : () => setState(() => _opensAt = null),
          ),
          _PickRow(
            icon: AppIcons.flagCheckered,
            label: 'Voting closes',
            value: _closesAt == null ? 'When I close it' : formatEventDate(_closesAt!),
            onTap: () async {
              final fallback = ev?.closesAt.subtract(const Duration(hours: 1));
              final t = await _pick(
                _closesAt ?? (fallback != null && fallback.isAfter(DateTime.now()) ? fallback : DateTime.now().add(const Duration(hours: 2))),
                'Voting closes',
              );
              if (t != null) setState(() => _closesAt = t);
            },
            onClear: _closesAt == null ? null : () => setState(() => _closesAt = null),
          ),
          const SizedBox(height: 12),
          const _Label('CARS'),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _membersEnter,
            onChanged: (v) => setState(() => _membersEnter = v),
            title: const Text('Members can enter their car', style: TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text(
              _membersEnter ? 'You approve each one. You can also add cars by @handle.' : 'Only you add cars, by @handle.',
              style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
            ),
          ),
          const SizedBox(height: 24),
          PrimaryButton(label: _editing ? 'Save changes' : 'Open the vote', loading: _busy, onPressed: _save),
          const SizedBox(height: 10),
          Text(
            'Checked-in members vote once. Votes never give lucky draw entries.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: AppColors.textMuted, height: 1.35),
          ),
        ],
      ),
    );
  }
}

class _PickRow extends StatelessWidget {
  const _PickRow({required this.icon, required this.label, required this.value, required this.onTap, this.onClear});
  final IconData icon;
  final String label;
  final String value;
  final VoidCallback onTap;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(
            children: [
              Icon(icon, size: 20, color: AppColors.textSecondary),
              const SizedBox(width: 10),
              Expanded(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600))),
              const SizedBox(width: 8),
              Flexible(
                child: Text(value, textAlign: TextAlign.end, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
              ),
              if (onClear != null)
                IconButton(tooltip: 'Clear', visualDensity: VisualDensity.compact, icon: const Icon(AppIcons.x, size: 18), onPressed: onClear)
              else
                Icon(AppIcons.caretRight, size: 16, color: AppColors.textMuted),
            ],
          ),
        ),
      );
}
