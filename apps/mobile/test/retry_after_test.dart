// 429 / Retry-After ve 402 X-Paywall-Feature bekçileri (D6, §9).
//
// Ölçülen üç kusur:
// 1. `friendlyError` 429'u görmüyordu: sunucu "30 saniye sonra" demişken
//    kullanıcı genel `detail` cümlesini ya da "beklenmeyen sorun"u okuyor,
//    NE ZAMAN deneyeceğini öğrenemiyordu. Bekleme bitişi hiçbir yere not
//    edilmiyordu (`kotaBeklemeProvider` yoktu).
// 2. `abonelikDurumunuOku` 429'u "hızlı, onarılabilir" sayıp 600 ms sonra
//    ikinci isteği atıyordu — sunucu "yavaşla" demişken kotayı besliyordu.
// 3. `X-Paywall-Feature` başlığı hiç okunmuyordu; satış ekranı her kilitte
//    aynı genel cümleyi gösteriyordu.
//
// Interceptor ölçümleri GERÇEK `apiProvider` üzerinde (cuzdan_tazeleme_test
// deseni): sahte bir kopya değil, gerçek `ref` kapanışı koşuyor. `Future
// .timeout` ile kesilen akışın `TimeoutException`ı da burada: "bağlantı
// yok" demekken "beklenmeyen sorun" diyordu.
import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show Uint8List;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rytho/core/api.dart';
import 'package:rytho/core/subscription.dart'
    show SubscriptionStatus, abonelikDurumunuOku;
import 'package:rytho/features/paywall/ozellik_katalogu.dart';
import 'package:rytho/features/paywall/paywall_acilis.dart';
import 'package:rytho/features/paywall/paywall_screen.dart';
import 'package:rytho/l10n/app_localizations_en.dart';
import 'package:rytho/l10n/app_localizations_tr.dart';

final _tr = AppLocalizationsTr();
final _en = AppLocalizationsEn();

DioException _hata(int kod,
    {Map<String, List<String>> basliklar = const {},
    Object? govde,
    String yol = '/api/v1/chat'}) {
  final istek = RequestOptions(path: yol);
  return DioException(
    requestOptions: istek,
    type: DioExceptionType.badResponse,
    response: Response(
      requestOptions: istek,
      statusCode: kod,
      data: govde,
      headers: Headers.fromMap(basliklar),
    ),
  );
}

/// Hatayı GERÇEK interceptor zincirinden geçirir.
///
/// `handler.next(hata)` işleyicinin kendi future'ını HATAYLA tamamlar
/// (Dio'nun zincir sözleşmesi); kimse beklemeyince bölge onu "yakalanmamış
/// hata" sayıp testi düşürür. O future `@protected` (dışarıdan yok
/// sayılamaz); işleyici korumalı bir bölgede kurulur ki hatası oraya
/// düşsün. Ölçülen şey yan etki, zincirin sonucu değil.
void _hatayiGecir(Dio dio, DioException e) {
  for (final i in dio.interceptors) {
    runZonedGuarded(() => i.onError(e, ErrorInterceptorHandler()), (_, _) {});
  }
}

/// İstekleri sayan, sabit durum döndüren sahte sunucu.
class _SayanAdapter implements HttpClientAdapter {
  _SayanAdapter(this.durum);
  final int durum;
  int istek = 0;

  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    istek++;
    return ResponseBody.fromString('{}', durum, headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
      if (durum == 429) 'retry-after': ['30'],
    });
  }

  @override
  void close({bool force = false}) {}
}

class _RotaGozcusu extends NavigatorObserver {
  final itilenler = <Route<dynamic>>[];

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    itilenler.add(route);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('retryAfterSaniye', () {
    test('saniye okunur, boşluk tolere edilir', () {
      expect(retryAfterSaniye(Headers.fromMap({'retry-after': ['30']})), 30);
      expect(retryAfterSaniye(Headers.fromMap({'Retry-After': [' 12 ']})), 12);
    });

    test('yok / sayı değil / sıfır → null (süre uydurulmaz)', () {
      expect(retryAfterSaniye(null), isNull);
      expect(retryAfterSaniye(Headers()), isNull);
      expect(retryAfterSaniye(Headers.fromMap({'retry-after': ['abc']})),
          isNull);
      expect(retryAfterSaniye(
              Headers.fromMap({'retry-after': ['Wed, 21 Oct 2015 07:28:00 GMT']})),
          isNull);
      expect(retryAfterSaniye(Headers.fromMap({'retry-after': ['0']})), isNull);
    });
  });

