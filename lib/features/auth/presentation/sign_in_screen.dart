import 'package:flutter/foundation.dart' show TargetPlatform, defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/friendly_error.dart';
import '../../../core/widgets/primary_button.dart';
import 'package:go_router/go_router.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart' show SignInWithAppleButton, SignInWithAppleButtonStyle;
import 'package:supabase_flutter/supabase_flutter.dart' show AuthException;

import '../../../core/router/app_router.dart';
import '../application/auth_controller.dart';
import '../data/auth_repository.dart';
import '../../../core/widgets/brand_logo.dart';

enum _Mode { signIn, signUp }

/// Instagram-style login: centered wordmark, two fields, blue button,
/// "OR" divider, Google link, and a pinned switch row at the bottom.
class SignInScreen extends ConsumerStatefulWidget {
  const SignInScreen({super.key});

  @override
  ConsumerState<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends ConsumerState<SignInScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  _Mode _mode = _Mode.signIn;
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
    setState(() => _mode = _isSignUp ? _Mode.signIn : _Mode.signUp);
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    setState(() => _validate = true);
    if (!_formKey.currentState!.validate()) return;
    final ctrl = ref.read(authControllerProvider.notifier);
    final email = _email.text.trim().toLowerCase();
    if (_isSignUp) {
      final needsCode = await ctrl.signUp(email: email, password: _password.text);
      if (needsCode && mounted) context.push(Routes.verify(email));
    } else {
      await ctrl.signIn(email: email, password: _password.text);
      final err = ref.read(authControllerProvider).error;
      // Signed up but never typed the code: send a fresh one and go there.
      if (err is AuthException && err.code == 'email_not_confirmed' && mounted) {
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

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 400),
                    child: Form(
                      key: _formKey,
                      autovalidateMode: _validate ? AutovalidateMode.always : AutovalidateMode.disabled,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const SizedBox(height: 8),
                          Center(child: const BrandLogo(height: 150)),
                          const SizedBox(height: 10),
                          Text(
                            "Malaysia's car meet spot",
                            textAlign: TextAlign.center,
                            style: TextStyle(color: AppColors.textSecondary, fontSize: 14),
                          ),
                          const SizedBox(height: 40),

                          TextFormField(
                            controller: _email,
                            keyboardType: TextInputType.emailAddress,
                            autocorrect: false,
                            textInputAction: TextInputAction.next,
                            autofillHints: const [AutofillHints.email],
                            decoration: InputDecoration(hintText: _isSignUp ? 'Email' : 'Email or username'),
                            validator: (v) {
                              final s = v?.trim() ?? '';
                              if (s.isEmpty) return _isSignUp ? 'Enter your email' : 'Enter your email or username';
                              if (_isSignUp && (!s.contains('@') || !s.contains('.'))) return 'Enter a valid email';
                              return null;
                            },
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _password,
                            obscureText: !_showPassword,
                            textInputAction: TextInputAction.done,
                            autofillHints: [_isSignUp ? AutofillHints.newPassword : AutofillHints.password],
                            onFieldSubmitted: (_) => busy ? null : _submit(),
                            decoration: InputDecoration(
                              hintText: 'Password',
                              suffixIcon: IconButton(
                                icon: Icon(
                                  _showPassword ? AppIcons.eyeSlash : AppIcons.eye,
                                  size: 22,
                                ),
                                onPressed: () => setState(() => _showPassword = !_showPassword),
                              ),
                            ),
                            validator: (v) {
                              if ((v ?? '').isEmpty) return 'Enter your password';
                              if (_isSignUp && v!.length < 6) return 'Use at least 6 characters';
                              return null;
                            },
                          ),

                          AnimatedSize(
                            duration: const Duration(milliseconds: 200),
                            curve: Curves.easeOut,
                            alignment: Alignment.topCenter,
                            child: _isSignUp
                                ? Padding(
                                    padding: EdgeInsets.only(top: 12),
                                    child: Text(
                                      'We email you a 6-digit code to confirm. Next: your name, phone number and the Terms.',
                                      style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary, height: 1.4),
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
                          const SizedBox(height: 20),

                          PrimaryButton(
                            label: _isSignUp ? 'Sign up' : 'Log in',
                            loading: busy,
                            onPressed: _submit,
                          ),

                          const SizedBox(height: 28),
                          const _OrDivider(),
                          const SizedBox(height: 20),

                          // Apple asks for this whenever another social login is offered (iPhone only).
                          if (defaultTargetPlatform == TargetPlatform.iOS) ...[
                            SizedBox(
                              height: 48,
                              child: SignInWithAppleButton(
                                text: _isSignUp ? 'Sign up with Apple' : 'Sign in with Apple',
                                style: Theme.of(context).brightness == Brightness.dark ? SignInWithAppleButtonStyle.white : SignInWithAppleButtonStyle.black,
                                borderRadius: const BorderRadius.all(Radius.circular(12)),
                                onPressed: busy ? () {} : () => ref.read(authControllerProvider.notifier).signInWithApple(),
                              ),
                            ),
                            const SizedBox(height: 8),
                          ],

                          TextButton.icon(
                            onPressed: busy
                                ? null
                                : () => ref.read(authControllerProvider.notifier).signInWithGoogle(),
                            icon: const _GoogleG(),
                            label: Text(_isSignUp ? 'Sign up with Google' : 'Log in with Google'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),

            // Pinned bottom row, like Instagram
            const Divider(),
            SizedBox(
              height: 56,
              child: Center(
                child: GestureDetector(
                  onTap: busy ? null : _toggleMode,
                  behavior: HitTestBehavior.opaque,
                  child: RichText(
                    text: TextSpan(
                      style: TextStyle(fontSize: 14, color: AppColors.textSecondary),
                      children: [
                        TextSpan(text: _isSignUp ? 'Have an account? ' : "Don't have an account? "),
                        TextSpan(
                          text: _isSignUp ? 'Log in.' : 'Sign up.',
                          style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w600),
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

class _OrDivider extends StatelessWidget {
  const _OrDivider();

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Expanded(child: Divider()),
      Padding(
        padding: EdgeInsets.symmetric(horizontal: 16),
        child: Text('OR', style: TextStyle(color: AppColors.textSecondary, fontSize: 13, fontWeight: FontWeight.w600)),
      ),
      Expanded(child: Divider()),
    ]);
  }
}

/// Google "G" mark drawn with text so we don't need an image asset.
class _GoogleG extends StatelessWidget {
  const _GoogleG();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 20,
      height: 20,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: AppColors.border, width: 1.5),
      ),
      child: const Text(
        'G',
        style: TextStyle(color: Color(0xFF4285F4), fontWeight: FontWeight.w800, fontSize: 12, height: 1),
      ),
    );
  }
}
