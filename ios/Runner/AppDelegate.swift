import Flutter
import UIKit
import UserNotifications

func shouldAcceptNotificationReadinessAck(
  currentGeneration: Int,
  ackGeneration: Int
) -> Bool {
  currentGeneration == ackGeneration
}

func shouldDeliverNotificationTap(
  channelReady: Bool,
  hasChannel: Bool
) -> Bool {
  channelReady && hasChannel
}

struct NotificationTap {
  let kind: String
  let sessionId: String
}

final class NotificationTapBuffer {
  private var pendingTap: NotificationTap?

  func store(kind: String?, sessionId: String?) {
    guard kind == "highSpeed", let sessionId, !sessionId.isEmpty else {
      pendingTap = nil
      return
    }
    pendingTap = NotificationTap(kind: kind!, sessionId: sessionId)
  }

  func take() -> NotificationTap? {
    defer { pendingTap = nil }
    return pendingTap
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
  private var notificationChannelReady = false
  private var notificationChannelGeneration = 0

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    UNUserNotificationCenter.current().delegate = self
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    let channel = FlutterMethodChannel(
      name: Self.methodChannelName,
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    // The implicit engine can be recreated while the app remains alive.
    // Require a fresh Dart readiness acknowledgement for every messenger.
    notificationChannelReady = false
    let channelGeneration = notificationChannelGeneration + 1
    notificationChannelGeneration = channelGeneration
    notificationChannel = channel
    channel.setMethodCallHandler { [weak self] call, result in
      self?.handleMethodCall(
        call,
        result: result,
        channelGeneration: channelGeneration
      )
    }
    UNUserNotificationCenter.current().delegate = self
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
    let sessionId = response.notification.request.content.userInfo["sessionId"] as? String
    deliverOrBuffer(kind: kind, sessionId: sessionId)
    completionHandler()
  }

  private func handleMethodCall(
    _ call: FlutterMethodCall,
    result: @escaping FlutterResult,
    channelGeneration: Int
  ) {
    switch call.method {
    case "ready":
      if shouldAcceptNotificationReadinessAck(
        currentGeneration: notificationChannelGeneration,
        ackGeneration: channelGeneration
      ) {
        notificationChannelReady = true
        flushPendingTap()
      }
      result(nil)
    case "getTimezone":
      result(TimeZone.current.identifier)
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
        isSupportedNotification(
          id: id,
          kind: arguments["kind"] as? String,
          sessionId: arguments["sessionId"] as? String
        )
      else {
        result(FlutterError(code: "invalid_arguments", message: "Notification fields are missing or invalid.", details: nil))
        return
      }
      showNotification(
        id: id,
        title: title,
        body: body,
        kind: arguments["kind"] as? String,
        sessionId: arguments["sessionId"] as? String,
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
    sessionId: String?,
    result: @escaping FlutterResult
  ) {
    let content = UNMutableNotificationContent()
    content.title = title
    content.body = body
    content.sound = .default
    if let kind {
      content.userInfo["kind"] = kind
    }
    if let sessionId, !sessionId.isEmpty {
      content.userInfo["sessionId"] = sessionId
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

  private func deliverOrBuffer(kind: String?, sessionId: String?) {
    guard kind == "highSpeed", let sessionId, !sessionId.isEmpty else { return }
    if shouldDeliverNotificationTap(
      channelReady: notificationChannelReady,
      hasChannel: notificationChannel != nil
    ), let channel = notificationChannel {
      channel.invokeMethod(
        "notificationTapped",
        arguments: ["kind": kind!, "sessionId": sessionId]
      )
    } else {
      tapBuffer.store(kind: kind, sessionId: sessionId)
    }
  }

  private func flushPendingTap() {
    guard let channel = notificationChannel, let tap = tapBuffer.take() else { return }
    channel.invokeMethod(
      "notificationTapped",
      arguments: ["kind": tap.kind, "sessionId": tap.sessionId]
    )
  }

  private func isSupportedNotification(id: Int, kind: String?, sessionId: String?) -> Bool {
    switch id {
    case Self.stationaryWarningId:
      return kind == "stationary" || kind == "duration"
    case Self.highSpeedWarningId:
      return kind == "highSpeed" && sessionId != nil && !sessionId!.isEmpty
    case Self.completionNotificationId:
      return kind == nil
    default:
      return false
    }
  }
}
