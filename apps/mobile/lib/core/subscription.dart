import 'dart:async';

import 'package:dio/dio.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart' show StateProvider;
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api.dart';
import 'providers.dart';
import 'wallet.dart' show cuzdanTazelemeProvider, walletProvider;

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

  // Kalıcı toplayıcı BURADAN kuruluyor — izlenmezse hiç doğmaz.
  //
  // `main.dart`'taki kapı yalnız bu sağlayıcıyı izliyor
  // ([notificationSyncProvider] ile aynı durum) ve toplayıcı uygulama ömrü
  // boyunca yaşamak ZORUNDA: işi tam da ekran söküldükten sonra olanı
  // yakalamak. Kendi başına duran bir sağlayıcı olarak bırakılsaydı
  // kimse izlemediği için gövdesi hiç koşmazdı.
  ref.watch(yetkiToplayiciProvider);
});

/// Mağazanın bildirdiği yetki değişimini sayan SAYAÇ.
///
/// Kalıcı toplayıcının ([yetkiToplayiciProvider]) yazdığı tek yer; okuyan
/// [subscriptionProvider]. Halka bu yüzden kurulmuyor: dinleyici sağlayıcıya
/// DOKUNMAZ, sade bir sayaca yazar (bulgu B10'un dersi — `apiProvider`'ın
/// interceptor'ından `subscriptionProvider`'a dokunmak çalışma anında
/// `CircularDependencyError` fırlatıyordu).
///
/// Bayrak DEĞİL sayaç: `bool` ikinci olayda `true`→`true` olur, Riverpod
/// "değişmedi" sayar ve durum bir daha tazelenmez — bayrağı geri indirecek
/// kimse de yok (`cuzdanTazelemeProvider` ile birebir aynı gerekçe).
final yetkiDegisimProvider = StateProvider<int>((_) => 0);

/// Sunucunun gördüğü abonelik durumu — arayüz kilitleri buna bakar.
final subscriptionProvider =
    FutureProvider<SubscriptionStatus>((ref) async {
  // Toplayıcının sayacı İZLENİYOR: mağaza yetkiyi değiştirdiğinde durum
  // EKRAN ÖMRÜNDEN BAĞIMSIZ yeniden okunur. Bu sağlayıcı auto-dispose
  // değil, yani sayaç olmadan bayat bir "abone değil" oturum boyunca
  // önbellekte kalıyordu.
  ref.watch(yetkiDegisimProvider);
  final user = ref.watch(authStateProvider).value;
  if (user == null) return SubscriptionStatus.none;
  return abonelikDurumunuOku(ref.watch(apiProvider));
});

/// Mağazanın yetki bildirimini dinleyiciye bağlayan işlev — TEST DİKİŞİ.
///
/// Dikiş [teklifGetiriciProvider] ile aynı gerekçeyle var: `Purchases`
/// eklentisi `flutter test` içinde çağrılamaz, yani dikişsiz hâlde
/// toplayıcının gövdesi hiçbir testte KOŞMUYOR ve "toplayıcı söküldü"
/// sessizce geçerdi.
///
/// Dinleyiciye `CustomerInfo` değil **aktif yetki kimlikleri** verilir:
/// testin elinde `CustomerInfo` üretmenin yolu yok, kararın ihtiyacı olan
/// bilgi ise yalnız bu küme.
typedef YetkiDinleyiciKurucu = void Function(
    void Function(Set<String> aktifYetkiler));

/// `null` = üretim yolu (`Purchases.addCustomerInfoUpdateListener`).
final yetkiDinleyiciKurucuProvider =
    Provider<YetkiDinleyiciKurucu?>((_) => null);

