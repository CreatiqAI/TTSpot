import 'package:car_meet/core/theme/app_theme.dart';
import 'package:car_meet/features/safety/application/wallet_pin.dart';
import 'package:car_meet/features/safety/data/wallet_pin_repository.dart';
import 'package:car_meet/features/safety/presentation/wallet_pin_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// The wallet PIN RPCs, with a real PIN and the server's 5-try lockout.
class _FakeRepo implements WalletPinRepository {
  _FakeRepo();
  String pin = '482915';
  int failed = 0;
  final verifies = <String>[];
  final sets = <(String, String?)>[];
  final resets = <String>[];

  DateTime get _exp => DateTime.now().add(const Duration(minutes: 5));

  @override
  Future<WalletPinStatus> status() async => const WalletPinStatus(hasPin: true);

  @override
  Future<WalletPinResult> verify(String p) async {
    verifies.add(p);
    if (p == pin) return WalletPinResult(ok: true, expiresAt: _exp);
    failed++;
    if (failed >= 5) {
      return WalletPinResult(ok: false, code: 'LOCKED', error: 'Too many tries. Try again in 15 minutes.', lockedUntil: DateTime.now().add(const Duration(minutes: 15)));
    }
    final left = 5 - failed;
    return WalletPinResult(ok: false, code: 'WRONG', error: 'Wrong PIN. $left ${left == 1 ? 'try' : 'tries'} left.');
  }

  @override
  Future<WalletPinResult> set(String p, {String? oldPin}) async {
    sets.add((p, oldPin));
    if (oldPin != null && oldPin != pin) return const WalletPinResult(ok: false, code: 'WRONG', error: 'Wrong current PIN. 4 tries left.');
    pin = p;
    return WalletPinResult(ok: true, expiresAt: _exp);
  }

  @override
  Future<WalletPinResult> reset(String p) async {
    resets.add(p);
    pin = p;
    return WalletPinResult(ok: true, expiresAt: _exp);
  }
}

class _FakeReauth extends WalletReauth {
  _FakeReauth(super.ref, {this.hasPassword = true});
  final bool hasPassword;
  final passwords = <String>[];

  @override
  Future<({bool password, bool apple})> methods() async => (password: hasPassword, apple: false);

  @override
  Future<void> password(String password) async => passwords.add(password);
}

late _FakeRepo _repo;
late _FakeReauth _reauth;
DateTime? _result;
bool _closed = false;

Future<void> _open(WidgetTester t, WalletPinMode mode, {DateTime? lockedUntil, double scale = 1, Size size = const Size(393, 851), bool hasPassword = true}) async {
  _result = null;
  _closed = false;
  t.view.physicalSize = size * 3;
  t.view.devicePixelRatio = 3;
  addTearDown(t.view.reset);
  await t.pumpWidget(ProviderScope(
    overrides: [
      walletPinRepositoryProvider.overrideWithValue(_repo),
      walletReauthProvider.overrideWith((ref) => _reauth = _FakeReauth(ref, hasPassword: hasPassword)),
    ],
    child: MaterialApp(
      theme: AppTheme.current,
      builder: (context, c) => MediaQuery(data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)), child: c!),
      home: Scaffold(
        body: Builder(
          builder: (ctx) => Center(
            child: TextButton(
              onPressed: () async {
                _result = await showWalletPinSheet(ctx, mode, lockedUntil: lockedUntil);
                _closed = true;
              },
              child: const Text('OPEN'),
            ),
          ),
        ),
      ),
    ),
  ));
  await t.tap(find.text('OPEN'));
  await t.pumpAndSettle();
}

Future<void> _type(WidgetTester t, String digits) async {
  for (final d in digits.split('')) {
    await t.tap(find.byKey(Key('pin-key-$d')));
    await t.pump();
  }
  await t.pumpAndSettle();
}

String _error(WidgetTester t) => t.widget<Text>(find.byKey(const Key('pin-error'))).data ?? '';

