import 'dart:io';

import 'package:flutter/material.dart';

import '../../../../core/theme/app_art.dart';
import '../../../../core/theme/app_icons.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/dates.dart';
import '../../application/plan_draft.dart';
import 'when_step.dart';
import 'wizard_parts.dart';

/// Last step: everything on one card, an Edit link per part.
class ReviewStep extends StatelessWidget {
  const ReviewStep({super.key, required this.draft, required this.onEdit, this.hostName, this.clubName});
  final PlanDraft draft;
  final ValueChanged<PlanStep> onEdit;
  final String? hostName;
  final String? clubName;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: draft,
      builder: (context, _) {
        final d = draft;
        final s = d.startsAt;
        final end = d.endsAt;
        final who = d.friendsOnly ? (clubName == null ? 'Friends' : 'Friends and $clubName members') : 'Everyone on TT Spot';
        final invites = d.invitees.isEmpty ? null : '${d.invitees.length} friend${d.invitees.length == 1 ? '' : 's'} invited';
        final notes = d.notesCtrl.text.trim();
        return ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          children: [
            StepHeading('Looks good?', subtitle: d.session ? 'Check it over, then post it. Friends see it on the map.' : 'Check it over, then publish.'),
            Container(
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: AppColors.surfaceRaised,
                borderRadius: BorderRadius.circular(AppRadius.lg),
                border: Border.all(color: AppColors.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Stack(
                    children: [
                      AspectRatio(
                        aspectRatio: 16 / 9,
                        child: d.coverFile != null ? Image.file(File(d.coverFile!.path), fit: BoxFit.cover) : Image.asset(d.coverAsset, fit: BoxFit.cover),
                      ),
                      Positioned(right: 8, top: 8, child: _EditPill(onTap: () => onEdit(PlanStep.style))),
                    ],
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 12, 14, 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  ArtIcon(d.type.art, size: 18),
                                  const SizedBox(width: 6),
                                  Flexible(child: Text(d.type.label.toUpperCase(), style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1, color: AppColors.textSecondary))),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(d.title, style: TextStyle(fontFamily: AppFonts.display, fontSize: 26, height: 1.05, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
                              if (hostName != null) ...[
                                const SizedBox(height: 4),
                                Text('Hosted by $hostName', style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary)),
                              ],
                            ],
                          ),
                        ),
                        if (!d.session) TextButton(onPressed: () => onEdit(PlanStep.kind), child: const Text('Edit')),
                      ],
                    ),
                  ),
                  _Row(icon: AppIcons.mapPin, title: d.venue, sub: d.address, onEdit: () => onEdit(PlanStep.where)),
                  _Row(
                    icon: AppIcons.calendarBlank,
                    title: formatEventDateFriendly(s),
                    sub: end == null ? null : 'Until ${formatTime(end)} · ${WhenStep.durationLabel(d.minutes)}',
                    onEdit: () => onEdit(PlanStep.when),
                  ),
                  _Row(icon: d.friendsOnly ? AppIcons.users : AppIcons.globe, title: who, sub: invites, onEdit: () => onEdit(PlanStep.who)),
                  if (notes.isNotEmpty) _Row(icon: AppIcons.notePencil, title: notes, maxLines: 3, onEdit: () => onEdit(PlanStep.style)),
                  const SizedBox(height: 8),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Text(
              d.session ? 'Keep it legal and friendly. No street racing.' : 'By publishing you confirm this is a legal, public gathering. No street racing.',
              style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary, height: 1.4),
            ),
          ],
        );
      },
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.icon, required this.title, this.sub, required this.onEdit, this.maxLines = 2});
  final IconData icon;
  final String title;
  final String? sub;
  final VoidCallback onEdit;
  final int maxLines;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(14, 6, 4, 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(padding: const EdgeInsets.only(top: 2), child: Icon(icon, size: 20, color: AppColors.textPrimary)),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, maxLines: maxLines, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700, height: 1.3)),
                  if (sub != null && sub!.isNotEmpty) Text(sub!, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.5, height: 1.3, color: AppColors.textSecondary)),
                ],
              ),
            ),
            TextButton(onPressed: onEdit, child: const Text('Edit')),
          ],
        ),
      );
}

class _EditPill extends StatelessWidget {
  const _EditPill({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
        color: Colors.black.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(AppRadius.pill),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppRadius.pill),
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(AppIcons.pencilSimple, size: 14, color: Colors.white),
                SizedBox(width: 4),
                Text('Cover', style: TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w700)),
              ],
            ),
          ),
        ),
      );
}
