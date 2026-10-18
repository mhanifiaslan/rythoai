// D6 bekçileri — derinlik yüzeylerinin TEK okuma kabı (`OkumaKabi`).
//
// Ölçülen hâl (2026-10-10): dokuz LLM okuma yüzeyinin beşi `fallback`
// bayrağını HİÇ okumuyordu; sunucunun şablon paragrafı rapor gibi duruyor,
// Yıl Haritası onu paylaşım KARTINA bile basıyordu. Bayrağı okuyan tek
// nokta artık `okumaDurumuFromYanit`, çizen tek widget `OkumaKabi`:
// üretilemedi → dürüst cümle + Tekrar dene, paylaşım YOK; hazır → okuma +
// paylaş + Rytho'ya sor.
//
// Bu dosya dört ekranı GERÇEK ağaçta ölçüyor (sağlayıcı override'ı
// yetiyor); İ Ching'in `_HexagramView`i özel ve çekimin tamamını ister —
// onun kaynak bekçisi `kehanet_iching_test.dart` ve
// `anlam_once_bes_ekran_test.dart`ta.
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// `Override` türü flutter_riverpod 3'te misc.dart'tan geliyor.
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:rytho/core/wallet.dart' show WalletStatus, walletProvider;
import 'package:flutter_test/flutter_test.dart';
import 'package:rytho/core/providers.dart';
import 'package:rytho/features/atlas/birth_hexagram_screen.dart';
import 'package:rytho/features/atlas/inner_calendar_screen.dart';
import 'package:rytho/features/atlas/solar_return_screen.dart';
import 'package:rytho/features/oracle/bazi_tab.dart';
import 'package:rytho/l10n/app_localizations.dart';
import 'package:rytho/l10n/app_localizations_tr.dart';
import 'package:rytho/main.dart' show kMaxTextScale;
import 'package:rytho/theme/rytho_theme.dart';
import 'package:rytho/widgets/atlas_widgets.dart' show MarginNote, RythoyaSor;
import 'package:rytho/widgets/common.dart' show ErrorCard;
import 'package:rytho/widgets/motion.dart' show StagedWaiting;
import 'package:rytho/widgets/okuma_kabi.dart' show PaylasKapisi;

final _tr = AppLocalizationsTr();

/// Kaynak bekçisi yorumları atar — bir şeyin YOKLUĞUNU ararken kendi
/// açıklamasına takılmasın (depoda iki kez patladı).
String _yorumsuz(String yol) => File(yol)
    .readAsStringSync()
    .replaceAll('\r\n', '\n')
    .split('\n')
    .where((s) => !s.trimLeft().startsWith('//'))
    .join('\n');

/// Ekranı UZUN bir yüzeye kurar (ListView tembel; dipteki kapı kurulsun)
/// ve istenirse dar ekran + büyük yazı ölçeğiyle (320 dp × `kMaxTextScale`).
Widget _sar(Widget govde,
        {List<Override> overrides = const [], double olcek = 1.0}) =>
    ProviderScope(
      // Bedel kapısı (D7) cüzdanı izliyor: `unknown` → kapı sorulmaz,
      // ekran kapı öncesi davranışında kalır; gerçek sağlayıcı Dio'ya
      // çıkıp zamanlayıcı bırakırdı. Bu dosyadaki testler cüzdanı kendileri
      // vermiyor (ölçüldü); veren bir test eklenirse Riverpod yineleneni
      // reddeder ve varsayılan o testte parametreye taşınır.
      overrides: [
        walletProvider.overrideWith((_) async => WalletStatus.unknown),
        ...overrides,
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
              disableAnimations: true,
              textScaler: TextScaler.linear(olcek)),
          child: child!,
        ),
        home: govde,
      ),
    );

void _yuzey(WidgetTester tester, {double genislik = 420}) {
  tester.view.physicalSize = Size(genislik, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

/// `pumpAndSettle` KULLANILMAZ: yıldız alanı ve usturlap sürekli animatör.
/// İç Mevsim ve Yıl Haritası'nda hazır okuma KATLI başlıyor (2026-10-18);
/// okumayı ölçen testler önce katı açar. Katı olmayan ekranda iş yapmaz.
Future<void> _okumayiAc(WidgetTester tester) async {
  final kat = find.text(AppLocalizationsTr().readingFullToggle);
  if (kat.evaluate().isEmpty) return;
  await tester.tap(kat);
  await _yerles(tester);
}

Future<void> _yerles(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 1500));
  await tester.pump(const Duration(milliseconds: 1500));
}

