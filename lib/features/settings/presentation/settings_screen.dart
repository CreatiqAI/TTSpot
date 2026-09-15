import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/config/app_version.dart';
import '../../../core/legal/legal_text.dart';
import '../../../core/router/app_router.dart';
import '../../../core/supabase/supabase_client.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/friendly_error.dart';
import '../../../core/utils/open_external.dart';
import '../../../core/widgets/user_avatar.dart';
import '../../auth/application/auth_controller.dart';
import '../../auth/data/auth_repository.dart';
import '../../safety/data/safety_repository.dart';
import '../application/settings_providers.dart';

/// Settings: account, notifications, map, privacy, legal, support, danger.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider);
    final profile = ref.watch(currentProfileProvider).value;
    final email = ref.watch(supabaseProvider).auth.currentUser?.email ?? '';
    final act = ref.read(settingsActionsProvider);

    Future<void> set(Map<String, dynamic> patch) async {
      try {
        await act.patch(patch);
      } catch (e) {
        if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e))));
      }
    }

    return Scaffold(
      appBar: AppBar(leading: IconButton(icon: const Icon(AppIcons.arrowLeft), onPressed: () => context.pop()), title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 40),
        children: [
          // ---- account card
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Material(
              color: AppColors.surfaceGray,
              borderRadius: BorderRadius.circular(AppRadius.lg),
              child: InkWell(
                borderRadius: BorderRadius.circular(AppRadius.lg),
                onTap: () => context.push(Routes.editProfile),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    children: [
                      UserAvatar(url: profile?.avatarUrl, name: profile?.displayName ?? profile?.username, size: 52),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(profile?.displayName ?? '@${profile?.username ?? ''}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                            Text('@${profile?.username ?? ''} · $email', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary)),
                          ],
                        ),
                      ),
                      const Icon(AppIcons.caretRight, size: 18, color: AppColors.textMuted),
                    ],
                  ),
                ),
              ),
            ),
          ),

          const _Head('NOTIFICATIONS'),
          _Toggle(icon: AppIcons.coffee, title: 'TT now pings', subtitle: 'When a friend starts a TT near you', value: s.notifTt, onChanged: (v) => set({'notif_tt': v})),
          _Toggle(icon: AppIcons.flagCheckered, title: 'Meets', subtitle: 'Reminders, changes and who joined', value: s.notifMeets, onChanged: (v) => set({'notif_meets': v})),
          _Toggle(icon: AppIcons.chatCircle, title: 'Messages', subtitle: 'New chat messages', value: s.notifMessages, onChanged: (v) => set({'notif_messages': v})),
          _Toggle(icon: AppIcons.users, title: 'Friends', subtitle: 'Requests, accepts and club invites', value: s.notifFriends, onChanged: (v) => set({'notif_friends': v})),
          _Toggle(icon: AppIcons.gift, title: 'Rewards', subtitle: 'Points earned, vouchers, badges', value: s.notifRewards, onChanged: (v) => set({'notif_rewards': v})),
          const _Note('Push notifications arrive once the app is published. These choices are saved now.'),

          const _Head('MAP'),
          _Choice(
            icon: AppIcons.mapTrifold,
            title: 'Map theme',
            value: s.mapTheme,
            options: const [('auto', 'Auto · light by day, dark after 7 pm'), ('light', 'Always light'), ('dark', 'Always dark')],
            onChanged: (v) => set({'map_theme': v}),
          ),
          _Toggle(icon: AppIcons.car, title: 'Show my car colour', subtitle: 'Friends see your car in its real colour', value: s.showCarColor, onChanged: (v) => set({'show_car_color': v})),
          _Toggle(icon: AppIcons.checkCircle, title: 'Auto check-in', subtitle: 'Check in by itself when you arrive at a meet you joined', value: s.autoCheckin, onChanged: (v) => set({'auto_checkin': v})),
          _Choice(icon: AppIcons.gauge, title: 'Distances', value: s.units, options: const [('km', 'Kilometres'), ('mi', 'Miles')], onChanged: (v) => set({'units': v})),

          const _Head('PRIVACY'),
          _Row(icon: AppIcons.eye, title: 'Who can see my car', subtitle: 'Friends · nearby · everyone · nobody', onTap: () => context.go(Routes.map)),
          _Choice(
            icon: AppIcons.chatText,
            title: 'Who can message me',
            value: s.dmFrom,
            options: const [('everyone', 'Everyone on TT Spot'), ('friends', 'Friends only')],
            onChanged: (v) => set({'dm_from': v}),
          ),
          _Row(icon: AppIcons.prohibit, title: 'Blocked people', onTap: () => context.push(Routes.blocked)),

          const _Head('ABOUT'),
          _Row(icon: AppIcons.shieldCheck, title: 'Privacy Policy', onTap: () => context.push(Routes.privacy)),
          _Row(icon: AppIcons.listChecks, title: 'Terms of Use', onTap: () => context.push(Routes.terms)),
          _Row(icon: AppIcons.envelope, title: 'Contact us', subtitle: kLegalContact, onTap: () => openExternal(context, 'mailto:$kLegalContact?subject=TT%20Spot')),
          _Row(icon: AppIcons.globe, title: 'ttspot.my', onTap: () => openExternal(context, 'https://ttspot.my')),
          const _Version(),

          const _Head('ACCOUNT'),
          _Row(icon: AppIcons.lock, title: 'Change password', subtitle: 'We email you a reset link', onTap: () async {
            try {
              await ref.read(authControllerProvider.notifier).requestPasswordReset(email);
              if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Reset link sent. Check your email.')));
            } catch (e) {
              if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e))));
            }
          }),
          _Row(icon: AppIcons.signOut, title: 'Log out', onTap: () => ref.read(authControllerProvider.notifier).signOut()),
          _Row(
            icon: AppIcons.trash,
            title: 'Delete account',
            subtitle: 'Removes your profile, cars, posts and messages for good',
            danger: true,
            onTap: () => _confirmDelete(context, ref),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete your account?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('This cannot be undone. Type DELETE to confirm.', style: TextStyle(height: 1.4)),
            const SizedBox(height: 12),
            TextField(controller: ctrl, autofocus: true, decoration: const InputDecoration(hintText: 'DELETE')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep my account')),
          TextButton(onPressed: () => Navigator.pop(ctx, ctrl.text.trim() == 'DELETE'), child: const Text('Delete', style: TextStyle(color: AppColors.danger))),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    try {
      await ref.read(settingsActionsProvider).deleteAccount();
    } catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e))));
    }
  }
}

