import 'dart:async' show TimeoutException;

import 'package:dio/dio.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart' show StateProvider;

import '../features/paywall/ozellik_katalogu.dart' show PlusOzellik;
import '../features/paywall/paywall_acilis.dart'
    show PaywallKaynak, acPaywall;
import '../features/paywall/token_store_screen.dart';
import '../l10n/app_localizations.dart';
import 'ai_consent.dart'
    show AiOnayiGerekli, aiOnayHatasiMi, aiOnayiSunucuIstedi;
import 'app_config.dart'
    show
        appBuildInterceptor,
        appBuildProvider,
        forceUpdateProvider,
        updateRequiredInterceptor;
import 'device_id.dart';
import 'device_session.dart'
    show
        deviceConflictInterceptor,
        deviceConflictProvider,
        devicePlatform,
        kDevicePlatformHeader,
        noteDeviceConflict;
import 'locale.dart';
import 'subscription.dart'
    show aboneAynasiProvider, abonelikDurumuYaniti, aynadakiAbonelik;
import 'wallet.dart' show cuzdanDegismisOlabilir, cuzdanTazelemeProvider;

/// Paywall'ı herhangi bir ekrandan açabilmek için kök navigatör.
final GlobalKey<NavigatorState> rythoNavigatorKey = GlobalKey<NavigatorState>();

/// Kilitli özellik için sunucunun döndürdüğü HTTP kodu.
const int kPaywallStatus = 402;

/// Kota/hız sınırı: sunucu `Retry-After` (saniye) ile birlikte döner.
const int kKotaStatus = 429;

/// Sunucunun 429 ile bildirdiği bekleme süresinin BİTİŞ ANI; `null` =
/// bekleme yok.
///
/// SADE `StateProvider` — `cuzdanTazelemeProvider` ile aynı gerekçe:
/// yazan taraf `apiProvider`'ın interceptor'ı; `apiProvider`'ı izleyen bir
/// sağlayıcıya oradan dokunmak çalışma anında `CircularDependencyError`
/// fırlatır (bulgu B10). Bu sağlayıcı hiçbir şeyi izlemez; okuyan yüzey
/// (ör. "{n} sn sonra tekrar dene" rozeti) kendi tarafından bağlanır.
///
/// Süre değil AN tutuluyor: "30 saniye" yazıldığı andan itibaren eskir;
/// bitiş anı okuyan yüzeye kalan süreyi istediği zaman hesaplatır.
final kotaBeklemeProvider = StateProvider<DateTime?>((_) => null);

/// `Retry-After` başlığını saniyeye çevirir; yoksa/sayı değilse `null`.
///
/// HTTP tarihi biçimi (`Wed, 21 Oct 2015 07:28:00 GMT`) BİLEREK
/// çözülmüyor: sunucumuz yalnız saniye yazar (`core/ratelimit.py`
/// `str(retry_after)`, `api/partners.py` `"2"`); tarih gelen bir başlık
/// bizim değildir (vekil/CDN), onu "0 sn" diye okumak yanlış bir vaat
/// olurdu.
int? retryAfterSaniye(Headers? basliklar) {
  final ham = basliklar?.value('retry-after')?.trim();
  if (ham == null) return null;
  final sn = int.tryParse(ham);
  return sn == null || sn <= 0 ? null : sn;
}

/// Tek cihaz kilidinin çakışma kodu (X-Device-Conflict başlığıyla birlikte).
/// İşleyişi core/device_session.dart'ta: kapı kapanır, oturum AÇIK kalır.
const int kDeviceConflictStatus = 409;

bool _paywallOpen = false;

/// 402'ye verilecek cevabın türü.
enum PaywallHedefi {
  /// Kilidi abonelik açar → [PaywallScreen] ("abone ol").
  abonelik,

  /// Kilidi bakiye açar → [TokenStoreScreen] ("doldur").
  jetonMagazasi,

  /// Satılacak bir şey YOK; yalnız sunucunun kendi metni gösterilir.
  mesaj,
}

