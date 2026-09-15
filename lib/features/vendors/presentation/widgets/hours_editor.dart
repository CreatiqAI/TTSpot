import 'package:flutter/cupertino.dart' show CupertinoDatePickerMode;
import 'package:flutter/material.dart';

import '../../../../core/theme/app_icons.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/wheel_picker.dart';

const kDays = ['mon', 'tue', 'wed', 'thu', 'fri', 'sat', 'sun'];
const kDayLabels = {'mon': 'Mon', 'tue': 'Tue', 'wed': 'Wed', 'thu': 'Thu', 'fri': 'Fri', 'sat': 'Sat', 'sun': 'Sun'};

/// One day: open and close as "HH:mm", or closed.
class DayHours {
  const DayHours(this.open, this.close);
  final String open;
  final String close;
  Map<String, String> toJson() => {'open': open, 'close': close};
  static DayHours? fromJson(Object? j) => j is Map && j['open'] is String && j['close'] is String ? DayHours(j['open'] as String, j['close'] as String) : null;
}

/// Opening hours for the week, stored as vendors.hours_json.
class OpeningHours {
  const OpeningHours(this.days);
  final Map<String, DayHours?> days;

  static const empty = OpeningHours({});

  factory OpeningHours.fromJson(Object? j) {
    if (j is! Map) return empty;
    return OpeningHours({for (final d in kDays) d: DayHours.fromJson(j[d])});
  }

  Map<String, Object?> toJson() => {for (final d in kDays) d: days[d]?.toJson()};

  bool get isEmpty => days.values.every((v) => v == null);

  OpeningHours copyWith(String day, DayHours? v) => OpeningHours({...days, day: v});

  /// "Mon–Sat 10:00 AM–7:00 PM · Sun closed" (groups equal consecutive days).
  String get summary {
    if (isEmpty) return '';
    final parts = <String>[];
    var i = 0;
    while (i < kDays.length) {
      final v = days[kDays[i]];
      var j = i;
      while (j + 1 < kDays.length && _same(days[kDays[j + 1]], v)) {
        j++;
      }
      final label = i == j ? kDayLabels[kDays[i]]! : '${kDayLabels[kDays[i]]}–${kDayLabels[kDays[j]]}';
      parts.add(v == null ? '$label closed' : '$label ${fmt(v.open)}–${fmt(v.close)}');
      i = j + 1;
    }
    return parts.join(' · ');
  }

  static bool _same(DayHours? a, DayHours? b) => a?.open == b?.open && a?.close == b?.close;

  /// "Open now · closes 7:00 PM", "Closed · opens 10:00 AM", or null when unset.
  String? status([DateTime? at]) {
    if (isEmpty) return null;
    final now = at ?? DateTime.now();
    final today = kDays[now.weekday - 1];
    final v = days[today];
    final minutes = now.hour * 60 + now.minute;
    if (v != null) {
      final o = _mins(v.open), c = _mins(v.close);
      final open = c > o ? (minutes >= o && minutes < c) : (minutes >= o || minutes < c);
      if (open) return 'Open now · closes ${fmt(v.close)}';
      if (minutes < o) return 'Closed · opens ${fmt(v.open)}';
    }
    // next opening day
    for (var k = 1; k <= 7; k++) {
      final d = kDays[(now.weekday - 1 + k) % 7];
      final n = days[d];
      if (n != null) return 'Closed · opens ${k == 1 ? 'tomorrow' : kDayLabels[d]} ${fmt(n.open)}';
    }
    return 'Closed';
  }

  static int _mins(String hhmm) {
    final p = hhmm.split(':');
    return int.parse(p[0]) * 60 + int.parse(p[1]);
  }

  static String fmt(String hhmm) {
    final m = _mins(hhmm);
    final h = m ~/ 60, mm = m % 60;
    final ap = h >= 12 ? 'PM' : 'AM';
    final h12 = h % 12 == 0 ? 12 : h % 12;
    return mm == 0 ? '$h12 $ap' : '$h12:${mm.toString().padLeft(2, '0')} $ap';
  }
}

/// Seven rows: day, open/closed switch, tap the times to change them on the
/// wheel. "Same as Monday" fills the rest in one tap.
class HoursEditor extends StatelessWidget {
  const HoursEditor({super.key, required this.value, required this.onChanged});
  final OpeningHours value;
  final ValueChanged<OpeningHours> onChanged;

  Future<void> _pick(BuildContext context, String day, DayHours current, {required bool openSide}) async {
    final hhmm = openSide ? current.open : current.close;
    final p = hhmm.split(':');
    final now = DateTime.now();
    final t = await showWheelPicker(
      context,
      initial: DateTime(now.year, now.month, now.day, int.parse(p[0]), int.parse(p[1]) - int.parse(p[1]) % 5),
      mode: CupertinoDatePickerMode.time,
      title: '${kDayLabels[day]} · ${openSide ? 'opens' : 'closes'}',
    );
    if (t == null) return;
    final s = '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
    onChanged(value.copyWith(day, openSide ? DayHours(s, current.close) : DayHours(current.open, s)));
  }

  @override
  Widget build(BuildContext context) {
    final mon = value.days['mon'];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final d in kDays)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              children: [
                SizedBox(width: 44, child: Text(kDayLabels[d]!, style: const TextStyle(fontWeight: FontWeight.w700))),
                Switch.adaptive(
                  value: value.days[d] != null,
                  activeTrackColor: AppColors.success,
                  onChanged: (on) => onChanged(value.copyWith(d, on ? (mon ?? const DayHours('10:00', '19:00')) : null)),
                ),
                const SizedBox(width: 6),
                if (value.days[d] == null)
                  const Text('Closed', style: TextStyle(color: AppColors.textSecondary))
                else ...[
                  _TimeChip(text: OpeningHours.fmt(value.days[d]!.open), onTap: () => _pick(context, d, value.days[d]!, openSide: true)),
                  const Padding(padding: EdgeInsets.symmetric(horizontal: 6), child: Text('–', style: TextStyle(color: AppColors.textSecondary))),
                  _TimeChip(text: OpeningHours.fmt(value.days[d]!.close), onTap: () => _pick(context, d, value.days[d]!, openSide: false)),
                ],
              ],
            ),
          ),
        const SizedBox(height: 4),
        Row(
          children: [
            TextButton.icon(
              style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
              onPressed: mon == null ? null : () => onChanged(OpeningHours({for (final d in kDays) d: d == 'sun' ? value.days['sun'] : mon})),
              icon: const Icon(AppIcons.arrowsClockwise, size: 16),
              label: const Text('Same as Monday for Tue–Sat'),
            ),
          ],
        ),
      ],
    );
  }
}

class _TimeChip extends StatelessWidget {
  const _TimeChip({required this.text, required this.onTap});
  final String text;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Material(
        color: AppColors.surfaceGray,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Text(text, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5)),
          ),
        ),
      );
}
