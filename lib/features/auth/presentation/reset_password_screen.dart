import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/utils/friendly_error.dart';
import '../data/auth_repository.dart';
import 'widgets/dark_auth.dart';

/// Opened by the link in the "reset your password" email (ttspot://reset-password).
/// The link already signed the member in, so all that's left is a new password.
/// Same dark panel as sign-in.
class ResetPasswordScreen extends ConsumerStatefulWidget {
  const ResetPasswordScreen({super.key});

  @override
  ConsumerState<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends ConsumerState<ResetPasswordScreen> {
  final _form = GlobalKey<FormState>();
  final _p1 = TextEditingController();
  final _p2 = TextEditingController();
  bool _show = false;
  bool _busy = false;

  @override
  void dispose() {
    _p1.dispose();
    _p2.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      await ref.read(authRepositoryProvider).updatePassword(_p1.text);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Password updated. You\'re signed in.')));
      context.go(Routes.map);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomPad = MediaQuery.paddingOf(context).bottom;
    return AuthPage(
      child: SafeArea(
        bottom: false,
        child: Column(
          children: [
            SizedBox(
              height: 112,
              child: Stack(
                children: [
                  Positioned(left: 4, top: 0, child: AuthIconButton(icon: AppIcons.x, tooltip: 'Close', onPressed: () => context.go(Routes.map))),
                  Positioned(left: 24, top: 44, child: Image.asset('assets/brand/logo_dark.png', height: 56, filterQuality: FilterQuality.medium)),
                ],
              ),
            ),
            Expanded(
              child: AuthPanel(
                padding: EdgeInsets.zero,
                child: SingleChildScrollView(
                  padding: EdgeInsets.fromLTRB(24, 26, 24, 24 + bottomPad),
                  child: Form(
                    key: _form,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text('NEW PASSWORD', style: AuthDark.display(38)),
                        const SizedBox(height: 10),
                        Text('At least 6 characters. You\'ll stay signed in on this phone.', style: TextStyle(fontSize: 15, color: AuthDark.text, height: 1.35)),
                        const SizedBox(height: 18),
                        TextFormField(
                          controller: _p1,
                          style: const TextStyle(fontSize: 16, color: Colors.white),
                          obscureText: !_show,
                          autofocus: true,
                          autofillHints: const [AutofillHints.newPassword],
                          decoration: InputDecoration(
                            hintText: 'New password',
                            suffixIcon: IconButton(
                              tooltip: _show ? 'Hide password' : 'Show password',
                              icon: Icon(_show ? AppIcons.eyeSlash : AppIcons.eye, size: 22),
                              onPressed: () => setState(() => _show = !_show),
                            ),
                          ),
                          validator: (v) => (v ?? '').length < 6 ? 'Use at least 6 characters' : null,
                        ),
                        const SizedBox(height: 10),
                        TextFormField(
                          controller: _p2,
                          style: const TextStyle(fontSize: 16, color: Colors.white),
                          obscureText: !_show,
                          decoration: const InputDecoration(hintText: 'Repeat new password'),
                          validator: (v) => v != _p1.text ? 'Passwords don\'t match' : null,
                          onFieldSubmitted: (_) => _busy ? null : _save(),
                        ),
                        const SizedBox(height: 18),
                        AuthPill(label: 'Save password', loading: _busy, onPressed: _save),
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