/// Sunucunun 402'sine hangi yüzeyle cevap verilir?
///
/// Kilit kararı tek yerde — sunucuda — verilir; istemci hangi ekranda olursa
/// olsun aynı davranışı gösterir. Ayrım `detail` metnine GÖMÜLEMEZ (o alan
/// kullanıcıya gösterilen düz metin); sunucu `X-Paywall-Reason` ile söyler:
///
/// * başlık yok → abonelik gerekiyor → [PaywallHedefi.abonelik]
/// * `tokens`   → bakiye bitti       → [PaywallHedefi.jetonMagazasi]
/// * `people`   → kontenjan doldu    → aşağıdaki ayrım
///
/// Token'ı biten aboneye abonelik satmaya çalışmak yanlış teşhis olurdu.
///
/// **`people` neden ÜÇÜNCÜ bir cevap gerektiriyor** (bulgu B10, ölçüldü):
/// kontenjan 402'si İKİ ayrı duruma da dönüyor ve sunucu ayrımı yalnız
/// metinde yapıyor — ücretsiz kullanıcıya `people.limit_free` ("Rytho+ ile
/// eşini, çocuklarını… takip edebilirsin"), ABONEYE `people.limit_plus`
/// ("listeden bir kişiyi çıkarabilirsin"). Başlığı `tokens` mı değil mi diye
/// ikiye indirmek, 10 kişilik kontenjanı dolan aboneye sunucunun kendi
/// cümlesinin TERSİNİ söylüyordu: tam ekran "Rytho+" sayfası ve satın al
/// düğmesi. Gösterilen tek şey de o ekrandı, çünkü `person_form_screen` 402'de
/// kendi mesajını bilerek bastırıyor ("interceptor zaten paywall açıyor").
///
/// [abone] üç değerli (`core/subscription.aboneAynasiProvider`): `false` ise
/// satış ekranı DOĞRU cevap; `true` ya da `null` ise satmıyoruz. Bilinmiyorken
/// de satmamanın gerekçesi, sunucunun metninin her iki durumda da doğru,
/// satış ekranının yalnız bir durumda doğru olması.
///
/// Başlıksız 402'de ayna SORULMAZ. Sunucu "Plus gerekiyor" diyorken aynanın
/// `true` olması aynanın BAYAT olduğu anlamına gelir (abonelik düşmüş olabilir)
/// ve doğru cevap yine satış ekranıdır — bu üründe sunucu esastır.
PaywallHedefi paywallHedefi(String? sebep, {required bool? abone}) {
  if (sebep == 'tokens') return PaywallHedefi.jetonMagazasi;
  if (sebep == 'people') {
    return abone == false ? PaywallHedefi.abonelik : PaywallHedefi.mesaj;
  }
  return PaywallHedefi.abonelik;
}

/// Sunucu 402 döndüğünde doğru yüzeyi açar.
///
/// [ozellik] sunucunun `X-Paywall-Feature` başlığından (`require_plus`
/// adı): satış ekranı "{özellik} için Rytho+" diyebilsin. Eskiden başlık
/// hiç okunmuyordu ve ekran her kilitte aynı genel cümleyi gösteriyordu.
///
/// Abonelik yolu `acPaywall` (TEK açılış noktası, `PaywallKaynak.kilit402`
/// = kesinti → tam ekran diyalog); `_paywallOpen` yeniden giriş kapısı
/// BURADA kalır — gerekçesi `paywall_acilis.dart` başında. Jeton mağazası
/// `acPaywall`ın kapsamında değil (o yalnız satış ekranını açar); aynı
/// kesinti rotası elle kurulur.
Future<void> _showPaywall(String? reason, PaywallHedefi hedef,
    {PlusOzellik? ozellik}) async {
  if (hedef == PaywallHedefi.mesaj) {
    _sunucuMesajiniGoster(reason);
    return;
  }
  if (_paywallOpen) return;
  final navigator = rythoNavigatorKey.currentState;
  final context = rythoNavigatorKey.currentContext;
  if (navigator == null || context == null) return;

  _paywallOpen = true;
  try {
    if (hedef == PaywallHedefi.jetonMagazasi) {
      await navigator.push(MaterialPageRoute(
        builder: (_) => TokenStoreScreen(reason: reason),
        fullscreenDialog: true,
      ));
    } else {
      await acPaywall(context,
          kaynak: PaywallKaynak.kilit402, ozellik: ozellik, reason: reason);
    }
  } finally {
    _paywallOpen = false;
  }
}

