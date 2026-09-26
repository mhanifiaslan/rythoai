import Flutter
import UIKit

class SceneDelegate: FlutterSceneDelegate {

  override func scene(
    _ scene: UIScene,
    willConnectTo session: UISceneSession,
    options connectionOptions: UIScene.ConnectionOptions
  ) {
    super.scene(scene, willConnectTo: session, options: connectionOptions)
    // AppDelegate, eklenti kaydı sırasında GEÇİCİ bir pencere taşıyor (bkz.
    // AppDelegate.didInitializeImplicitFlutterEngine). Burada gerçek Flutter
    // penceresiyle değiştirilir; `delegate.window` üzerinden ekran açan
    // eklentiler görünmez geçici pencereye değil, gerçeğine sunar.
    if let gercekPencere = window {
      (UIApplication.shared.delegate as? FlutterAppDelegate)?.window = gercekPencere
    }
  }
}
