import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Host: live numbers and CSV exports.
/// Scaffold stub: replaced by its build track.
class ExpoDashboardScreen extends ConsumerWidget {
  const ExpoDashboardScreen({super.key, required this.eventId});
  final String eventId;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(appBar: AppBar(title: const Text('Live dashboard')));
}
