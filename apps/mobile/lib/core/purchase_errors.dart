/// Mağaza (RevenueCat: Play ve App Store) hatalarının kullanıcı diline
/// çevirisi (G-turu).
///
/// İç test bulgusu: paywall bilinmeyen mağaza hatasında `e.message`'ı ham
/// basıyordu — kullanıcı Türkçe arayüzde "This product is already active
/// for the user." gördü. Kural: ekrana YALNIZ l10n metni çıkar; bilinmeyen
/// kodlar Crashlytics'e gider (kaybolmaz ama kullanıcıyı İngilizceyle baş
/// başa bırakmaz).
///
/// ## Tek kapı (D7)
/// Satın alma hatası üç ekranda üç ayrı yoldan çevriliyordu: paywall
/// `storeErrorText`, jeton mağazası `storeErrorText` + `friendlyError`,
/// abonelik ekranının geri yüklemesi yalnız `friendlyError` (PlatformException'ı
/// tanımıyor → ağ hatası "beklenmeyen sorun"). [purchaseErrorText] hepsini
/// tek kapıdan geçirir ve "zaten satın alınmış" kodunu ÜRÜNE göre ayırır:
/// abonelikte geri yükleme cümlesi, tüketilebilir pakette "işleniyor" —
/// çünkü Play bir consumable'ı tüketilmeden ikinci kez satmaz ve o hâl
/// "aboneliğin var" değil "ilk alımın hâlâ yolda" demektir. Eski metin
/// "Google hesabı" diyordu; iOS'ta yanlıştı, kelime gitti.
library;

import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:purchases_flutter/purchases_flutter.dart';

import '../l10n/app_localizations.dart';
import 'api.dart' show friendlyError;

/// Bilinmeyen mağaza kodunu Crashlytics'e yazan varsayılan kanal.
void varsayilanMagazaHatasiKaydedici(String mesaj) {
  if (!kDebugMode) {
    FirebaseCrashlytics.instance
        .recordError(mesaj, StackTrace.current, fatal: false);
  }
}

/// Kayıt kanalı — test dikişi.
@visibleForTesting
void Function(String mesaj) magazaHatasiKaydedici =
    varsayilanMagazaHatasiKaydedici;

/// Mağaza dışı bir GELİŞTİRİCİ kusurunu aynı kanala yazar (paywall:
/// anahtarsız derleme). Kanal test dikişi olduğu için dışarıdan doğrudan
/// çağrılamıyor; bu sarmalayıcı onun tek kamu kapısı.
void gelistiriciKusuruBildir(String mesaj) => magazaHatasiKaydedici(mesaj);

/// ÇİZİM yolunda bir kez bildirilmiş kodlar (bkz. [magazaVeyaAgHatasi]).
final Set<String> _cizimdeBildirilenKodlar = <String>{};

/// Testler arası sızmayı önler; kanalı da varsayılana döndürür.
@visibleForTesting
void magazaHataKaydiniSifirla() {
  _cizimdeBildirilenKodlar.clear();
  magazaHatasiKaydedici = varsayilanMagazaHatasiKaydedici;
}

/// Mağaza YA DA ağ hatasının kullanıcı diline çevirisi — paywall ile jeton
/// mağazasının hata dalının TEK kapısı.
///
/// Tek kapı şart: `friendlyError` PlatformException'ı tanımıyor, yani ayrı
/// ayrı çevirirsek aynı ağ hatası paywall'da doğru, jeton mağazasında
/// "beklenmeyen sorun" görünürdü.
///
/// Telemetri KOD BAŞINA BİR KEZ, ama YALNIZ BURADA. Bu fonksiyon `build()`
/// içinden çağrılıyor ve hata kartı ekranda durduğu SÜRECE her yeniden çizim
/// yeni bir Crashlytics kaydı üretirdi. Süzgeç [storeErrorText]in İÇİNE
/// KONAMAZ: satın alma akışı (paywall `_buy`/`_restore`, jeton mağazası
/// `_buy`) onu doğrudan çağırıyor ve oradaki tekrar sayısı sorunun
/// YAYGINLIĞIDIR — tekilleştirilirse ölçmek istediğimiz şey kaybolur.
String magazaVeyaAgHatasi(Object e, AppLocalizations l10n) {
  if (e is! PlatformException) return friendlyError(e, l10n);
  return storeErrorText(e, l10n, kaydet: _cizimdeBildirilenKodlar.add(e.code));
}

/// Satın alma / geri yükleme AKIŞININ hata metni — üç ekranın tek kapısı.
///
/// [abonelik] ürün sınıfı: `true` abonelik paketi, `false` tüketilebilir
/// jeton paketi. "Zaten satın alınmış" kodunun anlamı sınıfa göre değişir
/// (gerekçe dosya başında); öteki kodlar [storeErrorText]ten, mağaza dışı
/// hatalar (ağ, zaman aşımı, sunucu) `friendlyError`dan.
String purchaseErrorText(Object e, AppLocalizations l10n,
    {required bool abonelik}) {
  if (e is! PlatformException) return friendlyError(e, l10n);
  if (PurchasesErrorHelper.getErrorCode(e) ==
      PurchasesErrorCode.productAlreadyPurchasedError) {
    return abonelik
        ? l10n.purchaseAlreadyOwnedSubscription
        : l10n.purchasePackRefreshing;
  }
  return storeErrorText(e, l10n);
}

