import 'package:flutter/foundation.dart' show TargetPlatform, defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart' show SignInWithAppleButton, SignInWithAppleButtonStyle;
import 'package:supabase_flutter/supabase_flutter.dart' show AuthException;

import '../../../core/router/app_router.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/titi.dart';
import '../../../core/utils/friendly_error.dart';
import '../../../core/widgets/primary_button.dart';
import '../application/auth_controller.dart';
import '../data/auth_repository.dart';

enum _Mode { signIn, signUp }

/// Log in and Sign up: one route (`/sign-in`, and `/sign-in?mode=signup` from
/// the welcome screen's Get started) with two looks. Log in is light and quick:
/// "Welcome back", TiTi waving, two fields. Sign up is a dark "Join the crew"
/// card with TiTi celebrating and what you get, then the form with a
/// password strength hint. Switching cross-fades from one to the other.
///
/// The two fields sit in an [AutofillGroup], so iCloud Keychain (Face ID on
/// iPhone, tied to ttspot.my through the webcredentials associated domain)
/// and Google Password Manager suggest saved logins, and offer to save one
/// after a log in or sign up that worked. A failed attempt is never offered.
class SignInScreen extends ConsumerStatefulWidget {
  const SignInScreen({super.key, this.signUp = false});
  final bool signUp;

  @override
  ConsumerState<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends ConsumerState<SignInScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  late _Mode _mode = widget.signUp ? _Mode.signUp : _Mode.signIn;
  bool _showPassword = false;
  bool _validate = false;

  bool get _isSignUp => _mode == _Mode.signUp;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  void _toggleMode() {
    FocusScope.of(context).unfocus();
    setState(() {
      _mode = _isSignUp ? _Mode.signIn : _Mode.signUp;
      _validate = false;
      _showPassword = false;
    });
  }

