import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// iPhone-style wheel in a bottom sheet for dates and times. One Done button,
/// no dial, no keyboard toggle. Returns null when dismissed.
Future<DateTime?> showWheelPicker(
  BuildContext context, {
  required DateTime initial,
  required CupertinoDatePickerMode mode,
  DateTime? min,
  DateTime? max,
  String? title,
}) {
  var value = initial;
  final label = title ?? (mode == CupertinoDatePickerMode.date ? 'Pick a date' : 'Pick a time');
  return showModalBottomSheet<DateTime>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 8, 0),
            child: Row(
              children: [
                Expanded(child: Text(label, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800))),
                TextButton(onPressed: () => Navigator.pop(ctx, value), child: const Text('Done')),
              ],
            ),
          ),
          SizedBox(
            height: 216,
            child: CupertinoTheme(
              data: const CupertinoThemeData(
                textTheme: CupertinoTextThemeData(
                  dateTimePickerTextStyle: TextStyle(fontSize: 22, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
                ),
              ),
              child: CupertinoDatePicker(
                mode: mode,
                initialDateTime: initial,
                minimumDate: min,
                maximumDate: max,
                minuteInterval: 5,
                use24hFormat: false,
                onDateTimeChanged: (d) => value = d,
              ),
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
}
