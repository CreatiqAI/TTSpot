import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Event page: Pass, Floor plan, Exhibitors, Schedule, Stamps, Vote, My booth.
/// Scaffold stub: replaced by its build track.
class EventHubCard extends ConsumerWidget {
  const EventHubCard({super.key, required this.eventId});
  final String eventId;

  @override
  Widget build(BuildContext context, WidgetRef ref) => const SizedBox.shrink();
}
