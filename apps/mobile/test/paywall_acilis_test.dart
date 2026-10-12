// Paywall'ın rotası KAYNAĞA göre, etiketi kaynaktan.
//
// `PaywallScreen` dokuz yerden rastgele rota türüyle itiliyordu; etiket
// iki değerliydi. Bu dosya üç şeyi çiviler: kesinti (402, tanıtım) tam
// ekran diyalog, dokunuş fade-through; `PaywallScreen` etiketi
// `paywallEtiketi`nden alıyor; kilit kartı dokunuşu özelliği ekrana
// taşıyor.
//
// `PaywallScreen` ÇİZDİRİLMEZ (mağaza/analitik sağlayıcıları ister):
// rotanın kurucusu elle çağrılıp dönen widget okunuyor, ağaç hiç monte
// edilmiyor — `yeni_konusma_fab_test` emsali.
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rytho/core/wallet.dart' show WalletStatus, walletProvider;
import 'package:flutter_test/flutter_test.dart';
import 'package:rytho/features/paywall/ozellik_katalogu.dart';
import 'package:rytho/features/paywall/paywall_acilis.dart';
import 'package:rytho/features/paywall/paywall_screen.dart';
import 'package:rytho/features/paywall/plus_locked_card.dart';
import 'package:rytho/l10n/app_localizations.dart';
import 'package:rytho/theme/rytho_theme.dart';
import 'package:rytho/widgets/fade_through_route.dart';

class _RotaGozcusu extends NavigatorObserver {
  final itilenler = <Route<dynamic>>[];

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    itilenler.add(route);
  }
}

// `ProviderScope`: kilit kartı bedel rozeti taşıyor (D7), rozet cüzdanı
// izliyor; cüzdan gelmeden rozet çizilmez.
Widget _sar(Widget govde, _RotaGozcusu gozcu) => ProviderScope(
    overrides: [walletProvider.overrideWith((_) async => WalletStatus.unknown)],
    child: MaterialApp(
      locale: const Locale('tr'),
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      theme: buildRythoTheme(),
      navigatorObservers: [gozcu],
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: true),
        child: child!,
      ),
      home: Scaffold(body: Center(child: govde)),
    ));

/// İtilen rotanın SAYFASI — monte edilmeden.
Widget _sayfa(Route<dynamic> rota, BuildContext context) => switch (rota) {
      final MaterialPageRoute<dynamic> r => r.builder(context),
      final PageRouteBuilder<dynamic> r => r.pageBuilder(
          context, kAlwaysCompleteAnimation, kAlwaysDismissedAnimation),
      _ => throw StateError('beklenmeyen rota: ${rota.runtimeType}'),
    };

String _yorumsuz(String yol) => File(yol)
    .readAsStringSync()
    .replaceAll('\r\n', '\n')
    .split('\n')
    .where((s) => !s.trimLeft().startsWith('//'))
    .join('\n');

void main() {
  group('etiket', () {
    test('kesinti kaynakları eski etiketleri taşır — seri kopmasın', () {
      expect(PaywallKaynak.kilit402.etiket, 'locked');
      expect(PaywallKaynak.tanitim.etiket, 'intro');
    });

    test('etiketler benzersiz', () {
      final etiketler = PaywallKaynak.values.map((k) => k.etiket).toSet();
      expect(etiketler.length, PaywallKaynak.values.length);
    });

    test('PaywallScreen etiketi KAYNAKTAN alıyor; iki değerli kural yok', () {
      // D7: `kaynak` zorunlu, `paywallEtiketi` geriye-uyum kapısı silindi.
      // Etiket dizeleri yalnız enum'da yaşar; ekrana literal geri gelirse
      // hangi yüzeyin dönüştürdüğü yine ölçülemez olur.
      final kaynak = _yorumsuz('lib/features/paywall/paywall_screen.dart');
      expect(kaynak, contains('Analytics.paywallShown(widget.kaynak.etiket)'));
      expect(kaynak, contains('required this.kaynak'));
      expect(kaynak, isNot(contains("'intro'")));
      expect(kaynak, isNot(contains("'locked'")));
    });

    test('PaywallScreen yalnız acPaywall kuruyor', () {
      // Dokuz çağrı yeri teker teker göçtü; onuncusu doğrudan kurarsa
      // rota türü ve etiket yine yere göre rastgele olur.
      final dosyalar = Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))
          .where((f) => !f.path.endsWith('paywall_acilis.dart'))
          .where((f) => !f.path.endsWith('paywall_screen.dart'));
      for (final f in dosyalar) {
        final yol = f.path.replaceAll(r'\', '/');
        expect(_yorumsuz(yol), isNot(contains('PaywallScreen(')),
            reason: '$yol paywall\'ı doğrudan kuruyor');
      }
    });
  });

  group('acPaywall rota türü', () {
    for (final kaynak in PaywallKaynak.values) {
      testWidgets('${kaynak.name} → ${kaynak.kesinti ? "diyalog" : "fade"}',
          (tester) async {
        final gozcu = _RotaGozcusu();
        await tester.pumpWidget(_sar(const Placeholder(), gozcu));
        final context = tester.element(find.byType(Placeholder));

        // Dönüş beklenmez: rota ancak pop edilince tamamlanır.
        unawaited(acPaywall(context,
            kaynak: kaynak, ozellik: PlusOzellik.bazi, reason: 'r'));

        expect(gozcu.itilenler.length, 2, reason: 'ana rota + itilen');
        final rota = gozcu.itilenler.last;
        if (kaynak.kesinti) {
          expect(rota, isA<MaterialPageRoute<bool>>());
          expect((rota as MaterialPageRoute).fullscreenDialog, isTrue,
              reason: 'kesinti alttan gelir, kapatma düğmesi taşır');
        } else {
          expect(rota, isA<FadeThroughRoute<bool>>(),
              reason: 'dokunuş bastığı kartın devamı gibi açılır');
        }
        final sayfa = _sayfa(rota, context);
        expect(sayfa, isA<PaywallScreen>());
        final ekran = sayfa as PaywallScreen;
        expect(ekran.kaynak, kaynak);
        expect(ekran.ozellik, PlusOzellik.bazi);
        expect(ekran.reason, 'r');

        // Geçiş başlamadan ağaç sökülür — ekran hiç çizilmez.
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }
  });

  group('PlusLockedCard dokunuşu', () {
    testWidgets('kilitKarti kaynağı + özellik ekrana taşınır', (tester) async {
      final gozcu = _RotaGozcusu();
      await tester.pumpWidget(_sar(
          const PlusLockedCard(
              ozellik: PlusOzellik.solarReturn,
              title: 'Başlık',
              description: 'Gövde'),
          gozcu));
      final context = tester.element(find.byType(PlusLockedCard));

      await tester.tap(find.byType(PlusLockedCard));

      expect(gozcu.itilenler.length, 2);
      final rota = gozcu.itilenler.last;
      expect(rota, isA<FadeThroughRoute<bool>>());
      final ekran = _sayfa(rota, context) as PaywallScreen;
      expect(ekran.kaynak, PaywallKaynak.kilitKarti);
      expect(ekran.ozellik, PlusOzellik.solarReturn);

      await tester.pumpWidget(const SizedBox.shrink());
    });
  });
}
