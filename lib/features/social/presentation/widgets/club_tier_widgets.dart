import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/app_router.dart';
import '../../../../core/theme/app_icons.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/dates.dart';
import '../../../../core/utils/friendly_error.dart';
import '../../../../core/utils/open_external.dart';
import '../../../../core/widgets/place_search_field.dart';
import '../../../../core/widgets/primary_button.dart';
import '../../../../core/widgets/user_avatar.dart';
import '../../../map/application/map_providers.dart';
import '../../application/community_providers.dart';
import '../../domain/club.dart';

/// Human labels for club roles.
String clubRoleLabel(String role) => switch (role) {
      'owner' => 'President',
      'vp' => 'Vice President',
      'secretary' => 'Secretary',
      _ => 'Member',
    };

String clubRoleShort(String role) => switch (role) {
      'owner' => 'President',
      'vp' => 'VP',
      'secretary' => 'Secretary',
      _ => 'Member',
    };

/// What each tier gets. Shown on the club page and in the Go official sheet.
const kOfficialPerks = [
  ('Meets with notifications', 'Every member hears about a new meet.'),
  ('Plan any distance ahead', 'No 7-day limit on scheduling.'),
  ('Exclusive club badge on the map', 'Gold pin for your meets.'),
  ('No member limit', 'Underground clubs stop at 100.'),
  ('Partner benefits', 'Extra vendor perks for your members.'),
  ('10 % bonus points', 'President earns 10 % on every member check-in.'),
];

const kUndergroundPerks = [
  ('Meets up to 7 days ahead', 'Quiet: no notifications, just your people.'),
  ('Up to 100 members', 'Small crew, easy to run.'),
  ('Club garage', 'Get pinged when a clubmate pulls up.'),
  ('Share location with the club', 'Each member decides.'),
  ('Active member leaderboard', 'See who really shows up.'),
];

/// Official / Underground card. Owners of an underground club can request
/// the official tier; admins approve after payment (RM 69.90 / month).
class ClubTierCard extends ConsumerStatefulWidget {
  const ClubTierCard({super.key, required this.club, required this.isOwner});
  final Club club;
  final bool isOwner;
  @override
  ConsumerState<ClubTierCard> createState() => _ClubTierCardState();
}

class _ClubTierCardState extends ConsumerState<ClubTierCard> {
  bool _busy = false;

  Future<void> _request() async {
    final ok = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Row(children: [Icon(AppIcons.sealCheck, color: Color(0xFFD4A017)), SizedBox(width: 8), Text('Go official', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800))]),
              const SizedBox(height: 4),
              Text('RM 69.90 a month. We confirm the payment with you, then switch the club over.', style: TextStyle(fontSize: 13.5, color: AppColors.textSecondary, height: 1.4)),
              const SizedBox(height: 12),
              for (final p in kOfficialPerks)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(AppIcons.checkCircle, size: 18, color: AppColors.success),
                      const SizedBox(width: 8),
                      Expanded(child: RichText(text: TextSpan(style: TextStyle(fontSize: 13.5, color: AppColors.textPrimary, height: 1.35), children: [TextSpan(text: p.$1, style: const TextStyle(fontWeight: FontWeight.w700)), TextSpan(text: ' · ${p.$2}', style: TextStyle(color: AppColors.textSecondary))]))),
                    ],
                  ),
                ),
              const SizedBox(height: 14),
              PrimaryButton(label: 'Request official status', onPressed: () => Navigator.pop(ctx, true)),
            ],
          ),
        ),
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await ref.read(communityActionsProvider).requestOfficialClub(widget.club.id);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Request sent. We\'ll message you about payment.')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.club;
    if (c.isOfficial) {
      return Container(
        margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        decoration: BoxDecoration(color: const Color(0xFFD4A017).withValues(alpha: 0.12), borderRadius: BorderRadius.circular(AppRadius.md)),
        child: Row(
          children: [
            const Icon(AppIcons.sealCheck, color: Color(0xFFB8860B)),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Official club', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5)),
                  Text(
                    c.officialUntil == null ? 'Meet notifications, gold map badge, no member limit.' : 'Active until ${formatDate(c.officialUntil!)} · meet notifications, gold badge, no member limit.',
                    style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary, height: 1.35),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }
    if (!widget.isOwner) return const SizedBox.shrink();
    final pending = c.officialRequestedAt != null;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(color: AppColors.surfaceGray, borderRadius: BorderRadius.circular(AppRadius.md)),
      child: Row(
        children: [
          const Icon(AppIcons.sealCheck, color: Color(0xFFB8860B)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(pending ? 'Official status requested' : 'Underground club', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5)),
                Text(
                  pending ? 'We\'ll confirm payment with you, then switch the club over.' : 'Meets up to 7 days ahead, 100 members. Go official for notifications, a gold badge and no limits.',
                  style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary, height: 1.35),
                ),
              ],
            ),
          ),
          if (!pending) ...[
            const SizedBox(width: 8),
            TextButton(onPressed: _busy ? null : _request, style: TextButton.styleFrom(visualDensity: VisualDensity.compact), child: const Text('Go official')),
          ],
        ],
      ),
    );
  }
}