// ------------------------------------------------------------- blocked ---

class BlockedScreen extends ConsumerWidget {
  const BlockedScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(currentUserIdProvider);
    final ids = ref.watch(blockedUserIdsProvider).value ?? const <String>{};
    return Scaffold(
      appBar: AppBar(leading: IconButton(icon: const Icon(AppIcons.arrowLeft), onPressed: () => context.pop()), title: const Text('Blocked people')),
      body: ids.isEmpty
          ? const Center(child: Padding(padding: EdgeInsets.all(32), child: Text('Nobody blocked. Block someone from their profile\'s ⋯ menu.', textAlign: TextAlign.center, style: TextStyle(color: AppColors.textSecondary))))
          : ListView(
              children: [
                for (final id in ids)
                  Consumer(
                    builder: (ctx, ref, _) {
                      final p = ref.watch(blockedProfileProvider(id)).value;
                      return ListTile(
                        leading: UserAvatar(url: p?.avatarUrl, name: p?.displayName ?? p?.username, size: 42),
                        title: Text(p?.displayName ?? '@${p?.username ?? '…'}', style: const TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: Text('@${p?.username ?? ''}', style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                        trailing: TextButton(
                          onPressed: me == null
                              ? null
                              : () async {
                                  await ref.read(safetyRepositoryProvider).unblock(blockerId: me, blockedId: id);
                                  ref.invalidate(blockedUserIdsProvider);
                                },
                          child: const Text('Unblock'),
                        ),
                      );
                    },
                  ),
              ],
            ),
    );
  }
}

final blockedProfileProvider = FutureProvider.family((ref, String id) => ref.watch(authRepositoryProvider).fetchProfile(id));

// --------------------------------------------------------------- legal ---

class LegalScreen extends StatelessWidget {
  const LegalScreen({super.key, required this.title, required this.body});
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final blocks = body.trim().split('\n');
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(AppIcons.arrowLeft), onPressed: () => context.pop()),
        title: Text(title),
        actions: [IconButton(tooltip: 'Copy', icon: const Icon(AppIcons.link), onPressed: () => Clipboard.setData(ClipboardData(text: body)))],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
        children: [
          Text('Last updated $kLegalUpdated', style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
          const SizedBox(height: 8),
          for (final line in blocks)
            if (line.startsWith('# '))
              Padding(
                padding: const EdgeInsets.only(top: 18, bottom: 6),
                child: Text(line.substring(2), style: const TextStyle(fontFamily: AppFonts.display, fontSize: 22, fontWeight: FontWeight.w700, height: 1)),
              )
            else if (line.startsWith('- '))
              Padding(
                padding: const EdgeInsets.only(left: 6, bottom: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('•  ', style: TextStyle(fontSize: 14.5, height: 1.5)),
                    Expanded(child: Text(line.substring(2), style: const TextStyle(fontSize: 14.5, height: 1.5))),
                  ],
                ),
              )
            else if (line.trim().isNotEmpty)
              Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(line, style: const TextStyle(fontSize: 14.5, height: 1.5))),
        ],
      ),
    );
  }
}

