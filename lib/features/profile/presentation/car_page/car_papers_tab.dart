import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../core/theme/app_icons.dart';
import '../../../../core/theme/app_theme.dart';
import '../../domain/car_documents.dart';
import 'car_build_tab.dart' show CarEmptyCard;
import 'car_page_model.dart';

/// Papers (owner only; RLS keeps them private too): one card per dated
/// document with a ring counting down the days left of its period, cards to
/// add the missing road tax or insurance, and chips for the rest. Every tap
/// opens the documents form.
class CarPapersTab extends StatelessWidget {
  const CarPapersTab({super.key, required this.documents, required this.loading, required this.onEdit, this.now});
  final CarDocuments? documents;
  final bool loading;
  final VoidCallback onEdit;

  /// Today, for tests.
  final DateTime? now;

  @override
  Widget build(BuildContext context) {
    final d = documents;
    if (d == null || d.isEmpty) {
      if (loading) {
        return const Padding(
          padding: EdgeInsets.symmetric(vertical: 32),
          child: Center(child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))),
        );
      }
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
        child: CarEmptyCard(
          title: 'NEVER MISS A RENEWAL',
          body: 'Add your road tax and insurance dates. We remind you 30 days, 7 days and the day before. Only you see this.',
          action: 'Add road tax date',
          onAction: onEdit,
        ),
      );
    }
    final dues = [for (final due in d.dues) DocDue(due.kind, due.date, now: now)];
    final has = {for (final due in dues) due.kind};
    final missingChips = [
      if (!has.contains(DocKind.puspakom)) DocKind.puspakom,
      if (!has.contains(DocKind.service) && d.serviceDueKm == null) DocKind.service,
    ];
    final note = (d.note ?? '').trim();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final due in dues) ...[
            PaperCard(
              due: due,
              details: due.kind == DocKind.insurance ? insuranceLine(d) : null,
              km: due.kind == DocKind.service ? d.serviceDueKm : null,
              onTap: onEdit,
            ),
            const SizedBox(height: 10),
          ],
          if (d.serviceDueOn == null && d.serviceDueKm != null) ...[
            PaperCard.km(km: d.serviceDueKm!, onTap: onEdit),
            const SizedBox(height: 10),
          ],
          for (final kind in [DocKind.roadTax, DocKind.insurance])
            if (!has.contains(kind)) ...[
              PaperCard.add(kind: kind, details: kind == DocKind.insurance ? insuranceLine(d) : null, onTap: onEdit),
              const SizedBox(height: 10),
            ],
          if (missingChips.isNotEmpty) ...[
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [for (final k in missingChips) _AddChip(label: '+ ${k.label}', onTap: onEdit)],
            ),
            const SizedBox(height: 10),
          ],
          if (note.isNotEmpty) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(padding: const EdgeInsets.only(top: 1), child: Icon(AppIcons.notePencil, size: 16, color: AppColors.textSecondary)),
                const SizedBox(width: 6),
                Expanded(child: Text(note, style: TextStyle(fontSize: 13, height: 1.35, color: AppColors.textSecondary))),
              ],
            ),
            const SizedBox(height: 10),
          ],
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(padding: const EdgeInsets.only(top: 1), child: Icon(AppIcons.lock, size: 13, color: AppColors.textSecondary)),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'We remind you 30 days, 7 days and the day before anything runs out. Only you can see this.',
                  style: TextStyle(fontSize: 12, height: 1.35, color: AppColors.textSecondary),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// "Etiqa · Policy V123456 · NCD 55% · Sum insured RM 45,000", or null.
String? insuranceLine(CarDocuments d) {
  final bits = [
    if ((d.insurer ?? '').trim().isNotEmpty) d.insurer!.trim(),
    if ((d.policyNo ?? '').trim().isNotEmpty) 'Policy ${d.policyNo!.trim()}',
    if (d.ncdPct != null) 'NCD ${formatNcd(d.ncdPct!)}',
    if (d.sumInsured != null) 'Sum insured RM ${formatRinggit(d.sumInsured!)}',
  ];
  return bits.isEmpty ? null : bits.join(' · ');
}

/// How long one round of a document lasts, for its ring.
int _periodDays(DocKind k) => switch (k) {
      DocKind.roadTax || DocKind.insurance || DocKind.puspakom => 365,
      DocKind.service => 180,
    };

enum _PaperState { ok, soon, overdue }

/// One document: a ring of the days left of its period (green, amber at 30
/// days or less, red once past), its name and when it runs out.
class PaperCard extends StatelessWidget {
  const PaperCard({super.key, required DocDue this.due, this.details, this.km, required this.onTap}) : kind = null, _kmOnly = false;

  /// A missing document: "+ ADD" in the ring.
  const PaperCard.add({super.key, required DocKind this.kind, this.details, required this.onTap}) : due = null, km = null, _kmOnly = false;

  /// A service due at a mileage, with no date.
  const PaperCard.km({super.key, required int this.km, required this.onTap}) : due = null, kind = DocKind.service, details = null, _kmOnly = true;

  final DocDue? due;
  final DocKind? kind;
  final String? details;
  final int? km;
  final VoidCallback onTap;
  final bool _kmOnly;