/// Ödeme mağazada ONAY BEKLİYOR mu?
///
/// iOS'ta iki kaynağı var (RevenueCat 5.67.1 kaynağında okundu): StoreKit 1
/// `.deferred` işlemi (`PurchasesOrchestrator`, Ask to Buy) ve StoreKit 2
/// `Product.PurchaseResult.pending` (`StoreKit2TransactionListener`; Apple'a
/// göre Ask to Buy ya da SCA gibi ek bir onay adımı). Android'de hangi
/// durumda geldiği bu depoda ölçülmedi.
///
/// Ekranlar bu durumu hata dalından AYIRMAK zorunda: satın alma reddedilmedi,
/// ertelendi — onay gelirse webhook aboneliği/krediyi sunucuya kendisi yazar.
/// Macenta hata metni kullanıcıya "olmadı, yeniden dene" der; yeniden denemek
/// ise aynı ürün için ikinci bir onay isteği açar.
bool odemeOnayBekliyor(PlatformException e) =>
    PurchasesErrorHelper.getErrorCode(e) ==
    PurchasesErrorCode.paymentPendingError;

/// [kaydet] yalnız çizim yolunda `false` olabilir (bkz. [magazaVeyaAgHatasi]);
/// satın alma akışı HER denemeyi kaydeder.
///
/// Platform dalı yalnız gerçekten farklı çareler için var (U46). "Zaten
/// satın alınmış" ve "ürün yok" metinleri eskiden Google hesabını ve Play
/// test kanalını anıyordu; iOS'ta ikisinin de karşılığı yok ve kullanıcıyı
/// (ya da inceleyiciyi) var olmayan bir ayarı aramaya gönderirdi. D7 o iki
/// metni platformdan bağımsız yazdı, bu yüzden iOS'a ayrı kopya gerekmedi.
/// Kalan dal [PurchasesErrorCode.purchaseNotAllowedError]: iOS'ta çaresi
/// Ekran Süresi ayarı, Android'de geçici bir mağaza sorunu.
String storeErrorText(PlatformException e, AppLocalizations l10n,
    {bool kaydet = true}) {
  final ios = defaultTargetPlatform == TargetPlatform.iOS;
  switch (PurchasesErrorHelper.getErrorCode(e)) {
    case PurchasesErrorCode.productAlreadyPurchasedError:
      // Ürün sınıfını bilmeyen çağıran için abonelik cümlesi: bu kod bugün
      // yalnız [purchaseErrorText] üzerinden geliyor, orası sınıfı biliyor.
      return l10n.purchaseAlreadyOwnedSubscription;
    case PurchasesErrorCode.productNotAvailableForPurchaseError:
    case PurchasesErrorCode.purchaseInvalidError:
      // Üretim dili: eski metin iç test kanalına katılmayı anlatıyordu
      // (Erkan vakası, 2026-08-12) ve mağazadaki her kullanıcıya test
      // yönergesi okutuyordu.
      return l10n.purchaseItemUnavailable;
    case PurchasesErrorCode.networkError:
    case PurchasesErrorCode.offlineConnectionError:
      return l10n.authNetwork;
    case PurchasesErrorCode.storeProblemError:
      return l10n.purchaseStoreProblem;
    case PurchasesErrorCode.purchaseNotAllowedError:
      // iOS'ta RevenueCat bu kodu StoreKit'in "bu cihaz/kullanıcı ödeme
      // yapamaz" hatalarından üretiyor (`paymentNotAllowed`, `clientInvalid`,
      // `cloudServicePermissionDenied`, StoreKit 2 `purchaseNotAllowed`) —
      // tipik kaynağı Ekran Süresi'ndeki uygulama içi satın alma kısıtı.
      // Kısıt kalkmadıkça KALICI, yani eski "birkaç dakika sonra tekrar
      // dene" metni hiçbir zaman işe yaramazdı.
      return ios ? l10n.purchaseNotAllowedIos : l10n.purchaseStoreProblem;
    case PurchasesErrorCode.paymentPendingError:
      // Hata DEĞİL, kaydedilmez: Ask to Buy'da ebeveyn onayı saatler
      // sürebilir ve her bekleyen alım Crashlytics'te gerçek hataları
      // gömen sahte bir kayıt olurdu. Ekranlar bu metni hata rengiyle
      // DEĞİL bilgi olarak gösterir (bkz. [odemeOnayBekliyor]).
      return l10n.purchasePending;
    case PurchasesErrorCode.configurationError:
      // iOS'ta bu kodun en olası anı paywall'ın teklif okumasıdır:
      // RevenueCat `getOfferings`, teklifte ürün yoksa ya da StoreKit
      // ürünlerin hiçbirini döndürmezse (App Store Connect'te hazır/onaylı
      // değil) bu kodu veriyor (`OfferingsManager`). Eskiden varsayılana
      // düşüp HENÜZ SATIN ALMA YOKKEN "Satın alma tamamlanamadı" diyordu.
      // Kullanıcının düzeltebileceği bir şey yok (kurulum bizim işimiz), bu
      // yüzden kayıt KALIR — yanlış kurulmuş bir yayın sahada sessizce satış
      // kaybederdi. Çizim yolundaki tekilleştirme [magazaVeyaAgHatasi]'nda.
      if (kaydet) {
        magazaHatasiKaydedici('store-purchase: ${e.code}: ${e.message}');
      }
      return l10n.billingNoPackages;
    default:
      if (kaydet) {
        magazaHatasiKaydedici('store-purchase: ${e.code}: ${e.message}');
      }
      return l10n.purchaseFailed;
  }
}