/// Satın almanın sonucunu EKRANDAN BAĞIMSIZ toplayan kalıcı dinleyici.
///
/// Neden var (ölçüldü, 1.17.0+45 — paketin en pahalı kusuru): satın almanın
/// sonucunu toplayan tek yer [purchasePackage] idi ve o bir `WidgetRef`
/// taşıyor. Kullanıcı mağaza penceresi açıkken ödeme ekranını kapatırsa o
/// `WidgetRef` sökülmüş bir elemente bakar ve kullanıldığı anda FIRLATIR;
/// hata `paywall_screen`in geniş `catch`ine düşer, orada `mounted` false
/// olduğu için HİÇBİR ŞEY yapılmaz — log bile düşmez. Sonucu: **ödeme
/// cihazda gerçekleşti, uygulama bilmiyor.** Yedek de yoktu; bu dinleyici
/// depoda hiç kurulmamıştı ve `didChangeAppLifecycleState` yalnız sürüm
/// kapısını tazeliyor.
///
/// Dinleyici `Purchases.addCustomerInfoUpdateListener` — isim VARSAYILMADI,
/// pakette ölçüldü (purchases_flutter 9.16.1, `lib/purchases_flutter.dart`).
/// Paket onu kaydedilir kaydedilmez SDK'nın son bilinen bilgisiyle bir kez
/// çağırıyor (`_lastReceivedCustomerInfo` doluysa, SENKRON — gövde yeniden
/// okundu); bu yüzden ilk çağrı yalnız TEMEL ALINIR, sayacı artırmaz. Bedeli
/// ölçülü: o yankıyı olay saymak her açılışta bir `/billing/status` +
/// `/billing/wallet` turu, abonede ayrıca iki adımlık merdiven demekti — yani
/// kural kaldırılamaz, DELİĞİ kapatılır.
///
/// Delik gerçekti ve artık KAPALI: süreçte hiç `CustomerInfoUpdated` olayı
/// olmamışsa (önbellekte `CustomerInfo` yok, yani kayıt anında senkron yankı
/// da yok) satın almanın ürettiği olay İLK olay olur ve temel sayılıp
/// yutulurdu — sayaç artmaz, merdiven kurulmaz, yani toplayıcı tam da var
/// olma sebebinde susardı. Temel artık yalnız ilk bildirimden kurulmuyor:
/// satın alma/geri yükleme BAŞLARKEN [yetkiTemeliniKurulmusSay] kuruyor.
///
/// ⚠️ Deliğin KAPANMAYAN dilimi — yukarıdaki "KAPALI" yalnız UYGULAMA
/// İÇİNDEN başlayan yetki kazanımları için doğru, ve eksik bir gerekçe
/// bu depoda kusur sayılıyor. Uygulama DIŞINDA kazanılan yetki
/// (abonelik yenilemesi, Play Store / App Store yüzeyinden abone olma,
/// başka bir cihazda alınan abonelik) ne `purchasePackage`tan ne
/// `restorePurchases`tan geçer, yani temeli kuran kanca hiç çağrılmaz.
/// O bildirim süreçteki İLK `CustomerInfoUpdated` ise hâlâ temel sayılıp
/// yutulur: `subscriptionProvider` auto-dispose olmadığı için bayat
/// "abone değil" oturum boyunca önbellekte kalır ve kullanıcı ödediği
/// hâlde kilitleri görür. Uygulamayı yeniden başlatmak kurtarır.
///
/// Niçin kapatılmadı: bilinen tek yol yutma kuralını kaldırmaktı ve onun
/// ÖLÇÜLEN bedeli her açılışta üç tazeleme (abonede altı istek). Bu, 429
/// geçmişi olan bir yola her açılışta sabit yük bindirmek olurdu.
/// ⚠️ [AbonelikKurtarmaGozcusu] bunu KAPATMAZ: o yalnız durum
/// OKUNAMADIYSA tazeliyor; burada durum pekâlâ okunabilmiş, yalnız bayat.
///
/// Yetki KAZANILDIĞINDA sunucu yoklanır, KAYBEDİLDİĞİNDE tek tazeleme
/// yeter: kaybı sunucuya webhook yazar ve "yetki gelene kadar bekle"
/// döngüsü orada beklenecek bir şey olmadığı için bütçeyi boşa harcar.
final yetkiToplayiciProvider = Provider<void>((ref) {
  final kurucu = ref.watch(yetkiDinleyiciKurucuProvider);
  if (kurucu == null && !billingConfigured) return;

  // Sökülmüş kapsamda `ref.read` FIRLATIR ve bu kod mağaza dinleyicisinden
  // geliyor — hatayı yakalayacak bir çağıran yok, uygulama dışına düşerdi.
  var sokuldu = false;
  ref.onDispose(() => sokuldu = true);

  Set<String>? onceki;

  // Temel dışarıdan da kurulabiliyor; gerekçesi [yetkiTemeliniKurulmusSay]'da.
  // Kanca kapanış KİMLİĞİYLE geri alınıyor: testlerde birden çok kapsam
  // kuruluyor ve körlemesine `null` atamak BAŞKA bir kapsamın kancasını
  // söküp bu sağlayıcıyı sessizce eski hâline döndürürdü.
  void temeliKur() => onceki ??= const <String>{};
  _toplayiciTemeliniKur = temeliKur;
  ref.onDispose(() {
    if (_toplayiciTemeliniKur == temeliKur) _toplayiciTemeliniKur = null;
  });

  // Sayaç yazımları HER ZAMAN build'in DIŞINDA koşuyor.
  //
  // Ölçüldü (Riverpod 3.3.2): bir sağlayıcının build'i içinde `StateProvider`a
  // yazmak FIRLATIYOR — `ProviderException: Tried to use a provider that is in
  // error state` — ve hata o sağlayıcıda KALMIYOR: onu `ref.watch` eden
  // sağlayıcının da fırlattığı aynı ölçümde görüldü. Zincir
  // [billingIdentityProvider] → `main.dart`'taki kapı, yani bedeli AÇILIŞIN
  // KENDİSİ olurdu.
  //
  // Yazımın build'e düşmesi varsayımsal DEĞİL: paket dinleyiciyi kayıt anında
  // SENKRON çağırıyor (gerekçe yukarıda) ve o çağrı tam da bu gövdenin içinde
  // düşüyor. Eskiden kazayı önleyen tek şey "ilk bildirimi yut" kuralıydı —
  // yani bir İSTEK TASARRUFU, açılışın ayakta kalmasını taşıyordu. Artık
  // taşımıyor; o kural değişse bile yazım build'e inemez.
  void sayaclariArtir() {
    scheduleMicrotask(() {
      if (sokuldu) return;
      // Sayaçlar BİRLİKTE artıyor: aylık jeton hakkını da aynı webhook
      // yazıyor, yani yalnız aboneliği sormak Abonelik ekranını bayat
      // bakiyeyle bırakırdı (ekrandaki akışın öğrendiği ders).
      ref.read(yetkiDegisimProvider.notifier).state++;
      ref.read(cuzdanTazelemeProvider.notifier).state++;
    });
  }

  void geldi(Set<String> aktif) {
    if (sokuldu) return;
    final ilkBildirim = onceki == null;
    final degisti = !ilkBildirim && !setEquals(onceki, aktif);
    onceki = aktif;
    if (ilkBildirim || !degisti) return;

    sayaclariArtir();

    if (!aktif.contains(kPlusEntitlement)) return;

    // Merdiven KOŞULSUZ ve KISA.
    //
    // Üç adım, webhook'un ölçülen gecikmesine göre: ilk bump hemen yukarıda
    // atıldı, kalanlar 1 ve 4 saniye sonra. Ekrandaki akışın beş adımlık
    // merdiveni burada kullanılmıyor.
    //
    // Merdiven artık ekran yokluyorken de KURULUYOR. Eskiden bildirim anında
    // `_ekranBekliyor` sorulup çıkılıyordu ve geriye tek bir anlık bump
    // kalıyordu; oysa `purchaseWaitingLong` metni kullanıcıya "bu ekranı
    // kapatsan da satın alman kaybolmaz" diye söz veriyor ve o sözü tutan şey
    // tam olarak bu merdiven. Ekran kapandığı anda kendi yoklaması ölüyor
    // (sökülmüş `WidgetRef`; `tazele()` fırlatıyor — ölçüldü: `StateError:
    // Using "ref" when a widget is about to or has been unmounted is unsafe`
    // — ve `sunucuyuYokla` orada kesiliyor, çünkü oradaki try/catch yalnız
    // `yakalandi()`yi sarıyor). O andan sonra geriye kalan TEK mekanizma bu.
    unawaited(Future<void>(() async {
      for (final gecikme in const [Duration(seconds: 1), Duration(seconds: 4)]) {
        await Future<void>.delayed(gecikme);
        if (sokuldu) return;
        // Ekranın penceresi adımı ATLAMAZ, ERTELER (gerekçe işlevin başında).
        if (!await _ekranBosalsin(() => sokuldu)) return;

        // Sunucu YAKALADIYSA merdiven durur.
        //
        // Bu erken çıkış bu turda ZORUNLU oldu: adım artık ekranı atlamak
        // yerine beklediği için, ekranın başarıyla bitirdiği her satın almada
        // merdiven uyanıp iki tazeleme daha koşturacaktı — yani onarım istek
        // sayısını ARTIRIRDI. Eskiden "yakaladım" bilgisi yoktu.
        //
        // Halka geri gelmiyor: [aboneAynasiProvider] hiçbir şeyi izlemeyen
        // sade bir `StateProvider` ve değeri `/billing/status` GÖVDESİNDEN
        // yazılıyor (`api.dart`, `_yanitiNotEt`). B10'un halkası
        // `subscriptionProvider`a uzanmaktan geliyordu; oraya uzanmak
        // gerekmedi.
        if (ref.read(aboneAynasiProvider) == true) return;

        sayaclariArtir();
      }
    }));
  }

  if (kurucu != null) {
    kurucu(geldi);
    return;
  }

  void yerliDinleyici(CustomerInfo bilgi) =>
      geldi(bilgi.entitlements.active.keys.toSet());
  Purchases.addCustomerInfoUpdateListener(yerliDinleyici);
  ref.onDispose(
      () => Purchases.removeCustomerInfoUpdateListener(yerliDinleyici));
});

