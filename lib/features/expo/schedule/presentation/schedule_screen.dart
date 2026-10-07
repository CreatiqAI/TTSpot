import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/pop_or_home.dart';
import '../../../../core/theme/app_icons.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/titi.dart';
import '../../../../core/utils/dates.dart';
import '../../../../core/utils/friendly_error.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../floorplan/application/floorplan_providers.dart';
import '../../expo_routes.dart';
import '../application/agenda_providers.dart';
import '../domain/agenda.dart';

/// Members: the stage schedule with "Remind me".
class ScheduleScreen extends ConsumerWidget {
  const ScheduleScreen({super.key, required this.eventId});
  final String eventId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final host = ref.watch(isMeetHostProvider(eventId)).value ?? false;
    return HomeOnBack(
      child: Scaffold(
        appBar: AppBar(
          leading: const AppBackButton(),
          title: const Text('Schedule'),
          actions: [
            if (host)
              IconButton(tooltip: 'Edit schedule', icon: const Icon(AppIcons.pencilSimple), onPressed: () => context.push(ExpoRoutes.scheduleEditor(eventId))),
          ],
        ),
        body: RefreshIndicator(
          onRefresh: () => ref.refresh(eventAgendaProvider(eventId).future),
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [ScheduleBody(eventId: eventId)],
          ),
        ),
      ),
    );
  }
}

/// The schedule by day, with NOW / NEXT and the reminder bells. Slivers, for
/// a CustomScrollView: the Schedule screen and the event page's Schedule tab.
class ScheduleBody extends ConsumerStatefulWidget {
  const ScheduleBody({super.key, required this.eventId});
  final String eventId;

  @override
  ConsumerState<ScheduleBody> createState() => _ScheduleBodyState();
}

class _ScheduleBodyState extends ConsumerState<ScheduleBody> {
  Timer? _tick;

  /// Bell taps shown straight away, before the list refetches.
  final Map<String, bool> _pending = {};
  final Set<String> _busy = {};

  @override
  void initState() {
    super.initState();
    // "Now" and "Next" move with the clock.
    _tick = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  Future<void> _toggle(AgendaItem item) async {
    if (_busy.contains(item.id)) return;
    final want = !(_pending[item.id] ?? item.reminderOn);
    setState(() {
      _busy.add(item.id);
      _pending[item.id] = want;
    });
    try {
      final on = await ref.read(agendaActionsProvider).toggleReminder(widget.eventId, item.id);
      if (!mounted) return;
      setState(() => _pending[item.id] = on);
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(on ? "We'll remind you 10 min before." : 'Reminder off.')));
    } catch (e) {
      if (!mounted) return;
      setState(() => _pending.remove(item.id));
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(friendlyError(e))));
    } finally {
      if (mounted) setState(() => _busy.remove(item.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final agenda = ref.watch(eventAgendaProvider(widget.eventId));
    final host = ref.watch(isMeetHostProvider(widget.eventId)).value ?? false;
    return agenda.when(
      skipLoadingOnRefresh: true,
      skipLoadingOnReload: true,
      loading: () => const SliverToBoxAdapter(
        child: Padding(padding: EdgeInsets.symmetric(vertical: 48), child: Center(child: CircularProgressIndicator(strokeWidth: 2))),
      ),
      error: (e, _) => SliverToBoxAdapter(child: Padding(padding: const EdgeInsets.all(32), child: Text(friendlyError(e), textAlign: TextAlign.center))),
      data: (items) {
        if (items.isEmpty) {
          return SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.only(top: 36),
              child: EmptyState(
                titi: TitiPose.calendar,
                title: 'No schedule yet',
                subtitle: "The organizer hasn't posted one. Check back closer to the day.",
                actionLabel: host ? 'Add the first item' : null,
                onAction: host ? () => context.push(ExpoRoutes.scheduleEditor(widget.eventId)) : null,
              ),
            ),
          );
        }
        final now = DateTime.now();
        final phases = agendaPhases(items, now);
        final days = groupAgendaByDay(items);
        return SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 40),
          sliver: SliverList.list(
            children: [
              for (final d in days) ...[
                Padding(
                  padding: const EdgeInsets.only(top: 12, bottom: 8),
                  child: Text(
                    (isSameDay(d.day, now) ? 'Today · ${formatDate(d.day)}' : formatDate(d.day)).toUpperCase(),
                    style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, letterSpacing: 1, color: AppColors.textSecondary),
                  ),
                ),
                for (final i in d.items)
                  AgendaTile(
                    item: i,
                    phase: phases[i.id] ?? AgendaPhase.later,
                    reminderOn: _pending[i.id] ?? i.reminderOn,
                    busy: _busy.contains(i.id),
                    onToggle: () => _toggle(i),
                    onPlace: i.pinLevelId == null ? null : () => context.push('/event/${widget.eventId}/floorplan?level=${i.pinLevelId}'),
                  ),
              ],
            ],
          ),
        );
      },
    );
  }
}

