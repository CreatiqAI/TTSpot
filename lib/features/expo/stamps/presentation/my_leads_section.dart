import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_icons.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/friendly_error.dart';
import '../application/stamps_providers.dart';
import '../domain/stamps_models.dart';

/// On my event pass: booths that saved my contact, each with "Remove".
/// Hidden when no booth has it.
class MyLeadsSection extends ConsumerWidget {
  const MyLeadsSection({super.key, required this.eventId});
  final String eventId;

  Future<void> _remove(BuildContext context, WidgetRef ref, MyLead l) async {
    try {
      await ref.read(stampsActionsProvider).removeMyLead(eventId, l.id);
      if (context.mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text('Removed from ${l.exhibitorName}.')));
      }
    } catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e))));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final leads = ref.watch(myEventLeadsProvider(eventId)).value ?? const <MyLead>[];
    if (leads.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('Booths with your contact', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(color: AppColors.surfaceGray, borderRadius: BorderRadius.circular(AppRadius.lg)),
          child: Column(
            children: [
              for (final l in leads)
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
                  child: Row(
                    children: [
                      Icon(AppIcons.storefront, size: 20, color: AppColors.textPrimary),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(l.exhibitorName, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                            if (l.booths.isNotEmpty)
                              Text(boothLabel(l.booths), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary)),
                          ],
                        ),
                      ),
                      TextButton(onPressed: () => _remove(context, ref, l), child: const Text('Remove')),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
