/// Cihaz kimliği — tek cihaz kilidinin istemci yarısı.
///
/// Rastgele üretilmiş 128 bitlik bir değer, SharedPreferences'ta saklanır ve
/// her API isteğine `X-Device-Id` başlığı olarak eklenir (bkz. core/api.dart).
///
/// ## Neden donanım kimliği değil
///
/// Donanım kimlikleri (IMEI, Android ID) izin ve mağaza beyanı gerektirir,
/// gizlilik etiketine "cihaz tanımlayıcısı topluyoruz" satırı ekletir ve
/// kazandırdığı tek şey "uygulama silinip kurulunca kimlik korunur" olurdu —
/// ki o durumda kilidin sıfırlanması zaten kabul edilebilir: kullanıcı kendi
/// cihazında yeniden kurulum yapıyor.
///
/// ## Neden secure storage değil
///
/// Kimlik bir sır değil, bir AYIRICI. Tek geçerli kimlik sunucudaki kayıt;
/// kimliği kopyalamak "devralma"nın ta kendisi ve bunun meşru yolu zaten var
/// (`POST /device/claim`). Şifreli saklamak eklenti bağımlılığı getirir,
/// güvenlik kazandırmaz.
library;

import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String _kDeviceIdKey = 'rythoDeviceId';

/// Bu kurulumun en az bir kez açıldığının işareti (U45).
const String _kKurulumIsareti = 'rythoKurulumGoruldu';

String? _cached;

/// Bu cihazın kalıcı kimliği; ilk çağrıda üretilir.
Future<String> deviceId() async {
  final onbellek = _cached;
  if (onbellek != null) return onbellek;

  try {
    final prefs = await SharedPreferences.getInstance();
    var id = prefs.getString(_kDeviceIdKey);
    if (id == null || id.isEmpty) {
      id = _uret();
      await prefs.setString(_kDeviceIdKey, id);
    }
    _cached = id;
    return id;
  } catch (_) {
    // Depo okunamazsa oturum boyunca sabit bir kimlikle devam et: başlıksız
    // istek kilidi atlar (sunucu eski sürüm sanır) — üretmek her zaman
    // daha doğru.
    return _cached ??= _uret();
  }
}

String _uret() {
  final rasgele = Random.secure();
  final baytlar = List<int>.generate(16, (_) => rasgele.nextInt(256));
  return baytlar.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}

/// iOS'ta yeniden kurulumdan sağ çıkan Firebase oturumunu kapatır (U45).
///
/// iOS, Firebase oturumunu anahtar zincirinde tutar ve uygulama silinince
/// anahtar zinciri SİLİNMEZ; SharedPreferences ise silinir. Yeniden kuran
/// kullanıcı uygulamayı zaten girişli açıyordu ama yepyeni bir cihaz
/// kimliğiyle ve ESKİ `auth_time`'la. Ücretli abonede sunucunun hakemi
/// `auth_time` (backend core/device.py, "son giriş kazanır") ve eski
/// kurulumun kaydı o girişten daha yeni olduğu için kullanıcı, kendi eski
/// kurulumunun hesabı tuttuğunu söyleyen çakışma ekranına düşüyordu. Temiz
/// bir giriş taze `auth_time` üretir ve devralma kendiliğinden olur.
/// Uygulamayı silmenin oturumu da kapattığını sanan kullanıcı da girişli
/// açılmayı beklemez.
///
/// Yeniden kurulumun izi: SharedPreferences BOMBOŞ ama oturum var. Yalnız
/// kurulum işaretinin yokluğuna bakılsaydı, işaretten ÖNCEKİ bir sürümden
/// güncelleyen her iOS kullanıcısı bir kez çıkışa zorlanırdı; oysa onun
/// deposunda cihaz kimliği, dil tercihi gibi anahtarlar durur — depo
/// sağlamsa yeniden kurulum yok demektir. `main`'de bu çağrıdan önce depoya
/// yazan bir şey yok, yani taze kurulumda depo gerçekten boş.
///
/// Oturumun burada görünür olmasının kaynağı: iOS eklentisi `currentUser`'ı
/// `Firebase.initializeApp` sırasında yerel `[auth currentUser]`'dan
/// tohumluyor (firebase_auth 6.5.6, FLTFirebaseAuthPlugin.m,
/// `APP_CURRENT_USER`). Yine de null gelirse çıkış yapılmaz — yalnız eski
/// davranış kalır.
///
/// İşaret çıkıştan ÖNCE yazılır ve yazılamazsa çıkış yapılmaz: yazılamayan
/// bir işaretle her açılış kullanıcıyı yeniden çıkarırdı.
///
/// Yalnız iOS: Android'de oturum uygulama verisiyle birlikte gider; burada
/// ne depoya ne oturuma dokunulur.
///
/// Döner: oturum kapatıldıysa true. [oturumVar] ve [cikis] dikiş —
/// `main` doğrudan `FirebaseAuth.signOut`'u verir. `signOutEverywhere`
/// DEĞİL: o, `runApp`'ten önce henüz kurulmamış gezgin kabına, cihaz
/// kilidine ve push jetonuna uzanır; burada kapanması gereken yalnız yerel
/// oturum.
Future<bool> iosYenidenKurulumOturumunuKapat({
  required bool Function() oturumVar,
  required Future<void> Function() cikis,
}) async {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.iOS) return false;
  try {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_kKurulumIsareti) == true) return false;
    final depoEski = prefs.getKeys().isNotEmpty;
    if (!await prefs.setBool(_kKurulumIsareti, true)) return false;
    if (depoEski || !oturumVar()) return false;
    await cikis();
    return true;
  } catch (e) {
    // Açılışı asla düşürmez: en kötü durumda eski davranış (çakışma
    // ekranı ve "Bu cihazda kullan") geri gelir.
    debugPrint('Yeniden kurulum denetimi atlandı: $e');
    return false;
  }
}
