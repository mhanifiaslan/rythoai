// 429 bekleme notu: sunucunun söylediği süre ekranda kalır, dolunca kalkar;
// süre bilinmiyorsa HİÇ çizilmez.
//
// Kapatılan kusur: `kotaBeklemeProvider` interceptor'da yazılıyor ama hiçbir
// yüzey okumuyordu — kullanıcı her denemesinde yeni bir 429 alıp kotayı
// kendisi besliyordu.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rytho/core/api.dart' show kotaBeklemeProvider;
import 'package:rytho/l10n/app_localizations.dart';
import 'package:rytho/theme/rytho_theme.dart';
import 'package:rytho/widgets/kota_bekleme.dart';

String _yorumsuz(String yol) => File(yol)
    .readAsStringSync()
    .replaceAll('\r\n', '\n')
    .split('\n')
    .where((s) => !s.trimLeft().startsWith('//'))
    .join('\n');

Widget _sar(DateTime? bitis) => ProviderScope(
      overrides: [kotaBeklemeProvider.overrideWith((_) => bitis)],
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
        home: const Scaffold(body: KotaBeklemeNotu()),
      ),
    );

void main() {
  group('kotaKalanSaniye (saf)', () {
    final simdi = DateTime(2026, 10, 12, 12, 0, 0);

    test('bekleme yok → null', () {
      expect(kotaKalanSaniye(null, simdi), isNull);
    });

    test('ileride → kalan saniye', () {
      expect(kotaKalanSaniye(simdi.add(const Duration(seconds: 42)), simdi),
          42);
    });

    test('dolmuş ya da tam şimdi → null ("0 sn" notu olmaz)', () {
      expect(kotaKalanSaniye(simdi, simdi), isNull);
      expect(
          kotaKalanSaniye(simdi.subtract(const Duration(seconds: 1)), simdi),
          isNull);
    });
  });

  group('KotaBeklemeNotu (widget)', () {
    testWidgets('bekleme yok → hiç çizilmez', (tester) async {
      await tester.pumpWidget(_sar(null));
      await tester.pump();
      expect(find.byType(Text), findsNothing);
    });

    testWidgets('bekleme var → "{n} sn sonra tekrar dene"', (tester) async {
      await tester.pumpWidget(
          _sar(DateTime.now().add(const Duration(seconds: 30))));
      await tester.pump();
      expect(find.textContaining('sn'), findsOneWidget);
      expect(find.textContaining(RegExp(r'\b(29|30)\b')), findsOneWidget,
          reason: 'saniye gerçek saatten; bir saniyelik pay');
      // Sayaç sökülünce kapanmalı (asılı periyodik zamanlayıcı yok).
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('dolmuş bekleme → çizilmez', (tester) async {
      await tester.pumpWidget(
          _sar(DateTime.now().subtract(const Duration(seconds: 1))));
      await tester.pump();
      expect(find.byType(Text), findsNothing);
    });
  });

  group('Kaynak bekçisi', () {
    test('sohbet notu kuruyor (sağlayıcının okuyucusu var)', () {
      final k = _yorumsuz('lib/features/chat/chat_screen.dart');
      expect(k, contains('const KotaBeklemeNotu()'));
    });

    test('sohbet gönder düğmesi kendi anahtarını taşıyor', () {
      final k = _yorumsuz('lib/features/chat/chat_screen.dart');
      expect(k, contains('semanticLabel: l10n.chatSend'));
      expect(k, isNot(contains('semanticLabel: l10n.feedbackSend')));
    });
  });
}
