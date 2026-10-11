// Çark çizgi dili bekçileri (D6).
//
// Açı sınıfı yalnız renkle ayrışıyordu; plan "sert düz / yumuşak uzun
// kesik / minör kısa kesik" dedi ve bunun TEK tanımı `aspectDashFor` +
// `drawAspectLine` (chart_palette). Ressam, lejant satırı ve açı tablosu
// hücresi aynı fonksiyonu çağırır — burada hem kural hem üç tüketici
// çivilenir. Lejantın minör satırı yalnız minörler açıkken, Y/A dipnotu
// yalnız hareket ölçülmüşken çizilir (ölçülmeyen söylenmez).
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:rytho/l10n/app_localizations.dart';
import 'package:rytho/l10n/app_localizations_tr.dart';
import 'package:rytho/widgets/chart/aci_lejanti.dart';
import 'package:rytho/widgets/chart/chart_palette.dart';

final _tr = AppLocalizationsTr();

/// Kaynak bekçisi bir şeyin YOKLUĞUNU ararken kendi açıklama yorumuna
/// takılmasın (emsal: anlam_once_bes_ekran_test).
String _yorumsuz(String yol) => File(yol)
    .readAsStringSync()
    .replaceAll('\r\n', '\n')
    .split('\n')
    .where((s) => !s.trimLeft().startsWith('//'))
    .join('\n');

/// Yalnız çizgi çağrılarını sayan kanvas — çizilen şey ölçülür, kaynak
/// değil. `implements Canvas` + `noSuchMethod`: öteki çağrılar yutulur.
class _CizgiSayanKanvas implements Canvas {
  final cizgiler = <(Offset, Offset)>[];

