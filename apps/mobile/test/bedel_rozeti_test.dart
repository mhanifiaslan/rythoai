// Bedel rozeti: bilinmiyorsa YOK, biliniyorsa sunucunun sayısı.
//
// İ Ching rozetinin kuralı (`iching_bedel_test`) bütün jetonlu yüzeylere
// taşınıyor: bedel SUNUCUDAN (`costs` haritası, katalog anahtarıyla)
// gelir; cüzdan okunamadıysa, anahtar yoksa, sayı sıfır/negatifse rozet
// HİÇ çizilmez. Uydurma sayı bayat sayıdan kötü — kullanıcı ona göre
// davranır.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rytho/core/wallet.dart';
import 'package:rytho/features/paywall/bedel_rozeti.dart';
import 'package:rytho/features/paywall/ozellik_katalogu.dart';
import 'package:rytho/l10n/app_localizations.dart';
import 'package:rytho/theme/rytho_theme.dart';

Widget _sar(Widget govde, {required Future<WalletStatus> cuzdan}) =>
    ProviderScope(
      overrides: [walletProvider.overrideWith((_) => cuzdan)],
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
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: true),
          child: child!,
        ),
        home: Scaffold(body: Center(child: govde)),
      ),
    );

Future<void> _bekle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

const _dolu = WalletStatus(
    allowance: 80,
    purchased: 0,
    monthlyAllowance: 100,
    costs: {'natal': 5, 'chat': 1, 'iching': 2});

void main() {
  group('bedelOku (saf)', () {
    test('sunucu ne derse O — 5 ayrıcalıklı değil', () {
      expect(bedelOku(_dolu, PlusOzellik.natal), 5);
      expect(bedelOku(_dolu, PlusOzellik.chat), 1);
      const baska = WalletStatus(
          allowance: 0, purchased: 0, monthlyAllowance: 0,
          costs: {'natal': 7});
      expect(bedelOku(baska, PlusOzellik.natal), 7);
    });

    test('cüzdan yok ya da BİLİNMİYOR → null (costs dolu olsa bile)', () {
      expect(bedelOku(null, PlusOzellik.natal), isNull);
      // Bilinmiyor bayrağı tek başına yeter: harita dolu gelse bile o
      // yanıta güvenilmez. `unknown` sabitinin boş haritası bu dalı
      // maskelerdi — o yüzden dolu haritayla kuruluyor.
      const okunamadi = WalletStatus(
          allowance: 0, purchased: 0, monthlyAllowance: 0,
          costs: {'natal': 5}, bilinmiyor: true);
      expect(bedelOku(okunamadi, PlusOzellik.natal), isNull);
    });

    test('bedel anahtarı olmayan özellik → null', () {
      // Günlük okuma kapılı ama jetonsuz; çevre ve takvim ikisi de değil.
      expect(bedelOku(_dolu, PlusOzellik.daily), isNull);
      expect(bedelOku(_dolu, PlusOzellik.people), isNull);
      expect(bedelOku(_dolu, PlusOzellik.transitCalendar), isNull);
    });

    test('sunucu anahtarı göndermediyse → null', () {
      expect(bedelOku(_dolu, PlusOzellik.bazi), isNull);
    });

    test('sıfır ve negatif → null — "bedava" sözü verilmez', () {
      const bozuk = WalletStatus(
          allowance: 0, purchased: 0, monthlyAllowance: 0,
          costs: {'natal': 0, 'chat': -1});
      expect(bedelOku(bozuk, PlusOzellik.natal), isNull);
      expect(bedelOku(bozuk, PlusOzellik.chat), isNull);
    });
  });

  group('BedelRozeti (widget)', () {
    testWidgets('bedel 5 → "5 kredi"', (tester) async {
      await tester.pumpWidget(_sar(const BedelRozeti(PlusOzellik.natal),
          cuzdan: Future.value(_dolu)));
      await _bekle(tester);
      expect(find.text('5 kredi'), findsOneWidget);
      expect(find.byIcon(Icons.toll_rounded), findsOneWidget);
    });

    testWidgets('kucuk: metin var, ikon yok', (tester) async {
      await tester.pumpWidget(
          _sar(const BedelRozeti(PlusOzellik.natal, kucuk: true),
              cuzdan: Future.value(_dolu)));
      await _bekle(tester);
      expect(find.text('5 kredi'), findsOneWidget);
      expect(find.byIcon(Icons.toll_rounded), findsNothing);
    });

    testWidgets('bilinmiyor → HİÇ çizilmez', (tester) async {
      await tester.pumpWidget(_sar(const BedelRozeti(PlusOzellik.natal),
          cuzdan: Future.value(WalletStatus.unknown)));
      await _bekle(tester);
      expect(find.byType(Text), findsNothing);
      expect(find.byIcon(Icons.toll_rounded), findsNothing);
    });

    testWidgets('yükleniyor → HİÇ çizilmez', (tester) async {
      await tester.pumpWidget(_sar(const BedelRozeti(PlusOzellik.natal),
          cuzdan: Completer<WalletStatus>().future));
      await _bekle(tester);
      expect(find.byType(Text), findsNothing);
    });
  });
}
