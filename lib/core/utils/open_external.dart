import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// Opens another app (Waze, Google Maps, WhatsApp) or a web page. Falls back
/// to the browser version when the app isn't installed.
Future<void> openExternal(BuildContext context, String url, {String? fallbackUrl}) async {
  Future<bool> tryOpen(String u) async {
    try {
      return await launchUrl(Uri.parse(u), mode: LaunchMode.externalApplication);
    } catch (_) {
      return false;
    }
  }

  if (await tryOpen(url)) return;
  if (fallbackUrl != null && await tryOpen(fallbackUrl)) return;
  if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Couldn\'t open that app.')));
}

String wazeUrl(double lat, double lng) => 'https://waze.com/ul?ll=$lat,$lng&navigate=yes';
String googleMapsUrl(double lat, double lng) => 'https://www.google.com/maps/dir/?api=1&destination=$lat,$lng';
String whatsappUrl(String text) => 'https://wa.me/?text=${Uri.encodeComponent(text)}';
