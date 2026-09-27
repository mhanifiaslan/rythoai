import 'package:dio/dio.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api.dart';
import 'providers.dart';
import 'wallet.dart' show walletProvider;

/// Rytho+ aboneliği.
///
/// İki kaynak vardır ve **sunucu esastır**: RevenueCat SDK'sı cihazda hızlı
/// yanıt verir ama asıl doğruluk `/api/v1/billing/status` ucundan gelir.
/// Sunucu bu bilgiyi yalnızca RevenueCat webhook'undan yazar; istemcinin
/// abonelik kaydına yazma izni yoktur (bkz. infra/firestore.rules).
///
/// Böylece istemci tarafında kurcalayarak ücretli içerik açılamaz: uçlar
/// kilitliyse sunucu 402 döner, arayüz ne gösterirse göstersin.

/// RevenueCat genel API anahtarları.
///
/// Kaynağa gömülmez; çalıştırırken geçilir:
/// `flutter run --dart-define-from-file=dart_defines.local.json`
/// (örnek için bkz. `dart_defines.example.json`).
///
/// Tanımlı değilse SDK hiç başlatılmaz ve satın alma devre dışı kalır —
/// uygulamanın geri kalanı ücretsiz katmanla normal çalışır.
///
/// UYARI: `test_` önekli anahtarlar RevenueCat Test Store'a aittir ve satın
/// almaları **simüle eder**. Yayın öncesi gerçek mağaza anahtarlarıyla
/// (`appl_...` / `goog_...`) değiştirilmelidir.
const String kRevenueCatAndroidKey =
    String.fromEnvironment('REVENUECAT_ANDROID_KEY');
const String kRevenueCatIosKey = String.fromEnvironment('REVENUECAT_IOS_KEY');

/// RevenueCat panelinde tanımlı yetki (entitlement) kimliği.
/// Paneldeki adla birebir aynı olmalı; farklıysa satın alma sonrası
/// `entitlements.active` boş görünür ve abonelik açılmaz.
///
/// Varsayılan panele HİZALI (M1): eski varsayılan 'rytho_plus' idi ve
/// dart-define'sız her derleme (CI, düz `flutter build`) sessizce yanlış
/// yetkiye bakıyordu — panel 'RhytoAI Pro'. Tek gerçek panel kimliğidir.
const String kPlusEntitlement = String.fromEnvironment(
    'RYTHO_PLUS_ENTITLEMENT',
    defaultValue: 'RhytoAI Pro');

bool get billingConfigured =>
    kRevenueCatAndroidKey.isNotEmpty || kRevenueCatIosKey.isNotEmpty;

class SubscriptionStatus {
  const SubscriptionStatus({
    required this.active,
    this.productId,
    this.expiresAt,
    this.willRenew,
    this.isTrial,
    this.trialDaysLeft,
    this.okunabildi = true,
  });

  final bool active;
  final String? productId;
  final DateTime? expiresAt;
  final bool? willRenew;
  final bool? isTrial;

  /// OT6: sunucu taraflı 3 günlük denemede kalan gün — paywall geri
  /// sayımı. Deneme aktif değilse null. Kural SUNUCUDA yaşar; istemci
  /// tarih hesabı yapmaz (iki kopya kaçınılmaz olarak ayrışırdı).
  final int? trialDaysLeft;

  /// Durum SUNUCUDAN okunabildi mi?
  ///
  /// "Abone degil" ile "bilmiyorum" ayni sey degil (ilkacilis-2): soguk
  /// acilista tek 5xx ya da tek zaman asimi `active: false` uretiyordu ve
  /// denemesi suren testcinin yuzune tanitim paywall'i acilip hesap
  /// omrundeki TEK gosterim bosa yaniyordu. Kilitler yine `active`e bakar
  /// (bilinmiyorken kapali kalmak dogru taraf); yalniz KULLANICIYA BIR SEY
  /// SOYLEYEN kararlar bu alani sorar.
  final bool okunabildi;

  /// Oturum yok — BILINEN durum.
  static const none = SubscriptionStatus(active: false);

  /// Sunucuya ulasilamadi; abonelik durumu bilinmiyor.
  static const bilinmiyor =
      SubscriptionStatus(active: false, okunabildi: false);

