// `GoldButton` bekçileri (D3): erişilebilirlik düğümü, yıkıcı varyant,
// CTA degradesi ve basma kapısı.
//
// NEDEN ayrı dosya: `login_hierarchy_test` düğmenin HİYERARŞİSİNİ (tek
// birincil) sabitler; burası düğmenin kendi sözleşmesi. İkisi karışırsa
// hiyerarşi testi düğme içine, düğme testi ekran içine sızar.
//
// Degrade `ctaGradient` (sahip kararı K5): beyaz metin `primaryGradient`'ın
// magenta ucunda 3,36:1 ölçüldü; `ctaGradient` her durakta ≥ 4,6
// (`kontrast_test`). Dekoratif yüzeyler `primaryGradient`'ta kalır; bu düğme
// metin taşıdığı için değişti. Kaynak bekçisi o ayrımı korur.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rytho/theme/rytho_theme.dart';
import 'package:rytho/theme/rytho_tokens.dart';
import 'package:rytho/widgets/atlas_widgets.dart';

/// Usturlap (meşgul hâl) sürekli animatör: `pumpAndSettle` dönmez.
Widget _sar(Widget child, {bool hareketAzalt = false}) => MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(disableAnimations: hareketAzalt),
        child: child!,
      ),
      home: Scaffold(body: Center(child: child)),
    );

String _yorumsuz(String yol) => File(yol)
    .readAsStringSync()
    .replaceAll('\r\n', '\n')
    .split('\n')
    .where((s) => !s.trimLeft().startsWith('//'))
    .join('\n');

/// Düğmenin tek `Container`ının dekorasyonu.
BoxDecoration _dekor(WidgetTester tester) => tester
    .widget<Container>(find.descendant(
        of: find.byType(GoldButton), matching: find.byType(Container)))
    .decoration! as BoxDecoration;

AnimatedScale _olcek(WidgetTester tester) => tester.widget<AnimatedScale>(
    find.descendant(
        of: find.byType(GoldButton), matching: find.byType(AnimatedScale)));

void main() {
  group('erişilebilirlik düğümü', () {
    testWidgets('açıkken düğme + etkin + etiket metin', (tester) async {
      final semantik = tester.ensureSemantics();
      await tester.pumpWidget(_sar(GoldButton(text: 'Gönder', onPressed: () {})));

      expect(
          tester.getSemantics(find.byType(GoldButton)),
          isSemantics(
            isButton: true,
            isEnabled: true,
            hasEnabledState: true,
            hasTapAction: true,
            isLiveRegion: false,
            label: 'Gönder',
          ));
      semantik.dispose();
    });

    testWidgets('meşgulken etkin DEĞİL, canlı bölge, etiket KALIR',
        (tester) async {
      // Meşgulken metin yerine usturlap çiziliyor; etiket çocuktan gelseydi
      // ekran okuyucu düğmeyi tam o anda kaybederdi.
      final semantik = tester.ensureSemantics();
      await tester.pumpWidget(
          _sar(GoldButton(text: 'Gönder', busy: true, onPressed: () {})));
      await tester.pump(RythoMotion.press);

      expect(find.text('Gönder'), findsNothing,
          reason: 'meşgul düğme metin çizmez; etiket düğümden gelmeli');
      expect(
          tester.getSemantics(find.byType(GoldButton)),
          isSemantics(
            isButton: true,
            isEnabled: false,
            hasEnabledState: true,
            isLiveRegion: true,
            label: 'Gönder',
          ));
      semantik.dispose();
    });

    testWidgets('onPressed yokken etkin değil', (tester) async {
      final semantik = tester.ensureSemantics();
      await tester.pumpWidget(_sar(const GoldButton(text: 'Gönder')));

      expect(tester.getSemantics(find.byType(GoldButton)),
          isSemantics(isButton: true, isEnabled: false));
      semantik.dispose();
    });
  });

  group('yıkıcı varyant', () {
    testWidgets('degrade YOK, dolgu madder, glow YOK, metin ink',
        (tester) async {
      await tester.pumpWidget(_sar(
          GoldButton(text: 'Hesabı sil', destructive: true, onPressed: () {})));

      final d = _dekor(tester);
      expect(d.gradient, isNull, reason: 'yıkıcı eylem degrade almaz');
      expect(d.color, RythoColors.madder);
      expect(d.boxShadow, isNull, reason: 'parıltı davet eder; silme davet edilmez');
      // Beyaz madder üstünde 2,74:1 (AA 4,5'in altı); ink 7,29:1 — ölçüldü.
      expect(tester.widget<Text>(find.text('Hesabı sil')).style?.color,
          RythoColors.ink);
    });

    testWidgets('devre dışı yıkıcı madder DEĞİL', (tester) async {
      // Kırmızı ama basılamayan düğme "bozuk" okunur; devre dışı hâl diğer
      // varyantlarla aynı nötr yüzeyi alır.
      await tester.pumpWidget(
          _sar(const GoldButton(text: 'Hesabı sil', destructive: true)));

      final d = _dekor(tester);
      expect(d.color, RythoColors.inkLighter);
      expect(d.gradient, isNull);
    });

    testWidgets('filled:true ile birlikte de degrade ALMAZ', (tester) async {
      // Varsayılan `filled: true`; yıkıcı bayrağı onun önüne geçmeli, yoksa
      // çağıran `filled: false` yazmayı unutunca kırmızı yerine mor gelir.
      await tester.pumpWidget(_sar(GoldButton(
          text: 'Hesabı sil',
          destructive: true,
          filled: true,
          onPressed: () {})));

      expect(_dekor(tester).gradient, isNull);
      expect(_dekor(tester).color, RythoColors.madder);
    });
  });

  group('CTA degradesi', () {
    testWidgets('birincil düğme ctaGradient çizer', (tester) async {
      await tester.pumpWidget(_sar(GoldButton(text: 'Devam', onPressed: () {})));

      final d = _dekor(tester);
      expect(d.gradient, RythoColors.ctaGradient);
      expect(tester.widget<Text>(find.text('Devam')).style?.color,
          RythoColors.onGradient);
    });

    testWidgets('devre dışı düğme degrade TAŞIMAZ', (tester) async {
      // Eski hâl iki durağı aynı olan bir "degrade" idi; degrade sayan
      // bekçiler (login_hierarchy) devre dışı düğmeyi birincil sayardı.
      await tester.pumpWidget(_sar(const GoldButton(text: 'Devam')));
      expect(_dekor(tester).gradient, isNull);
      expect(_dekor(tester).color, RythoColors.inkLighter);
    });

    test('kaynakta ctaGradient VAR, primaryGradient YOK (yorumsuz)', () {
      final kaynak = _yorumsuz('lib/widgets/atlas_widgets.dart');
      expect(kaynak, contains('RythoColors.ctaGradient'));
      expect(kaynak, isNot(contains('primaryGradient')),
          reason: 'metin taşıyan düğme AA altı degradeye geri dönmüş');
    });
  });

  group('basma kapısı', () {
    testWidgets('token süresi; hareket azaltmada ANINDA', (tester) async {
      await tester.pumpWidget(_sar(GoldButton(text: 'Devam', onPressed: () {})));
      expect(_olcek(tester).duration, RythoMotion.press);

      await tester.pumpWidget(_sar(
          GoldButton(text: 'Devam', onPressed: () {}),
          hareketAzalt: true));
      expect(_olcek(tester).duration, Duration.zero);
    });
  });
}
