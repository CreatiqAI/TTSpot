import 'dart:io';

import 'package:flutter/foundation.dart';

/// A public file's bytes (our storage buckets are public-read): a plain HTTP
/// GET, no storage session needed. Throws on anything but a 200.
Future<Uint8List> downloadBytes(String url) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 20);
  try {
    final req = await client.getUrl(Uri.parse(url));
    final res = await req.close().timeout(const Duration(seconds: 30));
    if (res.statusCode != 200) throw HttpException('HTTP ${res.statusCode}', uri: Uri.parse(url));
    return await consolidateHttpClientResponseBytes(res);
  } finally {
    client.close();
  }
}
