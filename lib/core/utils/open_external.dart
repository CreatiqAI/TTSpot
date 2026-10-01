import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../theme/app_theme.dart';
import '../widgets/primary_button.dart';

/// Opens another app (WhatsApp, the dialler, a map) or a web page. Directions
/// go through `openDirections` in core/directions/directions.dart instead.
///
/// Pass [appName] to ask first ("Open WhatsApp?") so nobody leaves TT Spot by
/// accident; Cancel does nothing. When the app is installed we hand off once
/// and stop. The browser fallback is only for phones without the app.
Future<void> openExternal(BuildContext context, String url, {String? fallbackUrl, String? appName}) async {
  if (appName != null) {
    final ok = await confirmSheet(context, title: 'Open $appName?', body: 'This leaves TT Spot and opens $appName.', confirm: 'Open $appName');
    if (!ok || !context.mounted) return;
  }

  final uri = Uri.parse(url);
  final isAppScheme = !uri.scheme.startsWith('http');

  if (isAppScheme) {
    var installed = false;
    try {
      installed = await canLaunchUrl(uri);
    } catch (_) {}
    if (installed) {
      try {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } catch (_) {}
      return;
    }
    if (fallbackUrl == null) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${appName ?? 'That app'} isn\'t installed.')));
      return;
    }
    url = fallbackUrl;
  }

  try {
    if (await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication)) return;
  } catch (_) {}
  if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Couldn\'t open that link.')));
}

String wazeUrl(double lat, double lng) => 'https://waze.com/ul?ll=$lat,$lng&navigate=yes';
String whatsappUrl(String text) => 'https://wa.me/?text=${Uri.encodeComponent(text)}';


/// Bottom-sheet confirmation: title, one line, then Cancel (grey) and the
/// action (red) side by side. Returns true when confirmed.
Future<bool> confirmSheet(BuildContext context, {required String title, String? body, String confirm = 'OK', String cancel = 'Cancel', IconData? icon}) async {
  final ok = await showModalBottomSheet<bool>(
    useRootNavigator: true, // above the shell tab bar
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (icon != null) ...[
              Container(
                width: 56,
                height: 56,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: AppColors.surfaceGray, shape: BoxShape.circle),
                child: Icon(icon, size: 26, color: AppColors.textPrimary),
              ),
              const SizedBox(height: 12),
            ],
            Text(title, textAlign: icon == null ? TextAlign.start : TextAlign.center, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
            if (body != null) ...[
              const SizedBox(height: 6),
              Text(body, textAlign: icon == null ? TextAlign.start : TextAlign.center, style: TextStyle(fontSize: 14, height: 1.4, color: AppColors.textSecondary)),
            ],
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(child: SecondaryButton(label: cancel, onPressed: () => Navigator.pop(ctx, false))),
                const SizedBox(width: 10),
                Expanded(child: PrimaryButton(label: confirm, onPressed: () => Navigator.pop(ctx, true))),
              ],
            ),
          ],
        ),
      ),
    ),
  );
  return ok == true;
}
