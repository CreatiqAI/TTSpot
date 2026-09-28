import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/titi.dart';
import '../../../core/utils/friendly_error.dart';
import '../../../core/widgets/user_avatar.dart';
import '../../auth/domain/profile.dart';
import '../../friends/application/friends_providers.dart';
import '../application/organizer_providers.dart';
import '../data/organizer_repository.dart';
import '../domain/organizer_models.dart';

/// Crew for one meet: co-hosts (announcements, draw, crew, door) and crew
/// (check-in QR, confirm arrivals, scan prize claims).
class CrewScreen extends ConsumerWidget {
  const CrewScreen({super.key, required this.eventId});
  final String eventId;

  Future<void> _run(BuildContext context, Future<void> Function() f, [String? done]) async {
    try {
      await f();
      if (done != null && context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(done)));
    } catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e))));
    }
  }

  Future<void> _add(BuildContext context, WidgetRef ref, EventRole role, List<CrewMember> crew) async {
    final picked = await showModalBottomSheet<Profile>(
      useRootNavigator: true,
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => _PeoplePicker(exclude: crew.map((c) => c.userId).toSet()),
    );
    if (picked == null || !context.mounted) return;
    var r = 'crew';
    if (role.managesCohosts) {
      final chosen = await _pickRole(context, picked.displayName ?? '@${picked.username}');
      if (chosen == null) return;
      r = chosen;
    }
    if (!context.mounted) return;
    await _run(context, () => ref.read(organizerActionsProvider).setCrew(eventId, picked.id, r),
        '${picked.displayName ?? '@${picked.username}'} is now ${r == 'cohost' ? 'a co-host' : 'on the crew'}.');
  }

  static Future<String?> _pickRole(BuildContext context, String name) => showModalBottomSheet<String>(
        useRootNavigator: true,
        context: context,
        showDragHandle: true,
        builder: (ctx) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Text('What does $name do?', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
              ),
              ListTile(
                leading: const Icon(AppIcons.qrCode),
                title: const Text('Crew', style: TextStyle(fontWeight: FontWeight.w700)),
                subtitle: const Text('Check-in QR, door list, confirm arrivals, scan prize claims.'),
                onTap: () => Navigator.pop(ctx, 'crew'),
              ),
              ListTile(
                leading: const Icon(AppIcons.crown),
                title: const Text('Co-host', style: TextStyle(fontWeight: FontWeight.w700)),
                subtitle: const Text('Everything crew can do, plus announcements, the lucky draw and adding crew.'),
                onTap: () => Navigator.pop(ctx, 'cohost'),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final role = ref.watch(myEventRoleProvider(eventId)).value ?? EventRole.none;
    final crew = ref.watch(eventCrewProvider(eventId));
    final list = crew.value ?? const <CrewMember>[];
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(AppIcons.arrowLeft), onPressed: () => context.pop()),
        title: const Text('Crew'),
      ),
      floatingActionButton: role.isHostCircle
          ? FloatingActionButton.extended(
              onPressed: () => _add(context, ref, role, list),
              icon: const Icon(AppIcons.userPlus),
              label: const Text('Add crew'),
            )
          : null,
      body: crew.when(
        loading: () => const Center(child: CircularProgressIndicator(strokeWidth: 2)),
        error: (e, _) => Center(child: Padding(padding: const EdgeInsets.all(32), child: Text(friendlyError(e), textAlign: TextAlign.center))),
        data: (list) => RefreshIndicator(
          onRefresh: () => ref.refresh(eventCrewProvider(eventId).future),
          child: ListView(
            padding: const EdgeInsets.only(bottom: 100),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: TitiSays(
                  list.length <= 1
                      ? 'Who\'s helping tonight? Add friends as crew for the door, or as co-hosts to run the draw and announcements.'
                      : 'Crew can\'t enter the lucky draw. That keeps it fair.',
                  pose: TitiPose.thumbsUp,
                  typing: false,
                ),
              ),
              for (final c in list)
                ListTile(
                  leading: UserAvatar(url: c.avatarUrl, name: c.name, size: 44),
                  title: Text(c.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text(c.username == null ? c.roleLabel : '@${c.username}', style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _RoleChip(c.roleLabel, strong: c.role != 'crew'),
                      if (c.role != 'host' && (role.managesCohosts || (role.isHostCircle && c.role == 'crew')))
                        PopupMenuButton<String>(
                          icon: Icon(AppIcons.dotsThreeVertical, color: AppColors.textSecondary),
                          onSelected: (v) => switch (v) {
                            'remove' => _run(context, () => ref.read(organizerActionsProvider).removeCrew(eventId, c.userId), 'Removed ${c.name}.'),
                            _ => _run(context, () => ref.read(organizerActionsProvider).setCrew(eventId, c.userId, v)),
                          },
                          itemBuilder: (_) => [
                            if (role.managesCohosts && c.role == 'crew') const PopupMenuItem(value: 'cohost', child: Text('Make co-host')),
                            if (role.managesCohosts && c.role == 'cohost') const PopupMenuItem(value: 'crew', child: Text('Make crew')),
                            const PopupMenuItem(value: 'remove', child: Text('Remove')),
                          ],
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RoleChip extends StatelessWidget {
  const _RoleChip(this.text, {this.strong = false});
  final String text;
  final bool strong;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(color: strong ? AppColors.textPrimary : AppColors.surfaceGray, borderRadius: BorderRadius.circular(AppRadius.pill)),
        child: Text(text.toUpperCase(), style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 0.6, color: strong ? AppColors.onInk : AppColors.textPrimary)),
      );
}

/// Friends first; type two letters of a handle to search everyone.
class _PeoplePicker extends ConsumerStatefulWidget {
  const _PeoplePicker({required this.exclude});
  final Set<String> exclude;

  @override
  ConsumerState<_PeoplePicker> createState() => _PeoplePickerState();
}

class _PeoplePickerState extends ConsumerState<_PeoplePicker> {
  final _q = TextEditingController();
  Timer? _debounce;
  List<Profile> _results = const [];
  bool _searching = false;

  @override
  void dispose() {
    _debounce?.cancel();
    _q.dispose();
    super.dispose();
  }

  void _onChanged(String v) {
    setState(() {});
    _debounce?.cancel();
    if (v.trim().replaceAll('@', '').length < 2) {
      setState(() => _results = const []);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 300), () async {
      setState(() => _searching = true);
      try {
        final r = await ref.read(organizerRepositoryProvider).searchUsers(v);
        if (mounted) setState(() => _results = r);
      } catch (_) {
        // keep the last results
      } finally {
        if (mounted) setState(() => _searching = false);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final q = _q.text.trim().replaceAll('@', '').toLowerCase();
    final friends = (ref.watch(friendsProvider).value ?? const <Profile>[])
        .where((p) => q.isEmpty || '${p.username ?? ''} ${p.displayName ?? ''}'.toLowerCase().contains(q))
        .toList();
    final ids = friends.map((f) => f.id).toSet();
    final others = _results.where((p) => !ids.contains(p.id)).toList();
    final all = [...friends, ...others].where((p) => !widget.exclude.contains(p.id)).toList();

    return SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.75,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: TextField(
                controller: _q,
                autofocus: true,
                onChanged: _onChanged,
                decoration: InputDecoration(
                  hintText: 'Search friends or any @handle',
                  prefixIcon: const Icon(AppIcons.magnifyingGlass, size: 20),
                  suffixIcon: _searching ? const Padding(padding: EdgeInsets.all(14), child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))) : null,
                  isDense: true,
                ),
              ),
            ),
            Expanded(
              child: all.isEmpty
                  ? Center(
                      child: Text(q.length < 2 ? 'Type a handle to find someone.' : 'No one found.', style: TextStyle(color: AppColors.textSecondary)),
                    )
                  : ListView.builder(
                      itemCount: all.length,
                      itemBuilder: (_, i) {
                        final p = all[i];
                        final friend = ids.contains(p.id);
                        return ListTile(
                          leading: UserAvatar(url: p.avatarUrl, name: p.displayName ?? p.username, size: 40),
                          title: Text(p.displayName ?? '@${p.username}', style: const TextStyle(fontWeight: FontWeight.w700)),
                          subtitle: Text('@${p.username ?? ''}${friend ? ' · friend' : ''}', style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary)),
                          trailing: Icon(AppIcons.plusCircle, color: AppColors.textPrimary),
                          onTap: () => Navigator.pop(context, p),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
