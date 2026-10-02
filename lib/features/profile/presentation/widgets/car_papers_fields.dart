import 'package:flutter/material.dart';

import '../../../../core/theme/app_icons.dart';
import '../../../../core/theme/app_theme.dart';
import '../../domain/car_documents.dart';

/// The papers step of Add car: road tax, insurance and PUSPAKOM, all
/// optional. Kept while the member goes back and forth; nothing is stored
/// unless something was filled in (skipping creates no row).
class CarPapersDraft {
  final insurer = TextEditingController();
  DateTime? roadTax;
  DateTime? insurance;
  double? ncd;
  DateTime? puspakom;

  bool get isEmpty => roadTax == null && insurance == null && ncd == null && puspakom == null && insurer.text.trim().isEmpty;

  /// The row for [carId] (car_documents), null when there is nothing.
  CarDocuments? documentsFor(String carId) => isEmpty
      ? null
      : CarDocuments(carId: carId, roadTaxExpiry: roadTax, insurer: insurer.text, insuranceExpiry: insurance, ncdPct: ncd, puspakomDue: puspakom);

  void clear() {
    insurer.clear();
    roadTax = null;
    insurance = null;
    ncd = null;
    puspakom = null;
  }

  void dispose() => insurer.dispose();
}

/// The fields for a [CarPapersDraft]. [onChanged] after every change.
class CarPapersFields extends StatelessWidget {
  const CarPapersFields({super.key, required this.draft, required this.onChanged, this.enabled = true});
  final CarPapersDraft draft;
  final VoidCallback onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    void set(void Function() change) {
      change();
      onChanged();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _PapersHead(icon: AppIcons.receipt, text: 'ROAD TAX (LKM)'),
        DocDateField(label: 'Road tax expiry', value: draft.roadTax, enabled: enabled, onChanged: (d) => set(() => draft.roadTax = d)),
        _PapersHead(icon: AppIcons.shieldCheck, text: 'INSURANCE'),
        TextField(
          controller: draft.insurer,
          enabled: enabled,
          maxLength: 60,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(labelText: 'Insurer', hintText: 'e.g. Etiqa, Allianz, Zurich', counterText: ''),
          onChanged: (_) => onChanged(),
        ),
        const SizedBox(height: 12),
        DocDateField(label: 'Insurance expiry', value: draft.insurance, enabled: enabled, onChanged: (d) => set(() => draft.insurance = d)),
        const SizedBox(height: 14),
        Text('No-claim discount (NCD)', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final step in kNcdSteps)
              ChoiceChip(
                label: Text(formatNcd(step)),
                selected: draft.ncd == step,
                showCheckmark: false,
                onSelected: enabled ? (on) => set(() => draft.ncd = on ? step : null) : null,
              ),
          ],
        ),
        _PapersHead(icon: AppIcons.wrench, text: 'PUSPAKOM'),
        DocDateField(label: 'Inspection due', value: draft.puspakom, enabled: enabled, onChanged: (d) => set(() => draft.puspakom = d)),
      ],
    );
  }
}

class _PapersHead extends StatelessWidget {
  const _PapersHead({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 22, bottom: 10),
        child: Row(
          children: [
            Icon(icon, size: 15, color: AppColors.textSecondary),
            const SizedBox(width: 6),
            Expanded(child: Text(text, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 1, color: AppColors.textSecondary))),
          ],
        ),
      );
}

/// A date box that opens the date picker, with an × to clear it.
class DocDateField extends StatelessWidget {
  const DocDateField({super.key, required this.label, required this.value, required this.onChanged, this.enabled = true});
  final String label;
  final DateTime? value;
  final ValueChanged<DateTime?> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    return InkWell(
      onTap: !enabled
          ? null
          : () async {
              FocusScope.of(context).unfocus();
              final d = await showDatePicker(
                context: context,
                initialDate: value ?? now,
                firstDate: DateTime(now.year - 10),
                lastDate: DateTime(now.year + 10, 12, 31),
                helpText: label,
              );
              if (d != null) onChanged(d);
            },
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          enabled: enabled,
          suffixIcon: value == null
              ? Icon(AppIcons.calendarBlank, size: 18, color: AppColors.textSecondary)
              : IconButton(tooltip: 'Clear', icon: Icon(AppIcons.xCircle, size: 18, color: AppColors.textSecondary), onPressed: enabled ? () => onChanged(null) : null),
        ),
        isEmpty: value == null,
        child: Text(value == null ? '' : formatDay(value!), style: const TextStyle(fontSize: 15)),
      ),
    );
  }
}
