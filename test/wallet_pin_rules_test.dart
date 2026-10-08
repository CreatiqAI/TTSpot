import 'package:car_meet/features/safety/application/wallet_pin.dart';
import 'package:car_meet/features/safety/domain/pin_rules.dart';
import 'package:car_meet/features/safety/presentation/wallet_pin_sheet.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  group('trivial PINs (mirrors wallet_pin_is_trivial on the server)', () {
    test('same digit, straight runs and repeats are refused', () {
      for (final p in [
        '000000', '111111', '999999', // one digit
        '123456', '234567', '456789', '012345', // straight up
        '654321', '987654', '543210', // straight down
        '121212', '909090', // a pair repeated
        '123123', '420420', // a triple repeated
      ]) {
        expect(isTrivialPin(p), isTrue, reason: p);
        expect(newPinProblem(p), 'That PIN is too easy to guess. Pick another.', reason: p);
      }
    });

    test('ordinary PINs pass', () {
      for (final p in ['482915', '739164', '583920', '927461', '102938', '112233', '135790']) {
        expect(isTrivialPin(p), isFalse, reason: p);
        expect(newPinProblem(p), isNull, reason: p);
      }
    });

    test('anything but exactly 6 digits is refused', () {
      for (final p in ['', '12345', '1234567', '12a456', ' 48291', '48291 ', '４８２９１５']) {
        expect(newPinProblem(p), 'Your PIN must be 6 digits.', reason: p);
      }
    });
  });

  group('unlock memory', () {
    test('lasts until the server time, capped just under 5 minutes', () {
      var now = DateTime(2026, 10, 9, 12);
      final m = WalletUnlockMemory(clock: () => now);
      expect(m.unlocked, isFalse);

      m.remember(now.add(const Duration(minutes: 5)));
      expect(m.unlocked, isTrue);
      now = now.add(const Duration(minutes: 4, seconds: 29));
      expect(m.unlocked, isTrue);
      now = now.add(const Duration(seconds: 2));
      expect(m.unlocked, isFalse, reason: 'kept shorter than the server window');

      m.remember(now.add(const Duration(minutes: 1)));
      now = now.add(const Duration(minutes: 1, seconds: 1));
      expect(m.unlocked, isFalse, reason: 'an earlier server expiry wins');

      m.remember(null);
      expect(m.unlocked, isTrue);
      m.forget();
      expect(m.unlocked, isFalse);
    });
  });

  test('the server codes are recognised', () {
    expect(walletPinErrorCode(const PostgrestException(message: 'PIN_REQUIRED')), kPinRequired);
    expect(walletPinErrorCode(const PostgrestException(message: 'PIN_SETUP_REQUIRED')), kPinSetupRequired);
    expect(walletPinErrorCode(const PostgrestException(message: 'This voucher has ended')), isNull);
    expect(walletPinErrorCode(Exception('PIN_REQUIRED')), isNull);
  });

  test('lockout text counts the minutes left', () {
    final now = DateTime(2026, 10, 9, 12);
    expect(walletLockText(now.add(const Duration(minutes: 15)), now: now), 'Too many tries. Try again in 15 minutes.');
    expect(walletLockText(now.add(const Duration(minutes: 3, seconds: 10)), now: now), 'Too many tries. Try again in 4 minutes.');
    expect(walletLockText(now.add(const Duration(seconds: 20)), now: now), 'Too many tries. Try again in 1 minute.');
  });
}
