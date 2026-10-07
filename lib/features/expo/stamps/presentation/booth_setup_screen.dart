import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Host: stamp stops, freebies, rally goal, booth staff, printable booth QR codes.
/// Scaffold stub: replaced by its build track.
class BoothSetupScreen extends ConsumerWidget {
  const BoothSetupScreen({super.key, required this.eventId});
  final String eventId;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(appBar: AppBar(title: const Text('Stamps & booths')));
}