/// Ekrandaki satın alma akışı şu an sunucuyu yokluyor mu?
///
/// Toplayıcı ile ekran aynı sayaçları artırıyor; ikisinin merdiveni üst üste
/// binerse istek sayısı ikiye katlanır ve depo tek bir 429 ile bir kez yandı
/// (KL-turu). Modül düzeyinde tutuluyor çünkü soruyu soran (toplayıcı) ile
/// cevabı bilen (satın alma işlevi) aynı kütüphanede ama farklı `ref`lerde
/// yaşıyor.
bool _ekranBekliyor = false;

/// [_ekranBosalsin] iki yoklaması arasındaki ara.
const Duration _kEkranYoklamaAdimi = Duration(seconds: 1);

/// Ekranın yoklama penceresi kapanana kadar bekler. `true` = ekran boşaldı.
///
/// Merdiven adımının ekranı ATLAMASI yetmiyordu — sayılar tutmuyor: ekranın
/// bütçesi 15 saniye ([_kBeklemeButcesi]), merdivenin iki adımı ise +1 ve +5.
/// saniyede. Kullanıcı 10. saniyede ekranı kapatırsa atlanan iki adım da
/// çoktan tükenmiş olur; merdiven "yaşıyor" görünür ama elde HİÇBİR ŞEY
/// bırakmaz. Bu yüzden adım harcanmıyor, ERTELENİYOR.
///
/// Tavan ekranın kendi sınırlarından türetiliyor (bütçe + tek yoklamanın üst
/// sınırı), elle yazılmış bir sabit değil: o sınırlar değişirse burası
/// kendiliğinden uyar, yoksa sessizce kısa kalırdı. Tavan dolduğu hâlde ekran
/// hâlâ yokluyorsa işi O yapıyor demektir ve `false` dönülür — istek sayısını
/// ikiye katlamanın karşılığı yok.
///
/// [vazgec] sağlayıcı söküldüğünde `true` döner: bekleyiş o anda kesilmeli,
/// yoksa sökülmüş kapsamda `ref.read` fırlatır.
Future<bool> _ekranBosalsin(bool Function() vazgec) async {
  var kalan = _kBeklemeButcesi + _kYoklamaSiniri;
  while (_ekranBekliyor && kalan > Duration.zero) {
    await Future<void>.delayed(_kEkranYoklamaAdimi);
    if (vazgec()) return false;
    kalan -= _kEkranYoklamaAdimi;
  }
  return !_ekranBekliyor;
}

