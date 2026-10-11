// Gömülü çark SALT ÖNİZLEME (D6): dokunuş Harita İnceleme'yi açar,
// gezegen/açı alt-sayfaları yalnız İnceleme'de.
//
// `ChartWheel.onTap` verilince isabet çözümlemesi yapılmaz; çark ekran
// okuyucuya düğme olur. "Şu an gökyüzünde" bu sözleşmenin ilk tüketicisi;
// Atlas ve kişi detayı kendi turunda göçer (varsayılan eski davranış).
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:rytho/core/providers.dart';
import 'package:rytho/features/atlas/chart_inspector_screen.dart';
import 'package:rytho/features/sky/sky_now_screen.dart';
import 'package:rytho/l10n/app_localizations.dart';
import 'package:rytho/main.dart' show kMaxTextScale;
import 'package:rytho/theme/rytho_theme.dart';
import 'package:rytho/widgets/chart/chart_wheel.dart';

String _yorumsuz(String yol) => File(yol)
    .readAsStringSync()
    .replaceAll('\r\n', '\n')
    .split('\n')
    .where((s) => !s.trimLeft().startsWith('//'))
    .join('\n');

/// GET /sky/now yükü — `ChartData.fromSky` sözleşmesiyle (longitude,
/// degree_in_sign, orb, *_local).
final _gokyuzu = <String, dynamic>{
  'timestamp_utc': '2026-10-10T09:00:00Z',
  'moon_phase': {'emoji': '🌒', 'name': 'Hilal', 'illumination': '%18'},
  'retrogrades': ['Satürn'],
  'planets': [
    {'name': 'Sun', 'name_local': 'Güneş', 'longitude': 197.2,
      'sign': 'libra', 'degree_in_sign': 17.2},
    {'name': 'Moon', 'name_local': 'Ay', 'longitude': 40.5,
      'sign': 'taurus', 'degree_in_sign': 10.5},
    {'name': 'Saturn', 'name_local': 'Satürn', 'longitude': 2.1,
      'sign': 'aries', 'degree_in_sign': 2.1, 'retrograde': true},
  ],
  'aspects': [
    {'p1': 'Sun', 'p2': 'Saturn', 'aspect': 'opposition', 'orb': 4.9,
      'p1_local': 'Güneş', 'p2_local': 'Satürn', 'aspect_local': 'Karşıt',
      'movement': 'applying'},
    {'p1': 'Moon', 'p2': 'Saturn', 'aspect': 'sextile', 'orb': 1.6,
      'p1_local': 'Ay', 'p2_local': 'Satürn', 'aspect_local': 'Altmışlık'},
  ],
};

Widget _sar(Widget child, {double genislik = 400, double olcek = 1.0}) =>
    ProviderScope(
      overrides: [
        skyNowProvider.overrideWith((ref) async => _gokyuzu),
      ],
      child: MaterialApp(
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('tr'),
        theme: buildRythoTheme(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(olcek),
            disableAnimations: true,
          ),
          child: child!,
        ),
        home: child,
      ),
    );

void main() {
  GoogleFonts.config.allowRuntimeFetching = false;

  // `ChartWheel.onTap` sözleşmesinin kendisi cark_onizleme_sozlesme_test'te
  // (yalnız çark grafiği); burada EKRAN tüketicisi ölçülür.
  group('"Şu an gökyüzünde" gömülü çark', () {
    testWidgets('çark onTap taşır, gezegen/açı geri çağrısı YOK; dokunuş '
        'İnceleme\'yi açar', (tester) async {
      await tester.pumpWidget(_sar(const SkyNowScreen()));
      await tester.pump();
      await tester.pump();

      final cark = tester.widget<ChartWheel>(find.byType(ChartWheel));
      expect(cark.onTap, isNotNull, reason: 'gömülü çark salt önizleme değil');
      expect(cark.onPlanetTap, isNull,
          reason: 'iki etkileşim modeli yan yana — alt-sayfa yalnız İnceleme\'de');
      expect(cark.onAspectTap, isNull);
      expect(cark.interactive, isFalse);

      await tester.tap(find.byType(ChartWheel));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();
      expect(find.byType(ChartInspectorScreen), findsOneWidget,
          reason: 'dokunuş Harita İnceleme\'yi açmalı');
    });

    testWidgets('çark panelin kısıtına sığar — ClipRect kırpması yok',
        (tester) async {
      await tester.pumpWidget(_sar(const SkyNowScreen()));
      await tester.pump();
      await tester.pump();
      final cark = tester.getRect(find.byType(ChartWheel));
      final ekran = tester.getRect(find.byType(SkyNowScreen));
      // Çark liste dolgusu (16) + kart kenarı (16) + iç dolgu (8) içinde:
      // eski `genişlik - 72` hesabı 8 px taşıyordu.
      expect(cark.left, greaterThanOrEqualTo(ekran.left + 40 - 0.5));
      expect(cark.right, lessThanOrEqualTo(ekran.right - 40 + 0.5));
      // Kırpmanın GERÇEK ölçüsü: istenen `size` ile çizilen kutu aynı mı.
      // Üstteki iki satır tek başına KÖRDÜ (mutasyonla ölçüldü): fazla
      // büyük çark kısıt tarafından kutuda kelepçelenir, ressam `size`
      // ile çizer ve ClipRect sessizce keser — kutu yine dolgunun içinde.
      final istenen = tester.widget<ChartWheel>(find.byType(ChartWheel)).size;
      expect(cark.width, moreOrLessEquals(istenen, epsilon: 0.5),
          reason: 'çark istediğinden küçük çizildi — kısıt kırpıyor');
    });

    testWidgets('320 dp × 1,3 yazı ölçeğinde taşmaz', (tester) async {
      tester.view.physicalSize = const Size(320 * 3, 800 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
          _sar(const SkyNowScreen(), genislik: 320, olcek: kMaxTextScale));
      await tester.pump();
      await tester.pump();
      expect(tester.takeException(), isNull, reason: 'gövde taşıyor');
      expect(find.byType(ChartWheel), findsOneWidget);
    });

    test('kaynak: gezegen alt-sayfası gömülü çarktan ÇIKTI', () {
      final k = _yorumsuz('lib/features/sky/sky_now_screen.dart');
      expect(k, isNot(contains('showPointSheet')),
          reason: 'gezegen alt-sayfası yalnız İnceleme\'de');
      expect(k, isNot(contains('pointSheetMap')));
      expect(k, contains('onTap: incelemeyiAc'));
      expect(k, contains('LayoutBuilder('));
      expect(k, isNot(contains('size.width - 72')),
          reason: 'dolgu varsayımına dayalı boyut geri gelmiş (8 px kırpma)');
      // Ay evresi emojisi rol adıyla: çıplak TextStyle değil.
      expect(k, contains('RythoText.emoji('));
      expect(k, isNot(contains('TextStyle(fontSize')));
    });
  });
}
