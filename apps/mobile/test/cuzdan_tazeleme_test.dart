// Bulgu B10 bekçileri — para UX'i: bayat bakiye ve ödemiş kullanıcıya paywall.
//
// Bu dosyanın var olma sebebi bulgunun kendi notunda yazılı: "Neden hiçbir
// bekçi görmedi: on üç testin hepsi geri çağrıyı ENJEKTE ediyor
// (`() async => true`), gerçek `ref` kapanışı hiçbir yerde koşmuyor." Bu yüzden
// aşağıdaki testler GERÇEK `apiProvider`ı gerçek bir `ProviderContainer`da
// kuruyor, cüzdanı CANLI hâle getiriyor (halkanın kurulduğu tek durum) ve
// interceptor'ın KENDİ kapanışını çağırıyor. Halkanın kurulmadığı ölçülerek
// kanıtlanıyor, varsayılmıyor.
//
// Sabitlenen sözleşmeler:
// 1. Harcama yanıtından sonra bakiye YENİDEN SORULUR (sayaç → walletProvider).
// 2. Sayaç bayrak DEĞİL: ikinci harcama da tazeler.
// 3. Abonelik aynası sunucunun `/billing/status` GÖVDESİNDEN dolar.
// 4. 402 üç yollu dağıtılır; `people` + abone → satış ekranı AÇILMAZ.
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rytho/core/api.dart'
    show PaywallHedefi, apiProvider, paywallHedefi;
import 'package:rytho/core/subscription.dart'
    show aboneAynasiProvider, abonelikDurumuYaniti, aynadakiAbonelik;
import 'package:rytho/core/wallet.dart'
    show cuzdanDegismisOlabilir, cuzdanTazelemeProvider, walletProvider;

const _kCuzdanYolu = '/api/v1/billing/wallet';
const _kDurumYolu = '/api/v1/billing/status';

/// Cüzdan gövdesi (`api/billing.WalletStatus` ile aynı şekil).
const _kCuzdanGovdesi = {
  'allowance': 12,
  'purchased': 0,
  'total': 12,
  'monthly_allowance': 300,
  'costs': {'natal': 5, 'chat': 1},
};

/// Ağa ÇIKMAYAN sahte sunucu: her isteği kaydeder ve yerinde yanıtlar.
///
/// `handler.resolve` isteği zincirin BAŞINDA bitiriyor; böylece gerçek
/// `apiProvider`ın kimlik interceptor'ı (`FirebaseAuth.instance`) hiç
/// koşmuyor — Firebase'siz bir birim testinde o satır fırlatırdı ve ölçüm
/// gerçek sağlayıcı yerine enjekte edilmiş bir kopya üzerinden yapılmak
/// zorunda kalırdı. Yanıt interceptor'ları BİLEREK çağrılmıyor (ikinci
/// parametre `false`): onları testin kendisi, tek tek ve görünür biçimde
/// tetikliyor.
Interceptor _sahteSunucu(List<RequestOptions> kayit) => InterceptorsWrapper(
      onRequest: (options, handler) {
        kayit.add(options);
        handler.resolve(Response(
          requestOptions: options,
          statusCode: 200,
          data: options.path == _kDurumYolu
              ? const {'active': true}
              : _kCuzdanGovdesi,
        ));
      },
    );

Response<dynamic> _yanit(String yol,
        {String metot = 'POST', Object? govde}) =>
    Response<dynamic>(
      requestOptions: RequestOptions(path: yol, method: metot),
      statusCode: 200,
      data: govde,
    );

/// Yanıtı GERÇEK interceptor zincirinden geçirir.
///
/// Sıraya bel bağlanmıyor: `apiProvider`ın dört interceptor'ının üçü yalnız
/// istek/hata tarafını kuruyor, onların `onResponse`u varsayılan geçiştir.
/// Böylece api.dart'ta interceptor sırası değişse de bekçi ölçmeye devam eder.
void _yanitiGecir(Dio dio, Response<dynamic> yanit) {
  for (final i in dio.interceptors) {
    i.onResponse(yanit, ResponseInterceptorHandler());
  }
}

