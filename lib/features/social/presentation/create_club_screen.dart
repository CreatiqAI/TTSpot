import 'dart:io';

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
import '../../../core/widgets/photo_picker_sheet.dart';
import '../../../core/widgets/user_avatar.dart';
import '../application/community_providers.dart';

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
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    _handle.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    FocusScope.of(context).unfocus();
    setState(() => _busy = true);
    try {
      final club = await ref.read(communityActionsProvider).createClub(
            name: _name.text,
            handle: _handle.text,
            description: _description.text.trim().isEmpty ? null : _description.text,
            homeState: _state,
            avatar: _avatar,
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
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(AppIcons.x), onPressed: _busy ? null : () => context.pop()),
        title: const Text('New club'),
        actions: [
          _busy
              ? const Padding(padding: EdgeInsets.only(right: 20), child: Center(child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))))
              : TextButton(onPressed: _create, child: const Text('Create')),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
        children: [
          Center(
            child: Column(
              children: [
                GestureDetector(
                  onTap: () async {
                    final files = await pickPhotos(context, max: 1, multi: false);
                    if (files.isNotEmpty) setState(() => _avatar = files.first);
                  },
                  child: _avatar == null
                      ? const UserAvatar(name: 'C', size: 96)
                      : Container(width: 96, height: 96, decoration: BoxDecoration(shape: BoxShape.circle, image: DecorationImage(image: FileImage(File(_avatar!.path)), fit: BoxFit.cover))),
                ),
                TextButton(
                  onPressed: () async {
                    final files = await pickPhotos(context, max: 1, multi: false);
                    if (files.isNotEmpty) setState(() => _avatar = files.first);
                  },
                  child: const Text('Add club logo'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
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
        ],
      ),
    );
  }
}

class _Lower extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) => newValue.copyWith(text: newValue.text.toLowerCase());
}
