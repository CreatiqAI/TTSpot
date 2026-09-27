import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../../core/supabase/supabase_client.dart';
import '../../../core/theme/app_art.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/dates.dart';
import '../../../core/utils/friendly_error.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/user_avatar.dart';
import '../../points/application/points_providers.dart';
import '../application/cards_providers.dart';
import '../domain/cards.dart';
import 'widgets/card_face.dart';

/// Cards: my collection and boxes · trades with friends · prizes that cost cards.
class CardsScreen extends ConsumerStatefulWidget {
  const CardsScreen({super.key, this.initialTab = 0});
  final int initialTab;

  @override
  ConsumerState<CardsScreen> createState() => _CardsScreenState();
}

class _CardsScreenState extends ConsumerState<CardsScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 3, vsync: this, initialIndex: widget.initialTab.clamp(0, 2));

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final incoming = ref.watch(incomingTradeCountProvider);
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(AppIcons.arrowLeft), onPressed: () => context.pop()),
        title: const Text('Cards'),
        actions: [IconButton(tooltip: 'How it works', icon: const Icon(AppIcons.question), onPressed: () => _howItWorks(context))],
        bottom: TabBar(
          controller: _tabs,
          labelColor: AppColors.textPrimary,
          unselectedLabelColor: AppColors.textSecondary,
          indicatorColor: AppColors.textPrimary,
          indicatorSize: TabBarIndicatorSize.tab,
          indicatorWeight: 1.5,
          dividerColor: AppColors.border,
          labelStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          tabs: [
            const Tab(text: 'Collection'),
            Tab(text: incoming == 0 ? 'Trades' : 'Trades · $incoming'),
            const Tab(text: 'Prizes'),
          ],
        ),
      ),
      body: TabBarView(controller: _tabs, children: const [_CollectionTab(), _TradesTab(), _PrizesTab()]),
    );
  }

  void _howItWorks(BuildContext context) {
    final s = ref.read(cardSettingsProvider).value ?? const CardSettings();
    showModalBottomSheet<void>(
      useRootNavigator: true,
      context: context,
      showDragHandle: true,
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('How cards work', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
              const SizedBox(height: 12),
              _rule(AppArt.gift, 'Every new member gets one blind box. More boxes cost ${s.boxCost} points.'),
              _rule(AppArt.sparkles, 'Each box holds one of 7 cards. Odds: ${s.pct(CardRarity.common).round()}% common · ${s.pct(CardRarity.rare).round()}% rare · ${s.pct(CardRarity.legendary).round()}% legendary.'),
              _rule(AppArt.handshake, 'Trade with friends, up to ${s.tradeMax} cards a side. Cards never expire.'),
              _rule(AppArt.trophy, 'Spend cards on prizes. Spent cards leave your collection, so the full set is worth keeping until you want the big one.'),
            ],
          ),
        ),
      ),
    );
  }

  Widget _rule(String art, String text) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ArtIcon(art, size: 28),
            const SizedBox(width: 12),
            Expanded(child: Text(text, style: const TextStyle(fontSize: 14, height: 1.4))),
          ],
        ),
      );
}

// ------------------------------------------------------------ collection ---

class _CollectionTab extends ConsumerWidget {
  const _CollectionTab();

