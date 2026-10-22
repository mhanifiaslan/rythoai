import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    // UIScene düzeninde pencere SAHNEDE durur ve eklentiler kaydedilirken
    // henüz yoktur; `AppDelegate.window` nil'dir. flutter_contacts 1.1.9+2
    // ise kayıtta `UIApplication.shared.delegate!.window!!.rootViewController!`
    // okuyor — uygulama İLK KAREDE çöküyordu (ölçüldü 2026-09-26, simülatörde
    // "Unexpectedly found nil", SwiftFlutterContactsPlugin.swift:435; aynı
    // satır gerçek cihazda da koşar).
    //
    // Geçici pencere yalnız o zorla açmayı geçirmek için. Eklentinin sakladığı
    // denetleyici yalnız kişi SEÇİCİ ekranlarında kullanılıyor; uygulama
    // yalnız requestPermission + getContacts çağırıyor (lib/core/
    // contact_match.dart). Sahne bağlanınca SceneDelegate bu pencereyi
    // gerçeğiyle değiştirir.
    //
    // Kayıt biter bitmez pencere GERİ ALINIR: bırakılırsa sahne onu
    // benimsiyor ve ekran SİYAH kalıyordu (ölçüldü — key window boştu,
    // Dart hiç başlamadı).
    //
    // flutter_contacts 2.x'e geçilirse bu blok yeniden ölçülmeli.
    let geciciKondu = window == nil
    if geciciKondu {
      let geciciPencere = UIWindow(frame: UIScreen.main.bounds)
      geciciPencere.rootViewController = UIViewController()
      window = geciciPencere
    }
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if geciciKondu {
      window = nil
    }
  }
}
