import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart' show StateProvider;

import 'ai_consent.dart' show aiOnayiGerektir, aiSorguParametresi;
import 'analytics.dart';
import 'api.dart';
import 'gun_donumu.dart';
import 'subscription.dart';

/// Firebase oturum akışı.
final authStateProvider = StreamProvider<User?>(
  (ref) => FirebaseAuth.instance.authStateChanges(),
);

/// Onboarding finalinin sonucu (R12-B1 + O3).
enum OnboardOutcome {
  /// Harita hesaplandı — Büyük Üçlü perdesi açılır.
  chartOk,

  /// Doğum verisi yazıldı ama harita hesaplanamadı (ör. çevrimdışı).
  /// Perde açılmaz; kullanıcıya DÜRÜSTÇE söylenir — eskiden bu durum
  /// sessizce yutuluyordu ve rozetlerin yokluğu açıklanamıyordu.
  chartMissing,
}

/// Onboarding'i BU oturumda bitiren kullanıcının sonucu (R12-B1).
///
/// `saveBirthRecord` onboardingCompleted'ı tek yazımda yazar ve yazım iner
/// inmez `_Gate` kabuğa geçer — Büyük Üçlü perdesi bu yüzden onboarding
/// ekranında yaşayamaz. Değer yazım ÖNCESİ konur; AppShell ilk karede
/// görür, sahneyi oynatır ve sıfırlar. Kalıcı değil: uygulamanın sonraki
/// açılışlarında sahne tekrarlanmaz.
final justOnboardedProvider = StateProvider<OnboardOutcome?>((_) => null);

/// Bir profil anlık görüntüsüne **karar için** güvenilebilir mi?
///
/// Firestore, dinleyici kurulduğunda önce yerel önbellekten yayın yapıyor.
/// Önbellek boşsa (taze kurulum, yeni giriş) bu yayın "doküman yok" diyor —
/// oysa doküman sunucuda duruyor. Sunucu yanıtı bir an sonra geliyor ve
/// düzeliyor.
///
/// Cihaz testinde görülen şey buydu: giriş yapınca doğum bilgisi formu
/// açılıyor, sonra kendiliğinden geçiyordu. Kullanıcının profili tamdı
/// (`onboardingCompleted = true`); uygulama yalnızca bir anlığına yokmuş gibi
/// davranıyordu.
///
/// Kural: **var olan bir doküman her zaman güvenilir; "yok" bilgisi ancak
/// SUNUCUDAN geldiyse güvenilir.**
bool profileSnapshotIsAuthoritative({
  required bool exists,
  required bool isFromCache,
}) =>
    exists || !isFromCache;

/// Profil akışının İLK yayını için üst sınır.
///
/// NEDEN: yukarıdaki süzgeç güvenilmez anlık görüntüyü yutuyor ve bu
/// doğru — ama çevrimdışı TAZE kurulumda (önbellek boş, ağ yok) sunucudan
/// hiçbir şey gelmiyor, süzgeç hiçbir şey geçirmiyor ve sağlayıcı sonsuza
/// dek `loading` kalıyor: `_Gate` açılış sahnesini sonsuz döndürüyor,
/// kullanıcı ne hata görüyor ne "tekrar dene" alıyor. 12 sn: Firestore'un
/// kendi çevrimdışı tespitinin (10 sn civarı) üstünde, kullanıcının "takıldı"
/// deyip uygulamayı kapatmasının altında.
const Duration kProfilAkisiZamanAsimi = Duration(seconds: 12);

/// [kaynak] ilk olayını [sure] içinde vermezse akışa bir
/// [TimeoutException] EKLER — akışı KAPATMAZ.
///
/// `Stream.timeout` bilerek kullanılmadı: onun sayacı HER olay arası
/// boşluğu ölçer. Profil dokümanı günlerce değişmez; ilk yayından sonra
/// her 12 saniyede bir hata üretir, `_Gate` sağlıklı oturumu hata
/// sahnesine düşürürdü. Buradaki sayaç yalnız ilk olaya kadar yaşar.
///
/// Akış kapanmıyor çünkü hata kalıcı değil: ağ gelince Firestore aynı
/// dinleyiciye sunucu görüntüsünü yayar ve sağlayıcı kendiliğinden
/// toparlanır. `StreamProvider` hata olayından sonra dinlemeyi sürdürür;
/// bu yüzden "Tekrar dene" (sağlayıcıyı geçersiz kılar) ve kendiliğinden
/// iyileşme ikisi de çalışır.
Stream<T> ilkYayinZamanAsimi<T>(Stream<T> kaynak, Duration sure) {
  late final StreamController<T> kontrol;
  StreamSubscription<T>? abonelik;
  Timer? sayac;
  kontrol = StreamController<T>(
    // İç iptalin Future'ı BİLEREK döndürülmüyor: Firestore dinleyicisinin
    // kapanışı beklenecek bir şey değil, ve döndürülünce dış akışın `done`
    // olayı o Future'ın `whenComplete` zincirine bağlanıyor — zincir kök
    // bölgede (zone) kuruluyor, sahte-zamanlı testte hiç gelmiyor ve
    // `cancel()` askıda kalıyordu (ölçüldü: splash_sabri_test 9 dk hang).
    onCancel: () {
      sayac?.cancel();
      abonelik?.cancel();
    },
    onListen: () {
      sayac = Timer(sure, () {
        if (!kontrol.isClosed) {
          kontrol.addError(TimeoutException(
              'profil akışı ilk yayını vermedi', sure));
        }
      });
      abonelik = kaynak.listen(
        (deger) {
          sayac?.cancel();
          kontrol.add(deger);
        },
        onError: (Object hata, StackTrace iz) {
          sayac?.cancel();
          kontrol.addError(hata, iz);
        },
        onDone: () {
          sayac?.cancel();
          kontrol.close();
        },
      );
    },
    onPause: () => abonelik?.pause(),
    onResume: () => abonelik?.resume(),
  );
  return kontrol.stream;
}