/// Ekranın yoklama penceresini AÇIP KAPATAN sarmalayıcı — TEST DİKİŞİ de bu.
///
/// Dikiş gerekli: [_ekranBekliyor] kütüphaneye özel ve onu açan tek yol
/// `Purchases` gerektiren satın alma yolundan geçiyordu. Yani "ekran
/// yokluyorken toplayıcının merdiveni ne yapıyor" sorusu hiçbir testte
/// SORULAMIYORDU — bu turda onarılan kusur tam orada yaşıyordu.
///
/// `finally` şart: bayrak açık kalırsa toplayıcının merdiveni oturumun
/// kalanında her adımda tavan dolana kadar bekler ve hiç tazelemez.
Future<T> ekranYoklarken<T>(Future<T> Function() yoklama) async {
  _ekranBekliyor = true;
  try {
    return await yoklama();
  } finally {
    _ekranBekliyor = false;
  }
}

/// Toplayıcıya "temeli KURULMUŞ say" diyen kanca.
///
/// Toplayıcının temeli ([yetkiToplayiciProvider] içindeki `onceki`) bir
/// kapanışta yaşıyor; ona dışarıdan ulaşmanın tek yolu bu. [_ekranBekliyor]
/// ile aynı gerekçeyle modül düzeyinde.
void Function()? _toplayiciTemeliniKur;

