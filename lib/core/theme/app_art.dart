import 'package:flutter/material.dart';

/// Illustrated 3D icons (Microsoft Fluent Emoji, MIT). Used wherever the app
/// used to draw an emoji: event types, place kinds, badges, empty states, the
/// create hub, and map pins. Files live in assets/art/ as 256 px PNGs.
abstract final class AppArt {
  static const _dir = 'assets/art';

  static const car = '$_dir/car.png';
  static const suv = '$_dir/suv.png';
  static const racing = '$_dir/racing.png';
  static const coffee = '$_dir/coffee.png';
  static const road = '$_dir/road.png';
  static const flag = '$_dir/flag.png';
  static const heartYellow = '$_dir/heart_yellow.png';
  static const trophy = '$_dir/trophy.png';
  static const parking = '$_dir/parking.png';
  static const mall = '$_dir/mall.png';
  static const pin = '$_dir/pin.png';
  static const camera = '$_dir/camera.png';
  static const eyes = '$_dir/eyes.png';
  static const chart = '$_dir/chart.png';
  static const map = '$_dir/map.png';
  static const stopwatch = '$_dir/stopwatch.png';
  static const shield = '$_dir/shield.png';
  static const fire = '$_dir/fire.png';
  static const ghost = '$_dir/ghost.png';
  static const hug = '$_dir/hug.png';
  static const repeat = '$_dir/repeat.png';
  static const megaphone = '$_dir/megaphone.png';
  static const star = '$_dir/star.png';
  static const party = '$_dir/party.png';
  static const sparkles = '$_dir/sparkles.png';
  static const redDot = '$_dir/red_dot.png';
  static const alarm = '$_dir/alarm.png';
  static const speech = '$_dir/speech.png';
  static const calendar = '$_dir/calendar.png';
  static const bell = '$_dir/bell.png';
  static const bookmark = '$_dir/bookmark.png';
  static const search = '$_dir/search.png';
  static const picture = '$_dir/picture.png';
  static const wrench = '$_dir/wrench.png';
  static const rocket = '$_dir/rocket.png';
  static const wave = '$_dir/wave.png';
  static const handshake = '$_dir/handshake.png';
  static const night = '$_dir/night.png';
  static const compass = '$_dir/compass.png';
  static const locked = '$_dir/locked.png';
  static const thumbsUp = '$_dir/thumbs_up.png';
  static const prohibited = '$_dir/wifi_off.png';
  static const cityscape = '$_dir/cityscape.png';
  static const tools = '$_dir/wrench2.png';
  static const gear = '$_dir/gear.png';
  static const confetti = '$_dir/tada.png';
  static const medal = '$_dir/medal.png';
  static const firstPlace = '$_dir/first.png';
  static const police = '$_dir/police.png';
  static const fuel = '$_dir/fuel.png';
  static const cool = '$_dir/cool.png';
  static const mailbox = '$_dir/mailbox.png';
  static const check = '$_dir/check.png';

  /// Badges and other server-driven content still carry an emoji character;
  /// this turns it into the matching 3D art (null when we have no match).
  static String? forEmoji(String? emoji) {
    if (emoji == null) return null;
    return switch (emoji.replaceAll('️', '')) {
      '🚗' => car,
      '🚙' => suv,
      '🏎' => racing,
      '☕' => coffee,
      '🛣' => road,
      '🏁' => flag,
      '💛' => heartYellow,
      '🏆' => trophy,
      '🅿' => parking,
      '🏬' => mall,
      '📍' => pin,
      '📸' => camera,
      '📷' => camera,
      '👀' => eyes,
      '📊' => chart,
      '🗺' => map,
      '⏱' => stopwatch,
      '🛡' => shield,
      '🔥' => fire,
      '👻' => ghost,
      '🫂' => hug,
      '🔁' => repeat,
      '📣' => megaphone,
      '⭐' => star,
      '🎉' => party,
      '✨' => sparkles,
      '🔴' => redDot,
      '⏰' => alarm,
      '💬' => speech,
      '📅' => calendar,
      '🔔' => bell,
      '🔖' => bookmark,
      '🔍' => search,
      '🖼' => picture,
      '🔧' => wrench,
      '🚀' => rocket,
      '👋' => wave,
      '🤝' => handshake,
      '🌃' => night,
      '🧭' => compass,
      '🔒' => locked,
      '👍' => thumbsUp,
      '🚫' => prohibited,
      '🌆' => cityscape,
      '🛠' => tools,
      '⚙' => gear,
      '🎊' => confetti,
      '🏅' => medal,
      '🥇' => firstPlace,
      '🚨' => police,
      '⛽' => fuel,
      '😎' => cool,
      '📩' => mailbox,
      '✅' => check,
      _ => null,
    };
  }
}

/// One piece of 3D art at a given size. Falls back to the emoji text when the
/// asset is unknown, so server-driven badges never render blank.
class ArtIcon extends StatelessWidget {
  const ArtIcon(this.asset, {super.key, this.size = 24, this.emojiFallback});

  /// Convenience: pick the art for an emoji character, or draw the emoji.
  ArtIcon.emoji(String emoji, {super.key, this.size = 24})
      : asset = AppArt.forEmoji(emoji),
        emojiFallback = emoji;

  final String? asset;
  final double size;
  final String? emojiFallback;

  @override
  Widget build(BuildContext context) {
    if (asset == null) {
      return SizedBox(
        width: size,
        height: size,
        child: Center(child: Text(emojiFallback ?? '', style: TextStyle(fontSize: size * 0.8))),
      );
    }
    return Image.asset(
      asset!,
      width: size,
      height: size,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.medium,
      cacheWidth: (size * MediaQuery.devicePixelRatioOf(context)).round().clamp(32, 256),
    );
  }
}