/// Firestore'daki kullanıcı profili (users/{uid}).
final profileProvider = StreamProvider<Map<String, dynamic>?>((ref) {
  final user = ref.watch(authStateProvider).value;
  if (user == null) return Stream.value(null);
  final akis = FirebaseFirestore.instance
      .collection('users')
      .doc(user.uid)
      .snapshots()
      // Güvenilmez anlık görüntü YAYILMIYOR; sağlayıcı o sırada `loading`
      // kalıyor ve arayüz açılış ekranını gösteriyor. Yanlış bir "profil yok"
      // yaymak, kullanıcıyı verisi dururken onboarding'e düşürüyordu.
      .where((s) => profileSnapshotIsAuthoritative(
            exists: s.exists,
            isFromCache: s.metadata.isFromCache,
          ))
      .map((snapshot) => snapshot.data())
      // İÇERİK karşılaştırması: Firestore her yerel meta değişiminde
      // (pending-write, cache→server) yeni bir anlık görüntü yayıyor ve
      // her biri YENİ bir Map nesnesi. `AsyncData` eşitliği Map'in kimliğine
      // düştüğü için profili izleyen 12 sağlayıcı — aralarında
      // `POST /reports/daily` ve `/reports/natal` — içerik hiç
      // değişmeden yeniden koşuyordu. Kotayı besleyen üçüncü döngü buydu.
      .distinct(ayniProfil);
  // Süzgecin bedeli: çevrimdışı taze kurulumda hiç yayın yok → sonsuz
  // açılış. İlk yayın için üst sınır (bkz. ilkYayinZamanAsimi).
  return ilkYayinZamanAsimi(akis, kProfilAkisiZamanAsimi);
});

/// İki profil anlık görüntüsü içerikçe aynı mı?
///
/// `mapEquals` yeterli değil: profilde iç içe map/liste alanlar var
/// (bildirim tercihleri, tepki sayaçları) ve onlar kimlikle karşılaştırılıp
/// her seferinde "değişti" derdi.
bool ayniProfil(Map<String, dynamic>? a, Map<String, dynamic>? b) =>
    _ayniDeger(a, b);

bool _ayniDeger(Object? a, Object? b) {
  if (identical(a, b)) return true;
  if (a is Map && b is Map) {
    if (a.length != b.length) return false;
    for (final anahtar in a.keys) {
      if (!b.containsKey(anahtar)) return false;
      if (!_ayniDeger(a[anahtar], b[anahtar])) return false;
    }
    return true;
  }
  if (a is List && b is List) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!_ayniDeger(a[i], b[i])) return false;
    }
    return true;
  }
  return a == b;
}

/// Anlık gökyüzü durumu (retrolar, Ay evresi, açılar, NASA mesafeleri).
final skyNowProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  final dio = ref.watch(apiProvider);
  final response = await dio.get('/api/v1/sky/now');
  return Map<String, dynamic>.from(response.data['data']);
});

/// Doğum haritası — ÜCRETSİZ katman (R2-F1).
///
/// Çark, yerleşimler, evler ve açılar herkese açıktır: bunlar hesaptır,
/// LLM maliyeti YOKTUR. Kullanıcı ilk dakikada "bu uygulama gerçekten
/// benim haritamı biliyor" diyebilmeli; ücretli olan, bu haritanın
/// Rytho tarafından OKUNMASI (natalReportProvider).
final natalChartProvider =
    FutureProvider<Map<String, dynamic>?>((ref) async {
  final profile = ref.watch(profileProvider).value;
  if (profile == null || profile['onboardingCompleted'] != true) return null;
  final dio = ref.watch(apiProvider);
  final response = await dio.post('/api/v1/astrology/natal-chart',
      data: birthPayload(profile));
  return Map<String, dynamic>.from(response.data['data']);
});