  factory SubscriptionStatus.fromJson(Map<String, dynamic> json) {
    final raw = json['expires_at'] as String?;
    return SubscriptionStatus(
      active: json['active'] == true,
      productId: json['product_id'] as String?,
      expiresAt: raw == null ? null : DateTime.tryParse(raw),
      willRenew: json['will_renew'] as bool?,
      isTrial: json['is_trial'] as bool?,
      trialDaysLeft: (json['trial_days_left'] as num?)?.toInt(),
    );
  }
}

/// RevenueCat SDK kurulumu. Anahtar yoksa sessizce atlanır.
///
/// Burada **kullanıcı bağlanmaz**: uygulama açılırken Firebase oturumu henüz
/// geri yüklenmemiş olabilir ve `currentUser` null döner. Kimlik bağlama
/// [billingIdentityProvider] ile oturum akışına bağlıdır.
Future<void> initBilling() async {
  if (!billingConfigured) return;
  try {
    final key = defaultTargetPlatform == TargetPlatform.iOS
        ? kRevenueCatIosKey
        : kRevenueCatAndroidKey;
    if (key.isEmpty) return;

    await Purchases.setLogLevel(LogLevel.warn);
    await Purchases.configure(PurchasesConfiguration(key));
  } catch (e) {
    debugPrint('RevenueCat başlatılamadı: $e');
  }
}

/// RevenueCat kimliğini Firebase oturumuna bağlar.
///
/// **Bu bağlama olmadan satın alma kaybolur.** RevenueCat oturum açılmamışsa
/// anonim bir kimlik (`$RCAnonymousID:...`) üretir ve webhook sunucuya o
/// kimlikle gelir; sunucu aboneliği o dokümana yazar, kullanıcının Firebase
/// uid'i altında hiçbir şey olmaz. Sonuç: ödeme başarılı görünür ama kilitli
/// ekran açılmaz ve paywall tekrar tekrar gelir.
///
/// Eskiden bağlama yalnızca açılışta bir kez deneniyordu ve Firebase oturumu
/// asenkron geri yüklendiği için çoğu açılışta `currentUser` henüz null
/// oluyordu. Bu yüzden kimlik artık oturum AKIŞINA bağlı.
final billingIdentityProvider = Provider<void>((ref) {
  if (!billingConfigured) return;

  ref.listen<AsyncValue<User?>>(authStateProvider, (previous, next) {
    final uid = next.value?.uid;
    final oncekiUid = previous?.value?.uid;
    if (uid == oncekiUid) return;

    Future<void>(() async {
      try {
        if (uid == null) {
          await Purchases.logOut();
        } else {
          await Purchases.logIn(uid);
        }
      } catch (e) {
        // Sahada görünmez kalmasın: kimlik bağlanamazsa satın almalar anonim
        // kimliğe iner ve sunucuda yetim kalır (iç test bulgusu, 2026-08-12).
        // Satın alma anındaki ensureBillingIdentity son savunma hattı; burası
        // ise sorunun YAYGINLIĞINI gösteren telemetri.
        debugPrint('RevenueCat kimliği bağlanamadı: $e');
        if (!kDebugMode) {
          FirebaseCrashlytics.instance.recordError(
              'billing-identity: $e', StackTrace.current,
              fatal: false);
        }
      }
      ref.invalidate(subscriptionProvider);
    });
  }, fireImmediately: true);
});

/// Sunucunun gördüğü abonelik durumu — arayüz kilitleri buna bakar.
final subscriptionProvider =
    FutureProvider<SubscriptionStatus>((ref) async {
  final user = ref.watch(authStateProvider).value;
  if (user == null) return SubscriptionStatus.none;
  return abonelikDurumunuOku(ref.watch(apiProvider));
});

/// `/billing/status` okumasi — saglayicidan AYRI tutuluyor, cunku bekcisi
/// sahte bir Firebase `User`i olmadan yazilamaz (ilkacilis-2).
Future<SubscriptionStatus> abonelikDurumunuOku(Dio dio) async {
  try {
    final response = await dio.get('/api/v1/billing/status');
    return SubscriptionStatus.fromJson(
        Map<String, dynamic>.from(response.data));
  } catch (_) {
    // Durum okunamadıysa ücretsiz varsay; sunucu zaten uçları koruyor.
    //
    // Yakalama BİLEREK geniş (`on DioException` değil): bu sağlayıcı hata
    // durumuna DÜŞMEMELİ. Riverpod hatalı bir sağlayıcıyı yeniden deniyor ve
    // `.future` o süre boyunca tamamlanmıyor; satın alma sonrası yoklama da
    // orada asılı kalıyordu.
    //
    // Ama "ucretsiz varsay" artik SESSIZ degil: bayrak duser, boylece
    // kullaniciya bir sey SOYLEYEN kararlar bu acilista susar.
    return SubscriptionStatus.bilinmiyor;
  }
}

