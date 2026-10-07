/// Paths for Expo mode (docs/expo-mode-plan.md). Registered in app_router.
abstract final class ExpoRoutes {
  // ---- members
  static String pass(String eventId) => '/event/$eventId/pass';
  static String exhibitors(String eventId) => '/event/$eventId/exhibitors';
  static String schedule(String eventId) => '/event/$eventId/schedule';
  static String stamps(String eventId) => '/event/$eventId/stamps';
  static String vote(String eventId, {String? contestId}) => contestId == null ? '/event/$eventId/vote' : '/event/$eventId/vote?contest=$contestId';

  /// Booth staff: the leads their booth scanned.
  static String leads(String eventId, String exhibitorId) => '/event/$eventId/booth/$exhibitorId/leads';

  /// The floor plan, zoomed to an exhibitor's booths.
  static String floorplanAt(String eventId, String exhibitorId) => '/event/$eventId/floorplan?exhibitor=$exhibitorId';

  /// The floor plan right after a door check-in ("You're in · #0427").
  static String floorplanWelcome(String eventId) => '/event/$eventId/floorplan?welcome=1';

  // ---- hosts (organizer tools)
  static String checkinArea(String eventId) => '/event-tools/$eventId/area';
  static String registrationForm(String eventId) => '/event-tools/$eventId/form';
  static String exhibitorsEditor(String eventId) => '/event-tools/$eventId/exhibitors';
  static String boothSetup(String eventId) => '/event-tools/$eventId/booths';
  static String scheduleEditor(String eventId) => '/event-tools/$eventId/schedule';
  static String contestEditor(String eventId) => '/event-tools/$eventId/vote';
  static String dashboard(String eventId) => '/event-tools/$eventId/dashboard';
}
