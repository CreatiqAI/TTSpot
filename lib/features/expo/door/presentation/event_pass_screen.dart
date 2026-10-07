import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// My pass for an event: entry number, pass QR, registration, draw status, links.
/// Scaffold stub: replaced by its build track.
class EventPassScreen extends ConsumerWidget {
  const EventPassScreen({super.key, required this.eventId});
  final String eventId;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(appBar: AppBar(title: const Text('Event pass')));
}
