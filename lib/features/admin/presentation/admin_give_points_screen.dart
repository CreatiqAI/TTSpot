import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_images.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/dates.dart';
import '../../../core/utils/friendly_error.dart';
import '../../../core/widgets/primary_button.dart';
import '../../../core/widgets/user_avatar.dart';
import '../application/admin_providers.dart';
import 'widgets/admin_widgets.dart';

String _n(int v) => v.toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');

/// "1 point", "1,000 points".
String _pts(int v) => '${_n(v)} point${v == 1 ? '' : 's'}';

/// Admin · Give points: pick a member, give them points (or take some back,
/// never below 0), confirm, and they get a notification. The latest gifts
/// are listed underneath.
class AdminGivePointsScreen extends ConsumerStatefulWidget {
  const AdminGivePointsScreen({super.key, this.userId});

  /// Member picked already (from the Members list).
  final String? userId;

  @override
  ConsumerState<AdminGivePointsScreen> createState() => _AdminGivePointsScreenState();
}

class _AdminGivePointsScreenState extends ConsumerState<AdminGivePointsScreen> {
  static const _max = 100000;
  final _q = TextEditingController();
  final _amount = TextEditingController();
  final _note = TextEditingController();
  late String? _userId = widget.userId;
  bool _take = false;
  bool _busy = false;

