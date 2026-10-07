import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Top of the floor plan right after a door check-in: "You're in, #0427".
/// Scaffold stub: replaced by its build track.
class DoorWelcomeBanner extends ConsumerWidget {
  const DoorWelcomeBanner({super.key, required this.eventId});
  final String eventId;

  @override
  Widget build(BuildContext context, WidgetRef ref) => const SizedBox.shrink();
}
