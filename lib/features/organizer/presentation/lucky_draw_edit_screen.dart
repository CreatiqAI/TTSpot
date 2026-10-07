import 'package:flutter/cupertino.dart' show CupertinoDatePickerMode;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_images.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/dates.dart';
import '../../../core/utils/friendly_error.dart';
import '../../../core/widgets/primary_button.dart';
import '../../../core/widgets/wheel_picker.dart';
import '../../events/application/event_providers.dart';
import '../application/organizer_providers.dart';
import '../domain/organizer_models.dart';

/// Create or edit a lucky draw: name, time, entry cut-off, prizes, and the
/// claim rules (must be present, claim window).
class LuckyDrawEditScreen extends ConsumerStatefulWidget {
  const LuckyDrawEditScreen({super.key, required this.eventId, this.drawId});
  final String eventId;
  final String? drawId;

  @override
  ConsumerState<LuckyDrawEditScreen> createState() => _LuckyDrawEditScreenState();
}

class _PrizeRow {
  _PrizeRow({String name = '', this.quantity = 1}) : name = TextEditingController(text: name);
  final TextEditingController name;
  int quantity;
}

class _LuckyDrawEditScreenState extends ConsumerState<LuckyDrawEditScreen> {
  final _title = TextEditingController(text: 'Lucky draw');
  DateTime? _drawAt;
  DateTime? _cutoffAt; // null = entries close at the draw
  bool _mustBePresent = true;
  int _claimMinutes = 15;
  int? _rollCall; // minutes before the draw; null = off
  final List<_PrizeRow> _prizes = [_PrizeRow()];
  bool _loaded = false;
  bool _busy = false;

  bool get _editing => widget.drawId != null;

  @override
  void initState() {
    super.initState();
    if (_editing) _load();
  }

