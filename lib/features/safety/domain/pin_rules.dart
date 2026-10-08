/// The wallet PIN rules, mirroring the server's `wallet_pin_check_new` and
/// `wallet_pin_is_trivial` (supabase/migrations/20261009000130_wallet_pin.sql).
library;

const kPinLength = 6;

final _sixDigits = RegExp(r'^[0-9]{6}$');
final _oneDigit = RegExp(r'^(.)\1{5}$'); // 111111
final _pair = RegExp(r'^(..)\1\1$'); // 121212
final _triple = RegExp(r'^(...)\1$'); // 123123

/// Too easy to guess: one digit repeated, a pair or triple repeated, or a
/// straight run up or down (123456, 654321).
bool isTrivialPin(String pin) =>
    _oneDigit.hasMatch(pin) ||
    _pair.hasMatch(pin) ||
    _triple.hasMatch(pin) ||
    '0123456789'.contains(pin) ||
    '9876543210'.contains(pin);

/// Null when [pin] is fine as a new PIN, else the short reason.
String? newPinProblem(String pin) {
  if (!_sixDigits.hasMatch(pin)) return 'Your PIN must be 6 digits.';
  if (isTrivialPin(pin)) return 'That PIN is too easy to guess. Pick another.';
  return null;
}
