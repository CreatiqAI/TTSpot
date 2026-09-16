import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// Opens another app (Waze, Google Maps, WhatsApp, the dialler) or a web page.
///
/// Pass [appName] to ask first ("Open Waze?") so nobody leaves TT Spot by
/// accident; Cancel does nothing. When the app is installed we hand off once
/// and stop. The browser fallback is only for phones without the app.
Future<void> openExternal(BuildContext context, String url, {String? fallbackUrl, String? appName}) async {
  if (appName != null) {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Open $appName?'),
        content: Text('This leaves TT Spot and opens $appName.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Open')),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
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
String googleMapsUrl(double lat, double lng) => 'https://www.google.com/maps/dir/?api=1&destination=$lat,$lng';
String whatsappUrl(String text) => 'https://wa.me/?text=${Uri.encodeComponent(text)}';
