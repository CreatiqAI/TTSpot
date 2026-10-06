import ActivityKit
import Flutter
import Foundation

// MethodChannel my.ttspot.app/live_activity. Dart side:
// lib/features/events/application/live_activity.dart. The widget extension
// (ios/TTSpotWidgets) draws what this starts.
//
//   supported -> Bool         iOS 16.1+ and Live Activities allowed for TT Spot
//   active    -> [String]     event ids with a running activity
//   start {eventId, title, venue, startsAt, endsAt (ms since epoch), type}
//             -> Bool         starts it, or refreshes the running one
//   end {eventId} / endAll    -> Int, how many ended
//
// The app's minimum is iOS 15, so everything is behind iOS 16.1 checks and
// ActivityKit is weak-linked (the Runner target links it as Optional).
enum LiveActivityBridge {
  static func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard #available(iOS 16.1, *) else {
      switch call.method {
      case "active": result([String]())
      case "end", "endAll": result(0)
      default: result(false)
      }
      return
    }
    LiveActivities.handle(call, result: result)
  }
}

@available(iOS 16.1, *)
private enum LiveActivities {
  typealias Attrs = TTSpotActivityAttributes

  static func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any] ?? [:]
    switch call.method {
    case "supported":
      result(ActivityAuthorizationInfo().areActivitiesEnabled)
    case "active":
      result(running().map { $0.attributes.eventId })
    case "start":
      start(args, result: result)
    case "end":
      let id = args["eventId"] as? String
      end(running().filter { $0.attributes.eventId == id }, result: result)
    case "endAll":
      end(running(), result: result)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  /// Activities still showing (active or stale).
  private static func running() -> [Activity<Attrs>] {
    Activity<Attrs>.activities.filter { $0.activityState != .ended && $0.activityState != .dismissed }
  }

  private static func date(_ v: Any?) -> Date? {
    guard let n = v as? NSNumber else { return nil }
    return Date(timeIntervalSince1970: n.doubleValue / 1000)
  }

  private static func start(_ args: [String: Any], result: @escaping FlutterResult) {
    guard let eventId = args["eventId"] as? String, !eventId.isEmpty,
          let startsAt = date(args["startsAt"]), var endsAt = date(args["endsAt"]) else {
      result(FlutterError(code: "bad_args", message: "eventId, startsAt and endsAt are required", details: nil))
      return
    }
    if endsAt < startsAt.addingTimeInterval(60) { endsAt = startsAt.addingTimeInterval(60) }
    let now = Date()
    guard now < endsAt, ActivityAuthorizationInfo().areActivitiesEnabled else {
      result(false)
      return
    }
    let state = Attrs.ContentState(
      title: (args["title"] as? String) ?? "Meet",
      venue: (args["venue"] as? String) ?? "",
      startsAt: startsAt,
      endsAt: endsAt,
      type: (args["type"] as? String) ?? "meet"
    )
    // iOS redraws the activity at the stale date: at the start it flips to
    // Live, at the end to Ended. No pushes, no updates in between.
    let stale = now < startsAt ? startsAt : endsAt

    if let existing = running().first(where: { $0.attributes.eventId == eventId }) {
      Task {
        if #available(iOS 16.2, *) {
          await existing.update(ActivityContent(state: state, staleDate: stale))
        } else {
          await existing.update(using: state)
        }
        DispatchQueue.main.async { result(true) }
      }
      return
    }
    do {
      if #available(iOS 16.2, *) {
        _ = try Activity<Attrs>.request(attributes: Attrs(eventId: eventId), content: ActivityContent(state: state, staleDate: stale), pushType: nil)
      } else {
        _ = try Activity<Attrs>.request(attributes: Attrs(eventId: eventId), contentState: state, pushType: nil)
      }
      result(true)
    } catch {
      result(FlutterError(code: "start_failed", message: error.localizedDescription, details: nil))
    }
  }

  private static func end(_ activities: [Activity<Attrs>], result: @escaping FlutterResult) {
    if activities.isEmpty {
      result(0)
      return
    }
    Task {
      for a in activities {
        if #available(iOS 16.2, *) {
          await a.end(nil, dismissalPolicy: .immediate)
        } else {
          await a.end(using: nil, dismissalPolicy: .immediate)
        }
      }
      DispatchQueue.main.async { result(activities.count) }
    }
  }
}