/// Bugünün transitleri (HI-turu HA8): gökyüzünün BU haritaya değdiği
/// noktalar + natal↔transit çapraz açılar.
///
/// `/astrology/transits` sunucuda BAŞTAN BERİ vardı ve mobil hiç
/// çağırmıyordu — bi-wheel bu yüzden çapraz açısız çiziliyordu. Hesap
/// LLM'siz; Harita İnceleme'nin bi-wheel görünümü buradan beslenir.
final transitsProvider =
    FutureProvider<Map<String, dynamic>?>((ref) async {
  final profile = ref.watch(profileProvider).value;
  if (profile == null || profile['onboardingCompleted'] != true) return null;
  final dio = ref.watch(apiProvider);
  final response = await dio.post('/api/v1/astrology/transits',
      data: birthPayload(profile));
  return Map<String, dynamic>.from(response.data['data']);
});

/// Günlük girişleri (R2-G1/R4-3): yeniden eskiye.
///
/// Ana ekrandaki hızlı giriş kartı son girişin tarihini göstermek için
/// izler; tam liste DiaryScreen'de. Kayıt POST sonrası invalidate edilir.
final diaryProvider =
    FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final profile = ref.watch(profileProvider).value;
  if (profile == null || profile['onboardingCompleted'] != true) {
    return const [];
  }
  final dio = ref.watch(apiProvider);
  final response = await dio.get('/api/v1/account/diary');
  final data = Map<String, dynamic>.from(response.data['data']);
  return [
    for (final e in (data['entries'] as List? ?? const []))
      Map<String, dynamic>.from(e as Map),
  ];
});

/// Kişisel sinyaller (R2-S1): "Rytho bugün senin için fark etti" kartları.
///
/// HER katmana açık: başlık cümleleri sunucuda ŞABLONLA (LLM'siz) kurulur,
/// abonede ayrıca tek cümlelik yorum ("insight") gelir. Doğum verisi yoksa
/// sunucu hata değil boş liste döner; ekran bölümü sessizce gizler — ana
/// ekran yeni kullanıcıya hata göstermez.
/// Tam sinyal yanıtı — liste + `fingerprint` (KA5 derin bağlantı
/// eşleşmesi) + `checkin_question` alanları.
final signalsDataProvider =
    FutureProvider<Map<String, dynamic>>((ref) async {
  final profile = ref.watch(profileProvider).value;
  if (profile == null || profile['onboardingCompleted'] != true) {
    return const {'signals': []};
  }
  // "Rytho BUGÜN senin için fark etti" diyen kartlar gün dönünce dünün
  // kartları olurdu. Ana ekranda aşağı çekme bu sağlayıcıyı tazeliyor,
  // yani kurtarma yolu VARDI — ama kullanıcının çekmesi gerekiyordu;
  // başlık "bugün" diyorken içerik dünden kalmış olabilir.
  _gunuIzle(ref);
  final dio = ref.watch(apiProvider);
  // U06: onay yoksa `ai=0` — sinyaller (LLM'siz hesap) yine gelir, yorum
  // katmanı sunucuda hiç üretilmez. Kullanıcı açılıştaki onay sayfasına
  // henüz cevap vermemişken de ilk istek haritasını Gemini'ye göndermesin.
  final response = await dio.get('/api/v1/reports/signals',
      queryParameters: await aiSorguParametresi(ref));
  return Map<String, dynamic>.from(response.data['data']);
});

final signalsProvider =
    FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final data = await ref.watch(signalsDataProvider.future);
  return [
    for (final s in (data['signals'] as List? ?? const []))
      Map<String, dynamic>.from(s as Map),
  ];
});

/// Burç bazlı günlük yorum — ÜCRETSİZ katmanın omurgası.
///
/// Kullanıcıdan bağımsızdır ve sunucuda paylaşımlı önbellekten servis edilir:
/// 12 burç için dönem başına tek LLM çağrısı yapılır, kullanıcı sayısı arttıkça
/// maliyet artmaz. Ana ekran bu yüzden hiçbir zaman boş kalmaz.
///
/// ⚠️ Gün anahtarı burada EN ÇOK gerekli, en son fark edildi: sunucu
/// kovasını kullanıcının YEREL gününe bağlıyor (`report_service.py`
/// `_horoscope_bucket`, varsayılan dönem `daily`) ve o kova bu kusurun
/// sunucudaki eşini kapatmak için konmuştu — "sunucu UTC'de ve gece
/// yarısından sonra kullanıcı dünkü yorumu görüyordu" (`reports.py`).
/// İstemci aynı belirtiyi geri getiriyordu: `FutureProvider.family` de
/// varsayılan `isAutoDispose = false`, yani yanıt OTURUM BOYUNCA
/// önbellekte kalıyordu.
///
/// Bu yüzeyin kurtarma yolu HİÇ yoktu ve bu onu kardeşlerinden ayırıyor:
/// Gökyüzü'ndeki aşağı çekme bu sağlayıcıyı tazelemiyor (`sky_screen.dart`
/// `onRefresh` dört sağlayıcı sayıyor, bu onlardan biri değil) ve var olan
/// iki `invalidate` çağrısı yalnız HATA dalında (`sky_screen.dart` ön
/// çekme, `sign_story_screen.dart` tekrar dene düğmesi). Yani ücretsiz
/// katmanın omurgası gün dönümünden sonra oturum boyunca dünün yorumunu
/// gösteriyordu — jetonu olmayan, dolayısıyla "önbellek jeton kurtarıyor"
/// gerekçesi de bulunmayan tek günlük yüzeyde.
final signHoroscopeProvider =
    FutureProvider.family<Map<String, dynamic>, String>((ref, signKey) async {
  _gunuIzle(ref);
  final dio = ref.watch(apiProvider);
  final response = await dio.get('/api/v1/reports/horoscope/$signKey');
  return Map<String, dynamic>.from(response.data['data']);
});

