import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Host: open a vote, approve entries, print vote QR codes, close it.
/// Scaffold stub: replaced by its build track.
class ContestEditorScreen extends ConsumerWidget {
  const ContestEditorScreen({super.key, required this.eventId});
  final String eventId;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(appBar: AppBar(title: const Text('Show car vote')));
}
