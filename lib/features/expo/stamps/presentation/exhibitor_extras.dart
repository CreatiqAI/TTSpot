import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Inside the exhibitor sheet: stamp status, freebie, leads for staff.
/// Scaffold stub: replaced by its build track.
class ExhibitorExtras extends ConsumerWidget {
  const ExhibitorExtras({super.key, required this.eventId, required this.exhibitorId});
  final String eventId;
  final String exhibitorId;

  @override
  Widget build(BuildContext context, WidgetRef ref) => const SizedBox.shrink();
}
