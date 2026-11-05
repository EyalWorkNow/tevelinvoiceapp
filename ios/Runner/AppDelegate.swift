import Flutter
import UIKit
import UniformTypeIdentifiers
import MessageUI

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    excludePendingFromBackup()
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  /// lib/state/cache.dart keeps in-progress issue/payment state (customer,
  /// amounts, cheque bank details) in Application Support/pending. It must
  /// not be purged like Caches, but must not reach iCloud/iTunes backups.
  private func excludePendingFromBackup() {
    guard let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
    else { return }
    var pending = support.appendingPathComponent("pending", isDirectory: true)
    try? FileManager.default.createDirectory(at: pending, withIntermediateDirectories: true)
    var values = URLResourceValues()
    values.isExcludedFromBackup = true
    try? pending.setResourceValues(values)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "TevelSmsComposer") {
      SmsComposer.register(with: registrar)
    }
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "TevelPdfPicker") {
      PdfPicker.register(with: registrar)
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
