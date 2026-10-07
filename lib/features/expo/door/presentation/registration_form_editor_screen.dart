import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Host: the questions members answer after checking in, plus consent.
/// Scaffold stub: replaced by its build track.
class RegistrationFormEditorScreen extends ConsumerWidget {
  const RegistrationFormEditorScreen({super.key, required this.eventId});
  final String eventId;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(appBar: AppBar(title: const Text('Registration form')));
}
