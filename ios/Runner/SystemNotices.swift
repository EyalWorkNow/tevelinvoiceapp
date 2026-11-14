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
    case "status":
      UNUserNotificationCenter.current().getNotificationSettings { settings in
        DispatchQueue.main.async {
          var enabled = false
          if #available(iOS 17.2, *) { enabled = ActivityAuthorizationInfo().areActivitiesEnabled }
          result(["notifications": settings.authorizationStatus == .authorized,
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

  /// Foreground handling never tries to start a Live Activity in the background.
  func receive(_ userInfo: [AnyHashable: Any], opened: Bool) -> Bool {
    guard let kind = userInfo["tevelKind"] as? String,
          let route = userInfo["route"] as? String,
          let businessID = userInfo["businessId"] as? String,
          route.range(of: "^(/(home|activity|expenses)|/(quote|doc|person)/[A-Za-z0-9_-]{1,64})$", options: .regularExpression) != nil else { return false }
    emit(["type": opened ? "opened" : "notice", "kind": kind, "route": route,
          "businessId": businessID, "eventID": userInfo["eventID"] as? String ?? ""])
    return true
  }
}
