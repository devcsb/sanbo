import Flutter
import UIKit
import UserNotifications

final class NotificationTapBuffer {
  private var pendingKind: String?

  func store(kind: String?) {
    pendingKind = kind == "highSpeed" ? kind : nil
  }

  func take() -> String? {
    defer { pendingKind = nil }
    return pendingKind
  }
}

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private static let methodChannelName = "sanbo/session_notifications"
  private static let stationaryWarningId = 4101
  private static let completionNotificationId = 4102
  private static let highSpeedWarningId = 4103

  private let tapBuffer = NotificationTapBuffer()
  private var notificationChannel: FlutterMethodChannel?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    UNUserNotificationCenter.current().delegate = self
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    guard let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "SessionNotifications") else {
      return
    }
    let channel = FlutterMethodChannel(
      name: Self.methodChannelName,
      binaryMessenger: registrar.messenger()
    )
    notificationChannel = channel
    channel.setMethodCallHandler { [weak self] call, result in
      self?.handleMethodCall(call, result: result)
    }
    UNUserNotificationCenter.current().delegate = self
    if let kind = tapBuffer.take() {
      channel.invokeMethod("notificationTapped", arguments: ["kind": kind])
    }
  }

  override func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping @Sendable (UNNotificationPresentationOptions) -> Void
  ) {
    completionHandler([])
  }

  override func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse,
    withCompletionHandler completionHandler: @escaping @Sendable () -> Void
  ) {
    let kind = response.notification.request.content.userInfo["kind"] as? String
    deliverOrBuffer(kind: kind)
    completionHandler()
  }

  private func handleMethodCall(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "requestPermission":
      UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) {
        granted, error in
        DispatchQueue.main.async {
          if let error {
            result(FlutterError(code: "permission_failed", message: error.localizedDescription, details: nil))
          } else {
            result(granted)
          }
        }
      }
    case "show":
      guard
        let arguments = call.arguments as? [String: Any],
        let id = arguments["id"] as? Int,
        let title = arguments["title"] as? String,
        let body = arguments["body"] as? String,
        isSupportedNotification(id: id, kind: arguments["kind"] as? String)
      else {
        result(FlutterError(code: "invalid_arguments", message: "Notification fields are missing or invalid.", details: nil))
        return
      }
      showNotification(
        id: id,
        title: title,
        body: body,
        kind: arguments["kind"] as? String,
        result: result
      )
    case "cancel":
      guard
        let arguments = call.arguments as? [String: Any],
        let id = arguments["id"] as? Int
      else {
        result(FlutterError(code: "invalid_arguments", message: "Notification id is missing.", details: nil))
        return
      }
      let identifier = String(id)
      let center = UNUserNotificationCenter.current()
      center.removePendingNotificationRequests(withIdentifiers: [identifier])
      center.removeDeliveredNotifications(withIdentifiers: [identifier])
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func showNotification(
    id: Int,
    title: String,
    body: String,
    kind: String?,
    result: @escaping FlutterResult
  ) {
    let content = UNMutableNotificationContent()
    content.title = title
    content.body = body
    content.sound = .default
    if let kind {
      content.userInfo["kind"] = kind
    }
    let request = UNNotificationRequest(
      identifier: String(id),
      content: content,
      trigger: nil
    )
    UNUserNotificationCenter.current().add(request) { error in
      DispatchQueue.main.async {
        if let error {
          result(FlutterError(code: "show_failed", message: error.localizedDescription, details: nil))
        } else {
          result(nil)
        }
      }
    }
  }

  private func deliverOrBuffer(kind: String?) {
    guard kind == "highSpeed" else { return }
    if let channel = notificationChannel {
      channel.invokeMethod("notificationTapped", arguments: ["kind": kind!])
    } else {
      tapBuffer.store(kind: kind)
    }
  }

  private func isSupportedNotification(id: Int, kind: String?) -> Bool {
    switch id {
    case Self.stationaryWarningId:
      return kind == "stationary" || kind == "duration"
    case Self.highSpeedWarningId:
      return kind == "highSpeed"
    case Self.completionNotificationId:
      return kind == nil
    default:
      return false
    }
  }
}
