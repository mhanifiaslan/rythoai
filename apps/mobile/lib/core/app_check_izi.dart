/// App Check arızasının yayın derlemesinde iz bırakması (U30).
///
/// Zorlama 2026-09-26'da Firestore ve identitytoolkit için açıldı. O andan
/// beri App Check'in düşmesi kullanıcıya yalnız "Giriş yapılamadı" ya da
/// Firestore izin hatası olarak görünüyor — yanlış şifreden ya da kural
/// hatasından ayırt edilemiyor. `activate()` hatası da yalnız `debugPrint`
/// ediliyordu, yani yayında hiçbir yere gitmiyordu.
///
/// iOS'ta bu kör nokta en pahalısı: App Attest simülatörde çalışmıyor ve
/// gerçek iPhone yok (sahibin kararı 3), ilk gerçek sinyal TestFlight
/// testçilerinden gelecek. Üstelik iOS'ta `activate()` yalnız sağlayıcıyı
/// kaydediyor (firebase_app_check 0.4.5+2 `FirebaseAppCheckPlugin.swift`
/// `activate`: Firebase uygulaması bulunamazsa düşer, başka hiçbir şey
/// denemez). Kayıtsız uygulama, Firebase'de eksik Team ID, attestation
/// reddi — hepsi ancak JETON alınırken ortaya çıkıyor; bu yüzden
/// etkinleştirme hatasının yanında bir jeton yoklaması da var.
library;

import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';

/// Crashlytics'e yazan varsayılan kanal.
///
/// Yalnız yayın derlemesinde: debug oturumları ve web rapor kirliliği
/// yaratmasın (main.dart'taki işleyicilerle aynı kural). Bu noktada
/// Crashlytics işleyicileri henüz kurulmamış olabilir; `recordError` onlara
/// bağlı değil, `Firebase.initializeApp` sonrası doğrudan çalışır.
void _crashlyticsKaydet(Object hata, StackTrace iz, String neden) {
  if (kDebugMode || kIsWeb) return;
  FirebaseCrashlytics.instance
      .recordError(hata, iz, reason: neden, fatal: false);
}

/// Kayıt kanalı — test dikişi (`purchase_errors.dart`'taki desen).
@visibleForTesting
void Function(Object hata, StackTrace iz, String neden) appCheckKaydedici =
    _crashlyticsKaydet;

/// Testler arası sızmayı önler.
@visibleForTesting
void appCheckKaydediciyiSifirla() => appCheckKaydedici = _crashlyticsKaydet;

/// `FirebaseAppCheck.activate` fırlattı.
///
/// Açılış yine sürer (main.dart: kullanıcıyı kapıda bırakmak yerine
/// sunucu karar verir); fark, artık iz kalması.
void appCheckEtkinlestirmeHatasi(Object hata, StackTrace iz) {
  debugPrint('App Check etkinleştirilemedi: $hata');
  appCheckKaydedici(hata, iz, 'app-check-activate');
}

/// Açılışta jeton yoklaması yapılır mı?
///
/// Yalnız iOS yayın derlemesi. Debug'da sağlayıcı zaten debug sağlayıcısı;
/// yoklanacak olan App Attest.
///
/// Android'e bilerek konmadı: yoklama orada yeni bir Play Integrity isteği
/// demek ve Android davranışı Windows oturumunun. iOS'ta eşzamanlı jeton
/// istekleri tek istekte birleşiyor (AppCheckCore `GACAppCheck.m`
/// `ongoingRetrieveOrRefreshTokenPromise`), yani yoklama Firestore'un kendi
/// isteğinin yanında ikinci bir attestation doğurmaz; Android SDK'sında
/// aynı birleşme burada doğrulanamadı ve Play Integrity isteklerinin
/// günlük kotası var. Android'de de istenirse karar Windows tarafında,
/// cihazda ölçülerek verilir. Parametreler test dikişidir.
bool appCheckYoklamasiYapilir({
  bool hataAyiklama = kDebugMode,
  bool web = kIsWeb,
  TargetPlatform? platform,
}) =>
    !hataAyiklama &&
    !web &&
    (platform ?? defaultTargetPlatform) == TargetPlatform.iOS;

/// Jetonu bir kez ister; düşerse ya da boş dönerse kaydeder. ASLA fırlatmaz.
///
/// Çağıran bunu BEKLEMEMELİ (`unawaited`): ilk açılışta App Attest
/// ağ üzerinden attestation yapıyor ve açılış onu beklememeli.
Future<void> appCheckJetonunuYokla(Future<String?> Function() jetonAl) async {
  try {
    final jeton = await jetonAl();
    if (jeton == null || jeton.isEmpty) {
      appCheckKaydedici(StateError('App Check jetonu boş döndü'),
          StackTrace.current, 'app-check-token');
    }
  } catch (e, iz) {
    appCheckKaydedici(e, iz, 'app-check-token');
  }
}
