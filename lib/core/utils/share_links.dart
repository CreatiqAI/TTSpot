import 'package:share_plus/share_plus.dart';

/// Public link to something in the app. The landing page (docs/m.html on
/// GitHub Pages) opens TT Spot when installed and offers the download
/// otherwise. When ttspot.my serves the app-link files (tool/app-links),
/// switch this to `https://www.ttspot.my/<type>/<id>` and the links open the
/// app directly.
String shareLink(String type, String id) => 'https://creatiqai.github.io/TTSpot/m.html?t=$type&id=$id';

/// Native share sheet (WhatsApp, Telegram, Instagram DM, copy…).
Future<void> shareThing({required String type, required String id, required String text}) =>
    SharePlus.instance.share(ShareParams(text: '$text\n${shareLink(type, id)}'));
