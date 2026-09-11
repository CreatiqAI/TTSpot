import 'dart:async';

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

class StoryViewerArgs {
  const StoryViewerArgs({required this.groups, required this.initialGroup});
  final List<StoryGroup> groups;
  final int initialGroup;
}

/// Full-screen story player: progress bars, tap left/right, hold to pause, swipe down to close.
class StoryViewerScreen extends ConsumerStatefulWidget {
  const StoryViewerScreen({super.key, required this.args});
  final StoryViewerArgs args;

  @override
  ConsumerState<StoryViewerScreen> createState() => _StoryViewerScreenState();
}

class _StoryViewerScreenState extends ConsumerState<StoryViewerScreen> {
  static const _duration = Duration(seconds: 5);
  late int _group;
  int _index = 0;
  double _progress = 0;
  Timer? _timer;
  bool _paused = false;

  StoryGroup get _g => widget.args.groups[_group];
  Story get _story => _g.stories[_index];

  @override
  void initState() {
    super.initState();
    _group = widget.args.initialGroup;
    _start();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _start() {
    _timer?.cancel();
    _progress = 0;
    ref.read(socialActionsProvider).markStoryViewed(_story.id).catchError((_) {});
    _timer = Timer.periodic(const Duration(milliseconds: 50), (t) {
      if (_paused) return;
      setState(() => _progress += 50 / _duration.inMilliseconds);
      if (_progress >= 1) _next();
    });
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
    if (_progress > 0.15 || (_index == 0 && _group == 0)) {
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
    _timer?.cancel();
    ref.invalidate(storiesProvider);
    if (mounted) context.pop();
  }

  Future<void> _delete() async {
    _paused = true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete story?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete', style: TextStyle(color: AppColors.danger))),
        ],
      ),
    );
    if (ok == true) {
      await ref.read(socialActionsProvider).deleteStory(_story.id);
      _close();
      return;
    }
    _paused = false;
  }

  @override
  Widget build(BuildContext context) {
    final me = ref.watch(currentUserIdProvider);
    final s = _story;
    final width = MediaQuery.sizeOf(context).width;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: GestureDetector(
          onTapUp: (d) => d.localPosition.dx < width / 3 ? _prev() : _next(),
          onLongPressStart: (_) => setState(() => _paused = true),
          onLongPressEnd: (_) => setState(() => _paused = false),
          onVerticalDragEnd: (d) {
            if ((d.primaryVelocity ?? 0) > 300) _close();
          },
          child: Stack(
            fit: StackFit.expand,
            children: [
              Image.network(
                s.photoUrl,
                fit: BoxFit.contain,
                loadingBuilder: (_, child, prog) => prog == null ? child : const Center(child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)),
                errorBuilder: (_, _, _) => const Center(child: Icon(AppIcons.imageBroken, color: Colors.white54, size: 48)),
              ),
              SafeArea(
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
                      child: Row(
                        children: [
                          for (var i = 0; i < _g.stories.length; i++)
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 2),
                                child: LinearProgressIndicator(
                                  value: i < _index ? 1 : (i == _index ? _progress : 0),
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
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 10, 4, 0),
                      child: Row(
                        children: [
                          GestureDetector(
                            onTap: () {
                              _timer?.cancel();
                              context.push(Routes.profile(_g.author.id));
                            },
                            child: UserAvatar(url: _g.author.avatarUrl, name: _g.author.displayName ?? _g.author.username, size: 34, borderColor: Colors.white),
                          ),
                          const SizedBox(width: 10),
                          Text(_g.author.username ?? '', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14)),
                          const SizedBox(width: 8),
                          Text(timeAgo(s.createdAt), style: const TextStyle(color: Colors.white70, fontSize: 13)),
                          const Spacer(),
                          if (s.authorId == me) IconButton(icon: const Icon(AppIcons.trash, color: Colors.white), onPressed: _delete),
                          IconButton(icon: const Icon(AppIcons.x, color: Colors.white), onPressed: _close),
                        ],
                      ),
                    ),
                    const Spacer(),
                    if ((s.caption ?? '').trim().isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          decoration: BoxDecoration(color: Colors.black45, borderRadius: BorderRadius.circular(12)),
                          child: Text(s.caption!.trim(), textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 15, height: 1.4)),
                        ),
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
