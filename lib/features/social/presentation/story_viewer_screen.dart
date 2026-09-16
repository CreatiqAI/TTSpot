import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../../core/supabase/supabase_client.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/dates.dart';
import '../../../core/widgets/user_avatar.dart';
import '../application/social_providers.dart';
import '../domain/post.dart';
import 'moment_sheets.dart';
import 'share_sheet.dart';
import 'widgets/story_video.dart';

class StoryViewerArgs {
  const StoryViewerArgs({required this.groups, required this.initialGroup, this.initialIndex = 0});
  final List<StoryGroup> groups;
  final int initialGroup;
  final int initialIndex;
}

/// Full-screen moment player. Finger down pauses at once, lift resumes; a
/// quick tap goes back / forward; swipe down closes. Progress runs on an
/// AnimationController so it never stutters, and the next photo is
/// pre-loaded while the current one plays.
class StoryViewerScreen extends ConsumerStatefulWidget {
  const StoryViewerScreen({super.key, required this.args});
  final StoryViewerArgs args;

  @override
  ConsumerState<StoryViewerScreen> createState() => _StoryViewerScreenState();
}

class _StoryViewerScreenState extends ConsumerState<StoryViewerScreen> with SingleTickerProviderStateMixin {
  static const _duration = Duration(seconds: 5);
  late final AnimationController _ctrl = AnimationController(vsync: this, duration: _duration)
    ..addStatusListener((st) {
      if (st == AnimationStatus.completed) _next();
    });
  late int _group;
  int _index = 0;
  DateTime? _downAt;
  /// True while the finger is down or a sheet is up (videos pause too).
  bool _paused = false;

  StoryGroup get _g => widget.args.groups[_group];
  Story get _story => _g.stories[_index];

