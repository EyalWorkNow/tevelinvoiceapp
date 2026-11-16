import Flutter
import UIKit
import UniformTypeIdentifiers
import MessageUI
import UserNotifications
import Contacts
import EventKit

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
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "TevelDeviceCalendar") {
      DeviceCalendar.register(with: registrar)
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


/// "יומן" (lib/screens/calendar/device_calendar.dart): the phone's own calendars through EventKit —
/// iCloud, Google, Outlook and Exchange accounts already on the iPhone. Reads ONLY start/end of
/// busy events in the calendars the owner chose (titles, attendees and locations never leave this
/// method), writes confirmed bookings into one chosen calendar (marked with a tevel-booking:// URL,
/// so they are never read back as "busy"), and schedules local reminders that open "יומן".
final class DeviceCalendar: NSObject {
  private static let store = EKEventStore()
  private static let marker = "tevel-booking"
  private static let reminderPrefix = "tevel-booking-reminder-"

  private static var channel: FlutterMethodChannel?
  private static var observer: NSObjectProtocol?

  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "tevel/calendar", binaryMessenger: registrar.messenger())
    Self.channel = channel
    // "after changes": the app re-syncs busy times when the owner edits a calendar while it runs.
    observer = NotificationCenter.default.addObserver(
      forName: .EKEventStoreChanged, object: store, queue: .main
    ) { _ in Self.channel?.invokeMethod("changed", arguments: nil) }
    channel.setMethodCallHandler { call, result in
        let args = call.arguments as? [String: Any] ?? [:]
        switch call.method {
        case "status": result(status())
        case "requestAccess": requestAccess(result)
        case "calendars": result(hasRead() ? calendars() : [])
        case "busy": result(hasRead() ? busy(args) : [])
        case "upsertEvent": result(hasWrite() ? upsert(args) : nil)
        case "deleteEvent":
          if hasWrite(), let id = args["eventId"] as? String, let event = store.event(withIdentifier: id) {
            try? store.remove(event, span: .thisEvent, commit: true)
          }
          result(nil)
        case "scheduleReminders": scheduleReminders(args, result)
        #if DEBUG
        // QA only (compiled out of release): a plain private event, as if the owner added it in
        // the Calendar app — to prove its time is blocked and its title never leaves the phone.
        case "debugAddEvent":
          guard hasWrite(), let title = args["title"] as? String,
                let s = args["start"] as? Int64, let e = args["end"] as? Int64 else { return result(nil) }
          let event = EKEvent(eventStore: store)
          event.calendar = store.defaultCalendarForNewEvents
          event.title = title
          event.startDate = Date(timeIntervalSince1970: TimeInterval(s) / 1000)
          event.endDate = Date(timeIntervalSince1970: TimeInterval(e) / 1000)
          try? store.save(event, span: .thisEvent, commit: true)
          result(event.eventIdentifier)
        #endif
        default: result(FlutterMethodNotImplemented)
        }
      }
  }

  private static func status() -> String {
    switch EKEventStore.authorizationStatus(for: .event) {
    case .notDetermined: return "notDetermined"
    case .restricted: return "restricted"
    case .denied: return "denied"
    case .authorized: return "full" // before iOS 17 (deprecated name for full access)
    default:
      if #available(iOS 17.0, *) {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess: return "full"
        case .writeOnly: return "writeOnly"
        default: return "denied"
        }
      }
      return "denied"
    }
  }

  private static func hasRead() -> Bool { status() == "full" }
  private static func hasWrite() -> Bool { status() == "full" || status() == "writeOnly" }

  private static func requestAccess(_ result: @escaping FlutterResult) {
    let done: (Bool, Error?) -> Void = { _, _ in
      DispatchQueue.main.async {
        store.reset()
        result(status())
      }
    }
    if #available(iOS 17.0, *) {
      store.requestFullAccessToEvents(completion: done)
    } else {
      store.requestAccess(to: .event, completion: done)
    }
  }

  private static func calendars() -> [[String: Any]] {
    store.calendars(for: .event).map { c in
      [
        "id": c.calendarIdentifier,
        "title": c.title,
        "account": c.source.title,
        "color": hex(c.cgColor),
        "writable": c.allowsContentModifications,
        "isDefault": c.calendarIdentifier == store.defaultCalendarForNewEvents?.calendarIdentifier,
      ]
    }
  }

  private static func hex(_ color: CGColor?) -> String {
    guard let c = color?.converted(to: CGColorSpaceCreateDeviceRGB(), intent: .defaultIntent, options: nil),
          let p = c.components, p.count >= 3 else { return "#8A948F" }
    return String(format: "#%02X%02X%02X", Int(p[0] * 255), Int(p[1] * 255), Int(p[2] * 255))
  }

  /// [{start, end}] in epoch milliseconds — nothing else.
  private static func busy(_ args: [String: Any]) -> [[String: Int64]] {
    guard let from = args["from"] as? Int64, let to = args["to"] as? Int64,
          let ids = args["calendarIds"] as? [String], !ids.isEmpty else { return [] }
    let chosen = store.calendars(for: .event).filter { ids.contains($0.calendarIdentifier) }
    if chosen.isEmpty { return [] }
    let start = Date(timeIntervalSince1970: TimeInterval(from) / 1000)
    let end = Date(timeIntervalSince1970: TimeInterval(to) / 1000)
    let predicate = store.predicateForEvents(withStart: start, end: end, calendars: chosen)
    return store.events(matching: predicate).compactMap { e in
      if e.availability == .free || e.status == .canceled { return nil }
      if e.url?.scheme == marker { return nil } // our own booking events
      guard let s = e.startDate, let f = e.endDate, f > s else { return nil }
      return ["start": Int64(s.timeIntervalSince1970 * 1000), "end": Int64(f.timeIntervalSince1970 * 1000)]
    }
  }

  private static func upsert(_ args: [String: Any]) -> String? {
    guard let bookingId = args["bookingId"] as? String,
          bookingId.range(of: "^[0-9a-fA-F-]{36}$", options: .regularExpression) != nil,
          let startMs = args["start"] as? Int64, let endMs = args["end"] as? Int64, endMs > startMs,
          let title = args["title"] as? String else { return nil }
    var event: EKEvent?
    if let id = args["eventId"] as? String { event = store.event(withIdentifier: id) }
    let target = event ?? EKEvent(eventStore: store)
    if event == nil {
      let calendarId = args["calendarId"] as? String
      target.calendar = calendarId.flatMap { store.calendar(withIdentifier: $0) } ?? store.defaultCalendarForNewEvents
    }
    target.title = String(title.prefix(200))
    target.startDate = Date(timeIntervalSince1970: TimeInterval(startMs) / 1000)
    target.endDate = Date(timeIntervalSince1970: TimeInterval(endMs) / 1000)
    target.notes = (args["notes"] as? String).map { String($0.prefix(2000)) }
    target.url = URL(string: "\(marker)://\(bookingId)")
    target.availability = .busy
    do {
      try store.save(target, span: .thisEvent, commit: true)
      return target.eventIdentifier
    } catch {
      return nil
    }
  }

  /// Replaces every pending booking reminder with [items]: {id, at (ms), title, body, businessId}.
  private static func scheduleReminders(_ args: [String: Any], _ result: @escaping FlutterResult) {
    let center = UNUserNotificationCenter.current()
    let items = args["items"] as? [[String: Any]] ?? []
    center.getPendingNotificationRequests { pending in
      center.removePendingNotificationRequests(
        withIdentifiers: pending.map(\.identifier).filter { $0.hasPrefix(reminderPrefix) })
      center.getNotificationSettings { settings in
        let add = {
          var scheduled = 0
          for item in items.prefix(40) {
            guard let id = item["id"] as? String, let at = item["at"] as? Int64,
                  let title = item["title"] as? String, let body = item["body"] as? String,
                  let businessId = item["businessId"] as? String else { continue }
            let interval = TimeInterval(at) / 1000 - Date().timeIntervalSince1970
            if interval < 1 { continue }
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.sound = .default
            content.threadIdentifier = "tevel-calendar"
            content.userInfo = ["tevelKind": "bookingSoon", "route": "/calendar",
                                "businessId": businessId, "eventID": "local-\(id)"]
            center.add(UNNotificationRequest(
              identifier: reminderPrefix + id, content: content,
              trigger: UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)))
            scheduled += 1
          }
          DispatchQueue.main.async { result(scheduled) }
        }
        if settings.authorizationStatus == .notDetermined && !items.isEmpty {
          center.requestAuthorization(options: [.alert, .sound]) { _, _ in add() }
        } else if settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional {
          add()
        } else {
          DispatchQueue.main.async { result(0) }
        }
      }
    }
  }
}
