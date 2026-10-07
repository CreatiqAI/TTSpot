import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Host: add, import (paste CSV) and edit exhibitors; link booth pins.
/// Scaffold stub: replaced by its build track.
class ExhibitorsEditorScreen extends ConsumerWidget {
  const ExhibitorsEditorScreen({super.key, required this.eventId});
  final String eventId;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(appBar: AppBar(title: const Text('Exhibitors')));
}
