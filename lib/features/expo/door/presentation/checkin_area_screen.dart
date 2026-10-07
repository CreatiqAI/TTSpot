import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Host: how far from the event pin members can check in.
/// Scaffold stub: replaced by its build track.
class CheckinAreaScreen extends ConsumerWidget {
  const CheckinAreaScreen({super.key, required this.eventId});
  final String eventId;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(appBar: AppBar(title: const Text('Check-in area')));
}
