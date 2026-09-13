import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/app_art.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/dates.dart';
import '../../../core/utils/friendly_error.dart';
import '../../../core/widgets/photo_picker_sheet.dart';
import '../../../core/widgets/primary_button.dart';
import '../../../core/widgets/user_avatar.dart';
import '../application/vendors_providers.dart';
import '../domain/vendor.dart';

/// Vendor side, after scanning a member's voucher QR: confirm who/what, type
/// the bill, optionally snap the receipt, redeem. Commission is computed
/// server-side from the bill.
class RedeemScreen extends ConsumerStatefulWidget {
  const RedeemScreen({super.key, required this.claimId, required this.code});
  final String claimId;
  final String code;

  @override
  ConsumerState<RedeemScreen> createState() => _RedeemScreenState();
}

class _RedeemScreenState extends ConsumerState<RedeemScreen> {
  final _bill = TextEditingController();
  final _note = TextEditingController();
  late Future<ClaimLookup> _lookup;
  XFile? _receipt;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _lookup = ref.read(vendorActionsProvider).lookup(claimId: widget.claimId, code: widget.code);
  }

  @override
  void dispose() {
    _bill.dispose();
    _note.dispose();
    super.dispose();
  }

  double get _billValue => double.tryParse(_bill.text.trim()) ?? 0;

  Future<void> _redeem(ClaimLookup c) async {
    final bill = _billValue;
    if (bill <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Type the bill total first.')));
      return;
    }
    if (c.minSpend > 0 && bill < c.minSpend) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('This voucher needs a minimum spend of ${rm(c.minSpend)}.')));
      return;
    }
    setState(() => _busy = true);
    try {
      final r = await ref.read(vendorActionsProvider).redeem(claimId: widget.claimId, code: widget.code, bill: bill, receipt: _receipt, note: _note.text.trim());
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const ArtIcon(AppArt.check, size: 64),
              const SizedBox(height: 12),
              const Text('Redeemed', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              Text('${r.title}\nBill ${rm(r.bill)} · commission ${rm(r.commission)}', textAlign: TextAlign.center, style: const TextStyle(color: AppColors.textSecondary, height: 1.4)),
            ],
          ),
          actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('Done'))],
        ),
      );
      if (mounted) context.pushReplacement(Routes.vendor);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(AppIcons.arrowLeft), onPressed: () => context.pop()),
        title: const Text('Redeem voucher'),
      ),
      body: FutureBuilder<ClaimLookup>(
        future: _lookup,
        builder: (context, snap) {
          if (snap.hasError) {
            return Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const ArtIcon(AppArt.prohibited, size: 72),
                  const SizedBox(height: 14),
                  Text(friendlyError(snap.error!), textAlign: TextAlign.center, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 18),
                  PrimaryButton(label: 'Scan another', onPressed: () => context.pushReplacement(Routes.scan)),
                ],
              ),
            );
          }
          if (!snap.hasData) return const Center(child: CircularProgressIndicator(strokeWidth: 2));
          final c = snap.data!;
          final usable = c.status == ClaimStatus.active;
          final commission = (_billValue * c.commissionRate);
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: usable ? AppColors.warnColor : AppColors.surfaceGray,
                  borderRadius: BorderRadius.circular(AppRadius.lg),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(c.headline, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800, height: 1)),
                    const SizedBox(height: 4),
                    Text(c.title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                    if (c.terms != null) ...[const SizedBox(height: 6), Text(c.terms!, style: const TextStyle(fontSize: 13, color: Colors.black87))],
                    if (c.minSpend > 0) Text('Min spend ${rm(c.minSpend)}', style: const TextStyle(fontSize: 13, color: Colors.black87)),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        UserAvatar(url: c.avatarUrl, name: c.displayName ?? c.username, size: 32),
                        const SizedBox(width: 8),
                        Expanded(child: Text('@${c.username ?? ''} · ${c.displayName ?? ''}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600))),
                        Text(
                          usable ? 'valid till ${formatDate(c.expiresAt)}' : c.status.label.toUpperCase(),
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: usable ? Colors.black87 : AppColors.danger),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (!usable) ...[
                const SizedBox(height: 20),
                Text(
                  c.status == ClaimStatus.redeemed
                      ? 'This voucher was already used${c.redeemedAt == null ? '' : ' on ${formatEventDate(c.redeemedAt!)}'}.'
                      : 'This voucher is ${c.status.label.toLowerCase()} and cannot be used.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppColors.textSecondary, height: 1.4),
                ),
                const SizedBox(height: 18),
                PrimaryButton(label: 'Scan another', onPressed: () => context.pushReplacement(Routes.scan)),
              ] else ...[
                const SizedBox(height: 20),
                TextField(
                  controller: _bill,
                  autofocus: true,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  onChanged: (_) => setState(() {}),
                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
                  decoration: const InputDecoration(labelText: 'Bill total (after discount)', prefixText: 'RM ', hintText: '0.00'),
                ),
                const SizedBox(height: 6),
                Text(
                  'Platform commission ${(c.commissionRate * 100).toStringAsFixed(c.commissionRate * 100 % 1 == 0 ? 0 : 2)}% = ${rm(commission)}',
                  style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    GestureDetector(
                      onTap: () async {
                        final files = await pickPhotos(context, max: 1, multi: false);
                        if (files.isNotEmpty) setState(() => _receipt = files.first);
                      },
                      child: Container(
                        width: 64,
                        height: 64,
                        decoration: BoxDecoration(
                          color: AppColors.surfaceGray,
                          borderRadius: BorderRadius.circular(AppRadius.md),
                          image: _receipt == null ? null : DecorationImage(image: FileImage(File(_receipt!.path)), fit: BoxFit.cover),
                        ),
                        child: _receipt == null ? const Icon(AppIcons.receipt, color: AppColors.textSecondary) : null,
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(child: Text('Snap the receipt (optional, helps with the monthly statement).', style: TextStyle(fontSize: 13, color: AppColors.textSecondary))),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(controller: _note, decoration: const InputDecoration(labelText: 'Note (optional)', hintText: 'Table 4, invoice no…')),
                const SizedBox(height: 20),
                PrimaryButton(label: 'Confirm redemption', loading: _busy, onPressed: () => _redeem(c)),
              ],
            ],
          );
        },
      ),
    );
  }
}
