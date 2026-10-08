import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../../core/router/pop_or_home.dart';
import '../../../../core/theme/app_icons.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/friendly_error.dart';
import '../../../../core/widgets/primary_button.dart';
import '../../../events/application/event_providers.dart';
import '../application/door_providers.dart';
import '../data/door_repository.dart';
import '../domain/door_models.dart';
import '../domain/registration_csv.dart';

/// Host: the questions members answer after checking in, plus consent.
class RegistrationFormEditorScreen extends ConsumerStatefulWidget {
  const RegistrationFormEditorScreen({super.key, required this.eventId});
  final String eventId;

  @override
  ConsumerState<RegistrationFormEditorScreen> createState() => _RegistrationFormEditorScreenState();
}

/// One question being edited.
class _Draft {
  _Draft({required this.id, String label = '', this.type = QuestionType.text, List<String>? options, this.required = false})
    : label = TextEditingController(text: label),
      options = options ?? [];

  factory _Draft.of(FormQuestion q) => _Draft(id: q.id, label: q.label, type: q.type, options: [...q.options], required: q.required);

  final String id;
  final TextEditingController label;
  final TextEditingController newOption = TextEditingController();
  QuestionType type;
  final List<String> options;
  bool required;

  FormQuestion toQuestion() => FormQuestion(
    id: id,
    label: label.text.trim(),
    type: type,
    options: type == QuestionType.text ? const [] : options.map((o) => o.trim()).where((o) => o.isNotEmpty).toList(),
    required: required,
  );

  void dispose() {
    label.dispose();
    newOption.dispose();
  }
}

class _RegistrationFormEditorScreenState extends ConsumerState<RegistrationFormEditorScreen> {
  final _drafts = <_Draft>[];
  final _consent = TextEditingController();
  bool _askContact = true;
  bool _required = false;
  bool _loaded = false;
  bool _saving = false;
  bool _exporting = false;

  @override
  void dispose() {
    for (final d in _drafts) {
      d.dispose();
    }
    _consent.dispose();
    super.dispose();
  }

  void _load(RegistrationForm? f) {
    if (_loaded) return;
    _loaded = true;
    if (f == null) return;
    _drafts.addAll(f.questions.map(_Draft.of));
    _consent.text = f.consentText ?? '';
    _askContact = f.askContact;
    _required = f.required;
  }

  void _snack(String m) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(m)));

  void _add() {
    if (_drafts.length >= kMaxFormQuestions) return;
    setState(() => _drafts.add(_Draft(id: nextQuestionId(_drafts.map((d) => d.id)))));
  }

  void _move(int i, int by) {
    final j = i + by;
    if (j < 0 || j >= _drafts.length) return;
    setState(() => _drafts.insert(j, _drafts.removeAt(i)));
  }

  void _remove(int i) {
    final d = _drafts[i];
    setState(() => _drafts.removeAt(i));
    // Its text fields let go of the controllers in this frame.
    WidgetsBinding.instance.addPostFrameCallback((_) => d.dispose());
  }

  void _addOption(_Draft d) {
    final o = d.newOption.text.trim();
    if (o.isEmpty) return;
    if (d.options.length >= 20) return _snack('Up to 20 options.');
    if (d.options.contains(o)) return _snack('That option is already there.');
    setState(() {
      d.options.add(o.length > 60 ? o.substring(0, 60) : o);
      d.newOption.clear();
    });
  }

  Future<void> _save() async {
    // An option typed but not added yet counts.
    for (final d in _drafts) {
      if (d.type != QuestionType.text && d.newOption.text.trim().isNotEmpty) _addOption(d);
    }
    final questions = _drafts.map((d) => d.toQuestion()).toList();
    final problem = validateForm(questions);
    if (problem != null) return _snack(problem);
    setState(() => _saving = true);
    try {
      await ref
          .read(doorActionsProvider)
          .saveForm(widget.eventId, questions: questions, consentText: _consent.text, askContact: _askContact, required: _required && questions.isNotEmpty);
      _snack(questions.isEmpty ? 'Saved. No form for this event.' : 'Saved.');
    } catch (e) {
      _snack(friendlyError(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _export() async {
    setState(() => _exporting = true);
    try {
      final repo = ref.read(doorRepositoryProvider);
      final form = await repo.form(widget.eventId);
      final rows = await repo.exportRegistrations(widget.eventId);
      if (rows.isEmpty) {
        _snack('Nobody yet. Check-ins and answers show up here.');
        return;
      }
      final csv = buildRegistrationCsv(questions: form?.questions ?? const [], rows: rows);
      final title = ref.read(eventDetailProvider(widget.eventId)).value?.event.title ?? 'event';
      final safe = title.replaceAll(RegExp(r'[^A-Za-z0-9_-]+'), '_');
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/ttspot-registrations-$safe.csv');
      // BOM so Excel reads it as UTF-8.
      await file.writeAsString('﻿$csv', flush: true);
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path, mimeType: 'text/csv')],
          subject: 'Registrations: $title',
        ),
      );
    } catch (e) {
      _snack(friendlyError(e));
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final form = ref.watch(registrationFormProvider(widget.eventId));
    if (form.hasValue) _load(form.value);
    final head = TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, letterSpacing: 1, color: AppColors.textSecondary);

    return Scaffold(
      appBar: AppBar(
        leading: const AppBackButton(),
        title: const Text('Registration form'),
      ),
      body: !_loaded
          ? (form.hasError
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(friendlyError(form.error!), textAlign: TextAlign.center),
                    ),
                  )
                : const Center(child: CircularProgressIndicator(strokeWidth: 2)))
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
              children: [
                Text(
                  'People answer these after checking in. Up to $kMaxFormQuestions questions.',
                  style: TextStyle(fontSize: 13.5, color: AppColors.textSecondary, height: 1.4),
                ),
                const SizedBox(height: 14),
                for (var i = 0; i < _drafts.length; i++) ...[
                  _QuestionCard(
                    key: ObjectKey(_drafts[i]),
                    index: i,
                    draft: _drafts[i],
                    isFirst: i == 0,
                    isLast: i == _drafts.length - 1,
                    onUp: () => _move(i, -1),
                    onDown: () => _move(i, 1),
                    onDelete: () => _remove(i),
                    onChanged: () => setState(() {}),
                    onAddOption: () => _addOption(_drafts[i]),
                  ),
                  const SizedBox(height: 10),
                ],
                SecondaryButton(
                  label: _drafts.length >= kMaxFormQuestions ? 'That is the most' : 'Add question',
                  icon: AppIcons.plus,
                  onPressed: _drafts.length >= kMaxFormQuestions ? null : _add,
                ),
                const SizedBox(height: 22),
                Text('CONSENT', style: head),
                const SizedBox(height: 8),
                TextField(
                  textInputAction: TextInputAction.done,
                  keyboardType: TextInputType.text,
                  controller: _consent,
                  maxLength: 300,
                  maxLines: 3,
                  minLines: 1,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(hintText: kDefaultConsent, counterText: ''),
                ),
                const SizedBox(height: 6),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _askContact,
                  onChanged: (v) => setState(() => _askContact = v),
                  title: const Text('Ask for phone & email', style: TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text('Only shared when they tick it.', style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary)),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _required,
                  onChanged: (v) => setState(() => _required = v),
                  title: const Text('Required', style: TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text('Their pass keeps asking until it is done.', style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary)),
                ),
                const SizedBox(height: 14),
                PrimaryButton(label: 'Save', loading: _saving, onPressed: _save),
                const SizedBox(height: 10),
                SecondaryButton(label: _exporting ? 'Exporting…' : 'Export CSV', icon: AppIcons.fileCsv, onPressed: _exporting ? null : _export),
                const SizedBox(height: 8),
                Text(
                  'Everyone who checked in or answered, with their entry number. Phone and email only for people who agreed.',
                  style: TextStyle(fontSize: 12, color: AppColors.textMuted, height: 1.35),
                ),
              ],
            ),
    );
  }
}

