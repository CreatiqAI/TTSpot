import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/supabase/supabase_client.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/friendly_error.dart';
import '../../profile/application/profile_providers.dart';
import '../../profile/presentation/widgets/car_picker_sheet.dart';
import '../application/event_providers.dart';
import '../domain/event_car.dart';

/// Check-in: "Which car did you bring?" with the car I RSVP'd with preselected.
/// Only asks with 2+ cars.
Future<OutingCarChoice> chooseCheckinCar(BuildContext context, WidgetRef ref, String eventId) async {
  Map<String, EventCar> cars = const {};
  try {
    cars = await ref.read(eventCarsProvider(eventId).future);
  } catch (_) {}
  if (!context.mounted) return (car: null, cancelled: true);
  return chooseOutingCar(
    context,
    ref,
    title: 'Which car did you bring?',
    subtitle: 'It shows on the meet\'s list and in the recap.',
    initialCarId: cars[ref.read(currentUserIdProvider)]?.carId,
  );
}

/// "Bringing: Myvi 1.5 AV · Change" under the Join button once I'm going.
/// "Change" only shows with 2+ cars in my garage.
class BringingCarRow extends ConsumerStatefulWidget {
  const BringingCarRow({super.key, required this.eventId});
  final String eventId;

  @override
  ConsumerState<BringingCarRow> createState() => _BringingCarRowState();
}

class _BringingCarRowState extends ConsumerState<BringingCarRow> {
  bool _busy = false;

  Future<void> _change(String? currentId) async {
    final car = await pickCarForOuting(context, ref, title: 'Which car are you bringing?', initialCarId: currentId);
    if (car == null || car.id == currentId || !mounted) return;
    setState(() => _busy = true);
    try {
      await ref.read(eventActionsProvider).setCar(widget.eventId, car.id);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final me = ref.watch(currentUserIdProvider);
    if (me == null) return const SizedBox.shrink();
    final mine = ref.watch(eventCarsProvider(widget.eventId)).value?[me];
    if (mine == null) return const SizedBox.shrink();
    final canChange = (ref.watch(userCarsProvider(me)).value?.length ?? 0) > 1;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        children: [
          CarThumb(url: mine.cover, bodyStyle: mine.bodyStyle, width: 40, height: 28, radius: 6),
          const SizedBox(width: 10),
          Expanded(
            child: Text.rich(
              TextSpan(
                style: TextStyle(fontSize: 13.5, color: AppColors.textSecondary),
                children: [
                  const TextSpan(text: 'Bringing: '),
                  TextSpan(text: mine.title ?? 'your car', style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                ],
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (canChange)
            _busy
                ? const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 12),
                    child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                  )
                : TextButton(
                    onPressed: () => _change(mine.carId),
                    style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                    child: const Text('Change'),
                  ),
        ],
      ),
    );
  }
}

/// Small car thumbnail + "Make Model" for attendee and check-in lists.
class EventCarLine extends StatelessWidget {
  const EventCarLine({super.key, required this.title, this.cover, this.bodyStyle});
  final String title;
  final String? cover;
  final String? bodyStyle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 3),
      child: Row(
        children: [
          CarThumb(url: cover, bodyStyle: bodyStyle, width: 30, height: 20, radius: 4),
          const SizedBox(width: 6),
          Flexible(
            child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
          ),
        ],
      ),
    );
  }
}
