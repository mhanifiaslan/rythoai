import 'dart:async' show unawaited;

import 'package:dio/dio.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'
    show SystemChrome, SystemUiMode, SystemUiOverlayStyle;
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart' show GoogleFonts;
import 'package:google_sign_in/google_sign_in.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'core/abonelik_kurtarma.dart';
import 'core/api.dart';
import 'core/app_check_izi.dart';
import 'core/app_config.dart';
import 'core/auth_service.dart' show signOutEverywhere;
import 'core/deep_links.dart';
import 'core/device_id.dart' show iosYenidenKurulumOturumunuKapat;
import 'core/device_session.dart' show deviceConflictProvider;
import 'core/gate_guard.dart';
import 'core/gun_donumu.dart';
import 'core/language_sync.dart';
import 'core/locale.dart';
import 'core/notifications.dart';
import 'core/providers.dart';
import 'core/subscription.dart';
import 'features/auth/device_conflict_screen.dart';
import 'features/auth/force_update_screen.dart';
import 'features/auth/login_screen.dart';
import 'features/onboarding/onboarding_wizard.dart';
import 'features/shell/app_shell.dart';
import 'l10n/app_localizations.dart';
import 'theme/rytho_theme.dart';
import 'theme/rytho_tokens.dart';
import 'widgets/atlas_widgets.dart';
import 'widgets/cosmic_scaffold.dart';
import 'widgets/motion.dart';

/// Sağlayıcı yeniden deneme politikası.
///
/// Riverpod 3'ün VARSAYILANI her hatayı 10 kez, üstel bekleyerek (200ms →
/// 6,4sn) yeniden dener. Bu, sunucu kotası (429) devreye girdiğinde kotayı
/// kendi kendini besleyen bir döngüye çeviriyordu: tek 429, sağlayıcı
/// başına ~11 isteğe; canlıdaki yedi sağlayıcı ~77 isteğe çıkıyor ve
/// pencere hiç boşalmadığı için tek çıkış yolu uygulamayı öldürmek
/// oluyordu. Kullanıcının "az kullanmama rağmen yoğun talep diyor"
/// bulgusunun istemci yarısı buydu.
///
/// Kural: 4xx **istemci** hatasıdır — yeniden denemek durumu değiştirmez
/// (402 paywall, 403 yetki, 429 kota, 404 yok). Yalnız geçici olabilecek
/// hatalar (ağ kopması, zaman aşımı, 5xx) sınırlı sayıda denenir.
Duration? rythoRetry(int retryCount, Object error) {
  if (error is DioException) {
    final kod = error.response?.statusCode;
    if (kod != null && kod >= 400 && kod < 500) return null;
  }
  // Yedek metin (gz-2) AG hatasi degil: sunucu 200 dondu, uretim dustu.
  // Otomatik yeniden deneme burada tam olarak yukarida anlatilan, kotayi
  // besleyen dongunun aynisini kurar (ustelik her deneme bir jeton dus/iade
  // turu); karari kullanici verir — ekranlarda "tekrar dene" var.
  if (error is RaporUretilemedi) return null;
  if (retryCount >= 2) return null;
  return Duration(milliseconds: 400 * (retryCount + 1));
}

/// Sistem yazı ölçeğinin uygulanan tavanı (bkz. [RythoApp.build] `builder`).
///
/// Arayüz sabit puntolar üzerine kurulu (`RythoText`); %130'un üstünde kart
/// başlıkları ve iki sütunlu satırlar dar ekranda yerleşimi bozuyor. Tavan
/// yalnız üst uçtadır; küçültme serbesttir.
const double kMaxTextScale = 1.3;

/// Web client id (google-services.json / client_type 3) — Google Sign-In için.
const kServerClientId =
    '770582338651-0kimgrjfj4brfl6k5h3g6amn2rm7ue6a.apps.googleusercontent.com';

