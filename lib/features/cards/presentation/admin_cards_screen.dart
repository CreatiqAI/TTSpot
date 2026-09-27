import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/dates.dart';
import '../../../core/utils/friendly_error.dart';
import '../../../core/widgets/user_avatar.dart';
import '../../admin/presentation/widgets/admin_widgets.dart';
import '../../vendors/application/vendors_providers.dart';
import '../application/cards_providers.dart';
import '../domain/cards.dart';
import 'widgets/card_face.dart';

/// Admin · Cards: numbers, odds and box price, the 7 designs (swap in the
/// final art by URL), prizes, claims waiting to be handed over, giveaways.
class AdminCardsScreen extends ConsumerWidget {
  const AdminCardsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stats = ref.watch(adminCardStatsProvider).value ?? const <String, dynamic>{};
    final settings = ref.watch(cardSettingsProvider).value ?? const CardSettings();
    final types = ref.watch(cardTypesProvider).value ?? const <CardType>[];
    final rewards = ref.watch(adminCardRewardsProvider).value ?? const <CardReward>[];
    final claims = ref.watch(adminCardClaimsProvider).value ?? const <AdminCardClaim>[];
    final byRarity = (stats['by_rarity'] as Map?)?.cast<String, dynamic>() ?? const {};

    Future<void> refresh() async {
      ref.invalidate(adminCardStatsProvider);
      ref.invalidate(cardSettingsProvider);
      ref.invalidate(cardTypesProvider);
      ref.invalidate(adminCardRewardsProvider);
      ref.invalidate(adminCardClaimsProvider);
      await ref.read(adminCardStatsProvider.future);
    }

