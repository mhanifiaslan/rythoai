/// Ortak kodunun KURULUM SONRASI hesaba bağlanması (OP-turu).
///
/// ## Neden var
///
/// Ortak `https://rytho.app/r/KOD` paylaşır. Uygulama kurulu değilse link
/// tarayıcıda açılır ve sayfa kullanıcıyı Play'e `&referrer=` ile
/// yönlendirir. Play o dizeyi kurulumdan sonra uygulamaya verir — yani
/// kullanıcı HİÇBİR ŞEY yazmaz, hiçbir şeye dokunmaz.
///
/// ## Neden yalnız Android
///
/// Play Install Referrer'ın iOS'ta dengi YOK ve bu Apple'ın bilinçli
/// kararı: `AdServices` yalnız Apple Search Ads içindir ve yükünde serbest
/// alan yoktur; `ct=`/`pt=` yalnız App Store Connect analitiğinde görünür,
/// uygulama okuyamaz; Universal Link uygulama kurulu değilken hiçbir şey
/// saklamaz; SKAdNetwork/AdAttributionKit toplu reklam ölçümüdür, kod
/// taşıyamaz.
///
/// iOS'ta kod YALNIZ kurulu uygulamada sayılır: Universal Link
/// (`apple-app-site-association` `/r/*`) uygulamayı açar ve
/// [applyPartnerCode] aynı uca çıkar. Kurulum öncesi atıf için seçilen yol
/// (sahip kararı, 2026-10-22): `/r/` sayfası iPhone'da "kur, hesabını aç,
/// bağlantıya bir kez daha dokun" der — ikinci dokunuşu yapmayan sayılmaz.
/// Custom Product Page (ortak başına bir mağaza sayfası, en çok 70, her biri
/// Apple incelemesinden geçer) ve pano okuma BİLEREK seçilmedi; parmak izi
/// eşleştirme hiç düşünülmedi (ölçüm değil olasılık). Gerekçe ve yayın günü
/// listesi `docs/mac-devir.md` 4.10'da.
///
/// Üçüncü parti bir atıf SDK'sı (Branch vb.) BİLEREK alınmadı: kendi
/// Android kurulum belgesi `AD_ID` izni istiyor ve `infra/build-aab.ps1`
/// o izni bulunca yayını durduruyor; ayrıca gizlilik politikamızdaki
/// "reklam kimliğini KULLANMAZ" cümlesini yalan yapardı.
library;

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:play_install_referrer/play_install_referrer.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Kod biçimi — backend `partner_service._KOD_DESENI` ve `web/r/index.html`
/// ile BİREBİR aynı. Üçü ayrışırsa geçerli bir kod sessizce düşer.
final RegExp kOrtakKodDeseni = RegExp(r'^[A-Z0-9_-]{4,24}$');

/// Referrer dizesinde kodu taşıyan alan. `web/r/index.html` utm biçiminde
/// gönderiyor; utm seçilmesinin bedava bir faydası var: Play Console'un
/// kendi edinme raporları ortak başına performansı gösteriyor.
const String _kKodAlani = 'utm_campaign';

/// Bayrak SÜRÜMSÜZ — `consent.dart`'takinden ayrılan tek yer.
///
/// Kabul kaydı şartlar sürümü değişince YENİDEN alınmalı; atıf ise hesap
/// başına ÖMÜRLÜK tektir (`users/{uid}/private/attribution`, sunucuda tek
/// sefer). Bayrağı sürümlemek, bir gün sürüm artınca herkesin zaten
/// kullanılmış kodu yeniden göndermesine ve 409 seline yol açardı.
const String _kBayrak = 'partner-referrer-islendi';

/// Referrer'ı okur, ortak kodunu çıkarır ve sunucuya bir kez gönderir.
///
/// ASLA FIRLATMAZ. Atıf bir ek fayda; açılışı düşürmemeli.
Future<void> ensurePartnerReferrer(Dio dio) async {
  if (defaultTargetPlatform != TargetPlatform.android) return;

  final prefs = await SharedPreferences.getInstance();
  if (prefs.getBool(_kBayrak) ?? false) return;

  String? ham;
  try {
    ham = (await PlayInstallReferrer.installReferrer).installReferrer;
  } catch (e) {
    // Play Services hazır değil ya da eklenti yok: bayrak YAZILMAZ,
    // bir sonraki açılış yeniden dener.
    debugPrint('Install Referrer okunamadı (sonra denenecek): $e');
    return;
  }

  final kod = ortakKodunuAyikla(ham);
  if (kod == null) {
    // Referrer okundu ve içinde ortak kodu YOK — organik kurulum.
    // Bu TERMİNAL bir cevap: her açılışta yeniden okumanın anlamı yok.
    await prefs.setBool(_kBayrak, true);
    return;
  }

  await _gonder(dio, kod, prefs);
}

