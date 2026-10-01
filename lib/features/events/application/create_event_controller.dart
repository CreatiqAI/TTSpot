import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;
import '../../../core/geo/latlng.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/supabase/supabase_client.dart';
import '../../../core/utils/friendly_error.dart';
import '../../map/application/map_providers.dart';
import '../../social/application/chat_providers.dart';
import '../data/events_repository.dart';
import '../domain/event.dart';
import 'my_events_provider.dart';

/// Validates, uploads the cover, inserts the event, refreshes the map.
/// [submit] returns the new event id on success.
class CreateEventController extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}

  /// [cover] is an uploaded photo; [coverUrl] a picked preset (see
  /// `kCoverPresets`). Neither = the type's own bundled cover.
  /// [invitees]: friends who get an invite card in their chat afterwards.
  Future<String?> submit({
    required String title,
    required String description,
    required EventType type,
    required DateTime startsAt,
    DateTime? endsAt,
    required String venueName,
    required LatLng? location,
    int? maxAttendees,
    XFile? cover,
    String? coverUrl,
    String? clubId,
    String? vendorId,
    bool friendsOnly = false,
    String? address,
    List<String> invitees = const [],
  }) async {
    state = const AsyncLoading();
    String? createdId;
    state = await AsyncValue.guard(() async {
      final me = ref.read(currentUserIdProvider);
      if (me == null) throw const AppException('You\'re signed out. Sign in again.');
      if (title.trim().length < 3) throw const AppException('Give it a title (at least 3 characters).');
      if (venueName.trim().isEmpty) throw const AppException('Add a venue name so people know where to park.');
      if (location == null) throw const AppException('Drop the pin on the meet location.');
      if (startsAt.isBefore(DateTime.now().add(const Duration(minutes: 10)))) {
        throw const AppException('Pick a start time in the future.');
      }

      final repo = ref.read(eventsRepositoryProvider);
      var url = coverUrl;
      if (cover != null) {
        url = await repo.uploadCover(userId: me, bytes: await cover.readAsBytes());
      }
      final Event event;
      try {
        event = await repo.create(
          organizerId: me,
          title: title,
          description: description.trim().isEmpty ? null : description,
          type: type,
          coverUrl: url,
          startsAt: startsAt,
          endsAt: endsAt,
          venueName: venueName,
          location: location,
          maxAttendees: maxAttendees,
          clubId: clubId,
          vendorId: vendorId,
          friendsOnly: friendsOnly,
          address: address,
        );
      } on PostgrestException catch (e) {
        if (e.code == '42501') {
          throw const AppException('Only car clubs and partners can host events. Switch to your club or partner account, or plan a TT session instead.');
        }
        rethrow;
      }
      createdId = event.id;
      ref.invalidate(mapEventsProvider);
      ref.invalidate(myEventsProvider);
      // One invite card in each picked friend's chat (best effort: the meet
      // exists either way, and they can still find it on the map).
      if (invitees.isNotEmpty) {
        final chat = ref.read(chatActionsProvider);
        for (final uid in invitees) {
          try {
            final conv = await chat.openDm(uid);
            await chat.attach(conv, eventId: event.id);
          } catch (_) {}
        }
      }
    });
    return createdId;
  }
}

final createEventControllerProvider =
    AsyncNotifierProvider<CreateEventController, void>(CreateEventController.new);

/// Cover picker config: big enough for the details header, well under the 5 MB bucket limit.
Future<XFile?> pickCoverImage(ImageSource source) {
  return ImagePicker().pickImage(source: source, maxWidth: 2000, maxHeight: 2000, imageQuality: 90);
}
