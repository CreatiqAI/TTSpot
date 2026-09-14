import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/app_art.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/friendly_error.dart';
import '../../../core/widgets/primary_button.dart';
import '../data/auth_repository.dart';

/// Opened by the link in the "reset your password" email (ttspot://reset-password).
/// The link already signed the member in, so all that's left is a new password.
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
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(AppIcons.x), onPressed: () => context.go(Routes.map)),
        title: const Text('New password'),
      ),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
          children: [
            const Center(child: ArtIcon(AppArt.locked, size: 72)),
            const SizedBox(height: 16),
            const Text('Choose a new password', textAlign: TextAlign.center, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            const Text('At least 6 characters. You\'ll stay signed in on this phone.', textAlign: TextAlign.center, style: TextStyle(color: AppColors.textSecondary)),
            const SizedBox(height: 24),
            TextFormField(
              controller: _p1,
              obscureText: !_show,
              autofocus: true,
              autofillHints: const [AutofillHints.newPassword],
              decoration: InputDecoration(
                hintText: 'New password',
                suffixIcon: IconButton(icon: Icon(_show ? AppIcons.eyeSlash : AppIcons.eye, size: 22), onPressed: () => setState(() => _show = !_show)),
              ),
              validator: (v) => (v ?? '').length < 6 ? 'Use at least 6 characters' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _p2,
              obscureText: !_show,
              decoration: const InputDecoration(hintText: 'Repeat new password'),
              validator: (v) => v != _p1.text ? 'Passwords don\'t match' : null,
              onFieldSubmitted: (_) => _busy ? null : _save(),
            ),
            const SizedBox(height: 20),
            PrimaryButton(label: 'Save password', loading: _busy, onPressed: _save),
          ],
        ),
      ),
    );
  }
}
