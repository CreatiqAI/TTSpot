import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../../core/supabase/supabase_client.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/friendly_error.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/user_avatar.dart';
import '../../profile/presentation/garage/garage_images.dart' show garageToyProvider;
import '../../profile/presentation/widgets/car_picker_sheet.dart' show CarThumb;
import '../application/club_members_providers.dart';
import '../application/community_providers.dart' show clubProvider;
import '../domain/club_member.dart';
import 'widgets/club_name_tag.dart';
import 'widgets/club_tier_widgets.dart' show clubRoleLabel;

/// A club's members, all of them, with their cars: the club page's "View
/// all". Officers first (President, Vice President, Secretary), then in the
/// order they joined. Each row: avatar, name and the club tag they wear,
/// their role, their default car (toy model, else the photo or body-type
/// art, plus make and model). Tap: their profile. A search box above
/// [kClubMembersSearchFrom] members (name, handle or car).
///
/// Who can see it: anyone signed in, like the strip on the club page
/// (`club_members_list`, migration 0111), minus people in a block with me.
class ClubMembersScreen extends ConsumerStatefulWidget {
  const ClubMembersScreen({super.key, required this.clubId});
  final String clubId;

  @override
  ConsumerState<ClubMembersScreen> createState() => _ClubMembersScreenState();
}

class _ClubMembersScreenState extends ConsumerState<ClubMembersScreen> {
  final _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    ref.invalidate(clubMembersListProvider(widget.clubId));
    try {
      await ref.read(clubMembersListProvider(widget.clubId).future);
    } catch (_) {} // the page shows the error
  }

  void _clear() {
    _search.clear();
    FocusScope.of(context).unfocus();
    setState(() => _query = '');
  }

  @override
  Widget build(BuildContext context) {
    final club = ref.watch(clubProvider(widget.clubId)).value;
    final members = ref.watch(clubMembersListProvider(widget.clubId));
    final me = ref.watch(currentUserIdProvider);
    final all = members.value ?? const <ClubMemberEntry>[];
    final q = _query.trim().toLowerCase();
    final shown = all.where((m) => m.matches(q)).toList();
    final searchable = all.length > kClubMembersSearchFrom;

    final Widget body;
    if (members.isLoading && !members.hasValue) {
      body = const Center(child: CircularProgressIndicator(strokeWidth: 2));
    } else if (members.hasError && !members.hasValue) {
      body = Center(
        child: EmptyState(icon: AppIcons.wifiSlash, title: 'Couldn\'t load the members', subtitle: friendlyError(members.error!), actionLabel: 'Retry', onAction: _reload),
      );
    } else {
      body = RefreshIndicator(
        onRefresh: _reload,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          slivers: [
            if (searchable)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                  child: _SearchBox(controller: _search, onChanged: (v) => setState(() => _query = v), onClear: _clear),
                ),
              ),
            if (all.isEmpty)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: Center(child: EmptyState(icon: AppIcons.usersThree, title: 'No members yet', subtitle: 'People who join show up here with their cars.')),
              )
            else if (shown.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: EmptyState(icon: AppIcons.magnifyingGlass, title: 'Nobody matches "${_query.trim()}"', subtitle: 'Try a name or a car.', actionLabel: 'Clear search', onAction: _clear),
                ),
              )
            else
              SliverList.builder(
                itemCount: shown.length,
                itemBuilder: (_, i) => ClubMemberRow(entry: shown[i], isMe: shown[i].userId == me),
              ),
            SliverToBoxAdapter(child: SizedBox(height: MediaQuery.paddingOf(context).bottom + 24)),
          ],
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(AppIcons.arrowLeft), onPressed: () => context.pop()),
        title: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(members.hasValue ? 'Members · ${all.length}' : 'Members', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
            if (club != null)
              Text(
                club.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                // The club's name stays a subtitle even with large text.
                textScaler: MediaQuery.textScalerOf(context).clamp(maxScaleFactor: 1.15),
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: AppColors.textSecondary),
              ),
          ],
        ),
      ),
      body: body,
    );
  }
}

/// One member: avatar | name + tag, role, car | the car's thumbnail.
class ClubMemberRow extends StatelessWidget {
  const ClubMemberRow({super.key, required this.entry, this.isMe = false});
  final ClubMemberEntry entry;
  final bool isMe;

