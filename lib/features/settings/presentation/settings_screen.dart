import 'package:firebase_messaging/firebase_messaging.dart' show AuthorizationStatus;
import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/config/app_version.dart';
import '../../../core/directions/directions.dart';
import '../../../core/legal/legal_text.dart';
import '../../../core/router/app_router.dart';
import '../../../core/supabase/supabase_client.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/friendly_error.dart';
import '../../../core/utils/open_external.dart';
import '../../../core/widgets/primary_button.dart';
import '../../../core/widgets/user_avatar.dart';
import '../../auth/application/auth_controller.dart';
import '../../auth/application/account_basics.dart';
import '../../auth/data/auth_repository.dart';
import '../../auth/presentation/widgets/confirm_logout.dart';
import '../../friends/application/friends_providers.dart';
import '../../friends/domain/friend.dart';
import '../../map/presentation/widgets/visibility_sheet.dart';
import '../../safety/data/safety_repository.dart';
import '../../social/application/chat_providers.dart';
import '../../social/domain/chat.dart';
import '../../social/presentation/widgets/chat_wallpaper.dart';
import '../application/settings_providers.dart';
import '../../../core/push/push_service.dart';
import 'background_location_screen.dart';

bool get _isIOS => defaultTargetPlatform == TargetPlatform.iOS;

