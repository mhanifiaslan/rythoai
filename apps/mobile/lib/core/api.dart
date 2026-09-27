import 'package:dio/dio.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/paywall/paywall_screen.dart';
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

/// Paywall'ı herhangi bir ekrandan açabilmek için kök navigatör.
final GlobalKey<NavigatorState> rythoNavigatorKey = GlobalKey<NavigatorState>();

/// Kilitli özellik için sunucunun döndürdüğü HTTP kodu.
const int kPaywallStatus = 402;

/// Tek cihaz kilidinin çakışma kodu (X-Device-Conflict başlığıyla birlikte).
/// İşleyişi core/device_session.dart'ta: kapı kapanır, oturum AÇIK kalır.
const int kDeviceConflictStatus = 409;

bool _paywallOpen = false;

/// Sunucu 402 döndüğünde doğru ekranı açar.
///
/// Kilit kararı tek yerde — sunucuda — verilir; istemci hangi ekranda olursa
/// olsun aynı davranışı gösterir. İki 402 türü var ve ayrım `detail`
/// metnine GÖMÜLEMEZ (o alan kullanıcıya gösterilen düz metin); sunucu
/// `X-Paywall-Reason: tokens` başlığıyla söyler:
///
/// * başlık yok  → abonelik sorunu → [PaywallScreen] ("abone ol")
/// * `tokens`    → bakiye bitti    → [TokenStoreScreen] ("doldur")
///
/// Token'ı biten aboneye abonelik satmaya çalışmak yanlış teşhis olurdu.
Future<void> _showPaywall(String? reason, {bool tokens = false}) async {
  if (_paywallOpen) return;
  final navigator = rythoNavigatorKey.currentState;
  if (navigator == null) return;

  _paywallOpen = true;
  try {
    await navigator.push(MaterialPageRoute(
      builder: (_) => tokens
          ? TokenStoreScreen(reason: reason)
          : PaywallScreen(reason: reason),
      fullscreenDialog: true,
    ));
  } finally {
    _paywallOpen = false;
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
    onError: (error, handler) {
      if (error.response?.statusCode == kPaywallStatus) {
        final detail = error.response?.data is Map
            ? (error.response!.data as Map)['detail'] as String?
            : null;
        final sebep =
            error.response?.headers.value('x-paywall-reason');
        _showPaywall(detail, tokens: sebep == 'tokens');
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
  if (error is AiOnayiGerekli) return l10n.aiConsentOffBody;
  if (error is DioException) {
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
Map<String, dynamic> birthPayload(Map<String, dynamic> profile) {
  final birthDate = (profile['birthDate'] as String?) ?? '2000-01-01';
  // birthTime alanı YOKSA saat bilinmiyor demektir (Revize B1): 12:00
  // yalnızca saat gerektiren uçlar (natal) için teknik dolgu, hour_known
  // bayrağı gerçeği taşır — BaZi bu bayrağa bakıp saat sütununu kurmaz.
  final birthTime = profile['birthTime'] as String?;
  final dateParts = birthDate.split('-').map(int.parse).toList();
  final timeParts = (birthTime ?? '12:00').split(':').map(int.parse).toList();
  return {
    'name': profile['displayName'] ?? 'Gezgin',
    'year': dateParts[0],
    'month': dateParts[1],
    'day': dateParts[2],
    'hour': timeParts[0],
    'minute': timeParts[1],
    'hour_known': birthTime != null,
    'city': profile['birthCity'] ?? 'Istanbul',
    'nation': profile['birthNation'],
    'gender': profile['gender'] ?? 'female',
  };
}
