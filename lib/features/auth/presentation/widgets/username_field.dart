import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/supabase/supabase_client.dart';
import '../../../../core/theme/app_icons.dart';
import '../../../../core/theme/app_theme.dart';
import '../../application/onboarding_controller.dart';

/// Username input that checks availability while you type (400 ms after the
/// last keystroke) and shows a tick or a cross. Validates as a form field.
class UsernameField extends ConsumerStatefulWidget {
  const UsernameField({super.key, required this.controller, this.textInputAction, this.current});
  final TextEditingController controller;
  final TextInputAction? textInputAction;
  /// The name already saved for this person; typing it back is always fine.
  final String? current;

  @override
  ConsumerState<UsernameField> createState() => _UsernameFieldState();
}

class _UsernameFieldState extends ConsumerState<UsernameField> {
  Timer? _timer;
  bool? _free; // null = not checked / invalid
  bool _checking = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onChanged);
  }

  @override
  void dispose() {
    _timer?.cancel();
    widget.controller.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    final v = widget.controller.text.trim().toLowerCase();
    _timer?.cancel();
    if (!usernamePattern.hasMatch(v) || v == widget.current?.toLowerCase()) {
      if (_free != null || _checking) setState(() { _free = null; _checking = false; });
      return;
    }
    setState(() { _checking = true; _free = null; });
    _timer = Timer(const Duration(milliseconds: 400), () async {
      try {
        final ok = await ref.read(supabaseProvider).rpc('username_available', params: {'p_username': v}) as bool;
        if (!mounted || widget.controller.text.trim().toLowerCase() != v) return;
        setState(() { _free = ok; _checking = false; });
      } catch (_) {
        if (mounted) setState(() => _checking = false);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final name = widget.controller.text.trim();
    return TextFormField(
      controller: widget.controller,
      textInputAction: widget.textInputAction,
      autocorrect: false,
      maxLength: 20,
      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9_]')), _LowercaseFormatter()],
      decoration: InputDecoration(
        labelText: 'Username',
        prefixText: '@',
        helperText: _free == true
            ? '@$name is yours.'
            : _free == false
                ? 'That username is taken.'
                : 'Letters, numbers and underscores. 3–20 characters.',
        helperStyle: TextStyle(color: _free == true ? AppColors.success : _free == false ? AppColors.danger : null),
        counterText: '',
        suffixIcon: _checking
            ? const Padding(padding: EdgeInsets.all(14), child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)))
            : _free == true
                ? const Icon(AppIcons.checkCircle, color: AppColors.success)
                : _free == false
                    ? const Icon(AppIcons.xCircle, color: AppColors.danger)
                    : null,
      ),
      validator: (v) => !usernamePattern.hasMatch(v?.trim().toLowerCase() ?? '')
          ? 'Choose a valid username'
          : _free == false
              ? 'That username is taken'
              : null,
    );
  }
}

class _LowercaseFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) => newValue.copyWith(text: newValue.text.toLowerCase());
}
