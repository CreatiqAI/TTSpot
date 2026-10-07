import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Host: add and edit schedule items.
/// Scaffold stub: replaced by its build track.
class ScheduleEditorScreen extends ConsumerWidget {
  const ScheduleEditorScreen({super.key, required this.eventId});
  final String eventId;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(appBar: AppBar(title: const Text('Schedule')));
}