/// iOS debug derlemesinin App Check jetonu (`APP_CHECK_DEBUG_TOKEN`,
/// `dart_defines.local.json`; git'te YOK). Boşsa SDK kendi jetonunu üretir.
/// Jeton Firebase'de kayıtlıyken App Check'i aşar — o yüzden sırdır: depoya,
/// sohbete ya da günlüğe yazılmaz.
const kAppCheckDebugToken = String.fromEnvironment('APP_CHECK_DEBUG_TOKEN');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Yazı tipleri PAKETTE; ağdan çekme KAPALI.
  //
  // NEDEN: üç aile yalnız GoogleFonts.* ile kullanılıyordu → ilk açılışta
  // fonts.gstatic.com'a istek (gizlilik etiketinde yazmayan bir Google
  // çağrısı), ağsız açılışta yedek fontla çizim ve bir sonraki karede
  // metin flaşı. Dosyalar pubspec'te (tools/font_paketi_uret.py üretir).
  // Bu bayrak kapalıyken eksik bir ağırlık SESSİZCE ağa düşmez, FIRLATIR —
  // iyi: sessiz bir sapma yerine testte görünen bir hata
  // (test/font_paketi_test.dart her (aile, ağırlık) dosyasını bağlıyor).
  GoogleFonts.config.allowRuntimeFetching = false;

  // UÇTAN UCA (edge-to-edge) — AÇIKÇA ve HER Android sürümünde.
  //
  // NEDEN: targetSdk 36 (Flutter 3.44 varsayılanı); Android 15+ bunu zaten
  // ZORLUYOR ve Play "uçtan uca ekran tüm kullanıcılara gösterilmeyebilir"
  // uyarısı veriyor (2026-10-10). Ölçüldü: dock alt inset'i okuyor
  // (glass.dart:207-254), AppBar üst inset'i Scaffold'dan alıyor, ekranlar
  // SafeArea kullanıyor — yani içerik çubukların altında KALMIYOR. Eksik
  // olan şey davranışın sürüme göre DEĞİŞMESİYDİ: Android 15+'ta uçtan uca,
  // altında değil. Tek yol olsun ki cihaz testi tek davranışı ölçsün.
  // Çubuklar saydam, ikonlar açık renk (zemin gece); nav çubuğuna kontrast
  // zemini dayatılmıyor (dock zaten cam).
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: Colors.transparent,
    systemNavigationBarIconBrightness: Brightness.light,
    systemNavigationBarContrastEnforced: false,
  ));

  await Firebase.initializeApp();

  // App Check — İSTEĞİN GERÇEK UYGULAMADAN GELDİĞİNİ KANITLAR.
  //
  // Neden var (2026-09-15, canlıda ölçüldü): Firebase Auth ucu internete
  // açıktır ve API anahtarı gizli değildir; üstelik Android anahtarını
  // paket + SHA-1 ile kısıtlamak burada ZAYIF kalır, çünkü SHA-1
  // parmak izimiz App Links için `/.well-known/assetlinks.json` ile
  // zaten yayında. Bir bot çiftliği bunu kullanıp uygulamayı hiç
  // kurmadan 39 hesap açtı (hiçbirinin profili yok: sunucumuza tek
  // istek bile gelmemiş, doğrudan Google'ın kimlik ucuna vurulmuş).
  //
  // Play Integrity, isteği CİHAZIN kendisine bağlar; kopyalanabilir bir
  // sır değildir. Kapatılması gereken açık buydu.
  //
  // ⚠️ Bu çağrı token ÜRETİR, zorunlu kılmaz. Zorlama konsoldan açılır
  // (Firebase Console → App Check → API'ler). Sıra bilinçli: önce bu
  // sürüm yayılır, sonra zorlama açılır. Ters sırada eski paketler
  // kilitlenirdi.
  //
  // Debug derlemelerinde Play Integrity çalışmaz; debug sağlayıcı
  // kullanılır ve konsola bir debug token düşer (bir kez Firebase
  // Console → App Check → Manage debug tokens'a eklenir).
  //
  // Hata YUTULUR: App Check kurulamazsa uygulama açılmaya devam
  // etmeli. Zorlama kapalıyken zaten bir etkisi yok; açıkken de
  // kullanıcıyı kapıda bırakmak yerine sunucunun karar vermesi doğru.
  // Yutulan hata yayında Crashlytics'e iz bırakır (U30,
  // core/app_check_izi.dart).
  try {
    await FirebaseAppCheck.instance.activate(
      providerAndroid: kDebugMode
          ? const AndroidDebugProvider()
          : const AndroidPlayIntegrityProvider(),
      // Apple tarafı SESSİZCE varsayılana düşüyordu. `providerApple`
      // verilmezse paket `AppleDeviceCheckProvider()` kullanıyor
      // (firebase_app_check 0.4.5+2, firebase_app_check.dart:110) — App
      // Attest'ten zayıf bir kanıt. Zorlama 2026-09-26'da Firestore,
      // identitytoolkit ve Storage için AÇILDI, yani yanlış sağlayıcıyla
      // çıkan bir iOS paketi sunucuya hiç bağlanamaz ve bu ancak cihazda
      // görülür (yayın dalının bekçisi test/app_check_izi_test.dart).
      //
      // Fallback'li varyanta gerek yok: App Attest iOS 14+ ister, taban
      // 15.5 (ios/Podfile). Simülatörde App Attest çalışmaz, debug
      // sağlayıcı o boşluğu kapatıyor — Android'deki desenin aynısı.
      // Yedekli varyant da yalnız iOS SÜRÜMÜNE bakıyor (eklentinin
      // FirebaseAppCheckPlugin.swift'i), `isSupported`'a değil: Apple'a
      // göre Mac'te (Apple silicon'da çalışan iOS uygulaması dahil) App
      // Attest yok ve yedek bunu kurtarmaz. O boşluğun çaresi Mac
      // erişimi kararı (docs/ios-uyum-denetimi.md U53).
      //
      // Debug jetonu SABİT verilir (varsa): verilmezse SDK her kurulumda
      // yeni bir jeton üretiyor ve Firebase'e her seferinde yeniden
      // eklenmesi gerekiyordu — kayıtsız jeton `exchangeDebugToken` 403
      // ("App attestation failed") alır ve giriş "Bir şeyler ters gitti"
      // diye düşer (2026-10-24, simülatörde ölçüldü). Değer git'e girmeyen
      // `dart_defines.local.json`'dan gelir ve yalnız bu dalda okunur:
      // imzasız Release paketinde 0 kez geçtiği ölçüldü (2026-10-24) ve
      // `infra/build-ipa.sh` paket kapısı her yayın paketinde yeniden
      // ölçer — aynı define dosyası yayın derlemesine de veriliyor.
      providerApple: kDebugMode
          ? AppleDebugProvider(
              debugToken:
                  kAppCheckDebugToken.isEmpty ? null : kAppCheckDebugToken)
          : const AppleAppAttestProvider(),
    );
    // iOS'ta App Attest arızası ancak jeton alınırken görünür; açılış onu
    // BEKLEMEZ (gerekçe: core/app_check_izi.dart).
    if (appCheckYoklamasiYapilir()) {
      unawaited(appCheckJetonunuYokla(FirebaseAppCheck.instance.getToken));
    }
  } catch (e, iz) {
    appCheckEtkinlestirmeHatasi(e, iz);
  }

  // Crashlytics: yalnızca gerçek cihaz/release akışında etkin;
  // debug oturumları ve web rapor kirliliği yaratmasın.
  if (!kIsWeb && !kDebugMode) {
    FlutterError.onError =
        FirebaseCrashlytics.instance.recordFlutterFatalError;
    PlatformDispatcher.instance.onError = (error, stack) {
      FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
      return true;
    };
  }

  // TÜM diller yüklenir. Eskiden yalnız `'tr_TR'` yükleniyordu ve bu sessiz
  // bir hataydı: `DateFormat('MMM', 'en')` İngilizce sembol verisini
  // bulamayınca yüklü olan tek dile düşüyor, arayüz İngilizce olsa bile
  // tarihler Türkçe basılıyordu ("Ağu 27" / "Eyl 2"). Cihaz turunda
  // "kartlar İngilizceye çevirince de Türkçe kalıyor" diye görüldü.
  await initializeDateFormatting();
  try {
    await GoogleSignIn.instance.initialize(serverClientId: kServerClientId);
  } catch (_) {
    // Web'de serverClientId gerekmez; sessizce geç.
  }
  // Abonelik SDK'sı İKİ hâlde sessizce atlanır: bu platformun anahtarı
  // tanımlı değilse, ya da yayın derlemesinde (Release/Profile) anahtar
  // `test_` önekliyse — RevenueCat yayında Test Store anahtarını görünce
  // BİLEREK çöküyor (iOS kaynağından ölçüldü; Android SDK'sı ölçülmedi),
  // yani `configure` hiç çağrılmamalı. Karar tek yerde
  // (`subscription.dart` `rcEtkinAnahtar`); uygulama ücretsiz katmanla
  // normal çalışır, satın alma yolları "kullanılamıyor" der.
  await initBilling();

  // U45: iOS anahtar zinciri oturumu yeniden kurulumdan sağ çıkarıyor;
  // `_Gate` onu görmeden kapatılmalı (gerekçe fonksiyonda). Android'de
  // hiçbir şeye dokunmaz.
  await iosYenidenKurulumOturumunuKapat(
    oturumVar: () => FirebaseAuth.instance.currentUser != null,
    cikis: () => FirebaseAuth.instance.signOut(),
  );

  runApp(ProviderScope(retry: rythoRetry, child: const RythoApp()));
}