/// Kişiye özel günlük okuma — Rytho+ .
///
/// Abone olmayan için hiç İSTEK ATILMAZ. Atılsaydı sunucu 402 doner ve paywall
/// her acilista kendiliginden acilirdi; kilitli icerik kullanicinin
/// dokunmasiyla acilmali, yuzune firlatilmamali.
final dailyReadingProvider = FutureProvider<Map<String, dynamic>?>((ref) async {
  if (!_hasPlus(ref)) return null;
  _gunuIzle(ref);

  final profile = ref.watch(profileProvider).value;
  if (profile == null || profile['onboardingCompleted'] != true) return null;
  // U06: abonelik kapısından SONRA — abone olmayan kilitli kartı görür,
  // onay sorusunu değil; onay kilidi açmaz, yalnız aktarımı açar.
  final dio = ref.watch(apiProvider);
  await aiOnayiGerektir(ref);
  final response =
      await dio.post('/api/v1/reports/daily', data: birthPayload(profile));
  final veri = Map<String, dynamic>.from(response.data['data']);
  // Yedek metin okuma SAYILMAZ (gz-2): hata olarak yukselir — Gokyuzu
  // kartinda durust cumle + tekrar dene cikar ve sayac "uretildi" demez;
  // yoksa olcum de yalan soyluyordu. Burada okumanin DISINDA gosterilecek
  // bir sey yok (burc etiketleri okumanin ustundeki satir), o yuzden
  // BaZi'deki gibi kismi cizim anlamli degil.
  if (veri['fallback'] == true) {
    throw RaporUretilemedi(jetonIadeEdildi: veri['refunded'] == true);
  }
  Analytics.reportGenerated('daily');
  return veri;
});

/// Rytho+ kapısının ÜÇ hâli.
///
/// Soruyu ikiye indirmek ("abone mi, değil mi") bu depoda üç kez zarar verdi
/// ve her seferinde aynı yönde: **bilmemek, olumsuz cevap sanıldı.**
/// [SubscriptionStatus.okunabildi], `WalletStatus.bilinmiyor` ve
/// `paywallKarariVerilebilir` aynı dersin ürünü. Üçüncü hâl AYRI çizilir —
/// ne kilit (ödemiş kullanıcıya yalan) ne açık içerik (ödemeyene yalan).
enum PlusHali {
  /// Sunucu "abone" dedi.
  abone,

  /// Sunucu "abone değil" dedi — BİLİNEN olumsuz cevap.
  aboneDegil,

  /// Cevap henüz YOK ya da okunamadı. "Abone değil" ile aynı şey DEĞİL.
  bilinmiyor,
}

