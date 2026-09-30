import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/dates.dart';
import '../../../core/utils/friendly_error.dart';
import '../../../core/widgets/primary_button.dart';
import '../../../core/widgets/user_avatar.dart';
import '../application/event_providers.dart';
import '../domain/checkin_row.dart';
import '../domain/event.dart';
import 'event_car_widgets.dart';

/// Host's door list while the meet is live and for a day after. Small meet:
/// every check-in, Here / Not here per row, "Confirm all so far". Big meet:
/// whoever stayed 10+ min is already confirmed; only the exceptions show, with
/// "Confirm the rest".
Future<void> showWhosHereSheet(BuildContext context, Event event) {
  return showModalBottomSheet<void>(
    useRootNavigator: true, // above the shell tab bar
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (_) => _WhosHereSheet(event: event),
  );
}

class _WhosHereSheet extends ConsumerStatefulWidget {
  const _WhosHereSheet({required this.event});
  final Event event;

  @override
  ConsumerState<_WhosHereSheet> createState() => _WhosHereSheetState();
}

class _WhosHereSheetState extends ConsumerState<_WhosHereSheet> {
  final _busy = <String>{};
  bool _allBusy = false;

  void _snack(String msg) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _confirm(CheckinRow r, bool here) async {
    if (_busy.contains(r.userId)) return;
    setState(() => _busy.add(r.userId));
    try {
      await ref.read(eventActionsProvider).hostConfirm(widget.event.id, r.userId, confirmed: here);
    } catch (e) {
      _snack(friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy.remove(r.userId));
    }
  }

  Future<void> _confirmAll() async {
    setState(() => _allBusy = true);
    try {
      final n = await ref.read(eventActionsProvider).hostConfirmAll(widget.event.id);
      _snack(n == 0 ? 'Nothing left to confirm.' : 'Confirmed $n.');
    } catch (e) {
      _snack(friendlyError(e));
    } finally {
      if (mounted) setState(() => _allBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final e = widget.event;
    final mode = ref.watch(meetModeProvider(e.id)).value ?? MeetMode.small;
    final list = ref.watch(hostCheckinListProvider(e.id));
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.7,
        child: list.when(
          loading: () => const Center(child: CircularProgressIndicator(strokeWidth: 2)),
          error: (err, _) => Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(friendlyError(err), textAlign: TextAlign.center))),
          data: (rows) {
            final confirmed = rows.where((r) => r.confirmed).length;
            // Big meets: whoever stayed is settled; the host only sees the rest.
            final shown = mode == MeetMode.big ? rows.where((r) => !r.stayed).toList() : rows;
            final undecided = rows.where((r) => !r.confirmed && !r.rejected).length;
            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
                  child: Row(
                    children: [
                      Expanded(child: Text('Who\'s here · ${rows.length}', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800))),
                      Text('$confirmed confirmed', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: confirmed == 0 ? AppColors.textMuted : AppColors.success)),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(color: AppColors.surfaceGray, borderRadius: BorderRadius.circular(AppRadius.pill)),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(mode == MeetMode.big ? AppIcons.usersFour : AppIcons.listChecks, size: 14, color: AppColors.textSecondary),
                          const SizedBox(width: 6),
                          Text(mode.label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
                        ],
                      ),
                    ),
                  ),
                ),
                Divider(height: 1, color: AppColors.divider),
                Expanded(
                  child: shown.isEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Text(
                              rows.isEmpty
                                  ? 'Nobody has checked in yet. Show your QR or let members tap "I\'m here".'
                                  : 'Everyone who checked in stayed 10+ minutes and is confirmed.',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: AppColors.textSecondary, height: 1.4),
                            ),
                          ),
                        )
                      : ListView.builder(
                          itemCount: shown.length,
                          itemBuilder: (_, i) => _Row(
                            row: shown[i],
                            busy: _busy.contains(shown[i].userId),
                            onHere: () => _confirm(shown[i], true),
                            onNotHere: () => _confirm(shown[i], false),
                            onOpen: () {
                              final router = GoRouter.of(context);
                              Navigator.pop(context);
                              router.push(Routes.profile(shown[i].userId));
                            },
                          ),
                        ),
                ),
                if (rows.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 10, 20, 12),
                    child: PrimaryButton(
                      label: mode == MeetMode.big ? 'Confirm the rest' : 'Confirm all so far',
                      loading: _allBusy,
                      onPressed: undecided == 0 ? null : _confirmAll,
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.row, required this.busy, required this.onHere, required this.onNotHere, required this.onOpen});
  final CheckinRow row;
  final bool busy;
  final VoidCallback onHere;
  final VoidCallback onNotHere;
  final VoidCallback onOpen;

  String get _via => switch (row.source) {
        'qr' => 'scanned QR',
        'auto' => 'auto',
        'organizer' => 'by host',
        _ => 'tapped in',
      };

  @override
  Widget build(BuildContext context) {
    final detail = [
      '${formatTime(row.checkedInAt)} · $_via',
      row.stayed ? 'stayed ${row.stayedMin} min' : (row.stayedMin > 0 ? 'seen ${row.stayedMin} min' : 'not seen since'),
    ].join(' · ');
    return ListTile(
      onTap: onOpen,
      leading: UserAvatar(url: row.avatarUrl, name: row.name, seed: row.userId, size: 42),
      title: Text(row.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // the car they brought (their pick, else their default car)
          if (row.car != null) EventCarLine(title: row.car!, cover: row.carCover, bodyStyle: row.carBodyStyle),
          Text(detail, maxLines: 2, style: TextStyle(fontSize: 12, color: row.stayed ? AppColors.success : AppColors.textSecondary)),
        ],
      ),
      trailing: busy
          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _Toggle(label: 'Here', icon: AppIcons.check, on: row.confirmed, color: AppColors.success, onTap: row.confirmed ? null : onHere),
                const SizedBox(width: 6),
                _Toggle(label: 'Not here', icon: AppIcons.x, on: row.rejected, color: AppColors.danger, onTap: row.rejected ? null : onNotHere),
              ],
            ),
    );
  }
}

/// Small pill; filled in its colour when that answer is the current one.
class _Toggle extends StatelessWidget {
  const _Toggle({required this.label, required this.icon, required this.on, required this.color, required this.onTap});
  final String label;
  final IconData icon;
  final bool on;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final fg = on ? Colors.white : AppColors.textPrimary;
    return Material(
      color: on ? color : AppColors.surfaceGray,
      borderRadius: BorderRadius.circular(AppRadius.pill),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.pill),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: fg),
              const SizedBox(width: 4),
              Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: fg)),
            ],
          ),
        ),
      ),
    );
  }
}
