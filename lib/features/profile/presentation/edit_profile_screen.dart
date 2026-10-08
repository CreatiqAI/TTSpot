import 'package:flutter/foundation.dart' show Uint8List;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/constants/malaysian_states.dart';
import '../../../core/supabase/supabase_client.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/widgets/avatar_crop_screen.dart';
import '../../../core/widgets/picker_field.dart';
import '../../../core/utils/friendly_error.dart';
import '../../../core/widgets/titi_avatar_grid.dart';
import '../../../core/widgets/user_avatar.dart';
import '../../auth/application/onboarding_controller.dart';
import '../../auth/presentation/widgets/username_field.dart';
import '../../auth/data/auth_repository.dart';
import '../../safety/application/name_check.dart';
import '../application/profile_providers.dart';

/// Instagram "Edit profile": avatar + Edit picture, Name, Username, Bio, Home state.
class EditProfileScreen extends ConsumerStatefulWidget {
  const EditProfileScreen({super.key});

  @override
  ConsumerState<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends ConsumerState<EditProfileScreen> {
  final _name = TextEditingController();
  final _username = TextEditingController();
  final _bio = TextEditingController();
  String? _homeState;
  /// The cropped photo (a square JPEG), uploaded on Done.
  Uint8List? _avatar;
  /// A picked TiTi default avatar (0..7); saved as its public URL.
  int? _preset;
  bool _prefilled = false;
  final _form = GlobalKey<FormState>();
  /// The name filter on Name, while typing.
  late final LiveNameCheck _nameCheck;

  @override
  void initState() {
    super.initState();
    _nameCheck = LiveNameCheck(controller: _name, kind: NameKind.name, check: ref.read(nameCheckProvider))
      ..addListener(() {
        if (mounted) setState(() {});
      });
  }

  @override
  void dispose() {
    _nameCheck.dispose();
    _name.dispose();
    _username.dispose();
    _bio.dispose();
    super.dispose();
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _pickAvatar() async {
    final current = ref.read(currentProfileProvider).value?.avatarUrl;
    final selected = _avatar != null ? null : (_preset ?? DefaultAvatars.indexOfUrl(current));
    final choice = await showModalBottomSheet<Object>(
      useRootNavigator: true, // above the shell tab bar
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TitiAvatarGrid(selected: selected, onPick: (i) => Navigator.pop(ctx, i)),
            const Divider(height: 16),
            ListTile(leading: const Icon(AppIcons.images), title: const Text('Choose from library'), onTap: () => Navigator.pop(ctx, ImageSource.gallery)),
            ListTile(leading: const Icon(AppIcons.camera), title: const Text('Take photo'), onTap: () => Navigator.pop(ctx, ImageSource.camera)),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (choice is int) {
      setState(() {
        _preset = choice;
        _avatar = null;
      });
      return;
    }
    if (choice is! ImageSource) return;
    try {
      final f = await pickAvatarImage(choice);
      if (f == null || !mounted) return;
      final bytes = await f.readAsBytes();
      if (!mounted) return;
      // Zoom and move it under the circle: that square is what goes up.
      final cropped = await cropAvatar(context, bytes);
      if (cropped == null || !mounted) return;
      setState(() {
        _avatar = cropped;
        _preset = null;
      });
    } catch (e) {
      if (mounted) _snack(friendlyError(e));
    }
  }

  Future<void> _save() async {
    FocusScope.of(context).unfocus();
    await _nameCheck.verify();
    if (!mounted || !(_form.currentState?.validate() ?? true)) return;
    await ref.read(onboardingControllerProvider.notifier).submit(
          username: _username.text,
          displayName: _name.text,
          homeState: _homeState ?? '',
          bio: _bio.text,
          avatar: _avatar == null ? null : XFile.fromData(_avatar!, name: 'avatar.jpg', mimeType: 'image/jpeg'),
          presetAvatarUrl: _preset == null ? null : DefaultAvatars.publicUrl(_preset!),
        );
    final state = ref.read(onboardingControllerProvider);
    if (!state.hasError && mounted) {
      final me = ref.read(currentUserIdProvider);
      if (me != null) ref.invalidate(profileProvider(me));
      context.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(onboardingControllerProvider, (_, next) {
      if (next.hasError && !next.isLoading) _snack(friendlyError(next.error!));
    });
    final busy = ref.watch(onboardingControllerProvider).isLoading;
    final profile = ref.watch(currentProfileProvider).value;
    if (!_prefilled && profile != null) {
      _prefilled = true;
      _nameCheck.saved = profile.displayName;
      _name.text = profile.displayName ?? '';
      _username.text = profile.username ?? '';
      _bio.text = profile.bio ?? '';
      _homeState = malaysianStates.contains(profile.homeState) ? profile.homeState : null;
    }

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(AppIcons.x), onPressed: busy ? null : () => context.pop()),
        title: const Text('Edit profile'),
        actions: [
          busy
              ? const Padding(
                  padding: EdgeInsets.only(right: 20),
                  child: Center(child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))),
                )
              : TextButton(onPressed: _save, child: const Text('Done')),
        ],
      ),
      body: SafeArea(
        child: Form(
          key: _form,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
            children: [
              Center(
                child: Column(
                  children: [
                    GestureDetector(
                      onTap: busy ? null : _pickAvatar,
                      child: _avatar != null
                          ? Container(
                              width: 96,
                              height: 96,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                image: DecorationImage(image: MemoryImage(_avatar!), fit: BoxFit.cover),
                              ),
                            )
                          : _preset != null
                          ? Container(
                              width: 96,
                              height: 96,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                image: DecorationImage(image: AssetImage(DefaultAvatars.asset(_preset!)), fit: BoxFit.cover),
                              ),
                            )
                          : UserAvatar(url: profile?.avatarUrl, name: profile?.displayName ?? profile?.username, seed: profile?.id, size: 96),
                    ),
                    TextButton(onPressed: busy ? null : _pickAvatar, child: const Text('Edit picture')),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _name,
                textCapitalization: TextCapitalization.words,
                maxLength: 40,
                decoration: InputDecoration(labelText: 'Name', counterText: '', errorText: _nameCheck.problem, errorMaxLines: 2),
                validator: (_) => _nameCheck.problem,
              ),
              const SizedBox(height: 14),
              UsernameField(controller: _username, current: ref.watch(currentProfileProvider).value?.username),
              const SizedBox(height: 14),
              TextField(
                controller: _bio,
                maxLength: 300,
                minLines: 2,
                maxLines: 4,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(labelText: 'Bio', hintText: 'What you drive, where you hang out', alignLabelWithHint: true),
              ),
              const SizedBox(height: 14),
              PickerField<String>(
                label: 'Home state',
                icon: AppIcons.mapPin,
                value: _homeState,
                enabled: !busy,
                options: [for (final s in malaysianStates) (s, s)],
                onChanged: (v) => setState(() => _homeState = v),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
