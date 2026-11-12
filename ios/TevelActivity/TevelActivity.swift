import ActivityKit
import SwiftUI
import WidgetKit

@main
struct TevelActivityBundle: WidgetBundle {
  var body: some Widget { TevelActivityWidget() }
}

struct TevelActivityWidget: Widget {
  var body: some WidgetConfiguration {
    ActivityConfiguration(for: TevelActivityAttributes.self) { context in
      HStack(spacing: 16) {
        EventSeal(state: context.state, large: true)
        VStack(alignment: .leading, spacing: 6) {
          Text(context.state.title).font(.headline).contentTransition(.opacity)
          Text(context.state.detail).font(.subheadline).foregroundStyle(.white.opacity(0.7))
        }
        Spacer(minLength: 0)
        Image(systemName: "arrow.up.left").font(.caption.bold()).foregroundStyle(.white.opacity(0.45))
      }
      .padding(20)
      .environment(\.layoutDirection, .rightToLeft)
      .activityBackgroundTint(.black)
      .activitySystemActionForegroundColor(.white)
      .widgetURL(context.attributes.destination)
    } dynamicIsland: { context in
      DynamicIsland {
        DynamicIslandExpandedRegion(.leading) {
          EventSeal(state: context.state, large: true).padding(.leading, 4)
        }
        DynamicIslandExpandedRegion(.trailing) {
          Text("תבל").font(.caption.weight(.semibold)).foregroundStyle(accent(context.state.kind))
            .padding(.trailing, 6)
        }
        DynamicIslandExpandedRegion(.bottom) {
          VStack(alignment: .trailing, spacing: 7) {
            Text(context.state.title).font(.headline).contentTransition(.opacity)
            Text(context.state.detail).font(.subheadline).foregroundStyle(.white.opacity(0.65))
            Capsule().fill(LinearGradient(colors: [accent(context.state.kind).opacity(0.1),
              accent(context.state.kind)], startPoint: .leading, endPoint: .trailing)).frame(height: 2)
          }
          .frame(maxWidth: .infinity, alignment: .trailing)
          .padding(.horizontal, 8).padding(.bottom, 6)
          .animation(.spring(response: 0.55, dampingFraction: 0.65), value: context.state.revision)
        }
      } compactLeading: {
        EventSeal(state: context.state, large: false)
      } compactTrailing: {
        Image(systemName: symbol(context.state.kind)).font(.system(size: 14, weight: .bold))
          .foregroundStyle(accent(context.state.kind))
          .contentTransition(.symbolEffect(.replace))
      } minimal: {
        EventSeal(state: context.state, large: false)
      }
      .widgetURL(context.attributes.destination)
      .keylineTint(accent(context.state.kind))
    }
  }
}

private func accent(_ kind: String) -> Color {
  switch kind {
  case "approved", "payment": return Color(red: 0.51, green: 1, blue: 0.66)
  case "reminder": return Color(red: 0.98, green: 0.35, blue: 0.49)
  case "error", "rejected": return Color(red: 0.87, green: 0.51, blue: 0.42)
  default: return Color(red: 0.84, green: 0.74, blue: 0.95)
  }
}

private func symbol(_ kind: String) -> String {
  switch kind {
  case "approved": return "checkmark.seal.fill"
  case "payment": return "shekelsign.circle.fill"
  case "reminder": return "bell.badge.fill"
  case "rejected", "error": return "exclamationmark.circle.fill"
  case "viewed": return "eye.fill"
  case "expense": return "receipt.fill"
  case "reminder": return "phone.arrow.up.right.fill"
  case "visit": return "calendar.badge.clock"
  case "collection": return "creditcard.fill"
  case "issued": return "doc.fill"
  case "sent": return "paperplane.fill"
  case "signed": return "signature"
  default: return "doc.text.fill"
  }
}

private struct EventSeal: View {
  let state: TevelActivityAttributes.ContentState
  let large: Bool
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    ZStack {
      if large {
        Circle().fill(accent(state.kind).opacity(0.12))
        Circle().strokeBorder(accent(state.kind).opacity(0.3), lineWidth: 1)
      }
      Image(systemName: symbol(state.kind))
        .font(.system(size: large ? 27 : 16, weight: .semibold))
        .foregroundStyle(accent(state.kind))
        .symbolEffect(.bounce, options: .nonRepeating, value: reduceMotion ? 0 : state.revision)
        .contentTransition(.symbolEffect(.replace))
    }
    .frame(width: large ? 52 : 22, height: large ? 52 : 22)
    .accessibilityHidden(true)
  }
}