  @override
  void drawLine(Offset p1, Offset p2, Paint paint) => cizgiler.add((p1, p2));

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

Widget _sar(Widget child) => MaterialApp(
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('tr'),
      home: Scaffold(body: Center(child: child)),
    );

void main() {
  GoogleFonts.config.allowRuntimeFetching = false;

  group('aspectDashFor — üç sınıf, üç çizgi', () {
    test('sert ve kavuşum DÜZ', () {
      expect(aspectDashFor('opposition'), AspectDash.solid);
      expect(aspectDashFor('square'), AspectDash.solid);
      // Kavuşum çarkta jant braketi; kesik braket okunmaz.
      expect(aspectDashFor('conjunction'), AspectDash.solid);
    });

    test('yumuşak UZUN kesik', () {
      expect(aspectDashFor('trine'), AspectDash.long);
      expect(aspectDashFor('sextile'), AspectDash.long);
    });

    test('minör KISA kesik — tabloda olmayan her tür minördür', () {
      expect(aspectDashFor('quincunx'), AspectDash.short);
      expect(aspectDashFor('semisextile'), AspectDash.short);
      expect(aspectDashFor('quintile'), AspectDash.short);
    });

    test('uzun kesik kısadan UZUN — adlar ölçüye uyuyor', () {
      expect(AspectDash.long.dash, greaterThan(AspectDash.short.dash));
      expect(AspectDash.solid.dash, 0);
    });
  });

  group('drawAspectLine — kesik sayısı sınıfla değişir', () {
    int parca(AspectDash dil, {double zoom = 1.0}) {
      final k = _CizgiSayanKanvas();
      drawAspectLine(k, Offset.zero, const Offset(100, 0), Paint(), dil,
          zoom: zoom);
      return k.cizgiler.length;
    }

    test('düz tek parça; kısa kesik uzun kesikten çok parça', () {
      expect(parca(AspectDash.solid), 1);
      expect(parca(AspectDash.long), greaterThan(1));
      expect(parca(AspectDash.short), greaterThan(parca(AspectDash.long)));
    });

    test('zoom kesikleri geometriyle büyütür — parça sayısı düşer', () {
      // Zoom "geometriyi büyüt": aynı uzunlukta daha az, daha uzun kesik.
      expect(parca(AspectDash.short, zoom: 2.0),
          lessThan(parca(AspectDash.short)));
    });

    test('sıfır uzunlukta çizgi parça üretmez', () {
      final k = _CizgiSayanKanvas();
      drawAspectLine(k, Offset.zero, Offset.zero, Paint(), AspectDash.short);
      expect(k.cizgiler, isEmpty);
    });
  });

  group('AciSinifiLejanti — lejant satırı', () {
    testWidgets('sert + yumuşak her zaman; minör yalnız açıkken',
        (tester) async {
      await tester.pumpWidget(_sar(
          const AciSinifiLejanti(showMinors: false, hareketVar: false)));
      expect(find.text(_tr.chartFilterHard), findsOneWidget);
      expect(find.text(_tr.chartFilterSoft), findsOneWidget);
      expect(find.text(_tr.chartFilterMinors), findsNothing,
          reason: 'minörler kapalıyken çarkta kısa kesik YOK — anlatılmaz');
      expect(find.byType(AciCizgiOrnegi), findsNWidgets(2));

      await tester.pumpWidget(_sar(
          const AciSinifiLejanti(showMinors: true, hareketVar: false)));
      expect(find.text(_tr.chartFilterMinors), findsOneWidget);
      expect(find.byType(AciCizgiOrnegi), findsNWidgets(3));
    });

    testWidgets('Y/A dipnotu yalnız hareket ölçülmüşken', (tester) async {
      await tester.pumpWidget(_sar(
          const AciSinifiLejanti(showMinors: false, hareketVar: false)));
      expect(find.text(_tr.chartMovementLegend), findsNothing,
          reason: 'hiçbir hücrede harf yokken açıklaması basılmaz');

      await tester.pumpWidget(_sar(
          const AciSinifiLejanti(showMinors: false, hareketVar: true)));
      expect(find.text(_tr.chartMovementLegend), findsOneWidget);
    });

    testWidgets('320 dp × 1,3 yazı ölçeğinde taşmaz', (tester) async {
      tester.view.physicalSize = const Size(320 * 3, 1200);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('tr'),
        home: MediaQuery(
          data: const MediaQueryData(
              size: Size(320, 400), textScaler: TextScaler.linear(1.3)),
          child: const Scaffold(
            body: SizedBox(
                width: 320 - 48,
                child:
                    AciSinifiLejanti(showMinors: true, hareketVar: true)),
          ),
        ),
      ));
      expect(tester.takeException(), isNull);
      expect(find.text(_tr.chartMovementLegend), findsOneWidget);
    });

    testWidgets('örnek çizgi gerçekten çiziliyor (CustomPaint var)',
        (tester) async {
      await tester.pumpWidget(_sar(AciCizgiOrnegi(
          dil: AspectDash.long, renk: aspectColor('trine'))));
      expect(
          find.descendant(
              of: find.byType(AciCizgiOrnegi),
              matching: find.byType(CustomPaint)),
          findsOneWidget);
    });
  });

  group('kaynak: üç tüketici TEK tanımı çağırıyor', () {
    test('ressam kendi kesik çizgi kopyasını tutmuyor', () {
      final k = _yorumsuz('lib/widgets/chart/wheel_painter.dart');
      expect(k, contains('drawAspectLine('));
      expect(k, contains('aspectDashFor('));
      expect(k, isNot(contains('_dashedLine')),
          reason: 'ressamın özel kesik çizgisi geri doğmuş — ikinci tanım');
      // Yumuşak açı artık incelikle değil kesikle ayrılır: ikinci kanal yok.
      expect(k, isNot(contains('* 0.85')),
          reason: 'yumuşak açı için ayrı kalınlık kuralı — çizgi dili tek');
    });

    test('lejant ve açı tablosu hücresi aynı örnek çizgiyi kullanıyor', () {
      final k = _yorumsuz('lib/features/atlas/chart_inspector_screen.dart');
      final lejant = k.substring(
          k.indexOf('class _Lejant'), k.indexOf('class _SecimCubugu'));
      expect(lejant, contains('AciSinifiLejanti('),
          reason: 'lejantın açı sınıfı satırı düşmüş');
      final hucre = k.substring(k.indexOf('class _AspectCell'));
      expect(hucre, contains('AciCizgiOrnegi('));
      expect(hucre, contains('aspectDashFor('));
    });

    test('gökyüzü açı satırı renk noktası değil çizgi örneği', () {
      final k = _yorumsuz('lib/features/sky/sky_now_screen.dart');
      final satir = k.substring(
          k.indexOf('class _AciSatiri'), k.indexOf('class SkyNowSummary'));
      expect(satir, contains('AciCizgiOrnegi('));
      expect(satir, isNot(contains('BoxShape.circle')),
          reason: 'sınıfı yalnız renkle ayıran nokta geri gelmiş');
    });

    test('palet yorumunun gerekçesi artık DOĞRU (kesik gerçekten var)', () {
      // CLAUDE.md §1: yanlış gerekçeli yorum kusurdur. Yorum "çizgi
      // stiliyle verilir" diyordu, kod yumuşağı düz çiziyordu.
      final k = File('lib/widgets/chart/chart_palette.dart')
          .readAsStringSync();
      expect(k, contains('AspectDash.long'));
      expect(k, contains('aspectDashFor'));
    });
  });

  test('dart:ui kanvasında da çizilir (duman)', () {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    for (final dil in AspectDash.values) {
      drawAspectLine(canvas, Offset.zero, const Offset(50, 50), Paint(), dil);
    }
    recorder.endRecording();
  });
}
