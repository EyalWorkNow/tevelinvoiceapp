import UserNotifications

/// Adds the payload's `imageUrl` as an image attachment. Every other push (the server sets
/// `mutable-content` on all of them) passes through untouched, and any failure delivers the
/// original notification unchanged. The only network call is that one image download.
final class NotificationService: UNNotificationServiceExtension {
  private let lock = NSLock()
  private var contentHandler: ((UNNotificationContent) -> Void)?
  private var original: UNNotificationContent?
  private var downloader: RichPushDownloader?

  override func didReceive(_ request: UNNotificationRequest,
                           withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void) {
    lock.lock()
    self.contentHandler = contentHandler
    original = request.content
    lock.unlock()

    guard let url = RichPushImage.url(from: request.content.userInfo),
          let content = request.content.mutableCopy() as? UNMutableNotificationContent
    else { deliver(request.content); return }

    let downloader = RichPushDownloader()
    lock.lock(); self.downloader = downloader; lock.unlock()
    downloader.start(url) { [weak self] result in
      guard let self else { return }
      guard let (data, kind) = result,
            let file = RichPushImage.write(data, kind: kind),
            let attachment = try? UNNotificationAttachment(
              identifier: "image", url: file, options: RichPushImage.attachmentOptions(data, kind: kind))
      else { self.deliver(request.content); return }
      // The full-resolution download (never a server thumbnail). iOS always shows it as a small
      // square in the collapsed banner; the content extension (TEVEL_RICH) shows it full width
      // when the notification is expanded.
      content.attachments = [attachment]
      content.categoryIdentifier = RichPushImage.richCategory
      self.deliver(content)
    }
  }

  override func serviceExtensionTimeWillExpire() {
    lock.lock(); let downloader = self.downloader; let original = self.original; lock.unlock()
    if let original { deliver(original) }
    downloader?.cancel()
  }

  /// Calls the system's handler exactly once.
  private func deliver(_ content: UNNotificationContent) {
    lock.lock()
    let handler = contentHandler
    contentHandler = nil
    lock.unlock()
    handler?(content)
  }
}

extension RichPushImage {
  /// Attachment options: the type hint, and for a non-square image a centred square thumbnail
  /// clip (the collapsed banner's thumbnail is square; a wide banner image keeps its middle).
  static func attachmentOptions(_ data: Data, kind: Kind) -> [String: Any] {
    var options: [String: Any] = [UNNotificationAttachmentOptionsTypeHintKey: kind.typeIdentifier]
    if let clip = thumbnailClip(data) {
      options[UNNotificationAttachmentOptionsThumbnailClippingRectKey] =
        clip.dictionaryRepresentation
    }
    return options
  }
}
