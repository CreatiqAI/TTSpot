import 'package:flutter/material.dart';

import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_theme.dart';
import '../application/event_view.dart';

/// "Attendee · Organizer · Booth": a small segmented switch for members with
/// an extra role at a big event. Draws nothing with a single view.
class EventRoleSwitch extends StatelessWidget {
  const EventRoleSwitch({super.key, required this.views, required this.current, required this.onChanged});
  final List<EventView> views;
  final EventView current;
  final ValueChanged<EventView> onChanged;

  static IconData iconOf(EventView v) => switch (v) {
        EventView.attendee => AppIcons.user,
        EventView.organizer => AppIcons.sealCheck,
        EventView.booth => AppIcons.storefront,
      };

  @override
  Widget build(BuildContext context) {
    if (views.length < 2) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(color: AppColors.surfaceGray, borderRadius: BorderRadius.circular(AppRadius.pill)),
      child: Row(
        children: [
          for (final v in views)
            Expanded(
              child: Semantics(
                selected: v == current,
                button: true,
                child: Material(
                  key: ValueKey('view-${v.name}'),
                  color: v == current ? AppColors.textPrimary : Colors.transparent,
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                    onTap: v == current ? null : () => onChanged(v),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(iconOf(v), size: 16, color: v == current ? AppColors.onInk : AppColors.textSecondary),
                          const SizedBox(width: 5),
                          Flexible(
                            child: Text(
                              v.label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 13.5,
                                fontWeight: v == current ? FontWeight.w800 : FontWeight.w600,
                                color: v == current ? AppColors.onInk : AppColors.textSecondary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