/// Kapı kararı — SAF işlev.
///
/// Sağlayıcıdan ayrı tutuluyor, çünkü bekçisi sahte bir Firebase `User`ı
/// olmadan yazılamazdı ([abonelikDurumunuOku] ile aynı gerekçe). Parametre
/// tipleri bu yüzden `AsyncValue<Object?>`: karar için gereken tek şey
/// "cevap geldi mi, geldiyse boş mu".
///
/// [profil] yalnız doğum verisi İSTEYEN kapılara verilir (raporlar); İ Ching
/// ve Atlas kehanet karoları profil beklemez.
PlusHali plusHaliniOku({
  required AsyncValue<Object?> oturum,
  required AsyncValue<SubscriptionStatus> abonelik,
  AsyncValue<Object?>? profil,
}) {
  // Oturum henüz CEVAPLAMADI. Bu pencere aboneliğin `isLoading`'iyle BİLE
  // ayırt edilemiyor: oturum yokken `subscriptionProvider`
  // `SubscriptionStatus.none` ile BAŞARIYLA tamamlanıyor ve `none.okunabildi`
  // true. Tek ayırt edici işaret auth akışının kendisi.
  if (oturum.isLoading || !oturum.hasValue) return PlusHali.bilinmiyor;

  // Oturum YOK: bilinen olumsuz cevap (`SubscriptionStatus.none` ile aynı
  // duruş). Ücretli yüzeyler giriş kabuğunun arkasında zaten görünmez.
  if (oturum.value == null) return PlusHali.aboneDegil;

  // Oturum geldiği an abonelik sağlayıcısı yeniden kuruluyor ve Riverpod
  // ÖNCEKİ değeri — oturumsuz `none` — taşımaya devam ediyor; `hasValue` bu
  // yüzden tek başına yetmez, yükleniyorluk da sorulur (KT3 ile aynı kapı).
  if (abonelik.isLoading || !abonelik.hasValue) return PlusHali.bilinmiyor;
  final durum = abonelik.value!;

  // Sunucuya ulaşılamadı (ilkacilis-2): "abone değil" demek yalan olurdu.
  if (!durum.okunabildi) return PlusHali.bilinmiyor;
  if (!durum.active) return PlusHali.aboneDegil;

  // Abone — ama ücretli uç doğum verisini gövdede gönderiyor ve profil
  // yüklenirken `profile == null` okumak aynı çöküşün ikinci katıydı: kilit
  // kartı "abone değilsin" der, oysa eksik olan yalnız profil yayını.
  if (profil != null && (profil.isLoading || !profil.hasValue)) {
    return PlusHali.bilinmiyor;
  }
  return PlusHali.abone;
}

/// Yalnız ABONELİK sorusu — doğum verisi beklemeyen yüzeyler için
/// (İ Ching sekmesi, Atlas kehanet karoları, takvim şeridi).
final aboneHaliProvider = Provider<PlusHali>((ref) => plusHaliniOku(
      oturum: ref.watch(authStateProvider),
      abonelik: ref.watch(subscriptionProvider),
    ));

/// Ücretli RAPOR kapısı: abonelik + doğum verisinin gelmiş olması.
///
/// Ekranlar bunu okur, ücretli sağlayıcılar da ([_hasPlus]) buna bakar: "istek
/// atılır mı" ile "ne çizilir" tek kaynaktan karar alır. İki kopya olduğu an
/// ayrışırlardı — şikâyetin kökü tam olarak o ayrışmaydı.
///
/// Satın alma sonrası `subscriptionProvider` sunucu yetkiyi görene kadar
/// birkaç kez geçersizleştiriliyor (`_waitForServerEntitlement`); o pencerede
/// bu kapı `bilinmiyor` döner ve ekranlar iskelet çizer. BİLEREK böyle:
/// eskiden aynı pencerede ekranlar, ödeme biteli saniyeler olmasına rağmen
/// KİLİT çiziyordu.
final raporKapisiProvider = Provider<PlusHali>((ref) => plusHaliniOku(
      oturum: ref.watch(authStateProvider),
      abonelik: ref.watch(subscriptionProvider),
      profil: ref.watch(profileProvider),
    ));

/// Ücretli uca istek ancak kapı KESİN açıkken atılır.
///
/// Atılırsa sunucu 402 döner ve paywall ekran açılır açılmaz kullanıcının
/// yüzüne fırlar. Kilitli içerik kullanıcının dokunmasıyla açılmalı; bu yüzden
/// kapı açık değilken ücretli sağlayıcılar `null` döner.
///
/// `null` artık YALNIZ "kapı abone için açık değil" demek; "abone değil" ile
/// "henüz bilmiyorum" ayrımını ekranlar [raporKapisiProvider]'dan okur.
/// Eski hâl tek satırdı — `subscriptionProvider.value?.active ?? false` — ve
/// yükleniyorken `.value` null olduğu için "abone değil" diyordu. Sağlayıcılar
/// o anda AsyncLoading'de KALMIYOR, `AsyncData(null)` ile tamamlanıyordu: yani
/// ekranların `loading:` dalı hiç koşmuyor, `data:` dalı `null` görüp kilit
/// kartını çiziyordu. Abonelik cevabı gelince kapı açılıyor, sağlayıcılar
/// yeniden kuruluyor ve kilit kayboluyordu — sahibin "ekran açılınca kilitli,
/// bekleyince açılıyor" dediği belirti birebir buydu.
bool _hasPlus(Ref ref) => ref.watch(raporKapisiProvider) == PlusHali.abone;

