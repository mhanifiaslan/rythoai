// D6 bekçileri — Atlas dizini: 2×2 kehanet ızgarası, tek liste satırı,
// tek kilit rozeti, tek paywall kapısı, dizin sonunda sohbet kapısı.
//
// Ölçülen hâl: dört karo tek satırda ~80 dp genişlikteydi ve başlıklar
// "…" ile kırpılıyordu (design-system §9b: başlıkta ellipsis yok); kilit
// bir karoda çıplak gri ikon, satırda `🔒` emojisi; paywall iki yerden düz
// `MaterialPageRoute(fullscreenDialog: true)` ile açılıyordu (kaynak
// etiketi ve özellik taşınmıyordu).
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rytho/core/providers.dart';
import 'package:rytho/features/atlas/atlas_screen.dart';
import 'package:rytho/l10n/app_localizations.dart';
import 'package:rytho/l10n/app_localizations_tr.dart';
import 'package:rytho/main.dart' show kMaxTextScale;
import 'package:rytho/theme/rytho_theme.dart';
import 'package:rytho/widgets/atlas_widgets.dart' show RythoyaSor;
import 'package:rytho/widgets/liste_satiri.dart';

final _tr = AppLocalizationsTr();

String _yorumsuz(String yol) => File(yol)
    .readAsStringSync()
    .replaceAll('\r\n', '\n')
    .split('\n')
    .where((s) => !s.trimLeft().startsWith('//'))
    .join('\n');

/// Atlas'ı dar ekranda (320 dp × `kMaxTextScale`) uzun bir yüzeye kurar.
///
/// Harita BOŞ natal yük (nokta/ev/açı yok): çark boş çizilir, dizin
/// tamamen kurulur. Gökyüzü sağlayıcısı HİÇ dönmez (bölüm `loading`
/// dalında boş); abonelik açık, natal rapor `null` (kilitli satır).
Future<void> _darAtlas(WidgetTester tester, {required bool abone}) async {
  tester.view.physicalSize = const Size(320, 2600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  final hal = abone ? PlusHali.abone : PlusHali.aboneDegil;
  await tester.pumpWidget(ProviderScope(
    overrides: [
      natalChartProvider.overrideWith((ref) async => <String, dynamic>{
            'points': <Map<String, dynamic>>[],
            'houses': <Map<String, dynamic>>[],
            'aspects': <Map<String, dynamic>>[],
          }),
      skyNowProvider
          .overrideWith((ref) => Completer<Map<String, dynamic>>().future),
      aboneHaliProvider.overrideWithValue(hal),
      raporKapisiProvider.overrideWithValue(hal),
      natalReportProvider.overrideWith((ref) async => null),
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
        data: MediaQuery.of(context).copyWith(
            textScaler: const TextScaler.linear(kMaxTextScale),
            disableAnimations: true),
        child: child!,
      ),
      home: const AtlasScreen(),
    ),
  ));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 1500));
  await tester.pump(const Duration(milliseconds: 1500));
}

