import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Booth staff: members whose pass we scanned; export CSV.
/// Scaffold stub: replaced by its build track.
class LeadsScreen extends ConsumerWidget {
  const LeadsScreen({super.key, required this.eventId, required this.exhibitorId});
  final String eventId;
  final String exhibitorId;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(appBar: AppBar(title: const Text('Leads')));
}
