import ActivityKit
import Foundation

@available(iOS 17.2, *)
struct TevelActivityAttributes: ActivityAttributes {
  struct ContentState: Codable, Hashable {
    var kind: String
    var title: String
    var detail: String
    var revision: Int
  }

  var eventID: String
  var route: String
  var businessID: String

  var destination: URL? {
    guard route.range(of: "^(/(home|activity|expenses)|/(quote|doc|person)/[A-Za-z0-9_-]{1,64})$", options: .regularExpression) != nil
    else { return nil }
    guard var destination = URLComponents(string: "tevel:/" + route) else { return nil }
    if businessID != "preview" {
      destination.queryItems = [URLQueryItem(name: "businessId", value: businessID)]
    }
    return destination.url
  }
}
