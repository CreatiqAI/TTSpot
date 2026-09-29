import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/supabase/supabase_client.dart';
import '../../../../core/theme/app_icons.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/primary_button.dart';
import '../../../../core/widgets/thumb_image.dart';
import '../../application/profile_providers.dart';
import '../../domain/car.dart';

/// What [chooseOutingCar] came back with. [cancelled] is true when the member
/// closed the sheet without picking (the caller should stop what it was doing).
typedef OutingCarChoice = ({Car? car, bool cancelled});

/// "Which car are you bringing?" for a meet, a TT now, a check-in.
/// One car: that car, no sheet. No car (or the garage failed to load): null,
/// and the server falls back to the default car. Two or more: a sheet with the
/// default (or [initialCarId]) preselected. Null also when the sheet is closed;
/// use [chooseOutingCar] to tell that apart.
Future<Car?> pickCarForOuting(BuildContext context, WidgetRef ref, {required String title, String? subtitle, String? initialCarId}) async {
  final r = await chooseOutingCar(context, ref, title: title, subtitle: subtitle, initialCarId: initialCarId);
  return r.car;
}

/// [pickCarForOuting] that also says whether the member backed out.
Future<OutingCarChoice> chooseOutingCar(BuildContext context, WidgetRef ref, {required String title, String? subtitle, String? initialCarId}) async {
  final me = ref.read(currentUserIdProvider);
  if (me == null) return (car: null, cancelled: false);
  List<Car> cars;
  try {
    cars = await ref.read(userCarsProvider(me).future);
  } catch (_) {
    return (car: null, cancelled: false);
  }
  if (cars.isEmpty) return (car: null, cancelled: false);
  if (cars.length == 1) return (car: cars.first, cancelled: false);
  if (!context.mounted) return (car: null, cancelled: true);

  final initial = cars.where((c) => c.id == initialCarId).firstOrNull ?? cars.where((c) => c.isDefault).firstOrNull ?? cars.first;
  final picked = await showModalBottomSheet<Car>(
    useRootNavigator: true, // above the shell tab bar
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (_) => _CarPickerSheet(cars: cars, initial: initial, title: title, subtitle: subtitle),
  );
  return (car: picked, cancelled: picked == null);
}

class _CarPickerSheet extends StatefulWidget {
  const _CarPickerSheet({required this.cars, required this.initial, required this.title, this.subtitle});
  final List<Car> cars;
  final Car initial;
  final String title;
  final String? subtitle;

  @override
  State<_CarPickerSheet> createState() => _CarPickerSheetState();
}

class _CarPickerSheetState extends State<_CarPickerSheet> {
  late Car _selected = widget.initial;

  @override
  Widget build(BuildContext context) {
    final maxList = MediaQuery.sizeOf(context).height * 0.5;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(widget.title, style: TextStyle(fontFamily: AppFonts.display, fontSize: 24, fontWeight: FontWeight.w800, height: 1.1, color: AppColors.textPrimary)),
            ),
            if (widget.subtitle != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 4, 4, 0),
                child: Text(widget.subtitle!, style: TextStyle(fontSize: 13.5, color: AppColors.textSecondary, height: 1.35)),
              ),
            const SizedBox(height: 12),
            ConstrainedBox(
              constraints: BoxConstraints(maxHeight: maxList),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: widget.cars.length,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (_, i) {
                  final c = widget.cars[i];
                  return _CarOption(car: c, selected: c.id == _selected.id, onTap: () => setState(() => _selected = c));
                },
              ),
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: PrimaryButton(label: 'Bring this car', onPressed: () => Navigator.pop(context, _selected)),
            ),
          ],
        ),
      ),
    );
  }
}

class _CarOption extends StatelessWidget {
  const _CarOption({required this.car, required this.selected, required this.onTap});
  final Car car;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AppColors.brand.withValues(alpha: 0.06) : AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        side: BorderSide(color: selected ? AppColors.brand : AppColors.border, width: selected ? 2 : 1),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            children: [
              CarThumb(url: car.cover, width: 64, height: 44),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(car.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        if (car.year != null) Text('${car.year}', style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary)),
                        if (car.year != null && car.isDefault) const SizedBox(width: 8),
                        if (car.isDefault)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(color: AppColors.surfaceGray, borderRadius: BorderRadius.circular(AppRadius.pill)),
                            child: Text('Default', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.textSecondary)),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              selected
                  ? const Icon(AppIcons.checkCircleFill, size: 24, color: AppColors.brand)
                  : Container(
                      width: 22,
                      height: 22,
                      margin: const EdgeInsets.all(1),
                      decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: AppColors.textMuted, width: 1.6)),
                    ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Rounded car cover, or a car glyph on grey when there's no photo yet.
class CarThumb extends StatelessWidget {
  const CarThumb({super.key, required this.url, this.width = 64, this.height = 44, this.radius = 8});
  final String? url;
  final double width;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final placeholder = ColoredBox(color: AppColors.surfaceGray, child: Center(child: Icon(AppIcons.car, size: height * 0.42, color: AppColors.textSecondary)));
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: SizedBox(
        width: width,
        height: height,
        child: url == null
            ? placeholder
            : ThumbImage(url!, error: placeholder),
      ),
    );
  }
}
