// Cam bileşenlerin D5 genişlemeleri: `GlassPanel.tone`, `GlassSegments`
// (compact, seçimsiz hâl, semantik) ve `SkeletonList`.
//
// Üçü de ekleme: eski çağrı yerleri aynı imzayla derlenmeye devam ediyor.
// Bekçilerin işi, göç (D6) bu bileşenlere geçtiğinde kopyaların taşıdığı
// davranışın kaybolmaması — yükseltilmiş ton gerçekten `inkLighter`,
// segment ekran okuyucuya "seçili" diyor, iskelet kopyalardaki üç bloğu
// aynı boyda çiziyor.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rytho/theme/rytho_theme.dart';
import 'package:rytho/theme/rytho_tokens.dart';
import 'package:rytho/widgets/glass.dart';

import 'dar_ekran_test.dart' show darEkranda, tasmaYok;

/// Hareketsiz çerçeve: iskelet parıltısı sürekli animatör, `disableAnimations`
/// onu hiç kurdurmaz; ölçülen şey yerleşim ve semantik.
Widget _sar(Widget child) => MaterialApp(
      theme: buildRythoTheme(),
      home: MediaQuery(
        data: const MediaQueryData(disableAnimations: true),
        child: Scaffold(body: child),
      ),
    );

/// Kartın dolgu rengi: `GlassPanel` dolguyu `Ink` dekorasyonuna yazar.
Color? _dolgu(WidgetTester tester) {
  final ink = tester.widget<Ink>(find.descendant(
      of: find.byType(GlassPanel), matching: find.byType(Ink)));
  return (ink.decoration as BoxDecoration?)?.color;
}

/// Seçili görünen segment sayısı: zemin rengi verilen `AnimatedContainer`.
int _seciliSayisi(WidgetTester tester) => tester
    .widgetList<AnimatedContainer>(find.descendant(
        of: find.byType(GlassSegments),
        matching: find.byType(AnimatedContainer)))
    .where((c) => (c.decoration as BoxDecoration?)?.color != null)
    .length;