/// GÜNLÜK bir sağlayıcıyı yerel gün anahtarına bağlar.
///
/// NEDEN gerekli: bu dosyadaki rapor sağlayıcıları düz `FutureProvider` ve
/// varsayılan `isAutoDispose = false` — sonuç OTURUM BOYUNCA önbellekte
/// kalıyor. Sunucu gün dönünce yeni metin üretebilecek durumdayken ekran
/// dünkü metni gösteriyordu: yüzey kullanıcıya göre GÜNLÜK OLMADI. Tek
/// geçersizleştirme yolu [invalidatePlusProviders] ve o yalnız CİHAZ
/// DEVRALMADA ateşleniyor — gün dönümünde hiçbir şey
/// geçersizleştirmiyordu.
///
/// ⚠️ Yüzeyler buraya SAYIYLA yazılmaz. Bu gerekçe bir tur boyunca "üç
/// yüzey" diyordu ve o sayı eksikti: ücretsiz katmanın omurgası olan burç
/// yorumu ile günün sinyal kartları da aynı sınıftaydı, ikisi de
/// listelenmemişti. Bekçi listesi `test/gun_donumu_test.dart`ta tutulur,
/// yorumda değil — yorumdaki sayı kimseyi kırmızıya düşürmez.
///
/// NEDEN dönen değer yok ve `watch` yeterli: anahtar değişince sağlayıcı
/// yeniden kurulur, aynı kaldığı sürece önbellek yaşar. Anahtarı kim
/// ilerletir ve ön plan kancasının kapsamadığı hâl: `core/gun_donumu.dart`.
///
/// ⚠️ Çağrı, varsa KAPIDAN sonra ve istekten ÖNCE yapılır (jetonlu
/// yüzeylerde `_hasPlus`, sinyallerde profil kapısı). Kapıdan önce
/// yazılsaydı hiç istek atmayacak sağlayıcı da gün dönümünde yeniden
/// kurulurdu — zararsız ama ölçülmemiş bir iş. Kapısı OLMAYAN yüzeyde
/// (burç yorumu herkese açık) çağrı gövdenin ilk satırıdır; `ref.watch`
/// ilk `await`ten ÖNCE çağrılmak zorunda, sonrasında bağlanmaz.
void _gunuIzle(Ref ref) => ref.watch(gunAnahtariProvider);

/// Natal harita + derin rapor — Rytho+ .
final natalReportProvider = FutureProvider<Map<String, dynamic>?>((ref) async {
  if (!_hasPlus(ref)) return null;
  final profile = ref.watch(profileProvider).value;
  if (profile == null || profile['onboardingCompleted'] != true) return null;
  final dio = ref.watch(apiProvider);
  // U06: onay yoksa istek ATILMAZ (sağlayıcı AiOnayiGerekli ile düşer,
  // ekran "yapay zeka kapalı" kartını gösterir). `watch`lar await'ten önce.
  await aiOnayiGerektir(ref);
  final response =
      await dio.post('/api/v1/reports/natal', data: birthPayload(profile));
  final veri = Map<String, dynamic>.from(response.data['data']);
  // Yedek metin rapor SAYILMAZ (gz-2): Atlas satiri hata nesnesini
  // `friendlyError`e verip "su an uretemedik / jetonun iade edildi" der.
  // Natal CARKI bu saglayicidan gelmiyor (`natalChartProvider` ayri), yani
  // firlatmak olculmus hicbir seyi goturmuyor.
  if (veri['fallback'] == true) {
    throw RaporUretilemedi(jetonIadeEdildi: veri['refunded'] == true);
  }
  Analytics.reportGenerated('natal');
  return veri;
});

/// BaZi haritası + rapor — Rytho+ .
final baziReportProvider = FutureProvider<Map<String, dynamic>?>((ref) async {
  if (!_hasPlus(ref)) return null;
  // Günün Liu Ri'si burada: BaZi sekmesinde aşağı çekme YOK, yani gün
  // dönümünü kaçıran kullanıcının elinde hiçbir kurtarma yolu kalmıyordu
  // (günlük okumada en azından Gökyüzü'nde aşağı çekme var).
  _gunuIzle(ref);
  final profile = ref.watch(profileProvider).value;
  if (profile == null || profile['onboardingCompleted'] != true) return null;
  final dio = ref.watch(apiProvider);
  // U06: onay yoksa istek ATILMAZ (sağlayıcı AiOnayiGerekli ile düşer,
  // ekran "yapay zeka kapalı" kartını gösterir). `watch`lar await'ten önce.
  await aiOnayiGerektir(ref);
  final response =
      await dio.post('/api/v1/reports/bazi', data: birthPayload(profile));
  final veri = Map<String, dynamic>.from(response.data['data']);
  // BURADA FIRLATILMIYOR — bilincli (gz-2). Yedek metin "uretildi"
  // SAYILMAZ, o yuzden sayac susuyor; ama harita LLM urunu DEGIL:
  // dort sutun, Day Master, gizli kokler, On Tanrilar, guc hukmu, element
  // dagilimi, Shen Sha, sans donemleri — hepsi `get_bazi_chart`in
  // deterministik ciktisi ve ucreti odendi. Firlatsaydik ekran `data` dalina
  // hic girmez, olculmus ve dogru olan her sey silinir, kullanici bos bir
  // hata karti gorurdu. Eksik olan YALNIZ yorum; sekme bayragi gorup onun
  // yerine durust cumleyi koyuyor.
  if (veri['fallback'] != true) Analytics.reportGenerated('bazi');
  return veri;
});

