import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/supabase/supabase_client.dart';
import '../../../core/utils/friendly_error.dart';
import '../../map/application/map_providers.dart';
import '../data/events_repository.dart';
import '../domain/event.dart';
import 'my_events_provider.dart';

/// Validates, uploads the cover, inserts the event, refreshes the map.
/// [submit] returns the new event id on success.
class CreateEventController extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}

  Future<String?> submit({
    required String title,
    required String description,
    required EventType type,
    required DateTime startsAt,
    required String venueName,
    required LatLng? location,
    int? maxAttendees,
    XFile? cover,
    String? clubId,
    bool friendsOnly = false,
  }) async {
    state = const AsyncLoading();
    String? createdId;
    state = await AsyncValue.guard(() async {
      final me = ref.read(currentUserIdProvider);
      if (me == null) throw const AppException('You\'re signed out. Sign in again.');
      if (title.trim().length < 3) throw const AppException('Give your meet a title (at least 3 characters).');
      if (venueName.trim().isEmpty) throw const AppException('Add a venue name so people know where to park.');
      if (location == null) throw const AppException('Drop the pin on the meet location.');
      if (startsAt.isBefore(DateTime.now().add(const Duration(minutes: 10)))) {
        throw const AppException('Pick a start time in the future.');
      }

      final repo = ref.read(eventsRepositoryProvider);
      String? coverUrl;
      if (cover != null) {
        coverUrl = await repo.uploadCover(userId: me, bytes: await cover.readAsBytes());
      }
      final event = await repo.create(
        organizerId: me,
        title: title,
        description: description.trim().isEmpty ? null : description,
        type: type,
        coverUrl: coverUrl,
        startsAt: startsAt,
        venueName: venueName,
        location: location,
        maxAttendees: maxAttendees,
        clubId: clubId,
        friendsOnly: friendsOnly,
      );
      createdId = event.id;
      ref.invalidate(mapEventsProvider);
      ref.invalidate(myEventsProvider);
    });
    return createdId;
  }
}

final createEventControllerProvider =
    AsyncNotifierProvider<CreateEventController, void>(CreateEventController.new);

/// Cover picker config: big enough for the details header, well under the 5 MB bucket limit.
Future<XFile?> pickCoverImage(ImageSource source) {
  return ImagePicker().pickImage(source: source, maxWidth: 1600, maxHeight: 1600, imageQuality: 85);
}
