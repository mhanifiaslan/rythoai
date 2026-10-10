// Kilit rozeti TEK ve küçük hâli animasyonsuz.
//
// Kilit üç biçimde çiziliyordu (altın disk + tek atış shimmer / çıplak
// gri ikon / `🔒` emoji). Bu dosya iki şeyi çiviler: `KilitRozeti.kucuk`
// hiç animasyon kurmaz (dört karoda aynı anda dört kıvılcım dikkat
// dağıtır) ve `PlusLockedCard` varsayılan `🔒` emojisini bir daha
// doğurmaz — kilit anlamını rozet taşıyor.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart' show Animate;
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rytho/features/paywall/kilit_rozeti.dart';
import 'package:rytho/features/paywall/ozellik_katalogu.dart';
import 'package:rytho/features/paywall/plus_locked_card.dart';
import 'package:rytho/l10n/app_localizations.dart';
import 'package:rytho/theme/rytho_theme.dart';
import 'package:rytho/theme/rytho_tokens.dart';

Widget _sar(Widget govde, {bool hareketsiz = true}) => MaterialApp(
      locale: const Locale('tr'),
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      theme: buildRythoTheme(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(disableAnimations: hareketsiz),
        child: child!,
      ),
      home: Scaffold(body: Center(child: govde)),
    );

/// Tek atış animasyon biter — tekrarlanmayan zincir için pump yeter.
Future<void> _bitir(WidgetTester tester) => tester.pump(
    RythoMotion.celebrate + RythoMotion.slower + RythoMotion.base);

String _yorumsuz(String yol) => File(yol)
    .readAsStringSync()
    .replaceAll('\r\n', '\n')
    .split('\n')
    .where((s) => !s.trimLeft().startsWith('//'))
    .join('\n');

void main() {
  group('KilitRozeti', () {
    testWidgets('varsayılan: animasyon zinciri kurulur, ikon 14', (tester) async {
      await tester.pumpWidget(_sar(const KilitRozeti(), hareketsiz: false));
      expect(find.byType(Animate), findsOneWidget);
      expect(tester.widget<Icon>(find.byType(Icon)).size, 14);
      await _bitir(tester);
    });

    testWidgets('kucuk: 12 px ve animasyon YOK', (tester) async {
      // Animasyonlar AÇIK — kapalıyken zincir zaten kurulmaz ve test
      // `kucuk` kuralını değil reduce-motion kapısını ölçerdi.
      await tester.pumpWidget(
          _sar(const KilitRozeti(kucuk: true), hareketsiz: false));
      expect(find.byType(Animate), findsNothing,
          reason: 'karo köşesindeki rozet parlamaz');
      expect(tester.widget<Icon>(find.byType(Icon)).size, 12);
    });

    testWidgets('animate: false → zincir yok', (tester) async {
      await tester.pumpWidget(
          _sar(const KilitRozeti(animate: false), hareketsiz: false));
      expect(find.byType(Animate), findsNothing);
    });

    testWidgets('reduce-motion açıkken zincir yok', (tester) async {
      await tester.pumpWidget(_sar(const KilitRozeti()));
      expect(find.byType(Animate), findsNothing);
    });
  });

  group('PlusLockedCard', () {
    testWidgets('emoji katalogdan, kilit rozetten, 🔒 YOK', (tester) async {
      await tester.pumpWidget(_sar(const PlusLockedCard(
        ozellik: PlusOzellik.natal,
        title: 'Başlık',
        description: 'Gövde',
      )));
      expect(find.text(PlusOzellik.natal.emoji), findsOneWidget);
      expect(find.byType(KilitRozeti), findsOneWidget);
      expect(find.text('🔒'), findsNothing);
    });

    testWidgets('çağıranın emojisi katalogu EZER (köprü)', (tester) async {
      await tester.pumpWidget(_sar(const PlusLockedCard(
        emoji: '🌞',
        title: 'Başlık',
        description: 'Gövde',
      )));
      expect(find.text('🌞'), findsOneWidget);
    });

    test('kaynakta varsayılan 🔒 geri doğmadı', () {
      final kaynak =
          _yorumsuz('lib/features/paywall/plus_locked_card.dart');
      expect(kaynak, isNot(contains('🔒')),
          reason: 'kilit anlamını KilitRozeti taşıyor; başta ikinci bir '
              'kilit aynı şeyi iki dilde söyler');
      expect(kaynak, contains('KilitRozeti('));
    });
  });
}
