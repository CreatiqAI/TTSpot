import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/supabase/supabase_client.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/friendly_error.dart';
import '../data/safety_repository.dart';

const _reasons = [
  'Spam or scam',
  'Harassment or hate',
  'Illegal racing or dangerous driving',
  'Fake or misleading',
  'Inappropriate content',
  'Something else',
];

/// Instagram-style report sheet: pick a reason, optional note, submit.
Future<void> showReportSheet(
  BuildContext context, {
  required ReportTarget target,
  required String targetId,
}) {
  return showModalBottomSheet<void>(
    useRootNavigator: true, // above the shell tab bar
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _ReportSheet(target: target, targetId: targetId),
  );
}

class _ReportSheet extends ConsumerStatefulWidget {
  const _ReportSheet({required this.target, required this.targetId});
  final ReportTarget target;
  final String targetId;

  @override
  ConsumerState<_ReportSheet> createState() => _ReportSheetState();
}

class _ReportSheetState extends ConsumerState<_ReportSheet> {
  String? _reason;
  final _note = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final me = ref.read(currentUserIdProvider);
    if (_reason == null || me == null) return;
    setState(() => _busy = true);
    try {
      final reason = _note.text.trim().isEmpty ? _reason! : '${_reason!}: ${_note.text.trim()}';
      await ref.read(safetyRepositoryProvider).report(
            reporterId: me,
            target: widget.target,
            targetId: widget.targetId,
            reason: reason,
          );
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Thanks. We\'ll take a look.')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final what = switch (widget.target) {
      ReportTarget.event => 'meet',
      ReportTarget.comment => 'comment',
      ReportTarget.profile => 'profile',
    };
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text('Why are you reporting this $what?', style: AppText.sectionTitle.copyWith(fontSize: 18)),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(
                'Your report is anonymous. If someone is in immediate danger, call 999.',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
              ),
            ),
            RadioGroup<String>(
              groupValue: _reason,
              onChanged: _busy ? (_) {} : (v) => setState(() => _reason = v),
              child: Column(
                children: [
                  for (final r in _reasons)
                    RadioListTile<String>(
                      value: r,
                      title: Text(r, style: const TextStyle(fontSize: 15)),
                      dense: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                      activeColor: AppColors.primary,
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
              child: TextField(
                controller: _note,
                maxLength: 300,
                maxLines: 2,
                decoration: const InputDecoration(hintText: 'Anything else? (optional)', counterText: ''),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: FilledButton(
                onPressed: _reason == null || _busy ? null : _submit,
                child: _busy
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('Submit report'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Confirm + block. Returns true when the block was written.
Future<bool> confirmBlockUser(
  BuildContext context,
  WidgetRef ref, {
  required String userId,
  required String displayName,
}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('Block $displayName?'),
      content: const Text(
        'They won\'t be able to see your meets or comments, and you won\'t see theirs. They won\'t be notified.',
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Block', style: TextStyle(color: AppColors.danger)),
        ),
      ],
    ),
  );
  if (ok != true) return false;
  final me = ref.read(currentUserIdProvider);
  if (me == null) return false;
  try {
    await ref.read(safetyRepositoryProvider).block(blockerId: me, blockedId: userId);
    ref.invalidate(blockedUserIdsProvider);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$displayName blocked.')));
    }
    return true;
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e))));
    }
    return false;
  }
}
