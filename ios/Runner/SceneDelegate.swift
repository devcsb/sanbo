import Flutter
import UIKit

class SceneDelegate: FlutterSceneDelegate {

  override func scene(
    _ scene: UIScene,
    willConnectTo session: UISceneSession,
    options connectionOptions: UIScene.ConnectionOptions
  ) {
    super.scene(scene, willConnectTo: session, options: connectionOptions)

    // With a scene manifest, a notification tap that launches a terminated app
    // arrives here instead of through UNUserNotificationCenterDelegate.
    if let response = connectionOptions.notificationResponse,
       let appDelegate = UIApplication.shared.delegate as? AppDelegate {
      appDelegate.handleNotificationResponse(response)
    }
  }
}
