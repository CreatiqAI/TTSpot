import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Members: enter my car, vote once, see results.
/// Scaffold stub: replaced by its build track.
class ContestScreen extends ConsumerWidget {
  const ContestScreen({super.key, required this.eventId, this.contestId});
  final String eventId;
  final String? contestId;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(appBar: AppBar(title: const Text('Show car vote')));
}
