import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/supabase/supabase_client.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/friendly_error.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/theme/app_art.dart';
import '../application/social_providers.dart';
import '../domain/post.dart';

/// Make or edit a moment album: name it, tick the moments, pick a cover.
/// Selected moments keep the order you tapped them in.
class AlbumEditorScreen extends ConsumerStatefulWidget {
  const AlbumEditorScreen({super.key, this.albumId, this.preselect});
  final String? albumId;
  /// A moment to tick from the start (from "Add to album" → "New album").
  final String? preselect;

  @override
  ConsumerState<AlbumEditorScreen> createState() => _AlbumEditorScreenState();
}

class _AlbumEditorScreenState extends ConsumerState<AlbumEditorScreen> {
  final _name = TextEditingController();
  final _selected = <String>[]; // story ids, in tap order
  String? _cover;
  bool _busy = false;
  bool _loaded = false;

  bool get _editing => widget.albumId != null;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _snack(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  void _toggle(Story s) {
    setState(() {
      if (_selected.contains(s.id)) {
        _selected.remove(s.id);
        if (_cover == s.photoUrl) _cover = null;
      } else {
        _selected.add(s.id);
        _cover ??= s.photoUrl;
        // First pick names the album after where it was taken, if the name is still empty.
        if (_name.text.trim().isEmpty && s.whereLabel != null) _name.text = s.whereLabel!;
      }
    });
  }

  Future<void> _pickCover(List<Story> all) async {
    final chosen = all.where((s) => _selected.contains(s.id)).toList();
    if (chosen.isEmpty) {
      _snack('Pick some moments first.');
      return;
    }
    final url = await showModalBottomSheet<String>(
      useRootNavigator: true, // above the shell tab bar
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(padding: EdgeInsets.fromLTRB(20, 0, 20, 8), child: Text('Album cover', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800))),
            SizedBox(
              height: 110,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                children: [
                  for (final s in chosen)
                    GestureDetector(
                      onTap: () => Navigator.pop(ctx, s.photoUrl),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        child: Container(
                          width: 84,
                          height: 84,
                          padding: const EdgeInsets.all(2),
                          decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: _cover == s.photoUrl ? AppColors.brand : AppColors.border, width: 2)),
                          child: ClipOval(child: Image.network(s.photoUrl, fit: BoxFit.cover)),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
    if (url != null) setState(() => _cover = url);
  }

  Future<void> _save() async {
    FocusScope.of(context).unfocus();
    setState(() => _busy = true);
    try {
      await ref.read(socialActionsProvider).saveAlbum(id: widget.albumId, name: _name.text, coverUrl: _cover, storyIds: List.of(_selected));
      if (mounted) context.pop();
    } catch (e) {
      if (mounted) _snack(friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete this album?'),
        content: const Text('The moments themselves stay. Only the album goes.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete', style: TextStyle(color: AppColors.danger))),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(socialActionsProvider).deleteAlbum(widget.albumId!);
      if (mounted) context.pop();
    } catch (e) {
      if (mounted) _snack(friendlyError(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final me = ref.watch(currentUserIdProvider);
    if (me == null) return const Scaffold();
    final mine = ref.watch(myMomentsArchiveProvider);
    final album = _editing ? ref.watch(albumProvider(widget.albumId!)).value : null;
    final inAlbum = _editing ? (ref.watch(albumMomentsProvider(widget.albumId!)).value ?? const <Story>[]) : const <Story>[];

    // Prefill once when editing.
    if (_editing && !_loaded && album != null && (inAlbum.isNotEmpty || album.count == 0)) {
      _loaded = true;
      _name.text = album.name;
      _cover = album.coverUrl;
      _selected.addAll(inAlbum.map((s) => s.id));
    }

    // Everything I can put in: my moments plus whatever is already in the album (may be expired).
    final all = <String, Story>{for (final s in inAlbum) s.id: s, for (final s in (mine.value ?? const <Story>[])) s.id: s}.values.toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    if (!_editing && !_loaded && widget.preselect != null && all.isNotEmpty) {
      _loaded = true;
      final pre = all.where((s) => s.id == widget.preselect).firstOrNull;
      if (pre != null && !_selected.contains(pre.id)) {
        _selected.add(pre.id);
        _cover ??= pre.photoUrl;
        if (_name.text.trim().isEmpty && pre.whereLabel != null) _name.text = pre.whereLabel!;
      }
    }

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(AppIcons.x), onPressed: _busy ? null : () => context.pop()),
        title: Text(_editing ? 'Edit album' : 'New album'),
        actions: [
          _busy
              ? const Padding(padding: EdgeInsets.only(right: 20), child: Center(child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))))
              : TextButton(onPressed: _save, child: const Text('Save')),
        ],
      ),
      body: mine.when(
        loading: () => const Center(child: CircularProgressIndicator(strokeWidth: 2)),
        error: (e, _) => Center(child: Text(friendlyError(e))),
        data: (_) => ListView(
          padding: const EdgeInsets.only(bottom: 32),
          children: [
            const SizedBox(height: 16),
            Center(
              child: GestureDetector(
                onTap: () => _pickCover(all),
                child: Column(
                  children: [
                    Container(
                      width: 92,
                      height: 92,
                      padding: const EdgeInsets.all(3),
                      decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: AppColors.textPrimary, width: 1.5)),
                      child: ClipOval(
                        child: _cover == null
                            ? ColoredBox(color: AppColors.surfaceGray, child: Icon(AppIcons.image, size: 28, color: AppColors.textSecondary))
                            : Image.network(_cover!, fit: BoxFit.cover),
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text('Change cover', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.brand)),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: TextField(
                controller: _name,
                maxLength: 30,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Album name', hintText: 'e.g. Ulu Yam runs', counterText: ''),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 18, 16, 8),
              child: Row(
                children: [
                  Text('PICK MOMENTS', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 1, color: AppColors.textSecondary)),
                  const Spacer(),
                  Text('${_selected.length} selected', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.brand)),
                ],
              ),
            ),
            if (all.isEmpty)
              const EmptyState(art: AppArt.camera, title: 'No moments yet', subtitle: 'Snap one at a meet or a spot, then come back to make an album.')
            else
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                padding: const EdgeInsets.symmetric(horizontal: 2),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, mainAxisSpacing: 2, crossAxisSpacing: 2, childAspectRatio: 0.8),
                itemCount: all.length,
                itemBuilder: (_, i) {
                  final s = all[i];
                  final idx = _selected.indexOf(s.id);
                  final on = idx >= 0;
                  return GestureDetector(
                    onTap: () => _toggle(s),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        Image.network(s.photoUrl, fit: BoxFit.cover, errorBuilder: (_, _, _) => ColoredBox(color: AppColors.surfaceGray)),
                        if (on) const DecoratedBox(decoration: BoxDecoration(color: Color(0x33000000))),
                        Positioned(
                          right: 6,
                          top: 6,
                          child: Container(
                            width: 24,
                            height: 24,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: on ? AppColors.brand : Colors.black38,
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 1.5),
                            ),
                            child: on ? Text('${idx + 1}', style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800)) : null,
                          ),
                        ),
                        if (s.whereLabel != null)
                          Positioned(
                            left: 6,
                            right: 6,
                            bottom: 6,
                            child: Text(s.whereLabel!, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 10.5, fontWeight: FontWeight.w700, shadows: [Shadow(blurRadius: 6, color: Colors.black)])),
                          ),
                      ],
                    ),
                  );
                },
              ),
            if (_editing) ...[
              const SizedBox(height: 24),
              Center(child: TextButton(onPressed: _busy ? null : _delete, child: const Text('Delete album', style: TextStyle(color: AppColors.danger, fontWeight: FontWeight.w700)))),
            ],
          ],
        ),
      ),
    );
  }
}
