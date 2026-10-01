import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_icons.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/friendly_error.dart';
import '../../../../core/widgets/primary_button.dart';
import '../../../settings/application/settings_providers.dart';

/// The backgrounds a chat's messages can sit on, WhatsApp style. One choice
/// for every chat, saved as `chat_wallpaper` in profiles.settings and picked
/// in Settings > Appearance or on any chat's info page. Each has a light and a
/// dark picture (art: tool/art_wallpapers.py, preview: design/wallpapers/sheet.jpg).
enum ChatWallpaper {
  titi('TiTi'),
  ttspot('TT Spot'),
  night('Night drive');

  const ChatWallpaper(this.label);
  final String label;

  /// What a member who never picked one sees (an unset `chat_wallpaper`).
  static const fallback = titi;

  static ChatWallpaper fromId(String id) => values.firstWhere((w) => w.name == id, orElse: () => fallback);

  String get id => name;

  String asset({required bool dark}) => 'assets/wallpapers/${name}_${dark ? 'dark' : 'light'}.webp';

  /// The doodle tiles repeat; Night drive is one tall picture.
  bool get tiled => this != night;

  /// Painted under the picture (and while it loads), close to its average colour.
  Color ground({required bool dark}) => switch (this) {
        ttspot => dark ? const Color(0xFF0C0E12) : const Color(0xFFEDE9E3),
        night => dark ? const Color(0xFF0D0F1C) : const Color(0xFF5B5577),
        titi => dark ? const Color(0xFF161218) : const Color(0xFFFCEEE9),
      };

  /// Tiles are 768 px, shown [tileWidth] logical px wide (about one phone
  /// width in a chat). Everything is pinned to the bottom, so the background
  /// moves with the messages when the keyboard opens; Night drive's red glow
  /// sits on the composer.
  DecorationImage image({required bool dark, double tileWidth = 384}) => DecorationImage(
        image: AssetImage(asset(dark: dark)),
        repeat: tiled ? ImageRepeat.repeat : ImageRepeat.noRepeat,
        scale: tiled ? 768 / tileWidth : 1,
        fit: tiled ? null : BoxFit.cover,
        alignment: tiled ? Alignment.bottomLeft : Alignment.bottomCenter,
        filterQuality: FilterQuality.medium,
      );
}

/// Colours for what sits on a wallpaper: bubble fills, the "Today" chip and
/// the time under stickers and cards, sender names over bubbles. Read with
/// [ChatWallpaperStyle.of]; outside a chat it's the app's plain look.
/// Mirrors STYLE in tool/art_wallpapers.py; change both together.
class ChatWallpaperStyle {
  const ChatWallpaperStyle({
    required this.mineFill,
    required this.theirsFill,
    required this.theirsEdge,
    required this.chipFill,
    required this.chipText,
    required this.label,
  });

  final Color mineFill;
  final Color theirsFill;
  /// Outline of the other side's bubbles; null for none.
  final Color? theirsEdge;
  final Color chipFill;
  final Color chipText;
  final Color label;

  Color bubbleFill(bool mine) => mine ? mineFill : theirsFill;
  BoxBorder? bubbleBorder(bool mine) => mine || theirsEdge == null ? null : Border.all(color: theirsEdge!);

  /// Light mode's own bubbles: a cool grey that stands off the warm grounds.
  static const _lightMine = Color(0xFFE1E4EA);

  /// No wallpaper: plain bubbles on the plain ground.
  static ChatWallpaperStyle get plain => ChatWallpaperStyle(
        mineFill: AppColors.surfaceGray,
        theirsFill: AppColors.surface,
        theirsEdge: AppColors.border,
        chipFill: AppColors.surfaceGray,
        chipText: AppColors.textSecondary,
        label: AppColors.textSecondary,
      );

  static ChatWallpaperStyle forWallpaper(ChatWallpaper w) {
    final dark = AppColors.dark;
    if (w == ChatWallpaper.night) {
      // Light bubbles read on the dusk as they are; the dark ones get a stronger fill and edge.
      return dark
          ? const ChatWallpaperStyle(
              mineFill: Color(0xFF2B2F39),
              theirsFill: Color(0xFF1E212A),
              theirsEdge: Color(0xFF383D48),
              chipFill: Color(0x6E000000),
              chipText: Color(0xFFE1E4E9),
              label: Color(0xFFC9CDD4),
            )
          : const ChatWallpaperStyle(
              mineFill: _lightMine,
              theirsFill: Colors.white,
              theirsEdge: null,
              chipFill: Color(0x5C000000),
              chipText: Colors.white,
              label: Color(0xE6FFFFFF),
            );
    }
    return dark
        ? ChatWallpaperStyle(
            mineFill: AppColors.surfaceGray,
            theirsFill: AppColors.surface,
            theirsEdge: AppColors.border,
            chipFill: AppColors.surface.withValues(alpha: 0.88),
            chipText: const Color(0xFFAAB0B8),
            label: AppColors.textSecondary,
          )
        : ChatWallpaperStyle(
            mineFill: _lightMine,
            theirsFill: Colors.white,
            theirsEdge: AppColors.border,
            chipFill: Colors.white.withValues(alpha: 0.86),
            chipText: const Color(0xFF626262),
            label: const Color(0xFF626262),
          );
  }

