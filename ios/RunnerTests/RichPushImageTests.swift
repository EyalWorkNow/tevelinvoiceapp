import UIKit
import UserNotifications
import XCTest

/// RichPushImage.swift is compiled into this target as well as the extension.
final class RichPushImageTests: XCTestCase {
  private let jpeg = Data([0xFF, 0xD8, 0xFF, 0xE0, 0, 0x10, 0x4A, 0x46, 0x49, 0x46, 0, 1])
  private let png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0, 0, 0, 0x0D])
  private let gif = Data("GIF89a\u{1}\u{0}\u{1}\u{0}\u{0}\u{0}".utf8)
  private let heic = Data([0, 0, 0, 0x18] + Array("ftypheic".utf8) + [0, 0, 0, 0])

  func testAcceptsOnlyHttpsAllowListedHost() {
    let ok = "https://invoice.crm.tevel.space/public/push-images/abc123.png"
    XCTAssertEqual(RichPushImage.url(from: ["imageUrl": ok])?.absoluteString, ok)
    XCTAssertNotNil(RichPushImage.validURL("https://INVOICE.crm.tevel.space:443/public/push-images/a.jpg"))
    for bad in [
      "http://invoice.crm.tevel.space/public/push-images/a.png",
      "https://evil.example/a.png",
      "https://invoice.crm.tevel.space.evil.example/a.png",
      "https://user:pw@invoice.crm.tevel.space/a.png",
      "https://invoice.crm.tevel.space:8443/a.png",
      "https://invoice.crm.tevel.space/",
      "file:///etc/passwd",
      "not a url",
    ] {
      XCTAssertNil(RichPushImage.validURL(bad), bad)
    }
    XCTAssertNil(RichPushImage.url(from: [:]))
    XCTAssertNil(RichPushImage.url(from: ["imageUrl": 42]))
    XCTAssertNil(RichPushImage.url(from: ["imageURL": ok]))
  }

  func testContentTypes() {
    XCTAssertEqual(RichPushImage.kind(contentType: "image/jpeg"), .jpeg)
    XCTAssertEqual(RichPushImage.kind(contentType: "IMAGE/PNG; charset=binary"), .png)
    XCTAssertEqual(RichPushImage.kind(contentType: "image/gif"), .gif)
    XCTAssertEqual(RichPushImage.kind(contentType: "image/heic"), .heic)
    XCTAssertNil(RichPushImage.kind(contentType: "image/svg+xml"))
    XCTAssertNil(RichPushImage.kind(contentType: "text/html"))
    XCTAssertNil(RichPushImage.kind(contentType: nil))
  }

  func testMagicBytes() {
    XCTAssertEqual(RichPushImage.sniff(jpeg), .jpeg)
    XCTAssertEqual(RichPushImage.sniff(png), .png)
    XCTAssertEqual(RichPushImage.sniff(gif), .gif)
    XCTAssertEqual(RichPushImage.sniff(heic), .heic)
    XCTAssertNil(RichPushImage.sniff(Data("<html>".utf8)))
    XCTAssertNil(RichPushImage.sniff(Data()))
  }

  func testAcceptNeedsTypeBytesAndSize() {
    XCTAssertEqual(RichPushImage.accept(data: png, contentType: "image/png"), .png)
    // Bytes decide the kind when the declared image type differs.
    XCTAssertEqual(RichPushImage.accept(data: png, contentType: "image/jpeg"), .png)
    XCTAssertNil(RichPushImage.accept(data: png, contentType: "application/octet-stream"))
    XCTAssertNil(RichPushImage.accept(data: Data("<svg/>".utf8), contentType: "image/png"))
    var big = jpeg
    big.append(Data(count: RichPushImage.maxBytes))
    XCTAssertNil(RichPushImage.accept(data: big, contentType: "image/jpeg"))
  }

  func testWriteUsesSniffedExtension() throws {
    let file = try XCTUnwrap(RichPushImage.write(png, kind: .png))
    defer { try? FileManager.default.removeItem(at: file) }
    XCTAssertEqual(file.pathExtension, "png")
    XCTAssertEqual(try Data(contentsOf: file), png)
  }
}