  @override
  Widget build(BuildContext context) {
    final m = entry;
    final car = m.carLine;
    return InkWell(
      key: Key('club-member-${m.userId}'),
      onTap: () => context.push(Routes.profile(m.userId)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
        child: Row(
          children: [
            UserAvatar(url: m.avatarUrl, name: m.name, seed: m.userId, size: 46),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          isMe ? '${m.name} (you)' : m.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                        ),
                      ),
                      if (m.clubTag != null) ...[
                        const SizedBox(width: 6),
                        ClubNameTag(tag: m.clubTag, maxWidth: 104),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  _RoleLine(role: m.role),
                  if (car != null) ...[
                    const SizedBox(height: 1),
                    Text(car, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary)),
                  ],
                ],
              ),
            ),
            if (m.car != null) ...[
              const SizedBox(width: 10),
              MemberCarThumb(entry: m),
            ],
          ],
        ),
      ),
    );
  }
}

/// "President" with a crown, "Vice President" / "Secretary" with a shield
/// (the club page's strip marks them the same way), or "Member".
class _RoleLine extends StatelessWidget {
  const _RoleLine({required this.role});
  final String role;

  @override
  Widget build(BuildContext context) {
    final officer = role == 'owner' || role == 'vp' || role == 'secretary';
    final color = role == 'owner' ? officialGold() : officer ? AppColors.textPrimary : AppColors.textSecondary;
    return Row(
      children: [
        if (officer) ...[
          Icon(role == 'owner' ? AppIcons.crown : AppIcons.shieldCheck, size: 13, color: color),
          const SizedBox(width: 4),
        ],
        Flexible(
          child: Text(
            clubRoleLabel(role),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 12.5, fontWeight: officer ? FontWeight.w700 : FontWeight.w500, color: color),
          ),
        ),
      ],
    );
  }
}

/// Their default car, small: the die-cast toy when it has one (no frame, it
/// sits on the page), else the cover photo or the body-type art, rounded.
class MemberCarThumb extends StatelessWidget {
  const MemberCarThumb({super.key, required this.entry});
  final ClubMemberEntry entry;

  static const width = 72.0;
  static const height = 42.0;

  @override
  Widget build(BuildContext context) {
    final car = entry.car!;
    final photo = CarThumb(url: car.photoCover ?? car.portraitUrl, bodyStyle: car.bodyStyle, width: 64, height: height, radius: 8);
    final toy = garageToyProvider(car);
    final cache = (width * MediaQuery.devicePixelRatioOf(context)).round();
    return Semantics(
      label: '${car.make} ${car.model}',
      image: true,
      excludeSemantics: true,
      child: SizedBox(
        width: width,
        height: height,
        child: Center(
          child: toy == null
              ? photo
              : Image(
                  key: const ValueKey('member-car-toy'),
                  image: ResizeImage(toy, width: cache, policy: ResizeImagePolicy.fit),
                  width: width,
                  height: height,
                  fit: BoxFit.contain,
                  filterQuality: FilterQuality.medium,
                  gaplessPlayback: true,
                  errorBuilder: (_, _, _) => photo,
                ),
        ),
      ),
    );
  }
}

/// Narrows the list by name, handle or car. Local: no extra queries.
class _SearchBox extends StatelessWidget {
  const _SearchBox({required this.controller, required this.onChanged, required this.onClear});
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) => TextField(
        key: const Key('club-members-search'),
        controller: controller,
        onChanged: onChanged,
        textInputAction: TextInputAction.search,
        style: TextStyle(fontSize: 14.5, color: AppColors.textPrimary),
        decoration: InputDecoration(
          isDense: true,
          hintText: 'Search members or cars',
          prefixIcon: Icon(AppIcons.magnifyingGlass, size: 18, color: AppColors.textSecondary),
          prefixIconConstraints: const BoxConstraints(minWidth: 40, minHeight: 38),
          suffixIcon: ValueListenableBuilder<TextEditingValue>(
            valueListenable: controller,
            builder: (_, v, _) => v.text.isEmpty
                ? const SizedBox.shrink()
                : IconButton(tooltip: 'Clear', icon: Icon(AppIcons.xCircle, size: 18, color: AppColors.textSecondary), onPressed: onClear),
          ),
          contentPadding: const EdgeInsets.symmetric(vertical: 10),
          filled: true,
          fillColor: AppColors.surfaceGray,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.md), borderSide: BorderSide.none),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.md), borderSide: BorderSide.none),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.md), borderSide: BorderSide.none),
        ),
      );
}