  static ChatWallpaperStyle of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<_Scope>()?.style ?? plain;
}

class _Scope extends InheritedWidget {
  _Scope({required this.wallpaper, required this.dark, required super.child}) : style = ChatWallpaperStyle.forWallpaper(wallpaper);
  final ChatWallpaper wallpaper;
  final bool dark;
  final ChatWallpaperStyle style;

  @override
  bool updateShouldNotify(_Scope old) => old.wallpaper != wallpaper || old.dark != dark;
}

/// The chosen wallpaper behind a chat's message list, following light / dark,
/// with the matching bubble colours handed down to everything on it.
class ChatWallpaperBackground extends ConsumerWidget {
  const ChatWallpaperBackground({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final w = ChatWallpaper.fromId(ref.watch(settingsProvider.select((s) => s.chatWallpaper)));
    final dark = AppColors.dark;
    return DecoratedBox(
      decoration: BoxDecoration(color: w.ground(dark: dark), image: w.image(dark: dark)),
      child: _Scope(wallpaper: w, dark: dark, child: child),
    );
  }
}

/// A soft card for text that would otherwise sit straight on the wallpaper
/// (an empty chat's "Say hi", a load error).
class ChatWallpaperPanel extends StatelessWidget {
  const ChatWallpaperPanel({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 18),
        decoration: BoxDecoration(color: AppColors.surface.withValues(alpha: 0.94), borderRadius: BorderRadius.circular(20)),
        child: child,
      );
}

/// "Chat background" on a chat's info page: the same choice as in Settings.
class ChatWallpaperTile extends ConsumerWidget {
  const ChatWallpaperTile({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final w = ChatWallpaper.fromId(ref.watch(settingsProvider.select((s) => s.chatWallpaper)));
    return ListTile(
      leading: Icon(AppIcons.image, color: AppColors.textPrimary),
      title: const Text('Chat background', style: TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text('${w.label} · the same in all your chats', style: const TextStyle(fontSize: 12)),
      trailing: Icon(AppIcons.caretRight, size: 16, color: AppColors.textMuted),
      onTap: () => showChatWallpaperPicker(context),
    );
  }
}

/// Pick the chat background: three phone-shaped previews, tap one to use it.
Future<void> showChatWallpaperPicker(BuildContext context) => showModalBottomSheet<void>(
      useRootNavigator: true, // above the shell tab bar
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => const _Picker(),
    );

class _Picker extends ConsumerWidget {
  const _Picker();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ChatWallpaper.fromId(ref.watch(settingsProvider.select((s) => s.chatWallpaper)));

    Future<void> pick(ChatWallpaper w) async {
      if (w == current) return;
      try {
        await ref.read(settingsActionsProvider).patch({'chat_wallpaper': w.id});
      } catch (e) {
        if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e))));
      }
    }

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Chat background', textAlign: TextAlign.center, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text('Sits behind the messages in all your chats.', textAlign: TextAlign.center, style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary)),
            const SizedBox(height: 16),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final (i, w) in ChatWallpaper.values.indexed) ...[
                  if (i > 0) const SizedBox(width: 10),
                  Expanded(child: _Option(wallpaper: w, selected: w == current, onTap: () => pick(w))),
                ],
              ],
            ),
            const SizedBox(height: 18),
            PrimaryButton(label: 'Done', onPressed: () => Navigator.pop(context)),
          ],
        ),
      ),
    );
  }
}

class _Option extends StatelessWidget {
  const _Option({required this.wallpaper, required this.selected, required this.onTap});
  final ChatWallpaper wallpaper;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        selected: selected,
        label: '${wallpaper.label} chat background',
        excludeSemantics: true,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Column(
            children: [
              AspectRatio(
                aspectRatio: 9 / 16,
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        padding: EdgeInsets.all(selected ? 3 : 1),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: selected ? AppColors.brand : AppColors.border, width: selected ? 2.5 : 1),
                        ),
                        child: ClipRRect(borderRadius: BorderRadius.circular(selected ? 13 : 16), child: _PhonePreview(wallpaper)),
                      ),
                    ),
                    if (selected)
                      Positioned(
                        top: 8,
                        right: 8,
                        child: Container(
                          width: 24,
                          height: 24,
                          decoration: BoxDecoration(color: AppColors.brand, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 2)),
                          child: const Icon(AppIcons.check, size: 13, color: Colors.white),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Text(
                wallpaper.label,
                textAlign: TextAlign.center,
                maxLines: 2,
                style: TextStyle(fontSize: 13.5, fontWeight: selected ? FontWeight.w800 : FontWeight.w600, color: selected ? AppColors.textPrimary : AppColors.textSecondary),
              ),
              if (wallpaper == ChatWallpaper.fallback) Text('Default', textAlign: TextAlign.center, style: TextStyle(fontSize: 11.5, color: AppColors.textMuted)),
            ],
          ),
        ),
      );
}

