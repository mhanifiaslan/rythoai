// Bedel kapısı: pahalı üretim ekrana girildiği an DEĞİL, ilk "Devam"dan
// sonra başlar — ve yalnız aboneye, yalnız eşik üstü bedelde, yalnız bedel
// BİLİNİYORKEN sorulur.
//
// Kapatılan kusur: BaZi, Yıl Haritası, İç Takvim ve Doğum Kapısı ekranları
// sağlayıcıyı `build`in başında izliyordu; abone ekrana "bir bakayım" diye
// girdiğinde 5 kredi düşmüştü bile. Bu dosya üç şeyi çiviler: (1) saf karar
// `onayGerekli`; (2) kapı widget'ı `builder`ı onaydan ÖNCE çağırmıyor,
// onaydan sonra çağırıyor ve tercihi yazıyor; (3) dört ekranda sağlayıcı
// izleme satırı `BedelKapisi(`ten SONRA geliyor — kaynak sırası, bayrak
// değil.
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rytho/core/providers.dart' show PlusHali, raporKapisiProvider;
import 'package:rytho/core/wallet.dart';
import 'package:rytho/features/paywall/bedel_onayi.dart';
import 'package:rytho/features/paywall/ozellik_katalogu.dart';
import 'package:rytho/l10n/app_localizations.dart';
import 'package:rytho/theme/rytho_theme.dart';
import 'package:rytho/widgets/glass.dart' show SkeletonList;

AppLocalizations _tr() => lookupAppLocalizations(const Locale('tr'));

String _yorumsuz(String yol) => File(yol)
    .readAsStringSync()
    .replaceAll('\r\n', '\n')
    .split('\n')
    .where((s) => !s.trimLeft().startsWith('//'))
    .join('\n');

/// Onay deposu dikişi: okunan değer sabit, yazılanlar listede.
({OnayDeposu depo, List<String> yazilanlar}) _depo({required bool onayli}) {
  final yazilanlar = <String>[];
  return (
    depo: (
      oku: (_) async => onayli,
      yaz: (anahtar) async => yazilanlar.add(anahtar),
    ),
    yazilanlar: yazilanlar,
  );
}

Widget _sar({
  required PlusHali kapi,
  required WalletStatus cuzdan,
  required OnayDeposu depo,
  required PlusOzellik ozellik,
  required List<String> kurulanlar,
}) =>
    ProviderScope(
      overrides: [
        raporKapisiProvider.overrideWithValue(kapi),
        walletProvider.overrideWith((_) async => cuzdan),
        onayDeposuProvider.overrideWithValue(depo),
      ],
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
        home: Scaffold(
          body: BedelKapisi(
            ozellik: ozellik,
            builder: (context, ref) {
              // "Sağlayıcı izlendi" olayının yerine geçen iz: builder
              // çağrıldıysa istek gitmiş demektir.
              kurulanlar.add(ozellik.name);
              return const Text('ICERIK');
            },
          ),
        ),
      ),
    );

Future<void> _bekle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

const _bes = WalletStatus(
    allowance: 80,
    purchased: 0,
    monthlyAllowance: 100,
    costs: {'bazi': 5, 'dyad': 3, 'solar_return': 7});