// -------------------------------------------------------------- pieces ---

class _Head extends StatelessWidget {
  const _Head(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 22, 20, 6),
        child: Text(text, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, letterSpacing: 1, color: AppColors.textSecondary)),
      );
}

class _Note extends StatelessWidget {
  const _Note(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
        child: Text(text, style: const TextStyle(fontSize: 12, color: AppColors.textMuted, height: 1.35)),
      );
}

class _Toggle extends StatelessWidget {
  const _Toggle({required this.icon, required this.title, this.subtitle, required this.value, required this.onChanged});
  final IconData icon;
  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;
  @override
  Widget build(BuildContext context) => SwitchListTile.adaptive(
        value: value,
        onChanged: onChanged,
        activeTrackColor: AppColors.brand,
        secondary: Icon(icon, color: AppColors.textPrimary),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14.5)),
        subtitle: subtitle == null ? null : Text(subtitle!, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
      );
}

class _Row extends StatelessWidget {
  const _Row({required this.icon, required this.title, this.subtitle, required this.onTap, this.danger = false});
  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;
  final bool danger;
  @override
  Widget build(BuildContext context) => ListTile(
        leading: Icon(icon, color: danger ? AppColors.danger : AppColors.textPrimary),
        title: Text(title, style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14.5, color: danger ? AppColors.danger : AppColors.textPrimary)),
        subtitle: subtitle == null ? null : Text(subtitle!, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
        trailing: danger ? null : const Icon(AppIcons.caretRight, size: 16, color: AppColors.textMuted),
        onTap: onTap,
      );
}

class _Choice extends StatelessWidget {
  const _Choice({required this.icon, required this.title, required this.value, required this.options, required this.onChanged});
  final IconData icon;
  final String title;
  final String value;
  final List<(String, String)> options;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final label = options.where((o) => o.$1 == value).firstOrNull?.$2 ?? value;
    return ListTile(
      leading: Icon(icon, color: AppColors.textPrimary),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14.5)),
      subtitle: Text(label, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
      trailing: const Icon(AppIcons.caretRight, size: 16, color: AppColors.textMuted),
      onTap: () async {
        final picked = await showModalBottomSheet<String>(
          context: context,
          showDragHandle: true,
          builder: (ctx) => SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(padding: const EdgeInsets.fromLTRB(20, 0, 20, 8), child: Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800))),
                for (final o in options)
                  ListTile(
                    title: Text(o.$2, style: TextStyle(fontWeight: o.$1 == value ? FontWeight.w700 : FontWeight.w500)),
                    trailing: o.$1 == value ? const Icon(AppIcons.checkCircleFill, color: AppColors.brand) : null,
                    onTap: () => Navigator.pop(ctx, o.$1),
                  ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        );
        if (picked != null && picked != value) onChanged(picked);
      },
    );
  }
}

class _Version extends StatelessWidget {
  const _Version();
  @override
  Widget build(BuildContext context) => ListTile(
        leading: const Icon(AppIcons.info, color: AppColors.textPrimary),
        title: const Text('Version', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14.5)),
        subtitle: const Text('TT Spot $kAppVersion ($kAppBuild) · tap for open-source licences', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
        onTap: () => showLicensePage(context: context, applicationName: 'TT Spot', applicationVersion: kAppVersion),
      );
}
