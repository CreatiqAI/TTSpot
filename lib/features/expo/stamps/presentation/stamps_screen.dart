import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Members: my booth stamps, the rally goal and reward, freebies to collect.
/// Scaffold stub: replaced by its build track.
class StampsScreen extends ConsumerWidget {
  const StampsScreen({super.key, required this.eventId});
  final String eventId;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(appBar: AppBar(title: const Text('Stamps')));
}
