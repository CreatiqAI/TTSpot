import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/supabase_client.dart';
import '../../auth/application/account_basics.dart';
import '../../auth/data/auth_repository.dart';
import '../data/wallet_pin_repository.dart';
import '../presentation/wallet_pin_sheet.dart';

/// The wallet PIN guards every member value action: card trades (offer,
/// accept, gift), points vouchers, blind boxes and card prizes. The server
/// refuses those with these stable messages until the wallet is unlocked.
const kPinRequired = 'PIN_REQUIRED';
const kPinSetupRequired = 'PIN_SETUP_REQUIRED';
const kReauthRequired = 'REAUTH_REQUIRED';

/// [kPinRequired] or [kPinSetupRequired] when [e] is the server asking for
/// the PIN, else null.
String? walletPinErrorCode(Object e) {
  if (e is! PostgrestException) return null;
  return e.message == kPinRequired || e.message == kPinSetupRequired ? e.message : null;
}

/// How long the unlock lasts on the server (`verify_wallet_pin`).
const kWalletUnlockFor = Duration(minutes: 5);

/// Remembers an unlock on this phone so actions within 5 minutes don't ask
/// again. Kept a little shorter than the server's window so the phone never
/// thinks it's unlocked when the server doesn't; if it ever does, the server
/// says PIN_REQUIRED and [runWithWalletPin] asks once more.
class WalletUnlockMemory {
  WalletUnlockMemory({DateTime Function()? clock}) : _now = clock ?? DateTime.now;
  final DateTime Function() _now;
  DateTime? _until;

  bool get unlocked {
    final until = _until;
    return until != null && _now().isBefore(until);
  }

  void remember(DateTime? serverUntil) {
    final cap = _now().add(kWalletUnlockFor - const Duration(seconds: 30));
    _until = serverUntil == null || serverUntil.isAfter(cap) ? cap : serverUntil;
  }

  void forget() => _until = null;
}

/// One per signed-in member (a new account starts locked).
final walletUnlockMemoryProvider = Provider<WalletUnlockMemory>((ref) {
  ref.watch(currentUserIdProvider);
  return WalletUnlockMemory();
});

/// For Settings → Wallet PIN.
final walletPinStatusProvider = FutureProvider.autoDispose<WalletPinStatus?>((ref) async {
  if (ref.watch(currentUserIdProvider) == null) return null;
  return ref.watch(walletPinRepositoryProvider).status();
});

/// Opens the right sheet when the wallet is locked: "Set your wallet PIN"
/// the first time, the PIN pad after that. Tests swap it for a fake.
class WalletGate {
  const WalletGate();

  /// True once the wallet is unlocked; false if the member backed out.
  /// [force] skips the remembered unlock (the server just said no).
  Future<bool> ensureUnlocked(BuildContext context, WidgetRef ref, {bool force = false}) async {
    final memory = ref.read(walletUnlockMemoryProvider);
    if (!force && memory.unlocked) return true;
    final status = await ref.read(walletPinRepositoryProvider).status();
    if (!force && status.unlockedUntil != null) {
      memory.remember(status.unlockedUntil);
      return true;
    }
    if (!context.mounted) return false;
    final until = await showWalletPinSheet(
      context,
      status.hasPin ? WalletPinMode.unlock : WalletPinMode.setup,
      lockedUntil: status.lockedUntil,
    );
    if (until == null) return false;
    memory.remember(until);
    ref.invalidate(walletPinStatusProvider);
    return true;
  }

  void forget(WidgetRef ref) => ref.read(walletUnlockMemoryProvider).forget();
}

final walletGateProvider = Provider<WalletGate>((ref) => const WalletGate());

/// Call before any action that moves cards, points or vouchers. True when
/// it's fine to go ahead.
Future<bool> ensureWalletUnlocked(BuildContext context, WidgetRef ref) => ref.read(walletGateProvider).ensureUnlocked(context, ref);

/// Runs a protected [action]: unlocks the wallet first (unless [askFirst]
/// is false, e.g. a voucher that might be free), and if the server still
/// says PIN_REQUIRED / PIN_SETUP_REQUIRED, shows the sheet and retries once.
/// False when the member backed out of the PIN sheet; other errors throw.
Future<bool> runWithWalletPin(BuildContext context, WidgetRef ref, Future<void> Function() action, {bool askFirst = true}) async {
  final gate = ref.read(walletGateProvider);
  if (askFirst && !await gate.ensureUnlocked(context, ref)) return false;
  try {
    await action();
    return true;
  } catch (e) {
    if (walletPinErrorCode(e) == null || !context.mounted) rethrow;
    gate.forget(ref);
    if (!await gate.ensureUnlocked(context, ref, force: true)) return false;
    await action();
    return true;
  }
}

// ------------------------------------------------------------- re-auth ---

/// Forgot PIN needs a fresh sign-in (the server checks it's < 2 minutes old).
/// Password accounts type their password; Apple accounts run Sign in with
/// Apple again; anyone else signs out and back in.
class WalletReauth {
  WalletReauth(this._ref);
  final Ref _ref;

  Future<({bool password, bool apple})> methods() async {
    final b = await _ref.read(accountBasicsProvider.future) ?? const AccountBasics();
    return (password: b.hasPassword, apple: b.hasApple);
  }

  /// Signs in again with the account's own email (a new session).
  Future<void> password(String password) async {
    final user = _ref.read(supabaseProvider).auth.currentUser;
    final id = user?.email;
    if (id == null || id.isEmpty) throw const AuthException('No email on this account', code: 'invalid_credentials');
    await _ref.read(authRepositoryProvider).signInWithEmail(email: id, password: password);
  }

  /// Sign in with Apple again (iPhone).
  Future<void> apple() => _ref.read(authRepositoryProvider).signInWithApple();
}

final walletReauthProvider = Provider<WalletReauth>((ref) => WalletReauth(ref));
