import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_art.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/friendly_error.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/primary_button.dart';
import '../../../core/widgets/user_avatar.dart';
import '../../auth/domain/profile.dart';
import '../../friends/application/friends_providers.dart';
import '../../safety/application/wallet_pin.dart';
import '../application/cards_providers.dart';
import '../domain/cards.dart';
import 'widgets/card_face.dart';

/// Build a trade: pick a friend, choose what you give and what you want back
/// (up to 9 cards a side), add a note, send. They accept in their Trades tab.
class NewTradeScreen extends ConsumerStatefulWidget {
  const NewTradeScreen({super.key, this.withUserId});
  final String? withUserId;

  @override
  ConsumerState<NewTradeScreen> createState() => _NewTradeScreenState();
}

class _NewTradeScreenState extends ConsumerState<NewTradeScreen> {
  Profile? _friend;
  final _give = <String, int>{}; // cardId -> copies
  final _get = <String, int>{};
  final _message = TextEditingController();
  final _search = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _message.dispose();
    _search.dispose();
    super.dispose();
  }

  int get _giveTotal => _give.values.fold(0, (a, b) => a + b);
  int get _getTotal => _get.values.fold(0, (a, b) => a + b);

  Future<void> _send(CardCollection mine, List<UserCard> theirs, int max) async {
    final friend = _friend;
    if (friend == null) return;
    final offer = <String>[];
    for (final e in _give.entries) {
      offer.addAll(mine.copiesOf(e.key).take(e.value).map((c) => c.id));
    }
    final request = <String>[];
    for (final e in _get.entries) {
      final copies = theirs.where((c) => c.cardId == e.key).toList()..sort((a, b) => a.acquiredAt.compareTo(b.acquiredAt));
      request.addAll(copies.take(e.value).map((c) => c.id));
    }
    if (offer.isEmpty && request.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Pick at least one card.')));
      return;
    }
    setState(() => _busy = true);
    try {
      final message = _message.text.trim().isEmpty ? null : _message.text.trim();
      final sent = await runWithWalletPin(context, ref, () => ref.read(cardsActionsProvider).proposeTrade(to: friend.id, offer: offer, request: request, message: message));
      if (!sent || !mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Offer sent to ${friend.displayName ?? '@${friend.username}'}.')));
      context.pop();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final friends = ref.watch(friendsProvider);
    // preselect from ?with=
    if (_friend == null && widget.withUserId != null) {
      final f = friends.value?.where((p) => p.id == widget.withUserId).firstOrNull;
      if (f != null) _friend = f;
    }
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(AppIcons.arrowLeft), onPressed: () => context.pop()),
        title: Text(_friend == null ? 'Trade with…' : 'Trade with ${_friend!.displayName ?? '@${_friend!.username}'}'),
        actions: [
          if (_friend != null && widget.withUserId == null)
            TextButton(onPressed: () => setState(() => _friend = null), child: const Text('Change')),
        ],
      ),
      body: _friend == null ? _pickFriend(friends) : _build(_friend!),
    );
  }

  Widget _pickFriend(AsyncValue<List<Profile>> friends) {
    return friends.when(
      loading: () => const Center(child: CircularProgressIndicator(strokeWidth: 2)),
      error: (e, _) => Center(child: Text(friendlyError(e))),
      data: (list) {
        if (list.isEmpty) {
          return const EmptyState(art: AppArt.hug, title: 'No friends yet', subtitle: 'Cards trade between friends only. Add someone from their profile or scan their QR at a meet.');
        }
        final q = _search.text.trim().toLowerCase();
        final shown = q.isEmpty ? list : list.where((p) => (p.displayName ?? '').toLowerCase().contains(q) || (p.username ?? '').toLowerCase().contains(q)).toList();
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: TextField(
                textInputAction: TextInputAction.search,
                controller: _search,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(hintText: 'Search friends', prefixIcon: Icon(AppIcons.magnifyingGlass, size: 18)),
              ),
            ),
            Expanded(
              child: ListView.builder(
                itemCount: shown.length,
                itemBuilder: (_, i) {
                  final p = shown[i];
                  return ListTile(
                    leading: UserAvatar(url: p.avatarUrl, name: p.displayName ?? p.username, seed: p.id, size: 40),
                    title: Text(p.displayName ?? '@${p.username}', style: const TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: p.displayName == null ? null : Text('@${p.username}', style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary)),
                    trailing: Icon(AppIcons.caretRight, size: 16, color: AppColors.textMuted),
                    onTap: () => setState(() => _friend = p),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _build(Profile friend) {
    final mine = ref.watch(myCollectionProvider);
    final theirs = ref.watch(friendCardsProvider(friend.id));
    final settings = ref.watch(cardSettingsProvider).value ?? const CardSettings();
    final max = settings.tradeMax;
    return mine.when(
      loading: () => const Center(child: CircularProgressIndicator(strokeWidth: 2)),
      error: (e, _) => Center(child: Text(friendlyError(e))),
      data: (col) {
        final theirList = theirs.value ?? const <UserCard>[];
        final theirCounts = <String, int>{};
        for (final c in theirList) {
          theirCounts[c.cardId] = (theirCounts[c.cardId] ?? 0) + 1;
        }
        return Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                children: [
                  _Head('YOU GIVE', '$_giveTotal / $max'),
                  if (col.heldCount == 0)
                    _hint('You have no cards to give yet. You can still ask for one.')
                  else
                    for (final t in col.types.where((t) => col.owns(t.id)))
                      _PickRow(
                        card: t,
                        have: col.count(t.id),
                        picked: _give[t.id] ?? 0,
                        canAdd: _giveTotal < max,
                        onChanged: (n) => setState(() => n == 0 ? _give.remove(t.id) : _give[t.id] = n),
                      ),
                  const SizedBox(height: 8),
                  _Head('YOU GET', '$_getTotal / $max'),
                  theirs.when(
                    loading: () => const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator(strokeWidth: 2))),
                    error: (e, _) => _hint(friendlyError(e)),
                    data: (_) => theirCounts.isEmpty
                        ? _hint('${friend.displayName ?? '@${friend.username}'} has no cards yet. Send something as a gift, or wait for them to open a box.')
                        : Column(
                            children: [
                              for (final t in col.types.where((t) => (theirCounts[t.id] ?? 0) > 0))
                                _PickRow(
                                  card: t,
                                  have: theirCounts[t.id]!,
                                  picked: _get[t.id] ?? 0,
                                  canAdd: _getTotal < max,
                                  mine: col.count(t.id),
                                  onChanged: (n) => setState(() => n == 0 ? _get.remove(t.id) : _get[t.id] = n),
                                ),
                            ],
                          ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _message,
                    maxLength: 200,
                    decoration: const InputDecoration(hintText: 'Add a note (optional)', counterText: ''),
                  ),
                ],
              ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: SizedBox(
                  width: double.infinity,
                  child: PrimaryButton(
                    label: _giveTotal == 0 && _getTotal == 0
                        ? 'Pick some cards'
                        : 'Send offer · give $_giveTotal, get $_getTotal',
                    loading: _busy,
                    onPressed: _giveTotal == 0 && _getTotal == 0 ? null : () => _send(col, theirList, max),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _hint(String text) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Text(text, style: TextStyle(fontSize: 13, color: AppColors.textSecondary, height: 1.4)),
      );
}

class _Head extends StatelessWidget {
  const _Head(this.text, this.right);
  final String text;
  final String right;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(0, 10, 0, 6),
        child: Row(
          children: [
            Expanded(child: Text(text, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 1, color: AppColors.textSecondary))),
            Text(right, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textSecondary)),
          ],
        ),
      );
}

/// A card with how many copies are on the table and a +/− stepper.
class _PickRow extends StatelessWidget {
  const _PickRow({required this.card, required this.have, required this.picked, required this.canAdd, required this.onChanged, this.mine});
  final CardType card;
  final int have;
  final int picked;
  final bool canAdd;
  /// When choosing from a friend's cards: how many of this I already hold.
  final int? mine;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final selected = picked > 0;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(10, 8, 8, 8),
      decoration: BoxDecoration(
        color: selected ? AppColors.surfaceGray : AppColors.surface,
        border: Border.all(color: selected ? AppColors.textPrimary : AppColors.border),
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      child: Row(
        children: [
          CardFace(card: card, width: 48),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(card.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Row(
                  children: [
                    RarityPill(rarity: card.rarity, scale: 0.95),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        mine == null ? 'you have $have' : 'they have $have · you have $mine',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12, color: mine == 0 ? AppColors.success : AppColors.textSecondary, fontWeight: mine == 0 ? FontWeight.w700 : FontWeight.w400),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: const Icon(AppIcons.minus, size: 18),
            onPressed: picked == 0 ? null : () => onChanged(picked - 1),
          ),
          SizedBox(width: 22, child: Text('$picked', textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15))),
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: const Icon(AppIcons.plus, size: 18),
            onPressed: picked >= have || !canAdd ? null : () => onChanged(picked + 1),
          ),
        ],
      ),
    );
  }
}
