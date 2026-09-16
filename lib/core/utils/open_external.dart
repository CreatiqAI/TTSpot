import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// Opens another app (Waze, Google Maps, WhatsApp) or a web page.
///
/// When the app is installed we hand off once and stop, even if the person
/// taps Cancel on the "Open in …?" prompt. The browser fallback is only for
/// phones that do not have the app at all.
Future<void> openExternal(BuildContext context, String url, {String? fallbackUrl}) async {
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
      return; // their choice on the prompt is final
    }
    if (fallbackUrl == null) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('That app isn\'t installed.')));
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
