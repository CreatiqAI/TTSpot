import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show AuthException, PostgrestException;

import '../../../core/theme/app_art.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/friendly_error.dart';
import '../../../core/widgets/primary_button.dart';
import '../../../core/widgets/sheet_header.dart';
import '../application/wallet_pin.dart';
import '../data/wallet_pin_repository.dart';
import '../domain/pin_rules.dart';

/// What the sheet is for. [setup]: first PIN (enter, confirm). [unlock]: the
/// PIN pad before a value action. [change]: old PIN, then a new one.
/// [reset]: Forgot PIN (confirm it's you, then a new one).
enum WalletPinMode { setup, unlock, change, reset }

enum _Step { current, fresh, confirm, forgot }

const kWalletPinBlurb = 'Protects your cards, points and vouchers.';

/// Opens the wallet PIN sheet. Returns when the wallet is unlocked until
/// (every successful mode unlocks it for 5 minutes), or null if closed.
Future<DateTime?> showWalletPinSheet(BuildContext context, WalletPinMode mode, {DateTime? lockedUntil}) => showModalBottomSheet<DateTime>(
      context: context,
      useRootNavigator: true, // above the shell tab bar
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => WalletPinSheet(mode: mode, lockedUntil: lockedUntil),
    );

/// "Too many tries. Try again in 12 minutes."
String walletLockText(DateTime until, {DateTime? now}) {
  final secs = until.difference(now ?? DateTime.now()).inSeconds;
  final m = (secs / 60).ceil().clamp(1, 999);
  return 'Too many tries. Try again in $m minute${m == 1 ? '' : 's'}.';
}

class WalletPinSheet extends ConsumerStatefulWidget {
  const WalletPinSheet({super.key, required this.mode, this.lockedUntil});
  final WalletPinMode mode;
  final DateTime? lockedUntil;

  @override
  ConsumerState<WalletPinSheet> createState() => _WalletPinSheetState();
}

class _WalletPinSheetState extends ConsumerState<WalletPinSheet> {
  late WalletPinMode _mode = widget.mode;
  late _Step _step;
  String _entry = '';
  String? _first; // the new PIN, waiting for its confirm
  String? _old; // change: the current PIN, checked when saving
  String? _error;
  bool _busy = false;
  bool _resetting = false; // signed in again, so the new PIN goes to reset
  DateTime? _lockedUntil;
  ({bool password, bool apple})? _methods;
  final _password = TextEditingController();

  @override
  void initState() {
    super.initState();
    _step = switch (_mode) {
      WalletPinMode.setup => _Step.fresh,
      WalletPinMode.unlock || WalletPinMode.change => _Step.current,
      WalletPinMode.reset => _Step.forgot,
    };
    final locked = widget.lockedUntil;
    if (locked != null && DateTime.now().isBefore(locked)) {
      _lockedUntil = locked;
      _error = walletLockText(locked);
    }
    if (_step == _Step.forgot) _loadMethods();
  }

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  bool get _locked {
    final until = _lockedUntil;
    return until != null && DateTime.now().isBefore(until);
  }

  WalletPinRepository get _repo => ref.read(walletPinRepositoryProvider);

  Future<void> _loadMethods() async {
    try {
      final m = await ref.read(walletReauthProvider).methods();
      if (mounted) setState(() => _methods = m);
    } catch (_) {
      if (mounted) setState(() => _methods = (password: false, apple: false));
    }
  }

  void _done(DateTime? until) {
    if (!mounted) return;
    Navigator.of(context).pop(until ?? DateTime.now().add(kWalletUnlockFor));
  }

  void _fail(String message) {
    HapticFeedback.mediumImpact();
    setState(() {
      _error = message;
      _entry = '';
    });
  }

  void _go(_Step step, {String? error}) => setState(() {
        _step = step;
        _entry = '';
        _error = error;
      });

  // ---------------------------------------------------------------- keys ---

  void _digit(String d) {
    if (_busy || _entry.length >= kPinLength) return;
    if (_locked && _step == _Step.current) {
      setState(() => _error = walletLockText(_lockedUntil!));
      return;
    }
    setState(() {
      _entry += d;
      if (!_locked) _error = null;
    });
    if (_entry.length == kPinLength) _submit();
  }

  void _delete() {
    if (_busy || _entry.isEmpty) return;
    setState(() => _entry = _entry.substring(0, _entry.length - 1));
  }