/// Satın alma/geri yükleme BAŞLIYOR: bundan sonra gelen yetki bildirimi
/// HABERDİR, temel değil.
///
/// Toplayıcı ilk bildirimi temel sayıp yutuyor ve gerekçesi geçerli (bkz.
/// [yetkiToplayiciProvider]); deliği ise süreçte hiç `CustomerInfoUpdated`
/// olmamış olması: o hâlde satın almanın ürettiği olay İLK olay olur ve
/// yutulur — sayaç artmaz, merdiven kurulmaz.
///
/// [ensureBillingIdentity]'nin `logIn` çağrısı temeli kurmaya YETMEZ: kimlik
/// zaten bağlıysa (`mevcut != uid` yanlış) o çağrı hiç yapılmaz. Deliğin
/// "pratikte kapalı" sayılması bu yüzden yanlıştı.
///
/// Niçin [ensureBillingIdentity]'nin İÇİNDE değil: onu jeton paketi yolu da
/// çağırıyor (`wallet.dart`), oysa jeton alımı yetkiyi değiştirmez. Temeli
/// orada da boş kurmak, abonenin jeton alımında gelen `{Plus}` bildirimini
/// "yetki KAZANILDI" gibi gösterip üç adımlık merdiveni boşa koştururdu.
void yetkiTemeliniKurulmusSay() => _toplayiciTemeliniKur?.call();