/// Serves canned responses for https://invoice.crm.tevel.space/… without the network.
final class StubImageProtocol: URLProtocol {
  static var responses: [String: (status: Int, type: String, body: Data)] = [:]
  static var requested: [String] = []
  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
  override func startLoading() {
    let url = request.url!
    Self.requested.append(url.absoluteString)
    guard let r = Self.responses[url.absoluteString] else {
      client?.urlProtocol(self, didFailWithError: URLError(.cannotConnectToHost)); return
    }
    let response = HTTPURLResponse(url: url, statusCode: r.status, httpVersion: "HTTP/1.1",
                                   headerFields: ["Content-Type": r.type, "Content-Length": "\(r.body.count)"])!
    client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(self, didLoad: r.body)
    client?.urlProtocolDidFinishLoading(self)
  }
  override func stopLoading() {}
}

final class NotificationServiceTests: XCTestCase {
  private let base = "https://invoice.crm.tevel.space/public/push-images/"

  override func setUp() {
    RichPushDownloader.testProtocolClasses = [StubImageProtocol.self]
    StubImageProtocol.responses = [:]
    StubImageProtocol.requested = []
  }
  override func tearDown() { RichPushDownloader.testProtocolClasses = nil }

  private func pngData() -> Data {
    let renderer = UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8))
    return renderer.pngData { ctx in UIColor.systemTeal.setFill(); ctx.fill(CGRect(x: 0, y: 0, width: 8, height: 8)) }
  }

  private func run(_ userInfo: [AnyHashable: Any]) -> UNNotificationContent {
    let content = UNMutableNotificationContent()
    content.title = "תבל"
    content.body = "גוף"
    content.userInfo = userInfo
    let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
    let service = NotificationService()
    let done = expectation(description: "delivered")
    var delivered: UNNotificationContent?
    service.didReceive(request) { delivered = $0; done.fulfill() }
    wait(for: [done], timeout: 10)
    return delivered!
  }

  func testAttachesAllowedImage() {
    StubImageProtocol.responses[base + "a.png"] = (200, "image/png", pngData())
    let out = run(["imageUrl": base + "a.png", "kind": "ANNOUNCEMENT"])
    XCTAssertEqual(out.attachments.count, 1)
    XCTAssertEqual(out.attachments.first?.identifier, "image")
    XCTAssertEqual(out.title, "תבל")
    XCTAssertEqual(out.userInfo["kind"] as? String, "ANNOUNCEMENT")
  }

  func testPassThroughWithoutImageMakesNoRequest() {
    let out = run(["tevelKind": "approved", "route": "/home", "businessId": "b1"])
    XCTAssertTrue(out.attachments.isEmpty)
    XCTAssertEqual(out.userInfo["route"] as? String, "/home")
    XCTAssertTrue(StubImageProtocol.requested.isEmpty)
  }

  func testDisallowedHostIsNeverFetched() {
    let out = run(["imageUrl": "https://evil.example/a.png"])
    XCTAssertTrue(out.attachments.isEmpty)
    XCTAssertTrue(StubImageProtocol.requested.isEmpty)
  }

  func testFailuresDeliverOriginal() {
    StubImageProtocol.responses[base + "404.png"] = (404, "image/png", pngData())
    StubImageProtocol.responses[base + "html.png"] = (200, "text/html", Data("<html>".utf8))
    StubImageProtocol.responses[base + "fake.png"] = (200, "image/png", Data("<svg/>".utf8))
    for name in ["404.png", "html.png", "fake.png", "missing.png"] {
      let out = run(["imageUrl": base + name])
      XCTAssertTrue(out.attachments.isEmpty, name)
      XCTAssertEqual(out.body, "גוף", name)
    }
  }

  func testOversizedImageIsDropped() {
    var big = pngData()
    big.append(Data(count: RichPushImage.maxBytes))
    StubImageProtocol.responses[base + "big.png"] = (200, "image/png", big)
    XCTAssertTrue(run(["imageUrl": base + "big.png"]).attachments.isEmpty)
  }

  func testTimeWillExpireDeliversOriginalOnce() {
    let content = UNMutableNotificationContent()
    content.body = "x"
    content.userInfo = ["imageUrl": base + "slow.png"]  // no stub → fails, but we expire first
    let service = NotificationService()
    var calls = 0
    let done = expectation(description: "once")
    done.assertForOverFulfill = true
    service.didReceive(UNNotificationRequest(identifier: "t", content: content, trigger: nil)) { delivered in
      calls += 1
      XCTAssertTrue(delivered.attachments.isEmpty)
      done.fulfill()
    }
    service.serviceExtensionTimeWillExpire()
    wait(for: [done], timeout: 5)
    XCTAssertEqual(calls, 1)
  }
}