/// One schedule item: time, title, place, about and the bell.
class AgendaTile extends StatelessWidget {
  const AgendaTile({super.key, required this.item, required this.phase, required this.reminderOn, this.busy = false, this.onToggle, this.onPlace, this.trailing});
  final AgendaItem item;
  final AgendaPhase phase;
  final bool reminderOn;
  final bool busy;

  /// Null hides the bell (hosts' editor).
  final VoidCallback? onToggle;

  /// Opens the floor plan at the pin's level; null = plain text.
  final VoidCallback? onPlace;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final i = item;
    final isNow = phase == AgendaPhase.now;
    final isNext = phase == AgendaPhase.next;
    final past = phase == AgendaPhase.past;
    final started = phase == AgendaPhase.now || past;
    return Opacity(
      opacity: past ? 0.5 : 1,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
        decoration: BoxDecoration(
          color: isNow ? AppColors.brand.withValues(alpha: 0.06) : AppColors.surfaceGray,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(color: isNow ? AppColors.brand : Colors.transparent, width: 1.5),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      if (isNow || isNext)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(color: isNow ? AppColors.brand : AppColors.ink, borderRadius: BorderRadius.circular(AppRadius.pill)),
                          child: Text(isNow ? 'NOW' : 'NEXT', style: const TextStyle(color: Colors.white, fontSize: 10.5, fontWeight: FontWeight.w800, letterSpacing: 0.8)),
                        ),
                      Text(
                        agendaTimeRange(i.startsAt, i.endsAt),
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: isNow ? AppColors.brand : AppColors.textSecondary),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(i.title, maxLines: 3, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, height: 1.2)),
                  if (i.place != null) ...[
                    const SizedBox(height: 4),
                    _Place(item: i, onTap: onPlace),
                  ],
                  if (i.about != null) ...[
                    const SizedBox(height: 6),
                    Text(i.about!, style: TextStyle(fontSize: 13.5, height: 1.4, color: AppColors.textSecondary)),
                  ],
                  if (onToggle != null && !started) ...[
                    const SizedBox(height: 8),
                    _Bell(on: reminderOn, busy: busy, onTap: onToggle!),
                  ],
                ],
              ),
            ),
            ?trailing,
          ],
        ),
      ),
    );
  }
}

class _Place extends StatelessWidget {
  const _Place({required this.item, this.onTap});
  final AgendaItem item;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final color = onTap == null ? AppColors.textSecondary : AppColors.textPrimary;
    final row = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(item.pinKind?.icon ?? AppIcons.mapPin, size: 16, color: item.pinKind?.color ?? AppColors.textSecondary),
        const SizedBox(width: 5),
        Flexible(
          child: Text(
            item.place!,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w700,
              color: color,
              decoration: onTap == null ? null : TextDecoration.underline,
              decorationColor: AppColors.textMuted,
            ),
          ),
        ),
        if (onTap != null) ...[
          const SizedBox(width: 2),
          Icon(AppIcons.caretRight, size: 14, color: AppColors.textMuted),
        ],
      ],
    );
    if (onTap == null) return row;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.sm),
      child: Padding(padding: const EdgeInsets.symmetric(vertical: 2), child: row),
    );
  }
}

class _Bell extends StatelessWidget {
  const _Bell({required this.on, required this.busy, required this.onTap});
  final bool on;
  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
        color: on ? AppColors.ink : AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        child: InkWell(
          onTap: busy ? null : onTap,
          borderRadius: BorderRadius.circular(AppRadius.pill),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 6, 12, 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(on ? AppIcons.bellRinging : AppIcons.bell, size: 16, color: on ? Colors.white : AppColors.textPrimary),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    on ? 'Reminder on' : 'Remind me',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: on ? Colors.white : AppColors.textPrimary),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
}
