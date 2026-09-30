import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/friendly_error.dart';
import '../application/garage_providers.dart';
import '../application/profile_providers.dart';
import '../domain/car_documents.dart';

/// Owner-only editor for a car's papers: road tax, insurance, PUSPAKOM and
/// the next service. Every field is optional; saving an empty form clears it.
class CarDocumentsScreen extends ConsumerStatefulWidget {
  const CarDocumentsScreen({super.key, required this.carId});
  final String carId;

  @override
  ConsumerState<CarDocumentsScreen> createState() => _CarDocumentsScreenState();
}

class _CarDocumentsScreenState extends ConsumerState<CarDocumentsScreen> {
  final _insurer = TextEditingController();
  final _policy = TextEditingController();
  final _sumInsured = TextEditingController();
  final _note = TextEditingController();
  final _serviceKm = TextEditingController();
  DateTime? _roadTax;
  DateTime? _insurance;
  DateTime? _puspakom;
  DateTime? _service;
  double? _ncd;
  bool _loaded = false;
  bool _hadAny = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final d = await ref.read(carDocumentsProvider(widget.carId).future);
      if (!mounted) return;
      setState(() {
        _loaded = true;
        if (d == null) return;
        _hadAny = !d.isEmpty;
        _roadTax = d.roadTaxExpiry;
        _insurer.text = d.insurer ?? '';
        _policy.text = d.policyNo ?? '';
        _insurance = d.insuranceExpiry;
        _ncd = d.ncdPct;
        _sumInsured.text = d.sumInsured == null ? '' : _plain(d.sumInsured!);
        _note.text = d.note ?? '';
        _puspakom = d.puspakomDue;
        _service = d.serviceDueOn;
        _serviceKm.text = d.serviceDueKm?.toString() ?? '';
      });
    } catch (e) {
      if (mounted) setState(() => _loaded = true);
    }
  }

  @override
  void dispose() {
    _insurer.dispose();
    _policy.dispose();
    _sumInsured.dispose();
    _note.dispose();
    _serviceKm.dispose();
    super.dispose();
  }

  static String _plain(double v) => v.toStringAsFixed(v == v.roundToDouble() ? 0 : 2);

  CarDocuments _current() => CarDocuments(
        carId: widget.carId,
        roadTaxExpiry: _roadTax,
        insurer: _insurer.text,
        policyNo: _policy.text,
        insuranceExpiry: _insurance,
        ncdPct: _ncd,
        sumInsured: double.tryParse(_sumInsured.text.trim()),
        note: _note.text,
        puspakomDue: _puspakom,
        serviceDueOn: _service,
        serviceDueKm: int.tryParse(_serviceKm.text.trim()),
      );

  Future<void> _save({bool clear = false}) async {
    FocusScope.of(context).unfocus();
    final sum = _sumInsured.text.trim();
    if (!clear && sum.isNotEmpty && double.tryParse(sum) == null) return _snack('Check the sum insured.');
    setState(() => _busy = true);
    try {
      await ref.read(garageActionsProvider).saveDocuments(clear ? CarDocuments(carId: widget.carId) : _current());
      if (mounted) context.pop();
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        _snack(friendlyError(e));
      }
    }
  }

  Future<void> _clearAll() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear all documents?'),
        content: const Text('Removes the dates and details for this car. Reminders stop.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Clear', style: TextStyle(color: AppColors.danger))),
        ],
      ),
    );
    if (ok == true) await _save(clear: true);
  }

  void _snack(String msg) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  @override
  Widget build(BuildContext context) {
    final car = ref.watch(carProvider(widget.carId)).value;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(AppIcons.x), onPressed: _busy ? null : () => context.pop()),
        title: const Text('Documents'),
        actions: [
          _busy
              ? const Padding(padding: EdgeInsets.only(right: 20), child: Center(child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))))
              : TextButton(onPressed: _loaded ? _save : null, child: const Text('Save')),
        ],
      ),
      body: !_loaded
          ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 40),
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: AppColors.surfaceGray, borderRadius: BorderRadius.circular(AppRadius.md)),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(padding: const EdgeInsets.only(top: 1), child: Icon(AppIcons.lock, size: 16, color: AppColors.textSecondary)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Only you can see this${car == null ? '' : ' for your ${car.model}'}. We\'ll remind you 30, 7 and 1 day before road tax or insurance runs out.',
                          style: TextStyle(fontSize: 13, height: 1.4, color: AppColors.textSecondary),
                        ),
                      ),
                    ],
                  ),
                ),

                const _Head('ROAD TAX (LKM)'),
                _DateField(label: 'Expiry date', value: _roadTax, onChanged: (d) => setState(() => _roadTax = d)),

                const _Head('INSURANCE'),
                TextField(
                  controller: _insurer,
                  maxLength: 60,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(labelText: 'Insurer', hintText: 'e.g. Etiqa, Allianz, Zurich', counterText: ''),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _policy,
                  maxLength: 40,
                  textCapitalization: TextCapitalization.characters,
                  decoration: const InputDecoration(labelText: 'Policy number', counterText: ''),
                ),
                const SizedBox(height: 12),
                _DateField(label: 'Expiry date', value: _insurance, onChanged: (d) => setState(() => _insurance = d)),
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
                        selected: _ncd == step,
                        showCheckmark: false,
                        onSelected: (on) => setState(() => _ncd = on ? step : null),
                      ),
                  ],
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _sumInsured,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
                  decoration: const InputDecoration(labelText: 'Sum insured (optional)', prefixText: 'RM '),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _note,
                  maxLength: 300,
                  minLines: 2,
                  maxLines: 4,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(labelText: 'Note (optional)', hintText: 'Agent\'s number, windscreen cover, add-ons', alignLabelWithHint: true, counterText: ''),
                ),

                const _Head('PUSPAKOM'),
                _DateField(label: 'Inspection due', value: _puspakom, onChanged: (d) => setState(() => _puspakom = d)),

                const _Head('NEXT SERVICE'),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: _DateField(label: 'Date', value: _service, onChanged: (d) => setState(() => _service = d))),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: _serviceKm,
                        keyboardType: TextInputType.number,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(7)],
                        decoration: const InputDecoration(labelText: 'Or at', suffixText: 'km'),
                      ),
                    ),
                  ],
                ),

                if (_hadAny) ...[
                  const SizedBox(height: 28),
                  Center(
                    child: TextButton(
                      onPressed: _busy ? null : _clearAll,
                      child: const Text('Clear all documents', style: TextStyle(color: AppColors.danger)),
                    ),
                  ),
                ],
              ],
            ),
    );
  }
}

class _Head extends StatelessWidget {
  const _Head(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 24, bottom: 10),
        child: Text(text, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 1, color: AppColors.textSecondary)),
      );
}

/// A date box that opens the date picker, with an × to clear it.
class _DateField extends StatelessWidget {
  const _DateField({required this.label, required this.value, required this.onChanged});
  final String label;
  final DateTime? value;
  final ValueChanged<DateTime?> onChanged;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    return InkWell(
      onTap: () async {
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
          suffixIcon: value == null
              ? Icon(AppIcons.calendarBlank, size: 18, color: AppColors.textSecondary)
              : IconButton(tooltip: 'Clear', icon: Icon(AppIcons.xCircle, size: 18, color: AppColors.textSecondary), onPressed: () => onChanged(null)),
        ),
        isEmpty: value == null,
        child: Text(value == null ? '' : formatDay(value!), style: const TextStyle(fontSize: 15)),
      ),
    );
  }
}