  @override
  void dispose() {
    _q.dispose();
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  int get _value => int.tryParse(_amount.text.trim()) ?? 0;

  bool _matches(AdminUser u) {
    final q = _q.text.trim().toLowerCase().replaceFirst('@', '');
    if (q.isEmpty) return true;
    return '${u.username} ${u.displayName ?? ''} ${u.email ?? ''} ${u.phone ?? ''}'.toLowerCase().contains(q);
  }

  Future<void> _submit(AdminUser u) async {
    final amount = _value;
    final note = _note.text.trim();
    final verb = _take ? 'Take' : 'Give';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('$verb ${_pts(amount)} ${_take ? 'from' : 'to'} @${u.username}?'),
        content: Text(
          'They\'ll get a notification: "TT Spot ${_take ? 'took back' : 'gave you'} ${_pts(amount)}${note.isEmpty ? '.' : ': $note'}"',
          style: TextStyle(fontSize: 14, height: 1.4, color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text(verb, style: TextStyle(fontWeight: FontWeight.w700, color: _take ? AppColors.danger : AppColors.brand))),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    try {
      final balance = await ref.read(adminActionsProvider).givePoints(u.id, _take ? -amount : amount, note: note.isEmpty ? null : note);
      if (!mounted) return;
      _amount.clear();
      _note.clear();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${_take ? 'Took' : 'Gave'} ${_pts(amount)} ${_take ? 'from' : 'to'} @${u.username}. They have ${_n(balance)} now.')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final users = ref.watch(adminUsersProvider);
    final all = users.value ?? const <AdminUser>[];
    final picked = _userId == null ? null : all.where((u) => u.id == _userId).firstOrNull;
    final balance = _userId == null ? null : ref.watch(adminMemberPointsProvider(_userId!)).value;
    final gifts = ref.watch(adminGiftsProvider);
    final amount = _value;
    final tooMany = amount > _max || (_take && balance != null && amount > balance);
    final canSend = picked != null && amount > 0 && !tooMany && !_busy;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(AppIcons.arrowLeft), onPressed: () => context.pop()),
        title: const Text('Give points'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(AppIcons.arrowsClockwise),
            onPressed: () {
              ref.invalidate(adminGiftsProvider);
              ref.invalidate(adminUsersProvider);
              if (_userId != null) ref.invalidate(adminMemberPointsProvider(_userId!));
            },
          ),
        ],
      ),
      body: ListView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: EdgeInsets.only(bottom: MediaQuery.paddingOf(context).bottom + 32),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: false, label: Text('Give points'), icon: Icon(AppIcons.gift, size: 16)),
                ButtonSegment(value: true, label: Text('Take points'), icon: Icon(AppIcons.minus, size: 16)),
              ],
              selected: {_take},
              showSelectedIcon: false,
              onSelectionChanged: (s) => setState(() => _take = s.first),
            ),
          ),

          // ---- member
          const AdminHead('MEMBER'),
          if (picked != null)
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
              decoration: BoxDecoration(color: AppColors.surfaceGray, borderRadius: BorderRadius.circular(14)),
              child: Row(
                children: [
                  UserAvatar(url: picked.avatarUrl, name: picked.displayName ?? picked.username, seed: picked.id, size: 44),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(picked.displayName ?? '@${picked.username}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            Flexible(child: Text('@${picked.username} · ', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary))),
                            const PointsCoin(size: 14),
                            const SizedBox(width: 3),
                            Text(balance == null ? '…' : _n(balance), style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                          ],
                        ),
                      ],
                    ),
                  ),
                  TextButton(onPressed: _busy ? null : () => setState(() => _userId = null), child: const Text('Change')),
                ],
              ),
            )
          else if (_userId != null && users.isLoading)
            // Opened for one member: wait for them rather than flash the search.
            const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator(strokeWidth: 2)))
          else ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
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
            if (users.isLoading && all.isEmpty)
              const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator(strokeWidth: 2)))
            else if (users.hasError && all.isEmpty)
              Padding(padding: const EdgeInsets.all(16), child: Text(friendlyError(users.error!), style: TextStyle(color: AppColors.textSecondary)))
            else ...[
              // The newest few until the admin searches, so Amount stays in reach.
              for (final u in all.where((u) => u.username.isNotEmpty && _matches(u)).take(_q.text.trim().isEmpty ? 6 : 20))
                ListTile(
                  dense: true,
                  leading: UserAvatar(url: u.avatarUrl, name: u.displayName ?? u.username, seed: u.id, size: 38),
                  title: Text(u.displayName ?? '@${u.username}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                  subtitle: Text('@${u.username}', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                  onTap: () => setState(() {
                    _userId = u.id;
                    _q.clear();
                    FocusScope.of(context).unfocus();
                  }),
                ),
              if (all.where((u) => u.username.isNotEmpty && _matches(u)).isEmpty)
                Padding(padding: const EdgeInsets.all(16), child: Text('No one matches.', style: TextStyle(color: AppColors.textSecondary))),
            ],
          ],

          // ---- amount + note
          const AdminHead('AMOUNT'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              controller: _amount,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(6)],
              onChanged: (_) => setState(() {}),
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              decoration: InputDecoration(
                hintText: 'How many points',
                prefixIcon: const Padding(padding: EdgeInsets.all(12), child: PointsCoin(size: 20)),
                prefixText: _take ? '− ' : '+ ',
                isDense: true,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final v in const [100, 500, 1000, 5000])
                  ChoiceChip(label: Text(_n(v)), selected: amount == v, showCheckmark: false, onSelected: (_) => setState(() => _amount.text = '$v')),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Text(
              amount > _max
                  ? 'Up to ${_n(_max)} points at a time.'
                  : _take && balance != null && amount > balance
                      ? 'They only have ${_pts(balance)}. You can take up to that.'
                      : _take
                          ? 'Their balance can\'t go below 0.'
                          : 'Up to ${_n(_max)} points at a time.',
              style: TextStyle(fontSize: 12.5, color: tooMany ? AppColors.danger : AppColors.textSecondary),
            ),
          ),
          const AdminHead('NOTE · OPTIONAL'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              controller: _note,
              maxLength: 140,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(hintText: 'Shown to them, e.g. Thanks for hosting the meet', counterText: '', isDense: true),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: SizedBox(
              width: double.infinity,
              child: PrimaryButton(
                label: picked == null ? 'Pick a member first' : '${_take ? 'Take' : 'Give'} ${amount > 0 ? _pts(amount) : 'points'}',
                icon: _take ? AppIcons.minus : AppIcons.gift,
                loading: _busy,
                onPressed: canSend ? () => _submit(picked) : null,
              ),
            ),
          ),

          // ---- recent
          const AdminHead('RECENT GIFTS'),
          gifts.when(
            loading: () => const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator(strokeWidth: 2))),
            error: (e, _) => Padding(padding: const EdgeInsets.all(16), child: Text(friendlyError(e), style: TextStyle(color: AppColors.textSecondary))),
            data: (list) => list.isEmpty
                ? Padding(padding: const EdgeInsets.fromLTRB(16, 0, 16, 8), child: Text('No points given yet.', style: TextStyle(fontSize: 13, color: AppColors.textSecondary)))
                : Column(children: [for (final g in list) _GiftRow(g: g)]),
          ),
        ],
      ),
    );
  }
}

class _GiftRow extends StatelessWidget {
  const _GiftRow({required this.g});
  final AdminGift g;

  @override
  Widget build(BuildContext context) {
    final give = g.delta > 0;
    final note = (g.note == null || g.note == 'Free points' || g.note == 'Taken back by TT Spot') ? null : g.note;
    return ListTile(
      dense: true,
      leading: UserAvatar(url: g.avatarUrl, name: g.displayName ?? g.username, seed: g.userId, size: 38),
      title: Text(g.displayName ?? '@${g.username}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
      subtitle: Text('@${g.username} · ${timeAgo(g.createdAt)}${note == null ? '' : '\n$note'}', style: TextStyle(fontSize: 12, height: 1.35, color: AppColors.textSecondary)),
      isThreeLine: note != null,
      trailing: Text('${give ? '+' : '−'}${_n(g.delta.abs())}', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: give ? AppColors.success : AppColors.danger)),
      onTap: () => context.push(Routes.profile(g.userId)),
    );
  }
}