    Future<void> run(Future<void> Function() f) async {
      try {
        await f();
      } catch (e) {
        if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e))));
      }
    }

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(AppIcons.arrowLeft), onPressed: () => context.pop()),
        title: const Text('Cards'),
        actions: [IconButton(tooltip: 'Refresh', icon: const Icon(AppIcons.arrowsClockwise), onPressed: refresh)],
      ),
      body: RefreshIndicator(
        onRefresh: refresh,
        child: ListView(
          padding: const EdgeInsets.only(bottom: 40),
          children: [
            const AdminHead('RIGHT NOW'),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  AdminStat(label: 'Sealed boxes', value: '${stats['boxes_sealed'] ?? '–'}', accent: true),
                  const SizedBox(width: 8),
                  AdminStat(label: 'Opened', value: '${stats['boxes_opened'] ?? '–'}', delta: '${stats['boxes_bought_30d'] ?? 0} bought · 30 d'),
                  const SizedBox(width: 8),
                  AdminStat(label: 'Collectors', value: '${stats['collectors'] ?? '–'}', delta: '${stats['cards_held'] ?? 0} cards held'),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  AdminStat(label: 'Open trades', value: '${stats['trades_open'] ?? '–'}', delta: '${stats['trades_30d'] ?? 0} done · 30 d'),
                  const SizedBox(width: 8),
                  AdminStat(label: 'Prizes waiting', value: '${stats['claims_waiting'] ?? '–'}', delta: '${stats['claims_30d'] ?? 0} claimed · 30 d'),
                  const SizedBox(width: 8),
                  AdminStat(label: 'Legendary out', value: '${byRarity['legendary'] ?? 0}', delta: '${byRarity['rare'] ?? 0} rare · ${byRarity['common'] ?? 0} common'),
                ],
              ),
            ),

            const AdminHead('SETTINGS'),
            ListTile(
              title: const Text('Drop odds', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14.5)),
              subtitle: Text('${settings.pct(CardRarity.common).round()}% common · ${settings.pct(CardRarity.rare).round()}% rare · ${settings.pct(CardRarity.legendary).round()}% legendary', style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary)),
              trailing: Icon(AppIcons.caretRight, size: 16, color: AppColors.textMuted),
              onTap: () => _editOdds(context, ref, settings),
            ),
            ListTile(
              title: const Text('Box price', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14.5)),
              subtitle: Text('${settings.boxCost} points', style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary)),
              trailing: Icon(AppIcons.caretRight, size: 16, color: AppColors.textMuted),
              onTap: () async {
                final v = await _askNumber(context, 'Box price (points)', settings.boxCost.toDouble());
                if (v != null) await run(() => ref.read(cardsActionsProvider).setBoxCost(v.round()));
              },
            ),
            ListTile(
              title: const Text('Give boxes to a member', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14.5)),
              subtitle: Text('Giveaways, make-goods, testing', style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary)),
              trailing: Icon(AppIcons.caretRight, size: 16, color: AppColors.textMuted),
              onTap: () => _grant(context, ref),
            ),

            AdminHead('CARD DESIGNS · ${types.length}'),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
              child: Text('Tap a card to rename it or paste the final art URL. Until an art URL is set, the app draws the tinted placeholder.', style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary, height: 1.4)),
            ),
            SizedBox(
              height: 150,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                children: [
                  for (final t in types)
                    Padding(
                      padding: const EdgeInsets.only(right: 10),
                      child: GestureDetector(
                        onTap: () => _editType(context, ref, t),
                        child: Opacity(opacity: t.active ? 1 : 0.4, child: CardFace(card: t, width: 92)),
                      ),
                    ),
                ],
              ),
            ),

            AdminHead('PRIZES · ${rewards.where((r) => r.active).length} live', action: 'Add', onAction: () => _editReward(context, ref, null)),
            if (rewards.isEmpty)
              Padding(padding: const EdgeInsets.fromLTRB(16, 0, 16, 8), child: Text('No prizes yet. Add one: a sticker pack for 3 commons, a cap for the full set…', style: TextStyle(fontSize: 13, color: AppColors.textSecondary))),
            for (final r in rewards)
              ListTile(
                dense: true,
                leading: Icon(r.vendorId == null ? AppIcons.trophy : AppIcons.storefront, color: r.active ? AppColors.textPrimary : AppColors.textMuted),
                title: Text(r.title, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: r.active ? AppColors.textPrimary : AppColors.textMuted)),
                subtitle: Text('${r.costLabel} · ${r.byName} · ${r.claimsCount} claimed, ${r.redeemedCount} handed over${r.stock == null ? '' : ' · ${r.left} left'}${r.active ? '' : ' · OFF'}', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                trailing: Icon(AppIcons.caretRight, size: 16, color: AppColors.textMuted),
                onTap: () => _editReward(context, ref, r),
              ),

            AdminHead('CLAIMS · ${claims.where((c) => c.status == ClaimState.active).length} waiting'),
            if (claims.isEmpty)
              Padding(padding: const EdgeInsets.fromLTRB(16, 0, 16, 8), child: Text('Nobody has claimed a prize yet.', style: TextStyle(fontSize: 13, color: AppColors.textSecondary))),
            for (final c in claims.take(30))
              ListTile(
                dense: true,
                leading: UserAvatar(url: c.avatarUrl, name: c.displayName ?? c.username, size: 36),
                title: Text('${c.displayName ?? '@${c.username}'} · ${c.title}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                subtitle: Text(
                  c.status == ClaimState.active ? 'Waiting · ${c.cardsUsed} cards · till ${formatDate(c.expiresAt)}' : '${c.status.label}${c.redeemedAt == null ? '' : ' ${timeAgo(c.redeemedAt!)}'}',
                  style: TextStyle(fontSize: 12, color: c.status == ClaimState.active ? AppColors.warnColor : AppColors.textSecondary),
                ),
                trailing: c.status == ClaimState.active
                    ? TextButton(
                        onPressed: () => context.push(Routes.cardPrizeRedeem(c.id, c.code)),
                        child: const Text('Hand over'),
                      )
                    : null,
              ),
          ],
        ),
      ),
    );
  }

  // ------------------------------------------------------------- dialogs ---

  Future<double?> _askNumber(BuildContext context, String label, double current) async {
    final ctrl = TextEditingController(text: current.toStringAsFixed(current % 1 == 0 ? 0 : 1));
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(label),
        content: TextField(controller: ctrl, keyboardType: const TextInputType.numberWithOptions(decimal: true), autofocus: true),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save')),
        ],
      ),
    );
    if (ok != true) return null;
    return double.tryParse(ctrl.text.trim());
  }

  Future<void> _editOdds(BuildContext context, WidgetRef ref, CardSettings s) async {
    final c = TextEditingController(text: '${s.common}');
    final r = TextEditingController(text: '${s.rare}');
    final l = TextEditingController(text: '${s.legendary}');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Drop odds (%)'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: c, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Common')),
            const SizedBox(height: 8),
            TextField(controller: r, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Rare')),
            const SizedBox(height: 8),
            TextField(controller: l, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Legendary')),
            const SizedBox(height: 8),
            Text('Shown to members as-is. Make them add up to 100.', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save')),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    final vc = num.tryParse(c.text.trim()), vr = num.tryParse(r.text.trim()), vl = num.tryParse(l.text.trim());
    if (vc == null || vr == null || vl == null || vc < 0 || vr < 0 || vl < 0 || vc + vr + vl <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Type three numbers, at least one above zero.')));
      return;
    }
    try {
      await ref.read(cardsActionsProvider).setOdds(common: vc, rare: vr, legendary: vl);
    } catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e))));
    }
  }

  Future<void> _grant(BuildContext context, WidgetRef ref) async {
    final u = TextEditingController();
    final n = TextEditingController(text: '1');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Give boxes'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: u, autofocus: true, decoration: const InputDecoration(labelText: 'Username', prefixText: '@')),
            const SizedBox(height: 8),
            TextField(controller: n, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'How many (1–50)')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Give')),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    try {
      final count = await ref.read(cardsActionsProvider).grantBoxes(username: u.text.trim().replaceFirst('@', ''), count: int.tryParse(n.text.trim()) ?? 1);
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Gave @${u.text.trim().replaceFirst('@', '')} $count box${count == 1 ? '' : 'es'}.')));
    } catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e))));
    }
  }

  Future<void> _editType(BuildContext context, WidgetRef ref, CardType t) async {
    final name = TextEditingController(text: t.name);
    final desc = TextEditingController(text: t.description ?? '');
    final art = TextEditingController(text: t.artUrl ?? '');
    final color = TextEditingController(text: t.hex);
    var rarity = t.rarity;
    var active = t.active;
    final ok = await showModalBottomSheet<bool>(
      useRootNavigator: true,
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.viewInsetsOf(ctx).bottom),
            child: ListView(
              shrinkWrap: true,
              children: [
                Text('Card ${t.number} · ${t.id}', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                const SizedBox(height: 12),
                TextField(controller: name, decoration: const InputDecoration(labelText: 'Name')),
                const SizedBox(height: 8),
                TextField(controller: desc, decoration: const InputDecoration(labelText: 'One line on the card')),
                const SizedBox(height: 8),
                TextField(controller: art, decoration: const InputDecoration(labelText: 'Art URL (63×88 portrait, PNG/JPG)')),
                const SizedBox(height: 8),
                TextField(controller: color, decoration: const InputDecoration(labelText: 'Placeholder tint (#RRGGBB)')),
                const SizedBox(height: 8),
                DropdownButtonFormField<CardRarity>(
                  initialValue: rarity,
                  decoration: const InputDecoration(labelText: 'Rarity'),
                  items: [for (final r in CardRarity.values) DropdownMenuItem(value: r, child: Text(r.label))],
                  onChanged: (v) => setSheet(() => rarity = v ?? rarity),
                ),
                SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('In the box pool'), value: active, onChanged: (v) => setSheet(() => active = v)),
                const SizedBox(height: 8),
                FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save')),
              ],
            ),
          ),
        ),
      ),
    );
    if (ok != true || !context.mounted) return;
    try {
      await ref.read(cardsActionsProvider).saveCardType(CardType(
        id: t.id,
        setId: t.setId,
        number: t.number,
        name: name.text.trim().isEmpty ? t.name : name.text.trim(),
        rarity: rarity,
        description: desc.text.trim().isEmpty ? null : desc.text.trim(),
        artUrl: art.text.trim().isEmpty ? null : art.text.trim(),
        color: CardType.parseHex(color.text.trim()) ?? t.color,
        active: active,
        sort: t.sort,
      ));
    } catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e))));
    }
  }

  Future<void> _editReward(BuildContext context, WidgetRef ref, CardReward? r) async {
    final partners = ref.read(partnersDirectoryProvider).value ?? const [];
    final title = TextEditingController(text: r?.title ?? '');
    final desc = TextEditingController(text: r?.description ?? '');
    final terms = TextEditingController(text: r?.terms ?? '');
    final image = TextEditingController(text: r?.imageUrl ?? '');
    final common = TextEditingController(text: '${r?.needCommon ?? 0}');
    final rare = TextEditingController(text: '${r?.needRare ?? 0}');
    final legendary = TextEditingController(text: '${r?.needLegendary ?? 0}');
    final stock = TextEditingController(text: r?.stock?.toString() ?? '');
    final perUser = TextEditingController(text: '${r?.perUserLimit ?? 1}');
    var fullSet = r?.needFullSet ?? false;
    var active = r?.active ?? true;
    String? vendorId = r?.vendorId;
    final ok = await showModalBottomSheet<bool>(
      useRootNavigator: true,
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.viewInsetsOf(ctx).bottom),
            child: ListView(
              shrinkWrap: true,
              children: [
                Text(r == null ? 'New prize' : 'Edit prize', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                const SizedBox(height: 12),
                TextField(controller: title, decoration: const InputDecoration(labelText: 'Title'), autofocus: r == null),
                const SizedBox(height: 8),
                TextField(controller: desc, decoration: const InputDecoration(labelText: 'Description')),
                const SizedBox(height: 8),
                TextField(controller: terms, decoration: const InputDecoration(labelText: 'Terms (optional)')),
                const SizedBox(height: 8),
                TextField(controller: image, decoration: const InputDecoration(labelText: 'Image URL (optional)')),
                const SizedBox(height: 8),
                DropdownButtonFormField<String?>(
                  initialValue: vendorId,
                  decoration: const InputDecoration(labelText: 'Handed out by'),
                  items: [
                    const DropdownMenuItem<String?>(value: null, child: Text('TT Spot (admin scans the QR)')),
                    for (final p in partners) DropdownMenuItem<String?>(value: p.id, child: Text(p.name)),
                  ],
                  onChanged: (v) => setSheet(() => vendorId = v),
                ),
                const SizedBox(height: 12),
                Text('COST', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 1, color: AppColors.textSecondary)),
                SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Full set (one of every card)'), value: fullSet, onChanged: (v) => setSheet(() => fullSet = v)),
                Row(
                  children: [
                    Expanded(child: TextField(controller: common, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: '+ common'))),
                    const SizedBox(width: 8),
                    Expanded(child: TextField(controller: rare, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: '+ rare'))),
                    const SizedBox(width: 8),
                    Expanded(child: TextField(controller: legendary, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: '+ legendary'))),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(child: TextField(controller: stock, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Stock (blank = unlimited)'))),
                    const SizedBox(width: 8),
                    Expanded(child: TextField(controller: perUser, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Per member'))),
                  ],
                ),
                SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Live'), value: active, onChanged: (v) => setSheet(() => active = v)),
                const SizedBox(height: 8),
                FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save')),
              ],
            ),
          ),
        ),
      ),
    );
    if (ok != true || !context.mounted) return;
    if (title.text.trim().length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Give the prize a title.')));
      return;
    }
    try {
      await ref.read(cardsActionsProvider).saveReward(
            id: r?.id,
            title: title.text.trim(),
            description: desc.text.trim().isEmpty ? null : desc.text.trim(),
            terms: terms.text.trim().isEmpty ? null : terms.text.trim(),
            imageUrl: image.text.trim().isEmpty ? null : image.text.trim(),
            vendorId: vendorId,
            common: int.tryParse(common.text.trim()) ?? 0,
            rare: int.tryParse(rare.text.trim()) ?? 0,
            legendary: int.tryParse(legendary.text.trim()) ?? 0,
            fullSet: fullSet,
            stock: int.tryParse(stock.text.trim()),
            perUser: int.tryParse(perUser.text.trim()) ?? 1,
            starts: r?.startsAt,
            ends: r?.endsAt,
            active: active,
          );
    } catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e))));
    }
  }
}