// ---------------------------------------------------------------------------
// Sahte yükler — her ekranın GERÇEKTEN okuduğu alanlar; `yedek` sunucunun
// şablona düştüğü hâl (`fallback` + `refunded`).
// ---------------------------------------------------------------------------

const _okuma = 'ROOKUMA: bu donemde icine donup bakman istenen bir esik.';
const _sablon = 'SABLON: gokyuzu sakin, kendine iyi bak.';

Map<String, dynamic> _bayrak(bool yedek) =>
    yedek ? {'fallback': true, 'refunded': true} : const {};

Map<String, dynamic> _icTakvimYuku({bool yedek = false}) => {
      'progressions': {
        'report': yedek ? _sablon : _okuma,
        ..._bayrak(yedek),
        'progressions': {
          'prog_moon': {
            'sign_local': 'Yay',
            'position': '12.4',
            'phase_local': 'İlk dördün',
            'next_sign_at': '2027-03-04',
          },
          'solar_arc_hits': [
            {
              'directed_local': 'SA Güneş',
              'aspect_local': 'kare',
              'natal_local': 'Satürn',
              'exact_on': '2026-11-01',
            },
          ],
          'disclosure_texts': <String>['Doğum saati bilinmediği için ev yok.'],
        },
      },
      'calendar': {
        'active_now': [
          {
            'transit_local': 'Neptün',
            'aspect_local': 'kare',
            'natal_local': 'Venüs',
            'orb': '1.2',
            'movement': 'applying',
          },
        ],
        'disclosure_texts': <String>[],
      },
    };

Map<String, dynamic> _yilHaritasiYuku({bool yedek = false}) => {
      'report': yedek ? _sablon : _okuma,
      ..._bayrak(yedek),
      'solar_return': {
        'return_at_local': '2026-05-12T20:16:00+03:00',
        'next_return_at_local': '2027-05-13T02:04:00+03:00',
        'sr_ascendant': {'sign_local': 'Terazi', 'position': '8.1'},
        'sr_sun_house': 10,
        'sr_moon_local': 'Balık',
        'disclosure_texts': <String>['İstanbul için kuruldu.'],
      },
    };

Map<String, dynamic> _dogumKapisiYuku({bool yedek = false}) => {
      'report': yedek ? _sablon : _okuma,
      ..._bayrak(yedek),
      'gate_text': 'KAPIDOKUSU: temeli söküp yeniden döken bir damar.',
      'position': {
        'gate': 34,
        'line': 5,
        'longitude': '131.06',
        'alternate_gate': 35,
      },
      'alternate_hexagram': {'number': 35},
      'hexagram': {
        'unicode': '䷡',
        'name_local': 'Büyük Gücün Kudreti',
        'name_tr': 'Büyük Gücün Kudreti',
        'name': 'Da Zhuang',
        'name_cn': '大壯',
        'judgment': 'HUKUM metni.',
        'image': 'IMGE metni.',
        'line_texts': ['a', 'b', 'c', 'd', 'e', 'f'],
      },
    };

Map<String, dynamic> _sutun(String stem, String branch, String hayvan) => {
      'stem': {'cn': stem, 'element': 'Ahşap'},
      'branch': {
        'cn': branch,
        'animal': hayvan,
        'hidden': [
          {'pinyin': 'Wu'},
        ],
      },
    };

Map<String, dynamic> _baziYuku({bool yedek = false}) => {
      'report': yedek ? _sablon : _okuma,
      ..._bayrak(yedek),
      'chart': {
        'zodiac_animal': 'Köpek',
        'day_master': {'description': 'Yang Ahşap'},
        'pillars': {
          'year': _sutun('甲', '戌', 'Köpek'),
          'month': _sutun('壬', '申', 'Maymun'),
          'day': _sutun('戊', '子', 'Sıçan'),
          'hour': _sutun('丙', '辰', 'Ejder'),
        },
        'ten_gods': {
          'year': {'name': 'Jie Cai'},
        },
        'strength': {
          'ratio': 0.62,
          'verdict_name': 'GÜÇLÜ GÖVDE',
          'season_state_name': 'Wang',
          'favorable_names': ['Metal'],
          'components': <Map<String, dynamic>>[],
        },
        'notes': <String>['Gerçek güneş saati düzeltmesi: −77 dakika.'],
        'element_distribution': {'Ahşap': 2.4, 'Toprak': 3.1},
        'missing_elements': <String>['Ateş'],
        'shen_sha': <Map<String, dynamic>>[],
        'luck_pillars': [
          {
            'from_year': 2000,
            'to_year': 2010,
            'from_age': 6,
            'to_age': 16,
            'stem': {'cn': '甲'},
            'branch': {'cn': '戌'},
            'ten_god': {'name': 'Jie Cai'},
          },
        ],
        'current_luck_index': 0,
        'luck_direction_known': true,
      },
    };

