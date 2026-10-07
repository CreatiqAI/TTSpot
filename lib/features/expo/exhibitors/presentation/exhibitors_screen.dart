import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Members: search exhibitors, open one, show it on the floor plan.
/// Scaffold stub: replaced by its build track.
class ExhibitorsScreen extends ConsumerWidget {
  const ExhibitorsScreen({super.key, required this.eventId});
  final String eventId;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(appBar: AppBar(title: const Text('Exhibitors')));
}
