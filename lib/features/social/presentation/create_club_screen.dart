import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/constants/malaysian_states.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/widgets/picker_field.dart';
import '../../../core/utils/friendly_error.dart';
import '../../vendors/application/vendors_providers.dart';
import '../../vendors/domain/vendor.dart';
import '../application/community_providers.dart';
import 'widgets/club_logo.dart';

/// New club. The logo comes first and is required (owner's rule: it is the
/// club's face on the map and on its events); Create stays off until there
/// is one. The logo sent with the club application is offered as a start.
class CreateClubScreen extends ConsumerStatefulWidget {
  const CreateClubScreen({super.key});

  @override
  ConsumerState<CreateClubScreen> createState() => _CreateClubScreenState();
}

class _CreateClubScreenState extends ConsumerState<CreateClubScreen> {
  final _name = TextEditingController();
  final _handle = TextEditingController();
  final _description = TextEditingController();
  String? _state;
  XFile? _avatar;
  /// The application's logo, once the member keeps it (no new upload needed).
  String? _appLogo;
  bool _appLogoDismissed = false;
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    _handle.dispose();
    _description.dispose();
    super.dispose();
  }

  bool get _hasLogo => _avatar != null || (_appLogo ?? '').isNotEmpty;

  Future<void> _pickLogo() async {
    final f = await pickClubLogo(context);
    if (f != null && mounted) {
      setState(() {
        _avatar = f;
        _appLogoDismissed = true;
      });
    }
  }

  Future<void> _create() async {
    FocusScope.of(context).unfocus();
    if (!_hasLogo) return;
    setState(() => _busy = true);
    try {
      final club = await ref.read(communityActionsProvider).createClub(
            name: _name.text,
            handle: _handle.text,
            description: _description.text.trim().isEmpty ? null : _description.text,
            homeState: _state,
            avatar: _avatar,
            avatarUrl: _avatar == null ? _appLogo : null,
          );
      if (mounted) context.pushReplacement(Routes.club(club.id));
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e))));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Start from the logo sent with the club application, when there was one.
    if (!_appLogoDismissed && _avatar == null && _appLogo == null) {
      final fromApp = ref.watch(myPartnerApplicationProvider(ApplicationKind.club)).value?.logoUrl;
      if ((fromApp ?? '').isNotEmpty) _appLogo = fromApp;
    }
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(AppIcons.x), onPressed: _busy ? null : () => context.pop()),
        title: const Text('New club'),
        actions: [
          _busy
              ? const Padding(padding: EdgeInsets.only(right: 20), child: Center(child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))))
              : TextButton(key: const Key('club-create'), onPressed: _hasLogo ? _create : null, child: const Text('Create')),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
        children: [
          ClubLogoPicker(file: _avatar, url: _avatar == null ? _appLogo : null, onTap: _busy ? null : _pickLogo),
          const SizedBox(height: 18),
          TextField(controller: _name, maxLength: 60, textCapitalization: TextCapitalization.words, decoration: const InputDecoration(labelText: 'Club name', hintText: 'e.g. Myvi Owners KL', counterText: '')),
          const SizedBox(height: 14),
          TextField(
            controller: _handle,
            maxLength: 24,
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9_]')), _Lower()],
            decoration: const InputDecoration(labelText: 'Handle', prefixText: '@', hintText: 'myvi_kl', counterText: ''),
          ),
          const SizedBox(height: 14),
          TextField(controller: _description, maxLength: 500, minLines: 2, maxLines: 5, textCapitalization: TextCapitalization.sentences, decoration: const InputDecoration(labelText: 'About', hintText: 'Who it\'s for, where you meet, house rules', alignLabelWithHint: true)),
          const SizedBox(height: 14),
          PickerField<String>(
            label: 'Home state (optional)',
            icon: AppIcons.mapPin,
            value: _state,
            options: [for (final s in malaysianStates) (s, s)],
            onChanged: (v) => setState(() => _state = v),
          ),
          const SizedBox(height: 20),
          FilledButton(
            key: const Key('club-create-bottom'),
            onPressed: _busy || !_hasLogo ? null : _create,
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
            child: Text(_hasLogo ? 'Create club' : 'Add a logo to create the club'),
          ),
        ],
      ),
    );
  }
}

class _Lower extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) => newValue.copyWith(text: newValue.text.toLowerCase());
}
