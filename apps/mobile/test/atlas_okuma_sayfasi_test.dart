// D6 bekçileri — okuma kartı ve okuma sayfası (`reading_card.dart`).
//
// Ölçülen hâl: kartın "devamını oku" satırı l10n dışında sabit metindi
// ('Read' / 'Okumaya devam et', dil anahtarına bakmadan); okuma sayfası
// paylaşımı AppBar ikonuyla veriyordu — dokuz yüzeyde ikinci bir paylaş
// biçimi. Paylaşımın tek konumu okumanın alt satırı (`PaylasKapisi`,
// `OkumaKabi` ile aynı kapı).
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rytho/l10n/app_localizations.dart';
import 'package:rytho/l10n/app_localizations_tr.dart';
import 'package:rytho/widgets/okuma_kabi.dart' show PaylasKapisi;
import 'package:rytho/widgets/reading_card.dart';

final _tr = AppLocalizationsTr();

String _yorumsuz(String yol) => File(yol)
    .readAsStringSync()
    .replaceAll('\r\n', '\n')
    .split('\n')
    .where((s) => !s.trimLeft().startsWith('//'))
    .join('\n');

Widget _sar(Widget child) => MaterialApp(
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('tr'),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: true),
        child: child!,
      ),
      home: child,
    );

void main() {
  testWidgets('kartın "devamını oku" satırı l10n anahtarından',
      (tester) async {
    await tester.pumpWidget(_sar(const Scaffold(
        body: ReadingCard(title: 'Başlık', body: 'Kısa gövde.'))));
    await tester.pump();
    expect(find.text(_tr.readingCardReadMore), findsOneWidget);
  });

  testWidgets('okuma sayfası: paylaş kapısı okumanın SONUNDA, AppBar boş',
      (tester) async {
    var paylasildi = 0;
    await tester.pumpWidget(_sar(ReadingScreen(
      title: 'Başlık',
      body: 'Birinci paragraf.\n\nİkinci paragraf.',
      onShare: (_) async => paylasildi++,
    )));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 900));

    final kapi = find.byType(PaylasKapisi);
    expect(kapi, findsOneWidget, reason: 'paylaş kapısı okumada yok');
    expect(
        find.descendant(
            of: find.byType(AppBar), matching: find.byType(IconButton)),
        findsNothing,
        reason: 'AppBar paylaş ikonu geri gelmiş — ikinci paylaş biçimi');
    // Kapı metnin ALTINDA: önce okunur, sonra paylaşılır.
    expect(tester.getTopLeft(find.text('İkinci paragraf.')).dy,
        lessThan(tester.getTopLeft(kapi).dy));
    await tester.tap(kapi);
    expect(paylasildi, 1);
  });

  testWidgets('onShare yoksa kapı da yok', (tester) async {
    await tester.pumpWidget(
        _sar(const ReadingScreen(title: 'Başlık', body: 'Gövde.')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 900));
    expect(find.byType(PaylasKapisi), findsNothing);
  });

  group('kaynak', () {
    final k = _yorumsuz('lib/widgets/reading_card.dart');

    test('sabit "devamını oku" metni yok, anahtar var', () {
      expect(k, contains('readingCardReadMore'));
      expect(k, isNot(contains("'Okumaya devam et'")));
      expect(k, isNot(contains("'Read'")));
    });

    test('AppBar actions yok; paylaşım PaylasKapisi ile', () {
      final sayfa = k.substring(k.indexOf('class ReadingScreen'));
      expect(sayfa, isNot(contains('actions:')));
      expect(sayfa, isNot(contains('IconButton(')));
      expect(sayfa, contains('PaylasKapisi(onTap: () => paylas(context))'));
    });
  });
}
