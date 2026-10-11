// Çevrem / kişi / ilişki bekçilerinin ORTAK harness'ı (D6). `main` YOK —
// bir test dosyası değil, test dosyalarının paylaştığı kurulum.
//
// NEDEN paylaşılıyor: dört ekran (Çevrem, arkadaş, ilişki, kişi) aynı
// sahte sunucuya, aynı yerelleştirme kabuğuna ve aynı 320 dp × 1,3
// ölçütüne bakıyor. Her dosyada kopyalansa dördü zamanla ayrışır
// (`dar_ekran_ekranlar_test` aynı gerekçeyle harness'ını paylaşıyor).
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:rytho/l10n/app_localizations.dart';
import 'package:rytho/main.dart' show kMaxTextScale;
import 'package:rytho/theme/rytho_theme.dart';

/// Yola göre sabit gövde veren sahte sunucu: `yollar` anahtarı isteğin
/// yolunda GEÇİYORSA o gövde döner; yoksa boş nesne. Her yakalanan istek
/// `istekler`e yazılır (hangi uca gidildiği ölçülebilsin).
class SahteAdapter implements HttpClientAdapter {
  SahteAdapter(this.yollar, {this.durum = 200});

  final Map<String, String> yollar;
  final int durum;
  final List<RequestOptions> istekler = [];

  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    istekler.add(options);
    var govde = '{}';
    for (final e in yollar.entries) {
      if (options.path.contains(e.key)) {
        govde = e.value;
        break;
      }
    }
    return ResponseBody.fromString(govde, durum, headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    });
  }

  @override
  void close({bool force = false}) {}
}

Dio sahteDio(SahteAdapter adapter) =>
    Dio(BaseOptions(baseUrl: 'https://test.invalid'))
      ..httpClientAdapter = adapter;

/// İtilen rotaları yakalar: "Rytho'ya sor" dokunuşunun ChatScreen'e NE
/// taşıdığı, rota monte edilmeden (`builder` elle çağrılarak) okunur —
/// ChatScreen'i monte etmek Firebase ister (tohum_gecer_gonderilmez_test
/// gerekçesi).
class RotaGozcusu extends NavigatorObserver {
  final itilenler = <Route<dynamic>>[];

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    itilenler.add(route);
  }
}

/// Uygulama kabuğu: TR yerelleştirme, tema, hareket kapalı (sürekli
/// animatörler — yıldız alanı, usturlap — testte hiç durmaz; ölçülen şey
/// yerleşim ve metin, hareket değil).
Widget sar(
  Widget home, {
  List<Override> overrides = const [],
  NavigatorObserver? gozcu,
  double olcek = 1.0,
}) =>
    ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        locale: const Locale('tr'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: buildRythoTheme(),
        navigatorObservers: gozcu != null ? [gozcu] : const [],
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            disableAnimations: true,
            textScaler: TextScaler.linear(olcek),
          ),
          child: child!,
        ),
        home: home,
      ),
    );

/// Uzun yüzey: `ListView` tembel çizer; dibe yakın blok 800×600'de hiç
/// kurulmaz ve `findsNothing` ölçüm kusuru olurdu.
void uzunYuzey(WidgetTester tester, {double genislik = 420}) {
  tester.view.physicalSize = Size(genislik, 2600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

/// Dar yüzey: 320 dp × 800 dp, `kMaxTextScale` ile birlikte kullanılır.
void darYuzey(WidgetTester tester) {
  tester.view.physicalSize = const Size(320 * 3, 800 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

/// Dar ekran ölçeği — uygulamanın kelepçesiyle aynı sayı.
const double darOlcek = kMaxTextScale;

/// Ağ turunu ve kademeli girişleri bekler. `pumpAndSettle` KULLANILMAZ:
/// sürekli animatörler hiç durmaz.
Future<void> yerles(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 1200));
  await tester.pump(const Duration(milliseconds: 1200));
}

/// Taşma yok mu — Flutter taşmayı çizim anında fırlatır.
void tasmaYok(WidgetTester tester, {String? neden}) {
  expect(tester.takeException(), isNull, reason: neden);
}

/// Listeyi aşağı kaydırıp her adımda taşma arar: tembel liste dibini ancak
/// kaydırınca çizer.
Future<void> kaydirarakTasmaAra(WidgetTester tester, Finder liste,
    {int adim = 4, String? neden}) async {
  for (var i = 0; i < adim; i++) {
    await tester.drag(liste, const Offset(0, -500));
    await tester.pump();
    tasmaYok(tester, neden: neden);
    // Sürükleme çarkın çift-dokunuş tanıyıcısına düşebilir; onun bekleme
    // sayacı test sonunda "pending timer" olarak kalırdı (ölçüldü).
    await tester.pump(const Duration(milliseconds: 400));
  }
}