  group('friendlyError', () {
    test('429 + Retry-After 30 → "{n} sn sonra tekrar dene"', () {
      final e = _hata(429,
          basliklar: {'retry-after': ['30']},
          govde: {'detail': 'Yoğun talep'});
      expect(friendlyError(e, _tr), _tr.retryAfterSeconds(30));
      expect(friendlyError(e, _tr), contains('30'));
      // Sunucunun genel cümlesi DEĞİL, sayı: kullanıcı ne zaman deneyeceğini
      // öğrenir.
      expect(friendlyError(e, _tr), isNot('Yoğun talep'));
    });

    test('İngilizce arayüzde çoğul doğru, Türkçe sızmaz', () {
      final e = _hata(429, basliklar: {'retry-after': ['30']});
      expect(friendlyError(e, _en), _en.retryAfterSeconds(30));
      expect(friendlyError(e, _en), isNot(contains('sn sonra')));
      expect(friendlyError(_hata(429, basliklar: {'retry-after': ['1']}), _en),
          contains('1 second'));
    });

    test('başlıksız 429 detail yoluna düşer, süre uydurulmaz', () {
      expect(friendlyError(_hata(429, govde: {'detail': 'Yoğun talep'}), _tr),
          'Yoğun talep');
      expect(friendlyError(_hata(429), _tr), _tr.errorGeneric);
    });

    test('TimeoutException → bağlantı metni (beklenmeyen sorun DEĞİL)', () {
      // Profil akışının 12 sn `Future.timeout`u Dio dışında düşer.
      expect(friendlyError(TimeoutException('12 sn'), _tr),
          _tr.errorConnection);
      expect(friendlyError(TimeoutException('12 sn'), _en),
          _en.errorConnection);
    });
  });

  group('GERÇEK apiProvider — 429 bekleme notu', () {
    test('Retry-After → kotaBeklemeProvider bitiş anı', () {
      final kap = ProviderContainer();
      addTearDown(kap.dispose);
      final dio = kap.read(apiProvider);
      expect(kap.read(kotaBeklemeProvider), isNull);

      final once = DateTime.now();
      _hatayiGecir(dio, _hata(429, basliklar: {'retry-after': ['30']}));

      final bitis = kap.read(kotaBeklemeProvider);
      expect(bitis, isNotNull, reason: 'interceptor bekleme anını yazmadı');
      final kalan = bitis!.difference(once).inMilliseconds;
      expect(kalan, inInclusiveRange(29000, 31000));
    });

    test('başlıksız 429 not düşmez — süresi bilinmeyen bekleme ilan edilmez',
        () {
      final kap = ProviderContainer();
      addTearDown(kap.dispose);
      _hatayiGecir(kap.read(apiProvider), _hata(429));
      expect(kap.read(kotaBeklemeProvider), isNull);
    });

    test('429 olmayan hata notu ilgilendirmez', () {
      final kap = ProviderContainer();
      addTearDown(kap.dispose);
      _hatayiGecir(kap.read(apiProvider),
          _hata(500, basliklar: {'retry-after': ['30']}));
      expect(kap.read(kotaBeklemeProvider), isNull);
    });
  });

  group('abonelikDurumunuOku — 429 ikinci hızlı denemeyi YAPMAZ', () {
    Dio dio(_SayanAdapter a) =>
        Dio(BaseOptions(baseUrl: 'https://test.invalid'))..httpClientAdapter = a;

    test('429: TEK istek, bilinmiyor', () async {
      final a = _SayanAdapter(429);
      final durum = await abonelikDurumunuOku(dio(a));
      expect(durum, SubscriptionStatus.bilinmiyor);
      expect(a.istek, 1, reason: 'sunucu "yavaşla" demişken ikinci istek '
          'kotayı kendisi besler');
    });

    test('5xx: hızlı yeniden deneme KORUNUR (iki istek)', () async {
      final a = _SayanAdapter(500);
      await abonelikDurumunuOku(dio(a));
      expect(a.istek, 2);
    });
  });

  // ⚠️ Bu test dosyanın SONUNDA ve TEK: itilen satış rotası hiç
  // kapanmıyor (paywall çizdirilmez — mağaza sağlayıcıları ister), yani
  // `api.dart`taki yeniden giriş bayrağı bu izolatta açık kalır ve ikinci
  // bir 402 itme testi sessizce "atlandı" olurdu.
  testWidgets('402 + X-Paywall-Feature → acPaywall(ozellik:) kesinti rotası',
      (tester) async {
    final kap = ProviderContainer();
    addTearDown(kap.dispose);
    final gozcu = _RotaGozcusu();
    await tester.pumpWidget(UncontrolledProviderScope(
      container: kap,
      child: MaterialApp(
        navigatorKey: rythoNavigatorKey,
        navigatorObservers: [gozcu],
        home: const SizedBox(),
      ),
    ));

    _hatayiGecir(
        kap.read(apiProvider),
        _hata(402,
            basliklar: {'x-paywall-feature': ['bazi']},
            govde: {'detail': 'BaZi Rytho+ ile açılır.'},
            yol: '/api/v1/reports/bazi'));

    expect(gozcu.itilenler.length, 2, reason: 'ana rota + satış rotası');
    final rota = gozcu.itilenler.last;
    expect(rota, isA<MaterialPageRoute<bool>>());
    expect((rota as MaterialPageRoute<bool>).fullscreenDialog, isTrue,
        reason: '402 bir KESİNTİ: tam ekran diyalog, kapatma düğmesi');
    final ekran = rota.builder(tester.element(find.byType(SizedBox)));
    expect(ekran, isA<PaywallScreen>());
    final paywall = ekran as PaywallScreen;
    expect(paywall.ozellik, PlusOzellik.bazi,
        reason: 'X-Paywall-Feature okunmadı; satış ekranı genel cümleye düşer');
    expect(paywall.kaynak, PaywallKaynak.kilit402);
    expect(paywall.reason, 'BaZi Rytho+ ile açılır.');

    // Satış ekranı ÇİZDİRİLMEDEN ağaç sökülür.
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