  Future<void> _submit() async {
    final pin = _entry;
    switch (_step) {
      case _Step.current:
        if (_mode == WalletPinMode.change) {
          _old = pin;
          _go(_Step.fresh);
          return;
        }
        await _call(() => _repo.verify(pin), onFail: (r) {
          if (r.code == kPinSetupRequired) {
            _mode = WalletPinMode.setup;
            _go(_Step.fresh);
          }
        });
      case _Step.fresh:
        final problem = newPinProblem(pin);
        if (problem != null) return _fail(problem);
        _first = pin;
        _go(_Step.confirm);
      case _Step.confirm:
        if (pin != _first) {
          _first = null;
          HapticFeedback.mediumImpact();
          _go(_Step.fresh, error: "PINs don't match. Try again.");
          return;
        }
        await _call(() => _resetting ? _repo.reset(pin) : _repo.set(pin, oldPin: _old), onFail: (r) {
          // change: the current PIN was wrong, so start again from it
          _old = null;
          _first = null;
          _go(_Step.current, error: r.error);
        });
      case _Step.forgot:
        break;
    }
  }

  /// Runs a PIN call: closes on success, shows the error (and any lockout)
  /// otherwise.
  Future<void> _call(Future<WalletPinResult> Function() f, {void Function(WalletPinResult r)? onFail}) async {
    setState(() => _busy = true);
    try {
      final r = await f();
      if (!mounted) return;
      if (r.ok) return _done(r.expiresAt);
      setState(() => _busy = false);
      if (r.locked) _lockedUntil = r.lockedUntil ?? DateTime.now().add(const Duration(minutes: 15));
      onFail?.call(r);
      if (r.code != kPinSetupRequired) _fail(r.error ?? 'Wrong PIN.');
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      if (e is PostgrestException && e.message == kReauthRequired) {
        _resetting = false;
        _go(_Step.forgot, error: friendlyError(e));
        _loadMethods();
        return;
      }
      _fail(friendlyError(e));
      if (_step == _Step.confirm) _go(_Step.fresh, error: friendlyError(e));
    }
  }

  // -------------------------------------------------------------- forgot ---

  void _forgot() {
    _go(_Step.forgot);
    _loadMethods();
  }

  Future<void> _reauth(Future<void> Function() signIn) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await signIn();
      if (!mounted) return;
      _password.clear();
      _resetting = true;
      _lockedUntil = null;
      _busy = false;
      _go(_Step.fresh);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e is AuthException && e.code == 'invalid_credentials' ? 'Wrong password.' : friendlyError(e);
      });
    }
  }

  // --------------------------------------------------------------- build ---

  String get _title => switch (_step) {
        _Step.current => _mode == WalletPinMode.change ? 'Enter your current PIN' : 'Enter your wallet PIN',
        _Step.fresh => _mode == WalletPinMode.setup ? 'Set your wallet PIN' : 'Pick a new PIN',
        _Step.confirm => 'Enter it again',
        _Step.forgot => 'Forgot your PIN?',
      };

  String get _subtitle => switch (_step) {
        _Step.current => kWalletPinBlurb,
        _Step.fresh => _mode == WalletPinMode.setup ? kWalletPinBlurb : '6 digits that are hard to guess.',
        _Step.confirm => 'Same 6 digits once more.',
        _Step.forgot => '',
      };

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, 0, 20, 12 + bottom),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SheetHeader(title: _title),
              if (_step == _Step.forgot) ..._forgotBody() else ..._padBody(),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _padBody() => [
        const SizedBox(height: 4),
        Row(
          children: [
            const ArtIcon(AppArt.locked, size: 22),
            const SizedBox(width: 8),
            Expanded(child: Text(_subtitle, style: TextStyle(fontSize: 13, color: AppColors.textSecondary))),
          ],
        ),
        const SizedBox(height: 22),
        PinDots(filled: _entry.length),
        const SizedBox(height: 12),
        ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 22),
          child: Center(
            child: _busy
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : Text(
                    _error ?? '',
                    key: const Key('pin-error'),
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.danger),
                  ),
          ),
        ),
        const SizedBox(height: 10),
        PinKeypad(onDigit: _digit, onDelete: _delete, enabled: !_busy && !(_locked && _step == _Step.current)),
        if (_step == _Step.current)
          Center(child: TextButton(key: const Key('pin-forgot'), onPressed: _busy ? null : _forgot, child: const Text('Forgot PIN?'))),
      ];

  List<Widget> _forgotBody() {
    final m = _methods;
    final apple = m != null && m.apple && defaultTargetPlatform == TargetPlatform.iOS;
    final errorText = _error == null
        ? null
        : Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(_error!, key: const Key('pin-error'), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.danger)),
          );
    final note = TextStyle(fontSize: 13.5, height: 1.4, color: AppColors.textSecondary);
    if (m == null) {
      return const [Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator(strokeWidth: 2)))];
    }
    if (m.password) {
      return [
        const SizedBox(height: 4),
        Text('Enter your TT Spot password to set a new PIN.', style: note),
        const SizedBox(height: 14),
        TextField(
          key: const Key('pin-password'),
          controller: _password,
          autofocus: true,
          obscureText: true,
          textInputAction: TextInputAction.done,
          decoration: const InputDecoration(hintText: 'Password', prefixIcon: Icon(AppIcons.lock, size: 20)),
          onSubmitted: (_) => _busy ? null : _reauth(() => ref.read(walletReauthProvider).password(_password.text)),
        ),
        ?errorText,
        const SizedBox(height: 14),
        PrimaryButton(label: 'Continue', loading: _busy, onPressed: () => _reauth(() => ref.read(walletReauthProvider).password(_password.text))),
      ];
    }
    if (apple) {
      return [
        const SizedBox(height: 4),
        Text('Confirm with Apple to set a new PIN.', style: note),
        ?errorText,
        const SizedBox(height: 14),
        PrimaryButton(label: 'Continue with Apple', loading: _busy, onPressed: () => _reauth(() => ref.read(walletReauthProvider).apple())),
      ];
    }
    return [
      const SizedBox(height: 4),
      Text('Log out, log back in, then come back here within 2 minutes to set a new PIN.', style: note),
      ?errorText,
      const SizedBox(height: 14),
      SecondaryButton(
        label: 'I just logged in',
        onPressed: () {
          _resetting = true;
          _lockedUntil = null;
          _go(_Step.fresh);
        },
      ),
    ];
  }
}

