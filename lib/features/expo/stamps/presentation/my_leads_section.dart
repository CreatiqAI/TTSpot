import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// On my event pass: booths that saved my contact, each with "Remove".
/// Scaffold stub: replaced by its build track.
class MyLeadsSection extends ConsumerWidget {
  const MyLeadsSection({super.key, required this.eventId});
  final String eventId;

  @override
  Widget build(BuildContext context, WidgetRef ref) => const SizedBox.shrink();
}