void main() {
  group('GlassPanel.tone', () {
    testWidgets('varsayılan ton glassFill, raised ton inkLighter',
        (tester) async {
      await tester.pumpWidget(_sar(const GlassPanel(child: SizedBox())));
      expect(_dolgu(tester), RythoColors.glassFill);

      await tester.pumpWidget(_sar(
          const GlassPanel(tone: GlassTone.raised, child: SizedBox())));
      expect(_dolgu(tester), RythoColors.inkLighter,
          reason: 'yükseltilmiş yüzey saydam dolguyla altındaki kartla '
              'karışır — kopyaların (friends, person_form) taşıdığı değer');
    });

    testWidgets('kart yarıçapı token\'dan: 22', (tester) async {
      // Üç ayrı kart yarıçapı dolaşıyordu (22/20/24); tek kaynak token.
      const panel = GlassPanel(child: SizedBox());
      expect(panel.radius, RythoRadius.card);
    });
  });

  group('GlassSegments', () {
    const etiketler = ['Giriş yap', 'Üye ol'];

    testWidgets('tam boy 42 dp, compact 36 dp', (tester) async {
      await tester.pumpWidget(
          _sar(GlassSegments(labels: etiketler, index: 0, onChanged: (_) {})));
      expect(tester.getSize(find.byType(GlassSegments)).height, 42);

      await tester.pumpWidget(_sar(GlassSegments(
          labels: etiketler, index: 0, compact: true, onChanged: (_) {})));
      expect(tester.getSize(find.byType(GlassSegments)).height, 36,
          reason: 'form içi seçici sekme çubuğunun ağırlığını taşımamalı');
    });

    testWidgets('index null: hiçbir segment seçili çizilmez', (tester) async {
      // Cinsiyet seçici ilk açılışta bir seçeneği seçili GÖSTEREMEZ —
      // kullanıcı seçmediği şeyi beyan etmiş olur.
      await tester.pumpWidget(
          _sar(GlassSegments(labels: etiketler, onChanged: (_) {})));
      expect(_seciliSayisi(tester), 0);

      await tester.pumpWidget(
          _sar(GlassSegments(labels: etiketler, index: 1, onChanged: (_) {})));
      expect(_seciliSayisi(tester), 1);
    });

    testWidgets('her segment ekran okuyucuya düğme + seçili/seçili değil der',
        (tester) async {
      final semantik = tester.ensureSemantics();
      await tester.pumpWidget(
          _sar(GlassSegments(labels: etiketler, index: 1, onChanged: (_) {})));

      expect(
          tester.getSemantics(find.bySemanticsLabel('Üye ol')),
          isSemantics(
              isButton: true,
              isSelected: true,
              hasTapAction: true,
              label: 'Üye ol'));
      expect(
          tester.getSemantics(find.bySemanticsLabel('Giriş yap')),
          isSemantics(isButton: true, isSelected: false, label: 'Giriş yap'),
          reason: 'seçili olmayan segment "seçili" diye duyulmamalı');
      // Etiket iki kez okunmaz: Semantics düğümü + çıplak Text.
      expect(find.bySemanticsLabel('Üye ol'), findsOneWidget);
      // Tutamak test GÖVDESİNDE kapatılır: `addTearDown` doğrulamadan
      // sonra koşuyor ve test "tutamak açık kaldı" diye düşüyor.
      semantik.dispose();
    });

    testWidgets('dokununca seçim değişir (compact dahil)', (tester) async {
      var secilen = -1;
      await tester.pumpWidget(_sar(GlassSegments(
          labels: etiketler,
          index: 0,
          compact: true,
          onChanged: (i) => secilen = i)));
      await tester.tap(find.text('Üye ol'));
      expect(secilen, 1);
    });

    testWidgets('seçili segment degrade/glow almaz (doktrin korunur)',
        (tester) async {
      await tester.pumpWidget(
          _sar(GlassSegments(labels: etiketler, index: 0, onChanged: (_) {})));
      final kutular = tester.widgetList<AnimatedContainer>(find.descendant(
          of: find.byType(GlassSegments),
          matching: find.byType(AnimatedContainer)));
      for (final k in kutular) {
        final d = k.decoration as BoxDecoration?;
        expect(d?.gradient, isNull, reason: 'segment durum, buton eylem');
        expect(d?.boxShadow ?? const [], isEmpty);
      }
    });

    testWidgets('320 dp × 1,3 ölçekte gerçek etiketlerle taşma yok',
        (tester) async {
      await darEkranda(
          tester, GlassSegments(labels: etiketler, index: 0, onChanged: (_) {}));
      tasmaYok(tester);
    });
  });

  group('SkeletonList', () {
    testWidgets('varsayılan üç blok: 150 / 110 / 90', (tester) async {
      // Kopyaların (solar_return, inner_calendar, birth_hexagram) ölçüsü:
      // rapor sayfalarının gerçek bölüm hacimleri, cevap gelince düzen
      // zıplamasın diye.
      await tester.pumpWidget(_sar(const SkeletonList()));
      final bloklar =
          tester.widgetList<SkeletonPanel>(find.byType(SkeletonPanel));
      expect(bloklar.map((b) => b.height).toList(), [150, 110, 90]);
    });

    testWidgets('yükseklik listesi birebir uygulanır', (tester) async {
      await tester.pumpWidget(
          _sar(const SkeletonList(heights: [64, 64, 64, 64])));
      expect(find.byType(SkeletonPanel), findsNWidgets(4));
      for (final b in tester.widgetList<SkeletonPanel>(find.byType(SkeletonPanel))) {
        expect(b.height, 64);
      }
    });

    testWidgets('alt dolgu dock payı: son blok dock\'un altında kalmaz',
        (tester) async {
      await tester.pumpWidget(_sar(const SkeletonList()));
      final liste = tester.widget<ListView>(find.byType(ListView));
      expect((liste.padding as EdgeInsets?)?.bottom, RythoSpace.dockClearance);
    });

    testWidgets('320 dp × 1,3 ölçekte taşma yok', (tester) async {
      await darEkranda(
          tester, const SizedBox(height: 500, child: SkeletonList()));
      tasmaYok(tester);
    });
  });
}
