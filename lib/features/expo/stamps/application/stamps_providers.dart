import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/supabase/supabase_client.dart';
import '../../../floorplan/application/floorplan_providers.dart';
import '../data/stamps_repository.dart';
import '../domain/stamps_models.dart';

/// My stamp card at an event.
final myStampsProvider = FutureProvider.autoDispose.family<StampCard, String>((ref, eventId) {
  if (ref.watch(currentUserIdProvider) == null) return const StampCard();
  return ref.watch(stampsRepositoryProvider).myStamps(eventId);
});

/// One exhibitor as I see it (exhibitor sheet).
final exhibitorExtrasProvider = FutureProvider.autoDispose.family<ExhibitorExtrasInfo?, String>((ref, exhibitorId) {
  if (ref.watch(currentUserIdProvider) == null) return null;
  return ref.watch(stampsRepositoryProvider).extras(exhibitorId);
});

/// Booths holding my contact at an event.
final myEventLeadsProvider = FutureProvider.autoDispose.family<List<MyLead>, String>((ref, eventId) {
  if (ref.watch(currentUserIdProvider) == null) return const [];
  return ref.watch(stampsRepositoryProvider).myLeads(eventId);
});

/// Host: every exhibitor with stamp, freebie and staff settings.
final boothSetupProvider = FutureProvider.autoDispose.family<List<BoothSetupRow>, String>((ref, eventId) {
  return ref.watch(stampsRepositoryProvider).setupList(eventId);
});

final rallySettingsProvider = FutureProvider.autoDispose.family<RallySettings, String>((ref, eventId) {
  return ref.watch(stampsRepositoryProvider).rallySettings(eventId);
});

/// The booths I staff at an event.
final myStaffBoothsProvider = FutureProvider.autoDispose.family<List<StaffBooth>, String>((ref, eventId) {
  if (ref.watch(currentUserIdProvider) == null) return const [];
  return ref.watch(stampsRepositoryProvider).myStaffBooths(eventId);
});

final exhibitorLeadsProvider = FutureProvider.autoDispose.family<List<Lead>, String>((ref, exhibitorId) {
  return ref.watch(stampsRepositoryProvider).leads(exhibitorId);
});

/// Mutations. Each refreshes what it touched.
class StampsActions {
  StampsActions(this._ref);
  final Ref _ref;

  StampsRepository get _repo => _ref.read(stampsRepositoryProvider);

  /// After a stamp: my card, the exhibitor sheet and "you are here".
  void refreshAfterStamp({required String eventId, required String exhibitorId}) {
    _ref.invalidate(myStampsProvider(eventId));
    _ref.invalidate(exhibitorExtrasProvider(exhibitorId));
    _ref.invalidate(myEventPositionProvider(eventId));
  }

  Future<DateTime> redeemFreebie({required String eventId, required String exhibitorId}) async {
    try {
      return await _repo.redeemFreebie(exhibitorId);
    } finally {
      _ref.invalidate(myStampsProvider(eventId));
      _ref.invalidate(exhibitorExtrasProvider(exhibitorId));
    }
  }

  Future<DateTime> redeemRally(String eventId) async {
    try {
      return await _repo.redeemRally(eventId);
    } finally {
      _ref.invalidate(myStampsProvider(eventId));
    }
  }

  Future<void> removeMyLead(String eventId, String leadId) async {
    await _repo.removeMyLead(leadId);
    _ref.invalidate(myEventLeadsProvider(eventId));
  }

  Future<void> setBoothStamp(String eventId, String exhibitorId, {required bool stop, String? freebie, int? limit}) async {
    await _repo.setBoothStamp(exhibitorId, stop: stop, freebie: freebie, limit: limit);
    _ref.invalidate(boothSetupProvider(eventId));
    _ref.invalidate(exhibitorExtrasProvider(exhibitorId));
  }

  Future<void> setRally(String eventId, {int? goal, String? reward}) async {
    await _repo.setRally(eventId, goal: goal, reward: reward);
    _ref.invalidate(rallySettingsProvider(eventId));
    _ref.invalidate(myStampsProvider(eventId));
  }

  Future<BoothStaff> addStaff(String eventId, String exhibitorId, String username) async {
    final s = await _repo.addStaff(exhibitorId, username);
    _ref.invalidate(boothSetupProvider(eventId));
    return s;
  }

  Future<void> removeStaff(String eventId, String exhibitorId, String userId) async {
    await _repo.removeStaff(exhibitorId, userId);
    _ref.invalidate(boothSetupProvider(eventId));
  }

  Future<void> rotateCode(String eventId, String exhibitorId) async {
    await _repo.rotateCode(exhibitorId);
    _ref.invalidate(boothSetupProvider(eventId));
  }

  Future<LeadSaved> saveLead({required String eventId, required String passCode, String? exhibitorId}) async {
    final r = await _repo.saveLead(eventId: eventId, passCode: passCode, exhibitorId: exhibitorId);
    _ref.invalidate(exhibitorLeadsProvider(r.exhibitorId));
    _ref.invalidate(exhibitorExtrasProvider(r.exhibitorId));
    return r;
  }

  Future<void> setLeadNote(String exhibitorId, String leadId, String? note) async {
    await _repo.setLeadNote(leadId, note);
    _ref.invalidate(exhibitorLeadsProvider(exhibitorId));
  }
}

final stampsActionsProvider = Provider<StampsActions>((ref) => StampsActions(ref));