  Future<void> _buy(BuildContext context, WidgetRef ref, CardSettings s, int balance) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Spend ${s.boxCost} points?'),
        content: Text('One sealed blind box. You have $balance points.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Buy a box')),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    try {
      final id = await ref.read(cardsActionsProvider).buyBox();
      if (context.mounted) context.push(Routes.openBox(id));
    } catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e))));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final collection = ref.watch(myCollectionProvider);
    final sealed = ref.watch(sealedBoxesProvider);
    final settings = ref.watch(cardSettingsProvider).value ?? const CardSettings();
    final balance = ref.watch(pointsBalanceProvider).value ?? 0;
    final canBuy = balance >= settings.boxCost;

    return RefreshIndicator(
      onRefresh: () async {
        ref.read(cardsActionsProvider).refreshCollection();
        ref.invalidate(cardTypesProvider);
        ref.invalidate(cardSettingsProvider);
        await ref.read(myCollectionProvider.future);
      },
      child: collection.when(
        loading: () => const Center(child: CircularProgressIndicator(strokeWidth: 2)),
        error: (e, _) => Center(child: Text(friendlyError(e))),
        data: (col) => ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
          children: [
            // ---- boxes
            if (sealed.isNotEmpty)
              _BoxBanner(
                count: sealed.length,
                onOpen: () => context.push(Routes.openBox(sealed.first.id)),
              )
            else
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(border: Border.all(color: AppColors.border), borderRadius: BorderRadius.circular(AppRadius.lg)),
                child: Row(
                  children: [
                    const ArtIcon(AppArt.gift, size: 36),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('No sealed boxes', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                          Text('A box is ${settings.boxCost} points · you have $balance', style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary)),
                        ],
                      ),
                    ),
                    FilledButton(
                      style: FilledButton.styleFrom(visualDensity: VisualDensity.compact, minimumSize: const Size(0, 36), padding: const EdgeInsets.symmetric(horizontal: 14)),
                      onPressed: canBuy ? () => _buy(context, ref, settings, balance) : () => context.push(Routes.points),
                      child: Text(canBuy ? 'Buy a box' : 'Earn points'),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 16),
            // ---- tally
            Row(
              children: [
                _Tally(label: 'Collected', value: '${col.distinctOwned}/${col.setSize}', accent: col.hasFullSet),
                const SizedBox(width: 8),
                _Tally(label: 'Cards', value: '${col.heldCount}'),
                const SizedBox(width: 8),
                _Tally(label: 'Rare', value: '${col.heldOfRarity(CardRarity.rare)}', color: CardRarity.rare.color),
                const SizedBox(width: 8),
                _Tally(label: 'Legendary', value: '${col.heldOfRarity(CardRarity.legendary)}', color: CardRarity.legendary.color),
              ],
            ),
            if (col.hasFullSet)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Row(
                  children: [
                    const ArtIcon(AppArt.confetti, size: 20),
                    const SizedBox(width: 6),
                    Expanded(child: Text('Full set! Check the Prizes tab.', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.success))),
                  ],
                ),
              ),
            const SizedBox(height: 18),
            // ---- grid
            LayoutBuilder(
              builder: (_, c) {
                const gap = 12.0;
                final w = (c.maxWidth - gap * 2) / 3;
                return Wrap(
                  spacing: gap,
                  runSpacing: gap,
                  children: [
                    for (final t in col.types.where((t) => t.active))
                      GestureDetector(
                        onTap: () => _showCard(context, ref, t, col),
                        child: CardFace(card: t, width: w, count: col.count(t.id), locked: !col.owns(t.id)),
                      ),
                  ],
                );
              },
            ),
            const SizedBox(height: 18),
            Text(
              'Drop odds: ${settings.pct(CardRarity.common).round()}% common · ${settings.pct(CardRarity.rare).round()}% rare · ${settings.pct(CardRarity.legendary).round()}% legendary. Cards never expire.',
              style: TextStyle(fontSize: 12, color: AppColors.textMuted, height: 1.4),
            ),
            if (sealed.isNotEmpty && canBuy)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: TextButton(onPressed: () => _buy(context, ref, settings, balance), child: Text('Buy another box for ${settings.boxCost} points')),
              ),
          ],
        ),
      ),
    );
  }

  void _showCard(BuildContext context, WidgetRef ref, CardType t, CardCollection col) {
    final owned = col.owns(t.id);
    showModalBottomSheet<void>(
      useRootNavigator: true,
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 210,
                height: 210 / kCardAspect,
                child: owned ? TiltCard(child: CardFace(card: t, width: 210)) : CardFace(card: t, width: 210, locked: true),
              ),
              const SizedBox(height: 18),
              RarityPill(rarity: t.rarity, scale: 1.2),
              const SizedBox(height: 8),
              Text(t.name, style: const TextStyle(fontFamily: AppFonts.display, fontSize: 28, fontWeight: FontWeight.w800, height: 1)),
              if (t.description != null) ...[
                const SizedBox(height: 6),
                Text(t.description!, textAlign: TextAlign.center, style: TextStyle(fontSize: 13.5, color: AppColors.textSecondary, height: 1.4)),
              ],
              const SizedBox(height: 8),
              Text(
                owned ? 'You have ${col.count(t.id)}' : 'Not in your collection yet. Open a box or ask a friend.',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: owned ? AppColors.textPrimary : AppColors.textSecondary),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () {
                    Navigator.pop(ctx);
                    context.push(Routes.newTrade);
                  },
                  icon: const Icon(AppIcons.handshake, size: 18),
                  label: Text(owned ? 'Trade with a friend' : 'Ask a friend for one'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BoxBanner extends StatefulWidget {
  const _BoxBanner({required this.count, required this.onOpen});
  final int count;
  final VoidCallback onOpen;

  @override
  State<_BoxBanner> createState() => _BoxBannerState();
}

class _BoxBannerState extends State<_BoxBanner> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 2200))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onOpen,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
        decoration: BoxDecoration(
          gradient: const LinearGradient(colors: [Color(0xFFFF3B3B), AppColors.brandDeep], begin: Alignment.topLeft, end: Alignment.bottomRight),
          borderRadius: BorderRadius.circular(AppRadius.lg),
          boxShadow: [BoxShadow(color: AppColors.brand.withValues(alpha: 0.3), blurRadius: 18, offset: const Offset(0, 8))],
        ),
        child: Row(
          children: [
            AnimatedBuilder(
              animation: _c,
              builder: (_, child) {
                final t = _c.value;
                final wiggle = t < 0.25 ? (0.5 - (t * 4 - 0.5).abs()) * 0.5 : 0.0; // a quick shake, then rest
                final angle = (t * 40).floor().isEven ? wiggle * 0.5 : -wiggle * 0.5;
                return Transform.rotate(angle: angle, child: child);
              },
              child: const ArtIcon(AppArt.gift, size: 44),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(widget.count == 1 ? 'You have a blind box!' : 'You have ${widget.count} blind boxes!', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: Colors.white)),
                  const Text('Tap to open it. One of 7 cards is inside.', style: TextStyle(fontSize: 12.5, color: Colors.white70)),
                ],
              ),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.white, foregroundColor: AppColors.brand, visualDensity: VisualDensity.compact, minimumSize: const Size(0, 36), padding: const EdgeInsets.symmetric(horizontal: 14)),
              onPressed: widget.onOpen,
              child: const Text('Open'),
            ),
          ],
        ),
      ),
    );
  }
}

