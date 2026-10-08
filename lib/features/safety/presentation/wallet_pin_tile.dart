import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/friendly_error.dart';
import '../application/wallet_pin.dart';
import 'wallet_pin_sheet.dart';

/// Settings → Security → Wallet PIN: set it, change it, or reset it.
class WalletPinTile extends ConsumerWidget {
  const WalletPinTile({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(walletPinStatusProvider);
    final has = status.value?.hasPin;
    return ListTile(
      key: const Key('settings-wallet-pin'),
      leading: Icon(AppIcons.lock, color: AppColors.textPrimary),
      title: const Text('Wallet PIN', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14.5)),
      subtitle: Text(
        has == null ? kWalletPinBlurb : (has ? 'On · change or reset it' : 'Not set · $kWalletPinBlurb'),
        style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
      ),
      trailing: Icon(AppIcons.caretRight, size: 16, color: AppColors.textMuted),
      onTap: () => _open(context, ref),
    );
  }

  Future<void> _open(BuildContext context, WidgetRef ref) async {
    final bool has;
    try {
      has = (await ref.read(walletPinStatusProvider.future))?.hasPin ?? false;
    } catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e))));
      return;
    }
    if (!context.mounted) return;
    var mode = WalletPinMode.setup;
    if (has) {
      final picked = await showModalBottomSheet<WalletPinMode>(
        useRootNavigator: true, // above the shell tab bar
        context: context,
        showDragHandle: true,
        builder: (ctx) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Padding(padding: EdgeInsets.fromLTRB(20, 0, 20, 4), child: Text('Wallet PIN', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800))),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Text(kWalletPinBlurb, style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary)),
              ),
              ListTile(
                key: const Key('wallet-pin-change'),
                leading: Icon(AppIcons.pencilSimple, color: AppColors.textPrimary),
                title: const Text('Change PIN', style: TextStyle(fontWeight: FontWeight.w600)),
                onTap: () => Navigator.pop(ctx, WalletPinMode.change),
              ),
              ListTile(
                key: const Key('wallet-pin-reset'),
                leading: Icon(AppIcons.arrowCounterClockwise, color: AppColors.textPrimary),
                title: const Text('Forgot PIN?', style: TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text('Confirm it is you, then pick a new one', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                onTap: () => Navigator.pop(ctx, WalletPinMode.reset),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      );
      if (picked == null || !context.mounted) return;
      mode = picked;
    }
    final until = await showWalletPinSheet(context, mode);
    if (until == null) return;
    ref.read(walletUnlockMemoryProvider).remember(until);
    ref.invalidate(walletPinStatusProvider);
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Wallet PIN saved.')));
  }
}
