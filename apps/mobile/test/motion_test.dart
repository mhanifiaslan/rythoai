import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rytho/widgets/atlas_widgets.dart' show AstrolabeSpinner;
import 'package:rytho/widgets/motion.dart';
import 'package:rytho/theme/rytho_tokens.dart';

/// R12-A0 hareket altyapısının değişmezleri.
///
/// Kural: sonsuz repeat içeren ağaçta (AstrolabeSpinner) ASLA pumpAndSettle
/// çağrılmaz — süreli `pump` adımlarıyla ilerlenir; settle hiç bitmez.

Widget _sar(Widget child, {bool azalt = false}) => MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: azalt),
        child: Scaffold(body: child),
      ),
    );

void main() {
  group('RythoReveal', () {
    testWidgets('normalde animasyon zinciri kurulur', (tester) async {
      await tester.pumpWidget(
          _sar(const RythoReveal(index: 1, child: Text('selamlik'))));
      expect(find.byType(Animate), findsOneWidget);
      // Gecikme + giriş sonunda metin tam görünür.
      await tester.pump(const Duration(milliseconds: 700));
      expect(find.text('selamlik'), findsOneWidget);
    });

    testWidgets('reduce-motion açıkken çocuk ÇIPLAK döner', (tester) async {
      // Geciken görünmezlik, animasyonsuzluktan daha rahatsız edicidir:
      // kapı açıkken stagger gecikmesi dahil hiçbir şey kurulmamalı.
      await tester.pumpWidget(_sar(
          const RythoReveal(index: 5, child: Text('sabit')),
          azalt: true));
      expect(find.byType(Animate), findsNothing);
      expect(find.text('sabit'), findsOneWidget);
    });
  });

  group('StagedWaiting', () {
    testWidgets('aşamalar sırayla ilerler ve SONDA DURUR', (tester) async {
      await tester.pumpWidget(_sar(const StagedWaiting(
          stages: ['bir', 'iki', 'üç'],
          interval: Duration(milliseconds: 500))));
      expect(find.text('bir'), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 600));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('iki'), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('üç'), findsOneWidget);

      // Döngü YOK: uzun süre sonra hâlâ son aşama — başa saran metin
      // "takıldı" hissi verirdi (yüz okuma sahnesinin kuralı).
      await tester.pump(const Duration(seconds: 3));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('üç'), findsOneWidget);
      expect(find.text('bir'), findsNothing);
    });

    testWidgets('tek aşamalı kullanım çökmeden durur', (tester) async {
      await tester.pumpWidget(
          _sar(const StagedWaiting(stages: ['bekle'])));
      expect(find.text('bekle'), findsOneWidget);
      await tester.pump(const Duration(seconds: 6));
      expect(find.text('bekle'), findsOneWidget);
    });

    // PBZ: `visual` düz alan — verilmeyince usturlap, verilince yalnız
    // verilen sahne (BaZi luopan bu yoldan giriyor).
    testWidgets('visual verilmeyince AstrolabeSpinner var', (tester) async {
      await tester.pumpWidget(
          _sar(const StagedWaiting(stages: ['bekle'])));
      expect(find.byType(AstrolabeSpinner), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 300));
    });

    testWidgets('visual verilince AstrolabeSpinner YOK, sahne var',
        (tester) async {
      await tester.pumpWidget(_sar(const StagedWaiting(
        stages: ['bekle'],
        visual: SizedBox(key: Key('luopan'), width: 10, height: 10),
      )));
      expect(find.byType(AstrolabeSpinner), findsNothing);
      expect(find.byKey(const Key('luopan')), findsOneWidget);
      expect(find.text('bekle'), findsOneWidget);
    });
  });
  group('sayfayaGit', () {
    // `animateToPage` sıfır süreyi assert ile reddeder
    // (`DrivenScrollActivity`): `kapili` hareket azaltmada sıfır döndürünce
    // ilk sayfa geçişi fırlıyordu (ölçüldü D4, sihirbaz_adimlar_test).
    // Karar tek yerde: sıfırda `jumpToPage`, aksi hâlde `animateToPage`.
    // Denetleyici SAHTE: hangi fiilin çağrıldığı sayılır, kaydırma değil.
    testWidgets('hareket azaltmada jumpToPage, normalde animateToPage',
        (tester) async {
      Future<_SahteSayfa> kos({required bool azalt}) async {
        final sayfa = _SahteSayfa();
        addTearDown(sayfa.dispose);
        await tester.pumpWidget(_sar(
          Builder(builder: (context) {
            sayfayaGit(sayfa, context, 3);
            return const SizedBox.shrink();
          }),
          azalt: azalt,
        ));
        return sayfa;
      }

      final azaltilmis = await kos(azalt: true);
      expect(azaltilmis.atlanan, 3);
      expect(azaltilmis.canlandirilan, isNull,
          reason: 'sıfır süreyle animateToPage assert ile fırlar');

      final normal = await kos(azalt: false);
      expect(normal.canlandirilan, 3);
      expect(normal.sure, RythoMotion.route, reason: 'varsayılan süre rota');
      expect(normal.atlanan, isNull);
    });

    testWidgets('süre verilirse o süre, kapıdan geçer', (tester) async {
      final sayfa = _SahteSayfa();
      addTearDown(sayfa.dispose);
      await tester.pumpWidget(_sar(Builder(builder: (context) {
        sayfayaGit(sayfa, context, 1, sure: RythoMotion.base);
        return const SizedBox.shrink();
      })));
      expect(sayfa.sure, RythoMotion.base);
    });
  });
}

/// Fiili kaydeden PageController: bağlı bir PageView gerekmez.
class _SahteSayfa extends PageController {
  int? atlanan;
  int? canlandirilan;
  Duration? sure;

  @override
  void jumpToPage(int page) => atlanan = page;

  @override
  Future<void> animateToPage(int page,
      {required Duration duration, required Curve curve}) async {
    canlandirilan = page;
    sure = duration;
  }
}