  /// Hands what was typed to the platform's password manager, which offers
  /// to save it. Called the moment the server said yes, before the router
  /// leaves this page (the group cancels the context when it goes).
  void _savePassword() => TextInput.finishAutofillContext();

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    setState(() => _validate = true);
    if (!_formKey.currentState!.validate()) return;
    final ctrl = ref.read(authControllerProvider.notifier);
    final email = _email.text.trim().toLowerCase();
    if (_isSignUp) {
      final r = await ctrl.signUp(email: email, password: _password.text);
      if (!r.ok) return;
      _savePassword();
      if (r.needsCode && mounted) context.push(Routes.verify(email));
      return;
    }
    if (await ctrl.signIn(email: email, password: _password.text)) {
      _savePassword();
      return; // the router moves on
    }
    if (!mounted) return;
    final err = ref.read(authControllerProvider).error;
    // Signed up but never typed the code: send a fresh one and go there.
    if (err is AuthException && err.code == 'email_not_confirmed') {
      if (!email.contains('@')) {
        _snack('Confirm your email first: log in with your email address to get a new code.');
        return;
      }
      try {
        await ref.read(authRepositoryProvider).resendSignupCode(email);
      } catch (_) {/* cooldown; the screen offers resend */}
      if (mounted) context.push(Routes.verify(email));
    }
  }

  Future<void> _forgotPassword() async {
    FocusScope.of(context).unfocus();
    final ctrl = TextEditingController(text: _email.text.trim());
    final id = await showModalBottomSheet<String>(
      useRootNavigator: true, // above the shell tab bar
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(24, 0, 24, 24 + MediaQuery.viewInsetsOf(ctx).bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Reset your password', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            Text("We'll email you a link. Open it on this phone and choose a new password.", style: TextStyle(color: AppColors.textSecondary, height: 1.4)),
            const SizedBox(height: 16),
            TextField(
              controller: ctrl,
              autofocus: true,
              keyboardType: TextInputType.emailAddress,
              autocorrect: false,
              textInputAction: TextInputAction.send,
              onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
              decoration: const InputDecoration(hintText: 'Email or username'),
            ),
            const SizedBox(height: 14),
            PrimaryButton(label: 'Send reset link', onPressed: () => Navigator.pop(ctx, ctrl.text.trim())),
          ],
        ),
      ),
    );
    if (id == null || id.isEmpty || !mounted) return;
    await ref.read(authControllerProvider.notifier).requestPasswordReset(id);
    if (!mounted || ref.read(authControllerProvider).hasError) return;
    _snack('If that account exists, a reset link is on its way. Check your inbox (and spam).');
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(authControllerProvider, (_, next) {
      if (next.hasError && !next.isLoading) {
        final e = next.error!;
        if (e is AuthException && e.code == 'email_not_confirmed') return; // handled in _submit
        _snack(friendlyError(e));
      }
    });
    final busy = ref.watch(authControllerProvider).isLoading;
    final signUp = _isSignUp;
    final canPop = context.canPop();

    final emailField = TextFormField(
      controller: _email,
      keyboardType: TextInputType.emailAddress,
      autocorrect: false,
      enableSuggestions: false,
      textInputAction: TextInputAction.next,
      // iOS reads the first hint: username, so Keychain pairs it with the password.
      autofillHints: signUp ? const [AutofillHints.email] : const [AutofillHints.username, AutofillHints.email],
      decoration: InputDecoration(hintText: signUp ? 'Email' : 'Email or username'),
      validator: (v) {
        final s = v?.trim() ?? '';
        if (s.isEmpty) return signUp ? 'Enter your email' : 'Enter your email or username';
        if (signUp && (!s.contains('@') || !s.contains('.'))) return 'Enter a valid email';
        return null;
      },
    );
    final passwordField = TextFormField(
      controller: _password,
      obscureText: !_showPassword,
      autocorrect: false,
      enableSuggestions: false,
      textInputAction: TextInputAction.done,
      autofillHints: [signUp ? AutofillHints.newPassword : AutofillHints.password],
      onFieldSubmitted: (_) => busy ? null : _submit(),
      decoration: InputDecoration(
        hintText: signUp ? 'Create a password' : 'Password',
        suffixIcon: IconButton(
          tooltip: _showPassword ? 'Hide password' : 'Show password',
          icon: Icon(_showPassword ? AppIcons.eyeSlash : AppIcons.eye, size: 22),
          onPressed: () => setState(() => _showPassword = !_showPassword),
        ),
      ),
      validator: (v) {
        if ((v ?? '').isEmpty) return signUp ? 'Create a password' : 'Enter your password';
        if (signUp && v!.length < 6) return 'Use at least 6 characters';
        return null;
      },
    );

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // Back to the welcome screen.
            if (canPop)
              Align(
                alignment: Alignment.centerLeft,
                child: IconButton(
                  tooltip: 'Back',
                  icon: const Icon(AppIcons.arrowLeft),
                  onPressed: busy ? null : () => context.pop(),
                ),
              ),
            Expanded(
              child: Center(
                child: SingleChildScrollView(
                  padding: EdgeInsets.fromLTRB(24, canPop ? 4 : 24, 24, 24),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 420),
                    child: Form(
                      key: _formKey,
                      autovalidateMode: _validate ? AutovalidateMode.always : AutovalidateMode.disabled,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _ModeSwitch(
                            signUp: signUp,
                            child: signUp ? _JoinHeader() : _WelcomeBackHeader(),
                          ),
                          SizedBox(height: signUp ? 20 : 24),

                          // A fresh group per mode: switching drops a half-typed
                          // context instead of carrying it into the other form.
                          AutofillGroup(
                            key: ValueKey(_mode),
                            onDisposeAction: AutofillContextAction.cancel,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [emailField, const SizedBox(height: 12), passwordField],
                            ),
                          ),

                          _ModeSwitch(
                            signUp: signUp,
                            child: signUp
                                ? Padding(
                                    padding: const EdgeInsets.only(top: 10),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.stretch,
                                      children: [
                                        _StrengthHint(_password),
                                        const SizedBox(height: 10),
                                        Text(
                                          'We email you a 6-digit code to confirm. Next: your name, phone number and the Terms.',
                                          style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary, height: 1.4),
                                        ),
                                      ],
                                    ),
                                  )
                                : Align(
                                    alignment: Alignment.centerRight,
                                    child: TextButton(
                                      onPressed: busy ? null : _forgotPassword,
                                      style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 4), visualDensity: VisualDensity.compact),
                                      child: const Text('Forgot password?', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                                    ),
                                  ),
                          ),
                          SizedBox(height: signUp ? 20 : 12),

                          PrimaryButton(
                            label: signUp ? 'Sign up' : 'Log in',
                            loading: busy,
                            onPressed: _submit,
                          ),

                          // Sign in with Apple, iPhone only.
                          if (defaultTargetPlatform == TargetPlatform.iOS) ...[
                            const SizedBox(height: 24),
                            _OrDivider(),
                            const SizedBox(height: 18),
                            SignInWithAppleButton(
                              height: 48,
                              text: signUp ? 'Sign up with Apple' : 'Sign in with Apple',
                              style: Theme.of(context).brightness == Brightness.dark ? SignInWithAppleButtonStyle.white : SignInWithAppleButtonStyle.black,
                              borderRadius: const BorderRadius.all(Radius.circular(12)),
                              onPressed: busy ? () {} : () => ref.read(authControllerProvider.notifier).signInWithApple(),
                            ),
                            const SizedBox(height: 8),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),

            // Pinned switch row
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: TextButton(
                onPressed: busy ? null : _toggleMode,
                // One fades out, then the other in: overlapping lines read as a jumble.
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 260),
                  switchInCurve: const Interval(0.5, 1, curve: Curves.easeOut),
                  switchOutCurve: const Interval(0.5, 1, curve: Curves.easeIn),
                  child: Text.rich(
                    key: ValueKey(signUp),
                    textAlign: TextAlign.center,
                    TextSpan(
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w400, color: AppColors.textSecondary),
                      children: [
                        TextSpan(text: signUp ? 'Have an account? ' : 'New to TT Spot? '),
                        TextSpan(
                          text: signUp ? 'Log in.' : 'Create an account',
                          style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w700),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Cross-fades a block between its Log in and Sign up versions, with a small
/// rise, and eases the height change so the page below glides.
class _ModeSwitch extends StatelessWidget {
  const _ModeSwitch({required this.signUp, required this.child});
  final bool signUp;
  final Widget child;

  static const _duration = Duration(milliseconds: 300);

  @override
  Widget build(BuildContext context) => AnimatedSize(
        duration: _duration,
        curve: Curves.easeOutCubic,
        alignment: Alignment.topCenter,
        child: AnimatedSwitcher(
          duration: _duration,
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          transitionBuilder: (child, anim) => FadeTransition(
            opacity: anim,
            child: SlideTransition(
              position: Tween(begin: const Offset(0, 0.04), end: Offset.zero).animate(anim),
              child: child,
            ),
          ),
          layoutBuilder: (current, previous) => Stack(
            fit: StackFit.passthrough,
            alignment: Alignment.topCenter,
            children: [...previous, ?current],
          ),
          child: KeyedSubtree(key: ValueKey(signUp), child: child),
        ),
      );
}

TextStyle _display(double size, Color color) =>
    TextStyle(fontFamily: AppFonts.display, fontSize: size, height: 0.95, fontWeight: FontWeight.w800, letterSpacing: -0.5, color: color);

/// TiTi's size for a header: a third of the row, within bounds, so the
/// headline keeps room on a small phone. Square, so nothing moves when the
/// art finishes loading.
double _titiSize(double width, double max) => (width * 0.36).clamp(88.0, max);

/// Log in: light and quick. TiTi waves you back in.
class _WelcomeBackHeader extends StatelessWidget {
  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, c) {
          final titi = _titiSize(c.maxWidth, 136);
          return Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text.rich(
                          TextSpan(
                            style: _display(54, AppColors.textPrimary),
                            children: const [
                              TextSpan(text: 'WELCOME\n'),
                              TextSpan(text: 'BACK.', style: TextStyle(color: AppColors.brand)),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text('Good to see you again.', style: TextStyle(fontSize: 15, color: AppColors.textSecondary, height: 1.35)),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox.square(dimension: titi, child: Titi(TitiPose.wave, height: titi)),
            ],
          );
        },
      );
}

/// Sign up: a dark card, TiTi celebrating, and what joining gets you.
class _JoinHeader extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    // Ink on the white page; on the dark page ink would vanish, so raised grey.
    final card = AppColors.dark ? AppColors.surfaceGray : AppColors.ink;
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 14, 10, 18),
      decoration: BoxDecoration(color: card, borderRadius: BorderRadius.circular(24)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LayoutBuilder(
            builder: (context, c) {
              final titi = _titiSize(c.maxWidth, 124);
              return Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text.rich(
                            TextSpan(
                              style: _display(48, Colors.white),
                              children: const [
                                TextSpan(text: 'JOIN THE\n'),
                                TextSpan(text: 'CREW.', style: TextStyle(color: AppColors.brand)),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Free. Two minutes to join.',
                          style: TextStyle(fontSize: 14, color: Colors.white.withValues(alpha: 0.72), height: 1.35),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 4),
                  SizedBox.square(dimension: titi, child: Titi(TitiPose.celebrate, height: titi)),
                ],
              );
            },
          ),
          const SizedBox(height: 14),
          Divider(height: 1, thickness: 1, color: Colors.white.withValues(alpha: 0.12)),
          const SizedBox(height: 14),
          const _Perk(AppIcons.usersThree, 'See your friends on the map'),
          const SizedBox(height: 10),
          const _Perk(AppIcons.coffee, 'Find meets and car cafés'),
          const SizedBox(height: 10),
          const _Perk(AppIcons.trafficCone, 'Collect TiTi cards'),
        ],
      ),
    );
  }
}