  Future<void> _load() async {
    try {
      final d = await ref.read(drawProvider(widget.drawId!).future);
      if (d == null || !mounted) return;
      setState(() {
        _title.text = d.title;
        _drawAt = d.drawAt;
        _cutoffAt = d.cutoffAt.isBefore(d.drawAt) ? d.cutoffAt : null;
        _mustBePresent = d.mustBePresent;
        _claimMinutes = d.claimMinutes;
        _rollCall = d.presenceMinutes;
        for (final p in _prizes) {
          p.name.dispose();
        }
        _prizes
          ..clear()
          ..addAll(d.prizes.map((p) => _PrizeRow(name: p.name, quantity: p.quantity)));
        if (_prizes.isEmpty) _prizes.add(_PrizeRow());
        _loaded = true;
      });
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e))));
    }
  }

  @override
  void dispose() {
    _title.dispose();
    for (final p in _prizes) {
      p.name.dispose();
    }
    super.dispose();
  }

  Future<DateTime?> _pick(DateTime initial, String title, {DateTime? max}) {
    final ev = ref.read(eventDetailProvider(widget.eventId)).value?.event;
    return showWheelPicker(
      context,
      initial: initial,
      mode: CupertinoDatePickerMode.dateAndTime,
      min: DateTime.now().add(const Duration(minutes: 1)),
      max: max ?? ev?.closesAt.add(const Duration(days: 1)),
      title: title,
    );
  }

  DateTime _defaultDrawAt() {
    final ev = ref.read(eventDetailProvider(widget.eventId)).value?.event;
    final now = DateTime.now();
    if (ev != null) {
      // Two hours in, or an hour before the end, whichever is earlier.
      final twoIn = ev.startsAt.add(const Duration(hours: 2));
      final end = ev.closesAt.subtract(const Duration(hours: 1));
      final t = twoIn.isBefore(end) ? twoIn : end;
      if (t.isAfter(now.add(const Duration(minutes: 5)))) return t;
    }
    return now.add(const Duration(minutes: 30));
  }

  Future<void> _save() async {
    final drawAt = _drawAt;
    if (drawAt == null) {
      _snack('Pick when the draw happens.');
      return;
    }
    final prizes = [
      for (final p in _prizes)
        if (p.name.text.trim().isNotEmpty) DrawPrize(name: p.name.text.trim(), quantity: p.quantity),
    ];
    if (prizes.isEmpty) {
      _snack('Add at least one prize.');
      return;
    }
    final roll = _rollCall;
    if (roll != null && _cutoffAt != null && !_cutoffAt!.isAfter(drawAt.subtract(Duration(minutes: roll)))) {
      _snack('Entries close before the roll call opens. Move "Entries close" later or turn roll call off.');
      return;
    }
    setState(() => _busy = true);
    try {
      await ref.read(organizerActionsProvider).saveDraw(
            eventId: widget.eventId,
            drawId: widget.drawId,
            title: _title.text.trim().isEmpty ? 'Lucky draw' : _title.text.trim(),
            drawAt: drawAt,
            cutoffAt: _cutoffAt,
            mustBePresent: _mustBePresent,
            claimMinutes: _claimMinutes,
            prizes: prizes,
            presenceMinutes: _rollCall,
          );
      if (mounted) context.pop();
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
    if (_editing && !_loaded) {
      return Scaffold(
        appBar: AppBar(leading: IconButton(icon: const Icon(AppIcons.arrowLeft), onPressed: () => context.pop()), title: const Text('Edit lucky draw')),
        body: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }
    final winners = _prizes.where((p) => p.name.text.trim().isNotEmpty).fold(0, (s, p) => s + p.quantity);
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(AppIcons.arrowLeft), onPressed: () => context.pop()),
        title: Text(_editing ? 'Edit lucky draw' : 'New lucky draw'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
        children: [
          TextField(
            controller: _title,
            maxLength: 80,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(labelText: 'Name', hintText: 'e.g. Midnight lucky draw', counterText: ''),
          ),
          const SizedBox(height: 16),
          const _Label('WHEN'),
          _PickRow(
            icon: AppIcons.calendarBlank,
            label: 'Draw time',
            value: _drawAt == null ? 'Pick a time' : formatEventDate(_drawAt!),
            onTap: () async {
              final t = await _pick(_drawAt ?? _defaultDrawAt(), 'Draw time');
              if (t != null) {
                setState(() {
                  _drawAt = t;
                  if (_cutoffAt != null && _cutoffAt!.isAfter(t)) _cutoffAt = null;
                });
              }
            },
          ),
          _PickRow(
            icon: AppIcons.hourglass,
            label: 'Entries close',
            value: _cutoffAt == null ? 'At the draw' : formatEventDate(_cutoffAt!),
            onTap: _drawAt == null
                ? null
                : () async {
                    final t = await _pick(_cutoffAt ?? _drawAt!.subtract(const Duration(minutes: 15)), 'Entries close', max: _drawAt);
                    if (t != null) setState(() => _cutoffAt = t.isBefore(_drawAt!) ? t : null);
                  },
            trailing: _cutoffAt == null ? null : IconButton(tooltip: 'At the draw', icon: const Icon(AppIcons.x, size: 18), onPressed: () => setState(() => _cutoffAt = null)),
          ),
          const SizedBox(height: 4),
          Text('Everyone who checks in by scanning the meet QR, or whom you or your crew confirm, before entries close is in. One entry each, free.',
              style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary, height: 1.35)),
          const SizedBox(height: 20),
          const _Label('ROLL CALL'),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _rollCall != null,
            onChanged: (v) => setState(() => _rollCall = v ? 15 : null),
            title: const Text('Roll call', style: TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text("Only people who tap 'I'm here' in time can win.", style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary)),
          ),
          if (_rollCall != null) ...[
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final m in {...kRollCallMinutes, _rollCall!}.toList()..sort())
                  ChoiceChip(label: Text('$m min before'), selected: _rollCall == m, showCheckmark: false, onSelected: (_) => setState(() => _rollCall = m)),
              ],
            ),
            if (_drawAt != null) ...[
              const SizedBox(height: 6),
              Text(
                'Everyone checked in gets a push at ${formatTime(_drawAt!.subtract(Duration(minutes: _rollCall!)))}. Tapping checks they are inside the event area.',
                style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary, height: 1.35),
              ),
            ],
          ],
          const SizedBox(height: 20),
          Row(
            children: [
              const Expanded(child: _Label('PRIZES')),
              Text('$winners winner${winners == 1 ? '' : 's'} + 3 alternates', style: TextStyle(fontSize: 12, color: AppColors.textSecondary, fontWeight: FontWeight.w600)),
            ],
          ),
          for (var i = 0; i < _prizes.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Stack(
                    clipBehavior: Clip.none,
                    children: [
                      AssetThumb(prizeAsset(_prizes[i].name.text)),
                      Positioned(
                        left: -4,
                        top: -4,
                        child: Container(
                          width: 18,
                          height: 18,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(color: AppColors.textPrimary, shape: BoxShape.circle, border: Border.all(color: AppColors.bg, width: 1.5)),
                          child: Text('${i + 1}', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: AppColors.bg)),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: _prizes[i].name,
                      onChanged: (_) => setState(() {}),
                      textCapitalization: TextCapitalization.sentences,
                      maxLength: 80,
                      decoration: InputDecoration(hintText: i == 0 ? 'Grand prize, e.g. Ceramic coating' : 'Prize', counterText: '', isDense: true),
                    ),
                  ),
                  const SizedBox(width: 6),
                  _Stepper(
                    value: _prizes[i].quantity,
                    min: 1,
                    max: 50,
                    onChanged: (v) => setState(() => _prizes[i].quantity = v),
                  ),
                  IconButton(
                    tooltip: 'Remove',
                    onPressed: _prizes.length == 1
                        ? null
                        : () => setState(() {
                              _prizes.removeAt(i).name.dispose();
                            }),
                    icon: Icon(AppIcons.minus, size: 18, color: AppColors.textSecondary),
                  ),
                ],
              ),
            ),
          if (_prizes.length < 20)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(onPressed: () => setState(() => _prizes.add(_PrizeRow())), icon: const Icon(AppIcons.plus, size: 18), label: const Text('Add a prize')),
            ),
          Text('List the grand prize first. On stage it is revealed last.', style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
          const SizedBox(height: 20),
          const _Label('CLAIMING'),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _mustBePresent,
            onChanged: (v) => setState(() => _mustBePresent = v),
            title: const Text('Winners must be present', style: TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text(
              _mustBePresent ? 'Unclaimed prizes pass to the next alternate when the window closes.' : 'Winners collect later; you arrange the handover.',
              style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
            ),
          ),
          if (_mustBePresent) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                const Expanded(child: Text('Claim window', style: TextStyle(fontWeight: FontWeight.w700))),
                _Stepper(value: _claimMinutes, min: 5, max: 240, step: 5, suffix: ' min', onChanged: (v) => setState(() => _claimMinutes = v)),
              ],
            ),
          ],
          const SizedBox(height: 24),
          PrimaryButton(label: _editing ? 'Save changes' : 'Schedule the draw', loading: _busy, onPressed: _save),
          const SizedBox(height: 10),
          Text(
            'Free to enter. TT Spot provides the platform; prizes are provided by you, the organizer. Apple is not a sponsor. Members see these rules on the meet page.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: AppColors.textMuted, height: 1.35),
          ),
        ],
      ),
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

