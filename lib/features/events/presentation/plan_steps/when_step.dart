import 'package:flutter/cupertino.dart' show CupertinoDatePickerMode, CupertinoTimerPicker, CupertinoTimerPickerMode;
import 'package:flutter/material.dart';

import '../../../../core/theme/app_icons.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/dates.dart';
import '../../../../core/widgets/wheel_picker.dart';
import '../../application/plan_draft.dart';
import 'wizard_parts.dart';

/// Step "When?": one-tap chips (Tonight, Tomorrow night, This weekend), the
/// wheel pickers for anything else, and for TT sessions how long it runs.
class WhenStep extends StatelessWidget {
  const WhenStep({super.key, required this.draft});
  final PlanDraft draft;

  static String durationLabel(int minutes) =>
      minutes % 60 == 0 ? '${minutes ~/ 60} h' : (minutes > 60 ? '${minutes ~/ 60} h ${minutes % 60} min' : '$minutes min');

  Future<void> _pickDate(BuildContext context) async {
    final now = DateTime.now();
    final d = await showWheelPicker(
      context,
      initial: draft.startsAt.isBefore(now) ? now : draft.startsAt,
      mode: CupertinoDatePickerMode.date,
      min: DateTime(now.year, now.month, now.day),
      max: draft.maxStart(now),
      title: 'Which day?',
    );
    if (d == null) return;
    final s = draft.startsAt;
    draft.setStart(DateTime(d.year, d.month, d.day, s.hour, s.minute));
  }

  Future<void> _pickTime(BuildContext context) async {
    final s = draft.startsAt;
    // The wheel moves in 5-minute steps; feed it a rounded start so it lands on a row.
    final rounded = DateTime(s.year, s.month, s.day, s.hour, s.minute - s.minute % 5);
    final t = await showWheelPicker(context, initial: rounded, mode: CupertinoDatePickerMode.time, title: 'What time?');
    if (t == null) return;
    draft.setStart(DateTime(s.year, s.month, s.day, t.hour, t.minute));
  }

  Future<void> _customDuration(BuildContext context) async {
    var d = Duration(minutes: draft.minutes);
    final ok = await showModalBottomSheet<bool>(
      useRootNavigator: true, // above the shell tab bar
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 8, 0),
              child: Row(children: [
                const Expanded(child: Text('How long?', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800))),
                TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Done')),
              ]),
            ),
            SizedBox(
              height: 200,
              child: CupertinoTimerPicker(mode: CupertinoTimerPickerMode.hm, initialTimerDuration: d, minuteInterval: 15, onTimerDurationChanged: (v) => d = v),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (ok == true && d.inMinutes >= 15) draft.setMinutes(d.inMinutes);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: draft,
      builder: (context, _) {
        final now = DateTime.now();
        final quick = PlanDraft.quickTimes(now, session: draft.session);
        final s = draft.startsAt;
        final end = draft.endsAt;
        const presets = [60, 120, 180];
        return ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          children: [
            StepHeading('When?', subtitle: draft.session ? 'Pick a night. You can change it later from the session page.' : 'When does it start?'),
            const SectionLabel('QUICK PICK'),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final q in quick)
                  PillChip(
                    key: Key('plan-quick-${q.label}'),
                    label: q.label,
                    sub: '${formatDate(q.at)} · ${formatTime(q.at)}',
                    on: q.at == s,
                    onTap: () => draft.setStart(q.at),
                  ),
              ],
            ),
            const SizedBox(height: 18),
            const SectionLabel('OR PICK A DAY AND TIME'),
            Row(
              children: [
                Expanded(child: TapField(icon: AppIcons.calendarBlank, text: formatDate(s), onTap: () => _pickDate(context))),
                const SizedBox(width: 10),
                Expanded(child: TapField(icon: AppIcons.clock, text: formatTime(s), onTap: () => _pickTime(context))),
              ],
            ),
            if (draft.session) ...[
              const SizedBox(height: 18),
              const SectionLabel('HOW LONG'),
              Row(
                children: [
                  for (final m in presets) ...[
                    Expanded(child: PillChip(label: durationLabel(m), on: draft.minutes == m, onTap: () => draft.setMinutes(m))),
                    const SizedBox(width: 6),
                  ],
                  Expanded(
                    child: PillChip(
                      label: presets.contains(draft.minutes) ? 'Custom' : durationLabel(draft.minutes),
                      on: !presets.contains(draft.minutes),
                      onTap: () => _customDuration(context),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 18),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: AppColors.surfaceGray, borderRadius: BorderRadius.circular(AppRadius.md)),
              child: Row(
                children: [
                  Icon(AppIcons.calendarCheck, size: 20, color: AppColors.textPrimary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      end == null ? 'Starts ${formatEventDateFriendly(s, now: now)}' : 'Starts ${formatEventDateFriendly(s, now: now)}, ends ${formatTime(end)}',
                      style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, height: 1.35),
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}
