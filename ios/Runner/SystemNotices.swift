import ActivityKit
import Flutter
import UIKit
import UserNotifications

/// OS notifications and ActivityKit use a separate native surface from Flutter.
final class SystemNotices: NSObject, FlutterPlugin, FlutterStreamHandler {
  static let shared = SystemNotices()
  private var sink: FlutterEventSink?
  private var pending: [[String: Any]] = []
  private var latestTokens: [String: [String: Any]] = [:]
  private var startTokenTask: Task<Void, Never>?
  private var activityTask: Task<Void, Never>?
  private var updateTasks: [String: Task<Void, Never>] = [:]

  static func register(with registrar: FlutterPluginRegistrar) {
    FlutterMethodChannel(name: "tevel/system_notices", binaryMessenger: registrar.messenger())
      .setMethodCallHandler(shared.handle)
    FlutterEventChannel(name: "tevel/system_notice_events", binaryMessenger: registrar.messenger())
      .setStreamHandler(shared)
    registrar.addApplicationDelegate(shared)
    // The server may set a badge number; it is cleared whenever the app comes forward.
    NotificationCenter.default.addObserver(forName: UIApplication.didBecomeActiveNotification,
                                           object: nil, queue: .main) { _ in clearBadge() }
  }

  /// iOS 16+ keeps delivered notifications; iOS 15's badge setter also clears them.
  static func clearBadge() {
    if #available(iOS 16.0, *) {
      UNUserNotificationCenter.current().setBadgeCount(0) { _ in }
    } else {
      UIApplication.shared.applicationIconBadgeNumber = 0
    }
  }

  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    sink = events
    for event in latestTokens.values { events(event) }
    for event in pending { events(event) }
    pending.removeAll()
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? { sink = nil; return nil }

  private func emit(_ event: [String: Any]) {
    if let tokenType = event["tokenType"] as? String { latestTokens[tokenType + ":" + (event["eventID"] as? String ?? "")] = event }
    if let sink { sink(event) }
    else if event["type"] != nil && event["tokenType"] == nil {
      pending.append(event)
      if pending.count > 20 { pending.removeFirst() }
    }
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "clearBadge":
      Self.clearBadge()
      result(nil)
    case "status":
      UNUserNotificationCenter.current().getNotificationSettings { settings in
        DispatchQueue.main.async {
          var enabled = false
          if #available(iOS 17.2, *) { enabled = ActivityAuthorizationInfo().areActivitiesEnabled }
          result(["notifications": settings.authorizationStatus == .authorized,
                  "determined": settings.authorizationStatus != .notDetermined,
                  "liveActivities": enabled])
        }
      }
    case "enable":
      UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { allowed, error in
        DispatchQueue.main.async {
          if let error { result(FlutterError(code: "NOTIFICATION_PERMISSION", message: error.localizedDescription, details: nil)); return }
          if allowed {
            UIApplication.shared.registerForRemoteNotifications()
            self.observeStartToken()
          }
          result(allowed)
        }
      }
    case "testLocal":
      let center = UNUserNotificationCenter.current()
      center.requestAuthorization(options: [.alert, .badge, .sound]) { allowed, error in
        guard allowed, error == nil else {
          DispatchQueue.main.async {
            result(FlutterError(code: "NOTIFICATION_PERMISSION_DENIED", message: error?.localizedDescription, details: nil))
          }
          return
        }
        let content = UNMutableNotificationContent()
        content.title = "תבל · התראת בדיקה"
        content.body = "כך נראית התראה באייפון שלך. היא לא נשלחה ללקוח."
        content.sound = .default
        let request = UNNotificationRequest(
          identifier: "tevel-local-test-\(UUID().uuidString)",
          content: content,
          trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        )
        center.add(request) { addError in
          DispatchQueue.main.async {
            if let addError {
              result(FlutterError(code: "NOTIFICATION_TEST_FAILED", message: addError.localizedDescription, details: nil))
            } else {
              result(nil)
            }
          }
        }
      }
    case "resume":
      UNUserNotificationCenter.current().getNotificationSettings { settings in
        DispatchQueue.main.async {
          if settings.authorizationStatus == .authorized {
            UIApplication.shared.registerForRemoteNotifications()
            self.observeStartToken()
          }
          result(nil)
        }
      }
    case "disable":
      UIApplication.shared.unregisterForRemoteNotifications()
      latestTokens.removeAll()
      pending.removeAll()
      startTokenTask?.cancel()
      startTokenTask = nil
      activityTask?.cancel()
      activityTask = nil
      for task in updateTasks.values { task.cancel() }
      updateTasks.removeAll()
      if #available(iOS 17.2, *) {
        Task { @MainActor in
          for activity in Activity<TevelActivityAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
          }
          result(nil)
        }
      } else { result(nil) }
    case "endAll":
      if #available(iOS 17.2, *) {
        Task { @MainActor in
          for activity in Activity<TevelActivityAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
          }
          result(nil)
        }
      } else { result(nil) }
    case "preview":
      #if DEBUG
      guard #available(iOS 17.2, *), ActivityAuthorizationInfo().areActivitiesEnabled else {
        result(FlutterError(code: "LIVE_ACTIVITIES_DISABLED", message: nil, details: nil)); return
      }
      Task { @MainActor in
        do {
          for old in Activity<TevelActivityAttributes>.activities { await old.end(nil, dismissalPolicy: .immediate) }
          let state = TevelActivityAttributes.ContentState(kind: "approved", title: "הצעת המחיר אושרה!",
            detail: "הלקוח אישר. אפשר להתקדם לחשבונית.", revision: 1)
          let activity = try Activity.request(
            attributes: TevelActivityAttributes(eventID: "preview", route: "/home", businessID: "preview"),
            content: ActivityContent(state: state, staleDate: Date().addingTimeInterval(120)), pushType: nil)
          result(activity.id)
        } catch { result(FlutterError(code: "LIVE_ACTIVITY_START", message: error.localizedDescription, details: nil)) }
      }
      #else
      result(FlutterMethodNotImplemented)
      #endif
    default: result(FlutterMethodNotImplemented)
    }
  }

  private func observeStartToken() {
    guard startTokenTask == nil else { return }
    if #available(iOS 17.2, *) {
      for activity in Activity<TevelActivityAttributes>.activities { observeUpdates(activity) }
      activityTask = Task { @MainActor in
        for await activity in Activity<TevelActivityAttributes>.activityUpdates {
          self.observeUpdates(activity)
        }
      }
      startTokenTask = Task { @MainActor in
        for await data in Activity<TevelActivityAttributes>.pushToStartTokenUpdates {
          self.emit(["type": "token", "tokenType": "liveActivityStart", "token": Self.hex(data),
                     "environment": Self.environment])
        }
      }
    }
  }

  @available(iOS 17.2, *)
  private func observeUpdates(_ activity: Activity<TevelActivityAttributes>) {
    guard updateTasks[activity.id] == nil else { return }
    updateTasks[activity.id] = Task { @MainActor in
      for await token in activity.pushTokenUpdates {
        self.emit(["type": "token", "tokenType": "liveActivityUpdate", "token": Self.hex(token),
          "environment": Self.environment, "eventID": activity.attributes.eventID,
          "businessId": activity.attributes.businessID])
      }
      self.updateTasks.removeValue(forKey: activity.id)
    }
  }

  private static func hex(_ data: Data) -> String { data.map { String(format: "%02x", $0) }.joined() }
  private static var environment: String {
    #if DEBUG
    return "sandbox"
    #else
    return "production"
    #endif
  }

  func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken token: Data) {
    emit(["type": "token", "tokenType": "alert", "token": Self.hex(token), "environment": Self.environment])
  }

  func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
    emit(["type": "registrationError", "code": "APNS_REGISTRATION_FAILED"])
  }

  /// packages/shared/src/push-catalogue.ts PUSH_KINDS (PUSH-001, /mobile/push/devices).
  static let catalogueKinds: Set<String> = [
    "ITA_ALLOCATION_APPROVED", "ITA_ALLOCATION_REJECTED", "DOCUMENT_SEND_FAILED",
    "PAYMENT_RECEIVED", "PAYMENTS_OVERDUE", "COLLECTION_REMINDERS_READY",
    "QUOTE_SIGNED", "QUOTE_VIEWED", "TEAM_MEMBER_JOINED", "SUBSCRIPTION_RENEWS_SOON",
    "SUBSCRIPTION_PAYMENT_FAILED", "SUBSCRIPTION_EXPIRED", "EXPORT_READY",
    "EXPORT_FAILED", "NEW_DEVICE_LOGIN", "UPLOAD_BLOCKED",
  ]
  /// Kinds with the server's own text (admin/template announcements, invoice#60): the system
  /// banner stays (also in the foreground); only a tap is forwarded, to open `link`.
  /// lib/state/system_notices.dart `pushOpenOnlyKinds` mirrors this.
  static let openOnlyKinds: Set<String> = ["ANNOUNCEMENT"]
  /// App routes a push may open (Dart re-checks with AppRoute.parse).
  static let allowedRoute =
    "^(/(home|activity|expenses|calendar|debts|reports|people)(\\?[A-Za-z0-9=&_-]{1,64})?|/(quote|doc|person|sign-request)/[A-Za-z0-9_-]{1,64}|/business/[a-z]{2,20})$"

  /// A tap on any push with `pushId` (invoice#61) is reported by Dart (POST /mobile/push/opened).
  /// Buffered like other events, so a tap that launched the app is not lost.
  @discardableResult
  func reportOpened(_ userInfo: [AnyHashable: Any]) -> Bool {
    guard let pushId = userInfo["pushId"] as? String,
          pushId.range(of: "^[0-9A-Fa-f]{8}(-[0-9A-Fa-f]{4}){3}-[0-9A-Fa-f]{12}$",
                       options: .regularExpression) != nil else { return false }
    emit(["type": "pushOpened", "pushId": pushId])
    return true
  }

  /// Foreground handling never tries to start a Live Activity in the background.
  func receive(_ userInfo: [AnyHashable: Any], opened: Bool) -> Bool {
    // `tevelKind`/`route` (/mobile/push-tokens) or the push catalogue's `kind`/`link` (QUOTE_SIGNED …).
    // Only catalogue kinds the Dart side presents are taken (others keep the system banner).
    let catalogueKind = (userInfo["kind"] as? String).flatMap {
      Self.catalogueKinds.contains($0) || Self.openOnlyKinds.contains($0) ? $0 : nil
    }
    let tevelKind = userInfo["tevelKind"] as? String
    guard let kind = tevelKind ?? catalogueKind,
          let route = (userInfo["route"] as? String) ?? (userInfo["link"] as? String),
          // Account-level catalogue pushes (subscription, new device) have no business.
          let businessID = (userInfo["businessId"] as? String) ?? (tevelKind == nil ? "" : nil),
          route.range(of: Self.allowedRoute, options: .regularExpression) != nil else { return false }
    if Self.openOnlyKinds.contains(kind) && !opened { return false }
    emit(["type": opened ? "opened" : "notice", "kind": kind, "route": route,
          "businessId": businessID, "eventID": userInfo["eventID"] as? String ?? ""])
    return true
  }
}
