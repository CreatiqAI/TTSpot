import 'package:flutter/cupertino.dart' show CupertinoDatePickerMode;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_icons.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/titi.dart';
import '../../../../core/utils/dates.dart';
import '../../../../core/utils/friendly_error.dart';
import '../../../../core/utils/open_external.dart' show confirmSheet;
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/primary_button.dart';
import '../../../../core/widgets/wheel_picker.dart';
import '../../../events/application/event_providers.dart';
import '../../../floorplan/application/floorplan_providers.dart';
import '../../../floorplan/domain/floorplan.dart';
import '../application/agenda_providers.dart';
import '../domain/agenda.dart';
import 'schedule_screen.dart' show AgendaTile;

/// Host: add and edit schedule items.
class ScheduleEditorScreen extends ConsumerWidget {
  const ScheduleEditorScreen({super.key, required this.eventId});
  final String eventId;

  Future<void> _edit(BuildContext context, List<AgendaItem> items, [AgendaItem? item]) => showModalBottomSheet<void>(
        useRootNavigator: true,
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (_) => AgendaItemForm(eventId: eventId, item: item, after: items.isEmpty ? null : items.last),
      );

  Future<void> _delete(BuildContext context, WidgetRef ref, AgendaItem item) async {
    final ok = await confirmSheet(context, title: 'Delete "${item.title}"?', body: 'Members lose it from the schedule and its reminders.', confirm: 'Delete', icon: AppIcons.trash);
    if (!ok) return;
    try {
      await ref.read(agendaActionsProvider).delete(eventId, item.id);
    } catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e))));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final agenda = ref.watch(eventAgendaProvider(eventId));
    final items = agenda.value ?? const <AgendaItem>[];
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(AppIcons.arrowLeft), onPressed: () => context.pop()),
        title: const Text('Schedule'),
      ),
      floatingActionButton: items.isEmpty
          ? null
          : FloatingActionButton.extended(
              onPressed: () => _edit(context, items),
              icon: const Icon(AppIcons.plus),
              label: const Text('Add item'),
            ),
      body: agenda.when(
        skipLoadingOnRefresh: true,
        skipLoadingOnReload: true,
        loading: () => const Center(child: CircularProgressIndicator(strokeWidth: 2)),
        error: (e, _) => Center(child: Padding(padding: const EdgeInsets.all(32), child: Text(friendlyError(e), textAlign: TextAlign.center))),
        data: (items) {
          if (items.isEmpty) {
            return ListView(
              children: [
                const SizedBox(height: 60),
                EmptyState(
                  titi: TitiPose.calendar,
                  title: 'Put your stage on the app',
                  subtitle: 'Add shows, talks and the lucky draw. Members tap "Remind me" and get a push 10 min before.',
                  actionLabel: 'Add the first item',
                  onAction: () => _edit(context, items),
                ),
              ],
            );
          }
          final now = DateTime.now();
          final phases = agendaPhases(items, now);
          return RefreshIndicator(
            onRefresh: () => ref.refresh(eventAgendaProvider(eventId).future),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 100),
              children: [
                for (final d in groupAgendaByDay(items)) ...[
                  Padding(
                    padding: const EdgeInsets.only(top: 12, bottom: 8),
                    child: Text(formatDate(d.day).toUpperCase(), style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, letterSpacing: 1, color: AppColors.textSecondary)),
                  ),
                  for (final i in d.items)
                    GestureDetector(
                      onTap: () => _edit(context, items, i),
                      child: AgendaTile(
                        item: i,
                        phase: phases[i.id] ?? AgendaPhase.later,
                        reminderOn: false,
                        trailing: Column(
                          children: [
                            PopupMenuButton<String>(
                              icon: Icon(AppIcons.dotsThreeVertical, color: AppColors.textSecondary),
                              onSelected: (v) => v == 'edit' ? _edit(context, items, i) : _delete(context, ref, i),
                              itemBuilder: (_) => const [
                                PopupMenuItem(value: 'edit', child: Text('Edit')),
                                PopupMenuItem(value: 'delete', child: Text('Delete')),
                              ],
                            ),
                            if ((i.reminderCount ?? 0) > 0)
                              Tooltip(
                                message: 'Reminders',
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(AppIcons.bell, size: 13, color: AppColors.textSecondary),
                                    const SizedBox(width: 2),
                                    Text('${i.reminderCount}', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textSecondary)),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                ],
                const SizedBox(height: 8),
                Text('Tap an item to edit it. Members with "Remind me" on get a push 10 min before it starts.',
                    style: TextStyle(fontSize: 12, color: AppColors.textMuted, height: 1.35)),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// The add / edit sheet for one item.
class AgendaItemForm extends ConsumerStatefulWidget {
  const AgendaItemForm({super.key, required this.eventId, this.item, this.after});
  final String eventId;
  final AgendaItem? item;

  /// The last item, so a new one starts where it ends.
  final AgendaItem? after;

  @override
  ConsumerState<AgendaItemForm> createState() => _AgendaItemFormState();
}

class _AgendaItemFormState extends ConsumerState<AgendaItemForm> {
  late final _title = TextEditingController(text: widget.item?.title ?? '');
  late final _about = TextEditingController(text: widget.item?.about ?? '');
  late DateTime? _start = widget.item?.startsAt;
  late DateTime? _end = widget.item?.endsAt;
  late String? _pinId = widget.item?.pinId;
  late String? _placeText = widget.item?.placeLabel;
  bool _busy = false;

  @override
  void dispose() {
    _title.dispose();
    _about.dispose();
    super.dispose();
  }

  static DateTime _round5(DateTime t) => DateTime(t.year, t.month, t.day, t.hour, t.minute - t.minute % 5);

  DateTime _defaultStart() {
    final ev = ref.read(eventDetailProvider(widget.eventId)).value?.event;
    final after = widget.after;
    if (after != null) return _round5(after.effectiveEnd);
    if (ev != null) return _round5(ev.startsAt);
    return _round5(DateTime.now().add(const Duration(minutes: 30)));
  }

  Future<void> _pickStart() async {
    final ev = ref.read(eventDetailProvider(widget.eventId)).value?.event;
    final max = ev?.closesAt.add(const Duration(days: 1));
    var initial = _round5(_start ?? _defaultStart());
    if (max != null && initial.isAfter(max)) initial = _round5(max);
    final t = await showWheelPicker(context, initial: initial, mode: CupertinoDatePickerMode.dateAndTime, max: max, title: 'Starts');
    if (t == null || !mounted) return;
    setState(() {
      // Keep the length when the start moves.
      final len = _start != null && _end != null ? _end!.difference(_start!) : null;
      _start = t;
      if (len != null) _end = t.add(len);
    });
  }

  Future<void> _pickEnd() async {
    final start = _start;
    if (start == null) return;
    final initial = _round5(_end ?? start.add(AgendaItem.defaultLength));
    final t = await showWheelPicker(context, initial: initial, mode: CupertinoDatePickerMode.time, title: 'Ends');
    if (t == null || !mounted) return;
    var end = DateTime(start.year, start.month, start.day, t.hour, t.minute);
    if (!end.isAfter(start)) end = end.add(const Duration(days: 1)); // runs past midnight
    setState(() => _end = end);
  }

  Future<void> _pickPlace(List<FloorLevel> levels) async {
    final r = await showModalBottomSheet<({String? pinId, String? text})>(
      useRootNavigator: true,
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _PlacePicker(levels: levels, text: _placeText),
    );
    if (r == null || !mounted) return;
    setState(() {
      _pinId = r.pinId;
      _placeText = r.text;
    });
  }

  Future<void> _save() async {
    final title = _title.text.trim();
    final start = _start;
    if (title.isEmpty) {
      _snack('Give it a title.');
      return;
    }
    if (start == null) {
      _snack('Pick a start time.');
      return;
    }
    setState(() => _busy = true);
    try {
      await ref.read(agendaActionsProvider).save(
            eventId: widget.eventId,
            itemId: widget.item?.id,
            title: title,
            about: _about.text.trim().isEmpty ? null : _about.text.trim(),
            startsAt: start,
            endsAt: _end,
            pinId: _pinId,
            place: _placeText,
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
    final levels = ref.watch(floorLevelsProvider(widget.eventId)).value ?? const <FloorLevel>[];
    FloorPin? pin;
    for (final l in levels) {
      for (final p in l.pins) {
        if (p.id == _pinId) pin = p;
      }
    }
    final placeValue = _placeText?.trim().isNotEmpty == true ? _placeText!.trim() : pin?.title ?? (_pinId != null ? 'Floor pin' : 'Pick a place');
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.88),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            children: [
              Text(widget.item == null ? 'New schedule item' : 'Edit schedule item', style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
              const SizedBox(height: 12),
              TextField(
                controller: _title,
                maxLength: 80,
                autofocus: widget.item == null,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(labelText: 'Title', hintText: 'e.g. Drift show', counterText: ''),
              ),
              const SizedBox(height: 8),
              _Row(icon: AppIcons.calendarBlank, label: 'Starts', value: _start == null ? 'Pick a time' : formatEventDate(_start!), onTap: _pickStart),
              _Row(
                icon: AppIcons.clock,
                label: 'Ends',
                value: _end == null ? 'Optional' : formatTime(_end!),
                onTap: _start == null ? null : _pickEnd,
                trailing: _end == null ? null : IconButton(tooltip: 'No end time', icon: const Icon(AppIcons.x, size: 18), onPressed: () => setState(() => _end = null)),
              ),
              _Row(
                icon: pin?.kind.icon ?? AppIcons.mapPin,
                label: 'Where',
                value: placeValue,
                onTap: () => _pickPlace(levels),
                trailing: _pinId == null && (_placeText ?? '').isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Clear',
                        icon: const Icon(AppIcons.x, size: 18),
                        onPressed: () => setState(() {
                          _pinId = null;
                          _placeText = null;
                        }),
                      ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _about,
                maxLength: 500,
                minLines: 2,
                maxLines: 5,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(labelText: 'About (optional)', hintText: "Who's on, what to expect"),
              ),
              const SizedBox(height: 12),
              PrimaryButton(label: widget.item == null ? 'Add to schedule' : 'Save changes', loading: _busy, onPressed: _save),
            ],
          ),
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.icon, required this.label, required this.value, required this.onTap, this.trailing});
  final IconData icon;
  final String label;
  final String value;
  final VoidCallback? onTap;
  final Widget? trailing;

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
              Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  value,
                  textAlign: TextAlign.right,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontWeight: FontWeight.w700, color: onTap == null ? AppColors.textMuted : AppColors.textPrimary),
                ),
              ),
              ?trailing,
              if (trailing == null) Icon(AppIcons.caretRight, size: 16, color: AppColors.textMuted),
            ],
          ),
        ),
      );
}