/// One line of what you get: a red dot with an icon, then the words.
class _Perk extends StatelessWidget {
  const _Perk(this.icon, this.text);
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Container(
            width: 30,
            height: 30,
            alignment: Alignment.center,
            decoration: const BoxDecoration(color: AppColors.brand, shape: BoxShape.circle),
            child: Icon(icon, size: 17, color: Colors.white),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(text, style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600, color: Colors.white, height: 1.3)),
          ),
        ],
      );
}

enum _Strength { empty, tooShort, weak, okay, strong }

/// Rough strength: length first, then how many kinds of character (lower,
/// upper, digit, symbol) it mixes. Only a nudge; the server's rule is 6+.
_Strength _strengthOf(String p) {
  if (p.isEmpty) return _Strength.empty;
  if (p.length < 6) return _Strength.tooShort;
  final kinds = [RegExp('[a-z]'), RegExp('[A-Z]'), RegExp('[0-9]'), RegExp(r'[^A-Za-z0-9]')].where((r) => r.hasMatch(p)).length;
  if (p.length >= 16 || (p.length >= 12 && kinds >= 3)) return _Strength.strong;
  if (p.length >= 8 && kinds >= 2) return _Strength.okay;
  return _Strength.weak;
}

/// Three bars and a word under the sign-up password, live as you type.
class _StrengthHint extends StatelessWidget {
  const _StrengthHint(this.password);
  final TextEditingController password;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<TextEditingValue>(
        valueListenable: password,
        builder: (context, value, _) {
          final s = _strengthOf(value.text);
          final (bars, color, label) = switch (s) {
            _Strength.empty => (0, AppColors.textMuted, 'At least 6 characters. Longer is stronger.'),
            _Strength.tooShort => (1, AppColors.danger, 'Too short. Use at least 6 characters.'),
            _Strength.weak => (1, AppColors.danger, 'Weak. Make it longer, or mix in numbers and symbols.'),
            _Strength.okay => (2, AppColors.textPrimary, 'Okay. A few more characters make it strong.'),
            _Strength.strong => (3, AppColors.success, 'Strong password.'),
          };
          final textColor = s == _Strength.empty || s == _Strength.okay ? AppColors.textSecondary : color;
          return Row(
            children: [
              for (var i = 0; i < 3; i++) ...[
                AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  width: 22,
                  height: 4,
                  decoration: BoxDecoration(color: i < bars ? color : AppColors.border, borderRadius: BorderRadius.circular(2)),
                ),
                const SizedBox(width: 4),
              ],
              const SizedBox(width: 6),
              Expanded(
                child: Text(label, style: TextStyle(fontSize: 12.5, fontWeight: s == _Strength.empty ? FontWeight.w400 : FontWeight.w600, color: textColor, height: 1.3)),
              ),
            ],
          );
        },
      );
}

class _OrDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Row(children: [
      const Expanded(child: Divider()),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Text('OR', style: TextStyle(color: AppColors.textSecondary, fontSize: 13, fontWeight: FontWeight.w600)),
      ),
      const Expanded(child: Divider()),
    ]);
  }
}