class _Tally extends StatelessWidget {
  const _Tally({required this.label, required this.value, this.color, this.accent = false});
  final String label;
  final String value;
  final Color? color;
  final bool accent;

  @override
  Widget build(BuildContext context) => Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: accent ? AppColors.success : AppColors.surfaceGray,
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          child: Column(
            children: [
              Text(value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, height: 1, color: accent ? Colors.white : (color ?? AppColors.textPrimary))),
              const SizedBox(height: 3),
              Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: accent ? Colors.white70 : AppColors.textSecondary)),
            ],
          ),
        ),
      );
}

// ---------------------------------------------------------------- trades ---

class _TradesTab extends ConsumerWidget {
  const _TradesTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final trades = ref.watch(myTradesProvider);
    final me = ref.watch(currentUserIdProvider);
    final types = ref.watch(cardTypesProvider).value ?? const <CardType>[];
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push(Routes.newTrade),
        backgroundColor: AppColors.textPrimary,
        foregroundColor: AppColors.onInk,
        icon: const Icon(AppIcons.handshake),
        label: const Text('New trade'),
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(myTradesProvider);
          await ref.read(myTradesProvider.future);
        },
        child: trades.when(
          loading: () => const Center(child: CircularProgressIndicator(strokeWidth: 2)),
          error: (e, _) => Center(child: Text(friendlyError(e))),
          data: (list) {
            if (list.isEmpty) {
              return LayoutBuilder(
                builder: (_, c) => SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  child: SizedBox(
                    height: c.maxHeight,
                    child: const EmptyState(art: AppArt.handshake, title: 'No trades yet', subtitle: 'Offer a friend some of your doubles for the card you are missing. Up to 9 cards a side.'),
                  ),
                ),
              );
            }
            final open = list.where((t) => t.status == TradeStatus.proposed).toList();
            final done = list.where((t) => t.status != TradeStatus.proposed).toList();
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
              children: [
                if (open.isNotEmpty) ...[
                  _Section('OPEN'),
                  for (final t in open) _TradeCard(t: t, me: me, types: types),
                ],
                if (done.isNotEmpty) ...[
                  _Section('HISTORY'),
                  for (final t in done) _TradeCard(t: t, me: me, types: types),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}

class _TradeCard extends ConsumerStatefulWidget {
  const _TradeCard({required this.t, required this.me, required this.types});
  final CardTrade t;
  final String? me;
  final List<CardType> types;

  @override
  ConsumerState<_TradeCard> createState() => _TradeCardState();
}

class _TradeCardState extends ConsumerState<_TradeCard> {
  bool _busy = false;

  Future<void> _run(Future<void> Function() f, {String? done}) async {
    setState(() => _busy = true);
    try {
      await f();
      if (mounted && done != null) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(done)));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.t;
    final me = widget.me;
    final incoming = t.isIncoming(me);
    final open = t.status == TradeStatus.proposed;
    // "I give" / "I get" from my side of the table
    final iGive = incoming ? t.request : t.offer;
    final iGet = incoming ? t.offer : t.request;
    final statusColor = switch (t.status) {
      TradeStatus.accepted => AppColors.success,
      TradeStatus.proposed => AppColors.warnColor,
      _ => AppColors.textSecondary,
    };
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(border: Border.all(color: AppColors.border), borderRadius: BorderRadius.circular(AppRadius.lg)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              GestureDetector(
                onTap: () => context.push(Routes.profile(t.otherId(me))),
                child: UserAvatar(url: t.otherAvatar(me), name: t.otherName(me), size: 36),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(incoming ? '${t.otherName(me)} offers you a trade' : 'Your offer to ${t.otherName(me)}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                    Text(timeAgo(t.decidedAt ?? t.createdAt), style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                  ],
                ),
              ),
              Text(t.status.label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: statusColor)),
            ],
          ),
          if (t.message != null) ...[
            const SizedBox(height: 8),
            Text('“${t.message}”', style: TextStyle(fontSize: 13, fontStyle: FontStyle.italic, color: AppColors.textSecondary)),
          ],
          const SizedBox(height: 12),
          _Side(label: 'YOU GIVE', items: iGive, types: widget.types),
          const SizedBox(height: 8),
          _Side(label: 'YOU GET', items: iGet, types: widget.types),
          if (open) ...[
            const SizedBox(height: 12),
            if (incoming)
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _busy ? null : () => _run(() => ref.read(cardsActionsProvider).decideTrade(t.id, accept: false)),
                      child: const Text('Decline'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton(
                      onPressed: _busy ? null : () => _run(() => ref.read(cardsActionsProvider).decideTrade(t.id, accept: true), done: 'Trade done. The cards are in your collection.'),
                      child: const Text('Accept'),
                    ),
                  ),
                ],
              )
            else
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: _busy ? null : () => _run(() => ref.read(cardsActionsProvider).cancelTrade(t.id)),
                  child: const Text('Cancel offer'),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