/// `/billing/status` okumasi — saglayicidan AYRI tutuluyor, cunku bekcisi
/// sahte bir Firebase `User`i olmadan yazilamaz (ilkacilis-2).
Future<SubscriptionStatus> abonelikDurumunuOku(Dio dio) async {
  // TEK bir yeniden deneme, ve yalnız HIZLI düşen hatada.
  //
  // Gerekçe ölçüldü: `bilinmiyor` hâli TERMİNAL'di. Aşağıdaki geniş yakalama
  // bir `AsyncData` üretiyor — yani Riverpod için hata DEĞİL, dolayısıyla
  // kendiliğinden hiç yenilenmiyor. Tek bir 429/zaman aşımı, yedi yüzeyi
  // (Gökyüzü kişisel kart, BaZi, İ Ching, Doğum Heksagramı, İç Takvim, Yıl
  // Haritası, Atlas'ın dört karosu) OTURUM BOYUNCA iskelette bırakıyordu.
  // İskelet "veri geliyor" der; hiçbir istek yolda değildir — kilit
  // kartından farklı ama aynı sınıf bir yalan, üstelik çıkışı yok.
  //
  // Niçin Riverpod'un kendi retry'ı DEĞİL: varsayılan retry sağlayıcı başına
  // 11 isteğe çıkıyor ve tek bir 429'u kotanın kendisini besleyen bir
  // sağanağa çeviriyor (ölçüldü, ayrı bir turda onarıldı). Burada tavan
  // ikinci istekte sabit.
  //
  // Niçin yalnız HIZLI hatada: ilk deneme zaman aşımıyla düştüyse sunucu
  // gerçekten ulaşılamaz demektir ve ikinci deneme bir zaman aşımını daha
  // ÜST ÜSTE bindirir — ilk çizimi saniyelerce geciktirirdi. 429/5xx/bağlantı
  // reddi ise milisaniyelerde döner; onarılabilecek tek sınıf da bu.
  const hizliEsik = Duration(seconds: 3);
  final saat = Stopwatch()..start();
  for (var deneme = 0; deneme < 2; deneme++) {
    try {
      final response = await dio.get('/api/v1/billing/status');
      return SubscriptionStatus.fromJson(
          Map<String, dynamic>.from(response.data));
    } catch (_) {
      // Durum okunamadıysa ücretsiz varsay; sunucu zaten uçları koruyor.
      //
      // Yakalama BİLEREK geniş (`on DioException` değil): bu sağlayıcı hata
      // durumuna DÜŞMEMELİ. Riverpod hatalı bir sağlayıcıyı yeniden deniyor
      // ve `.future` o süre boyunca tamamlanmıyor; satın alma sonrası
      // yoklama da orada asılı kalıyordu.
      //
      // Ama "ucretsiz varsay" artik SESSIZ degil: bayrak duser, boylece
      // kullaniciya bir sey SOYLEYEN kararlar bu acilista susar.
      if (deneme > 0 || saat.elapsed > hizliEsik) {
        return SubscriptionStatus.bilinmiyor;
      }
      await Future<void>.delayed(const Duration(milliseconds: 600));
    }
  }
  return SubscriptionStatus.bilinmiyor;
}

/// Sunucunun SON söylediği "bu kullanıcı Plus mı" cevabı — interceptor'ın
/// okuyabildiği TEK kopya (bulgu B10).
///
/// [subscriptionProvider] bu soruyu zaten cevaplıyor ama `apiProvider`'ın
/// interceptor'ından OKUNAMAZ: gövdesinde `ref.watch(apiProvider)` var ve
/// interceptor `apiProvider`'ın kendi ref'ini taşıyor, yani
/// `ref.read(subscriptionProvider.future)` çalışma anında
/// `CircularDependencyError` fırlatır (ölçüldü). Bu ayna hiçbir şeyi izlemez;
/// değeri `/billing/status` YANITINDAN, yani sunucunun kendi gövdesinden gelir
/// — istemci tahmininden değil.
///
/// Değer sunucudaki `is_subscriber` ile BİREBİR aynı (bkz. `api/billing.py`
/// `status`: `active=entitlements.is_subscriber(...)`), yani deneme dönemi de
/// `true`. Kişi kontenjanı kararında sunucunun kullandığı yüklem de o; iki
/// taraf aynı soruya aynı cevabı veriyor.
///
/// `null` = bu oturumda durum HİÇ okunamadı ve bu "abone değil" ile aynı şey
/// DEĞİL ([SubscriptionStatus.okunabildi] ile aynı gerekçe): kullanıcıya bir
/// şey SÖYLEYEN karar, bilmediğini bilmelidir.
final aboneAynasiProvider = StateProvider<bool?>((_) => null);

/// Yanıt `/billing/status` ucundan mı geliyor?
bool abonelikDurumuYaniti(RequestOptions istek) =>
    Uri.parse(istek.path).path == '/api/v1/billing/status';