/// Settings: account, notifications, map, privacy, legal, support, danger.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider);
    final profile = ref.watch(currentProfileProvider).value;
    final email = ref.watch(supabaseProvider).auth.currentUser?.email ?? '';
    final act = ref.read(settingsActionsProvider);
    final basics = ref.watch(accountBasicsProvider).value ?? const AccountBasics();

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
        padding: EdgeInsets.only(bottom: MediaQuery.paddingOf(context).bottom + 24),
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
                      UserAvatar(url: profile?.avatarUrl, name: profile?.displayName ?? profile?.username, seed: profile?.id, size: 52),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(profile?.displayName ?? '@${profile?.username ?? ''}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                            Text('@${profile?.username ?? ''} · $email', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary)),
                          ],
                        ),
                      ),
                      Icon(AppIcons.caretRight, size: 18, color: AppColors.textMuted),
                    ],
                  ),
                ),
              ),
            ),
          ),

          const _Head('NOTIFICATIONS'),
          ValueListenableBuilder<String>(
            valueListenable: ref.read(pushServiceProvider).status,
            builder: (_, st, _) {
              final on = PushKind.values.where((k) => k.isOn(s)).length;
              return _Row(
                icon: AppIcons.bell,
                title: 'Push notifications',
                subtitle: switch (st) {
                  'On' => on == PushKind.values.length ? 'On for this phone' : 'On · $on of ${PushKind.values.length} kinds',
                  'Checking…' => 'Checking…',
                  _ when st.startsWith('Off in') => 'Off · not allowed on this phone',
                  _ => 'Off · tap to turn on',
                },
                onTap: () => context.push(Routes.pushSettings),
              );
            },
          ),

          const _Head('APPEARANCE'),
          _Choice(
            icon: AppIcons.moon,
            title: 'Theme',
            value: s.theme,
            options: const [('auto', 'Auto · light 7 am to 7 pm, dark at night'), ('light', 'Always light'), ('dark', 'Always dark')],
            onChanged: (v) => set({'theme': v, 'map_theme': v}),
          ),
          const _Note('The whole app follows this, map included.'),
          _Row(
            icon: AppIcons.image,
            title: 'Chat background',
            subtitle: ChatWallpaper.fromId(s.chatWallpaper).label,
            onTap: () => showChatWallpaperPicker(context),
          ),

          const _Head('MAP'),
          _Toggle(icon: AppIcons.car, title: 'Show my car colour', subtitle: 'Friends see your car in its real colour', value: s.showCarColor, onChanged: (v) => set({'show_car_color': v})),
          _Toggle(icon: AppIcons.checkCircle, title: 'Auto check-in', subtitle: 'Check in by itself when you arrive at a meet you joined', value: s.autoCheckin, onChanged: (v) => set({'auto_checkin': v})),
          _Choice(icon: AppIcons.gauge, title: 'Distances', value: s.units, options: const [('km', 'Kilometres'), ('mi', 'Miles')], onChanged: (v) => set({'units': v})),
          _Choice(
            icon: AppIcons.navigationArrow,
            title: 'Directions app',
            // Apple Maps picked on an iPhone means "ask" on Android.
            value: !_isIOS && s.directionsApp == DirectionsApp.apple.key ? kDirectionsAsk : s.directionsApp,
            options: [
              (kDirectionsAsk, 'Ask every time'),
              for (final a in directionsAppsFor(iOS: _isIOS)) (a.key, a.label),
            ],
            onChanged: (v) => set({'directions_app': v}),
          ),
          const _Note('Directions and Go now open this app. Long-press them to pick another.'),

          const _Head('PRIVACY'),
          _Row(
            icon: AppIcons.eye,
            title: 'Who can see my car',
            subtitle: _shareLabel(ref.watch(myLocationProvider).value),
            onTap: () => _openVisibility(context, ref),
          ),
          const BackgroundLocationTile(),
          _Choice(
            icon: AppIcons.chatText,
            title: 'Who can message me',
            value: s.dmFrom,
            options: const [('everyone', 'Everyone on TT Spot'), ('friends', 'Friends only')],
            onChanged: (v) => set({'dm_from': v}),
          ),
          _Choice(
            icon: AppIcons.phoneCall,
            title: 'Who can call me',
            value: s.callsFrom,
            options: const [('nobody', 'Nobody'), ('friends', 'Friends · phone or WhatsApp')],
            onChanged: (v) => set({'calls_from': v}),
          ),
          _Row(icon: AppIcons.prohibit, title: 'Blocked people', onTap: () => context.push(Routes.blocked)),

          const _Head('ABOUT'),
          _Row(icon: AppIcons.shieldCheck, title: 'Privacy Policy', onTap: () => context.push(Routes.privacy)),
          _Row(icon: AppIcons.listChecks, title: 'Terms of Use', onTap: () => context.push(Routes.terms)),
          _Row(icon: AppIcons.envelope, title: 'Contact us', subtitle: kLegalContact, onTap: () => openExternal(context, 'mailto:$kLegalContact?subject=TT%20Spot')),
          _Row(icon: AppIcons.globe, title: 'ttspot.my', onTap: () => openExternal(context, 'https://ttspot.my')),
          _Row(icon: AppIcons.info, title: 'About TT Spot', subtitle: 'Version $kAppVersion · what\'s new', onTap: () => context.push(Routes.about)),

          const _Head('ACCOUNT'),
          _Row(
            icon: AppIcons.envelope,
            title: 'Email',
            subtitle: '$email${basics.emailConfirmed ? ' · verified' : ' · not verified'}',
            onTap: () => ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Email changes are coming. For now, contact us to change it.'))),
          ),
          _Row(
            icon: AppIcons.phone,
            title: 'Phone number',
            subtitle: basics.phone == null ? 'Add your number' : '${prettyPhone(basics.phone!)} · private',
            onTap: () => _editPhone(context, ref, basics.phone),
          ),
          _Row(
            icon: AppIcons.link,
            title: 'Sign-in methods',
            subtitle: [if (basics.hasPassword) 'Email & password', if (basics.hasApple) 'Apple'].join(' · '),
            onTap: () => _signInMethods(context, ref),
          ),
          if (basics.hasPassword)
            _Row(icon: AppIcons.lock, title: 'Change password', subtitle: 'We email a reset link to $email', onTap: () async {
              try {
                await ref.read(authControllerProvider.notifier).requestPasswordReset(email);
                if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Reset link sent to $email. Check spam too.')));
              } catch (e) {
                if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e))));
              }
            })
          else
            _Row(icon: AppIcons.lock, title: 'Set a password', subtitle: 'So you can also log in with $email', onTap: () => _setPassword(context, ref)),
          _Row(icon: AppIcons.signOut, title: 'Log out', onTap: () => confirmLogout(context, ref)),
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

  /// The same "Who can see my car" sheet as the map's eye button, opened here
  /// once the current choice has loaded so it starts on the right option.
  Future<void> _openVisibility(BuildContext context, WidgetRef ref) async {
    try {
      await ref.read(myLocationProvider.future);
    } catch (_) {/* the sheet falls back to Friends */}
    if (context.mounted) await showVisibilitySheet(context);
  }

  static String _shareLabel(MyLocation? my) {
    if (my == null) return 'Friends · nearby · everyone · nobody';
    final km = my.shareRadiusM / 1000;
    return switch (my.shareMode) {
      'nearby' => 'Friends + nearby · ${km >= 1 ? '${km.toStringAsFixed(km % 1 == 0 ? 0 : 1)} km' : '${my.shareRadiusM} m'}',
      'public' => 'Everyone',
      'ghost' => 'Nobody (ghost)',
      _ => 'Friends',
    };
  }

  Future<void> _editPhone(BuildContext context, WidgetRef ref, String? current) async {
    final ctrl = TextEditingController(text: current == null ? '' : prettyPhone(current));
    final v = await showModalBottomSheet<String>(
      useRootNavigator: true, // above the shell tab bar
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.viewInsetsOf(ctx).bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Phone number', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text('Only you and TT Spot staff can see it. Malaysian numbers can skip the +60.', style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary)),
            const SizedBox(height: 14),
            TextField(
              controller: ctrl,
              autofocus: true,
              keyboardType: TextInputType.phone,
              inputFormatters: [MyPhoneFormatter()],
              decoration: const InputDecoration(hintText: '+60 12-345 6789', prefixIcon: Icon(AppIcons.phone, size: 20)),
              onSubmitted: (v) => Navigator.pop(ctx, v),
            ),
            const SizedBox(height: 14),
            FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text), child: const Text('Save')),
          ],
        ),
      ),
    );
    if (v == null || !context.mounted) return;
    try {
      await ref.read(accountActionsProvider).setPhone(v);
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Phone number saved.')));
    } catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e))));
    }
  }

  Future<void> _signInMethods(BuildContext context, WidgetRef ref) async {
    final b = ref.read(accountBasicsProvider).value ?? const AccountBasics();
    final email = ref.read(supabaseProvider).auth.currentUser?.email ?? '';
    await showModalBottomSheet<void>(
      useRootNavigator: true, // above the shell tab bar
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Sign-in methods', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              Text('How you can log in to this account.', style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary)),
              const SizedBox(height: 12),
              _Method(
                icon: AppIcons.envelope,
                title: 'Email & password',
                subtitle: b.hasPassword ? email : 'Not set. Add a password from Settings.',
                linked: b.hasPassword,
              ),
              const SizedBox(height: 8),
              _Method(
                icon: AppIcons.userCheck,
                title: 'Apple',
                subtitle: b.hasApple ? 'Linked' : 'Use "Sign in with Apple" on an iPhone',
                linked: b.hasApple,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _setPassword(BuildContext context, WidgetRef ref) async {
    final ctrl = TextEditingController();
    final v = await showModalBottomSheet<String>(
      useRootNavigator: true, // above the shell tab bar
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.viewInsetsOf(ctx).bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Set a password', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text('At least 6 characters. You can then log in with your email as well as Apple.', style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary)),
            const SizedBox(height: 14),
            TextField(controller: ctrl, autofocus: true, obscureText: true, decoration: const InputDecoration(hintText: 'New password'), onSubmitted: (v) => Navigator.pop(ctx, v)),
            const SizedBox(height: 14),
            FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text), child: const Text('Save')),
          ],
        ),
      ),
    );
    if (v == null || !context.mounted) return;
    try {
      await ref.read(accountActionsProvider).setPassword(v);
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Password set.')));
    } catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e))));
    }
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
          ? Center(child: Padding(padding: EdgeInsets.all(32), child: Text('Nobody blocked. Block someone from their profile\'s ⋯ menu.', textAlign: TextAlign.center, style: TextStyle(color: AppColors.textSecondary))))
          : ListView(
              children: [
                for (final id in ids)
                  Consumer(
                    builder: (ctx, ref, _) {
                      final p = ref.watch(blockedProfileProvider(id)).value;
                      return ListTile(
                        leading: UserAvatar(url: p?.avatarUrl, name: p?.displayName ?? p?.username, seed: id, size: 42),
                        title: Text(p?.displayName ?? '@${p?.username ?? '…'}', style: const TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: Text('@${p?.username ?? ''}', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
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

// ---------------------------------------------------------------- push ---

/// Each kind of push the server sends, with the profiles.settings switch
/// that silences it (the `push` Edge Function's SETTING map; the social
/// triggers in 20261003000097 and 20261005000102 read the social ones too).
enum PushKind {
  messages('notif_messages', AppIcons.chatCircle, 'Messages', 'New messages in your chats'),
  meets('notif_meets', AppIcons.flagCheckered, 'Meets', 'Reminders, changes, check-ins and host news'),
  tt('notif_tt', AppIcons.coffee, 'TT now pings', 'A friend starts a TT, a clubmate pulls up'),
  friendTt('notif_friend_tt', AppIcons.calendarCheck, "Friends' TT sessions", 'A friend plans a TT for later'),
  friendPosts('notif_friend_posts', AppIcons.images, "Friends' posts", 'New posts from friends and people you follow'),
  friends('notif_friends', AppIcons.users, 'Friends', 'Requests, likes, comments, club invites'),
  mentions('notif_mentions', AppIcons.chatText, 'Mentions', 'Someone tags you with @ in a post or comment'),
  replies('notif_replies', AppIcons.arrowBendUpLeft, 'Replies and comment likes', 'Someone replies to or likes your comment'),
  followers('notif_followers', AppIcons.userPlus, 'New followers', 'Someone starts following you'),
  clubMembers('notif_club_members', AppIcons.usersThree, 'New club members', "Someone joins a club you're in"),
  clubFollows('notif_club_follows', AppIcons.flagBanner, 'Clubs you follow', 'New posts and official meets from clubs you follow'),
  rewards('notif_rewards', AppIcons.gift, 'Rewards', 'Points, vouchers, badges and cards');

  const PushKind(this.key, this.icon, this.title, this.subtitle);
  final String key;
  final IconData icon;
  final String title;
  final String subtitle;

  bool isOn(AppSettings s) => switch (this) {
        messages => s.notifMessages,
        meets => s.notifMeets,
        tt => s.notifTt,
        friendTt => s.notifFriendTt,
        friendPosts => s.notifFriendPosts,
        friends => s.notifFriends,
        mentions => s.notifMentions,
        replies => s.notifReplies,
        followers => s.notifFollowers,
        clubMembers => s.notifClubMembers,
        clubFollows => s.notifClubFollows,
        rewards => s.notifRewards,
      };
}

/// Settings → Push notifications: is this phone getting pushes (and a way to
/// fix it when not), which kinds ping me, and the chats I muted.
class PushSettingsScreen extends ConsumerStatefulWidget {
  const PushSettingsScreen({super.key});

  @override
  ConsumerState<PushSettingsScreen> createState() => _PushSettingsScreenState();
}

class _PushSettingsScreenState extends ConsumerState<PushSettingsScreen> with WidgetsBindingObserver {
  AuthorizationStatus? _perm;
  bool _checked = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _check();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // Back from phone settings: read the permission again and register if it's now allowed.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _check(register: true);
  }

  Future<void> _check({bool register = false}) async {
    final push = ref.read(pushServiceProvider);
    final p = await push.permission();
    final allowed = p == AuthorizationStatus.authorized || p == AuthorizationStatus.provisional;
    if (register && allowed && push.status.value != 'On') await push.start();
    if (!mounted) return;
    setState(() {
      _perm = p;
      _checked = true;
    });
  }

  Future<void> _fix() async {
    setState(() => _busy = true);
    try {
      if (_blockedInSettings(_perm)) {
        final opened = await openPhoneNotificationSettings();
        if (!opened && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Open your phone\'s Settings, then Apps › TT Spot › Notifications, and allow them.')));
        }
      } else {
        await ref.read(pushServiceProvider).start(ask: true); // the phone's prompt again if it still may, then register
        await _check();
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _set(String key, bool v) async {
    try {
      await ref.read(settingsActionsProvider).patch({key: v});
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e))));
    }
  }

  Future<void> _unmute(Conversation c) async {
    try {
      await ref.read(chatActionsProvider).setMute(c.id, false);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(settingsProvider);
    final muted = (ref.watch(inboxProvider).value ?? const <Conversation>[]).where((c) => c.muted).toList();
    return Scaffold(
      appBar: AppBar(leading: IconButton(icon: const Icon(AppIcons.arrowLeft), onPressed: () => context.pop()), title: const Text('Push notifications')),
      body: ListView(
        padding: EdgeInsets.only(bottom: MediaQuery.paddingOf(context).bottom + 24),
        children: [
          ValueListenableBuilder<String>(
            valueListenable: ref.read(pushServiceProvider).status,
            builder: (_, st, _) => _PushStatusCard(checked: _checked, permission: _perm, status: st, busy: _busy, onFix: _fix),
          ),
          const _Head('WHAT PINGS YOU'),
          for (final k in PushKind.values)
            _Toggle(icon: k.icon, title: k.title, subtitle: k.subtitle, value: k.isOn(s), onChanged: (v) => _set(k.key, v)),
          const _Note('Switched off here, it still shows in Activity. It just stays off your lock screen.'),
          const _Head('MUTED CHATS'),
          if (muted.isEmpty)
            const _Note('None. Mute a chat from its info page and its messages stop pinging you.')
          else
            for (final c in muted)
              ListTile(
                leading: UserAvatar(url: c.avatarUrl, name: c.title, seed: c.other?.id ?? c.id, size: 40),
                title: Text(c.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14.5)),
                subtitle: Text(c.isMeet ? 'Meet chat · muted' : 'Muted', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                trailing: TextButton(onPressed: () => _unmute(c), child: const Text('Unmute')),
              ),
        ],
      ),
    );
  }
}

/// Only phone settings can turn notifications back on: Android after "Don't
/// allow" twice, and iOS after any "Don't Allow". A first Android denial can
/// still be asked again from the app.
bool _blockedInSettings(AuthorizationStatus? p) =>
    p == AuthorizationStatus.deniedPermanently || (p == AuthorizationStatus.denied && defaultTargetPlatform == TargetPlatform.iOS);

/// The phone's side: on, off (not allowed yet, or not set up) or blocked in
/// phone settings, with the one button that fixes it.
class _PushStatusCard extends StatelessWidget {
  const _PushStatusCard({required this.checked, required this.permission, required this.status, required this.busy, required this.onFix});
  final bool checked;
  final AuthorizationStatus? permission;
  final String status;
  final bool busy;
  final VoidCallback onFix;

  @override
  Widget build(BuildContext context) {
    final blocked = _blockedInSettings(permission);
    final allowed = permission == AuthorizationStatus.authorized || permission == AuthorizationStatus.provisional;
    final on = allowed && status == 'On';
    final (String title, String body, String? action, IconData? actionIcon) = !checked
        ? ('Checking…', 'Asking the phone.', null, null)
        : permission == null
            ? ('Not available', 'Push couldn\'t start on this phone. Close TT Spot, open it again and check here.', null, null)
            : blocked
                ? ('Not allowed in phone settings', 'Your phone is blocking TT Spot\'s notifications. Allow them there, then come back.', 'Open phone settings', AppIcons.gear)
                : !allowed
                    ? ('Off', 'TT Spot isn\'t allowed to notify you yet.', 'Turn on', AppIcons.bell)
                    : on
                    ? ('On', 'This phone gets the kinds switched on below.', null, null)
                    : status == 'Checking…'
                        ? ('Off', 'Not set up on this phone yet.', 'Turn on', AppIcons.bell)
                        : status.startsWith('Waiting for Apple')
                            ? ('Off', 'Waiting for Apple to hand over a push token. Try again in a minute.', 'Try again', AppIcons.arrowsClockwise)
                            // "Error: …" / "No push token": the full text is kept in settings.push_debug.
                            : ('Off', 'Couldn\'t set it up on this phone. Check your connection and try again.', 'Try again', AppIcons.arrowsClockwise);
    final tint = on ? AppColors.success : (blocked ? AppColors.danger : AppColors.textSecondary);
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: AppColors.surfaceGray, borderRadius: BorderRadius.circular(AppRadius.lg)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(color: tint.withValues(alpha: 0.14), shape: BoxShape.circle),
                child: Icon(on ? AppIcons.bellRinging : AppIcons.bellSlash, size: 22, color: tint),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: on ? AppColors.success : AppColors.textPrimary)),
                    const SizedBox(height: 2),
                    Text(body, style: TextStyle(fontSize: 12.5, height: 1.35, color: AppColors.textSecondary)),
                  ],
                ),
              ),
            ],
          ),
          if (action != null) ...[
            const SizedBox(height: 12),
            PrimaryButton(label: action, icon: actionIcon, loading: busy, onPressed: onFix),
          ],
        ],
      ),
    );
  }
}

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
          Text('Last updated $kLegalUpdated', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
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
        child: Text(text, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, letterSpacing: 1, color: AppColors.textSecondary)),
      );
}