/// One side of a trade: tiny card faces, grouped.
class _Side extends StatelessWidget {
  const _Side({required this.label, required this.items, required this.types});
  final String label;
  final List<TradeItem> items;
  final List<CardType> types;

  @override
  Widget build(BuildContext context) {
    final counts = <String, int>{};
    for (final i in items) {
      counts[i.cardId] = (counts[i.cardId] ?? 0) + 1;
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(width: 64, child: Padding(padding: const EdgeInsets.only(top: 4), child: Text(label, style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, letterSpacing: 1, color: AppColors.textSecondary)))),
        Expanded(
          child: items.isEmpty
              ? Text('nothing', style: TextStyle(fontSize: 13, color: AppColors.textMuted))
              : Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final e in counts.entries)
                      if (types.where((t) => t.id == e.key).firstOrNull case final t?) CardFace(card: t, width: 46, count: e.value),
                  ],
                ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------- prizes ---

class _PrizesTab extends ConsumerWidget {
  const _PrizesTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final shop = ref.watch(cardRewardShopProvider);
    final claims = ref.watch(myCardClaimsProvider).value ?? const <CardRewardClaim>[];
    final col = ref.watch(myCollectionProvider).value;
    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(cardRewardShopProvider);
        ref.invalidate(myCardClaimsProvider);
        await ref.read(cardRewardShopProvider.future);
      },
      child: shop.when(
        loading: () => const Center(child: CircularProgressIndicator(strokeWidth: 2)),
        error: (e, _) => Center(child: Text(friendlyError(e))),
        data: (list) => ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
          children: [
            if (list.isEmpty && claims.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 60),
                child: EmptyState(art: AppArt.trophy, title: 'No prizes yet', subtitle: 'Prizes that cost cards show up here. Keep collecting.'),
              ),
            for (final r in list) _RewardCard(r: r, col: col),
            if (claims.isNotEmpty) ...[
              _Section('MY PRIZES'),
              for (final c in claims) _ClaimTile(c: c),
            ],
          ],
        ),
      ),
    );
  }
}

class _RewardCard extends ConsumerStatefulWidget {
  const _RewardCard({required this.r, required this.col});
  final CardReward r;
  final CardCollection? col;

