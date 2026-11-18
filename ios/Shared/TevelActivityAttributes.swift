import ActivityKit
import Foundation

@available(iOS 17.2, *)
struct TevelActivityAttributes: ActivityAttributes {
  struct ContentState: Codable, Hashable {
    var kind: String
    var title: String
    var detail: String
    var revision: Int
    /// Admin "נוטצ׳" announcements (server 0124, kind "announcement"): a bundled symbol key
    /// (`TevelAnnouncementIcon`) and when the activity should go (Unix seconds). Optional, so
    /// business-event activities and older payloads decode unchanged.
    var icon: String?
    var endsAt: Double?

    var isAnnouncement: Bool { kind == "announcement" }
    var endDate: Date? { endsAt.map { Date(timeIntervalSince1970: $0) } }
  }

  var eventID: String
  var route: String
  var businessID: String

  /// Business events open their entity; announcements open one of the admin's screens
  /// (the same allow-list as SystemNotices.allowedRoute; Dart re-checks with AppRoute.parse).
  static let allowedRoute =
    "^(/(home|activity|expenses|calendar|debts|reports|people)|/(quote|doc|person|sign-request)/[A-Za-z0-9_-]{1,64}|/business/[a-z]{2,20})$"

  var destination: URL? {
    guard route.range(of: Self.allowedRoute, options: .regularExpression) != nil
    else { return nil }
    guard var destination = URLComponents(string: "tevel:/" + route) else { return nil }
    if businessID != "preview" && !businessID.isEmpty {
      destination.queryItems = [URLQueryItem(name: "businessId", value: businessID)]
    }
    return destination.url
  }
}

/// Symbols a notch announcement may show (server NOTCH_ICONS). SF Symbols ship with iOS, so the
/// Live Activity needs no image download (it cannot make one).
enum TevelAnnouncementIcon {
  static func symbol(_ key: String?) -> String {
    switch key {
    case "gift": return "gift.fill"
    case "sparkles": return "sparkles"
    case "bell": return "bell.badge.fill"
    case "star": return "star.fill"
    case "tag": return "tag.fill"
    case "info": return "info.circle.fill"
    case "heart": return "heart.fill"
    default: return "megaphone.fill"
    }
  }
}
