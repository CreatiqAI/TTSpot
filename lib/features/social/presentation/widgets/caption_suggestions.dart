import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/supabase/supabase_client.dart';
import '../../../../core/theme/app_icons.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/user_avatar.dart';
import '../../../auth/domain/profile.dart';
import '../../../friends/application/friends_providers.dart';
import '../../../profile/application/profile_providers.dart';
import '../../../profile/domain/car.dart';
import '../../application/social_providers.dart';
import '../../application/tags_providers.dart';
import '../../domain/tags.dart';

/// Room to leave under the caret so the suggestion row never covers it.
const kCaptionAssistScrollPadding = EdgeInsets.fromLTRB(20, 20, 20, 96);

/// Wraps a caption field. Typing # suggests tags (my cars' make and model,
/// then popular ones); typing @ suggests people (friends first, then
/// everyone). They show as one row of chips just above the keyboard; a tap
/// completes the word. Give the field [kCaptionAssistScrollPadding].
class CaptionAssist extends ConsumerStatefulWidget {
  const CaptionAssist({super.key, required this.controller, required this.child});
  final TextEditingController controller;
  final Widget child;

  @override
  ConsumerState<CaptionAssist> createState() => _CaptionAssistState();
}

class _CaptionAssistState extends ConsumerState<CaptionAssist> with WidgetsBindingObserver {
  final _portal = OverlayPortalController();
  bool _focused = false;
  CaptionQuery? _query;

  /// [_query]'s text, settled for 250 ms (what goes to the server).
  String _settled = '';
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onText);
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didUpdateWidget(covariant CaptionAssist old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller.removeListener(_onText);
      widget.controller.addListener(_onText);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onText);
    WidgetsBinding.instance.removeObserver(this);
    _debounce?.cancel();
    super.dispose();
  }

  // The keyboard moving: keep the row on top of it.
  @override
  void didChangeMetrics() {
    if (_portal.isShowing && mounted) setState(() {});
  }

  void _onFocus(bool focused) {
    _focused = focused;
    _onText();
  }

  void _onText() {
    if (!mounted) return;
    final q = _focused ? activeCaptionQuery(widget.controller.value) : null;
    if (q == _query) return;
    final textChanged = q?.query != _query?.query || q?.kind != _query?.kind;
    setState(() => _query = q);
    if (q == null) {
      _debounce?.cancel();
      if (_portal.isShowing) _portal.hide();
      return;
    }
    if (!_portal.isShowing) _portal.show();
    if (textChanged) {
      final typed = q.query;
      _debounce?.cancel();
      _debounce = Timer(const Duration(milliseconds: 250), () {
        if (mounted) setState(() => _settled = typed);
      });
    }
  }

  void _pick(String replacement) {
    final q = _query;
    if (q == null) return;
    widget.controller.value = completeCaptionQuery(widget.controller.value, q, replacement);
  }

  @override
  Widget build(BuildContext context) {
    return OverlayPortal(
      controller: _portal,
      overlayChildBuilder: _overlay,
      child: Focus(canRequestFocus: false, skipTraversal: true, onFocusChange: _onFocus, child: widget.child),
    );
  }

  Widget _overlay(BuildContext context) {
    final q = _query;
    if (q == null) return const SizedBox.shrink();
    // The body's MediaQuery has the keyboard taken out; the view still has it.
    final view = MediaQueryData.fromView(View.of(context));
    return Positioned(
      left: 0,
      right: 0,
      bottom: view.viewInsets.bottom + view.padding.bottom,
      child: TextFieldTapRegion(
        child: q.kind == CaptionTokenKind.tag
            ? _TagSuggestions(query: q.query, settled: _settled, onPick: _pick)
            : _PeopleSuggestions(query: q.query, settled: _settled, onPick: _pick),
      ),
    );
  }
}

/// My cars' make and model first (when they match), then tags others use.
class _TagSuggestions extends ConsumerWidget {
  const _TagSuggestions({required this.query, required this.settled, required this.onPick});
  final String query;
  final String settled;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(currentUserIdProvider);
    final cars = me == null ? null : ref.watch(userCarsProvider(me)).value;
    // While the debounce settles, keep showing the last answer.
    final remote = ref.watch(tagSearchProvider(query.startsWith(settled) || settled.startsWith(query) ? settled : '')).value ?? const <TagCount>[];
    final seen = <String>{};
    final chips = <Widget>[];
    // posts 0 = not counted (my own cars).
    void add(String tag, int posts) {
      if (!tag.startsWith(query) || !seen.add(tag) || chips.length >= 12) return;
      chips.add(_Chip(
        key: ValueKey('tag-$tag'),
        onTap: () => onPick('#$tag'),
        children: [
          Text('#$tag', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
          if (posts > 0) ...[
            const SizedBox(width: 6),
            Text(compactCount(posts), style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
          ],
        ],
      ));
    }

    for (final c in cars ?? const <Car>[]) {
      final make = tagFromName(c.make);
      final model = tagFromName(c.model);
      if (make != null) add(make, 0);
      if (model != null) add(model, 0);
    }
    for (final t in remote) {
      add(t.tag, t.posts);
    }
    if (chips.isEmpty) return const SizedBox.shrink();
    return _Bar(icon: AppIcons.hash, chips: chips);
  }
}

/// Friends whose name or handle matches, then anyone the search finds.
class _PeopleSuggestions extends ConsumerWidget {
  const _PeopleSuggestions({required this.query, required this.settled, required this.onPick});
  final String query;
  final String settled;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(currentUserIdProvider);
    final friends = ref.watch(friendsProvider).value ?? const <Profile>[];
    final others = settled.isEmpty ? const <Profile>[] : (ref.watch(profileSearchProvider(settled)).value ?? const <Profile>[]);
    bool matches(Profile p) {
      if (query.isEmpty) return true;
      final handle = (p.username ?? '').toLowerCase();
      final name = (p.displayName ?? '').toLowerCase();
      return handle.contains(query) || name.contains(query);
    }

    final seen = <String>{};
    final chips = <Widget>[];
    for (final p in [...friends.where(matches), ...others.where(matches)]) {
      final handle = p.username;
      if (handle == null || handle.isEmpty || p.id == me || !seen.add(p.id) || chips.length >= 12) continue;
      chips.add(_Chip(
        key: ValueKey('person-${p.id}'),
        onTap: () => onPick('@$handle'),
        children: [
          UserAvatar(url: p.avatarUrl, name: p.displayName ?? handle, seed: p.id, size: 22),
          const SizedBox(width: 6),
          Text('@$handle', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
        ],
      ));
    }
    if (chips.isEmpty) return const SizedBox.shrink();
    return _Bar(icon: AppIcons.users, chips: chips);
  }
}

class _Bar extends StatelessWidget {
  const _Bar({required this.icon, required this.chips});
  final IconData icon;
  final List<Widget> chips;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      elevation: 6,
      shadowColor: Colors.black26,
      child: SafeArea(
        top: false,
        bottom: false,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          child: Row(
            children: [
              Icon(icon, size: 18, color: AppColors.textSecondary),
              const SizedBox(width: 8),
              for (final c in chips) Padding(padding: const EdgeInsets.only(right: 8), child: c),
            ],
          ),
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({super.key, required this.onTap, required this.children});
  final VoidCallback onTap;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(color: AppColors.surfaceGray, borderRadius: BorderRadius.circular(AppRadius.pill)),
          child: Row(mainAxisSize: MainAxisSize.min, children: children),
        ),
      ),
    );
  }
}