  @override
  ConsumerState<_RewardCard> createState() => _RewardCardState();
}

class _RewardCardState extends ConsumerState<_RewardCard> {
  bool _busy = false;

  Future<void> _claim() async {
    final r = widget.r;
    final n = (r.needFullSet ? (widget.col?.setSize ?? 7) : 0) + r.cardsNeeded;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Spend ${r.costLabel.toLowerCase()}?'),
        content: Text('$n card${n == 1 ? '' : 's'} leave your collection for "${r.title}". Doubles go first. You get a QR to show ${r.vendorId == null ? 'TT Spot staff' : r.byName}.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Claim')),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busy = true);
    try {
      final res = await ref.read(cardsActionsProvider).claimReward(r.id);
      if (mounted) context.push(Routes.cardPrizeQr(res.id));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.r;
    final held = r.myActiveClaim != null;
    final maxed = r.myClaims >= r.perUserLimit;
    final short = widget.col?.shortfall(r);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(border: Border.all(color: AppColors.border), borderRadius: BorderRadius.circular(AppRadius.lg)),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (r.imageUrl != null)
            AspectRatio(aspectRatio: 2.2, child: Image(image: CachedNetworkImageProvider(r.imageUrl!), fit: BoxFit.cover, errorBuilder: (_, _, _) => const SizedBox.shrink())),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                      child: r.vendorLogo == null
                          ? Container(width: 32, height: 32, color: AppColors.surfaceGray, child: Icon(r.vendorId == null ? AppIcons.trophy : AppIcons.storefront, size: 16, color: AppColors.textSecondary))
                          : Image(image: CachedNetworkImageProvider(r.vendorLogo!), width: 32, height: 32, fit: BoxFit.cover),
                    ),
                    const SizedBox(width: 10),
                    Expanded(child: Text(r.byName, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13))),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(color: r.needFullSet ? CardRarity.legendary.color : AppColors.textPrimary, borderRadius: BorderRadius.circular(999)),
                      child: Text(r.costLabel, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: r.needFullSet ? AppColors.ink : AppColors.onInk)),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(r.title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                if (r.description != null) Padding(padding: const EdgeInsets.only(top: 2), child: Text(r.description!, style: TextStyle(fontSize: 13, color: AppColors.textSecondary, height: 1.35))),
                const SizedBox(height: 4),
                Text(
                  [if (r.left != null) '${r.left} left', if (r.endsAt != null) 'till ${formatDate(r.endsAt!)}', if (r.terms != null) r.terms!].join(' · '),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: AppColors.textMuted),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: held
                      ? OutlinedButton.icon(
                          onPressed: () => context.push(Routes.cardPrizeQr(r.myActiveClaim!)),
                          icon: const Icon(AppIcons.qrCode, size: 18),
                          label: const Text('Show my prize QR'),
                        )
                      : FilledButton(
                          onPressed: _busy || maxed || short != null ? null : _claim,
                          child: Text(maxed ? 'Already claimed' : (short ?? 'Claim for ${r.costLabel.toLowerCase()}')),
                        ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ClaimTile extends StatelessWidget {
  const _ClaimTile({required this.c});
  final CardRewardClaim c;

  @override
  Widget build(BuildContext context) {
    final ready = c.status == ClaimState.active;
    return Opacity(
      opacity: ready ? 1 : 0.55,
      child: InkWell(
        onTap: ready ? () => context.push(Routes.cardPrizeQr(c.id)) : null,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        child: Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: ready ? AppColors.textPrimary : AppColors.surfaceGray, borderRadius: BorderRadius.circular(AppRadius.lg)),
          child: Row(
            children: [
              Icon(ready ? AppIcons.trophy : AppIcons.checkCircle, size: 26, color: ready ? AppColors.onInk : AppColors.textSecondary),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(c.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w700, color: ready ? AppColors.onInk : AppColors.textPrimary)),
                    Text(
                      ready ? '${c.byName} · valid till ${formatDate(c.expiresAt)}' : (c.redeemedAt != null ? 'Handed over ${timeAgo(c.redeemedAt!)}' : c.status.label),
                      style: TextStyle(fontSize: 12, color: ready ? AppColors.onInk.withValues(alpha: 0.7) : AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
              if (ready) Icon(AppIcons.qrCode, size: 24, color: AppColors.onInk),
            ],
          ),
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(0, 14, 0, 8),
        child: Text(text, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 1, color: AppColors.textSecondary)),
      );
}
