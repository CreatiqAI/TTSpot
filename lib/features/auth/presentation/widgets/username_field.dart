import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_icons.dart';
import '../../../../core/theme/app_theme.dart';
import '../../application/onboarding_controller.dart';
import '../../application/username_suggestion.dart';
import '../../../safety/application/name_check.dart';

/// Username input that checks availability and the name filter while you
/// type (400 ms after the last keystroke) and shows a tick or a cross.
/// Validates as a form field.
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
  /// Why the name filter refuses it ("That name is reserved."), or null.
  String? _problem;
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
      if (_free != null || _problem != null || _checking) setState(() { _free = null; _problem = null; _checking = false; });
      return;
    }
    setState(() { _checking = true; _free = null; _problem = null; });
    _timer = Timer(const Duration(milliseconds: 400), () async {
      final problem = _nameProblem(v);
      try {
        final ok = await ref.read(usernameAvailabilityProvider)(v);
        final p = await problem;
        if (!mounted || widget.controller.text.trim().toLowerCase() != v) return;
        setState(() { _free = ok; _problem = p; _checking = false; });
      } catch (_) {
        final p = await problem;
        if (mounted && widget.controller.text.trim().toLowerCase() == v) setState(() { _problem = p; _checking = false; });
      }
    });
  }

  /// The name filter's reason, or null (also when the check can't run: the
  /// server still refuses the name on save).
  Future<String?> _nameProblem(String v) async {
    try {
      return await ref.read(nameCheckProvider)(v, NameKind.handle);
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final name = widget.controller.text.trim();
    final bad = _problem != null || _free == false;
    return TextFormField(
      controller: widget.controller,
      textInputAction: widget.textInputAction,
      autocorrect: false,
      maxLength: 20,
      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9_]')), _LowercaseFormatter()],
      decoration: InputDecoration(
        labelText: 'Username',
        prefixText: '@',
        helperText: _problem ??
            (_free == true
                ? '@$name is yours.'
                : _free == false
                    ? 'That username is taken.'
                    : 'Letters, numbers and underscores. 3–20 characters.'),
        helperMaxLines: 2,
        helperStyle: TextStyle(color: bad ? AppColors.danger : _free == true ? AppColors.success : null),
        counterText: '',
        suffixIcon: _checking
            ? const Padding(padding: EdgeInsets.all(14), child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)))
            : bad
                ? const Icon(AppIcons.xCircle, color: AppColors.danger)
                : _free == true
                    ? const Icon(AppIcons.checkCircle, color: AppColors.success)
                    : null,
      ),
      validator: (v) => !usernamePattern.hasMatch(v?.trim().toLowerCase() ?? '')
          ? 'Choose a valid username'
          : _problem ?? (_free == false ? 'That username is taken' : null),
    );
  }
}

class _LowercaseFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) => newValue.copyWith(text: newValue.text.toLowerCase());
}
