import Flutter
import UIKit
import XCTest
@testable import Runner

class RunnerTests: XCTestCase {

  func testExample() {
    // If you add code to the Runner application, consider adding tests here.
    // See https://developer.apple.com/documentation/xctest for more information about using XCTest.
  }

}


/// invoice#60 admin/template announcements: the banner keeps the server's text,
/// only a tap is forwarded (to open `link`).
final class SystemNoticesReceiveTests: XCTestCase {
  func testAnnouncementKeepsBannerAndOpensLinkOnTap() {
    let push: [AnyHashable: Any] = ["kind": "ANNOUNCEMENT", "link": "/business/account", "imageUrl": "https://invoice.crm.tevel.space/public/push-images/a.png"]
    XCTAssertFalse(SystemNotices.shared.receive(push, opened: false))
    XCTAssertTrue(SystemNotices.shared.receive(push, opened: true))
    XCTAssertTrue(SystemNotices.shared.receive(["kind": "ANNOUNCEMENT", "link": "/home", "businessId": "b_1"], opened: true))
  }

  /// 0124: the ordinary push of a notch announcement becomes the in-app notch notice in the
  /// foreground (the banner is suppressed); taps behave as before.
  func testNotchFallbackPushIsShownInApp() {
    let push: [AnyHashable: Any] = [
      "kind": "ANNOUNCEMENT", "link": "/people", "display": "notch",
      "pushId": "0f8fad5b-d9cb-469f-a165-70867728950e",
      "aps": ["alert": ["title": "מבצע", "body": "חודש במתנה"]],
    ]
    XCTAssertTrue(SystemNotices.shared.receive(push, opened: false))
    XCTAssertTrue(SystemNotices.shared.receive(push, opened: true))
    var noText = push
    noText["aps"] = ["alert": ["body": "x"]]
    XCTAssertFalse(SystemNotices.shared.receive(noText, opened: false))
    var standard = push
    standard.removeValue(forKey: "display")
    XCTAssertFalse(SystemNotices.shared.receive(standard, opened: false))
  }

  func testAnnouncementEventGuardsRoute() {
    XCTAssertNotNil(SystemNotices.announcementEvent(title: "t", body: "b", route: "/business/account",
                                                    businessID: "", eventID: "e"))
    XCTAssertNil(SystemNotices.announcementEvent(title: "t", body: "b", route: "/admin",
                                                 businessID: "", eventID: "e"))
    XCTAssertNil(SystemNotices.announcementEvent(title: "", body: "b", route: "/home",
                                                 businessID: "", eventID: "e"))
    let long = String(repeating: "א", count: 500)
    let event = SystemNotices.announcementEvent(title: long, body: long, route: "/home",
                                                businessID: "b", eventID: "e")!
    XCTAssertEqual((event["title"] as? String)?.count, 120)
    XCTAssertEqual((event["body"] as? String)?.count, 240)
  }

  @available(iOS 17.2, *)
  func testAnnouncementActivityStateDecodesOldAndNewPayloads() throws {
    typealias State = TevelActivityAttributes.ContentState
    let old = try JSONDecoder().decode(State.self, from: Data(
      #"{"kind":"approved","title":"t","detail":"d","revision":1}"#.utf8))
    XCTAssertNil(old.icon)
    XCTAssertFalse(old.isAnnouncement)
    let new = try JSONDecoder().decode(State.self, from: Data(
      #"{"kind":"announcement","title":"t","detail":"d","revision":1,"icon":"gift","endsAt":1900000000}"#.utf8))
    XCTAssertTrue(new.isAnnouncement)
    XCTAssertEqual(new.endDate, Date(timeIntervalSince1970: 1_900_000_000))
    XCTAssertEqual(TevelAnnouncementIcon.symbol("gift"), "gift.fill")
    XCTAssertEqual(TevelAnnouncementIcon.symbol("unknown"), "megaphone.fill")
    for route in ["/people", "/business/account", "/home", "/quote/q1"] {
      XCTAssertNotNil(TevelActivityAttributes(eventID: "e", route: route, businessID: "b").destination, route)
    }
    for route in ["/admin", "https://x", "/doc/../x"] {
      XCTAssertNil(TevelActivityAttributes(eventID: "e", route: route, businessID: "b").destination, route)
    }
  }

  func testAnnouncementWithUnsafeLinkOnlyOpensTheApp() {
    for link in ["https://evil.example", "/admin", "/doc/../x", ""] {
      XCTAssertFalse(SystemNotices.shared.receive(["kind": "ANNOUNCEMENT", "link": link], opened: true), link)
    }
    XCTAssertFalse(SystemNotices.shared.receive(["kind": "ANNOUNCEMENT"], opened: true))
  }

  func testCatalogueAndUnknownKindsUnchanged() {
    XCTAssertTrue(SystemNotices.shared.receive(["kind": "QUOTE_SIGNED", "link": "/quote/q1", "businessId": "b1"], opened: false))
    XCTAssertTrue(SystemNotices.shared.receive(["tevelKind": "approved", "route": "/home", "businessId": "b1"], opened: false))
    XCTAssertFalse(SystemNotices.shared.receive(["kind": "SOMETHING_NEW", "link": "/home"], opened: true))
  }

  func testPushOpenedOnlyForWellFormedPushId() {
    XCTAssertTrue(SystemNotices.shared.reportOpened(["pushId": "0f8fad5b-d9cb-469f-a165-70867728950e", "kind": "ANNOUNCEMENT"]))
    XCTAssertTrue(SystemNotices.shared.reportOpened(["pushId": "0F8FAD5B-D9CB-469F-A165-70867728950E"]))
    XCTAssertFalse(SystemNotices.shared.reportOpened(["pushId": "x; drop"]))
    XCTAssertFalse(SystemNotices.shared.reportOpened(["pushId": 7]))
    XCTAssertFalse(SystemNotices.shared.reportOpened(["kind": "QUOTE_SIGNED"]))
  }
}