void main() {
  group('gerçek ağaç — 320 dp × 1,3', () {
    testWidgets('dizin taşmaz; karolar 2×2; dizin sonu Rytho\'ya sor',
        (tester) async {
      await _darAtlas(tester, abone: true);
      expect(tester.takeException(), isNull, reason: 'dar ekranda taşma');

      // Dizin satırları tek bileşenden: 3 (bana dair) + 1 (tam rapor) +
      // 2 (zaman).
      expect(find.byType(ListeSatiri), findsNWidgets(6));

      // 2×2: ilk iki karo aynı satırda, üçüncüsü ALTTA.
      final yuz = tester.getTopLeft(find.text(_tr.faceReadingTitle)).dy;
      final iching = tester.getTopLeft(find.text(_tr.iChing)).dy;
      final bazi = tester.getTopLeft(find.text(_tr.baZi)).dy;
      final kapi = tester.getTopLeft(find.text(_tr.birthHexagram)).dy;
      expect(yuz, iching, reason: 'ilk satırın iki karosu hizalı değil');
      expect(bazi, kapi, reason: 'ikinci satırın iki karosu hizalı değil');
      expect(bazi, greaterThan(yuz), reason: 'dört karo tek satıra dönmüş');

      // Dizinin sonunda sohbet kapısı, tohumu Atlas'ın kendi anahtarı.
      final sor = find.byType(RythoyaSor);
      expect(sor, findsOneWidget);
      expect(tester.getTopLeft(sor).dy, greaterThan(kapi),
          reason: 'sohbet kapısı dizinin sonunda değil');
    });

    testWidgets('abone değil: dört karo kilitli, kilit TEK rozet',
        (tester) async {
      await _darAtlas(tester, abone: false);
      expect(tester.takeException(), isNull);
      // Kilit rozeti: altın diskli `lock_rounded` (KilitRozeti). Dört karo
      // + kilitli tam rapor satırı = 5 kilit ikonu; `🔒` emojisi hiç yok.
      expect(find.byIcon(Icons.lock_rounded), findsNWidgets(5));
      expect(find.text('🔒'), findsNothing);
    });
  });

  group('kaynak', () {
    final k = _yorumsuz('lib/features/atlas/atlas_screen.dart');

    test('paywall yalnız acPaywall ile; kaynak ve özellik taşınır', () {
      expect(k, isNot(contains('PaywallScreen(')),
          reason: 'paywall doğrudan itiliyor; kaynak etiketi kaybolur');
      expect(k, isNot(contains('fullscreenDialog')));
      expect(k, contains('kaynak: PaywallKaynak.atlasRapor'));
      expect(k, contains('kaynak: PaywallKaynak.atlasKaro'));
      expect(k, contains('ozellik: PlusOzellik.natal'));
    });

    test('liste satırı, segment ve kilit tek bileşenden', () {
      expect(k, isNot(contains('class _AtlasRow')));
      expect(k, contains('ListeSatiri('));
      expect(k, isNot(contains('class _WheelSegment')));
      expect(k, contains('GlassSegments('));
      expect(k, contains('KilitRozeti(kucuk: true)'));
      expect(k, isNot(contains('Icons.lock_rounded')),
          reason: 'çıplak kilit ikonu geri gelmiş');
      expect(k, isNot(contains("'🔒'")));
    });

    test('karo başlığında ellipsis YOK, iki satır', () {
      final karo = k.substring(k.indexOf('class _DivinationTile'));
      expect(karo, contains('Text(title, maxLines: 2, style: RythoType.cardTitle)'));
      // Başlık satırı yukarıda birebir (ellipsis yok); alt yazıda ellipsis
      // meşru (ListeSatiri ile aynı). Tek satıra düşüş iki yerde de yasak.
      expect(karo, isNot(contains('maxLines: 1')));
    });

    test('ızgara 2×2 kurulur, karo emojisi katalogdan', () {
      final govde = k.substring(k.indexOf('class _DivinationRow'));
      expect(govde, contains('karolar[satir * 2 + 1]'),
          reason: 'iki sütunlu ızgara yapısı gitmiş');
      expect(govde, isNot(contains("emoji: '")),
          reason: 'karo emojisi elle yazılmış; katalogla ayrışır');
      expect(govde, contains('ozellik: PlusOzellik.face'));
    });

    test('bölüm hataları ErrorCard(onRetry)', () {
      expect(k, contains('onRetry: () => ref.invalidate(natalChartProvider)'));
      expect(k, contains('onRetry: () => ref.invalidate(skyNowProvider)'));
      expect(k, isNot(contains('EdgeInsets.all(32)')),
          reason: 'çıplak Center(Text(friendlyError)) geri gelmiş');
    });

    test('stagger kopyası yok; kademeli giriş RythoReveal', () {
      expect(k, isNot(contains('.animate(')));
      expect(k, isNot(contains('next()')));
      expect(k, contains('RythoReveal('));
    });

    test('tarih etiketi tek kaynaktan (döngü kurmadan)', () {
      // `bugununEtiketi` okuma kabında: `atlas_screen → oracle_screen →
      // bazi_tab` zinciri Atlas'a geri dönemez.
      expect(k, isNot(contains('String bugununEtiketi()')));
      expect(k, contains("show bugununEtiketi"));
    });
  });
}