  @override
  void initState() {
    super.initState();
    _group = widget.args.initialGroup;
    _index = widget.args.initialIndex.clamp(0, _g.stories.length - 1);
    _start();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _precacheAround();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _precacheAround() {
    Story? at(int g, int i) {
      if (g < 0 || g >= widget.args.groups.length) return null;
      final list = widget.args.groups[g].stories;
      if (i < 0 || i >= list.length) return null;
      return list[i];
    }

    final next = at(_group, _index + 1) ?? at(_group + 1, 0);
    final prev = at(_group, _index - 1);
    for (final s in [next, prev]) {
      if (s != null) precacheImage(NetworkImage(s.photoUrl), context);
    }
  }

  void _start() {
    ref.read(socialActionsProvider).markStoryViewed(_story.id).catchError((_) {});
    _paused = false;
    _ctrl
      ..stop()
      ..reset()
      ..duration = _duration;
    // Videos start the bar once they know how long they are (see StoryVideo.onReady).
    if (!_story.isVideo) _ctrl.forward();
    if (mounted) _precacheAround();
  }

  void _pause() {
    _paused = true;
    _ctrl.stop();
    if (mounted) setState(() {});
  }

  void _resume() {
    _paused = false;
    _ctrl.forward();
    if (mounted) setState(() {});
  }

  void _next() {
    if (_index < _g.stories.length - 1) {
      setState(() => _index++);
      _start();
    } else if (_group < widget.args.groups.length - 1) {
      setState(() {
        _group++;
        _index = 0;
      });
      _start();
    } else {
      _close();
    }
  }

  void _prev() {
    if (_ctrl.value > 0.15 || (_index == 0 && _group == 0)) {
      _start();
      return;
    }
    if (_index > 0) {
      setState(() => _index--);
    } else {
      setState(() {
        _group--;
        _index = widget.args.groups[_group].stories.length - 1;
      });
    }
    _start();
  }

  void _close() {
    _ctrl.stop();
    ref.invalidate(storiesProvider);
    if (mounted) context.pop();
  }

  // ---- touch: down = pause now; up within 250 ms = tap; later = resume.
  void _down(TapDownDetails d) {
    _downAt = DateTime.now();
    _pause();
  }

  void _up(TapUpDetails d) {
    final held = DateTime.now().difference(_downAt ?? DateTime.now());
    _downAt = null;
    if (held < const Duration(milliseconds: 250)) {
      d.localPosition.dx < MediaQuery.sizeOf(context).width / 3 ? _prev() : _next();
    } else {
      _resume();
    }
  }

  void _cancel() {
    _downAt = null;
    _resume();
  }

  Future<void> _menu() async {
    _ctrl.stop();
    final me = ref.read(currentUserIdProvider);
    final mine = _story.authorId == me;
    final albumId = _g.albumId;
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (albumId != null && mine) ListTile(leading: const Icon(AppIcons.pencilSimple), title: const Text('Edit album'), onTap: () => Navigator.pop(ctx, 'edit')),
            if (albumId != null && mine)
              ListTile(leading: const Icon(AppIcons.trash, color: AppColors.danger), title: const Text('Delete album', style: TextStyle(color: AppColors.danger)), onTap: () => Navigator.pop(ctx, 'deleteAlbum')),
            if (mine)
              ListTile(leading: const Icon(AppIcons.trash, color: AppColors.danger), title: const Text('Delete this moment', style: TextStyle(color: AppColors.danger)), onTap: () => Navigator.pop(ctx, 'delete')),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (!mounted) return;
    switch (action) {
      case 'edit':
        _ctrl.stop();
        context.pushReplacement(Routes.editAlbum(albumId!));
      case 'deleteAlbum':
        final ok = await _confirm('Delete this album?', 'The moments themselves stay.');
        if (ok) {
          await ref.read(socialActionsProvider).deleteAlbum(albumId!);
          _close();
        } else {
          _ctrl.forward();
        }
      case 'delete':
        final ok = await _confirm('Delete this moment?', null);
        if (ok) {
          await ref.read(socialActionsProvider).deleteStory(_story.id);
          _close();
        } else {
          _ctrl.forward();
        }
      default:
        _ctrl.forward();
    }
  }

  /// Pause while a sheet is up, resume when it closes.
  Future<void> _hold(Future<void> Function() open) async {
    _pause();
    await open();
    if (mounted) _resume();
  }

  Future<bool> _confirm(String title, String? body) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: body == null ? null : Text(body),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete', style: TextStyle(color: AppColors.danger))),
        ],
      ),
    );
    return ok == true;
  }

  @override
  Widget build(BuildContext context) {
    final me = ref.watch(currentUserIdProvider);
    final s = _story;
    final label = _g.label;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: _down,
          onTapUp: _up,
          onTapCancel: _cancel,
          onVerticalDragEnd: (d) {
            if ((d.primaryVelocity ?? 0) > 300) _close();
          },
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (s.isVideo)
                StoryVideo(
                  key: ValueKey('v:${s.id}'),
                  url: s.videoUrl!,
                  posterUrl: s.photoUrl,
                  paused: _paused,
                  onReady: (d) {
                    if (!mounted || _story.id != s.id) return;
                    _ctrl
                      ..duration = d < const Duration(seconds: 1) ? const Duration(seconds: 1) : d
                      ..reset();
                    if (!_paused) _ctrl.forward();
                  },
                  // The progress bar (sized to the video) advances the story; nothing to do here.
                  onEnded: () {},
                )
              else
                Image.network(
                  s.photoUrl,
                  fit: BoxFit.contain,
                  gaplessPlayback: true,
                  loadingBuilder: (_, child, prog) => prog == null ? child : const Center(child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)),
                  errorBuilder: (_, _, _) => const Center(child: Icon(AppIcons.imageBroken, color: Colors.white54, size: 48)),
                ),
              // top fade so the bars and name read on bright photos
              const Positioned(
                left: 0,
                right: 0,
                top: 0,
                height: 140,
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0x99000000), Colors.transparent])),
                  ),
                ),
              ),
              SafeArea(
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
                      child: AnimatedBuilder(
                        animation: _ctrl,
                        builder: (_, _) => Row(
                          children: [
                            for (var i = 0; i < _g.stories.length; i++)
                              Expanded(
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 2),
                                  child: LinearProgressIndicator(
                                    value: i < _index ? 1 : (i == _index ? _ctrl.value : 0),
                                    minHeight: 2.5,
                                    backgroundColor: Colors.white30,
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(2),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 10, 4, 0),
                      child: Row(
                        children: [
                          GestureDetector(
                            onTap: () {
                              _ctrl.stop();
                              context.push(Routes.profile(_g.author.id));
                            },
                            child: UserAvatar(url: _g.author.avatarUrl, name: _g.author.displayName ?? _g.author.username, size: 34, borderColor: Colors.white),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(label ?? (_g.author.username ?? ''), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14)),
                                Text(
                                  label != null ? '${_g.author.username ?? ''} · ${s.whereLabel ?? timeAgo(s.createdAt)}' : (s.whereLabel != null ? '${s.whereLabel} · ${timeAgo(s.createdAt)}' : timeAgo(s.createdAt)),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                                ),
                              ],
                            ),
                          ),
                          if (s.authorId == me) IconButton(icon: const Icon(AppIcons.dotsThree, color: Colors.white), onPressed: _menu),
                          IconButton(icon: const Icon(AppIcons.x, color: Colors.white), onPressed: _close),
                        ],
                      ),
                    ),
                    const Spacer(),
                    if ((s.caption ?? '').trim().isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          decoration: BoxDecoration(color: Colors.black45, borderRadius: BorderRadius.circular(12)),
                          child: Text(s.caption!.trim(), textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 15, height: 1.4)),
                        ),
                      ),
                    _BottomBar(
                      mine: s.authorId == me,
                      viewers: s.authorId == me ? (ref.watch(storyViewersProvider(s.id)).value?.length) : null,
                      onViewers: () => _hold(() => showMomentViewers(context, s.id)),
                      onAlbum: () => _hold(() => showAddToAlbum(context, s.id)),
                      onSend: () => _hold(() => showShareSheet(context, storyId: s.id)),
                      onReply: () => _hold(() => showShareSheet(context, storyId: s.id, preset: s.authorId)),
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


/// Instagram-style strip at the bottom. Mine: viewers · add to album · send.
/// Someone else's: reply · send.
class _BottomBar extends StatelessWidget {
  const _BottomBar({required this.mine, required this.viewers, required this.onViewers, required this.onAlbum, required this.onSend, required this.onReply});
  final bool mine;
  final int? viewers;
  final VoidCallback onViewers;
  final VoidCallback onAlbum;
  final VoidCallback onSend;
  final VoidCallback onReply;

  @override
  Widget build(BuildContext context) {
    Widget item(IconData icon, String label, VoidCallback onTap) => Expanded(
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, color: Colors.white, size: 24),
                  const SizedBox(height: 4),
                  Text(label, style: const TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.w600)),
                ],
              ),
            ),
          ),
        );
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 10),
      decoration: const BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.transparent, Color(0xAA000000)])),
      child: Row(
        children: mine
            ? [
                item(AppIcons.eye, viewers == null ? 'Viewers' : '$viewers viewer${viewers == 1 ? '' : 's'}', onViewers),
                item(AppIcons.images, 'Add to album', onAlbum),
                item(AppIcons.paperPlaneTilt, 'Send', onSend),
              ]
            : [
                item(AppIcons.chatCircle, 'Reply', onReply),
                item(AppIcons.paperPlaneTilt, 'Send', onSend),
              ],
      ),
    );
  }
}
