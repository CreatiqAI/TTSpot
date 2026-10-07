import ActivityKit
import Foundation

// Shared by the app (Runner starts and ends the activity, see
// Runner/LiveActivityBridge.swift) and the widget extension (draws it).
// Both targets compile this file, so the two always agree on the shape.

/// One TT Spot meet on the lock screen / Dynamic Island. Everything the view
/// shows lives in [ContentState], so the app can refresh it (a renamed meet,
/// a new start time) without ending the activity.
@available(iOS 16.1, *)
struct TTSpotActivityAttributes: ActivityAttributes {
  public struct ContentState: Codable, Hashable {
    var title: String
    var venue: String
    var startsAt: Date
    /// After [startsAt]; the bridge makes sure.
    var endsAt: Date
    /// `events.event_type` ('meet', 'tt', 'convoy', 'trackday', 'charity', 'official').
    var type: String
    /// Optional pill next to the title, e.g. my entry number "#0427" once
    /// checked in (Expo mode). Optional so older payloads still decode.
    var badge: String? = nil
  }

  /// `events.id`: finds the activity again to update or end it.
  var eventId: String
}