  @override
  Widget build(BuildContext context) {
    final d = due;
    final k = d?.kind ?? kind!;
    final state = d == null ? null : (d.daysLeft < 0 ? _PaperState.overdue : (d.daysLeft <= 30 ? _PaperState.soon : _PaperState.ok));
    final color = switch (state) {
      null => AppColors.textMuted,
      _PaperState.ok => AppColors.success,
      _PaperState.soon => const Color(0xFFD97706),
      _PaperState.overdue => AppColors.danger,
    };
    final kmText = km == null ? null : '${formatRinggit(km!.toDouble())} km';
    final String sub;
    if (_kmOnly) {
      sub = 'At $kmText';
    } else if (d == null) {
      sub = k.expires ? 'Add your expiry date' : 'Add the date it\'s due';
    } else if (d.daysLeft < 0) {
      sub = '${k.expires ? 'Expired' : 'Was due'} ${formatDay(d.date)}';
    } else {
      sub = '${k.expires ? 'Valid till' : 'Due'} ${formatDay(d.date)}${kmText == null ? '' : ' or $kmText'}';
    }
    final tag = switch (state) {
      _PaperState.soon => (k.expires ? 'Renew soon' : 'Due soon', const Color(0xFFFEF3C7), const Color(0xFF92400E)),
      _PaperState.overdue => (k.expires ? 'Expired' : 'Overdue', AppColors.danger.withValues(alpha: 0.12), AppColors.danger),
      _ => null,
    };
    final Widget ringCentre;
    if (d == null) {
      ringCentre = _kmOnly
          ? Icon(AppIcons.wrench, size: 20, color: AppColors.textPrimary)
          : _RingText(big: '+', small: 'ADD');
    } else {
      final days = d.daysLeft.abs();
      // Past due: how long ago, the red ring and the tag say the rest.
      ringCentre = days >= 1000
          ? _RingText(big: '${days ~/ 365}', small: d.daysLeft < 0 ? 'YRS AGO' : 'YEARS')
          : _RingText(big: '$days', small: d.daysLeft < 0 ? 'AGO' : (days == 1 ? 'DAY' : 'DAYS'));
    }
    final progress = d == null ? 0.0 : (d.daysLeft / _periodDays(k)).clamp(0.0, 1.0);
    return Material(
      color: AppColors.surfaceGray,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              SizedBox(
                width: 56,
                height: 56,
                child: CustomPaint(
                  painter: _RingPainter(progress: progress, color: color, track: state == _PaperState.overdue ? AppColors.danger.withValues(alpha: 0.25) : AppColors.border),
                  child: Center(child: MediaQuery.withClampedTextScaling(maxScaleFactor: 1.1, child: ringCentre)),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(k.label, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                        if (tag != null)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(color: tag.$2, borderRadius: BorderRadius.circular(AppRadius.pill)),
                            child: Text(tag.$1, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: tag.$3)),
                          ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(sub, style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
                    if (details != null) ...[
                      const SizedBox(height: 2),
                      Text(details!, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                    ],
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

class _RingText extends StatelessWidget {
  const _RingText({required this.big, required this.small});
  final String big;
  final String small;

  @override
  Widget build(BuildContext context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(big, style: TextStyle(fontFamily: AppFonts.display, fontSize: 18, fontWeight: FontWeight.w800, height: 1, color: AppColors.textPrimary)),
          Text(small, maxLines: 1, style: TextStyle(fontSize: 8, fontWeight: FontWeight.w700, height: 1.2, color: AppColors.textSecondary)),
        ],
      );
}

class _RingPainter extends CustomPainter {
  const _RingPainter({required this.progress, required this.color, required this.track});
  final double progress;
  final Color color;
  final Color track;

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 6.0;
    final r = size.shortestSide / 2 - stroke / 2 - 1;
    final c = size.center(Offset.zero);
    canvas.drawCircle(c, r, Paint()
      ..color = track
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke);
    if (progress <= 0) return;
    canvas.drawArc(
      Rect.fromCircle(center: c, radius: r),
      -math.pi / 2,
      2 * math.pi * progress,
      false,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.progress != progress || old.color != color || old.track != track;
}

class _AddChip extends StatelessWidget {
  const _AddChip({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(AppRadius.pill), border: Border.all(color: AppColors.border, width: 1.5)),
          child: Text(label, style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
        ),
      );
}

// ------------------------------------------------- garage panel chips ---

/// One chip's worth: what to show and whether it is red.
typedef DocChipData = ({IconData icon, String text, bool urgent});

/// Chips for every dated paper, plus a mileage-only service reminder (the
/// garage panel shows the urgent ones).
List<DocChipData> docChips(CarDocuments d) {
  final km = d.serviceDueKm == null ? null : '${formatRinggit(d.serviceDueKm!.toDouble())} km';
  return [
    for (final due in d.dues)
      (
        icon: switch (due.kind) {
          DocKind.roadTax => AppIcons.receipt,
          DocKind.insurance => AppIcons.shieldCheck,
          DocKind.puspakom => AppIcons.listChecks,
          DocKind.service => AppIcons.wrench,
        },
        text: due.kind == DocKind.service && km != null ? '${due.text} or $km' : due.text,
        urgent: due.urgent,
      ),
    if (d.serviceDueOn == null && km != null) (icon: AppIcons.wrench, text: 'Service · at $km', urgent: false),
  ];
}

class DocChip extends StatelessWidget {
  const DocChip({super.key, required this.chip});
  final DocChipData chip;

  @override
  Widget build(BuildContext context) {
    final fg = chip.urgent ? AppColors.danger : AppColors.textPrimary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: chip.urgent ? AppColors.danger.withValues(alpha: 0.10) : AppColors.surfaceGray,
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(chip.icon, size: 14, color: fg),
          const SizedBox(width: 5),
          Text(chip.text, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: fg)),
        ],
      ),
    );
  }
}
