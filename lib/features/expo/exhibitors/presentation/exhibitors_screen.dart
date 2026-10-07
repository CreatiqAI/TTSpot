import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/pop_or_home.dart';
import '../../../../core/theme/app_icons.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/titi.dart';
import '../../../../core/utils/friendly_error.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../events/application/event_providers.dart';
import '../../../floorplan/presentation/floorplan_screen.dart';
import '../application/exhibitors_providers.dart';
import '../domain/exhibitor.dart';
import 'exhibitor_sheet.dart';
import 'exhibitor_widgets.dart';

/// Members: search exhibitors, open one, show it on the floor plan.
class ExhibitorsScreen extends ConsumerWidget {
  const ExhibitorsScreen({super.key, required this.eventId});
  final String eventId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final title = ref.watch(eventDetailProvider(eventId)).value?.event.title;
    final count = ref.watch(eventExhibitorsProvider(eventId)).value?.length;
    return HomeOnBack(
      child: Scaffold(
        appBar: AppBar(
          leading: const AppBackButton(),
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(count == null || count == 0 ? 'Exhibitors' : 'Exhibitors · $count'),
              if (title != null) Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: AppColors.textSecondary, fontWeight: FontWeight.w500)),
            ],
          ),
          actions: [
            IconButton(
              tooltip: 'Floor plan',
              icon: const Icon(AppIcons.mapTrifold),
              onPressed: () => context.push(FloorplanRoutes.view(eventId)),
            ),
          ],
        ),
        body: RefreshIndicator(
          onRefresh: () => ref.refresh(eventExhibitorsProvider(eventId).future),
          child: CustomScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            slivers: [ExhibitorsBody(eventId: eventId)],
          ),
        ),
      ),
    );
  }
}

/// The "Partners" chip (categories are plain strings).
const _partnersChip = '\u0000partners';

/// The exhibitors list: search, category chips, rows. Slivers, for a
/// CustomScrollView: the Exhibitors screen and the event page's Exhibitors
/// tab.
class ExhibitorsBody extends ConsumerStatefulWidget {
  const ExhibitorsBody({super.key, required this.eventId});
  final String eventId;

  @override
  ConsumerState<ExhibitorsBody> createState() => _ExhibitorsBodyState();
}

class _ExhibitorsBodyState extends ConsumerState<ExhibitorsBody> {
  final _q = TextEditingController();
  String _query = '';
  String? _chip;

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  List<Exhibitor> _filtered(List<Exhibitor> all) {
    final chip = _chip;
    final query = _query;
    return [
      for (final e in all)
        if ((chip == null || (chip == _partnersChip ? e.isPartner : e.category == chip)) && e.matches(query)) e,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(eventExhibitorsProvider(widget.eventId));
    return async.when(
      skipLoadingOnRefresh: true,
      skipLoadingOnReload: true,
      loading: () => const SliverToBoxAdapter(
        child: Padding(padding: EdgeInsets.symmetric(vertical: 48), child: Center(child: CircularProgressIndicator(strokeWidth: 2))),
      ),
      error: (e, _) => SliverToBoxAdapter(
        child: EmptyState(
          icon: AppIcons.wifiSlash,
          title: "Couldn't load exhibitors",
          subtitle: friendlyError(e),
          actionLabel: 'Try again',
          onAction: () => ref.invalidate(eventExhibitorsProvider(widget.eventId)),
        ),
      ),
      data: (all) {
        if (all.isEmpty) {
          return const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.only(top: 24),
              child: EmptyState(titi: TitiPose.binoculars, icon: AppIcons.storefront, title: 'No exhibitors yet', subtitle: 'Check back closer to the show.'),
            ),
          );
        }
        final categories = exhibitorCategories(all);
        final hasPartners = all.any((e) => e.isPartner);
        final list = _filtered(all);
        return SliverMainAxisGroup(
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
                child: TextField(
                  controller: _q,
                  textInputAction: TextInputAction.search,
                  onChanged: (v) => setState(() => _query = v),
                  decoration: InputDecoration(
                    hintText: 'Name, booth, category or country',
                    prefixIcon: const Icon(AppIcons.magnifyingGlass, size: 20),
                    isDense: true,
                    suffixIcon: _query.isEmpty
                        ? null
                        : IconButton(
                            tooltip: 'Clear',
                            icon: const Icon(AppIcons.x, size: 18),
                            onPressed: () => setState(() {
                              _q.clear();
                              _query = '';
                            }),
                          ),
                  ),
                ),
              ),
            ),
            if (hasPartners || categories.length > 1)
              SliverToBoxAdapter(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.fromLTRB(16, 6, 10, 6),
                  child: Row(
                    children: [
                      _Chip(label: 'All', on: _chip == null, onTap: () => setState(() => _chip = null)),
                      if (hasPartners)
                        _Chip(
                          label: 'Partners',
                          icon: AppIcons.sealCheck,
                          gold: true,
                          on: _chip == _partnersChip,
                          onTap: () => setState(() => _chip = _chip == _partnersChip ? null : _partnersChip),
                        ),
                      for (final c in categories) _Chip(label: c, on: _chip == c, onTap: () => setState(() => _chip = _chip == c ? null : c)),
                    ],
                  ),
                ),
              ),
            if (list.isEmpty)
              const SliverToBoxAdapter(child: EmptyState(titi: TitiPose.binoculars, title: 'No match', subtitle: 'Try a booth code like A019.'))
            else
              SliverPadding(
                padding: const EdgeInsets.only(bottom: 24),
                sliver: SliverList.builder(
                  itemCount: list.length,
                  itemBuilder: (_, i) => ExhibitorRow(
                    key: ValueKey(list[i].id),
                    exhibitor: list[i],
                    onTap: () => showExhibitorSheet(context, widget.eventId, list[i].id),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// One exhibitor in a list: logo, name, booths and category, partner tag.
class ExhibitorRow extends StatelessWidget {
  const ExhibitorRow({super.key, required this.exhibitor, required this.onTap, this.trailing});
  final Exhibitor exhibitor;
  final VoidCallback onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final e = exhibitor;
    final sub = [if (e.booths.isNotEmpty) e.boothsLabel, if (e.category != null) e.category!].join(' · ');
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 12, 10),
        child: Row(
          children: [
            ExhibitorLogo(exhibitor: e, size: 44),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(child: Text(e.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15))),
                      if (e.isPartner) ...[const SizedBox(width: 6), const PartnerTag()],
                    ],
                  ),
                  if (sub.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
                  ],
                ],
              ),
            ),
            trailing ?? Icon(AppIcons.caretRight, size: 18, color: AppColors.textMuted),
          ],
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.on, required this.onTap, this.icon, this.gold = false});
  final String label;
  final bool on;
  final VoidCallback onTap;
  final IconData? icon;
  final bool gold;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(right: 6),
        child: Material(
          color: on ? AppColors.textPrimary : (gold ? kPartnerGold.withValues(alpha: 0.16) : AppColors.surfaceGray),
          borderRadius: BorderRadius.circular(999),
          child: InkWell(
            borderRadius: BorderRadius.circular(999),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (icon != null) ...[Icon(icon, size: 15, color: on ? AppColors.onInk : (gold ? kPartnerGoldDeep : AppColors.textPrimary)), const SizedBox(width: 5)],
                  Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: on ? AppColors.onInk : (gold ? kPartnerGoldDeep : AppColors.textPrimary))),
                ],
              ),
            ),
          ),
        ),
      );
}
