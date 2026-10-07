import ActivityKit
import SwiftUI
import WidgetKit

// The meet Live Activity: lock screen banner + Dynamic Island.
//
// Before the start: "Starts in 1:12:05" counting down. From the start:
// "Live" with the time since the start counting up, until the meet ends.
// Both timers run on the phone (Text timer styles), so nothing is pushed or
// updated while it shows. The app starts it with staleDate = the start time,
// so iOS redraws it once at the start and the view flips to Live by itself
// (iOS 16.2+). The app ends it on its next open after the meet ends, or when
// the member leaves the meet.

private let brandRed = Color(red: 224 / 255, green: 0, blue: 8 / 255) // #E00008, the logo red

private enum Phase { case soon, live, ended }

/// Event type mark: SF Symbol, label and the app's colour for the type.
private struct Kind {
  let symbol: String
  let label: String
  let color: Color

  static func of(_ type: String) -> Kind {
    switch type {
    case "tt": return Kind(symbol: "cup.and.saucer.fill", label: "TT", color: Color(red: 0.96, green: 0.65, blue: 0.14))
    case "convoy": return Kind(symbol: "road.lanes", label: "Convoy", color: Color(red: 0.23, green: 0.51, blue: 0.96))
    case "trackday": return Kind(symbol: "flag.checkered", label: "Track day", color: Color(red: 0.13, green: 0.77, blue: 0.37))
    case "charity": return Kind(symbol: "heart.fill", label: "Charity", color: Color(red: 0.93, green: 0.28, blue: 0.60))
    case "official": return Kind(symbol: "trophy.fill", label: "Official", color: Color(red: 0.66, green: 0.33, blue: 0.97))
    default: return Kind(symbol: "car.fill", label: "Meet", color: Color(red: 1, green: 0.24, blue: 0.12))
    }
  }
}

@available(iOS 16.1, *)
struct TTSpotLiveActivity: Widget {
  var body: some WidgetConfiguration {
    ActivityConfiguration(for: TTSpotActivityAttributes.self) { context in
      LockScreenView(state: context.state, phase: phase(context))
        .activityBackgroundTint(Color.black)
        .activitySystemActionForegroundColor(Color.white)
        .widgetURL(link(context))
    } dynamicIsland: { context in
      let s = context.state
      let p = phase(context)
      let kind = Kind.of(s.type)
      return DynamicIsland {
        DynamicIslandExpandedRegion(.leading) {
          HStack(spacing: 6) {
            Mark(height: 16)
            Image(systemName: kind.symbol).font(.system(size: 13, weight: .semibold)).foregroundColor(kind.color)
          }
          .padding(.leading, 4)
        }
        DynamicIslandExpandedRegion(.trailing) {
          Caption(phase: p)
            .padding(.trailing, 4)
        }
        DynamicIslandExpandedRegion(.center) {
          HStack(spacing: 6) {
            Text(s.title)
              .font(.system(size: 15, weight: .bold))
              .foregroundColor(.white)
              .lineLimit(1)
            if let badge = s.badge {
              EntryPill(text: badge)
            }
          }
        }
        DynamicIslandExpandedRegion(.bottom) {
          HStack(alignment: .firstTextBaseline) {
            Venue(name: s.venue)
            Spacer(minLength: 8)
            Clock(phase: p, state: s, size: 22)
              .frame(maxWidth: 120, alignment: .trailing)
          }
          .padding(.horizontal, 4)
        }
      } compactLeading: {
        Mark(height: 12)
      } compactTrailing: {
        Clock(phase: p, state: s, size: 14)
          .frame(maxWidth: 58)
      } minimal: {
        Image(systemName: kind.symbol)
          .font(.system(size: 12, weight: .semibold))
          .foregroundColor(p == .live ? brandRed : kind.color)
      }
      .widgetURL(link(context))
      .keylineTint(brandRed)
    }
  }

  private func link(_ context: ActivityViewContext<TTSpotActivityAttributes>) -> URL? {
    URL(string: "ttspot://event/\(context.attributes.eventId)")
  }

