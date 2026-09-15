import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../../core/supabase/supabase_client.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/dates.dart';
import '../../../core/utils/friendly_error.dart';
import '../../../core/widgets/user_avatar.dart';
import '../application/admin_providers.dart';

/// Admin · Members: every account, searchable by name, handle, email or
/// phone, with quick filters and role actions.
class AdminMembersScreen extends ConsumerStatefulWidget {
  const AdminMembersScreen({super.key});

  @override
  ConsumerState<AdminMembersScreen> createState() => _AdminMembersScreenState();
}

class _AdminMembersScreenState extends ConsumerState<AdminMembersScreen> {
  final _q = TextEditingController();
  String _filter = 'all';

  static const _filters = [('all', 'All'), ('new', 'New this week'), ('active', 'Active today'), ('admins', 'Admins'), ('clubs', 'Club owners'), ('partners', 'Partners'), ('nocar', 'No car')];

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  bool _matches(AdminUser u) {
    final q = _q.text.trim().toLowerCase();
    if (q.isNotEmpty) {
      final hay = '${u.username} ${u.displayName ?? ''} ${u.email ?? ''} ${u.phone ?? ''} ${u.homeState ?? ''}'.toLowerCase();
      if (!hay.contains(q)) return false;
    }
    final now = DateTime.now();
    return switch (_filter) {
      'new' => u.createdAt.isAfter(now.subtract(const Duration(days: 7))),
      'active' => u.lastSeen != null && u.lastSeen!.isAfter(DateTime(now.year, now.month, now.day)),
      'admins' => u.isAdmin,
      'clubs' => u.clubOwner,
      'partners' => u.isPartner,
      'nocar' => u.cars == 0,
      _ => true,
    };
  }

  @override
  Widget build(BuildContext context) {
    final users = ref.watch(adminUsersProvider);
    final me = ref.watch(currentUserIdProvider);
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text('Members'),
        actions: [IconButton(tooltip: 'Refresh', icon: const Icon(AppIcons.arrowsClockwise), onPressed: () => ref.invalidate(adminUsersProvider))],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: TextField(
              controller: _q,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: 'Search name, @handle, email or phone',
                prefixIcon: const Icon(AppIcons.magnifyingGlass, size: 20),
                suffixIcon: _q.text.isEmpty ? null : IconButton(icon: const Icon(AppIcons.x, size: 18), onPressed: () => setState(_q.clear)),
                isDense: true,
              ),
            ),
          ),
          SizedBox(
            height: 40,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                for (final f in _filters)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(label: Text(f.$2), selected: _filter == f.$1, showCheckmark: false, onSelected: (_) => setState(() => _filter = f.$1)),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Expanded(
            child: users.when(
              loading: () => const Center(child: CircularProgressIndicator(strokeWidth: 2)),
              error: (e, _) => Center(child: Text(friendlyError(e))),
              data: (all) {
                final list = all.where(_matches).toList();
                return Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 2, 20, 4),
                      child: Align(alignment: Alignment.centerLeft, child: Text('${list.length} of ${all.length}', style: const TextStyle(fontSize: 12, color: AppColors.textSecondary, fontWeight: FontWeight.w600))),
                    ),
                    Expanded(
                      child: list.isEmpty
                          ? const Center(child: Text('No one matches.', style: TextStyle(color: AppColors.textSecondary)))
                          : ListView.separated(
                              itemCount: list.length,
                              separatorBuilder: (_, _) => const Divider(height: 1, indent: 72),
                              itemBuilder: (_, i) => _MemberRow(u: list[i], isMe: list[i].id == me),
                            ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _MemberRow extends ConsumerWidget {
  const _MemberRow({required this.u, required this.isMe});
  final AdminUser u;
  final bool isMe;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tags = <(String, Color)>[
      if (u.isAdmin) ('Admin', AppColors.brand),
      if (u.clubOwner) ('Club owner', const Color(0xFFA855F7)),
      if (u.isPartner) ('Partner', const Color(0xFF2B7CFF)),
    ];
    return ListTile(
      leading: UserAvatar(url: u.avatarUrl, name: u.displayName ?? u.username, size: 44),
      title: Row(
        children: [
          Flexible(child: Text(u.displayName ?? '@${u.username}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700))),
          for (final t in tags)
            Container(
              margin: const EdgeInsets.only(left: 6),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(color: t.$2.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(999)),
              child: Text(t.$1, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: t.$2)),
            ),
        ],
      ),
      subtitle: Text(
        '@${u.username}${u.email == null ? '' : ' · ${u.email}'}\n${u.phone ?? 'no phone'} · ${u.cars} car${u.cars == 1 ? '' : 's'} · joined ${u.createdAt.day}/${u.createdAt.month}/${u.createdAt.year % 100}${u.lastSeen == null ? '' : ' · seen ${timeAgo(u.lastSeen!)}'}',
        style: const TextStyle(fontSize: 12, color: AppColors.textSecondary, height: 1.35),
      ),
      isThreeLine: true,
      trailing: isMe
          ? null
          : PopupMenuButton<String>(
              onSelected: (v) async {
                final a = ref.read(adminActionsProvider);
                try {
                  switch (v) {
                    case 'admin':
                      await a.setRole(u.id, admin: !u.isAdmin);
                    case 'club':
                      await a.setRole(u.id, clubOwner: !u.clubOwner);
                    case 'profile':
                      if (context.mounted) context.push(Routes.profile(u.id));
                  }
                } catch (e) {
                  if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e))));
                }
              },
              itemBuilder: (_) => [
                const PopupMenuItem(value: 'profile', child: Text('Open profile')),
                PopupMenuItem(value: 'club', child: Text(u.clubOwner ? 'Remove club owner' : 'Make club owner')),
                PopupMenuItem(value: 'admin', child: Text(u.isAdmin ? 'Remove admin' : 'Make admin')),
              ],
            ),
      onTap: () => context.push(Routes.profile(u.id)),
    );
  }
}
