import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/app_router.dart';
import '../../../../core/theme/app_icons.dart';
import '../../../../core/theme/app_theme.dart';
import '../../application/garage_providers.dart';
import '../../domain/car.dart';
import '../../domain/car_documents.dart';

/// Owner-only "Documents" block on the car page: one chip per dated paper
/// ("Road tax · 23 days left", red under two weeks or expired) and the
/// insurance details under it. Tap anywhere to edit.
class CarDocumentsSection extends ConsumerWidget {
  const CarDocumentsSection({super.key, required this.car});
  final Car car;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final docs = ref.watch(carDocumentsProvider(car.id));
    final d = docs.value;
    void edit() => context.push(Routes.carDocuments(car.id));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('DOCUMENTS', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 1, color: AppColors.textSecondary)),
            const SizedBox(width: 8),
            Icon(AppIcons.lock, size: 12, color: AppColors.textMuted),
            const SizedBox(width: 3),
            Text('Only you', style: TextStyle(fontSize: 11.5, color: AppColors.textMuted)),
            const Spacer(),
            if (d != null && !d.isEmpty) TextButton(onPressed: edit, child: const Text('Edit')),
          ],
        ),
        if (d == null || d.isEmpty)
          docs.isLoading && d == null
              ? const SizedBox(height: 64)
              : _AddDocsCard(onTap: edit)
        else
          InkWell(
            onTap: edit,
            borderRadius: BorderRadius.circular(AppRadius.md),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(spacing: 6, runSpacing: 6, children: [for (final c in docChips(d)) DocChip(chip: c)]),
                  if (_insuranceLine(d) case final line?) ...[
                    const SizedBox(height: 10),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(padding: const EdgeInsets.only(top: 1), child: Icon(AppIcons.shieldCheck, size: 16, color: AppColors.textSecondary)),
                        const SizedBox(width: 6),
                        Expanded(child: Text(line, style: TextStyle(fontSize: 13, height: 1.35, color: AppColors.textSecondary))),
                      ],
                    ),
                  ],
                  if ((d.note ?? '').trim().isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(padding: const EdgeInsets.only(top: 1), child: Icon(AppIcons.notePencil, size: 16, color: AppColors.textSecondary)),
                        const SizedBox(width: 6),
                        Expanded(child: Text(d.note!.trim(), style: TextStyle(fontSize: 13, height: 1.35, color: AppColors.textSecondary))),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
      ],
    );
  }

  /// "Etiqa · Policy V123456 · NCD 55% · Sum insured RM 45,000", or null.
  static String? _insuranceLine(CarDocuments d) {
    final bits = [
      if ((d.insurer ?? '').trim().isNotEmpty) d.insurer!.trim(),
      if ((d.policyNo ?? '').trim().isNotEmpty) 'Policy ${d.policyNo!.trim()}',
      if (d.ncdPct != null) 'NCD ${formatNcd(d.ncdPct!)}',
      if (d.sumInsured != null) 'Sum insured RM ${formatRinggit(d.sumInsured!)}',
    ];
    return bits.isEmpty ? null : bits.join(' · ');
  }
}

/// One chip's worth: what to show and whether it is red.
typedef DocChipData = ({IconData icon, String text, bool urgent});

/// Chips for every dated paper, plus a mileage-only service reminder.
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

class _AddDocsCard extends StatelessWidget {
  const _AddDocsCard({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: AppColors.surfaceGray, borderRadius: BorderRadius.circular(AppRadius.lg)),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(12)),
                child: Icon(AppIcons.receipt, color: AppColors.textPrimary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Road tax and insurance', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Text('Save the expiry dates and we\'ll remind you before they run out.', style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary)),
                  ],
                ),
              ),
              Icon(AppIcons.caretRight, color: AppColors.textMuted),
            ],
          ),
        ),
      ),
    );
  }
}

/// 45,000 · 1,250.50
String formatRinggit(double v) {
  final s = v.toStringAsFixed(v == v.roundToDouble() ? 0 : 2);
  final parts = s.split('.');
  final whole = parts[0].replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');
  return parts.length > 1 ? '$whole.${parts[1]}' : whole;
}
