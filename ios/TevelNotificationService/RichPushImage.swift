import Foundation

/// Rich-push image rules for the Notification Service Extension.
///
/// Payload contract (admin notifications composer): `aps.mutable-content = 1` and a
/// top-level `"imageUrl": "https://invoice.crm.tevel.space/public/push-images/<id>.<ext>"`.
/// Pure logic only (no UserNotifications), so RunnerTests can compile and test it.
enum RichPushImage {
  /// Hosts an image may be downloaded from. Nothing else is ever contacted.
  static let allowedHosts: Set<String> = ["invoice.crm.tevel.space"]
  static let payloadKey = "imageUrl"
  static let maxBytes = 5 * 1024 * 1024
  static let timeout: TimeInterval = 8

  enum Kind: String, CaseIterable {
    case jpeg, png, gif, heic

    var fileExtension: String { self == .jpeg ? "jpg" : rawValue }
    /// UTI passed as the attachment type hint.
    var typeIdentifier: String {
      switch self {
      case .jpeg: return "public.jpeg"
      case .png: return "public.png"
      case .gif: return "com.compuserve.gif"
      case .heic: return "public.heic"
      }
    }
  }

  /// The image URL, only when it is https on an allowed host (no credentials, default port).
  static func url(from userInfo: [AnyHashable: Any]) -> URL? {
    guard let raw = userInfo[payloadKey] as? String else { return nil }
    return validURL(raw)
  }

  static func validURL(_ raw: String) -> URL? {
    guard raw.count <= 2048,
          let components = URLComponents(string: raw),
          components.scheme?.lowercased() == "https",
          let host = components.host?.lowercased(), allowedHosts.contains(host),
          components.user == nil, components.password == nil,
          components.port == nil || components.port == 443,
          !components.path.isEmpty, components.path != "/",
          let url = components.url
    else { return nil }
    return url
  }

  /// Content-Type header (parameters ignored) → allowed kind.
  static func kind(contentType: String?) -> Kind? {
    guard let mime = contentType?.split(separator: ";").first?
      .trimmingCharacters(in: .whitespaces).lowercased() else { return nil }
    switch mime {
    case "image/jpeg", "image/jpg", "image/pjpeg": return .jpeg
    case "image/png": return .png
    case "image/gif": return .gif
    case "image/heic", "image/heif": return .heic
    default: return nil
    }
  }

  private static let heicBrands: Set<String> = ["heic", "heix", "heim", "heis", "mif1", "msf1"]

  /// Image kind from the file's magic bytes.
  static func sniff(_ data: Data) -> Kind? {
    let b = [UInt8](data.prefix(12))
    if b.count >= 3, b[0] == 0xFF, b[1] == 0xD8, b[2] == 0xFF { return .jpeg }
    if b.count >= 8, b[0..<8].elementsEqual([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]) { return .png }
    if b.count >= 6, let sig = String(bytes: b[0..<6], encoding: .ascii), sig == "GIF87a" || sig == "GIF89a" {
      return .gif
    }
    if b.count >= 12, String(bytes: b[4..<8], encoding: .ascii) == "ftyp",
       let brand = String(bytes: b[8..<12], encoding: .ascii), heicBrands.contains(brand) {
      return .heic
    }
    return nil
  }

  /// Accepts the body only when both the declared type and the bytes are an allowed image.
  /// The bytes decide the file extension (that is what the system decodes).
  static func accept(data: Data, contentType: String?) -> Kind? {
    guard !data.isEmpty, data.count <= maxBytes, kind(contentType: contentType) != nil else { return nil }
    return sniff(data)
  }

  /// Writes the image to a fresh temporary file the attachment can take over.
  static func write(_ data: Data, kind: Kind, in directory: URL = FileManager.default.temporaryDirectory) -> URL? {
    let file = directory.appendingPathComponent("tevel-push-\(UUID().uuidString).\(kind.fileExtension)")
    do {
      try data.write(to: file, options: .atomic)
      return file
    } catch { return nil }
  }
}

/// Downloads one image with the size/type/host limits. No cookies, no cache, no redirects off
/// the allow-list; any failure yields nil.
final class RichPushDownloader: NSObject, URLSessionDataDelegate {
  /// RunnerTests only: stubbed URLProtocols. Always nil in the extension.
  static var testProtocolClasses: [AnyClass]?
  private var session: URLSession?
  private var data = Data()
  private var contentType: String?
  private var completion: ((Data, RichPushImage.Kind)?) -> Void = { _ in }
  private let lock = NSLock()
  private var finished = false

  func start(_ url: URL, completion: @escaping ((Data, RichPushImage.Kind)?) -> Void) {
    self.completion = completion
    let config = URLSessionConfiguration.ephemeral
    config.timeoutIntervalForRequest = RichPushImage.timeout
    config.timeoutIntervalForResource = RichPushImage.timeout
    config.httpCookieStorage = nil
    config.httpShouldSetCookies = false
    config.urlCache = nil
    config.requestCachePolicy = .reloadIgnoringLocalCacheData
    config.waitsForConnectivity = false
    if let stubs = Self.testProtocolClasses { config.protocolClasses = stubs }
    let session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
    self.session = session
    var request = URLRequest(url: url)
    request.setValue("image/jpeg, image/png, image/gif, image/heic", forHTTPHeaderField: "Accept")
    session.dataTask(with: request).resume()
  }

  func cancel() { finish(nil) }

  private func finish(_ result: (Data, RichPushImage.Kind)?) {
    lock.lock()
    if finished { lock.unlock(); return }
    finished = true
    lock.unlock()
    session?.invalidateAndCancel()
    session = nil
    completion(result)
  }

  func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                  completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
    guard let http = response as? HTTPURLResponse, http.statusCode == 200,
          RichPushImage.kind(contentType: http.value(forHTTPHeaderField: "Content-Type")) != nil,
          http.expectedContentLength <= Int64(RichPushImage.maxBytes)
    else { completionHandler(.cancel); finish(nil); return }
    contentType = http.value(forHTTPHeaderField: "Content-Type")
    completionHandler(.allow)
  }

  func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive chunk: Data) {
    data.append(chunk)
    if data.count > RichPushImage.maxBytes { dataTask.cancel(); finish(nil) }
  }

  func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                  newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
    // Follow a redirect only if it stays https on an allowed host.
    completionHandler(request.url.flatMap { RichPushImage.validURL($0.absoluteString) } == nil ? nil : request)
  }

  func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
    guard error == nil, let kind = RichPushImage.accept(data: data, contentType: contentType) else {
      finish(nil); return
    }
    finish((data, kind))
  }
}