/// `/billing/status` gövdesinden ayna değeri; gövde beklenen şekilde değilse
/// `null` döner ve o hâlde ayna DEĞİŞTİRİLMEZ.
///
/// Alan eksikse `false` DÖNMEZ: yarım ya da bozuk bir gövde "abone değil"
/// demek değil, "bilmiyorum" demektir. Sunucu bu alanı her yanıtta gönderiyor
/// (pydantic modeli zorunlu kılıyor), yani `null` gerçekten beklenmeyen bir
/// durumdur.
bool? aynadakiAbonelik(Object? govde) {
  if (govde is! Map) return null;
  if (!govde.containsKey('active')) return null;
  return govde['active'] == true;
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

/// Satın almanın NEREDE bittiği — üç hâl, çünkü ikisi aynı şey değil.
///
/// Eskiden dönen değer `bool`du ve "sunucu gördü" ile "sunucu henüz görmedi"
/// AYNI `true`ya iniyordu. Karar doğruydu (kullanıcıyı ödeme ekranına geri
/// göndermiyoruz) ama kullanıcıya söylenen cümle yoktu: kutlama perdesi
/// iniyor, ekran kapanıyor ve bakiye birkaç saniye bayat kalıyordu. Ayrım
/// **ölçülen bir şeyi doğru adla sunmak** için var.
enum SatinAlmaSonucu {
  /// Mağaza işi bitirdi ama beklenen yetki müşteri kaydında YOK — tipik
  /// nedeni panelde ürünün yanlış/eksik entitlement'a bağlanması.
  yetkiYok,

  /// Sunucu da gördü: her şey yerinde.
  sunucuOnayladi,

  /// Ödeme cihazda tamam, sunucu bütçe dolana kadar yetkiyi görmedi.
  sunucuGecikti,
}

/// Satın alma işlevi — TEST DİKİŞİ.
///
/// Dikiş [teklifGetiriciProvider] ile aynı gerekçeyle var: `Purchases`
/// eklentisi `flutter test` içinde çağrılamaz, yani gerçek yol hiçbir testte
/// koşmuyor. Ölçülmek istenen şey satın almanın kendisi DEĞİL, **mağaza
/// cevap vermezken ekranın hâli**: geri tuşu kapalı mı, düğme yeniden
/// basılabilir hale geliyor mu. Dikişsiz hâlde `_busy` hiçbir testte ayakta
/// tutulamıyor ve bu turun en pahalı iki kusuru ölçülemez kalıyordu.
typedef PaketSatinAlici = Future<SatinAlmaSonucu> Function(
    WidgetRef ref, Package paket);

/// `null` = üretim yolu ([purchasePackage]).
final paketSatinAliciProvider = Provider<PaketSatinAlici?>((_) => null);

/// Satın alma. Başarılıysa sunucu yetkiyi görene kadar bekler.
///
/// Yetki sunucuya **webhook üzerinden** işleniyor: satın almanın bitmesiyle
/// `/billing/status` uçlarının "aktif" demesi arasında saniyeler olabilir.
/// Tek seferlik `invalidate` bu yarışı kaybediyordu — kullanıcı ödeme yapıyor,
/// ekran kapanıyor, kilitli içeriğe dokunuyor ve sunucu henüz haberdar
/// olmadığı için 402 dönüp paywall yeniden açılıyordu.
///
/// Bu yüzden durum kısa aralıklarla birkaç kez okunur. Süre dolarsa yine de
/// başarı bildirilir ([SatinAlmaSonucu.sunucuGecikti]): satın alma cihazda
/// gerçekleşti, gecikme sunucu tarafındadır ve kullanıcıyı ödeme ekranına
/// geri göndermek yanlış olur.
Future<SatinAlmaSonucu> purchasePackage(WidgetRef ref, Package package) async {
  await ensureBillingIdentity();
  // Mağaza penceresi açılmadan ÖNCE: satın almanın ürettiği bildirim
  // toplayıcıda "ilk bildirim" sayılıp yutulmasın (gerekçe kancanın başında).
  yetkiTemeliniKurulmusSay();
  final result = await Purchases.purchase(PurchaseParams.package(package));
  final active =
      result.customerInfo.entitlements.active.containsKey(kPlusEntitlement);
  if (!active) return SatinAlmaSonucu.yetkiYok;

  return await _waitForServerEntitlement(ref)
      ? SatinAlmaSonucu.sunucuOnayladi
      : SatinAlmaSonucu.sunucuGecikti;
}

/// Tek bir durum yoklamasının üst sınırı.
///
/// Dio'nun alım zaman aşımı 120 saniye; sınırsız bırakılırsa beş yoklama en
/// kötü hâlde on dakika sürebiliyordu. Kullanıcının gördüğü şey "ödeme
/// adımını geçemiyorum" oluyor.
const Duration _kYoklamaSiniri = Duration(seconds: 6);

/// Sunucuyu bekleme bütçesinin tamamı.
const Duration _kBeklemeButcesi = Duration(seconds: 15);

/// Sunucu beklenen durumu görene kadar SINIRLI bütçeyle yokla.
///
/// Ortak tutulmasının sebebi ölçüldü: bütçe bir dönem yalnız abonelikte
/// vardı, jeton paketi tarafına HİÇ taşınmamıştı ve orada en kötü hâlde beş
/// yoklama ~40 saniye sürüyordu. Üstelik o taraftaki yorum "abonelikteki
/// desenle aynı bütçe" diyordu — yani yorumun gerekçesi YANLIŞTI, oysa
/// gerekçesi yanlış bir yorum kusurdur. İki çağıran artık gerçekten aynı
/// kapıdan geçiyor.
///
/// Dönen değer **"sunucu yakaladı mı"**. Bütçe dolarsa `false` döner ama bu
/// bir hata DEĞİL: ödeme cihazda gerçekleşti ve kullanıcıyı ödeme ekranına
/// geri göndermek yanlış olur (bu karar bilinçli ve değişmedi). Değer yalnız
/// kullanıcıya DÜRÜST bir cümle söylenebilsin diye taşınıyor.
Future<bool> sunucuyuYokla({
  required void Function() tazele,
  required Future<bool> Function() yakalandi,
  Duration butce = _kBeklemeButcesi,
  Duration yoklamaSiniri = _kYoklamaSiniri,
}) async {
  const gecikmeler = [
    Duration(milliseconds: 400),
    Duration(seconds: 1),
    Duration(seconds: 2),
    Duration(seconds: 3),
    Duration(seconds: 4),
  ];
  final bitis = DateTime.now().add(butce);
  for (final gecikme in gecikmeler) {
    if (DateTime.now().isAfter(bitis)) break;
    tazele();
    try {
      if (await yakalandi().timeout(yoklamaSiniri)) return true;
    } catch (_) {
      // Yoklama düşerse beklemeyi sürdür; bu bir satın alma hatası değil.
    }
    await Future<void>.delayed(gecikme);
  }
  tazele();
  return false;
}

/// Sunucu aboneliği görene kadar bekler — `true` = sunucu gördü.
///
/// Bekleme sürerken [_ekranBekliyor] kalkıyor: kalıcı toplayıcı aynı
/// saniyelerde kendi merdiveninin adımını ERTELESİN (gerekçe o bayrağın ve
/// [_ekranBosalsin]'in başında). Pencere [ekranYoklarken] üzerinden açılıyor:
/// bayrağı elle açıp `finally` ile kapatmak aynı şeydi ama o hâlde testlerin
/// pencereye hiç erişimi olmuyordu.
Future<bool> _waitForServerEntitlement(WidgetRef ref) async {
  return ekranYoklarken(() async {
    final gordu = await sunucuyuYokla(
      tazele: () {
        ref.invalidate(subscriptionProvider);
        // Cüzdan da tazelenir: aylık jeton hakkını webhook aboneliğle AYNI
        // anda yazıyor; yalnız aboneliği yoklamak Abonelik ekranının bayat
        // "0 / aylık hak" göstermesine yol açıyordu (iç test bulgusu — "ilk
        // alımda kredi sıfır"). Hakkın SAYISI burada yazılmıyor: o sunucunun
        // gerçeği ve dönem başına değişebiliyor.
        ref.invalidate(walletProvider);
      },
      yakalandi: () async =>
          (await ref.read(subscriptionProvider.future)).active,
    );
    // Yetki görüldüğü tur, cüzdan okuması hak yazılmadan ÖNCE başlamış
    // olabilir; son bir tazeleme o yarışı kapatıyor (eski davranış korundu).
    if (gordu) ref.invalidate(walletProvider);
    return gordu;
  });
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
  // Satın alma yolundaki gerekçenin aynısı: geri yükleme de yetki KAZANDIRIR
  // ve o bildirim süreçteki ilk bildirim olabilir.
  yetkiTemeliniKurulmusSay();
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
