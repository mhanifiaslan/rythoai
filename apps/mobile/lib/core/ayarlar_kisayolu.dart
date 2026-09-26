/// İzin reddinden sonra uygulamanın KENDİ Ayarlar sayfasına kısayol (U23).
///
/// iOS bir izni yalnız BİR KEZ sorar. "İzin Verme"den sonra her istek
/// diyalogsuz reddediliyor (`camera_avfoundation`:
/// `CameraAccessDeniedWithoutPrompt`; `flutter_contacts`: `false`), yani
/// uygulamadaki "Tekrar dene" iOS'ta bir daha hiçbir şey sormuyor ve
/// kullanıcı çıkışı olmayan bir döngüde kalıyordu. İzni geri vermenin tek
/// yolu Ayarlar; yolu tarif etmek yerine kullanıcıyı oraya götürüyoruz.
///
/// Yalnız iOS — ama bu, Android'de sorun olmadığı anlamına GELMİYOR. Android
/// davranışı bu turda bilerek değiştirilmedi: o ekranlar Windows oturumunun
/// ve Android tarafı cihazda ölçülmedi. Android 11+ da bir izni ikinci
/// retten sonra diyalogsuz reddediyor (platform kuralı; bu uygulamada
/// ölçülmedi), yani oradaki "Tekrar dene" de aynı çıkmaza varıyor. Kamera
/// reddi ise Android'de izin katmanına hiç ulaşmıyor, arıza katmanına
/// düşüyor (`docs/test-raporu.md` B11).
library;

import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

/// Ayarlar adresini açan fonksiyon — `url_launcher.launchUrl`'un sadesi.
/// Testte değiştirilir; üretimde [launchUrl].
typedef AyarlarAcici = Future<bool> Function(Uri adres);

/// `UIApplication.openSettingsURLString` — uygulamanın kendi Ayarlar sayfası.
///
/// `url_launcher_ios` 6.4.1 http dışı bir adresi doğrudan
/// `UIApplication.shared.open` ile açıyor, önce `canOpenURL` sormuyor; yani
/// Info.plist'e `LSApplicationQueriesSchemes` kaydı gerekmiyor.
final Uri iosAyarlarAdresi = Uri.parse('app-settings:');

/// Ayarlar kısayolu bu platformda gösterilir mi?
///
/// `Platform.isIOS` değil `defaultTargetPlatform`: testte değiştirilebilen
/// anahtar bu.
bool get ayarlarKisayoluVar => defaultTargetPlatform == TargetPlatform.iOS;

Future<bool> _varsayilanAcici(Uri adres) => launchUrl(adres);

/// Uygulamanın Ayarlar sayfasını açar; açılamazsa `false` döner, fırlatmaz.
///
/// Düğmenin yanında yolu tarif eden metin zaten duruyor (kamera ve rehber
/// ekranlarının ikisinde de); açılış düşerse kullanıcı o metinle yine
/// ilerleyebilir. Hata yutulmasaydı ekran düşmezdi ama `onPressed`'in
/// Future'ı yakalanmamış hatayla biterdi: `main.dart` bölge korumasız,
/// hata `PlatformDispatcher.onError`'a çıkar ve release'de Crashlytics'e
/// FATAL diye yazılırdı — U23'ün temizlediği sahte kaydın ta kendisi.
/// Fırlatma yolu gerçek: `url_launcher_ios` 6.4.1 `LaunchResult.invalidUrl`
/// sonucunda `PlatformException` atıyor.
Future<bool> uygulamaAyarlariniAc({AyarlarAcici? acici}) async {
  try {
    return await (acici ?? _varsayilanAcici)(iosAyarlarAdresi);
  } catch (_) {
    return false;
  }
}