/// Pins first (stage and zones on top), filtered by what's typed; or use the
/// typed text as the place.
class _PlacePicker extends StatefulWidget {
  const _PlacePicker({required this.levels, this.text});
  final List<FloorLevel> levels;
  final String? text;

  @override
  State<_PlacePicker> createState() => _PlacePickerState();
}

class _PlacePickerState extends State<_PlacePicker> {
  late final _q = TextEditingController(text: widget.text ?? '');

  static const _order = [PinKind.stage, PinKind.zone, PinKind.luckyDraw, PinKind.entrance, PinKind.info, PinKind.food, PinKind.parking];

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  int _rank(PinKind k) {
    final i = _order.indexOf(k);
    return i < 0 ? (k == PinKind.booth ? 99 : _order.length) : i;
  }

  @override
  Widget build(BuildContext context) {
    final q = _q.text.trim();
    final many = widget.levels.length > 1;
    final pins = [
      for (final l in widget.levels)
        for (final p in l.pins)
          if (p.kind != PinKind.toilet && p.kind != PinKind.lift && p.kind != PinKind.ramp) (pin: p, level: l),
    ]
      ..retainWhere((e) => q.isEmpty || e.pin.title.toLowerCase().contains(q.toLowerCase()) || e.pin.kind.label.toLowerCase().contains(q.toLowerCase()))
      ..sort((a, b) {
        final r = _rank(a.pin.kind).compareTo(_rank(b.pin.kind));
        return r != 0 ? r : a.pin.title.toLowerCase().compareTo(b.pin.title.toLowerCase());
      });
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Text('Where is it?', style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: TextField(
                  controller: _q,
                  maxLength: 60,
                  onChanged: (_) => setState(() {}),
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(
                    hintText: widget.levels.isEmpty ? 'Type a place, e.g. Main stage' : 'Search the floor plan or type a place',
                    prefixIcon: const Icon(AppIcons.magnifyingGlass, size: 18),
                    counterText: '',
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    if (q.isNotEmpty)
                      ListTile(
                        leading: const Icon(AppIcons.textbox),
                        title: Text('Use "$q"', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
                        subtitle: const Text('Not on the floor plan'),
                        onTap: () => Navigator.of(context).pop((pinId: null, text: q)),
                      ),
                    for (final e in pins)
                      ListTile(
                        leading: Icon(e.pin.kind.icon, color: e.pin.kind.color),
                        title: Text(e.pin.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
                        subtitle: Text(many ? '${e.pin.kind.label} · ${e.level.name}' : e.pin.kind.label, maxLines: 1, overflow: TextOverflow.ellipsis),
                        onTap: () => Navigator.of(context).pop((pinId: e.pin.id, text: null)),
                      ),
                    if (pins.isEmpty && q.isEmpty)
                      Padding(
                        padding: const EdgeInsets.all(20),
                        child: Text('No floor plan pins yet. Type a place above.', style: TextStyle(color: AppColors.textSecondary)),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