// Halka ŞEKİL KOPYASI (gerçek sağlayıcılar değil): `_halkaB` gövdesinde
// `_halkaA`yı izliyor, `_halkaA`nın kapanışı `_halkaB`yi invalidate ediyor —
// `walletProvider`/`apiProvider` ikilisinin aynı şekli. Deponun KENDİ Riverpod
// sürümünde ölçmek için var: sayacın gerekçesi folklor değil, koşan bir ölçüm.
// Degisken turleri ACIK yazilmak ZORUNDA: jenerik argumani vermek yetmiyor,
// analizci yine `top_level_cycle` diyor. Bulgu B10 tam bunu soyluyor — ve o
// hatayi kapatmak CALISMA ANINDAKI halkayi kapatmiyor (asagidaki test onu
// olcuyor).
final Provider<void Function()> _halkaA =
    Provider<void Function()>((ref) => () => ref.invalidate(_halkaB));
final FutureProvider<int> _halkaB = FutureProvider<int>((ref) async {
  ref.watch(_halkaA);
  return 0;
});

int _cuzdanOkumasi(List<RequestOptions> kayit) =>
    kayit.where((o) => o.path == _kCuzdanYolu).length;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('cuzdanDegismisOlabilir — yol kuralı', () {
    bool q(String yol, [String metot = 'POST']) =>
        cuzdanDegismisOlabilir(RequestOptions(path: yol, method: metot));

    test('jeton harcayan on ucun hepsi eşleşir', () {
      // Sunucudaki TOKEN_COSTS'un istemciye bakan yüzü (core/wallet.py).
      for (final yol in [
        '/api/v1/chat',
        '/api/v1/reports/iching',
        '/api/v1/reports/dyad',
        '/api/v1/reports/natal',
        '/api/v1/reports/bazi',
        '/api/v1/reports/synastry',
        '/api/v1/reports/birth-hexagram',
        '/api/v1/reports/solar-return',
        '/api/v1/reports/progressions',
        '/api/v1/face/reading',
      ]) {
        expect(q(yol), isTrue, reason: yol);
      }
    });

    test('jeton YÜKLEYEN ortak kodu da tazeler', () {
      // Bakiyeyi artıran tek istemci yolu; burası da hiç tazelemiyordu.
      expect(q('/api/v1/billing/redeem-code'), isTrue);
    });

    test('cüzdanın KENDİ okuması eşleşmez — yoksa istek sonsuza dönerdi', () {
      expect(q(_kCuzdanYolu, 'GET'), isFalse);
      expect(q(_kCuzdanYolu), isFalse);
      expect(q(_kDurumYolu, 'GET'), isFalse);
    });

    test('jeton harcamayan yollar eşleşmez (boşuna Firestore okuması yok)', () {
      expect(q('/api/v1/astrology/natal-chart'), isFalse);
      expect(q('/api/v1/astrology/synastry'), isFalse);
      expect(q('/api/v1/people'), isFalse);
      expect(q('/api/v1/account/diary'), isFalse);
      expect(q('/api/v1/notify/invite'), isFalse);
      expect(q('/api/v1/device/claim'), isFalse);
      expect(q('/api/v1/face/consent'), isFalse);
      // GET olan rapor uçları harcamaz.
      expect(q('/api/v1/reports/horoscope/aries', 'GET'), isFalse);
      expect(q('/api/v1/reports/iching/status', 'GET'), isFalse);
    });

    test('sorgu dizesi eşleşmeyi bozmaz, küçük harf metot da', () {
      expect(q('/api/v1/reports/natal?v=2'), isTrue);
      expect(q('/api/v1/chat', 'post'), isTrue);
    });
  });

  group('GERÇEK apiProvider — halka kurulmuyor', () {
    test('harcama yanıtı: sayaç artar ve bakiye YENİDEN SORULUR', () async {
      final kap = ProviderContainer();
      addTearDown(kap.dispose);

      final dio = kap.read(apiProvider); // gerçek sağlayıcı, gerçek ref
      final kayit = <RequestOptions>[];
      dio.interceptors.insert(0, _sahteSunucu(kayit));

      // Cüzdan CANLI: bulgunun ölçümü tam bu durumda fırlıyordu
      // ("ref.invalidate(b) → b CANLI ise CircularDependencyError").
      final ilk = await kap.read(walletProvider.future);
      expect(ilk.total, 12);
      expect(_cuzdanOkumasi(kayit), 1);
      final abone = kap.listen(walletProvider, (_, _) {});
      addTearDown(abone.close);

      // Rapor üretildi: 5 jeton düştü. Yanıt GERÇEK interceptor kapanışından
      // geçiyor — halka kurulsaydı burada CircularDependencyError düşerdi.
      _yanitiGecir(dio, _yanit('/api/v1/reports/natal'));

      expect(kap.read(cuzdanTazelemeProvider), 1,
          reason: 'interceptor sayaca yazamadı');
      // Tazeleme beklenerek ölçülüyor: sağlayıcı kirli DEĞİLSE bu okuma
      // önbellekteki future'ı döner ve sayı 1'de kalır — yani iddia
      // "tazelendi" olmadan geçemez.
      await kap.read(walletProvider.future);
      expect(_cuzdanOkumasi(kayit), 2,
          reason: 'harcamadan sonra bakiye yeniden sorulmadı — çip bayat '
              'kalırdı (bulgu B10 semptom a)');
    });

    test('SAYAÇ, bayrak değil: ikinci harcama da tazeler', () async {
      final kap = ProviderContainer();
      addTearDown(kap.dispose);
      final dio = kap.read(apiProvider);
      final kayit = <RequestOptions>[];
      dio.interceptors.insert(0, _sahteSunucu(kayit));
      await kap.read(walletProvider.future);
      final abone = kap.listen(walletProvider, (_, _) {});
      addTearDown(abone.close);

      for (var i = 0; i < 2; i++) {
        _yanitiGecir(dio, _yanit('/api/v1/chat'));
        await kap.read(walletProvider.future);
      }
      // `bool` bayrak olsaydı ikinci tur `true`→`true` olurdu: Riverpod
      // "değişmedi" sayar ve bakiye 2'de kalırdı.
      expect(kap.read(cuzdanTazelemeProvider), 2);
      expect(_cuzdanOkumasi(kayit), 3);
    });

    test('harcamayan yanıt boşuna tazelemez', () async {
      final kap = ProviderContainer();
      addTearDown(kap.dispose);
      final dio = kap.read(apiProvider);
      final kayit = <RequestOptions>[];
      dio.interceptors.insert(0, _sahteSunucu(kayit));
      await kap.read(walletProvider.future);
      final abone = kap.listen(walletProvider, (_, _) {});
      addTearDown(abone.close);

      _yanitiGecir(dio, _yanit('/api/v1/astrology/natal-chart'));
      await kap.read(walletProvider.future);
      expect(kap.read(cuzdanTazelemeProvider), 0);
      expect(_cuzdanOkumasi(kayit), 1);
    });

    test('abonelik aynası GERÇEK yanıt gövdesinden dolar', () async {
      final kap = ProviderContainer();
      addTearDown(kap.dispose);
      final dio = kap.read(apiProvider);
      dio.interceptors.insert(0, _sahteSunucu(<RequestOptions>[]));

      expect(kap.read(aboneAynasiProvider), isNull,
          reason: 'okunmadan önce BİLİNMİYOR olmalı');
      _yanitiGecir(
          dio, _yanit(_kDurumYolu, metot: 'GET', govde: {'active': true}));
      expect(kap.read(aboneAynasiProvider), isTrue);

      // Sonraki okuma "abone değil" derse ayna da düşer (abonelik bitti).
      _yanitiGecir(
          dio, _yanit(_kDurumYolu, metot: 'GET', govde: {'active': false}));
      expect(kap.read(aboneAynasiProvider), isFalse);
    });
  });

  group('halka GERÇEK — sayacın var olma sebebi', () {
    test('izlenen sağlayıcının kapanışından invalidate ÇALIŞMA ANINDA düşer',
        () async {
      final kap = ProviderContainer();
      addTearDown(kap.dispose);
      final kapanis = kap.read(_halkaA);
      await kap.read(_halkaB.future); // izlenen taraf CANLI
      expect(kapanis, throwsA(isA<Error>()),
          reason: 'bu düşüş olmasaydı interceptor doğrudan '
              'ref.invalidate(walletProvider) diyebilirdi');
    });

    test('hiçbir şeyi İZLEMEYEN sağlayıcıya yazmak düşmez', () async {
      // Sayacın deseni: yazan taraf okunan tarafça izlenmiyor.
      final sayac = Provider<void Function()>(
          (ref) => () => ref.read(cuzdanTazelemeProvider.notifier).state++);
      final kap = ProviderContainer();
      addTearDown(kap.dispose);
      final yaz = kap.read(sayac);
      await kap.read(walletProvider.future);
      expect(yaz, returnsNormally);
    });
  });

  group('paywallHedefi — 402 üç yollu', () {
    test('tokens → jeton mağazası (abonelikten bağımsız)', () {
      for (final abone in [true, false, null]) {
        expect(paywallHedefi('tokens', abone: abone),
            PaywallHedefi.jetonMagazasi);
      }
    });

    test('başlıksız 402 → satış ekranı; ayna SORULMAZ', () {
      // Sunucu "Plus gerekiyor" diyorken ayna `true` ise ayna bayattır
      // (abonelik düşmüş olabilir) ve doğru cevap yine satış ekranıdır.
      for (final abone in [true, false, null]) {
        expect(paywallHedefi(null, abone: abone), PaywallHedefi.abonelik);
      }
    });

    test('people + ÜCRETSİZ → satış ekranı (sunucu metni de Rytho+ diyor)',
        () {
      expect(paywallHedefi('people', abone: false), PaywallHedefi.abonelik);
    });

    test('people + ABONE → satış ekranı AÇILMAZ, sunucu metni gösterilir', () {
      // Ödemiş kullanıcıya paywall (bulgu B10 semptom b): sunucu ona
      // `people.limit_plus` ("listeden bir kişiyi çıkarabilirsin") diyorken
      // istemci tam ekran "Rytho+ al" sayfası açıyordu.
      expect(paywallHedefi('people', abone: true), PaywallHedefi.mesaj);
    });

    test('people + BİLİNMİYOR → satmıyoruz', () {
      // Sunucunun metni iki durumda da doğru; satış ekranı yalnız birinde.
      expect(paywallHedefi('people', abone: null), PaywallHedefi.mesaj);
    });

    test('tanınmayan sebep satış ekranına düşer (bugünkü davranış korunur)',
        () {
      expect(paywallHedefi('gelecekteki-sebep', abone: true),
          PaywallHedefi.abonelik);
    });
  });

  group('ayna süzgeçleri', () {
    test('yalnız /billing/status yanıtı aynayı ilgilendirir', () {
      expect(abonelikDurumuYaniti(RequestOptions(path: _kDurumYolu)), isTrue);
      expect(abonelikDurumuYaniti(RequestOptions(path: _kCuzdanYolu)), isFalse);
      expect(abonelikDurumuYaniti(RequestOptions(path: '/api/v1/chat')),
          isFalse);
    });

    test('eksik/bozuk gövde "abone değil" DEMEK DEĞİL — null', () {
      expect(aynadakiAbonelik(const {'active': true}), isTrue);
      expect(aynadakiAbonelik(const {'active': false}), isFalse);
      expect(aynadakiAbonelik(const {'product_id': 'x'}), isNull);
      expect(aynadakiAbonelik('patladı'), isNull);
      expect(aynadakiAbonelik(null), isNull);
    });
  });
}
