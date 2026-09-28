import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_icons.dart';
import '../../application/organizer_providers.dart';

/// Blue seal after a host's name when they are a verified organizer.
/// Draws nothing for everyone else (and while loading).
class OrganizerBadge extends ConsumerWidget {
  const OrganizerBadge({super.key, required this.userId, this.size = 15});
  final String? userId;
  final double size;

  static const color = Color(0xFF2B7CFF);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final id = userId;
    if (id == null) return const SizedBox.shrink();
    final verified = ref.watch(isOrganizerProvider(id)).value ?? false;
    if (!verified) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Tooltip(message: 'Verified organizer', child: Icon(AppIcons.sealCheck, size: size, color: color)),
    );
  }
}