/// Doğum Heksagramı — Rytho+ (Revize İ5): doğum anındaki Güneş boylamının
/// 64 kapı çarkındaki yeri + Rytho okuması.
///
/// ⚠️ Gerekçe DÜZELTİLDİ: burası bir dönem "kalıcı kimlik katmanı" diye
/// anlatılıyordu ve o gerekçe artık yanlış — yük GÜN katmanını da taşıyor
/// (bugünün kapısı). Yanlış gerekçeyi okuyan bir sonraki tur aşağıdaki
/// gün anahtarını gereksiz sanıp söker; kalıcı olan yalnız doğum kapısı.
final birthHexagramProvider =
    FutureProvider<Map<String, dynamic>?>((ref) async {
  if (!_hasPlus(ref)) return null;
  _gunuIzle(ref);
  final profile = ref.watch(profileProvider).value;
  if (profile == null || profile['onboardingCompleted'] != true) return null;
  final dio = ref.watch(apiProvider);
  // U06: onay yoksa istek ATILMAZ (sağlayıcı AiOnayiGerekli ile düşer,
  // ekran "yapay zeka kapalı" kartını gösterir). `watch`lar await'ten önce.
  await aiOnayiGerektir(ref);
  final response = await dio.post('/api/v1/reports/birth-hexagram',
      data: birthPayload(profile));
  final veri = Map<String, dynamic>.from(response.data['data']);
  // Fırlatılmıyor (BaZi emsali): kapı/çizgi/boylam deterministik ve ücreti
  // ödendi; düşen yalnız okuma. Ekran bayrağı `okumaDurumuFromYanit` ile
  // okur. Sayaç yine susar — yedek metin "üretildi" sayılırsa ölçüm yalan.
  if (veri['fallback'] != true) Analytics.reportGenerated('birth_hexagram');
  return veri;
});

/// Yıl Haritası — Rytho+ (T5). Aktif güneş dönüşü + LLM yıl okuması.
/// Sunucu SR yılı boyunca aynı raporu önbellekten servis eder.
final solarReturnProvider =
    FutureProvider<Map<String, dynamic>?>((ref) async {
  if (!_hasPlus(ref)) return null;
  final profile = ref.watch(profileProvider).value;
  if (profile == null || profile['onboardingCompleted'] != true) return null;
  final dio = ref.watch(apiProvider);
  // U06: onay yoksa istek ATILMAZ (sağlayıcı AiOnayiGerekli ile düşer,
  // ekran "yapay zeka kapalı" kartını gösterir). `watch`lar await'ten önce.
  await aiOnayiGerektir(ref);
  final response = await dio.post('/api/v1/reports/solar-return',
      data: birthPayload(profile));
  final veri = Map<String, dynamic>.from(response.data['data']);
  // Dönüş anı ve SR kimliği deterministik; yalnız okuma düşmüş olabilir
  // (bayrağı ekran `okumaDurumuFromYanit` ile okur). Sayaç bayrağa bağlı.
  if (veri['fallback'] != true) Analytics.reportGenerated('solar_return');
  return veri;
});

/// İç Takvim — Rytho+ (T5). İki uç paralel: progresyon okuması (LLM,
/// jetonlu) + 30 günlük ham transit takvimi (jetonsuz; doğum verisi
/// PROFİLDEN okunur, gövde yok).
final innerCalendarProvider =
    FutureProvider<Map<String, dynamic>?>((ref) async {
  if (!_hasPlus(ref)) return null;
  final profile = ref.watch(profileProvider).value;
  if (profile == null || profile['onboardingCompleted'] != true) return null;
  final dio = ref.watch(apiProvider);
  // U06: onay yoksa istek ATILMAZ (sağlayıcı AiOnayiGerekli ile düşer,
  // ekran "yapay zeka kapalı" kartını gösterir). `watch`lar await'ten önce.
  await aiOnayiGerektir(ref);
  final sonuclar = await Future.wait([
    dio.post('/api/v1/reports/progressions', data: birthPayload(profile)),
    dio.get('/api/v1/astrology/transit-calendar'),
  ]);
  final progresyon = Map<String, dynamic>.from(sonuclar[0].data['data']);
  // Bayrak progresyon gövdesinde (`/progressions` D0'dan beri taşıyor);
  // takvim ucu jetonsuz ve bayraksız. Sayaç bayrağa bağlı.
  if (progresyon['fallback'] != true) {
    Analytics.reportGenerated('progressions');
  }
  return {
    'progressions': progresyon,
    'calendar': Map<String, dynamic>.from(sonuclar[1].data['data']),
  };
});

