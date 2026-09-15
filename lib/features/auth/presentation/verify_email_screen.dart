import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/friendly_error.dart';
import '../../../core/widgets/primary_button.dart';
import '../data/auth_repository.dart';

/// "We emailed you a code": six boxes, auto-submit on the sixth digit,
/// resend with a 60 s cooldown. On success Supabase signs the member in and
/// the router moves on to onboarding.
class VerifyEmailScreen extends ConsumerStatefulWidget {
  const VerifyEmailScreen({super.key, required this.email});
  final String email;

  @override
  ConsumerState<VerifyEmailScreen> createState() => _VerifyEmailScreenState();
}

class _VerifyEmailScreenState extends ConsumerState<VerifyEmailScreen> {
  final _code = TextEditingController();
  final _focus = FocusNode();
  bool _busy = false;
  int _cooldown = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _code.addListener(() {
      setState(() {});
      if (_code.text.length == 6 && !_busy) _verify();
    });
    _startCooldown();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _code.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _startCooldown() {
    _timer?.cancel();
    setState(() => _cooldown = 60);
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return t.cancel();
      setState(() => _cooldown--);
      if (_cooldown <= 0) t.cancel();
    });
  }

  Future<void> _verify() async {
    FocusScope.of(context).unfocus();
    setState(() => _busy = true);
    try {
      await ref.read(authRepositoryProvider).verifySignupCode(email: widget.email, code: _code.text.trim());
      // Signed in now; the router redirects to onboarding.
    } catch (e) {
      if (mounted) {
        _snack(friendlyError(e));
        _code.clear();
        _focus.requestFocus();
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resend() async {
    try {
      await ref.read(authRepositoryProvider).resendSignupCode(widget.email);
      _startCooldown();
      _snack('New code sent to ${widget.email}.');
    } catch (e) {
      _snack(friendlyError(e));
    }
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final digits = _code.text.padRight(6).characters.toList();
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(AppIcons.arrowLeft), onPressed: () => context.canPop() ? context.pop() : context.go('/sign-in')),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(28, 8, 28, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(AppIcons.envelope, size: 44, color: AppColors.brand),
              const SizedBox(height: 16),
              const Text('Check your email', style: TextStyle(fontFamily: AppFonts.display, fontSize: 34, fontWeight: FontWeight.w700, height: 1)),
              const SizedBox(height: 8),
              Text.rich(
                TextSpan(
                  style: const TextStyle(fontSize: 14.5, color: AppColors.textSecondary, height: 1.45),
                  children: [
                    const TextSpan(text: 'We sent a 6-digit code to '),
                    TextSpan(text: widget.email, style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                    const TextSpan(text: '. Type it here. It expires in 15 minutes.'),
                  ],
                ),
              ),
              const SizedBox(height: 28),

              // Six boxes over one invisible text field.
              GestureDetector(
                onTap: () => _focus.requestFocus(),
                child: Stack(
                  children: [
                    Row(
                      children: [
                        for (var i = 0; i < 6; i++) ...[
                          Expanded(
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 120),
                              height: 60,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: AppColors.surfaceGray,
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: _code.text.length == i && _focus.hasFocus ? AppColors.ink : Colors.transparent,
                                  width: 2,
                                ),
                              ),
                              child: Text(
                                digits[i].trim(),
                                style: const TextStyle(fontFamily: AppFonts.display, fontSize: 30, fontWeight: FontWeight.w700),
                              ),
                            ),
                          ),
                          if (i < 5) const SizedBox(width: 8),
                        ],
                      ],
                    ),
                    Positioned.fill(
                      child: Opacity(
                        opacity: 0,
                        child: TextField(
                          controller: _code,
                          focusNode: _focus,
                          autofocus: true,
                          keyboardType: TextInputType.number,
                          maxLength: 6,
                          enableSuggestions: false,
                          autocorrect: false,
                          autofillHints: const [AutofillHints.oneTimeCode],
                          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                          decoration: const InputDecoration(counterText: '', border: InputBorder.none),
                          showCursor: false,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              PrimaryButton(label: 'Verify', loading: _busy, onPressed: _code.text.length == 6 && !_busy ? _verify : null),
              const SizedBox(height: 16),
              Center(
                child: _cooldown > 0
                    ? Text('Resend code in ${_cooldown}s', style: const TextStyle(fontSize: 13, color: AppColors.textMuted, fontWeight: FontWeight.w600))
                    : TextButton(onPressed: _resend, child: const Text('Resend code')),
              ),
              const SizedBox(height: 8),
              const Text(
                'No email? Check spam, or make sure the address is spelt right. Wrong address: go back and sign up again.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary, height: 1.4),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
