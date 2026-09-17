import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/supabase/supabase_client.dart';
import '../../../core/theme/app_art.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/dates.dart';
import '../../events/application/my_events_provider.dart';
import '../../profile/application/profile_providers.dart';
import '../application/community_providers.dart';

/// Sticker keys → art. Sent as the key, drawn from [AppArt] on both ends.
const kStickers = <String, String>{
  'car': AppArt.car,
  'racing': AppArt.racing,
  'coffee': AppArt.coffee,
  'flag': AppArt.flag,
  'fire': AppArt.fire,
  'thumbsUp': AppArt.thumbsUp,
  'wave': AppArt.wave,
  'party': AppArt.party,
  'cool': AppArt.cool,
  'handshake': AppArt.handshake,
  'trophy': AppArt.trophy,
  'heartYellow': AppArt.heartYellow,
  'rocket': AppArt.rocket,
  'sparkles': AppArt.sparkles,
  'confetti': AppArt.confetti,
  'road': AppArt.road,
  'night': AppArt.night,
  'fuel': AppArt.fuel,
  'wrench': AppArt.wrench,
  'police': AppArt.police,
};

/// Pick a sticker. Returns its key.
Future<String?> showStickerSheet(BuildContext context) {
  return showModalBottomSheet<String>(
    useRootNavigator: true, // above the shell tab bar
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Stickers', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
            const SizedBox(height: 12),
            GridView.count(
              crossAxisCount: 5,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              children: [
                for (final e in kStickers.entries)
                  InkWell(
                    onTap: () => Navigator.pop(ctx, e.key),
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      decoration: BoxDecoration(color: AppColors.surfaceGray, borderRadius: BorderRadius.circular(12)),
                      child: Center(child: ArtIcon(e.value, size: 40)),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

/// What "+" attaches: one of my meets, a spot, or one of my cars.
class ChatAttachment {
  const ChatAttachment({this.eventId, this.placeId, this.carId});
  final String? eventId;
  final String? placeId;
  final String? carId;
}

Future<ChatAttachment?> showAttachSheet(BuildContext context, {int initialTab = 0}) {
  return showModalBottomSheet<ChatAttachment>(
    useRootNavigator: true, // above the shell tab bar
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (_) => _AttachSheet(initialTab: initialTab),
  );
}

class _AttachSheet extends ConsumerStatefulWidget {
  const _AttachSheet({this.initialTab = 0});
  final int initialTab;
  @override
  ConsumerState<_AttachSheet> createState() => _AttachSheetState();
}

class _AttachSheetState extends ConsumerState<_AttachSheet> {
  late int _tab = widget.initialTab;

  @override
  Widget build(BuildContext context) {
    final me = ref.watch(currentUserIdProvider);
    final events = ref.watch(myEventsProvider).value;
    final spots = ref.watch(topSpotsProvider).value ?? const [];
    final cars = me == null ? null : ref.watch(userCarsProvider(me)).value;
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.6,
        child: Column(
          children: [
            const Padding(padding: EdgeInsets.fromLTRB(20, 0, 20, 8), child: Text('Attach', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800))),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  _Pill(label: 'Meet', icon: AppIcons.flagCheckered, on: _tab == 0, onTap: () => setState(() => _tab = 0)),
                  const SizedBox(width: 8),
                  _Pill(label: 'Spot', icon: AppIcons.mapPin, on: _tab == 1, onTap: () => setState(() => _tab = 1)),
                  const SizedBox(width: 8),
                  _Pill(label: 'My car', icon: AppIcons.car, on: _tab == 2, onTap: () => setState(() => _tab = 2)),
                ],
              ),
            ),
            const SizedBox(height: 6),
            Expanded(
              child: switch (_tab) {
                0 => events == null
                    ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
                    : [...events.upcoming, ...events.past].isEmpty
                        ? const _Empty('No meets yet. Join or plan one first.')
                        : ListView(
                            children: [
                              for (final e in [...events.upcoming, ...events.past.take(10)])
                                ListTile(
                                  leading: ClipRRect(
                                    borderRadius: BorderRadius.circular(10),
                                    child: SizedBox(width: 48, height: 48, child: e.coverUrl == null ? ColoredBox(color: AppColors.surfaceGray, child: Center(child: ArtIcon(e.type.art, size: 26))) : Image.network(e.coverUrl!, fit: BoxFit.cover)),
                                  ),
                                  title: Text(e.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
                                  subtitle: Text('${formatEventDate(e.startsAt)} · ${e.venueName}', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                                  onTap: () => Navigator.pop(context, ChatAttachment(eventId: e.id)),
                                ),
                            ],
                          ),
                1 => spots.isEmpty
                    ? const _Empty('No spots to share yet.')
                    : ListView(
                        children: [
                          for (final p in spots)
                            ListTile(
                              leading: ClipRRect(
                                borderRadius: BorderRadius.circular(10),
                                child: SizedBox(width: 48, height: 48, child: p.coverUrl == null ? ColoredBox(color: AppColors.surfaceGray, child: Center(child: ArtIcon(p.kindArt, size: 26))) : Image.network(p.coverUrl!, fit: BoxFit.cover)),
                              ),
                              title: Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
                              subtitle: Text(p.kindLabel, style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                              onTap: () => Navigator.pop(context, ChatAttachment(placeId: p.id)),
                            ),
                        ],
                      ),
                _ => cars == null
                    ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
                    : cars.isEmpty
                        ? const _Empty('No car in your garage yet.')
                        : ListView(
                            children: [
                              for (final c in cars)
                                ListTile(
                                  leading: ClipRRect(
                                    borderRadius: BorderRadius.circular(10),
                                    child: SizedBox(width: 48, height: 48, child: c.cover == null ? ColoredBox(color: AppColors.surfaceGray, child: Center(child: ArtIcon(AppArt.car, size: 26))) : Image.network(c.cover!, fit: BoxFit.cover)),
                                  ),
                                  title: Text('${c.make} ${c.model}', style: const TextStyle(fontWeight: FontWeight.w600)),
                                  subtitle: Text(c.year?.toString() ?? 'Garage', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                                  onTap: () => Navigator.pop(context, ChatAttachment(carId: c.id)),
                                ),
                            ],
                          ),
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(text, textAlign: TextAlign.center, style: TextStyle(color: AppColors.textSecondary))));
}

class _Pill extends StatelessWidget {
  const _Pill({required this.label, required this.icon, required this.on, required this.onTap});
  final String label;
  final IconData icon;
  final bool on;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(color: on ? AppColors.ink : AppColors.surfaceGray, borderRadius: BorderRadius.circular(999)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 14, color: on ? Colors.white : AppColors.textPrimary),
            const SizedBox(width: 6),
            Text(label, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: on ? Colors.white : AppColors.textPrimary)),
          ]),
        ),
      );
}
