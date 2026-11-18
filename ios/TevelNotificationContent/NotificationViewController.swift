import UIKit
import UserNotifications
import UserNotificationsUI

/// Expanded view (long-press / pull down) of a push with an image — category TEVEL_RICH, set by
/// the server and by TevelNotificationService once it attached the image. Shows the image at
/// full width, the title / subtitle / body, and "פתח" (the push's default action: the app opens
/// its `link`). The collapsed banner's small thumbnail is iOS's own and cannot be changed.
/// No network access: the image is the attachment the service extension already downloaded.
final class NotificationViewController: UIViewController, UNNotificationContentExtension {
  private let imageView = UIImageView()
  private let titleLabel = UILabel()
  private let subtitleLabel = UILabel()
  private let bodyLabel = UILabel()
  private let openButton = UIButton(type: .system)
  private var aspect: NSLayoutConstraint?

  override func viewDidLoad() {
    super.viewDidLoad()
    view.semanticContentAttribute = .forceRightToLeft
    view.backgroundColor = .systemBackground

    imageView.contentMode = .scaleAspectFill
    imageView.clipsToBounds = true
    imageView.layer.cornerRadius = 12
    imageView.backgroundColor = .secondarySystemBackground
    imageView.isAccessibilityElement = false

    titleLabel.font = .preferredFont(forTextStyle: .headline)
    subtitleLabel.font = .preferredFont(forTextStyle: .subheadline)
    subtitleLabel.textColor = .secondaryLabel
    bodyLabel.font = .preferredFont(forTextStyle: .body)
    for label in [titleLabel, subtitleLabel, bodyLabel] {
      label.numberOfLines = 0
      label.textAlignment = .natural
      label.adjustsFontForContentSizeCategory = true
    }

    var config = UIButton.Configuration.filled()
    config.title = "פתח"
    config.cornerStyle = .capsule
    config.baseBackgroundColor = UIColor(red: 0.29, green: 0.18, blue: 0.62, alpha: 1)
    openButton.configuration = config
    openButton.addTarget(self, action: #selector(open), for: .touchUpInside)

    let text = UIStackView(arrangedSubviews: [titleLabel, subtitleLabel, bodyLabel])
    text.axis = .vertical
    text.spacing = 4
    let stack = UIStackView(arrangedSubviews: [imageView, text, openButton])
    stack.axis = .vertical
    stack.spacing = 12
    stack.alignment = .fill
    stack.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(stack)
    NSLayoutConstraint.activate([
      stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
      stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
      stack.topAnchor.constraint(equalTo: view.topAnchor, constant: 12),
      stack.bottomAnchor.constraint(lessThanOrEqualTo: view.bottomAnchor, constant: -12),
      openButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 44),
    ])
    setAspect(1)
  }

  func didReceive(_ notification: UNNotification) {
    let content = notification.request.content
    titleLabel.text = content.title
    subtitleLabel.text = content.subtitle
    subtitleLabel.isHidden = content.subtitle.isEmpty
    bodyLabel.text = content.body
    let image = content.attachments.first.flatMap(Self.image(of:))
    imageView.image = image
    imageView.isHidden = image == nil
    if let image, image.size.width > 0 {
      // Never taller than 1.25 × the width (a tall poster stays readable with the text).
      setAspect(min(image.size.height / image.size.width, 1.25))
    }
    preferredContentSize = CGSize(width: view.bounds.width,
                                  height: view.systemLayoutSizeFitting(
                                    CGSize(width: view.bounds.width, height: 0),
                                    withHorizontalFittingPriority: .required,
                                    verticalFittingPriority: .fittingSizeLevel).height)
  }

  private func setAspect(_ ratio: CGFloat) {
    aspect?.isActive = false
    aspect = imageView.heightAnchor.constraint(equalTo: imageView.widthAnchor, multiplier: ratio)
    aspect?.priority = .defaultHigh
    aspect?.isActive = true
  }

  /// The attachment lives in the notification's store: security-scoped access only.
  static func image(of attachment: UNNotificationAttachment) -> UIImage? {
    let url = attachment.url
    let scoped = url.startAccessingSecurityScopedResource()
    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
    guard let data = try? Data(contentsOf: url) else { return nil }
    return UIImage(data: data)
  }

  @objc private func open() {
    extensionContext?.performNotificationDefaultAction()
  }
}