/// Tanitim paywall'i karari bu durumla VERILEBILIR mi?
///
/// Hesap omrunde bir kez gosterilen bir ekran icin "bilmiyorum" yeterli
/// gerekce degil: yukleniyorsa (KT3) ya da istek dustuyse (ilkacilis-2) karar
/// bir sonraki acilisa kalir — bayrak YANMAZ.
bool paywallKarariVerilebilir(AsyncValue<SubscriptionStatus> durum) =>
    !durum.isLoading && (durum.value?.okunabildi ?? false);

/// Kullanıcıya sunulacak plan tipleri.
///
/// RevenueCat teklifinde başka paketler tanımlı olsa da uygulama yalnızca
/// buradakileri gösterir; böylece plan yapısı panele dokunmadan tek yerden
/// değişir. Karar: **sadece aylık**.
const List<PackageType> kOfferedPackageTypes = [PackageType.monthly];

/// Mağazadan teklifleri getiren işlev — TEST DİKİŞİ.
///
/// Dikiş olmadan bu sağlayıcının GERÇEK gövdesi hiç koşmuyor: `Purchases`
/// eklentisi `flutter test` içinde çağrılamaz ve dart-define verilmediği için
/// `billingConfigured` false. Yani "hata yutuluyor mu" sorusunu hiçbir test
/// soramıyordu — yutmanın geri gelmesi sessiz kalırdı.
typedef TeklifGetirici = Future<Offerings> Function();

/// `null` = üretim yolu (mağaza anahtarı yoksa boş liste).
final teklifGetiriciProvider = Provider<TeklifGetirici?>((_) => null);

/// Satın alınabilir paketler.
///
/// Hata YUTULMAZ — bilerek. Eskiden mağaza/ağ hatasında BOŞ LİSTE dönüyordu
/// ve iki sonucu vardı: (1) bu sağlayıcı auto-dispose DEĞİL (Riverpod 3
/// varsayılanı), yani boş liste oturum boyunca önbellekte kalıyor ve
/// paywall'ı kapatıp açmak kurtarmıyordu — tek çıkış uygulamayı yeniden
/// başlatmaktı; (2) ekran "Mağazada tanımlı paket bulunamadı" diyerek ağ
/// sorununu mağazaya yıkıyordu. Fırlatınca `paywall_screen.dart`'taki
/// `error:` dalı canlanır ve kullanıcı yeniden deneme düğmesi görür.
final offeringsProvider = FutureProvider<List<Package>>((ref) async {
  final getirici = ref.watch(teklifGetiriciProvider);
  if (getirici == null && !billingConfigured) return const [];
  final offerings =
      getirici == null ? await Purchases.getOfferings() : await getirici();
  final all = offerings.current?.availablePackages ?? const <Package>[];
  final filtered = all
      .where((p) => kOfferedPackageTypes.contains(p.packageType))
      .toList();
  // Teklifte hiç eşleşme yoksa kullanıcıyı boş ekranla baş başa bırakma.
  return filtered.isEmpty ? all : filtered;
});

/// Paket satın alma işlevi — TEST DİKİŞİ.
///
/// Paywall'ın mağaza hata dalları ancak `Purchases.purchase` fırlatınca
/// koşuyor ve o eklenti `flutter test` içinde çağrılamaz ([TeklifGetirici]
/// ile aynı gerekçe). Dikişsiz hâlde "onay bekleyen ödeme hata rengine mi
/// boyanıyor" sorusunu hiçbir test soramazdı.
typedef PaketSatinAlici = Future<bool> Function(WidgetRef ref, Package paket);

final paketSatinAliciProvider =
    Provider<PaketSatinAlici>((_) => purchasePackage);

/// Geri yükleme işlevi — TEST DİKİŞİ ([PaketSatinAlici] ile aynı gerekçe;
/// Abonelik ekranının geri yükleme hata dalı ancak bununla ölçülebiliyor).
typedef GeriYukleyici = Future<bool> Function(WidgetRef ref);

final geriYukleyiciProvider =
    Provider<GeriYukleyici>((_) => restorePurchases);

/// RevenueCat müşteri bilgisini getiren işlev — TEST DİKİŞİ.
typedef MusteriBilgisiGetirici = Future<CustomerInfo> Function();