/// Satılacak bir şey olmadığında sunucunun kendi (yerelleştirilmiş) metni.
///
/// Kök navigatörün bağlamı kullanılıyor — paywall ve çıkış yolu da aynı
/// köprüden geçiyor (bkz. `auth_service._uygulamaKabi`). `ScaffoldMessenger`
/// `MaterialApp` içinde Navigator'ın ÜSTÜNDE kurulduğu için bu bağlamdan
/// bulunur.
///
/// Metin boşsa hiçbir şey gösterilmez: kontenjan 402'si sunucuda HER ZAMAN
/// metinle dönüyor (`services/people_service.create_person`). Metinsiz bir
/// kontenjan 402'si sunucu kusuru olurdu ve onu satış ekranıyla kapatmak
/// yanlış teşhis olurdu.
void _sunucuMesajiniGoster(String? metin) {
  if (metin == null || metin.isEmpty) return;
  final context = rythoNavigatorKey.currentContext;
  if (context == null || !context.mounted) return;
  ScaffoldMessenger.maybeOf(context)
      ?.showSnackBar(SnackBar(content: Text(metin)));
}

/// Yanıttan düşülen iki not: bakiye sayacı ve abonelik aynası (bulgu B10).
///
/// İkisi de SADE `StateProvider` — `apiProvider`'ı izlemeyen sağlayıcılar.
/// Halka bu yüzden kurulmuyor; gerekçenin tamamı
/// `core/wallet.cuzdanTazelemeProvider` ve
/// `core/subscription.aboneAynasiProvider` başında.
///
/// [govde] `null` geçilirse ayna dokunulmaz: DÜŞEN bir istek abonelik durumu
/// hakkında hiçbir şey söylemez.
///
/// try/catch zorunlu: başarılı bir yanıtın YAN ETKİSİ o yanıtı riske
/// atmamalı — raporu almış kullanıcıya hata göstermek, bir tazelemeyi
/// kaçırmaktan çok daha pahalı. (Aynı duruş: `updateRequiredInterceptor`
/// 426 kancasını da böyle sarıyor.)
void _yanitiNotEt(Ref ref, RequestOptions istek, Object? govde) {
  try {
    if (cuzdanDegismisOlabilir(istek)) {
      ref.read(cuzdanTazelemeProvider.notifier).state++;
    }
    if (govde != null && abonelikDurumuYaniti(istek)) {
      final abone = aynadakiAbonelik(govde);
      if (abone != null) ref.read(aboneAynasiProvider.notifier).state = abone;
    }
  } catch (e) {
    debugPrint('Yanıt notu düşülemedi: $e');
  }
}

/// Backend adresi: --dart-define=RYTHO_API_URL=... ile geçilir;
/// verilmezse Cloud Run üretim adresi kullanılır.
const String kApiBaseUrl = String.fromEnvironment(
  'RYTHO_API_URL',
  defaultValue: 'https://rytho-backend-770582338651.us-central1.run.app',
);

