import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/friendly_error.dart';
import '../../../core/widgets/primary_button.dart';
import '../application/auth_controller.dart';
import '../data/auth_repository.dart';

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
  bool _acceptedTerms = false;
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
    if (_isSignUp && !_acceptedTerms) {
      _snack('Please agree to the terms to sign up.');
      return;
    }
    final ctrl = ref.read(authControllerProvider.notifier);
    if (_isSignUp) {
      await ctrl.signUp(email: _email.text, password: _password.text);
    } else {
      await ctrl.signIn(email: _email.text, password: _password.text);
    }
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(authControllerProvider, (_, next) {
      if (next.hasError && !next.isLoading) _snack(friendlyError(next.error!));
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
                          Center(child: Image.asset('assets/brand/logo.png', height: 150, filterQuality: FilterQuality.medium)),
                          const SizedBox(height: 10),
                          const Text(
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
                              // Log in accepts a bare username in debug builds (see AuthRepository.normalizeLogin).
                              final resolved = _isSignUp ? s : AuthRepository.normalizeLogin(s);
                              if (!resolved.contains('@') || !resolved.contains('.')) return 'Enter a valid email';
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
                                    padding: const EdgeInsets.only(top: 12),
                                    child: _TermsRow(
                                      value: _acceptedTerms,
                                      onChanged: busy ? null : (v) => setState(() => _acceptedTerms = v),
                                    ),
                                  )
                                : const SizedBox(width: double.infinity),
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
                      style: const TextStyle(fontSize: 14, color: AppColors.textSecondary),
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

class _TermsRow extends StatelessWidget {
  const _TermsRow({required this.value, required this.onChanged});
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onChanged == null ? null : () => onChanged!(!value),
      behavior: HitTestBehavior.opaque,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 22,
            height: 22,
            child: Checkbox(
              value: value,
              onChanged: onChanged == null ? null : (v) => onChanged!(v ?? false),
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: VisualDensity.compact,
            ),
          ),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              'I agree to the Terms of Use and Community Rules. 18+ only, no street racing.',
              style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}

class _OrDivider extends StatelessWidget {
  const _OrDivider();

  @override
  Widget build(BuildContext context) {
    return const Row(children: [
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