/// `null` = üretim yolu (mağaza anahtarı yoksa hiç sorulmaz).
final musteriBilgisiGetiriciProvider =
    Provider<MusteriBilgisiGetirici?>((_) => null);

/// "Aboneliği yönet"e dokunan kullanıcının en fazla bekleyeceği süre;
/// cevap gelmezse çalışan platformun mağazası açılır.
const Duration _kKaynakMagazaSiniri = Duration(seconds: 3);

/// Etkin Rytho+ yetkisinin satın alındığı mağaza; bilinmiyorsa `null` (U47).
///
/// Sunucu bu bilgiyi istemciye vermiyor: webhook `store`u abonelik kaydına
/// yazıyor ama `/billing/status` döndürmüyor. RevenueCat ise yetkiyi
/// uygulama kullanıcı kimliğinde tutuyor ve her yetkinin kaynağını
/// `EntitlementInfo.store`da taşıyor — Android'de alınıp iPhone'da görülen
/// abonelik orada `Store.playStore` olur. Çalışan platforma bakmak bu
/// kullanıcıya aboneliğin OLMADIĞI mağazanın sayfasını açıyordu.
///
/// Hata YUTULUR — bilerek: cevap yalnız hangi sayfanın açılacağını seçiyor;
/// okunamazsa çalışan platformun mağazası (eski davranış) açılır.
Future<Store?> abonelikKaynakMagazasi(MusteriBilgisiGetirici? getirici) async {
  if (getirici == null && !billingConfigured) return null;
  try {
    final bilgi = await (getirici ?? Purchases.getCustomerInfo)()
        .timeout(_kKaynakMagazaSiniri);
    return bilgi.entitlements.active[kPlusEntitlement]?.store;
  } catch (e) {
    debugPrint('Abonelik mağazası okunamadı: $e');
    return null;
  }
}

/// Satın alma/geri yükleme ÖNCESİ RevenueCat kimliğini garantiye alır.
///
/// [billingIdentityProvider] oturum akışına bağlı ama tek denemeli:
/// `logIn` o an düşerse (ağ, soğuk başlangıç) kimlik anonim kalıyor ve
/// satın alma `$RCAnonymousID:...` altına yazılıyordu — webhook sunucuda
/// anonim dokümana işledi, kullanıcının uid'i boş kaldı, ödeme yapılmış
/// ama her şey kilitli görünmüştü (iç test, 2026-08-10, Feyza vakası).
/// Paranın el değiştirdiği anda kimliği şansa bırakmıyoruz.
Future<void> ensureBillingIdentity() async {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) {
    // Paywall yalnız oturumlu ekranlardan açılır; buraya düşmek anormal.
    throw StateError('Oturum yokken satın alma başlatıldı.');
  }
  final mevcut = await Purchases.appUserID;
  if (mevcut != uid) {
    await Purchases.logIn(uid);
  }
}

/// Satın alma. Başarılıysa sunucu yetkiyi görene kadar bekler.
///
/// Yetki sunucuya **webhook üzerinden** işleniyor: satın almanın bitmesiyle
/// `/billing/status` uçlarının "aktif" demesi arasında saniyeler olabilir.
/// Tek seferlik `invalidate` bu yarışı kaybediyordu — kullanıcı ödeme yapıyor,
/// ekran kapanıyor, kilitli içeriğe dokunuyor ve sunucu henüz haberdar
/// olmadığı için 402 dönüp paywall yeniden açılıyordu.
///
/// Bu yüzden durum kısa aralıklarla birkaç kez okunur. Süre dolarsa yine de
/// `true` döneriz: satın alma cihazda gerçekleşti, gecikme sunucu tarafındadır
/// ve kullanıcıyı ödeme ekranına geri göndermek yanlış olur.
Future<bool> purchasePackage(WidgetRef ref, Package package) async {
  await ensureBillingIdentity();
  final result = await Purchases.purchase(PurchaseParams.package(package));
  final active =
      result.customerInfo.entitlements.active.containsKey(kPlusEntitlement);
  if (!active) return false;

  await _waitForServerEntitlement(ref);
  return true;
}

/// Tek bir durum yoklamasının üst sınırı.
///
/// Dio'nun alım zaman aşımı 120 saniye; sınırsız bırakılırsa beş yoklama en
/// kötü hâlde on dakika sürebiliyordu. Kullanıcının gördüğü şey "ödeme
/// adımını geçemiyorum" oluyor.
const Duration _kYoklamaSiniri = Duration(seconds: 6);

