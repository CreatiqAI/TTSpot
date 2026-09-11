import 'package:flutter/material.dart';

import '../../features/events/domain/event.dart';
import '../theme/app_art.dart';
import '../theme/app_theme.dart';
import '../utils/dates.dart';

/// Light-theme event row: cover thumbnail, title, type · date, venue, badges.
class EventListTile extends StatelessWidget {
  const EventListTile({
    super.key,
    required this.event,
    required this.onTap,
    this.isOrganiser = false,
    this.trailing,
  });

  final Event event;
  final VoidCallback onTap;
  final bool isOrganiser;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final e = event;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.md),
              child: SizedBox(
                width: 60,
                height: 60,
                child: e.coverUrl == null
                    ? ColoredBox(
                        color: AppColors.surfaceGray,
                        child: Center(child: ArtIcon(e.type.art, size: 36)),
                      )
                    : Image.network(
                        e.coverUrl!,
                        fit: BoxFit.cover,
                        frameBuilder: (_, child, frame, sync) => frame == null && !sync
                            ? ColoredBox(color: AppColors.surfaceGray, child: Center(child: ArtIcon(e.type.art, size: 36)))
                            : child,
                        errorBuilder: (_, _, _) => ColoredBox(
                          color: AppColors.surfaceGray,
                          child: Center(child: ArtIcon(e.type.art, size: 36)),
                        ),
                      ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          e.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                        ),
                      ),
                      if (isOrganiser) const _Badge('Organiser'),
                      if (e.isCancelled) const _Badge('Cancelled', danger: true),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${e.type.label} · ${formatEventDateFriendly(e.startsAt)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${e.venueName} · ${e.attendeeCount} going',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
                  ),
                ],
              ),
            ),
            if (trailing != null) ...[const SizedBox(width: 8), trailing!],
          ],
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge(this.text, {this.danger = false});
  final String text;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(left: 8),
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: danger ? const Color(0xFFFDE8EA) : AppColors.surfaceGray,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: danger ? AppColors.danger : AppColors.textSecondary),
      ),
    );
  }
}
