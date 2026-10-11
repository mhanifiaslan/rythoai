// D6 bekçileri — BaZi sekmesinin hoşgörülü ayrıştırması ve şans yönü beyanı.
//
// İki ölçülmüş kusur:
//  1. `chart['missing_elements'] as List` hoşgörüsüz cast'ti: alan
//     gelmezse `Null is not a List` fırlar ve sekmenin TAMAMI çöker (Yıl
//     Haritası aynı riski bir üretim olayından sonra kapatmıştı, BaZi
//     kapatmamıştı — anlam_once_bes_ekran_test'in yük yorumunda kayıtlı).
//  2. Cinsiyet belirtilmemişse sunucu şans yönünü HESAPLAMAZ:
//     `luck_direction_known == false`, `luck_pillars` BOŞ, iki aday
//     `luck_pillar_candidates` altında (bazi_service.py:465-483). Alanın
//     okuyucusu yoktu — sekme 104 px'lik boş bir şerit çiziyor, beyan
//     etmiyordu ("okuyucusu olmayan" sınıfı, D0 notu).
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:rytho/core/providers.dart';
import 'package:rytho/features/oracle/bazi_tab.dart';
import 'package:rytho/l10n/app_localizations.dart';
import 'package:rytho/l10n/app_localizations_tr.dart';
import 'package:rytho/theme/rytho_theme.dart';

final _tr = AppLocalizationsTr();

Widget _sar(Widget govde, {List<Override> overrides = const []}) =>
    ProviderScope(
      overrides: overrides,
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
        home: Scaffold(body: govde),
      ),
    );

/// Uzun yüzey: `ListView` tembel, şans paneli sayfanın dibinde.
void _uzunYuzey(WidgetTester tester) {
  tester.view.physicalSize = const Size(420, 2800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

Future<void> _yerles(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 1500));
  await tester.pump(const Duration(milliseconds: 1500));
}

Map<String, dynamic> _sutun(String stem, String branch, String hayvan) => {
      'stem': {'cn': stem, 'element': 'Ahşap'},
      'branch': {'cn': branch, 'animal': hayvan, 'hidden': <Map>[]},
    };

Map<String, dynamic> _sans(int yil, String stem, String branch) => {
      'from_year': yil,
      'to_year': yil + 10,
      'from_age': 6,
      'to_age': 16,
      'stem': {'cn': stem},
      'branch': {'cn': branch},
      'ten_god': {'name': 'Jie Cai'},
    };

/// Sekmenin okuduğu çekirdek; `ek` ile alan eklenir/üzerine yazılır.
Map<String, dynamic> _harita(Map<String, dynamic> ek) => {
      'zodiac_animal': 'Köpek',
      'day_master': {'description': 'Yang Ahşap'},
      'pillars': {
        'year': _sutun('甲', '戌', 'Köpek'),
        'month': _sutun('壬', '申', 'Maymun'),
        'day': _sutun('戊', '子', 'Sıçan'),
        'hour': null,
      },
      'ten_gods': <String, dynamic>{},
      'notes': <String>[],
      'element_distribution': {'Ahşap': 2.4},
      'shen_sha': <Map<String, dynamic>>[],
      ...ek,
    };

List<Override> _overrides(Map<String, dynamic> chart) => [
      raporKapisiProvider.overrideWithValue(PlusHali.abone),
      baziReportProvider.overrideWith(
          (ref) async => {'chart': chart, 'report': 'GERÇEK BaZi raporu.'}),
    ];

void main() {
  testWidgets('missing_elements ve luck_pillars GELMEZSE sekme çökmez',
      (tester) async {
    // Eski sunucu / eksik gövde: iki alan da yok. Hoşgörülü ayrıştırma
    // satırı gizler, haritayı çizer.
    _uzunYuzey(tester);
    await tester.pumpWidget(_sar(const BaziTab(),
        overrides: _overrides(_harita(const {}))));
    await _yerles(tester);

    expect(tester.takeException(), isNull,
        reason: 'hoşgörüsüz cast sekmenin tamamını çökertiyor');
    expect(find.text('戊'), findsWidgets, reason: 'harita çizilmedi');
    expect(find.textContaining('GERÇEK BaZi raporu.'), findsOneWidget);
    // Eksik element yoksa besleme satırı da yok (boş liste gibi).
    expect(find.textContaining(_tr.baziNourish('')), findsNothing);
  });

  testWidgets('eksik element satırı listeyle gelir', (tester) async {
    _uzunYuzey(tester);
    await tester.pumpWidget(_sar(const BaziTab(),
        overrides: _overrides(_harita({
          'missing_elements': ['Ateş'],
        }))));
    await _yerles(tester);

    expect(find.text(_tr.baziNourish('Ateş')), findsOneWidget);
  });

  group('şans yönü', () {
    testWidgets('BİLİNMİYOR: beyan + iki aday dizi, "şimdi" etiketi yok',
        (tester) async {
      _uzunYuzey(tester);
      await tester.pumpWidget(_sar(const BaziTab(),
          overrides: _overrides(_harita({
            'luck_pillars': <Map<String, dynamic>>[],
            'luck_direction_known': false,
            'current_luck_index': null,
            'luck_pillar_candidates': {
              'forward': {
                'luck_pillars': [_sans(2001, '乙', '亥')],
                'luck_start': null,
              },
              'backward': {
                'luck_pillars': [_sans(1999, '癸', '酉')],
                'luck_start': null,
              },
            },
          }))));
      await _yerles(tester);

      expect(find.text(_tr.baziLuckDirectionUnknown), findsOneWidget,
          reason: 'yön hesaplanmadı ama ekran söylemiyor');
      expect(find.text(_tr.baziLuckCandidatesLabel), findsOneWidget);
      // İki aday da ekranda — biri seçilip "senin dönemin" diye sunulmaz.
      expect(find.text('2001-2011'), findsOneWidget);
      expect(find.text('1999-2009'), findsOneWidget);
      expect(find.textContaining(_tr.baziCurrentTag), findsNothing,
          reason: 'hangi dizinin gerçek olduğu bilinmezken "şimdi" yalan');
    });

    testWidgets('BİLİNİYOR: beyan yok, dizi ve aktif dönem var',
        (tester) async {
      _uzunYuzey(tester);
      await tester.pumpWidget(_sar(const BaziTab(),
          overrides: _overrides(_harita({
            'luck_pillars': [_sans(2000, '甲', '戌')],
            'luck_direction_known': true,
            'current_luck_index': 0,
            'luck_pillar_candidates': null,
          }))));
      await _yerles(tester);

      expect(find.text(_tr.baziLuckDirectionUnknown), findsNothing);
      expect(find.text(_tr.baziLuckCandidatesLabel), findsNothing);
      expect(find.textContaining('2000-2010'), findsOneWidget);
      expect(find.textContaining(_tr.baziCurrentTag), findsOneWidget);
    });
  });
}
