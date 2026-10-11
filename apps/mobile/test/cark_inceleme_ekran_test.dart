// Harita İnceleme — GERÇEK AĞAÇ bekçileri (D6, gökyüzü kipi).
//
// `anlam_once_test` bu ekranı kaynaktan çiviler çünkü natal kipi
// Firebase/profil sağlayıcılarını ister. Gökyüzü kipi öyle değil: tek
// bağımlılığı `skyNowProvider` ve o bir `FutureProvider` — üzerine yazılır,
// ekran gerçekten kurulur. Burada davranış ölçülür: hata → ErrorCard ve
// tekrar dene sağlayıcıyı GERÇEKTEN tazeler; bekleme metni kipe göre;
// gezegene dokununca seçim çubuğu ve görünür "Seçimi kaldır"; açı
// tablosunda ⚹ metin glifi; 320 dp × 1,3'te gövdenin sonuna kadar taşma
// yok (liste tembel kurar, sona kaydırılmadan ölçülmüş sayılmaz).
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:rytho/core/providers.dart';
import 'package:rytho/features/atlas/chart_inspector_screen.dart';
import 'package:rytho/l10n/app_localizations.dart';
import 'package:rytho/l10n/app_localizations_tr.dart';
import 'package:rytho/main.dart' show rythoRetry;
import 'package:rytho/theme/rytho_theme.dart';
import 'package:rytho/widgets/atlas_widgets.dart' show RythoyaSor;
import 'package:rytho/widgets/chart/aci_lejanti.dart';
import 'package:rytho/widgets/chart/chart_data.dart';
import 'package:rytho/widgets/chart/chart_wheel.dart';
import 'package:rytho/widgets/chart/wheel_layout.dart';
import 'package:rytho/widgets/common.dart' show ErrorCard;

final _tr = AppLocalizationsTr();

/// GET /sky/now yükü — `ChartData.fromSky` sözleşmesi. Bir karşıt
/// (`movement` taşır → Y/A dipnotu), bir altmışlık (⚹ hücresi).
final _gokyuzu = <String, dynamic>{
  'timestamp_utc': '2026-10-10T09:00:00Z',
  'moon_phase': {'emoji': '🌒', 'name': 'Hilal', 'illumination': '%18'},
  'retrogrades': <String>[],
  'planets': [
    {'name': 'Sun', 'name_local': 'Güneş', 'longitude': 197.2,
      'sign': 'libra', 'degree_in_sign': 17.2},
    {'name': 'Moon', 'name_local': 'Ay', 'longitude': 40.5,
      'sign': 'taurus', 'degree_in_sign': 10.5},
    {'name': 'Saturn', 'name_local': 'Satürn', 'longitude': 2.1,
      'sign': 'aries', 'degree_in_sign': 2.1},
  ],
  'aspects': [
    {'p1': 'Sun', 'p2': 'Saturn', 'aspect': 'opposition', 'orb': 4.9,
      'p1_local': 'Güneş', 'p2_local': 'Satürn', 'aspect_local': 'Karşıt',
      'movement': 'applying'},
    {'p1': 'Moon', 'p2': 'Saturn', 'aspect': 'sextile', 'orb': 1.6,
      'p1_local': 'Ay', 'p2_local': 'Satürn', 'aspect_local': 'Altmışlık'},
  ],
};

/// [yuk]: `GET /sky/now`un yerine geçen gelecek — hata, bekleme ve veri
/// dalları buradan kurulur (tür adı yazılmaz: Riverpod sürümüne bağlı).
Widget _sar(Widget child,
        {required Future<Map<String, dynamic>> Function() yuk,
        double olcek = 1.0}) =>
    ProviderScope(
      // ÜRETİMLE AYNI yeniden deneme politikası (`main.dart`): düşen
      // sağlayıcı iki kez kendiliğinden denenir (400 + 800 ms) ve o sırada
      // ekran bekleme aşamasında kalır; hata kartı ancak ondan SONRA
      // gelir. Politikasız bir kapsam bu sırayı ölçmezdi.
      retry: rythoRetry,
      overrides: [skyNowProvider.overrideWith((ref) => yuk())],
      child: MaterialApp(
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('tr'),
        theme: buildRythoTheme(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(olcek),
            disableAnimations: true,
          ),
          child: child!,
        ),
        home: child,
      ),
    );