/// Rytho+ uçlarına (`require_plus`) POST atan sağlayıcıların HEPSİ — cihaz
/// devralındıktan sonra tazelenir (`DeviceConflictScreen`, TC-turu).
///
/// Kapı kapanmadan önce ateşlenen istekler 409 ile düştü ve o hata
/// sağlayıcıda ÖNBELLEKTE; `dailyReadingProvider` açılışta kendiliğinden
/// ateşlendiği için ana ekran devralmadan sonra da "hata" gösterirdi.
/// Ekran-yerel çağrılar (sohbet, yüz, iching, dyad) kullanıcı dokununca
/// zaten yeniden dener; burada yalnız sağlayıcıda yaşayanlar. Bu dosyaya
/// yeni bir `reports/` POST sağlayıcısı eklenirse buraya da eklenir.
void invalidatePlusProviders(WidgetRef ref) {
  ref.invalidate(dailyReadingProvider);
  ref.invalidate(natalReportProvider);
  ref.invalidate(baziReportProvider);
  ref.invalidate(birthHexagramProvider);
  ref.invalidate(solarReturnProvider);
  ref.invalidate(innerCalendarProvider);
}

/// 30 günlük transit takvimi — **ücretsiz** (R5-6).
///
/// Ana ekrandaki yatay şeridin kaynağı. Rytho+ kapısı YOK: uç artık
/// herkese açık ve ücretsiz kullanıcıya gerçek tarih + tema döndürüyor,
/// yalnız okuma satırlarını çıkarıp olaya `locked: true` koyuyor
/// ("hesap bedava, yorum paralı"). Bu yüzden abonelik durumu burada
/// KAPI olarak sorulmaz — sorulursa ücretsiz kullanıcı şeridi hiç
/// göremez ve teaser'ın kendisi kaybolur.
///
/// Ama abonelik durumu İZLENİR. Kilit kararını sunucu isteğin geldiği
/// ANDA veriyor; abonelik sonradan başlarsa istemcideki yanıt bayat
/// kalıyor ve kullanıcı parasını ödediği hâlde kilidi görmeye devam
/// ediyordu. Cihaz turunda tam bunu yaşadı: takvim 17:27:26'da
/// çekilmiş, satın alma 17:27:40'ta düşmüş — 14 saniye. Durum
/// değiştiğinde bu sağlayıcı yeniden kurulur ve şerit kilitsiz döner.
final transitCalendarProvider =
    FutureProvider<Map<String, dynamic>?>((ref) async {
  final profile = ref.watch(profileProvider).value;
  if (profile == null || profile['onboardingCompleted'] != true) return null;
  // Cevap BEKLENİR — çift istek burada kesiliyor. Eski kalıp
  // (`select((s) => s.value?.active ?? false)`) yalnız abone OLMAYAN için
  // tek isteğe iniyordu: yükleniyorken `false` okuyup takvimi KİLİTLİ
  // çekiyor, gerçek cevap `true` gelince ikinci kez çekiyordu. Üç durumlu
  // kapıda kilit kararı kesinleşene kadar hiç istek atılmaz; sonra tek istek
  // atılır ve doğru kilit durumuyla döner.
  //
  // Kapı burada KAPI DEĞİL, yalnız bir bekleme koşulu: cevap gelince şerit
  // abone olmayana da açılır (yukarıdaki gerekçe). `null` dönmek şeridi bir
  // an gizler — `CalendarStrip` veri yokken kendini gizliyor — ve kilitli bir
  // şerit göstermekten iyidir: ölçülmeyen söylenmez.
  //
  // ⚠️ Beklenen şey "CEVAP YOLDA", "cevap OKUNAMADI" DEĞİL. `PlusHali`
  // ikisini tek değere indiriyor (`bilinmiyor`) ve o hâli sormak bir tur
  // boyunca ŞU KUSURU üretti: `/billing/status` tek bir zaman aşımına
  // düşünce `bilinmiyor` TERMİNAL oluyor (geniş yakalama `AsyncData`
  // üretiyor, Riverpod yenilemiyor) ve ÜCRETSİZ olan 30 günlük şerit ana
  // ekrandan oturum boyunca KAYBOLUYOR. Üstelik buradaki eski gerekçe
  // "cevap gelince açılır" diyordu — okunamayan cevap hiç gelmez, yani
  // gerekçe yanlıştı.
  //
  // Doğru soru doğrudan kaynağa sorulur: yalnız GERÇEKTEN yükleniyorsa
  // bekle. Durum okunamadıysa istek atılır ve kilit kararını zaten sunucu
  // veriyor — şerit (gerekirse kilitli) GÖRÜNÜR, ki yokluğundan iyidir.
  if (ref.watch(subscriptionProvider).isLoading) return null;
  final dio = ref.watch(apiProvider);
  // U06: onay yoksa `ai=0` — olaylar yorumsuz döner (bkz. sinyaller).
  final response = await dio.get('/api/v1/astrology/transit-calendar',
      queryParameters: await aiSorguParametresi(ref));
  return Map<String, dynamic>.from(response.data['data']);
});