/// Uygulama ZATEN KURULUYKEN gelen `rytho.app/r/KOD` bağlantısı için.
///
/// O durumda Play devreye hiç girmez: işletim sistemi linki doğrudan
/// uygulamaya verir (AndroidManifest'teki `/r/` intent-filter) ve kod
/// URL'den okunur. İki yol da aynı uca çıkar ve aynı bayrağı paylaşır.
Future<void> applyPartnerCode(Dio dio, String kod) async {
  final temiz = kod.trim().toUpperCase();
  if (!kOrtakKodDeseni.hasMatch(temiz)) return;
  final prefs = await SharedPreferences.getInstance();
  if (prefs.getBool(_kBayrak) ?? false) return;
  await _gonder(dio, temiz, prefs);
}

Future<void> _gonder(Dio dio, String kod, SharedPreferences prefs) async {
  try {
    await dio.post('/api/v1/billing/redeem-code', data: {'code': kod});
    await prefs.setBool(_kBayrak, true);
  } on DioException catch (e) {
    final durum = e.response?.statusCode ?? 0;
    // ⚠️ 4xx TERMİNALDİR ve bayrak YAZILIR — 401 HARİÇ.
    //
    // `consent.dart` deseni burada AYNEN kopyalanamaz: o uç idempotent
    // 200 döner, bu uç ikinci çağrıda 409 `already_redeemed` döner
    // (kod süresi geçmişse 400). Desen körlemesine kopyalansaydı atfı
    // ZATEN olan her kullanıcı HER açılışta bir 409 isteği atardı ve
    // bayrak hiç yazılmazdı — App Check'in arkasında sessiz, kalıcı bir
    // çöp yük. Yalnız ağ hatası, 401 ve 5xx yeniden denenir.
    //
    // 401 istisnası: atıf UID BAŞINA yazılır, yani oturum açılmadan
    // gönderilen kod hiçbir hesaba bağlanamaz. Bayrağı orada yakmak
    // kullanıcı giriş yaptıktan SONRAKİ meşru denemeyi de kapatırdı —
    // `/r/` bağlantısına girişsiz dokunan kurulu uygulama tam bu hâle
    // düşüyor (bkz. deep_links.dart).
    if (durum == 401) {
      debugPrint('Ortak kodu ertelendi: oturum yok.');
    } else if (durum >= 400 && durum < 500) {
      await prefs.setBool(_kBayrak, true);
      debugPrint('Ortak kodu işlenmedi ($durum) — tekrar denenmeyecek.');
    } else {
      debugPrint('Ortak kodu ertelendi ($durum): ${e.message}');
    }
  } catch (e) {
    debugPrint('Ortak kodu ertelendi: $e');
  }
}

/// Ham referrer dizesinden ortak kodunu çıkarır; yoksa `null`.
///
/// Saf fonksiyon — test edilebilir olsun diye ayrı. Play'in verdiği dize
/// sorgu-dizesi biçimindedir ve BİZİM koymadığımız alanlar da taşıyabilir
/// (organik kurulumda `utm_source=google-play&utm_medium=organic`).
String? ortakKodunuAyikla(String? ham) {
  if (ham == null || ham.isEmpty) return null;
  // `Uri.splitQueryString` yüzde-kodlamayı da çözer; sayfa kodu
  // `encodeURIComponent` ile gönderiyor.
  Map<String, String> alanlar;
  try {
    alanlar = Uri.splitQueryString(ham);
  } catch (_) {
    return null;
  }
  final aday = (alanlar[_kKodAlani] ?? '').trim().toUpperCase();
  if (aday.isEmpty || !kOrtakKodDeseni.hasMatch(aday)) return null;
  return aday;
}
