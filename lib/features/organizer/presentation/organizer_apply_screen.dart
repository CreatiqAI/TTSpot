import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/titi.dart';
import '../../../core/utils/dates.dart';
import '../../../core/utils/friendly_error.dart';
import '../../../core/widgets/primary_button.dart';
import '../../safety/application/name_check.dart';
import '../../vendors/application/vendors_providers.dart';
import '../../vendors/domain/vendor.dart';
import '../application/organizer_providers.dart';
import '../domain/organizer_models.dart';

/// "Apply to be an organizer": a short form an admin reviews. Approval turns
/// on crew roles, scheduled announcements and the free lucky draw on every
/// meet the member hosts, plus a verified seal next to their name.
class OrganizerApplyScreen extends ConsumerStatefulWidget {
  const OrganizerApplyScreen({super.key});

  @override
  ConsumerState<OrganizerApplyScreen> createState() => _OrganizerApplyScreenState();
}

class _OrganizerApplyScreenState extends ConsumerState<OrganizerApplyScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _links = TextEditingController();
  final _desc = TextEditingController();
  String? _size;
  bool _busy = false;
  bool _reapply = false;
  /// The name filter on the organisation name, while typing.
  late final LiveNameCheck _nameCheck;

  @override
  void initState() {
    super.initState();
    _nameCheck = LiveNameCheck(controller: _name, kind: NameKind.title, check: ref.read(nameCheckProvider))
      ..addListener(() {
        if (mounted) setState(() {});
      });
  }

  @override
  void dispose() {
    _nameCheck.dispose();
    _name.dispose();
    _links.dispose();
    _desc.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    await _nameCheck.verify();
    if (!mounted || !_form.currentState!.validate()) return;
    if (_size == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Pick your typical event size.')));
      return;
    }
    setState(() => _busy = true);
    try {
      await ref.read(organizerActionsProvider).apply(name: _name.text.trim(), links: _links.text.trim(), size: _size, description: _desc.text.trim());
      if (mounted) setState(() => _reapply = false);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final verified = ref.watch(amOrganizerProvider).value ?? false;
    final app = ref.watch(myPartnerApplicationProvider(ApplicationKind.organizer));
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(AppIcons.arrowLeft), onPressed: () => context.pop()),
        title: const Text('Apply to be an organizer'),
      ),
      body: app.when(
        loading: () => const Center(child: CircularProgressIndicator(strokeWidth: 2)),
        error: (e, _) => Center(child: Padding(padding: const EdgeInsets.all(32), child: Text(friendlyError(e), textAlign: TextAlign.center))),
        data: (a) {
          if (verified) return _Verified();
          if (a != null && !_reapply && a.status != ApplicationStatus.approved) {
            return _Status(app: a, onReapply: a.status == ApplicationStatus.rejected ? () => setState(() => _reapply = true) : null);
          }
          return _buildForm();
        },
      ),
    );
  }

  Widget _buildForm() {
    return Form(
      key: _form,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          TitiSays(
            'Run meets people trust. Verified organizers get a crew, scheduled announcements and a free lucky draw for checked-in members.',
            pose: TitiPose.thumbsUp,
          ),
          const SizedBox(height: 18),
          for (final f in const [
            (AppIcons.usersThree, 'Crew', 'Co-hosts and check-in crew for the door and the stage.'),
            (AppIcons.megaphone, 'Announcements', 'Message everyone linked to your meet, now or at a set time.'),
            (AppIcons.gift, 'Lucky draw', 'Free entry for checked-in members, drawn on our server, claim QR at the stage.'),
            (AppIcons.sealCheck, 'Verified seal', 'A blue seal next to your name on every meet you host.'),
          ])
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(f.$1, size: 22, color: AppColors.textPrimary),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text.rich(TextSpan(children: [
                      TextSpan(text: '${f.$2}. ', style: const TextStyle(fontWeight: FontWeight.w700)),
                      TextSpan(text: f.$3, style: TextStyle(color: AppColors.textSecondary)),
                    ]), style: const TextStyle(fontSize: 14, height: 1.35)),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 10),
          TextFormField(
            controller: _name,
            textCapitalization: TextCapitalization.words,
            maxLength: 80,
            decoration: InputDecoration(labelText: 'Organisation or crew name', hintText: 'e.g. Midnight Club KL', counterText: '', errorText: _nameCheck.problem, errorMaxLines: 2),
            validator: (v) => (v ?? '').trim().length < 2 ? 'Enter the name you run meets under' : _nameCheck.problem,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _links,
            keyboardType: TextInputType.url,
            decoration: const InputDecoration(labelText: 'Instagram or website', hintText: '@yourcrew or https://…'),
            validator: (v) => (v ?? '').trim().length < 3 ? 'Add a link so we can see your past meets' : null,
          ),
          const SizedBox(height: 16),
          Text('TYPICAL EVENT SIZE', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, letterSpacing: 1, color: AppColors.textSecondary)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final s in kEventSizes)
                ChoiceChip(label: Text(s), selected: _size == s, showCheckmark: false, onSelected: (_) => setState(() => _size = s)),
            ],
          ),
          const SizedBox(height: 16),
          TextFormField(
            textInputAction: TextInputAction.done,
            keyboardType: TextInputType.text,
            controller: _desc,
            maxLines: 4,
            maxLength: 500,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'About your meets',
              hintText: 'What kind of meets you run, where, how often, and who helps you run them.',
            ),
            validator: (v) => (v ?? '').trim().length < 20 ? 'Tell us a bit more about your meets' : null,
          ),
          const SizedBox(height: 20),
          PrimaryButton(label: 'Send application', loading: _busy, onPressed: _submit),
          const SizedBox(height: 10),
          Text(
            'We usually reply within a few days. Lucky draws are free to enter and the prizes are yours to provide; TT Spot provides the platform.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: AppColors.textMuted, height: 1.35),
          ),
        ],
      ),
    );
  }
}