void main() {
  group('onayGerekli (saf)', () {
    test('eşik ve üstü, onaysız → sorulur', () {
      expect(onayGerekli(bedel: kOnayEsigi, onaylanmis: false), isTrue);
      expect(onayGerekli(bedel: 9, onaylanmis: false), isTrue);
    });

    test('eşik altı → sorulmaz (sohbet 1, İ Ching 2, ikili 3)', () {
      expect(onayGerekli(bedel: kOnayEsigi - 1, onaylanmis: false), isFalse);
      expect(onayGerekli(bedel: 1, onaylanmis: false), isFalse);
    });

    test('bedel bilinmiyor → sorulmaz (ölçülmeyen söylenmez)', () {
      expect(onayGerekli(bedel: null, onaylanmis: false), isFalse);
    });

    test('bir kez onaylandıysa bir daha sorulmaz', () {
      expect(onayGerekli(bedel: 9, onaylanmis: true), isFalse);
    });

    test('eşik 5 — aylık hakkın %5\'i (ürün kararı)', () {
      expect(kOnayEsigi, 5);
    });

    test('tercih anahtarı özellik başına, sunucu adıyla', () {
      expect(bedelOnayAnahtari(PlusOzellik.bazi), 'bedelOnayi_bazi');
      expect(bedelOnayAnahtari(PlusOzellik.solarReturn),
          'bedelOnayi_solar_return');
    });
  });

  group('BedelKapisi (widget)', () {
    testWidgets('abone + 5 kredi + onaysız → kart, builder ÇAĞRILMAZ',
        (tester) async {
      final l10n = _tr();
      final d = _depo(onayli: false);
      final kurulanlar = <String>[];
      await tester.pumpWidget(_sar(
          kapi: PlusHali.abone,
          cuzdan: _bes,
          depo: d.depo,
          ozellik: PlusOzellik.bazi,
          kurulanlar: kurulanlar));
      await _bekle(tester);

      expect(find.text(l10n.costConfirmTitle(5)), findsOneWidget);
      expect(find.text(l10n.costConfirmBody), findsOneWidget);
      expect(find.text(l10n.costConfirmContinue), findsOneWidget);
      expect(find.text(l10n.costConfirmCancel), findsOneWidget);
      expect(find.text('ICERIK'), findsNothing);
      expect(kurulanlar, isEmpty,
          reason: 'sağlayıcı onaydan ÖNCE izlenirse istek gitmiş olur');
      expect(d.yazilanlar, isEmpty);
    });

    testWidgets('"Devam" → içerik kurulur, tercih yazılır', (tester) async {
      final l10n = _tr();
      final d = _depo(onayli: false);
      final kurulanlar = <String>[];
      await tester.pumpWidget(_sar(
          kapi: PlusHali.abone,
          cuzdan: _bes,
          depo: d.depo,
          ozellik: PlusOzellik.bazi,
          kurulanlar: kurulanlar));
      await _bekle(tester);

      await tester.tap(find.text(l10n.costConfirmContinue));
      await _bekle(tester);

      expect(find.text('ICERIK'), findsOneWidget);
      expect(kurulanlar, ['bazi']);
      expect(d.yazilanlar, ['bedelOnayi_bazi']);
    });

    testWidgets('daha önce onaylanmışsa kart yok, içerik hemen',
        (tester) async {
      final d = _depo(onayli: true);
      final kurulanlar = <String>[];
      await tester.pumpWidget(_sar(
          kapi: PlusHali.abone,
          cuzdan: _bes,
          depo: d.depo,
          ozellik: PlusOzellik.bazi,
          kurulanlar: kurulanlar));
      await _bekle(tester);

      expect(find.text('ICERIK'), findsOneWidget);
      expect(find.text(_tr().costConfirmContinue), findsNothing);
    });

    testWidgets('eşik altı bedel (ikili 3) → kapı yok', (tester) async {
      final d = _depo(onayli: false);
      final kurulanlar = <String>[];
      await tester.pumpWidget(_sar(
          kapi: PlusHali.abone,
          cuzdan: _bes,
          depo: d.depo,
          ozellik: PlusOzellik.dyad,
          kurulanlar: kurulanlar));
      await _bekle(tester);

      expect(find.text('ICERIK'), findsOneWidget);
      expect(kurulanlar, ['dyad']);
    });

    testWidgets('abone DEĞİL → kapı yok (harcanacak bir şey yok)',
        (tester) async {
      final d = _depo(onayli: false);
      final kurulanlar = <String>[];
      await tester.pumpWidget(_sar(
          kapi: PlusHali.aboneDegil,
          cuzdan: _bes,
          depo: d.depo,
          ozellik: PlusOzellik.bazi,
          kurulanlar: kurulanlar));
      await _bekle(tester);

      expect(find.text('ICERIK'), findsOneWidget);
      expect(find.text(_tr().costConfirmContinue), findsNothing);
    });

    testWidgets('bedel BİLİNMİYOR (cüzdan okunamadı) → kapı yok, soru yok',
        (tester) async {
      final d = _depo(onayli: false);
      final kurulanlar = <String>[];
      await tester.pumpWidget(_sar(
          kapi: PlusHali.abone,
          cuzdan: WalletStatus.unknown,
          depo: d.depo,
          ozellik: PlusOzellik.bazi,
          kurulanlar: kurulanlar));
      await _bekle(tester);

      // "Bu okuma ? kredi" diye bir soru yok; ölçülmeyen söylenmez.
      expect(find.text('ICERIK'), findsOneWidget);
      expect(find.textContaining('kredi'), findsNothing);
    });

    testWidgets('cüzdan YÜKLENİRKEN iskelet — builder çağrılmaz',
        (tester) async {
      final d = _depo(onayli: false);
      final kurulanlar = <String>[];
      final cuzdan = Completer<WalletStatus>();
      await tester.pumpWidget(ProviderScope(
        overrides: [
          raporKapisiProvider.overrideWithValue(PlusHali.abone),
          walletProvider.overrideWith((_) => cuzdan.future),
          onayDeposuProvider.overrideWithValue(d.depo),
        ],
        child: MaterialApp(
          locale: const Locale('tr'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: BedelKapisi(
              ozellik: PlusOzellik.bazi,
              builder: (context, ref) {
                kurulanlar.add('bazi');
                return const Text('ICERIK');
              },
            ),
          ),
        ),
      ));
      await _bekle(tester);

      // İlk kare deliği: `.value` null diye "bilinmiyor → geç" denirse
      // istek onaysız gider.
      expect(find.byType(SkeletonList), findsOneWidget);
      expect(kurulanlar, isEmpty);

      cuzdan.complete(_bes);
      await _bekle(tester);
      expect(find.text(_tr().costConfirmTitle(5)), findsOneWidget);
      expect(kurulanlar, isEmpty);
    });

    testWidgets('tercih okunana kadar iskelet — ne soru ne içerik',
        (tester) async {
      final kurulanlar = <String>[];
      // Okuma hiç tamamlanmıyor.
      final OnayDeposu asili = (
        oku: (_) => Future<bool>.delayed(const Duration(days: 1), () => true),
        yaz: (_) async {},
      );
      await tester.pumpWidget(_sar(
          kapi: PlusHali.abone,
          cuzdan: _bes,
          depo: asili,
          ozellik: PlusOzellik.bazi,
          kurulanlar: kurulanlar));
      await _bekle(tester);

      expect(find.byType(SkeletonList), findsOneWidget);
      expect(find.text('ICERIK'), findsNothing);
      expect(kurulanlar, isEmpty);
      // Asılı zamanlayıcı testten taşmasın.
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(days: 1));
    });
  });

  group('Kaynak bekçisi: dört ekranda sağlayıcı kapının İÇİNDE', () {
    const ekranlar = {
      'lib/features/atlas/solar_return_screen.dart': (
        'solarReturnProvider',
        'solarReturn'
      ),
      'lib/features/atlas/inner_calendar_screen.dart': (
        'innerCalendarProvider',
        'progressions'
      ),
      'lib/features/atlas/birth_hexagram_screen.dart': (
        'birthHexagramProvider',
        'birthHexagram'
      ),
      'lib/features/oracle/bazi_tab.dart': ('baziReportProvider', 'bazi'),
    };
    for (final girdi in ekranlar.entries) {
      test('${girdi.key}: izleme BedelKapisi(ten sonra, doğru üye', () {
        final k = _yorumsuz(girdi.key);
        final kapi = k.indexOf('BedelKapisi(');
        final izleme = k.indexOf('ref.watch(${girdi.value.$1})');
        // Yanlış katalog üyesi (bedelsiz `daily` gibi) kapıyı sessizce
        // kapatır: bedel null → soru yok.
        expect(k, contains('ozellik: PlusOzellik.${girdi.value.$2},'));
        expect(kapi, greaterThanOrEqualTo(0), reason: 'kapı yok');
        expect(izleme, greaterThanOrEqualTo(0), reason: 'izleme yok');
        expect(izleme, greaterThan(kapi),
            reason: 'sağlayıcı kapıdan ÖNCE izleniyor — istek onaysız gider');
        // Tek izleme: ikinci bir `ref.watch(<sağlayıcı>)` kapının dışında
        // durup aynı isteği onaysız atabilirdi.
        expect('ref.watch(${girdi.value.$1})'.allMatches(k).length, 1);
      });
    }
  });
}
