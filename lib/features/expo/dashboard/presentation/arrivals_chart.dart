import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../domain/dashboard.dart';

/// Check-ins per hour as thin bars. Tap or drag across to read one hour;
/// otherwise the busiest hour is labelled.
class ArrivalsChart extends StatefulWidget {
  const ArrivalsChart({super.key, required this.hours});
  final List<HourCount> hours;

  @override
  State<ArrivalsChart> createState() => _ArrivalsChartState();
}

class _ArrivalsChartState extends State<ArrivalsChart> {
  int? _sel;

  void _pick(Offset p, double width) {
    final n = widget.hours.length;
    if (n == 0) return;
    final i = (p.dx / (width / n)).floor().clamp(0, n - 1);
    if (i != _sel) setState(() => _sel = i);
  }

  @override
  Widget build(BuildContext context) {
    final hours = widget.hours;
    final scaler = MediaQuery.textScalerOf(context);
    final labelSize = scaler.scale(11);
    final peak = hours.isEmpty ? null : hours.reduce((a, b) => b.count > a.count ? b : a);
    final shown = _sel != null && _sel! < hours.length ? hours[_sel!] : peak;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (shown != null)
          Text.rich(
            TextSpan(children: [
              TextSpan(text: '${shown.count}', style: TextStyle(fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
              TextSpan(text: ' at ${hourLabel(shown.hour)}${_sel == null ? ', the busiest hour' : ''}', style: TextStyle(color: AppColors.textSecondary)),
            ]),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 13),
          ),
        const SizedBox(height: 8),
        LayoutBuilder(builder: (context, c) {
          // Bars + a row of hour labels sized for the text scale.
          final height = 120 + labelSize * 1.6;
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (d) => _pick(d.localPosition, c.maxWidth),
            onHorizontalDragUpdate: (d) => _pick(d.localPosition, c.maxWidth),
            onHorizontalDragEnd: (_) {},
            child: SizedBox(
              width: c.maxWidth,
              height: height,
              child: CustomPaint(
                painter: ArrivalsPainter(
                  hours: hours,
                  selected: _sel,
                  bar: AppColors.brand,
                  barMuted: AppColors.brand.withValues(alpha: 0.35),
                  axis: AppColors.border,
                  label: AppColors.textSecondary,
                  labelSize: labelSize,
                ),
              ),
            ),
          );
        }),
      ],
    );
  }
}

class ArrivalsPainter extends CustomPainter {
  ArrivalsPainter({
    required this.hours,
    required this.selected,
    required this.bar,
    required this.barMuted,
    required this.axis,
    required this.label,
    required this.labelSize,
  });

  final List<HourCount> hours;
  final int? selected;
  final Color bar;
  final Color barMuted;
  final Color axis;
  final Color label;
  final double labelSize;

  TextPainter _text(String s) => TextPainter(
        text: TextSpan(text: s, style: TextStyle(fontSize: labelSize, color: label, fontWeight: FontWeight.w600)),
        textDirection: TextDirection.ltr,
        maxLines: 1,
      )..layout();

  @override
  void paint(Canvas canvas, Size size) {
    final n = hours.length;
    final labelH = labelSize * 1.6;
    final plotH = size.height - labelH;
    canvas.drawLine(Offset(0, plotH), Offset(size.width, plotH), Paint()..color = axis..strokeWidth = 1);
    if (n == 0) return;

    final maxCount = hours.fold<int>(0, (m, h) => math.max(m, h.count));
    final slot = size.width / n;
    const gap = 2.0;
    final barW = math.max(1.0, math.min(28.0, slot - gap));
    final sel = selected;
    final fill = Paint()..color = bar;
    final muted = Paint()..color = barMuted;

    for (var i = 0; i < n; i++) {
      final c = hours[i].count;
      if (c <= 0 || maxCount == 0) continue;
      final h = math.max(2.0, (plotH - 4) * c / maxCount);
      final x = i * slot + (slot - barW) / 2;
      final r = math.min(4.0, barW / 2);
      final rect = RRect.fromRectAndCorners(
        Rect.fromLTWH(x, plotH - h, barW, h),
        topLeft: Radius.circular(r),
        topRight: Radius.circular(r),
      );
      canvas.drawRRect(rect, sel == null || sel == i ? fill : muted);
    }

    // Hour labels: as many as fit without touching.
    final sample = _text('12 PM');
    final every = math.max(1, (sample.width + 8) ~/ slot + 1);
    for (var i = 0; i < n; i += every) {
      final t = _text(hourLabel(hours[i].hour));
      final cx = i * slot + slot / 2;
      final x = (cx - t.width / 2).clamp(0.0, math.max(0.0, size.width - t.width)).toDouble();
      t.paint(canvas, Offset(x, plotH + labelH * 0.2));
    }
  }

  @override
  bool shouldRepaint(ArrivalsPainter old) =>
      old.hours != hours || old.selected != selected || old.bar != bar || old.labelSize != labelSize || old.label != label;
}
