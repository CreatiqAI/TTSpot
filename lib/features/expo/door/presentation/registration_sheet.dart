import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/friendly_error.dart';
import '../../../../core/widgets/primary_button.dart';
import '../../../../core/widgets/sheet_header.dart';
import '../application/door_providers.dart';
import '../domain/door_models.dart';

/// The member's registration form for an event. True when saved.
Future<bool> showRegistrationSheet(BuildContext context, String eventId) async {
  final saved = await showModalBottomSheet<bool>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _RegistrationSheet(eventId: eventId),
  );
  return saved ?? false;
}

class _RegistrationSheet extends ConsumerWidget {
  const _RegistrationSheet({required this.eventId});
  final String eventId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final form = ref.watch(registrationFormProvider(eventId));
    final mine = ref.watch(myRegistrationProvider(eventId));
    final maxH = MediaQuery.sizeOf(context).height * 0.88;
    Widget body;
    if (form.isLoading || mine.isLoading) {
      body = const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator(strokeWidth: 2)));
    } else if (form.hasError) {
      body = Padding(padding: const EdgeInsets.all(20), child: Text(friendlyError(form.error!)));
    } else if (form.value == null || form.value!.isEmpty) {
      body = Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Text('No questions for this event.', style: TextStyle(color: AppColors.textSecondary)),
      );
    } else {
      body = _FormBody(eventId: eventId, form: form.value!, mine: mine.value);
    }
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxH),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Padding(padding: EdgeInsets.fromLTRB(20, 0, 12, 8), child: SheetHeader(title: 'Register')),
              Flexible(child: body),
            ],
          ),
        ),
      ),
    );
  }
}

class _FormBody extends ConsumerStatefulWidget {
  const _FormBody({required this.eventId, required this.form, this.mine});
  final String eventId;
  final RegistrationForm form;
  final MyRegistration? mine;

  @override
  ConsumerState<_FormBody> createState() => _FormBodyState();
}

class _FormBodyState extends ConsumerState<_FormBody> {
  final _text = <String, TextEditingController>{};
  final _one = <String, String?>{};
  final _many = <String, Set<String>>{};
  late bool _consent = widget.mine != null;
  late bool _contact = widget.mine?.contactOk ?? false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final a = widget.mine?.answers ?? const <String, dynamic>{};
    for (final q in widget.form.questions) {
      final v = a[q.id];
      switch (q.type) {
        case QuestionType.text:
          _text[q.id] = TextEditingController(text: v is String ? v : '');
        case QuestionType.one:
          _one[q.id] = v is String && q.options.contains(v) ? v : null;
        case QuestionType.many:
          _many[q.id] = {if (v is List) ...v.map((x) => '$x').where(q.options.contains) else if (v is String && q.options.contains(v)) v};
      }
    }
  }

  @override
  void dispose() {
    for (final c in _text.values) {
      c.dispose();
    }
    super.dispose();
  }

  Map<String, dynamic> _answers() {
    final out = <String, dynamic>{};
    for (final q in widget.form.questions) {
      switch (q.type) {
        case QuestionType.text:
          final t = _text[q.id]!.text.trim();
          if (t.isNotEmpty) out[q.id] = t;
        case QuestionType.one:
          final o = _one[q.id];
          if (o != null) out[q.id] = o;
        case QuestionType.many:
          final picked = [for (final o in q.options) if (_many[q.id]!.contains(o)) o];
          if (picked.isNotEmpty) out[q.id] = picked;
      }
    }
    return out;
  }

  Future<void> _save() async {
    final answers = _answers();
    final missing = widget.form.questions.where((q) => q.required && !answers.containsKey(q.id)).firstOrNull;
    final messenger = ScaffoldMessenger.of(context);
    if (missing != null) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text('Answer "${missing.label}" first.')));
      return;
    }
    setState(() => _busy = true);
    try {
      await ref.read(doorActionsProvider).saveRegistration(widget.eventId, answers: answers, contactOk: widget.form.askContact && _contact);
      if (mounted) Navigator.of(context).pop(true);
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('Registered. Thanks!')));
    } catch (e) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(friendlyError(e))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final f = widget.form;
    return ListView(
      shrinkWrap: true,
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      children: [
        for (final q in f.questions) ...[
          Text.rich(
            TextSpan(children: [
              TextSpan(text: q.label),
              if (q.required) const TextSpan(text: ' *', style: TextStyle(color: AppColors.brand)),
            ]),
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, height: 1.3),
          ),
          const SizedBox(height: 8),
          switch (q.type) {
            QuestionType.text => TextField(
                controller: _text[q.id],
                maxLength: 200,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(hintText: 'Your answer', counterText: ''),
              ),
            QuestionType.one => Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final o in q.options)
                    ChoiceChip(
                      label: Text(o, maxLines: 2, overflow: TextOverflow.ellipsis),
                      selected: _one[q.id] == o,
                      showCheckmark: false,
                      onSelected: (on) => setState(() => _one[q.id] = on ? o : null),
                    ),
                ],
              ),
            QuestionType.many => Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final o in q.options)
                    FilterChip(
                      label: Text(o, maxLines: 2, overflow: TextOverflow.ellipsis),
                      selected: _many[q.id]!.contains(o),
                      onSelected: (on) => setState(() => on ? _many[q.id]!.add(o) : _many[q.id]!.remove(o)),
                    ),
                ],
              ),
          },
          const SizedBox(height: 18),
        ],
        _Tick(value: _consent, text: f.consent, onChanged: (v) => setState(() => _consent = v)),
        if (f.askContact) _Tick(value: _contact, text: 'Share my phone and email with the organizer', onChanged: (v) => setState(() => _contact = v)),
        const SizedBox(height: 14),
        PrimaryButton(label: 'Save', loading: _busy, onPressed: _consent ? _save : null),
      ],
    );
  }
}

class _Tick extends StatelessWidget {
  const _Tick({required this.value, required this.text, required this.onChanged});
  final bool value;
  final String text;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => InkWell(
        borderRadius: BorderRadius.circular(AppRadius.md),
        onTap: () => onChanged(!value),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Checkbox(value: value, onChanged: (v) => onChanged(v ?? false), visualDensity: VisualDensity.compact),
              const SizedBox(width: 4),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Text(text, style: TextStyle(fontSize: 13.5, height: 1.35, color: AppColors.textPrimary)),
                ),
              ),
            ],
          ),
        ),
      );
}
