import Flutter
import UIKit
import UserNotifications

/// Direct APNs for the Tevel invoice app (no Firebase).
///
/// Channel "tevel/push":
///   Dart → iOS  authorizationStatus · requestPermission · register · apnsEnvironment ·
///               setBadge(n) · initialNotification
///   iOS → Dart  onToken(hex) · onTokenError(msg) · onMessage(payload) · onTap(payload)
///
/// The plugin is the UNUserNotificationCenter delegate: a push that arrives while the app is open
/// is still shown as a banner, and a tap is reported once Dart listens.
public final class TevelPushPlugin: NSObject, FlutterPlugin, UNUserNotificationCenterDelegate {
  private var channel: FlutterMethodChannel?
  private var launchPayload: [String: Any]?
  private var pendingTaps: [[String: Any]] = []
  private var dartReady = false

  public static func register(with registrar: FlutterPluginRegistrar) {
    let instance = TevelPushPlugin()
    let channel = FlutterMethodChannel(name: "tevel/push", binaryMessenger: registrar.messenger())
    instance.channel = channel
    registrar.addMethodCallDelegate(instance, channel: channel)
    registrar.addApplicationDelegate(instance)
    UNUserNotificationCenter.current().delegate = instance
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "authorizationStatus":
      UNUserNotificationCenter.current().getNotificationSettings { settings in
        DispatchQueue.main.async { result(Self.name(settings.authorizationStatus)) }
      }
    case "requestPermission":
      UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) {
        granted, _ in
        DispatchQueue.main.async {
          if granted { UIApplication.shared.registerForRemoteNotifications() }
          result(granted)
        }
      }
    case "register":
      UNUserNotificationCenter.current().getNotificationSettings { settings in
        DispatchQueue.main.async {
          let ok = [.authorized, .provisional].contains(settings.authorizationStatus)
          if ok { UIApplication.shared.registerForRemoteNotifications() }
          result(ok)
        }
      }
    case "apnsEnvironment":
      result(Self.apnsEnvironment())
    case "setBadge":
      let n = (call.arguments as? Int) ?? 0
      if #available(iOS 16.0, *) {
        UNUserNotificationCenter.current().setBadgeCount(n)
      } else {
        UIApplication.shared.applicationIconBadgeNumber = n
      }
      result(nil)
    case "initialNotification":
      // Dart is listening now: flush taps that arrived before it was.
      dartReady = true
      let payload = launchPayload
      launchPayload = nil
      result(payload)
      for tap in pendingTaps { channel?.invokeMethod("onTap", arguments: tap) }
      pendingTaps.removeAll()
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  // MARK: application delegate (forwarded by FlutterAppDelegate)

  public func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [AnyHashable: Any] = [:]
  ) -> Bool {
    if let remote = launchOptions[UIApplication.LaunchOptionsKey.remoteNotification] as? [AnyHashable: Any] {
      launchPayload = Self.payload(remote)
    }
    return true
  }

  public func application(
    _ application: UIApplication,
    didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
  ) {
    let hex = deviceToken.map { String(format: "%02x", $0) }.joined()
    channel?.invokeMethod("onToken", arguments: hex)
  }

  public func application(
    _ application: UIApplication,
    didFailToRegisterForRemoteNotificationsWithError error: Error
  ) {
    channel?.invokeMethod("onTokenError", arguments: error.localizedDescription)
  }

  // MARK: UNUserNotificationCenterDelegate

  public func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    channel?.invokeMethod("onMessage", arguments: Self.payload(notification.request.content.userInfo))
    if #available(iOS 14.0, *) {
      completionHandler([.banner, .list, .sound])
    } else {
      completionHandler([.alert, .sound])
    }
  }

  public func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse,
    withCompletionHandler completionHandler: @escaping () -> Void
  ) {
    let payload = Self.payload(response.notification.request.content.userInfo)
    if dartReady {
      channel?.invokeMethod("onTap", arguments: payload)
    } else if launchPayload == nil {
      launchPayload = payload
    } else {
      pendingTaps.append(payload)
    }
    completionHandler()
  }

  // MARK: helpers

  /// Only our routing keys (link, kind, businessId) plus the visible text — never the whole userInfo.
  private static func payload(_ userInfo: [AnyHashable: Any]) -> [String: Any] {
    var out: [String: Any] = [:]
    for key in ["link", "kind", "businessId"] {
      if let value = userInfo[key] as? String { out[key] = value }
    }
    if let aps = userInfo["aps"] as? [String: Any], let alert = aps["alert"] as? [String: Any] {
      if let title = alert["title"] as? String { out["title"] = title }
      if let body = alert["body"] as? String { out["body"] = body }
    }
    return out
  }

  private static func name(_ status: UNAuthorizationStatus) -> String {
    switch status {
    case .authorized: return "authorized"
    case .denied: return "denied"
    case .provisional: return "provisional"
    case .notDetermined: return "notDetermined"
    default: return "authorized" // .ephemeral (App Clips)
    }
  }

  /// "sandbox" for Xcode/development builds and the simulator, "production" for TestFlight and
  /// the App Store (their provisioning profile is stripped or says aps-environment production).
  private static func apnsEnvironment() -> String {
    #if targetEnvironment(simulator)
      return "sandbox"
    #else
      guard let url = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision"),
        let data = try? Data(contentsOf: url),
        let text = String(data: data, encoding: .isoLatin1),
        let start = text.range(of: "<plist"),
        let end = text.range(of: "</plist>")
      else { return "production" }
      let xml = Data(text[start.lowerBound..<end.upperBound].utf8)
      guard
        let plist = try? PropertyListSerialization.propertyList(from: xml, format: nil) as? [String: Any],
        let entitlements = plist["Entitlements"] as? [String: Any],
        let aps = entitlements["aps-environment"] as? String
      else { return "production" }
      return aps == "development" ? "sandbox" : "production"
    #endif
  }
}
