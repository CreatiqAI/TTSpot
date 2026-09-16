import 'package:flutter/material.dart';

import '../theme/app_icons.dart';
import '../theme/app_theme.dart';

/// A form field that opens a bottom-sheet list instead of a Material dropdown.
/// Looks like our other inputs, scrolls properly for long lists (states), and
/// feels native on iPhone. Use `options` as (value, label) pairs.
class PickerField<T> extends FormField<T> {
  PickerField({
    super.key,
    required String label,
    required List<(T, String)> options,
    T? value,
    ValueChanged<T?>? onChanged,
    String? hint,
    IconData? icon,
    bool enabled = true,
    super.validator,
  }) : super(
          initialValue: value,
          builder: (state) {
            final selected = options.where((o) => o.$1 == state.value).firstOrNull;
            Future<void> open() async {
              FocusScope.of(state.context).unfocus();
              final picked = await showModalBottomSheet<T>(
                context: state.context,
                showDragHandle: true,
                isScrollControlled: true,
                builder: (ctx) => _PickerSheet<T>(title: label, options: options, selected: state.value),
              );
              if (picked == null) return;
              state.didChange(picked);
              onChanged?.call(picked);
            }

            // The whole box (icon, text and arrow) is one tap target.
            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: enabled ? open : null,
              child: InputDecorator(
                decoration: InputDecoration(
                  labelText: label,
                  // With a hint the label must float, or the two overlap in the empty box.
                  floatingLabelBehavior: hint == null ? null : FloatingLabelBehavior.always,
                  errorText: state.errorText,
                  prefixIcon: icon == null ? null : Icon(icon),
                  suffixIcon: Icon(AppIcons.caretDown, color: AppColors.textSecondary, size: 18),
                  enabled: enabled,
                ),
                isEmpty: selected == null,
                child: Text(
                  selected?.$2 ?? hint ?? '',
                  style: TextStyle(fontSize: 15, color: selected == null ? AppColors.textSecondary : AppColors.textPrimary),
                ),
              ),
            );
          },
        );
}

class _PickerSheet<T> extends StatelessWidget {
  const _PickerSheet({required this.title, required this.options, this.selected});
  final String title;
  final List<(T, String)> options;
  final T? selected;

  @override
  Widget build(BuildContext context) {
    final maxH = MediaQuery.sizeOf(context).height * 0.7;
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxH),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
            ),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: options.length,
                itemBuilder: (_, i) {
                  final o = options[i];
                  final on = o.$1 == selected;
                  return ListTile(
                    title: Text(o.$2, style: TextStyle(fontWeight: on ? FontWeight.w700 : FontWeight.w500)),
                    trailing: on ? const Icon(AppIcons.checkCircleFill, color: AppColors.primary) : null,
                    onTap: () => Navigator.pop(context, o.$1),
                  );
                },
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
