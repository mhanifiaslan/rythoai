// Alt sayfa kabuğu (`showRythoSheet` + `SheetTutamak`) ve ölçüm satırı
// (`OlcumSatiri`) bekçileri.
//
// Kabuğun var olma sebebi iki ÖLÇÜLMÜŞ kusur: takvim gün kartında kaydırma
// sarmalayıcısı yoktu ve 320×640'ta 1162 px içerik sessizce kırpılıyordu;
// arkadaş ekleme sayfasında klavye dolgusu dıştaki context'ten okunup 0
// kalıyordu. Kopyalar bu iki kapıyı ayrı ayrı unutabiliyordu; kabuk tek
// olunca ikisi de her sayfada var — bu dosya ikisini de çiviler.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rytho/l10n/app_localizations.dart';
import 'package:rytho/main.dart' show kMaxTextScale;
import 'package:rytho/theme/rytho_theme.dart';
import 'package:rytho/theme/rytho_tokens.dart';
import 'package:rytho/widgets/alt_sayfa.dart';
import 'package:rytho/widgets/basis_sheet.dart' show OlcumSatiri;

import 'dar_ekran_test.dart' show darEkranda, kDarGenislik, tasmaYok;

/// Alt sayfayı GERÇEKTEN açar: modal rota bir `Navigator` ister.
///
/// Ekran 320×640, yazı ölçeği tavanda: en dar Android × en kısa gerçek
/// telefon boyu. `builder`daki `MediaQuery` NAVIGATOR'u sarar, modal rota
/// da kapsanır; `home` içine konan bir override onu görmezdi.
Future<void> _sayfaAc(
  WidgetTester tester, {
  required WidgetBuilder builder,
  bool scrollable = true,
  bool klavyeyeUy = false,
  String? baslik,
}) async {
  tester.view.physicalSize = const Size(kDarGenislik * 3, 640 * 3);
  tester.view.devicePixelRatio = 3;
  tester.platformDispatcher.textScaleFactorTestValue = kMaxTextScale;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

  await tester.pumpWidget(MaterialApp(
    locale: const Locale('tr'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: const [Locale('tr'), Locale('en')],
    theme: buildRythoTheme(),
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(disableAnimations: true),
      child: child!,
    ),
    home: Scaffold(
      body: Builder(
        builder: (context) => TextButton(
          onPressed: () => showRythoSheet<void>(context,
              builder: builder,
              scrollable: scrollable,
              klavyeyeUy: klavyeyeUy,
              baslik: baslik),
          child: const Text('aç'),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('aç'));
  // Modal geçişi süreli; `pumpAndSettle` yerine adımlı bekleme.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
}

/// Ekrandan çok daha uzun gövde: 40 satır × 1,3 ölçek, 640 dp'ye sığmaz.
Widget _uzunGovde(BuildContext _) => Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < 40; i++)
          Text('Satır $i — gün kartındaki olay açıklaması gibi uzun'),
      ],
    );

void main() {
  group('showRythoSheet', () {
    testWidgets('kabuk: tutamak, inkLight zemin, kart köşesi, kontur',
        (tester) async {
      await _sayfaAc(tester, builder: (_) => const Text('gövde'));
      expect(find.byType(SheetTutamak), findsOneWidget);
      expect(find.text('gövde'), findsOneWidget);

      // Zemin ve biçim Material'ın alt sayfa kabuğuna yazılır.
      final kabuk = tester.widget<Material>(find
          .ancestor(of: find.text('gövde'), matching: find.byType(Material))
          .first);
      expect(kabuk.color, RythoColors.inkLight);
      final bicim = kabuk.shape as RoundedRectangleBorder;
      expect(bicim.borderRadius,
          const BorderRadius.vertical(top: Radius.circular(RythoRadius.card)));
      expect(bicim.side.color, RythoColors.glassStroke);
    });

    testWidgets('başlık verilirse sayfa başlığı rolünde ve ekran okuyucuya '
        'başlık', (tester) async {
      final semantik = tester.ensureSemantics();
      await _sayfaAc(tester,
          builder: (_) => const Text('gövde'), baslik: 'Kişi ekle');
      expect(find.text('Kişi ekle'), findsOneWidget);
      expect(tester.widget<Text>(find.text('Kişi ekle')).style,
          RythoType.sheetTitle);
      expect(tester.getSemantics(find.text('Kişi ekle')),
          isSemantics(isHeader: true));
      // Gövdede kapatılır: `addTearDown` doğrulamadan sonra koşuyor.
      semantik.dispose();
    });

    testWidgets('320×640 × 1,3: uzun içerik taşmaz, kaydırılır',
        (tester) async {
      // Takvim gün kartında ÖLÇÜLEN kusur: 1162 px içerik sessizce
      // kırpılıyordu. Kabuk kaydırma sarmalayıcısını kendi veriyor.
      await _sayfaAc(tester, builder: _uzunGovde);
      tasmaYok(tester, neden: 'uzun alt sayfa içeriği taşıyor');
      final ilk = find.textContaining(RegExp(r'^Satır 0 '));
      final son = find.textContaining(RegExp(r'^Satır 39 '));
      expect(
          find.ancestor(of: ilk, matching: find.byType(SingleChildScrollView)),
          findsOneWidget);
      // Son satır kaydırmayla ERİŞİLİR — kırpılmış değil.
      await tester.scrollUntilVisible(son, 200,
          scrollable: find.byType(Scrollable).last);
      expect(son, findsOneWidget);
      tasmaYok(tester);
    });

    testWidgets('scrollable: false — gövde kendi kaydırıcısını kullanır',
        (tester) async {
      // İç içe iki kaydırıcı dıştakini kilitler; `ListView` gövdeli sayfa
      // sarmalayıcıyı istemez.
      await _sayfaAc(tester,
          scrollable: false,
          builder: (_) => SizedBox(
              height: 200,
              child: ListView(children: const [Text('liste')])));
      expect(find.text('liste'), findsOneWidget);
      expect(find.byType(SingleChildScrollView), findsNothing);
    });

    testWidgets('klavyeyeUy: alt dolgu klavye kadar, SAYFANIN context\'inden',
        (tester) async {
      // Fiziksel 900 px / dpr 3 = 300 dp klavye.
      tester.view.viewInsets = const FakeViewPadding(bottom: 900);
      await _sayfaAc(tester,
          klavyeyeUy: true, builder: (_) => const Text('alan'));

      final dolgular = tester
          .widgetList<Padding>(find.ancestor(
              of: find.text('alan'), matching: find.byType(Padding)))
          .map((p) => p.padding.resolve(TextDirection.ltr).bottom);
      expect(dolgular, contains(300),
          reason: 'giriş alanı klavyenin altında kalır');
    });

    testWidgets('klavyeyeUy verilmezse klavye dolgusu yok', (tester) async {
      tester.view.viewInsets = const FakeViewPadding(bottom: 900);
      await _sayfaAc(tester, builder: (_) => const Text('alan'));
      final dolgular = tester
          .widgetList<Padding>(find.ancestor(
              of: find.text('alan'), matching: find.byType(Padding)))
          .map((p) => p.padding.resolve(TextDirection.ltr).bottom);
      expect(dolgular, isNot(contains(300)),
          reason: 'giriş alanı olmayan sayfa klavye için yer ayırmaz');
    });
  });

  group('SheetTutamak', () {
    testWidgets('36×4 çizgi, dekoratif: semantikten dışlanır',
        (tester) async {
      await tester.pumpWidget(const MaterialApp(
          home: Scaffold(body: Center(child: SheetTutamak()))));
      final cizgi = find.descendant(
          of: find.byType(SheetTutamak), matching: find.byType(Container));
      expect(tester.getSize(cizgi), const Size(36, RythoSpace.xs));
      expect(
          find.ancestor(
              of: cizgi, matching: find.byType(ExcludeSemantics)),
          findsOneWidget,
          reason: 'ekran okuyucu tutamağı duymamalı');
    });
  });

  group('OlcumSatiri', () {
    testWidgets('etiket büyük harfe ÇEVRİLMEZ', (tester) async {
      // Eski `_Satir` `toUpperCase()` çağırıyordu: Türkçe noktalı i
      // düşüyordu ("Kesinleşme" → "KESINLEŞME"). Rol tipografisi etiket
      // ağırlığını zaten veriyor.
      await tester.pumpWidget(const MaterialApp(
          home: Scaffold(
              body: OlcumSatiri(etiket: 'Kesinleşme', deger: '18 Eylül'))));
      expect(find.text('Kesinleşme'), findsOneWidget);
      expect(find.text('KESINLEŞME'), findsNothing);
      expect(tester.widget<Text>(find.text('Kesinleşme')).style,
          RythoType.label);
    });

    testWidgets('vurgu: değer altın', (tester) async {
      await tester.pumpWidget(const MaterialApp(
          home: Scaffold(
              body: Column(children: [
        OlcumSatiri(etiket: 'A', deger: 'düz'),
        OlcumSatiri(etiket: 'B', deger: 'vurgulu', vurgu: true),
      ]))));
      expect(tester.widget<Text>(find.text('düz')).style?.color,
          RythoColors.parchment);
      expect(tester.widget<Text>(find.text('vurgulu')).style?.color,
          RythoColors.gold);
    });

    testWidgets('değer boşsa satır HİÇ çizilmez', (tester) async {
      // Ölçülmemiş alan boş etiket olarak bile sunulmaz.
      await tester.pumpWidget(const MaterialApp(
          home: Scaffold(body: OlcumSatiri(etiket: 'Orb', deger: ''))));
      expect(find.text('Orb'), findsNothing);
    });

    testWidgets('320 dp × 1,3: uzun etiket + uzun değer taşmaz',
        (tester) async {
      await darEkranda(
          tester,
          const OlcumSatiri(
              etiket: 'Orb (ölçülen kesinleşme toleransı)',
              deger: 'Satürn, natal Ay ile Kare açısını 1.2° orb ile '
                  'kesinleştiriyor — ölçüm efemeristen'));
      tasmaYok(tester);
    });
  });
}