void main() {
  setUp(() => _repo = _FakeRepo());

  testWidgets('setup: enter, a mismatch starts over, then enter and confirm', (t) async {
    await _open(t, WalletPinMode.setup);
    expect(find.text('Set your wallet PIN'), findsOneWidget);
    expect(find.text(kWalletPinBlurb), findsOneWidget);

    // the delete key takes a digit back
    await _type(t, '73');
    await t.tap(find.byKey(const Key('pin-key-del')));
    await t.pump();
    await _type(t, '9164');
    expect(find.text('Enter it again'), findsNothing, reason: 'only 5 digits so far');
    await _type(t, '5');
    expect(find.text('Enter it again'), findsOneWidget);

    await _type(t, '111222');
    expect(find.text('Set your wallet PIN'), findsOneWidget);
    expect(_error(t), "PINs don't match. Try again.");
    expect(_repo.sets, isEmpty);

    await _type(t, '739164');
    await _type(t, '739164');
    expect(_repo.sets, [('739164', null)]);
    expect(_closed, isTrue);
    expect(_result, isNotNull);
  });

  testWidgets('setup refuses an easy PIN before asking to confirm it', (t) async {
    await _open(t, WalletPinMode.setup);
    await _type(t, '123456');
    expect(_error(t), 'That PIN is too easy to guess. Pick another.');
    expect(find.text('Set your wallet PIN'), findsOneWidget);
  });

  testWidgets('unlock: a wrong PIN says how many tries are left, the right one closes', (t) async {
    await _open(t, WalletPinMode.unlock);
    expect(find.text('Enter your wallet PIN'), findsOneWidget);
    await _type(t, '000001');
    expect(_error(t), 'Wrong PIN. 4 tries left.');
    expect(_closed, isFalse);

    await _type(t, '482915');
    expect(_repo.verifies, ['000001', '482915']);
    expect(_closed, isTrue);
    expect(_result, isNotNull);
  });

  testWidgets('unlock: the fifth wrong PIN locks the pad for 15 minutes', (t) async {
    await _open(t, WalletPinMode.unlock);
    for (var i = 0; i < 5; i++) {
      await _type(t, '000001');
    }
    expect(_error(t), 'Too many tries. Try again in 15 minutes.');
    // the pad is off: no more tries reach the server
    await _type(t, '482915');
    expect(_repo.verifies.length, 5);
    expect(_closed, isFalse);
    expect(find.byKey(const Key('pin-forgot')), findsOneWidget, reason: 'Forgot PIN still works while locked');
  });

  testWidgets('opened while locked out: says so straight away', (t) async {
    await _open(t, WalletPinMode.unlock, lockedUntil: DateTime.now().add(const Duration(minutes: 9, seconds: 30)));
    expect(_error(t), 'Too many tries. Try again in 10 minutes.');
    await _type(t, '482915');
    expect(_repo.verifies, isEmpty);
  });

  testWidgets('change: wrong current PIN goes back to it', (t) async {
    await _open(t, WalletPinMode.change);
    expect(find.text('Enter your current PIN'), findsOneWidget);
    await _type(t, '000001');
    expect(find.text('Pick a new PIN'), findsOneWidget);
    await _type(t, '739164');
    await _type(t, '739164');
    expect(_repo.sets.single, ('739164', '000001'));
    expect(find.text('Enter your current PIN'), findsOneWidget);
    expect(_error(t), 'Wrong current PIN. 4 tries left.');
  });

  testWidgets('forgot PIN: password, then a new PIN goes to reset', (t) async {
    await _open(t, WalletPinMode.unlock);
    await t.tap(find.byKey(const Key('pin-forgot')));
    await t.pumpAndSettle();
    expect(find.text('Forgot your PIN?'), findsOneWidget);
    await t.enterText(find.byKey(const Key('pin-password')), 'hunter22');
    await t.tap(find.text('Continue'));
    await t.pumpAndSettle();
    expect(_reauth.passwords, ['hunter22']);
    expect(find.text('Pick a new PIN'), findsOneWidget);
    await _type(t, '927461');
    await _type(t, '927461');
    expect(_repo.resets, ['927461']);
    expect(_closed, isTrue);
  });

  testWidgets('forgot PIN without a password: log out and back in', (t) async {
    await _open(t, WalletPinMode.reset, hasPassword: false);
    expect(find.textContaining('Log out, log back in'), findsOneWidget);
    expect(find.text('I just logged in'), findsOneWidget);
  });

  for (final scale in [1.0, 1.3]) {
    testWidgets('the pad fits a 360-wide phone at text scale $scale', (t) async {
      await _open(t, WalletPinMode.unlock, scale: scale, size: const Size(360, 640));
      expect(t.takeException(), isNull);
      for (final d in ['1', '5', '9', '0', 'del']) {
        expect(find.byKey(Key('pin-key-$d')).hitTestable(), findsOneWidget, reason: d);
      }
      await _type(t, '000001');
      expect(t.takeException(), isNull);
    });
  }
}