class RythoApp extends ConsumerWidget {
  const RythoApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Dil hem arayüzü hem backend'in ürettiği yorumları belirler; ikincisini
    // apiProvider aynı sağlayıcıyı izleyerek yapar (bkz. core/api.dart).
    final locale = ref.watch(localeProvider);

    // OT2: Firebase'in e-postaları (şifre sıfırlama, adres doğrulama)
    // şablon dilini BURADAN alır — hiç çağrılmadığı için Türk kullanıcıya
    // İngilizce "Reset your password" gidiyor ve spam sanılıyordu.
    // Çağrı ucuz ve idempotent; dil değişince kendiliğinden güncellenir.
    // GEÇERLİ dil (tercih yoksa sistem dili) — `SystemLocaleObserver`
    // sayesinde "Sistem" tercihinde telefon dili değişince de güncellenir.
    unawaited(FirebaseAuth.instance.setLanguageCode(
        ref.watch(effectiveLocaleProvider.select((l) => l.languageCode))));

    return SystemLocaleObserver(
      // Ön plana dönüşte yerel GÜNÜN değişip değişmediğine bakılır: günlük
      // sağlayıcılar (günlük okuma, BaZi, Doğum Heksagramı) düz
      // `FutureProvider` olduğu için sonuçları oturum boyunca önbellekte
      // kalıyor ve gün dönümünde dünkü metin ekranda duruyordu
      // (bkz. core/gun_donumu.dart). Gözcü `MaterialApp`ın ÜSTÜNDE:
      // kancanın yaşaması için ağacın bu oturum boyunca yaşayan bir
      // katmanında olması gerekiyor, aşağıdaki rotalar basılıp sökülüyor.
      child: GunDonumuGozcusu(
        // Ön plana dönüşte, OKUNAMAMIŞ abonelik durumu yeniden sorulur:
        // `bilinmiyor` hâli terminaldi ve yedi yüzeyi oturum boyunca
        // iskelette bırakıyordu (bkz. core/abonelik_kurtarma.dart).
        child: AbonelikKurtarmaGozcusu(
          // Ön plana dönüşte zorunlu güncelleme eşiği yeniden okunur
          // (bkz. core/app_config.dart).
          child: UpdateGateObserver(
            // Kapı kapanınca (426/409) yığın köke iner: kapı ekranı `_Gate`'in
            // alt ağacında yaşar, basılı bir rotanın altında kalmasın (bkz.
            // core/gate_guard.dart).
            child: GateRootGuard(
              navigatorKey: rythoNavigatorKey,
              child: MaterialApp(
                title: 'Rytho',
                debugShowCheckedModeBanner: false,
                theme: buildRythoTheme(),
                // Sunucu 402 döndüğünde paywall'ı hangi ekranda olursak olalım
                // açabilmek için (bkz. core/api.dart).
                navigatorKey: rythoNavigatorKey,
                locale: locale,
                supportedLocales: kSupportedLocales,
                localizationsDelegates: AppLocalizations.localizationsDelegates,
                // Yazı ölçeği tavanı (cihaz bulgusu): sistem yazı boyutu çok
                // büyükken uzun başlık cümleleri dar ekranda satıra sığmıyor ve
                // sağ taraf kırpılıyordu. Yerleşimler esnetildi (Wrap/Flexible)
                // ama tipografi sabit punto üzerine kurulu: %130 üstü ölçekte
                // kart mimarisi dağılıyor. Tavan yalnız ÜST uçta — kullanıcı
                // yazıyı küçültmek isterse (0,85) ona dokunulmaz.
                builder: (context, child) {
                  final mq = MediaQuery.of(context);
                  final olcek = mq.textScaler.clamp(maxScaleFactor: kMaxTextScale);
                  return MediaQuery(
                    data: mq.copyWith(textScaler: olcek),
                    child: child ?? const SizedBox.shrink(),
                  );
                },
                home: const _Gate(),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Oturum + onboarding durumuna göre yönlendirme.
class _Gate extends ConsumerWidget {
  const _Gate();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // RevenueCat kimliğini Firebase oturumuna bağlar. İzlenmezse sağlayıcı
    // hiç kurulmaz ve satın almalar anonim kimliğe yazılır (bkz.
    // core/subscription.dart).
    ref.watch(billingIdentityProvider);
    // Bildirim altyapısı: FCM token, saat dilimi ve dil sunucuya yazılır,
    // bildirime dokunma yönlendirmesi kurulur (bkz. core/notifications.dart).
    ref.watch(notificationSyncProvider);
    // Bildirim dili: profildeki `language` alanının tek yazıcısı, geçerli
    // dili izler (bkz. core/language_sync.dart).
    ref.watch(languageSyncListenerProvider);
    // Davet bağlantılarını yakalar (bkz. core/deep_links.dart).
    ref.watch(deepLinkProvider);

    // Zorunlu güncelleme kapısı (F3 → PBZ): sunucu bu derlemeyi asgari
    // sürümün altında ilan ettiyse giriş/onboarding/kabuğa hiç girilmez.
    // İki kaynak: açılış okuması (sunucuya ulaşılamazsa son bilinen eşik)
    // ve açık oturumda herhangi bir isteğe dönen 426. Yanıt beklenmez —
    // splash gecikmesi yok; yalnız kesin "kilitle" kapıyı kapatır.
    if (ref.watch(mustForceUpdateProvider)) {
      return const ForceUpdateScreen();
    }

    // `AppLocalizations.of` burada GUVENLI: `_Gate`, MaterialApp'in `home`'u
    // ve temsilci agacin ustunde kurulu (l10n.yaml: nullable-getter false).
    // widgets/common.dart'taki nullable arama oraya ozgu — o kart l10n'siz
    // agaclarda da ciziliyor; burada oyle bir durum yok.
    final l10n = AppLocalizations.of(context);

    // Hata dalinin ortak govdesi: cevrilmis metin + cikis yolu.
    //
    // Ham `'$e'` basmak depoda `friendlyError` ile kapatilmis bir kusur
    // sinifiydi (bkz. core/api.dart) ama bu iki dal kacmisti: testci ilk
    // acilisin tam ortasinda `[cloud_firestore/permission-denied] ...` gibi
    // cevrilmemis bir Dart istisnasi goruyordu. Sebep hala gerekli, ama
    // yalniz hata ayiklama derlemesinde.
    Widget hataSahnesi(Object hata, VoidCallback tekrarDene,
        {bool oturumAcik = false}) {
      assert(() {
        debugPrint('[RYTHO-GATE] hata dali: $hata');
        return true;
      }());
      return SplashScene(
        message: friendlyError(hata, l10n),
        onRetry: tekrarDene,
        // Hata oturumun kendisinden geliyorsa (iptal edilmis jeton, kural
        // degisimi) tekrar denemek durumu degistirmez; kok rotada geri tusu
        // da cikis vermiyor — tek gercek kapi budur.
        onSignOut: oturumAcik ? () => signOutEverywhere() : null,
      );
    }

    final auth = ref.watch(authStateProvider);
    final ekran = auth.when(
      loading: () => const SplashScene(),
      // Kimlik dali: oturum sahibi BILINMIYOR, o yuzden cikis sunulmaz.
      error: (e, _) => hataSahnesi(e, () => ref.invalidate(authStateProvider)),
      data: (user) {
        if (user == null) return const LoginScreen();
        // Tek cihaz kilidi kapısı (TC-turu K6): bu oturumun bir isteği 409
        // aldıysa onboarding/kabuk yerine çakışma ekranı — zorunlu
        // güncelleme kapısıyla aynı desen. Oturum AÇIK kalır ki "Bu cihazda
        // kullan" kimlikli gidebilsin; navigator yığınına basılmaz, diyalog
        // üstüne diyalog binmez (bkz. core/device_session.dart). Üstte
        // basılı rota varsa `GateRootGuard` yığını köke indirir.
        if (ref.watch(deviceConflictProvider) != null) {
          return const DeviceConflictScreen();
        }
        final profile = ref.watch(profileProvider);
        return profile.when(
          loading: () => const SplashScene(),
          // Profil akisi Firestore snapshot'i: `permission-denied` burada
          // duser ve oturum ACIK oldugu icin cikis da sunulur.
          error: (e, _) => hataSahnesi(e, () => ref.invalidate(profileProvider),
              oturumAcik: true),
          data: (data) {
            if (data == null || data['onboardingCompleted'] != true) {
              // Onboarding'e düşmek NADIR olmalı: yalnızca gerçekten yeni
              // kullanıcı. Cihaz testinde profili tam olan bir kullanıcıya
              // da açıldı ve sebebini ancak bu kararın girdisini görerek
              // bulabiliriz. Yalnızca hata ayıklama derlemesinde.
              assert(() {
                debugPrint('[RYTHO-GATE] onboarding acildi — '
                    'profilVar=${data != null} '
                    'alanlar=${data?.keys.toList() ?? "-"} '
                    'onboardingCompleted=${data?['onboardingCompleted']}');
                return true;
              }());
              return const OnboardingWizard();
            }
            return const AppShell();
          },
        );
      },
    );
    // Sert kesme yerine çapraz geçiş (R12-A1): splash → login/kabuk geçişi
    // eskiden tek karede oluyordu. Key EKRAN SINIFINA bağlı — _Gate her
    // yeniden build'inde yeni instance döner, key olmasa AnimatedSwitcher
    // aynı ekran için bile boşuna geçiş oynatırdı.
    return AnimatedSwitcher(
      duration: reduceMotion(context) ? Duration.zero : RythoMotion.slow,
      switchInCurve: RythoMotion.enter,
      child: KeyedSubtree(
        key: ValueKey(ekran.runtimeType),
        child: ekran,
      ),
    );
  }
}

/// Açılış sahnesi (R12-A1). Eski hâli çıplak spinner + statik "RYTHO"ydu —
/// uygulamanın ilk saniyesi markasızdı, logo yalnız giriş ekranındaydı.
/// Koreografi: logo belirir (600ms) → yazı, harf aralığı açılarak gelir
/// (mühür açılması) → usturlap süzülür. Splash zaten oturum çözülürken
/// görünüyor; sahne süre EKLEMEZ, var olan beklemeyi giydirir.
class SplashScene extends StatelessWidget {
  const SplashScene({super.key, this.message, this.onRetry, this.onSignOut});

  /// Gosterilecek metin — HAM istisna degil, `friendlyError` suzgecinden
  /// gecmis olan (bkz. core/api.dart).
  final String? message;

  /// "Tekrar dene": hataya dusen saglayiciyi yeniden kurar. Mesajli sahne bir
  /// KAPI oldugu icin en az bir eylem sunmak ZORUNDA (gz-8).
  final VoidCallback? onRetry;

  /// "Oturumu kapat": oturum kaynakli hatada tek cikis yolu.
  final VoidCallback? onSignOut;

  @override
  Widget build(BuildContext context) {
    final sabit = reduceMotion(context);
    final l10n = AppLocalizations.of(context);

    Widget logo = Image.asset('assets/brand/rytho_logo_512.png',
        width: 72, height: 72, filterQuality: FilterQuality.medium);
    Widget spinner = const AstrolabeSpinner(size: 36);
    if (!sabit) {
      logo = logo.animate().fadeIn(duration: RythoMotion.slower).scale(
          begin: const Offset(0.92, 0.92),
          end: const Offset(1, 1),
          duration: RythoMotion.slower,
          curve: RythoMotion.enter);
      spinner =
          spinner.animate(delay: 500.ms).fadeIn(duration: RythoMotion.slow);
    }

    return CosmicScaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            logo,
            const SizedBox(height: 18),
            _Wordmark(sabit: sabit),
            const SizedBox(height: 28),
            spinner,
            if (message != null) ...[
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Text(message!,
                   style: RythoText.body(13, color: RythoColors.parchmentDim),
                    textAlign: TextAlign.center),
              ),
              // Donen usturlap + hata metni, altinda hicbir eylem: testci
              // uygulamanin bozuldugunu dusunup ekran goruntusu aliyordu
              // (gz-8). Hiyerarsi DeviceConflictScreen ile ayni: birincil
              // GoldButton + sonuk TextButton.
              if (onRetry != null) ...[
                const SizedBox(height: RythoSpace.lg),
                GoldButton(text: l10n.retry, onPressed: onRetry),
              ],
              if (onSignOut != null)
                TextButton(
                  onPressed: onSignOut,
                  child: Text(l10n.signOut,
                      style:
                          RythoText.body(13, color: RythoColors.parchmentDim)),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

/// "RYTHO" yazısı: harf aralığı 2→5 açılarak belirir.
class _Wordmark extends StatelessWidget {
  const _Wordmark({required this.sabit});
  final bool sabit;

  @override
  Widget build(BuildContext context) {
    TextStyle stil(double aralik) => RythoText.label(16,
        color: RythoColors.gold).copyWith(letterSpacing: aralik);
    if (sabit) return Text(kMarkaAdi, style: stil(5));
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 800),
      // İlk çeyrek bekleme: logo önce gelir, yazı onu izler.
      curve: const Interval(0.25, 1, curve: RythoMotion.enter),
      builder: (_, t, _) => Opacity(
        opacity: t,
        child: Text(kMarkaAdi, style: stil(2 + 3 * t)),
      ),
    );
  }
}