/// Dört ekran: (ekran, yük, ölçümün ekrandaki izi).
typedef _Yuzey = ({
  String ad,
  Widget ekran,
  List<Override> Function(bool yedek) overrides,
  String olcumIzi,
});

final _yuzeyler = <_Yuzey>[
  (
    ad: 'İç mevsim',
    ekran: const InnerCalendarScreen(),
    overrides: (yedek) => [
          raporKapisiProvider.overrideWithValue(PlusHali.abone),
          innerCalendarProvider
              .overrideWith((ref) async => _icTakvimYuku(yedek: yedek)),
        ],
    olcumIzi: '12.4',
  ),
  (
    ad: 'Yıl Haritası',
    ekran: const SolarReturnScreen(),
    overrides: (yedek) => [
          raporKapisiProvider.overrideWithValue(PlusHali.abone),
          solarReturnProvider
              .overrideWith((ref) async => _yilHaritasiYuku(yedek: yedek)),
        ],
    olcumIzi: '2026-05-12',
  ),
  (
    ad: 'Doğum Kapısı',
    ekran: const BirthHexagramScreen(),
    overrides: (yedek) => [
          raporKapisiProvider.overrideWithValue(PlusHali.abone),
          birthHexagramProvider
              .overrideWith((ref) async => _dogumKapisiYuku(yedek: yedek)),
        ],
    olcumIzi: '131.06',
  ),
  (
    ad: 'BaZi',
    ekran: const BaziTab(),
    overrides: (yedek) => [
          raporKapisiProvider.overrideWithValue(PlusHali.abone),
          baziReportProvider
              .overrideWith((ref) async => _baziYuku(yedek: yedek)),
        ],
    olcumIzi: '戊',
  ),
];