  /// Worked out from the clock each time iOS draws it. The staleDate redraw at
  /// the start (and at the end, once Live) is what moves it on.
  private func phase(_ context: ActivityViewContext<TTSpotActivityAttributes>) -> Phase {
    let s = context.state
    let now = Date()
    if now >= s.endsAt { return .ended }
    if now >= s.startsAt { return .live }
    if #available(iOS 16.2, *), context.isStale { return .live } // redrawn a moment early
    return .soon
  }
}

// MARK: - Pieces

@available(iOS 16.1, *)
private struct LockScreenView: View {
  let state: TTSpotActivityAttributes.ContentState
  let phase: Phase

  var body: some View {
    let kind = Kind.of(state.type)
    HStack(alignment: .center, spacing: 12) {
      VStack(alignment: .leading, spacing: 5) {
        HStack(spacing: 6) {
          Mark(height: 14)
          Image(systemName: kind.symbol).font(.system(size: 11, weight: .bold)).foregroundColor(kind.color)
          Text(kind.label).font(.system(size: 12, weight: .semibold)).foregroundColor(kind.color)
        }
        HStack(spacing: 6) {
          Text(state.title)
            .font(.system(size: 17, weight: .bold))
            .foregroundColor(.white)
            .lineLimit(1)
          if let badge = state.badge {
            EntryPill(text: badge)
          }
        }
        Venue(name: state.venue)
      }
      Spacer(minLength: 8)
      VStack(alignment: .trailing, spacing: 2) {
        Caption(phase: phase)
        Clock(phase: phase, state: state, size: 26)
      }
      .frame(maxWidth: 130, alignment: .trailing)
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 14)
  }
}

/// The TT mark from the logo (white + red, for the black background).
private struct Mark: View {
  let height: CGFloat
  var body: some View {
    Image("TTSpotMark")
      .resizable()
      .aspectRatio(contentMode: .fit)
      .frame(height: height)
      .accessibilityLabel("TT Spot")
  }
}

/// A small pill next to the title: my entry number once checked in.
private struct EntryPill: View {
  let text: String
  var body: some View {
    Text(text)
      .font(.system(size: 12, weight: .heavy, design: .rounded))
      .monospacedDigit()
      .foregroundColor(.white)
      .lineLimit(1)
      .fixedSize()
      .padding(.horizontal, 7)
      .padding(.vertical, 2)
      .background(Capsule().fill(brandRed))
  }
}

private struct Venue: View {
  let name: String
  var body: some View {
    HStack(spacing: 4) {
      Image(systemName: "mappin.and.ellipse").font(.system(size: 11, weight: .semibold))
      Text(name).font(.system(size: 13, weight: .medium)).lineLimit(1)
    }
    .foregroundColor(Color.white.opacity(0.7))
  }
}

/// "Starts in" / "● Live" (nothing once ended: the clock says it).
private struct Caption: View {
  let phase: Phase
  var body: some View {
    switch phase {
    case .soon:
      Text("Starts in").font(.system(size: 12, weight: .semibold)).foregroundColor(Color.white.opacity(0.6))
    case .live:
      HStack(spacing: 4) {
        Circle().fill(brandRed).frame(width: 6, height: 6)
        Text("Live").font(.system(size: 12, weight: .bold)).foregroundColor(brandRed)
      }
    case .ended:
      EmptyView()
    }
  }
}

/// The running clock: time to the start, then time since the start (it stops
/// at the end). Text timers tick on the phone with no updates.
@available(iOS 16.1, *)
private struct Clock: View {
  let phase: Phase
  let state: TTSpotActivityAttributes.ContentState
  let size: CGFloat
  var body: some View {
    Group {
      switch phase {
      case .soon:
        // Stops at 0:00 if the redraw at the start is late.
        Text(timerInterval: Date()...max(Date(), state.startsAt), countsDown: true)
          .foregroundColor(.white)
      case .live:
        Text(timerInterval: state.startsAt...max(state.startsAt, state.endsAt), countsDown: false)
          .foregroundColor(.white)
      case .ended:
        Text("Ended").foregroundColor(Color.white.opacity(0.6))
      }
    }
    .font(.system(size: size, weight: .bold, design: .rounded))
    .monospacedDigit()
    .multilineTextAlignment(.trailing)
    .lineLimit(1)
  }
}