class _Note extends StatelessWidget {
  const _Note(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
        child: Text(text, style: TextStyle(fontSize: 12, color: AppColors.textMuted, height: 1.35)),
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
        subtitle: subtitle == null ? null : Text(subtitle!, style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
      );
}

class _Method extends StatelessWidget {
  const _Method({required this.icon, required this.title, required this.subtitle, required this.linked});
  final IconData icon;
  final String title;
  final String subtitle;
  final bool linked;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
        decoration: BoxDecoration(color: AppColors.surfaceGray, borderRadius: BorderRadius.circular(AppRadius.md)),
        child: Row(
          children: [
            Icon(icon, size: 22, color: AppColors.textPrimary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5)),
                  Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                ],
              ),
            ),
            if (linked)
              const Icon(AppIcons.checkCircleFill, color: AppColors.success, size: 22),
          ],
        ),
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
        subtitle: subtitle == null ? null : Text(subtitle!, style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
        trailing: danger ? null : Icon(AppIcons.caretRight, size: 16, color: AppColors.textMuted),
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
      subtitle: Text(label, style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
      trailing: Icon(AppIcons.caretRight, size: 16, color: AppColors.textMuted),
      onTap: () async {
        final picked = await showModalBottomSheet<String>(
          useRootNavigator: true, // above the shell tab bar
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

