import Flutter
import UIKit
import UniformTypeIdentifiers
import MessageUI
import UserNotifications
import Contacts

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    excludeLocalDataFromBackup()
    UNUserNotificationCenter.current().delegate = self
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  override func userNotificationCenter(_ center: UNUserNotificationCenter,
      willPresent notification: UNNotification,
      withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
    if SystemNotices.shared.receive(notification.request.content.userInfo, opened: false),
       applicationStateIsActive {
      completionHandler([])
    } else {
      completionHandler([.banner, .sound])
    }
  }

  private var applicationStateIsActive: Bool { UIApplication.shared.applicationState == .active }

  override func userNotificationCenter(_ center: UNUserNotificationCenter,
      didReceive response: UNNotificationResponse,
      withCompletionHandler completionHandler: @escaping () -> Void) {
    _ = SystemNotices.shared.receive(response.notification.request.content.userInfo, opened: true)
    completionHandler()
  }

  /// lib/state/cache.dart keeps in-progress issue/payment state (customer,
  /// amounts, cheque bank details) in Application Support/pending. It must
  /// not be purged like Caches, but must not reach iCloud/iTunes backups.
  private func excludeLocalDataFromBackup() {
    guard let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
    else { return }
    for name in ["pending", "user_data"] {
      var directory = support.appendingPathComponent(name, isDirectory: true)
      try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      var values = URLResourceValues()
      values.isExcludedFromBackup = true
      try? directory.setResourceValues(values)
    }
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "TevelSystemNotices") {
      SystemNotices.register(with: registrar)
    }
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "TevelSmsComposer") {
      SmsComposer.register(with: registrar)
    }
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "TevelPdfPicker") {
      PdfPicker.register(with: registrar)
    }
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "TevelContactsPermission") {
      ContactsPermission.register(with: registrar)
    }
  }
}

/// Explicitly asks before the app imports a person from the address book.
/// The selected contact itself is still returned by the privacy-preserving picker.
final class ContactsPermission: NSObject {
  static func register(with registrar: FlutterPluginRegistrar) {
    FlutterMethodChannel(name: "tevel/contacts_permission", binaryMessenger: registrar.messenger())
      .setMethodCallHandler { call, result in
        guard call.method == "requestAccess" else { return result(FlutterMethodNotImplemented) }
        let status = CNContactStore.authorizationStatus(for: .contacts)
        if status == .authorized {
          result(true)
          return
        }
        if #available(iOS 18.0, *), status == .limited {
          result(true)
          return
        }
        if status == .denied || status == .restricted {
          result(false)
          return
        }
        CNContactStore().requestAccess(for: .contacts) { allowed, error in
          DispatchQueue.main.async {
            if let error {
              result(FlutterError(code: "CONTACTS_PERMISSION", message: error.localizedDescription, details: nil))
            } else {
              result(allowed)
            }
          }
        }
      }
  }
}

/// S10 "קובץ PDF" (lib/screens/expense/expense_capture_screen.dart): the system
/// document picker, which needs no permission. Returns the picked PDF's bytes,
/// or nil when cancelled.
final class PdfPicker: NSObject, UIDocumentPickerDelegate {
  private static let shared = PdfPicker()
  private var registrar: FlutterPluginRegistrar?
  private var pending: FlutterResult?

  static func register(with registrar: FlutterPluginRegistrar) {
    shared.registrar = registrar
    FlutterMethodChannel(name: "tevel/pdf_picker", binaryMessenger: registrar.messenger())
      .setMethodCallHandler { call, result in
        guard call.method == "pickPdf" else { return result(FlutterMethodNotImplemented) }
        shared.pick(result)
      }
  }

  private func pick(_ result: @escaping FlutterResult) {
    guard pending == nil, let presenter = registrar?.viewController else {
      return result(FlutterError(code: "UNAVAILABLE", message: nil, details: nil))
    }
    pending = result
    let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.pdf], asCopy: true)
    picker.delegate = self
    presenter.present(picker, animated: true)
  }

  func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
    guard let url = urls.first else { return finish(nil) }
    defer { try? FileManager.default.removeItem(at: url) } // our private copy
    if let data = try? Data(contentsOf: url) {
      finish(FlutterStandardTypedData(bytes: data))
    } else {
      finish(FlutterError(code: "READ_FAILED", message: nil, details: nil))
    }
  }

  func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
    finish(nil)
  }

  private func finish(_ value: Any?) {
    pending?(value)
    pending = nil
  }
}


/// System SMS composer. No SMS is sent without the device user's confirmation.
final class SmsComposer: NSObject, MFMessageComposeViewControllerDelegate {
  private static let shared = SmsComposer()
  private var registrar: FlutterPluginRegistrar?
  private var pending: FlutterResult?
  static func register(with registrar: FlutterPluginRegistrar) {
    shared.registrar = registrar
    FlutterMethodChannel(name: "tevel/sms_composer", binaryMessenger: registrar.messenger())
      .setMethodCallHandler { call, result in
        guard call.method == "compose", let args = call.arguments as? [String: String],
              let phone = args["phone"], let body = args["body"],
              phone.range(of: "^[+][0-9]{8,15}$", options: .regularExpression) != nil else {
          return result(FlutterError(code: "INVALID_ARGUMENT", message: nil, details: nil))
        }
        guard MFMessageComposeViewController.canSendText() else { return result("UNAVAILABLE") }
        guard shared.pending == nil, var presenter = shared.registrar?.viewController else {
          return result(FlutterError(code: "UNAVAILABLE", message: nil, details: nil))
        }
        while let presented = presenter.presentedViewController { presenter = presented }
        shared.pending = result
        let composer = MFMessageComposeViewController()
        composer.recipients = [phone]
        composer.body = body
        composer.messageComposeDelegate = shared
        presenter.present(composer, animated: true)
      }
  }
  func messageComposeViewController(_ controller: MFMessageComposeViewController,
      didFinishWith result: MessageComposeResult) {
    controller.dismiss(animated: true) {
      self.pending?(result == .sent ? "SENT" : result == .cancelled ? "CANCELLED" : "FAILED")
      self.pending = nil
    }
  }
}