void main() {
  // -------------------------------------------------------------------------
  group('yedek metin: ölçüm KALIR, şablon rapor gibi durmaz', () {
    for (final y in _yuzeyler) {
      testWidgets('${y.ad}: dürüst cümle + tekrar dene, paylaşım YOK',
          (tester) async {
        _yuzey(tester);
        await tester.pumpWidget(_sar(y.ekran, overrides: y.overrides(true)));
        await _yerles(tester);

        // Ölçülen çıktı yerinde: fırlatan sağlayıcı onu da götürürdü.
        expect(find.textContaining(y.olcumIzi), findsWidgets,
            reason: '${y.ad}: ölçüm silinmiş');
        expect(find.byType(ErrorCard), findsOneWidget,
            reason: '${y.ad}: üretilemedi dalı yok');
        expect(find.text(_tr.reportUnavailableRefunded), findsOneWidget,
            reason: '${y.ad}: iade cümlesi kullanıcıya söylenmiyor');
        expect(find.text(_tr.retry), findsOneWidget,
            reason: '${y.ad}: çıkış yolu yok');
        // Şablon KART OLAMAZ: paylaş kapısı yapısal olarak yok.
        expect(find.byType(PaylasKapisi), findsNothing,
            reason: '${y.ad}: şablon paylaşılabilir');
        expect(find.byType(MarginNote), findsNothing,
            reason: '${y.ad}: şablon paragraf rapor gibi duruyor');
        expect(find.textContaining('SABLON'), findsNothing);
      });
    }
  });

  // -------------------------------------------------------------------------
  group('hazır okuma: paylaş + Rytho\'ya sor kabın altında', () {
    for (final y in _yuzeyler) {
      testWidgets(y.ad, (tester) async {
        _yuzey(tester);
        await tester.pumpWidget(_sar(y.ekran, overrides: y.overrides(false)));
        await _yerles(tester);
        await _okumayiAc(tester);

        expect(find.byType(MarginNote), findsOneWidget);
        expect(find.textContaining('ROOKUMA'), findsOneWidget);
        expect(find.byType(PaylasKapisi), findsOneWidget,
            reason: '${y.ad}: paylaşım tek konumdan (kap) gelmiyor');
        expect(find.byType(RythoyaSor), findsOneWidget);
        expect(find.byType(ErrorCard), findsNothing);
        // Paylaş kapısı okumanın ALTINDA — AppBar'da değil.
        expect(tester.getTopLeft(find.byType(MarginNote)).dy,
            lessThan(tester.getTopLeft(find.byType(PaylasKapisi)).dy));
      });
    }
  });

  // -------------------------------------------------------------------------
  group('320 dp × 1,3 yazı ölçeği: taşma yok', () {
    for (final y in _yuzeyler) {
      testWidgets(y.ad, (tester) async {
        _yuzey(tester, genislik: 320);
        await tester.pumpWidget(_sar(y.ekran,
            overrides: y.overrides(false), olcek: kMaxTextScale));
        await _yerles(tester);
        await _okumayiAc(tester);
        expect(tester.takeException(), isNull,
            reason: '${y.ad}: dar ekranda taşma');
        expect(find.byType(RythoyaSor), findsOneWidget);
      });
    }
  });

  // -------------------------------------------------------------------------
  testWidgets('Doğum Kapısı: bekleme SAHNELİ (çıplak usturlap değil)',
      (tester) async {
    // Dört kardeş ekran aşamalı bekliyordu, burası tek usturlaptı.
    _yuzey(tester);
    await tester.pumpWidget(_sar(const BirthHexagramScreen(), overrides: [
      raporKapisiProvider.overrideWithValue(PlusHali.abone),
      birthHexagramProvider
          .overrideWith((ref) => Completer<Map<String, dynamic>?>().future),
    ]));
    await tester.pump();

    expect(find.byType(StagedWaiting), findsOneWidget);
    expect(find.text(_tr.birthHexagramWaitStage1), findsOneWidget);
    // Sahnenin zamanlayıcısı testi kirletmesin.
    await tester.pumpWidget(const SizedBox.shrink());
  });

  // -------------------------------------------------------------------------
  group('kaynak: kopyalar gitti, kap tek', () {
    const yuzeyler = [
      'lib/features/atlas/inner_calendar_screen.dart',
      'lib/features/atlas/solar_return_screen.dart',
      'lib/features/atlas/birth_hexagram_screen.dart',
      'lib/features/oracle/bazi_tab.dart',
      'lib/features/oracle/iching_tab.dart',
    ];

    for (final yol in yuzeyler) {
      test('$yol: stagger kopyası yok, kilit kartı katalogdan, iskelet tek',
          () {
        final k = _yorumsuz(yol);
        // Hareket: tek yol `RythoReveal`; `.animate(` çağrısı reduce-motion
        // kapısını kendi okumak zorunda kalırdı.
        expect(k, isNot(contains('.animate(')), reason: 'çıplak animate');
        expect(k, isNot(contains('blok(')), reason: 'blok kopyası');
        expect(k, isNot(contains('gecikme()')), reason: 'gecikme kopyası');
        expect(k, contains('RythoReveal('));
        // Kilit kartı özelliğini KATALOGDAN alır: paywall hangi
        // özellikten gelindiğini ancak böyle bilir.
        expect(k, contains('ozellik: ozellik'));
        expect(k, isNot(contains('emoji:')),
            reason: 'kilit kartı emoji köprüsünde kalmış');
        // Kart kabı tek (`GlassPanel`); `Plaque` silinecek sınıf.
        expect(RegExp(r'(?<![A-Za-z_])Plaque\(').hasMatch(k), isFalse,
            reason: 'Plaque kopyası');
        // İskelet tek kaynaktan.
        expect(k, contains('SkeletonList('));
        expect(k, isNot(contains('class _Iskelet')));
      });
    }

    test('İç mevsim: bayat gerekçe silindi', () {
      // "Bu uç fallback HİÇ DÖNDÜRMÜYOR" D0 sonrası YANLIŞTI ve okuyan tur
      // bayrak dalını kurmazdı. Ham metin (yorumlar dâhil) aranır.
      final ham = File('lib/features/atlas/inner_calendar_screen.dart')
          .readAsStringSync();
      expect(ham, isNot(contains('HİÇ DÖNDÜRMÜYOR')));
      expect(ham, isNot(contains('OKUNAMIYOR')));
    });

    test('Doğum Kapısı: aşama anahtarları ekranda, gelen metin değil', () {
      final k = _yorumsuz('lib/features/atlas/birth_hexagram_screen.dart');
      expect(k, contains('birthHexagramWaitStage1'));
      expect(k, contains('birthHexagramWaitStage2'));
      expect(k, isNot(contains('Center(child: AstrolabeSpinner())')));
    });

    test('Yıl Haritası: AppBar/satır içi paylaş düğmesi yok', () {
      // Şablonu karta basan `OutlinedButton.icon` kalktı; paylaşım kabın
      // `Hazir` dalında (rapor_uretilemedi_test bunu ayrıca çiviliyor).
      final k = _yorumsuz('lib/features/atlas/solar_return_screen.dart');
      expect(k, isNot(contains('OutlinedButton')));
      expect(k, contains('paylasim: PaylasimTarifi('));
    });
  });
}
