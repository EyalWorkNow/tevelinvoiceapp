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
}
