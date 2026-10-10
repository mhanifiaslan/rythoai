// Taban bileşenlerin erişilebilirlik rolü + iki taban dosyanın kaynak bekçisi.
//
// Ölçüldü (D3): `Pressable` 41 çağrı yerinde rolsüzdü. Çıplak
// `GestureDetector` ekran okuyucuya "düğme" demez; TalkBack ana ekranın üst
// şeridini etiketsiz okuyordu. Rol artık TEK yerden (Pressable) geliyor ve
// bu dosya o tek yeri çiviler: rol, etkinlik, etiket birleşimi ve hareket
// azaltma kapısı.
//
// Aynı dosyada kaynak bekçisi: `nebula_widgets` ve `atlas_widgets` çıplak
// süre taşımaz (`Duration(milliseconds:` ve `N.ms`). D2'de her süre
// adlandırıldı; adsız bir süre geri gelirse aynı ekranda iki ritim yan yana
// çalışır ve göz senkronsuzluğu görür (rytho_tokens.dart, RythoMotion).
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rytho/l10n/app_localizations.dart';
import 'package:rytho/theme/rytho_tokens.dart';
import 'package:rytho/widgets/nebula_widgets.dart';

/// Yıldız alanı yok ama `AnimatedScale` örtük animatör; `pumpAndSettle`
/// yerine kapı + `pump(sure)` (emsal: yeni_konusma_fab_test).
Widget _sar(Widget child, {bool hareketAzalt = false}) => MaterialApp(
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('tr'),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(disableAnimations: hareketAzalt),
        child: child!,
      ),
      home: Scaffold(body: Center(child: child)),
    );

/// Kaynak bekçisi bir şeyin YOKLUĞUNU ararken kendi açıklama yorumuna
/// takılmasın: tam satır yorumları atılır (emsal: anlam_once_bes_ekran_test).
String _yorumsuz(String yol) => File(yol)
    .readAsStringSync()
    .replaceAll('\r\n', '\n')
    .split('\n')
    .where((s) => !s.trimLeft().startsWith('//'))
    .join('\n');

AnimatedScale _olcek(WidgetTester tester) => tester.widget<AnimatedScale>(
    find.descendant(
        of: find.byType(Pressable), matching: find.byType(AnimatedScale)));

void main() {
  group('Pressable semantiği', () {
    testWidgets('onTap varsa düğüm DÜĞME + etkin, etiket çocuktan gelir',
        (tester) async {
      final semantik = tester.ensureSemantics();
      await tester.pumpWidget(
          _sar(Pressable(onTap: () {}, child: const Text('Bugün'))));

      // Metin taşıyan 41 çağrı yeri etiketi bedavaya alır: MergeSemantics
      // çocuğun metnini düğüme birleştirir.
      expect(
          tester.getSemantics(find.byType(Pressable)),
          isSemantics(
            isButton: true,
            isEnabled: true,
            hasEnabledState: true,
            hasTapAction: true,
            label: 'Bugün',
          ),
          reason: 'TalkBack bu yüzeyi düğme olarak duymalı');
      semantik.dispose();
    });

    testWidgets('onTap yoksa düğme DEĞİL', (tester) async {
      // Dokunulamayan şeyi "düğme" diye duyurmak, hiç duyurmamaktan kötü:
      // kullanıcı çift dokunur, hiçbir şey olmaz.
      final semantik = tester.ensureSemantics();
      await tester.pumpWidget(_sar(const Pressable(child: Text('Bugün'))));

      expect(tester.getSemantics(find.byType(Pressable)),
          isSemantics(isButton: false, isEnabled: false));
      semantik.dispose();
    });

    testWidgets('semanticLabel ikon-tek yüzeye ad verir', (tester) async {
      final semantik = tester.ensureSemantics();
      await tester.pumpWidget(_sar(Pressable(
        onTap: () {},
        semanticLabel: 'Profil',
        child: const Icon(Icons.person_outline),
      )));

      expect(tester.getSemantics(find.byType(Pressable)),
          isSemantics(isButton: true, label: 'Profil'));
      semantik.dispose();
    });

    testWidgets('dokunuş onTap\'ı bir kez tetikler', (tester) async {
      var sayac = 0;
      await tester.pumpWidget(
          _sar(Pressable(onTap: () => sayac++, child: const Text('Bugün'))));
      await tester.tap(find.byType(Pressable));
      await tester.pump(RythoMotion.press);
      expect(sayac, 1);
    });

    testWidgets('basma ölçeği token süresinde, hareket azaltmada ANINDA',
        (tester) async {
      // Örtük animatör `reduceMotion`dan geçmiyordu: `.animate()` zincirleri
      // kapanırken basma ölçeği 120 ms oynamaya devam ediyordu.
      await tester.pumpWidget(
          _sar(Pressable(onTap: () {}, child: const Text('Bugün'))));
      expect(_olcek(tester).duration, RythoMotion.press);

      await tester.pumpWidget(_sar(
          Pressable(onTap: () {}, child: const Text('Bugün')),
          hareketAzalt: true));
      expect(_olcek(tester).duration, Duration.zero,
          reason: 'hareket azaltma açıkken basma ölçeği oynamamalı');
    });
  });

  group('hareket kapıları', () {
    testWidgets('StreakBadge: normalde belirir, hareket azaltmada Animate YOK',
        (tester) async {
      // Giriş animasyonu kapısızdı: hareket azaltmada da şişerek geliyordu.
      await tester.pumpWidget(_sar(const StreakBadge(count: 3)));
      expect(find.byType(Animate), findsOneWidget);
      await tester.pump(RythoMotion.celebrate);

      await tester.pumpWidget(
          _sar(const StreakBadge(count: 3), hareketAzalt: true));
      expect(find.byType(Animate), findsNothing);
      expect(find.textContaining('3'), findsOneWidget,
          reason: 'rozet animasyonsuz da görünür');
    });

    testWidgets('ZodiacChip seçim geçişi token süresinde, azaltmada ANINDA',
        (tester) async {
      AnimatedContainer kutu() => tester.widget<AnimatedContainer>(
          find.descendant(
              of: find.byType(ZodiacChip),
              matching: find.byType(AnimatedContainer)));

      await tester.pumpWidget(_sar(const ZodiacChip(signIndex: 0)));
      expect(kutu().duration, RythoMotion.base);

      await tester.pumpWidget(
          _sar(const ZodiacChip(signIndex: 0), hareketAzalt: true));
      expect(kutu().duration, Duration.zero);
    });
  });

  group('kaynak bekçisi: çıplak süre yok', () {
    const dosyalar = [
      'lib/widgets/nebula_widgets.dart',
      'lib/widgets/atlas_widgets.dart',
    ];
    final msUzantisi = RegExp(r'\d+\.ms\b');

    for (final yol in dosyalar) {
      test('$yol — Duration(milliseconds: ve N.ms sıfır (yorumsuz)', () {
        final kaynak = _yorumsuz(yol);
        expect(kaynak, isNot(contains('Duration(milliseconds:')),
            reason: 'süre RythoMotion tokenından okunmalı');
        expect(kaynak, isNot(contains('Duration(seconds:')),
            reason: 'süre RythoMotion tokenından okunmalı');
        expect(msUzantisi.hasMatch(kaynak), isFalse,
            reason: 'flutter_animate `.ms` kısayolu da çıplak süredir');
      });
    }
  });
}
