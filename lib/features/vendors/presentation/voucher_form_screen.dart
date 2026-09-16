import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/dates.dart';
import '../../../core/utils/friendly_error.dart';
import '../../../core/widgets/picker_field.dart';
import '../../../core/widgets/primary_button.dart';
import '../application/vendors_providers.dart';
import '../domain/vendor.dart';

/// Create or edit one voucher.
class VoucherFormScreen extends ConsumerStatefulWidget {
  const VoucherFormScreen({super.key, this.voucherId});
  final String? voucherId;

  @override
  ConsumerState<VoucherFormScreen> createState() => _VoucherFormScreenState();
}

class _VoucherFormScreenState extends ConsumerState<VoucherFormScreen> {
  final _form = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _desc = TextEditingController();
  final _terms = TextEditingController();
  final _value = TextEditingController();
  final _minSpend = TextEditingController(text: '0');
  final _points = TextEditingController(text: '0');
  final _maxClaims = TextEditingController();
  final _perUser = TextEditingController(text: '1');
  DiscountKind _kind = DiscountKind.percent;
  String? _productId; // null = whole shop
  DateTime? _endsAt;
  bool _active = true;
  bool _busy = false;
  bool _loaded = false;

  @override
  void dispose() {
    for (final c in [_title, _desc, _terms, _value, _minSpend, _points, _maxClaims, _perUser]) {
      c.dispose();
    }
    super.dispose();
  }

  void _fill(Voucher v) {
    _title.text = v.title;
    _desc.text = v.description ?? '';
    _terms.text = v.terms ?? '';
    _value.text = v.value % 1 == 0 ? '${v.value.toInt()}' : '${v.value}';
    _minSpend.text = v.minSpend % 1 == 0 ? '${v.minSpend.toInt()}' : '${v.minSpend}';
    _points.text = '${v.pointsCost}';
    _maxClaims.text = v.maxClaims?.toString() ?? '';
    _perUser.text = '${v.perUserLimit}';
    _kind = v.kind;
    _productId = v.productId;
    _endsAt = v.endsAt;
    _active = v.active;
    _loaded = true;
  }

  Future<void> _pickEnd() async {
    final now = DateTime.now();
    final d = await showDatePicker(context: context, initialDate: _endsAt ?? now.add(const Duration(days: 30)), firstDate: now, lastDate: now.add(const Duration(days: 365 * 2)));
    if (d == null) return;
    setState(() => _endsAt = DateTime(d.year, d.month, d.day, 23, 59));
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      await ref.read(vendorActionsProvider).saveVoucher(
            id: widget.voucherId,
            title: _title.text.trim(),
            description: _desc.text.trim(),
            terms: _terms.text.trim(),
            kind: _kind,
            value: _kind == DiscountKind.freebie ? 0 : (double.tryParse(_value.text.trim()) ?? 0),
            minSpend: double.tryParse(_minSpend.text.trim()) ?? 0,
            pointsCost: int.tryParse(_points.text.trim()) ?? 0,
            maxClaims: int.tryParse(_maxClaims.text.trim()),
            perUser: int.tryParse(_perUser.text.trim()) ?? 1,
            endsAt: _endsAt,
            active: _active,
            productId: _productId,
          );
      if (mounted) context.pop();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.voucherId != null;
    if (editing && !_loaded) {
      final existing = ref.watch(vendorVouchersProvider).value?.where((v) => v.id == widget.voucherId).firstOrNull;
      if (existing != null) _fill(existing);
    }
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(AppIcons.arrowLeft), onPressed: () => context.pop()),
        title: Text(editing ? 'Edit voucher' : 'New voucher'),
      ),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            TextFormField(
              controller: _title,
              maxLength: 80,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Title', hintText: 'e.g. 10% off drinks', counterText: ''),
              validator: (v) => (v ?? '').trim().length < 2 ? 'Give it a title' : null,
            ),
            const SizedBox(height: 12),
            Builder(builder: (context) {
              final products = ref.watch(vendorProductsProvider).value ?? const <Product>[];
              if (products.isEmpty) return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: PickerField<String>(
                  label: 'Applies to',
                  icon: AppIcons.shoppingBag,
                  value: _productId ?? '',
                  options: [('', 'Whole shop'), for (final p in products) (p.id, p.name)],
                  onChanged: (v) => setState(() => _productId = (v == null || v.isEmpty) ? null : v),
                ),
              );
            }),
            SegmentedButton<DiscountKind>(
              segments: const [
                ButtonSegment(value: DiscountKind.percent, label: Text('% off')),
                ButtonSegment(value: DiscountKind.amount, label: Text('RM off')),
                ButtonSegment(value: DiscountKind.freebie, label: Text('Free item')),
              ],
              selected: {_kind},
              onSelectionChanged: (s) => setState(() => _kind = s.first),
            ),
            if (_kind != DiscountKind.freebie) ...[
              const SizedBox(height: 12),
              TextFormField(
                controller: _value,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(labelText: _kind == DiscountKind.percent ? 'Percent off' : 'Ringgit off', suffixText: _kind == DiscountKind.percent ? '%' : 'RM'),
                validator: (v) {
                  final n = double.tryParse((v ?? '').trim());
                  if (n == null || n <= 0) return 'Enter a number above 0';
                  if (_kind == DiscountKind.percent && n > 100) return 'Max 100%';
                  return null;
                },
              ),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _minSpend,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'Min spend', prefixText: 'RM '),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextFormField(
                    controller: _points,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Costs points', helperText: '0 = free to claim'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _maxClaims,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Total available', helperText: 'blank = unlimited'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextFormField(
                    controller: _perUser,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Per member'),
                    validator: (v) => (int.tryParse((v ?? '').trim()) ?? 0) < 1 ? 'At least 1' : null,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(AppIcons.calendarBlank),
              title: Text(_endsAt == null ? 'No end date' : 'Ends ${formatDate(_endsAt!)}'),
              subtitle: const Text('Claimed vouchers expire on this date, or after 30 days if none.', style: TextStyle(fontSize: 12)),
              trailing: _endsAt == null ? null : IconButton(icon: const Icon(AppIcons.x), onPressed: () => setState(() => _endsAt = null)),
              onTap: _pickEnd,
            ),
            TextFormField(
              controller: _desc,
              maxLines: 2,
              maxLength: 200,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Description', hintText: 'What members get'),
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _terms,
              maxLines: 2,
              maxLength: 200,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Terms', hintText: 'Dine-in only, one per table…'),
            ),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              value: _active,
              onChanged: (v) => setState(() => _active = v),
              title: const Text('Live in the Rewards shop'),
            ),
            const SizedBox(height: 8),
            PrimaryButton(label: editing ? 'Save' : 'Publish voucher', loading: _busy, onPressed: _save),
            const SizedBox(height: 8),
            Text(
              'When a member redeems, you type the bill and the platform books 1% of it as commission.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: AppColors.textMuted),
            ),
          ],
        ),
      ),
    );
  }
}
