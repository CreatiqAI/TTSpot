import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/supabase/supabase_client.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/friendly_error.dart';
import '../../../core/utils/open_external.dart';
import '../../auth/application/account_basics.dart' show prettyPhone;

/// Call a friend: their number comes back only if they switched on
/// "Friends can call me" (Settings → Privacy). Then Phone or WhatsApp.
Future<void> showCallSheet(BuildContext context, WidgetRef ref, {required String userId, required String name}) async {
  String? phone;
  try {
    phone = await ref.read(supabaseProvider).rpc('friend_phone', params: {'p_user': userId}) as String?;
  } catch (e) {
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e))));
    return;
  }
  if (!context.mounted) return;
  if (phone == null || phone.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$name has not turned on calls from friends. Send a message instead.')));
    return;
  }
  final digits = phone.replaceAll(RegExp(r'[^0-9]'), '');
  final tel = phone;
  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
            child: Align(alignment: Alignment.centerLeft, child: Text('Call $name', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800))),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Align(alignment: Alignment.centerLeft, child: Text(prettyPhone(tel), style: const TextStyle(fontSize: 13, color: AppColors.textSecondary))),
          ),
          ListTile(
            leading: const Icon(AppIcons.phoneCall),
            title: const Text('Phone call', style: TextStyle(fontWeight: FontWeight.w600)),
            onTap: () {
              Navigator.pop(ctx);
              openExternal(context, 'tel:$tel');
            },
          ),
          ListTile(
            leading: const Icon(AppIcons.whatsappLogo, color: Color(0xFF25D366)),
            title: const Text('WhatsApp', style: TextStyle(fontWeight: FontWeight.w600)),
            subtitle: const Text('Voice or video call from the chat', style: TextStyle(fontSize: 12)),
            onTap: () {
              Navigator.pop(ctx);
              openExternal(context, 'whatsapp://send?phone=$digits', fallbackUrl: 'https://wa.me/$digits');
            },
          ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
}