class _QuestionCard extends StatelessWidget {
  const _QuestionCard({
    super.key,
    required this.index,
    required this.draft,
    required this.isFirst,
    required this.isLast,
    required this.onUp,
    required this.onDown,
    required this.onDelete,
    required this.onChanged,
    required this.onAddOption,
  });

  final int index;
  final _Draft draft;
  final bool isFirst;
  final bool isLast;
  final VoidCallback onUp;
  final VoidCallback onDown;
  final VoidCallback onDelete;
  final VoidCallback onChanged;
  final VoidCallback onAddOption;

  @override
  Widget build(BuildContext context) {
    final d = draft;
    return Material(
      color: AppColors.surfaceGray,
      borderRadius: BorderRadius.circular(AppRadius.lg),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 6, 6, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'QUESTION ${index + 1}',
                    style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, letterSpacing: 1, color: AppColors.textSecondary),
                  ),
                ),
                IconButton(
                  tooltip: 'Move up',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(AppIcons.arrowUp, size: 18),
                  onPressed: isFirst ? null : onUp,
                ),
                IconButton(
                  tooltip: 'Move down',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(AppIcons.arrowDown, size: 18),
                  onPressed: isLast ? null : onDown,
                ),
                IconButton(
                  tooltip: 'Delete',
                  visualDensity: VisualDensity.compact,
                  icon: Icon(AppIcons.trash, size: 18, color: AppColors.danger),
                  onPressed: onDelete,
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: TextField(
                controller: d.label,
                maxLength: 120,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(hintText: 'e.g. You are a', counterText: ''),
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final t in QuestionType.values)
                  ChoiceChip(
                    label: Text(t.label),
                    selected: d.type == t,
                    showCheckmark: false,
                    onSelected: (_) {
                      d.type = t;
                      onChanged();
                    },
                  ),
              ],
            ),
            if (d.type != QuestionType.text) ...[
              const SizedBox(height: 10),
              if (d.options.isNotEmpty)
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final o in d.options)
                      InputChip(
                        label: Text(o, maxLines: 1, overflow: TextOverflow.ellipsis),
                        onDeleted: () {
                          d.options.remove(o);
                          onChanged();
                        },
                      ),
                  ],
                ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: d.newOption,
                      maxLength: 60,
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => onAddOption(),
                      decoration: const InputDecoration(hintText: 'Add an option', counterText: ''),
                    ),
                  ),
                  IconButton(tooltip: 'Add option', icon: const Icon(AppIcons.plusCircle), onPressed: onAddOption),
                ],
              ),
            ],
            SwitchListTile(
              dense: true,
              contentPadding: const EdgeInsets.only(right: 6),
              value: d.required,
              onChanged: (v) {
                d.required = v;
                onChanged();
              },
              title: const Text('Required', style: TextStyle(fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      ),
    );
  }
}
