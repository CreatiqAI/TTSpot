import 'package:flutter/material.dart';

import '../../../core/theme/app_art.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/glass.dart';

// Chat stickers. A sticker message stores only its key (messages.sticker) and
// both phones draw the art from the app bundle. Keys are forever: old
// messages keep pointing at them, so never rename or drop a shipped key (move
// it to the legacy map instead). Art and captions come from
// tool/art_stickers.py, which writes assets/stickers/<pack>/<key>.webp.

/// One tab in the sticker picker.
class StickerPack {
  const StickerPack({required this.id, required this.label, required this.keys});
  final String id;
  final String label;
  final List<String> keys;

  String asset(String key) => 'assets/stickers/$id/$key.webp';
}

const kStickerPacks = <StickerPack>[
  StickerPack(id: 'titi', label: 'TiTi', keys: [
    'titi_yo', 'titi_otw', 'titi_jomtt', 'titi_steady', 'titi_shiok', 'titi_paiseh', //
    'titi_waitme', 'titi_siap', 'titi_mamak', 'titi_niceride', 'titi_tido', 'titi_loveit',
    'titi_whereyou', 'titi_letsgo', 'titi_modtime', 'titi_hahaha', 'titi_terbaik', 'titi_gg',
  ]),
  StickerPack(id: 'car', label: 'Car talk', keys: [
    'car_vroom', 'car_tehtarik', 'car_fulltank', 'car_drift', 'car_parking', //
    'car_turbo', 'car_needwash', 'car_slowlah', 'car_jam',
  ]),
];

/// The first emoji-art stickers (until 0.3.44). No longer in the picker, but
/// messages sent with them still draw.
const kLegacyStickers = <String, String>{
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

/// The bundled art for [key], or null for a legacy (or unknown) key.
String? stickerAsset(String key) {
  for (final p in kStickerPacks) {
    if (p.keys.contains(key)) return p.asset(key);
  }
  return null;
}

/// A sticker as it sits in the chat: big, no bubble. Legacy keys draw their
/// emoji art; a key from a newer app version than this one draws the car.
class ChatSticker extends StatelessWidget {
  const ChatSticker(this.stickerKey, {super.key, this.size = 130});
  final String stickerKey;
  final double size;

  @override
  Widget build(BuildContext context) {
    final asset = stickerAsset(stickerKey);
    if (asset == null) return ArtIcon(kLegacyStickers[stickerKey] ?? AppArt.car, size: size * 0.74);
    return Image.asset(
      asset,
      width: size,
      height: size,
      cacheWidth: (size * MediaQuery.devicePixelRatioOf(context)).round(),
      semanticLabel: 'Sticker',
      errorBuilder: (_, _, _) => ArtIcon(AppArt.car, size: size * 0.74),
    );
  }
}

/// Pick a sticker: one tab per pack, swipe or tap between them. Returns its key.
Future<String?> showStickerSheet(BuildContext context) {
  return showModalBottomSheet<String>(
    useRootNavigator: true, // above the shell tab bar
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (_) => const _StickerSheet(),
  );
}

class _StickerSheet extends StatefulWidget {
  const _StickerSheet();

  @override
  State<_StickerSheet> createState() => _StickerSheetState();
}

class _StickerSheetState extends State<_StickerSheet> {
  // The pack you last picked from opens first next time (for this app run).
  static int _lastPack = 0;
  late final _pages = PageController(initialPage: _lastPack);
  late int _pack = _lastPack;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  void _goTo(int i) {
    setState(() => _pack = i);
    _pages.animateToPage(i, duration: const Duration(milliseconds: 260), curve: Curves.easeOutCubic);
  }

  @override
  Widget build(BuildContext context) {
    // Four to a row: decode each at about its size on screen.
    final cell = (MediaQuery.sizeOf(context).width / 4 * MediaQuery.devicePixelRatioOf(context)).round().clamp(64, 512);
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.58,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, 10),
              child: Text('Stickers', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
            ),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  for (var i = 0; i < kStickerPacks.length; i++) ...[
                    if (i > 0) const SizedBox(width: 8),
                    _PackTab(pack: kStickerPacks[i], on: _pack == i, onTap: () => _goTo(i)),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: PageView(
                controller: _pages,
                onPageChanged: (i) => setState(() => _pack = i),
                children: [
                  for (final p in kStickerPacks)
                    GridView.builder(
                      padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 4, mainAxisSpacing: 4, crossAxisSpacing: 4),
                      itemCount: p.keys.length,
                      itemBuilder: (ctx, i) {
                        final key = p.keys[i];
                        return PressScale(
                          scale: 0.9,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(14),
                            onTap: () {
                              _lastPack = kStickerPacks.indexOf(p);
                              Navigator.pop(context, key);
                            },
                            child: Padding(
                              padding: const EdgeInsets.all(4),
                              child: Image.asset(p.asset(key), fit: BoxFit.contain, cacheWidth: cell, semanticLabel: key),
                            ),
                          ),
                        );
                      },
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A pack's tab: its first sticker as the icon, then the name.
class _PackTab extends StatelessWidget {
  const _PackTab({required this.pack, required this.on, required this.onTap});
  final StickerPack pack;
  final bool on;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => PressScale(
        child: GestureDetector(
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            padding: const EdgeInsets.fromLTRB(6, 5, 14, 5),
            decoration: BoxDecoration(color: on ? AppColors.textPrimary : AppColors.surfaceGray, borderRadius: BorderRadius.circular(999)),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Image.asset(pack.asset(pack.keys.first), width: 26, height: 26, cacheWidth: 96),
                const SizedBox(width: 6),
                Text(pack.label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: on ? AppColors.onInk : AppColors.textPrimary)),
              ],
            ),
          ),
        ),
      );
}