/// Six dots, [filled] of them dark.
class PinDots extends StatelessWidget {
  const PinDots({super.key, required this.filled});
  final int filled;

  @override
  Widget build(BuildContext context) => Semantics(
        label: '$filled of $kPinLength digits',
        child: Row(
          key: const Key('pin-dots'),
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (var i = 0; i < kPinLength; i++)
              AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                margin: const EdgeInsets.symmetric(horizontal: 8),
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: i < filled ? AppColors.textPrimary : Colors.transparent,
                  border: Border.all(color: i < filled ? AppColors.textPrimary : AppColors.textMuted, width: 1.6),
                ),
              ),
          ],
        ),
      );
}

/// The in-app number pad: big keys, no system keyboard.
class PinKeypad extends StatelessWidget {
  const PinKeypad({super.key, required this.onDigit, required this.onDelete, this.enabled = true});
  final ValueChanged<String> onDigit;
  final VoidCallback onDelete;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    Widget key(String d) => _Key(key: Key('pin-key-$d'), enabled: enabled, onTap: () => onDigit(d), semantics: d, child: Text(d, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w600)));
    Widget row(List<Widget> keys) => Row(children: [for (final k in keys) Expanded(child: Padding(padding: const EdgeInsets.all(5), child: k))]);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 340),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            row([key('1'), key('2'), key('3')]),
            row([key('4'), key('5'), key('6')]),
            row([key('7'), key('8'), key('9')]),
            row([
              const SizedBox.shrink(),
              key('0'),
              _Key(
                key: const Key('pin-key-del'),
                enabled: enabled,
                plain: true,
                onTap: onDelete,
                semantics: 'Delete',
                child: Icon(AppIcons.arrowLeft, size: 24, color: AppColors.textPrimary),
              ),
            ]),
          ],
        ),
      ),
    );
  }
}

class _Key extends StatelessWidget {
  const _Key({super.key, required this.child, required this.onTap, required this.semantics, this.enabled = true, this.plain = false});
  final Widget child;
  final VoidCallback onTap;
  final String semantics;
  final bool enabled;
  final bool plain;

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: semantics,
        excludeSemantics: true,
        child: Opacity(
          opacity: enabled ? 1 : 0.4,
          child: Material(
            color: plain ? Colors.transparent : AppColors.surfaceGray,
            borderRadius: BorderRadius.circular(AppRadius.lg),
            child: InkWell(
              borderRadius: BorderRadius.circular(AppRadius.lg),
              onTap: enabled ? onTap : null,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 58),
                child: Center(child: Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: child)),
              ),
            ),
          ),
        ),
      );
}