class _Status extends StatelessWidget {
  const _Status({required this.app, this.onReapply});
  final PartnerApplication app;
  final VoidCallback? onReapply;

  @override
  Widget build(BuildContext context) {
    final pending = app.status == ApplicationStatus.pending;
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 32, 24, 32),
      children: [
        Center(child: Titi(pending ? TitiPose.phone : TitiPose.sad, height: 150)),
        const SizedBox(height: 16),
        Text(pending ? 'Application received' : 'Not approved this time', textAlign: TextAlign.center, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        Text(
          pending
              ? '${app.businessName} is waiting for review. Sent ${timeAgo(app.createdAt)}. We\'ll let you know in Activity.'
              : (app.reason == null || app.reason!.isEmpty ? 'No reason was given.' : app.reason!),
          textAlign: TextAlign.center,
          style: TextStyle(color: AppColors.textSecondary, height: 1.4),
        ),
        if (onReapply != null) ...[
          const SizedBox(height: 24),
          PrimaryButton(label: 'Apply again', onPressed: onReapply),
        ],
      ],
    );
  }
}

class _Verified extends StatelessWidget {
  const _Verified();

  @override
  Widget build(BuildContext context) => ListView(
        padding: const EdgeInsets.fromLTRB(24, 32, 24, 32),
        children: [
          const Center(child: Titi(TitiPose.celebrate, height: 160)),
          const SizedBox(height: 16),
          const Text('You\'re a verified organizer', textAlign: TextAlign.center, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          Text(
            'Open any meet you host and tap Organizer tools: add your crew, schedule announcements and set up a lucky draw.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textSecondary, height: 1.4),
          ),
          const SizedBox(height: 24),
          PrimaryButton(label: 'My meets', onPressed: () => context.pushReplacement(Routes.meets)),
        ],
      );
}