/// A tiny chat on the wallpaper: app bar, a day chip, two bubbles each way, composer.
/// Drawn to scale with the card, so its text ignores the phone's text size.
class _PhonePreview extends StatelessWidget {
  const _PhonePreview(this.wallpaper);
  final ChatWallpaper wallpaper;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, c) {
          final w = c.maxWidth;
          final dark = AppColors.dark;
          final st = ChatWallpaperStyle.forWallpaper(wallpaper);
          final fs = w * 0.075;
          final bar = w * 0.17;

          Widget line(double width, Color color) => Container(
                width: width,
                height: fs * 0.55,
                decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(fs)),
              );

          Widget bubble(String text, {required bool mine}) => Align(
                alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
                child: Container(
                  margin: EdgeInsets.only(top: fs * 0.45),
                  padding: EdgeInsets.symmetric(horizontal: fs * 0.75, vertical: fs * 0.4),
                  decoration: BoxDecoration(
                    color: st.bubbleFill(mine),
                    border: st.bubbleBorder(mine),
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(fs),
                      topRight: Radius.circular(fs),
                      bottomLeft: Radius.circular(mine ? fs : fs * 0.25),
                      bottomRight: Radius.circular(mine ? fs * 0.25 : fs),
                    ),
                  ),
                  child: Text(text, maxLines: 1, softWrap: false, overflow: TextOverflow.clip, style: TextStyle(fontSize: fs, height: 1.2, color: AppColors.textPrimary)),
                ),
              );

          return MediaQuery.withNoTextScaling(
            child: Column(
              children: [
                Container(
                  height: bar,
                  padding: EdgeInsets.symmetric(horizontal: w * 0.07),
                  decoration: BoxDecoration(color: AppColors.bg, border: Border(bottom: BorderSide(color: AppColors.border, width: 0.5))),
                  child: Row(
                    children: [
                      Container(width: bar * 0.48, height: bar * 0.48, decoration: const BoxDecoration(color: AppColors.brand, shape: BoxShape.circle)),
                      SizedBox(width: w * 0.05),
                      Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [line(w * 0.36, AppColors.textPrimary.withValues(alpha: 0.75)), SizedBox(height: fs * 0.3), line(w * 0.24, AppColors.textMuted)],
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: DecoratedBox(
                    decoration: BoxDecoration(color: wallpaper.ground(dark: dark), image: wallpaper.image(dark: dark, tileWidth: w * 1.3)),
                    child: Stack(
                      children: [
                        Positioned(
                          left: w * 0.06,
                          right: w * 0.06,
                          bottom: w * 0.07,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Center(
                                child: Container(
                                  padding: EdgeInsets.symmetric(horizontal: fs * 0.7, vertical: fs * 0.2),
                                  decoration: BoxDecoration(color: st.chipFill, borderRadius: BorderRadius.circular(fs)),
                                  child: Text('Today', maxLines: 1, softWrap: false, style: TextStyle(fontSize: fs * 0.8, fontWeight: FontWeight.w600, color: st.chipText)),
                                ),
                              ),
                              SizedBox(height: fs * 0.3),
                              bubble('Jom TT?', mine: false),
                              bubble('Usual spot', mine: false),
                              bubble('Otw, 10 min', mine: true),
                              bubble('Steady bos', mine: true),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Container(
                  height: bar,
                  padding: EdgeInsets.symmetric(horizontal: w * 0.06, vertical: bar * 0.22),
                  decoration: BoxDecoration(color: AppColors.bg, border: Border(top: BorderSide(color: AppColors.border, width: 0.5))),
                  child: Row(
                    children: [
                      Expanded(child: Container(decoration: BoxDecoration(color: AppColors.surfaceRaised, border: Border.all(color: AppColors.border, width: 0.5), borderRadius: BorderRadius.circular(bar)))),
                      SizedBox(width: w * 0.04),
                      AspectRatio(aspectRatio: 1, child: Container(decoration: const BoxDecoration(color: AppColors.brand, shape: BoxShape.circle))),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      );
}
