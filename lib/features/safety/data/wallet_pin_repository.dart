import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/supabase_client.dart';

/// `wallet_pin_status()`: does the member have a PIN, and is it locked out
/// or unlocked right now.
class WalletPinStatus {
  const WalletPinStatus({required this.hasPin, this.lockedUntil, this.unlockedUntil});
  final bool hasPin;
  final DateTime? lockedUntil;
  final DateTime? unlockedUntil;

  factory WalletPinStatus.fromMap(Map<String, dynamic> m) => WalletPinStatus(
        hasPin: m['has_pin'] == true,
        lockedUntil: _time(m['locked_until']),
        unlockedUntil: _time(m['unlocked_until']),
      );
}

/// The reply of verify / set / reset. [ok] with [expiresAt] (the wallet is
/// unlocked until then), or a [code] ('WRONG', 'LOCKED', 'OLD_PIN_REQUIRED',
/// 'PIN_SETUP_REQUIRED') and a short [error] to show.
class WalletPinResult {
  const WalletPinResult({required this.ok, this.expiresAt, this.code, this.error, this.lockedUntil});
  final bool ok;
  final DateTime? expiresAt;
  final String? code;
  final String? error;
  final DateTime? lockedUntil;

  bool get locked => code == 'LOCKED';

  factory WalletPinResult.fromMap(Map<String, dynamic> m) => WalletPinResult(
        ok: m['ok'] == true,
        expiresAt: _time(m['expires_at']),
        code: m['code'] as String?,
        error: m['error'] as String?,
        lockedUntil: _time(m['locked_until']),
      );
}

DateTime? _time(Object? v) => v == null ? null : DateTime.parse(v as String).toLocal();

/// The wallet PIN RPCs (20261009000130_wallet_pin.sql). Bad input and a
/// stale sign-in on reset throw; wrong PINs come back as a result, because
/// the server keeps count.
class WalletPinRepository {
  WalletPinRepository(this._db);
  final SupabaseClient _db;

  Map<String, dynamic> _map(Object? v) => (v as Map).cast<String, dynamic>();

  Future<WalletPinStatus> status() async => WalletPinStatus.fromMap(_map(await _db.rpc('wallet_pin_status')));

  Future<WalletPinResult> verify(String pin) async => WalletPinResult.fromMap(_map(await _db.rpc('verify_wallet_pin', params: {'p_pin': pin})));

  /// First set (no [oldPin]) or change (needs [oldPin]).
  Future<WalletPinResult> set(String pin, {String? oldPin}) async =>
      WalletPinResult.fromMap(_map(await _db.rpc('set_wallet_pin', params: {'p_pin': pin, 'p_old_pin': oldPin})));

  /// Forgot PIN, right after a fresh sign-in. Throws REAUTH_REQUIRED if not.
  Future<WalletPinResult> reset(String pin) async => WalletPinResult.fromMap(_map(await _db.rpc('reset_wallet_pin', params: {'p_new_pin': pin})));
}

final walletPinRepositoryProvider = Provider<WalletPinRepository>((ref) => WalletPinRepository(ref.watch(supabaseProvider)));