final apiProvider = Provider<Dio>((ref) {
  // Dil izleniyor: değiştiğinde bu sağlayıcı yeniden kurulur ve ona bağlı tüm
  // ağ sağlayıcıları (burç yorumu, gökyüzü, günlük okuma...) tazelenir.
  // İzlenmezse başlık yalnızca SONRAKİ isteklerde değişir; ekrandaki yorum
  // eski dilde asılı kalır — dil değiştirmenin en görünür kusuru buydu.
  //
  // İzlenen şey GEÇERLİ dil: kullanıcı tercihi YOKSA sistem dili. Eskiden
  // yalnız `localeProvider` izleniyordu ve tercih `null` kalan (yani
  // varsayılan) kullanıcıda sistem dili değişince hiçbir şey tazelenmiyordu
  // — arayüz İngilizceye geçiyor, önbellekteki yorumlar Türkçe kalıyordu.
  // İzlenen şey Locale NESNESİ değil DİL KODU: sistem dili "tr_TR", kullanıcı
  // tercihi "tr" olarak kurulduğu için açılışta tercih yüklenince nesne
  // değişiyor ve apiProvider bir kez daha kuruluyordu — ona bağlı BÜTÜN ağ
  // sağlayıcıları soğuk açılışta ikinci kez ateşleniyordu (ölçüldü: ~14
  // istek ~27'ye çıkıyor). Sunucu için "tr" ile "tr_TR" aynı dil.
  final dil = ref.watch(effectiveLocaleProvider.select((l) => l.languageCode));
  final locale = Locale(dil);

  final dio = Dio(BaseOptions(
    baseUrl: kApiBaseUrl,
    connectTimeout: const Duration(seconds: 20),
    receiveTimeout: const Duration(seconds: 120),
  ));
  // Zorunlu güncelleme (PBZ): her istek derleme numarasını taşır; sunucu
  // eşiğin altındaysa 426 döner ve kapı O ANDA kapanır — açık oturum da.
  // Eski kapı yalnız açılışta ve yalnız istemcide bakıyordu.
  dio.interceptors
      .add(appBuildInterceptor(() => ref.read(appBuildProvider.future)));
  dio.interceptors.add(updateRequiredInterceptor(
      () => ref.read(forceUpdateProvider.notifier).state = true));
  // Tek cihaz kilidi (TC): 409 + X-Device-Conflict → kapı kapanır, oturum
  // AÇIK kalır; devralma/çıkış kararı `DeviceConflictScreen`'de (bkz.
  // core/device_session.dart). 426 ile aynı desen: interceptor → bayrak.
  // Eski hâli burada `signOut` yapıyordu ve devralma bu yüzden 401'e
  // çarpıyordu. İlk 409 kazanır (`noteDeviceConflict`).
  dio.interceptors.add(deviceConflictInterceptor((cakisma) =>
      noteDeviceConflict(ref.read(deviceConflictProvider.notifier), cakisma)));
  dio.interceptors.add(InterceptorsWrapper(
    onRequest: (options, handler) async {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        final token = await user.getIdToken();
        options.headers['Authorization'] = 'Bearer $token';
      }
      // Backend yorumları bu başlığa göre üretir (persona, korpus ve önbellek
      // dahil). Gönderilmezse sunucu Türkçe varsayar ve arayüz İngilizce olsa
      // bile yorumlar Türkçe gelir.
      options.headers['Accept-Language'] = acceptLanguageHeader(locale);
      // Tek cihaz kilidi (yalnızca ücretli abonede etkili). Sunucu bu
      // kimliği kayıtlı cihazla karşılaştırır; uyuşmazlıkta 409 döner
      // (yukarıdaki `deviceConflictInterceptor`).
      options.headers['X-Device-Id'] = await deviceId();
      // Platform da gider: sunucu otomatik devralmada kayda yazar, öbür
      // cihazın kapı ekranı "{platform} cihazında" derken doğru cihazı
      // söyler (bkz. core/device_session.dart).
      options.headers[kDevicePlatformHeader] = devicePlatform();
      handler.next(options);
    },
    onResponse: (response, handler) {
      // Harcama sunucuda BİTTİKTEN sonra bakiye yeniden sorulur (bulgu B10):
      // jeton düşümü yanıt gönderilmeden önce işlenmiş olur, yani burada
      // okunan bakiye harcamayı İÇERİR.
      _yanitiNotEt(ref, response.requestOptions, response.data);
      handler.next(response);
    },
    onError: (error, handler) {
      try {
        final yanit = error.response;
        // Gövde geçilmiyor (ayna dokunulmasın), ama harcama uçlarından dönen
        // hata bakiyeyi İLGİLENDİRİR: 402'den sonra açılan jeton mağazası
        // bakiyeyi ekranda gösteriyor ve bayat bir sayı orada "bakiyen var"
        // derken sunucu aynı isteği yetersiz bakiyeyle reddetmişti.
        if (yanit != null) _yanitiNotEt(ref, yanit.requestOptions, null);
        if (yanit?.statusCode == kPaywallStatus) {
          final govde = yanit!.data;
          final detay = govde is Map ? govde['detail'] : null;
          final sebep = yanit.headers.value('x-paywall-reason');
          _showPaywall(detay is String ? detay : null,
              paywallHedefi(sebep, abone: ref.read(aboneAynasiProvider)),
              ozellik:
                  PlusOzellik.bul(yanit.headers.value('x-paywall-feature')));
        }
        // 429: sunucu "yavaşla" dedi. Bitiş anı not edilir; başlıksız
        // 429'da not YOK — süresi bilinmeyen bir bekleme ilan etmek
        // uydurma olurdu.
        if (yanit?.statusCode == kKotaStatus) {
          final sn = retryAfterSaniye(yanit!.headers);
          if (sn != null) {
            ref.read(kotaBeklemeProvider.notifier).state =
                DateTime.now().add(Duration(seconds: sn));
          }
        }
      } catch (e) {
        // Yan etkideki bir hata sunucunun KENDİ hatasının yerine geçmemeli:
        // 402'nin detayı ve paywall kararı kaybolurdu.
        debugPrint('402/429 yan etkisi düştü: $e');
      }
      // U06: sunucu "AI onayı yok" dedi — bu cihazın bildiği bayat (onay
      // başka cihazda geri alınmış olabilir). Onay sayfası açılır; hata
      // yine çağırana gider ve ekran "yapay zeka kapalı" kartını gösterir.
      if (aiOnayHatasiMi(error)) aiOnayiSunucuIstedi();
      handler.next(error);
    },
  ));
  return dio;
});

