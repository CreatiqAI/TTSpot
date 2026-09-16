import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../../core/router/app_router.dart';
import '../../../core/supabase/supabase_client.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/dates.dart';
import '../../../core/utils/friendly_error.dart';
import '../../../core/widgets/user_avatar.dart';
import '../../auth/data/auth_repository.dart';
import '../../safety/data/safety_repository.dart';
import '../../safety/presentation/report_sheet.dart';
import '../application/social_providers.dart';
import '../domain/post.dart';
import 'widgets/post_card.dart';

class PostDetailScreen extends ConsumerStatefulWidget {
  const PostDetailScreen({super.key, required this.postId});
  final String postId;

  @override
  ConsumerState<PostDetailScreen> createState() => _PostDetailScreenState();
}

class _PostDetailScreenState extends ConsumerState<PostDetailScreen> {
  final _comment = TextEditingController();
  final _commentFocus = FocusNode();
  bool _busy = false;

  @override
  void dispose() {
    _comment.dispose();
    _commentFocus.dispose();
    super.dispose();
  }

  Future<void> _post() async {
    final text = _comment.text.trim();
    if (text.isEmpty) return;
    FocusScope.of(context).unfocus();
    setState(() => _busy = true);
    try {
      await ref.read(socialActionsProvider).addComment(widget.postId, text);
      _comment.clear();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final post = ref.watch(postProvider(widget.postId));
    final comments = ref.watch(postCommentsProvider(widget.postId));
    final me = ref.watch(currentUserIdProvider);
    final myProfile = ref.watch(currentProfileProvider).value;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(AppIcons.arrowLeft), onPressed: () => context.pop()),
        title: Text(post.value?.post.kind.label ?? 'Post'),
      ),
      body: post.when(
        loading: () => const Center(child: CircularProgressIndicator(strokeWidth: 2)),
        error: (e, _) => Center(child: Text(friendlyError(e))),
        data: (f) {
          if (f == null) return const Center(child: Text('This post is gone.'));
          return Column(
            children: [
              Expanded(
                child: RefreshIndicator(
                  onRefresh: () async {
                    ref.invalidate(postProvider(widget.postId));
                    ref.invalidate(postCommentsProvider(widget.postId));
                    await ref.read(postProvider(widget.postId).future);
                  },
                  child: ListView(
                    padding: EdgeInsets.zero,
                    children: [
                      PostCard(feed: f, expanded: true, onComment: () => _commentFocus.requestFocus()),
                      if (f.post.kind == PostKind.guide && (f.post.guideStops ?? const []).isNotEmpty) _GuideMap(post: f.post),
                      if (f.post.kind == PostKind.spotted && f.post.latLng != null) _SpottedMap(post: f.post),
                      const Divider(),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                        child: comments.when(
                          loading: () => const Center(child: Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator(strokeWidth: 2))),
                          error: (e, _) => Text(friendlyError(e)),
                          data: (list) => list.isEmpty
                              ? Text('No comments yet.', style: TextStyle(color: AppColors.textSecondary))
                              : Column(children: [for (final c in list) _CommentTile(comment: c, isMine: c.userId == me, postId: widget.postId)]),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Container(
                decoration: BoxDecoration(color: AppColors.bg, border: Border(top: BorderSide(color: AppColors.border, width: 0.5))),
                child: SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
                    child: Row(
                      children: [
                        UserAvatar(url: myProfile?.avatarUrl, name: myProfile?.displayName ?? myProfile?.username, size: 32),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            controller: _comment,
                            focusNode: _commentFocus,
                            minLines: 1,
                            maxLines: 4,
                            maxLength: 1000,
                            decoration: const InputDecoration(
                              hintText: 'Add a comment…',
                              counterText: '',
                              filled: false,
                              border: InputBorder.none,
                              enabledBorder: InputBorder.none,
                              focusedBorder: InputBorder.none,
                              contentPadding: EdgeInsets.symmetric(vertical: 8),
                            ),
                          ),
                        ),
                        TextButton(
                          onPressed: _busy ? null : _post,
                          child: _busy ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Post'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _CommentTile extends ConsumerWidget {
  const _CommentTile({required this.comment, required this.isMine, required this.postId});
  final PostComment comment;
  final bool isMine;
  final String postId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final name = comment.author?.username ?? 'someone';
    return InkWell(
      onLongPress: () async {
        final action = await showModalBottomSheet<String>(
          context: context,
          showDragHandle: true,
          builder: (ctx) => SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (isMine)
                  ListTile(leading: const Icon(AppIcons.trash, color: AppColors.danger), title: const Text('Delete comment', style: TextStyle(color: AppColors.danger)), onTap: () => Navigator.pop(ctx, 'delete'))
                else ...[
                  ListTile(leading: const Icon(AppIcons.flag), title: const Text('Report comment'), onTap: () => Navigator.pop(ctx, 'report')),
                  ListTile(leading: const Icon(AppIcons.prohibit, color: AppColors.danger), title: Text('Block @$name', style: const TextStyle(color: AppColors.danger)), onTap: () => Navigator.pop(ctx, 'block')),
                ],
                const SizedBox(height: 8),
              ],
            ),
          ),
        );
        if (!context.mounted || action == null) return;
        switch (action) {
          case 'delete':
            try {
              await ref.read(socialActionsProvider).deleteComment(postId, comment.id);
            } catch (e) {
              if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e))));
            }
          case 'report':
            await showReportSheet(context, target: ReportTarget.comment, targetId: comment.id);
          case 'block':
            await confirmBlockUser(context, ref, userId: comment.userId, displayName: '@$name');
        }
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            GestureDetector(
              onTap: () => context.push(Routes.profile(comment.userId)),
              child: UserAvatar(url: comment.author?.avatarUrl, name: comment.author?.displayName ?? name, size: 32),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  RichText(
                    text: TextSpan(
                      style: TextStyle(fontSize: 14, color: AppColors.textPrimary, height: 1.4),
                      children: [TextSpan(text: '$name  ', style: const TextStyle(fontWeight: FontWeight.w600)), TextSpan(text: comment.body)],
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(timeAgo(comment.createdAt), style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GuideMap extends StatelessWidget {
  const _GuideMap({required this.post});
  final Post post;

  @override
  Widget build(BuildContext context) {
    final stops = post.guideStops!;
    final points = stops.map((s) => s.latLng).toList();
    var south = points.first.latitude, north = points.first.latitude, west = points.first.longitude, east = points.first.longitude;
    for (final p in points) {
      if (p.latitude < south) south = p.latitude;
      if (p.latitude > north) north = p.latitude;
      if (p.longitude < west) west = p.longitude;
      if (p.longitude > east) east = p.longitude;
    }
    final center = LatLng((south + north) / 2, (west + east) / 2);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.md),
            child: SizedBox(
              height: 220,
              child: GoogleMap(
                initialCameraPosition: CameraPosition(target: center, zoom: 10.5),
                onMapCreated: (c) {
                  if (points.length > 1) {
                    c.animateCamera(CameraUpdate.newLatLngBounds(LatLngBounds(southwest: LatLng(south, west), northeast: LatLng(north, east)), 48));
                  }
                },
                markers: {
                  for (var i = 0; i < stops.length; i++)
                    Marker(markerId: MarkerId('stop$i'), position: stops[i].latLng, infoWindow: InfoWindow(title: '${i + 1}. ${stops[i].name}')),
                },
                polylines: {
                  if (points.length > 1) Polyline(polylineId: const PolylineId('route'), points: points, color: AppColors.primary, width: 4),
                },
                zoomControlsEnabled: false,
                myLocationButtonEnabled: false,
                mapToolbarEnabled: false,
                liteModeEnabled: false,
              ),
            ),
          ),
          const SizedBox(height: 10),
          for (var i = 0; i < stops.length; i++)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  CircleAvatar(radius: 11, backgroundColor: AppColors.textPrimary, child: Text('${i + 1}', style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700))),
                  const SizedBox(width: 10),
                  Expanded(child: Text(stops[i].name, style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w500))),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _SpottedMap extends StatelessWidget {
  const _SpottedMap({required this.post});
  final Post post;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: SizedBox(
          height: 160,
          child: GoogleMap(
            initialCameraPosition: CameraPosition(target: post.latLng!, zoom: 14),
            liteModeEnabled: true,
            markers: {Marker(markerId: MarkerId(post.id), position: post.latLng!)},
            zoomControlsEnabled: false,
            myLocationButtonEnabled: false,
            mapToolbarEnabled: false,
          ),
        ),
      ),
    );
  }
}
