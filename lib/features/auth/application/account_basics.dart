import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/legal/legal_text.dart';
import '../../../core/supabase/supabase_client.dart';
import '../../../core/utils/friendly_error.dart';
import '../data/auth_repository.dart';

/// The private half of an account: phone, accepted Terms, confirmed email,
/// linked sign-in methods. Every account must complete phone + Terms once
/// (the router sends people to onboarding until then).
class AccountBasics {
  const AccountBasics({this.phone, this.termsAcceptedAt, this.termsVersion, this.emailConfirmed = false, this.providers = const []});
  final String? phone;
  final DateTime? termsAcceptedAt;
  final String? termsVersion;
  final bool emailConfirmed;
  /// 'email', 'google', …
  final List<String> providers;

  bool get hasPhone => phone != null && phone!.isNotEmpty;
  bool get acceptedCurrentTerms => termsAcceptedAt != null && termsVersion == kTermsVersion;
  /// Missing phone or (current) Terms → "Complete your account".
  bool get complete => hasPhone && acceptedCurrentTerms;
  bool get hasPassword => providers.contains('email');
  bool get hasGoogle => providers.contains('google');

  factory AccountBasics.fromMap(Map<String, dynamic> m) => AccountBasics(
        phone: m['phone'] as String?,
        termsAcceptedAt: m['terms_accepted_at'] == null ? null : DateTime.parse(m['terms_accepted_at'] as String),
        termsVersion: m['terms_version'] as String?,
        emailConfirmed: m['email_confirmed'] as bool? ?? false,
        providers: ((m['providers'] as List?) ?? const []).cast<String>(),
      );
}

final accountBasicsProvider = FutureProvider<AccountBasics?>((ref) async {
  final me = ref.watch(currentUserIdProvider);
  if (me == null) return null;
  final rows = await ref.read(supabaseProvider).rpc('my_account_basics') as List;
  if (rows.isEmpty) return const AccountBasics();
  return AccountBasics.fromMap((rows.first as Map).cast<String, dynamic>());
});

/// "+60 12-345 6789", "0123456789", "60123456789" → "+60123456789".
/// Numbers without a country code are assumed Malaysian.
String? normalizePhone(String raw) {
  var s = raw.replaceAll(RegExp(r'[\s\-().]'), '');
  if (s.isEmpty) return null;
  if (s.startsWith('00')) s = '+${s.substring(2)}';
  if (s.startsWith('+')) {
    // international as typed
  } else if (s.startsWith('0')) {
    s = '+60${s.substring(1)}';
  } else if (s.startsWith('60')) {
    s = '+$s';
  } else if (s.startsWith('1') && s.length >= 9 && s.length <= 10) {
    s = '+60$s';
  } else {
    return null;
  }
  return RegExp(r'^\+[1-9][0-9]{7,14}$').hasMatch(s) ? s : null;
}

/// "+60123456789" → "+60 12-345 6789" (Malaysian) or "+65 9123 4567".
String prettyPhone(String e164) {
  if (e164.startsWith('+60')) {
    final n = e164.substring(3);
    if (n.length >= 9) return '+60 ${n.substring(0, 2)}-${n.substring(2, n.length - 4)} ${n.substring(n.length - 4)}';
  }
  return e164;
}

class AccountActions {
  AccountActions(this._ref);
  final Ref _ref;

  Future<void> setBasics({required String phone, required bool acceptedTerms}) async {
    final e164 = normalizePhone(phone);
    if (e164 == null) throw const AppException('Enter a valid phone number, e.g. 012-345 6789.');
    if (!acceptedTerms) throw const AppException('Please accept the Terms of Use and Privacy Policy.');
    await _ref.read(supabaseProvider).rpc('set_account_basics', params: {'p_phone': e164, 'p_terms_version': kTermsVersion});
    _ref.invalidate(accountBasicsProvider);
  }

  Future<void> setPhone(String phone) async {
    final e164 = normalizePhone(phone);
    if (e164 == null) throw const AppException('Enter a valid phone number, e.g. 012-345 6789.');
    await _ref.read(supabaseProvider).rpc('set_my_phone', params: {'p_phone': e164});
    _ref.invalidate(accountBasicsProvider);
  }

  Future<void> linkGoogle() async {
    await _ref.read(authRepositoryProvider).linkGoogle();
    _ref.invalidate(accountBasicsProvider);
  }

  Future<void> unlinkGoogle() async {
    await _ref.read(authRepositoryProvider).unlinkProvider('google');
    _ref.invalidate(accountBasicsProvider);
  }

  /// Google-only accounts: give the account a password so email login works too.
  Future<void> setPassword(String password) async {
    if (password.length < 6) throw const AppException('Use at least 6 characters.');
    await _ref.read(authRepositoryProvider).updatePassword(password);
    _ref.invalidate(accountBasicsProvider);
  }
}

final accountActionsProvider = Provider<AccountActions>((ref) => AccountActions(ref));
