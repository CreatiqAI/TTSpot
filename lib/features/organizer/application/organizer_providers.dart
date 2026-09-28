import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/supabase/supabase_client.dart';
import '../../vendors/application/vendors_providers.dart';
import '../../vendors/domain/vendor.dart';
import '../data/organizer_repository.dart';
import '../domain/organizer_models.dart';

/// Whether a member is a verified organizer (the badge next to a host's name).
final isOrganizerProvider = FutureProvider.family<bool, String>((ref, userId) {
  return ref.watch(organizerRepositoryProvider).isOrganizer(userId);
});

/// Whether I am a verified organizer.
final amOrganizerProvider = FutureProvider<bool>((ref) async {
  final me = ref.watch(currentUserIdProvider);
  if (me == null) return false;
  return ref.watch(isOrganizerProvider(me).future);
});

/// My role at a meet and whether its organizer tools are on.
final myEventRoleProvider = FutureProvider.autoDispose.family<EventRole, String>((ref, eventId) {
  if (ref.watch(currentUserIdProvider) == null) return EventRole.none;
  return ref.watch(organizerRepositoryProvider).myEventRole(eventId);
});

final eventCrewProvider = FutureProvider.autoDispose.family<List<CrewMember>, String>((ref, eventId) {
  return ref.watch(organizerRepositoryProvider).crew(eventId);
});

final eventAnnouncementsProvider = FutureProvider.autoDispose.family<List<EventAnnouncement>, String>((ref, eventId) {
  return ref.watch(organizerRepositoryProvider).announcements(eventId);
});

final audienceCountProvider = FutureProvider.autoDispose.family<int, ({String eventId, Audience audience})>((ref, a) {
  return ref.watch(organizerRepositoryProvider).audienceCount(a.eventId, a.audience);
});

final eventDrawsProvider = FutureProvider.autoDispose.family<List<LuckyDraw>, String>((ref, eventId) {
  return ref.watch(organizerRepositoryProvider).draws(eventId);
});

final drawProvider = FutureProvider.autoDispose.family<LuckyDraw?, String>((ref, drawId) {
  return ref.watch(organizerRepositoryProvider).draw(drawId);
});

/// Every draw at a meet as I see it: am I in, did I win.
final myDrawStatusProvider = FutureProvider.autoDispose.family<List<MyDraw>, String>((ref, eventId) {
  if (ref.watch(currentUserIdProvider) == null) return const [];
  return ref.watch(organizerRepositoryProvider).myDrawStatus(eventId);
});

final drawResultsProvider = FutureProvider.autoDispose.family<List<DrawResult>, String>((ref, drawId) {
  return ref.watch(organizerRepositoryProvider).results(drawId);
});

final drawStageProvider = FutureProvider.autoDispose.family<DrawStage, String>((ref, drawId) {
  return ref.watch(organizerRepositoryProvider).stage(drawId);
});

/// Mutations. Each call refreshes what it touched.
class OrganizerActions {
  OrganizerActions(this._ref);
  final Ref _ref;

  OrganizerRepository get _repo => _ref.read(organizerRepositoryProvider);

  Future<void> apply({required String name, String? links, String? size, String? description}) async {
    await _repo.applyOrganizer(name: name, links: links, size: size, description: description);
    _ref.invalidate(myPartnerApplicationProvider(ApplicationKind.organizer));
  }

  Future<void> setCrew(String eventId, String userId, String role) async {
    await _repo.setCrew(eventId, userId, role);
    _ref.invalidate(eventCrewProvider(eventId));
  }

  Future<void> removeCrew(String eventId, String userId) async {
    await _repo.removeCrew(eventId, userId);
    _ref.invalidate(eventCrewProvider(eventId));
    _ref.invalidate(myEventRoleProvider(eventId));
  }

  Future<void> announce({required String eventId, required String title, required String body, required Audience audience, DateTime? sendAt}) async {
    await _repo.createAnnouncement(eventId: eventId, title: title, body: body, audience: audience, sendAt: sendAt);
    _ref.invalidate(eventAnnouncementsProvider(eventId));
  }

  Future<void> cancelAnnouncement(String eventId, String id) async {
    await _repo.cancelAnnouncement(id);
    _ref.invalidate(eventAnnouncementsProvider(eventId));
  }

  Future<String> saveDraw({
    required String eventId,
    String? drawId,
    required String title,
    required DateTime drawAt,
    DateTime? cutoffAt,
    required bool mustBePresent,
    required int claimMinutes,
    required List<DrawPrize> prizes,
  }) async {
    final id = await _repo.saveDraw(
      eventId: eventId,
      drawId: drawId,
      title: title,
      drawAt: drawAt,
      cutoffAt: cutoffAt,
      mustBePresent: mustBePresent,
      claimMinutes: claimMinutes,
      prizes: prizes,
    );
    _refreshDraw(eventId, id);
    return id;
  }

  Future<void> cancelDraw(String eventId, String drawId) async {
    await _repo.cancelDraw(drawId);
    _refreshDraw(eventId, drawId);
  }

  Future<void> runDraw(String eventId, String drawId) async {
    await _repo.runDraw(drawId);
    _refreshDraw(eventId, drawId);
  }

  Future<void> forfeit(String eventId, String drawId, String winnerId) async {
    await _repo.forfeitWinner(winnerId);
    _refreshDraw(eventId, drawId);
  }

  Future<PrizeClaimResult> claimPrize(String code) => _repo.claimPrize(code);

  void _refreshDraw(String eventId, String drawId) {
    _ref.invalidate(eventDrawsProvider(eventId));
    _ref.invalidate(drawProvider(drawId));
    _ref.invalidate(drawStageProvider(drawId));
    _ref.invalidate(myDrawStatusProvider(eventId));
    _ref.invalidate(drawResultsProvider(drawId));
  }
}

final organizerActionsProvider = Provider<OrganizerActions>((ref) => OrganizerActions(ref));