/// Underground clubs: the garage. Officers set it; members get pinged when a
/// clubmate who shares location pulls up within 200 m.
class ClubGarageSection extends ConsumerWidget {
  const ClubGarageSection({super.key, required this.club, required this.isManager});
  final Club club;
  final bool isManager;

  Future<void> _set(BuildContext context, WidgetRef ref) async {
    final ctrl = TextEditingController(text: club.garageName ?? '');
    double? lat = club.garageLat, lng = club.garageLng;
    final here = ref.read(userLocationProvider).value;
    final ok = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(20, 0, 20, 16 + MediaQuery.viewInsetsOf(ctx).bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Club garage', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text('Where the crew hangs out. Members who share location ping everyone when they arrive.', style: TextStyle(fontSize: 13, color: AppColors.textSecondary, height: 1.4)),
            const SizedBox(height: 14),
            PlaceSearchField(
              controller: ctrl,
              label: 'Garage',
              hint: 'Search a workshop, carpark or mamak',
              icon: AppIcons.garage,
              near: here == null ? null : (here.latitude, here.longitude),
              onPicked: (d) {
                ctrl.text = d.name;
                lat = d.lat;
                lng = d.lng;
              },
            ),
            const SizedBox(height: 12),
            PrimaryButton(label: 'Save garage', onPressed: () => Navigator.pop(ctx, true)),
          ],
        ),
      ),
    );
    if (ok != true || !context.mounted) return;
    if (lat == null || lng == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Pick the garage from the search list.')));
      return;
    }
    try {
      await ref.read(communityActionsProvider).setClubGarage(club.id, ctrl.text.trim(), lat!, lng!);
    } catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e))));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final has = club.garageLat != null && club.garageLng != null;
    if (!has && !isManager) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      child: Container(
        decoration: BoxDecoration(color: AppColors.surfaceGray, borderRadius: BorderRadius.circular(AppRadius.md)),
        child: ListTile(
          leading: const Icon(AppIcons.garage),
          title: Text(has ? (club.garageName ?? 'Club garage') : 'Set a club garage', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
          subtitle: Text(
            has ? 'Everyone gets a ping when a clubmate pulls up here.' : 'Members get pinged when a clubmate pulls up.',
            style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
          ),
          trailing: isManager
              ? TextButton(style: TextButton.styleFrom(visualDensity: VisualDensity.compact), onPressed: () => _set(context, ref), child: Text(has ? 'Change' : 'Set'))
              : IconButton(icon: const Icon(AppIcons.navigationArrow, size: 18), onPressed: () => showDirectionsSheet(context, lat: club.garageLat!, lng: club.garageLng!, label: club.garageName)),
        ),
      ),
    );
  }
}

/// Who shows up: top members over the last 90 days.
class ClubLeaderboard extends ConsumerWidget {
  const ClubLeaderboard({super.key, required this.clubId});
  final String clubId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rows = ref.watch(clubLeaderboardProvider(clubId)).value ?? const <ClubLeader>[];
    final active = rows.where((r) => r.score > 0).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Row(
            children: [
              Icon(AppIcons.trophy, size: 14, color: AppColors.textSecondary),
              const SizedBox(width: 6),
              Text('MOST ACTIVE · 90 DAYS', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 1, color: AppColors.textSecondary)),
            ],
          ),
        ),
        if (active.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text('Nobody on the board yet. Check-ins at club meets count most, then posts and moments.', style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
          )
        else
          for (var i = 0; i < active.length && i < 5; i++)
            ListTile(
              dense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 16),
              leading: SizedBox(
                width: 60,
                child: Row(
                  children: [
                    SizedBox(width: 22, child: Text('${i + 1}', style: TextStyle(fontFamily: AppFonts.display, fontSize: 20, fontWeight: FontWeight.w700, color: i == 0 ? const Color(0xFFB8860B) : AppColors.textSecondary))),
                    UserAvatar(url: active[i].avatarUrl, name: active[i].displayName ?? active[i].username, size: 32),
                  ],
                ),
              ),
              title: Text(active[i].displayName ?? active[i].username ?? '', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
              subtitle: Text(
                [
                  if (active[i].checkins > 0) '${active[i].checkins} check-in${active[i].checkins == 1 ? '' : 's'}',
                  if (active[i].joins > 0) '${active[i].joins} joined',
                  if (active[i].posts > 0) '${active[i].posts} post${active[i].posts == 1 ? '' : 's'}',
                  if (active[i].moments > 0) '${active[i].moments} moment${active[i].moments == 1 ? '' : 's'}',
                ].join(' · '),
                style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
              ),
              trailing: Text('${active[i].score}', style: const TextStyle(fontFamily: AppFonts.display, fontSize: 18, fontWeight: FontWeight.w700)),
              onTap: () => context.push(Routes.profile(active[i].userId)),
            ),
      ],
    );
  }
}