/// FastAPI'nin KENDİ ürettiği, çevrilmemiş gövde metinleri.
///
/// Sunucumuz kendi hatalarında `detail` alanını kullanıcının dilinde üretiyor
/// (`core/messages.py` → `text()`) ve o metinler olduğu gibi gösterilebilir.
/// Ama **yönlendirme düzeyindeki** hataları — var olmayan uç, yanlış metot —
/// FastAPI üretiyor ve bunlar İngilizce sabitler.
///
/// Cihaz testinde tam olarak bu görüldü: yüz okuma ucu henüz deploy
/// edilmemişti, sunucu 404 döndü ve rıza ekranında kullanıcıya kırmızı
/// **"Not Found"** yazdı.
const _cerceveMetinleri = {'Not Found', 'Method Not Allowed'};

/// Sunucu 200 dondu ama YORUM uretilemedi (yedek metin bayragi).
///
/// gz-2: Gemini kotasi doldugunda uc, uc cumlelik hazir bir paragrafi normal
/// rapor gibi donduruyordu. Kullanici bunu URUN saniyor ("rapor cok yuzeysel"
/// bize model sikayeti olarak donuyor), jetonunun iade edildigini de
/// ogrenmiyordu. Depo doktrini "olculmeyen soylenmez": uretilmemis metin
/// rapor yerine gecmez. Karsit ornek zaten depoda — sohbet ucu ayni durumda
/// `llm_unavailable` diyor.
///
/// Sinir: bu istisna YALNIZ yorumu temsil eder. OLCULMUS cikti (BaZi
/// haritasi, natal carki) yerinde kalir; onu da silmek ayni doktrini ters
/// yone cevirirdi. Bu yuzden BaZi saglayicisi firlatmaz, sekme bayraga bakar.
class RaporUretilemedi implements Exception {
  const RaporUretilemedi({this.jetonIadeEdildi = false});

  /// Sunucu harcanan jetonu geri verdi mi?
  ///
  /// Gunluk okuma jeton HARCAMAZ; orada "jetonun iade edildi" demek yalan
  /// olurdu. Bu yuzden bayrak istemcide sabitlenmiyor, sunucudan geliyor.
  final bool jetonIadeEdildi;
}

