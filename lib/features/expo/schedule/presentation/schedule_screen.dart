import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Members: the stage schedule with "Remind me".
/// Scaffold stub: replaced by its build track.
class ScheduleScreen extends ConsumerWidget {
  const ScheduleScreen({super.key, required this.eventId});
  final String eventId;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(appBar: AppBar(title: const Text('Schedule')));
}