/// Telefon boyu: 400 × 1200 (dpr 3) — çark, lejant ve açı tablosu tek
/// görünümde kurulsun, dokunuş hedefi ekran dışına düşmesin.
void _telefon(WidgetTester tester, {double genislik = 400}) {
  tester.view.physicalSize = Size(genislik * 3, 1200 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

Future<void> _kur(WidgetTester tester,
    {required Future<Map<String, dynamic>> Function() yuk,
    double olcek = 1.0}) async {
  await tester.pumpWidget(_sar(
      const ChartInspectorScreen(mode: ChartInspectorMode.sky),
      yuk: yuk,
      olcek: olcek));
  await tester.pump();
  await tester.pump();
}

Future<Map<String, dynamic>> _hazir() async => _gokyuzu;

void main() {
  GoogleFonts.config.allowRuntimeFetching = false;

  group('hata ≠ boş', () {
    testWidgets('sağlayıcı düşünce (kendiliğinden denemeler tükenince) '
        'ErrorCard; tekrar dene sağlayıcıyı tazeler ve çark gelir',
        (tester) async {
      _telefon(tester);
      var cagri = 0;
      // İlk çağrı + rythoRetry'nin iki denemesi düşer; dördüncü çağrı
      // yalnız kullanıcının "Tekrar dene"siyle gelir ve başarır.
      await _kur(tester, yuk: () async {
        cagri++;
        if (cagri <= 3) throw Exception('gökyüzü kopuk');
        return _gokyuzu;
      });
      // Denemeler sürerken bekleme aşaması, hata kartı DEĞİL.
      expect(find.text(_tr.chartLoading), findsOneWidget);
      expect(find.byType(ErrorCard), findsNothing);
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 800));
      await tester.pump();
      await tester.pump();
      expect(cagri, 3, reason: 'yeniden deneme politikası üretimle aynı değil');
      expect(find.byType(ErrorCard), findsOneWidget,
          reason: 'hata boş gövdeye düşüyor');
      expect(find.byType(ChartWheel), findsNothing);

      await tester.tap(find.text(_tr.retry));
      await tester.pump();
      await tester.pump();
      expect(cagri, 4, reason: 'tekrar dene sağlayıcıyı tazelemedi');
      expect(find.byType(ErrorCard), findsNothing);
      expect(find.byType(ChartWheel), findsOneWidget);
    });
  });

  group('bekleme metni kipe göre', () {
    testWidgets('gökyüzü kipinde "Çark hazırlanıyor", dış halka DEĞİL',
        (tester) async {
      _telefon(tester);
      // Hiç dolmayan gelecek: ekran bekleme durumunda kalır.
      final bekle = Completer<Map<String, dynamic>>();
      await _kur(tester, yuk: () => bekle.future);
      expect(find.text(_tr.chartLoading), findsOneWidget);
      expect(find.text(_tr.chartOuterLoading), findsNothing,
          reason: 'tek halkalı kipte olmayan dış halka bekleniyor');
      // Bekleme animatörü sökülsün — sarkan zamanlayıcı testi düşürür.
      await tester.pumpWidget(const SizedBox());
    });
  });

  group('gövde', () {
    testWidgets('lejant: açı sınıfı satırı + Y/A dipnotu (hareket ölçülü)',
        (tester) async {
      _telefon(tester);
      await _kur(tester, yuk: _hazir);
      expect(find.byType(AciSinifiLejanti), findsOneWidget);
      expect(find.text(_tr.chartMovementLegend), findsOneWidget,
          reason: 'karşıt açı `movement` taşıyor — dipnot basılmalı');
    });

    testWidgets('açı tablosunda altmışlık METİN glifi ⚹ (vektör dalı yok)',
        (tester) async {
      _telefon(tester);
      await _kur(tester, yuk: _hazir);
      expect(find.text('⚹'), findsOneWidget);
    });

    testWidgets('gezegene dokunuş → seçim çubuğu + görünür "Seçimi kaldır"; '
        'basınca seçim kalkar', (tester) async {
      _telefon(tester);
      await _kur(tester, yuk: _hazir);
      expect(find.byTooltip(_tr.chartSelectionClear), findsNothing);

      // Güneş'in GERÇEK yerleşimi (isabet == çizim): çarkın kendi boyutuyla.
      final cark = tester.widget<ChartWheel>(find.byType(ChartWheel));
      final veri = ChartData.fromSky(_gokyuzu, label: 'x');
      final layout = WheelLayout.compute(Size.square(cark.size), veri);
      final gunes =
          layout.placements.first.firstWhere((g) => g.point.name == 'Sun');
      await tester.tapAt(
          tester.getTopLeft(find.byType(ChartWheel)) + gunes.center);
      // onDoubleTap kayıtlı: tekli dokunuş çift-dokunuş zaman aşımından sonra.
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();

      final kaldir = find.byTooltip(_tr.chartSelectionClear);
      expect(kaldir, findsOneWidget,
          reason: 'seçim çubuğu ya da kaldırma düğmesi yok');
      await tester.tap(kaldir);
      await tester.pump();
      expect(find.byTooltip(_tr.chartSelectionClear), findsNothing,
          reason: 'kaldır düğmesi seçimi temizlemiyor');
    });

    testWidgets('320 dp × 1,3: gövdenin SONUNA kadar taşma yok, '
        '"Rytho\'ya sor" en altta kuruluyor', (tester) async {
      _telefon(tester, genislik: 320);
      await _kur(tester, yuk: _hazir, olcek: 1.3);
      expect(tester.takeException(), isNull, reason: 'üst gövde taşıyor');
      expect(find.byType(ChartWheel), findsOneWidget);
      // Liste tembel: alt kalemler kaydırılmadan hiç kurulmaz, taşmaları
      // da ölçülmez. Davete kadar in.
      await tester.scrollUntilVisible(find.byType(RythoyaSor), 200,
          scrollable: find.byType(Scrollable).first);
      await tester.pump();
      expect(tester.takeException(), isNull, reason: 'alt gövde taşıyor');
      expect(find.byType(RythoyaSor), findsOneWidget);
    });
  });
}