/// Hata mesajını kullanıcıya gösterilebilir hale getirir.
///
/// Backend kendi hatalarında kullanıcının dilinde ve anlaşılır bir `detail`
/// döndürüyor (kota, paywall, sunucu hatası). Ham `DioException` metnini
/// ekrana basmak kullanıcıya HTTP durum kodu ve MDN bağlantısı göstermek
/// demek.
///
/// `l10n` ZORUNLU ve Türkçe geri düşüş metni YOK: parametre opsiyonelken 41
/// çağrı yerinin 8'i onu geçmiyordu (günlük, tepki, doğum kaydı, ilişki) ve
/// bağlantı koptuğu anda İngilizce arayüzün ortasına Türkçe bir SnackBar
/// düşüyordu. Metni gövdeden silmek atlanan çağrıyı DERLEYİCİYE yakalattırır
/// — gramer/dil tarayıcısı ARB'ye bakıyor, gövdeye gömülü sabiti görmüyor.
String friendlyError(Object error, AppLocalizations l10n) {
  // Tek suzgec: dort yol da ayni durust cumleyi gosterir (gz-2). Imza ve
  // "govdeye gomulu Turkce YOK" kurali korunuyor — cumleler ARB'den gelir.
  if (error is RaporUretilemedi) {
    return error.jetonIadeEdildi
        ? l10n.reportUnavailableRefunded
        : l10n.reportUnavailable;
  }
  // `Future.timeout` ile kesilen akislar (profil yuklemesi, 12 sn) Dio
  // disinda duser; "beklenmeyen sorun" degil, baglanti yok demektir.
  if (error is TimeoutException) return l10n.errorConnection;
  if (error is AiOnayiGerekli) return l10n.aiConsentOffBody;
  if (error is DioException) {
    // 429 + Retry-After: sunucunun soyledigi sure, genel `detail`
    // cumlesinden daha dogru — kullanici NE ZAMAN deneyecegini ogrenir.
    // Basliksiz 429 asagidaki `detail` yoluna duser (sure uydurulmaz).
    if (error.response?.statusCode == kKotaStatus) {
      final sn = retryAfterSaniye(error.response?.headers);
      if (sn != null) return l10n.retryAfterSeconds(sn);
    }
    // Sunucunun `detail` alani zaten kullanicinin dilinde uretiliyor
    // (Accept-Language ile), o yuzden oldugu gibi gosterilir — cerceveden
    // gelenler HARIC.
    final data = error.response?.data;
    if (data is Map && data['detail'] is String) {
      final detay = data['detail'] as String;
      if (!_cerceveMetinleri.contains(detay)) return detay;
    }
    if (error.type == DioExceptionType.connectionTimeout ||
        error.type == DioExceptionType.receiveTimeout ||
        error.type == DioExceptionType.connectionError) {
      return l10n.errorConnection;
    }
  }
  return l10n.errorGeneric;
}

/// Kullanıcının doğum verisini backend'in beklediği gövdeye çevirir.
///
/// [varsayilanAd]: profilde ad yoksa sunucuya giden ad — çağıran
/// `l10n.defaultUserName` geçer ("Gezgin"/"Traveller"). Verilmezse alan
/// HİÇ gönderilmez ve sunucunun kendi varsayılanı işler: eskiden burada
/// `'Gezgin'` sabitti ve İngilizce kullanıcı promptta "Gezgin" diye
/// anılıyordu — aynı sabitin istemcide ikinci kopyası olmasın.
Map<String, dynamic> birthPayload(Map<String, dynamic> profile,
    {String? varsayilanAd}) {
  final birthDate = (profile['birthDate'] as String?) ?? '2000-01-01';
  // birthTime alanı YOKSA saat bilinmiyor demektir (Revize B1): 12:00
  // yalnızca saat gerektiren uçlar (natal) için teknik dolgu, hour_known
  // bayrağı gerçeği taşır — BaZi bu bayrağa bakıp saat sütununu kurmaz.
  final birthTime = profile['birthTime'] as String?;
  final dateParts = birthDate.split('-').map(int.parse).toList();
  final timeParts = (birthTime ?? '12:00').split(':').map(int.parse).toList();
  final ad = (profile['displayName'] as String?) ?? varsayilanAd;
  return {
    'name': ?ad,
    'year': dateParts[0],
    'month': dateParts[1],
    'day': dateParts[2],
    'hour': timeParts[0],
    'minute': timeParts[1],
    'hour_known': birthTime != null,
    'city': profile['birthCity'] ?? 'Istanbul',
    'nation': profile['birthNation'],
    // Belirtilmemiş cinsiyet BELİRTİLMEMİŞTİR: eski `'female'` önseçimi
    // BaZi'de şans yönünü kadın varsayımıyla ölçtürüyordu. Sunucu
    // `unspecified` ile yönü "ölçülemez" sayar (D0).
    'gender': profile['gender'] ?? 'unspecified',
  };
}