/// Sunucuyu bekleme bütçesinin tamamı.
const Duration _kBeklemeButcesi = Duration(seconds: 15);

/// Sunucu aboneliği görene kadar bekler — sınırlı bir bütçeyle.
///
/// Süre dolarsa sessizce çıkılır: satın alma cihazda gerçekleşti, gecikme
/// sunucu tarafında ve kullanıcıyı ödeme ekranında tutmak yanlış olur.
Future<void> _waitForServerEntitlement(WidgetRef ref) async {
  const gecikmeler = [
    Duration(milliseconds: 400),
    Duration(seconds: 1),
    Duration(seconds: 2),
    Duration(seconds: 3),
    Duration(seconds: 4),
  ];
  final bitis = DateTime.now().add(_kBeklemeButcesi);
  for (final gecikme in gecikmeler) {
    if (DateTime.now().isAfter(bitis)) break;
    ref.invalidate(subscriptionProvider);
    // Cüzdan da tazelenir (K2): aylık 300 jetonluk hak webhook'la aynı
    // anda yazılıyor; yalnız aboneliği yoklamak, Abonelik ekranının bayat
    // "0/300" göstermesine yol açıyordu (iç test bulgusu — "ilk alımda
    // kredi sıfır").
    ref.invalidate(walletProvider);
    try {
      final durum =
          await ref.read(subscriptionProvider.future).timeout(_kYoklamaSiniri);
      if (durum.active) {
        ref.invalidate(walletProvider); // hak yazıldıysa son bir tazeleme
        return;
      }
    } catch (_) {
      // Yoklama düşerse beklemeyi sürdür; bu bir satın alma hatası değil.
    }
    await Future<void>.delayed(gecikme);
  }
  ref.invalidate(subscriptionProvider);
  ref.invalidate(walletProvider);
}

/// Ödeme ONAY BEKLERKEN abonelik ve cüzdan önbelleğini düşürür (U33).
///
/// Onayı BEKLEMEZ ve kilidi AÇMAZ — bunu yanlış okumak kolay. Onay gelene
/// kadar sunucu "abone değil" der; iki sağlayıcı da auto-dispose değil ve
/// paywall açıkken altta duran Gökyüzü ekranında izleniyor (kredi çipi,
/// kilitli şeritler), yani bu çağrı onları ŞİMDİ yeniden okutur ve o anki
/// cevap önbelleğe girer. Sonradan gelen bir onay ekrana ancak bir sonraki
/// tazelemede yansır (Gökyüzü'nde çek-yenile, "Satın alımları geri yükle",
/// yeniden açılış). Sunucu tarafında kapı webhook'la kendiliğinden kalkar.
///
/// Yine de çağrılıyor: mağazada artık bu hesaba ait bir işlem VAR ve
/// ekranların satın alma ÖNCESİ anlık görüntüde kalması için sebep yok;
/// bedeli tek bir yeniden okuma. [abonelik] kredi paketinde `false`:
/// abonelik sağlayıcısını düşürmek ona bağlı ücretli sağlayıcıları da
/// yeniden kurar, kredi alımı ise aboneliği değiştirmez.
void odemeOnayiBekleniyor(WidgetRef ref, {bool abonelik = true}) {
  if (abonelik) ref.invalidate(subscriptionProvider);
  ref.invalidate(walletProvider);
}

/// Onboarding sonrası paywall'ın bir kez gösterilip gösterilmediği.
const String _kIntroPaywallKey = 'introPaywallShown';

/// Tanıtım paywall'ı daha önce gösterildi mi?
Future<bool> introPaywallShown() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kIntroPaywallKey) ?? false;
  } catch (_) {
    // Okunamazsa göstermemiş gibi davranmak, kullanıcıyı her açılışta
    // paywall'la karşılaştırma riskini doğurur; güvenli taraf "gösterildi".
    return true;
  }
}

Future<void> markIntroPaywallShown() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kIntroPaywallKey, true);
  } catch (_) {}
}

/// Satın alımları geri yükle (mağaza kuralı: bu seçenek sunulmak zorunda).
Future<bool> restorePurchases(WidgetRef ref) async {
  await ensureBillingIdentity();
  final info = await Purchases.restorePurchases();
  final active = info.entitlements.active.containsKey(kPlusEntitlement);
  if (active) {
    await _waitForServerEntitlement(ref);
  } else {
    ref.invalidate(subscriptionProvider);
    ref.invalidate(walletProvider);
  }
  return active;
}