class _PickRow extends StatelessWidget {
  const _PickRow({required this.icon, required this.label, required this.value, required this.onTap, this.trailing});
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
              Expanded(child: Text(label, style: const TextStyle(fontWeight: FontWeight.w600))),
              Text(value, style: TextStyle(fontWeight: FontWeight.w700, color: onTap == null ? AppColors.textMuted : AppColors.textPrimary)),
              ?trailing,
              if (trailing == null) Icon(AppIcons.caretRight, size: 16, color: AppColors.textMuted),
            ],
          ),
        ),
      );
}

class _Stepper extends StatelessWidget {
  const _Stepper({required this.value, required this.min, required this.max, required this.onChanged, this.step = 1, this.suffix = ''});
  final int value;
  final int min;
  final int max;
  final int step;
  final String suffix;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(color: AppColors.surfaceGray, borderRadius: BorderRadius.circular(AppRadius.pill)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              visualDensity: VisualDensity.compact,
              onPressed: value <= min ? null : () => onChanged((value - step).clamp(min, max)),
              icon: const Icon(AppIcons.minus, size: 16),
            ),
            Text('${step == 1 && suffix.isEmpty ? '×' : ''}$value$suffix', style: const TextStyle(fontWeight: FontWeight.w800)),
            IconButton(
              visualDensity: VisualDensity.compact,
              onPressed: value >= max ? null : () => onChanged((value + step).clamp(min, max)),
              icon: const Icon(AppIcons.plus, size: 16),
            ),
          ],
        ),
      );
}
