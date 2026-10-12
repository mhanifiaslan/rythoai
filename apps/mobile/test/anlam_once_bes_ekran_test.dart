// OKUMA ÖNDE, ÖLÇÜM ARKADA — beş teknik ekranın bekçileri (lifestyle turu).
//
// Sahibin tarifi: "Rytho'da teknik ifadeler ve teknik bir kart düzeni var,
// bu bir lifestyle uygulaması, dolayısıyla daha anlaşılırdan isteyenler için
// daha teknik bir yapıya gidilmeli."
//
// Ölçülen hâl (bu tur): beş ekranın BEŞİNDE de ilk görünen şey bir sayı,
// glif ya da mono satırdı; insan cümlesi (`MarginNote`) sayfanın EN SONUNDA,
// bütün ölçüm bloklarının arkasındaydı. Beşinin de HİÇBİR bekçisi yoktu —
// bu dosya yazılmadan önce sıra tersine çevrilebilir ve takım yeşil kalırdı
// (ölçüldü: değişiklikten sonra 838 test geçti, hiçbiri kırılmadı).
//
// ⚠️ BU DOSYANIN ÇİVİLEMEDİĞİ ŞEY: ölçümün KALDIRILMASI. Doktrin "ölçülen
// yanlış adla sunulmaz" ve "hesaplanmış olan silinmez". Dört sütun tablosu,
// progres Ay derecesi, dönüş anı, Güneş boylamı — hepsi YERİNDE. Testler
// yalnız SIRAYI tutuyor; bir bloğun varlığını kaldıran bir sonraki tur
// bu dosyadan izin alamaz, başka bekçilere çarpar
// (`rapor_uretilemedi_test`, `plus_kapisi_test`).
//
// ⚠️ İKİ EKRANDA OKUMA EN BAŞTA DEĞİL ve bu bilinçli: Doğum Kapısı'nın
// glifi ile İ Ching'in çekim glifi ÖLÇÜM DEĞİL, konunun KENDİSİ (İ Ching'de
// kullanıcı onu kendi eliyle üretti). Oralarda çivilenen şey "okuma glifin
// hemen altında ve bütün ölçümlerin üstünde".
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
import 'package:rytho/features/chat/chat_screen.dart';
import 'package:rytho/features/oracle/bazi_tab.dart';
import 'package:rytho/l10n/app_localizations.dart';
import 'package:rytho/l10n/app_localizations_tr.dart';
import 'package:rytho/theme/rytho_theme.dart';
import 'package:rytho/widgets/atlas_widgets.dart' show MarginNote, RythoyaSor;

final _tr = AppLocalizationsTr();

/// Kaynak bekçisi bir şeyin YOKLUĞUNU ararken kendi açıklama yorumuna
/// takılmasın: tam satır yorumları ve `///` belgeleri atılır. Bu tuzak bu
/// depoda iki kez patladı (build kapısı, davet sayfası testi).
String _yorumsuz(String yol) => File(yol)
    .readAsStringSync()
    .replaceAll('\r\n', '\n')
    .split('\n')
    .where((s) => !s.trimLeft().startsWith('//'))
    .join('\n');

/// İtilen rotaları toplar — sohbete gidildiğini ROTADAN doğruluyoruz.
///
/// NEDEN rotadan: `ChatScreen` çizdirilirse Firebase/cüzdan sağlayıcıları
/// ister ve test ürün hatası olmayan bir yerde düşer. Emsal depoda var
/// (`yeni_konusma_fab_test`): rotanın `builder`ı elle çağrılıp dönen
/// widget okunuyor, ağaç hiç monte edilmiyor.
class _RotaGozcusu extends NavigatorObserver {
  final itilenler = <Route<dynamic>>[];

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    itilenler.add(route);
  }
}

Widget _sar(Widget govde,
        {List<Override> overrides = const [], NavigatorObserver? gozcu}) =>
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
        navigatorObservers: gozcu != null ? [gozcu] : const [],
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: true),
          child: child!,
        ),
        home: govde,
      ),
    );

/// `pumpAndSettle` KULLANILMAZ: yıldız alanı ve `AstrolabeSpinner` sürekli
/// animatör, hiç dönmez. Kademeli giriş `RythoReveal` ve `disableAnimations`
/// açıkken hiç kurulmuyor; yine de 3 sn beklenir — kabın içindeki
/// `AnimatedSize`/geçişler ve ileride eklenecek bir gecikme ölçümü
/// yanıltmasın.
Future<void> _yerles(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 1500));
  await tester.pump(const Duration(milliseconds: 1500));
}

/// Ekranı UZUN bir yüzeye kurar.
///
/// NEDEN: `ListView` tembel çiziyor — 800×600 varsayılanında sayfanın
/// dibindeki "Rytho'ya sor" HİÇ kurulmaz ve `findsNothing` ürün kusuru
/// değil ölçüm kusuru olurdu. Sıra iddiası da aynı sebeple uzun yüzey
/// ister: karşılaştırılan iki blok da çizilmiş olmalı.
void _uzunYuzey(WidgetTester tester) {
  tester.view.physicalSize = const Size(420, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

/// Dokunuşun ittiği rotadan `ChatScreen`i çıkarır ve tohumunu döndürür.
String? _tohum(WidgetTester tester, _RotaGozcusu gozcu, Finder kok) {
  final rota = gozcu.itilenler.last;
  expect(rota, isA<MaterialPageRoute<dynamic>>());
  final widget = (rota as MaterialPageRoute<dynamic>)
      .builder(tester.element(kok));
  expect(widget, isA<ChatScreen>());
  return (widget as ChatScreen).initialText;
}

// ---------------------------------------------------------------------------
// Sahte yükler — her ekranın GERÇEKTEN okuduğu alanlar.
//
// Okuma metinleri TEK SATIR: uzun bir paragraf sayfayı aşağı itip
// karşılaştırılacak ölçüm bloğunu görünür alanın dışına atardı.
// ---------------------------------------------------------------------------

const _okuma = 'ROOKUMA: bu donemde icine donup bakman istenen bir esik.';

Map<String, dynamic> _icTakvimYuku() => {
      'progressions': {
        'report': _okuma,
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
          'disclosure_texts': <String>[],
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

Map<String, dynamic> _yilHaritasiYuku() => {
      'report': _okuma,
      'solar_return': {
        'return_at_local': '2026-05-12T20:16:00+03:00',
        'next_return_at_local': '2027-05-13T02:04:00+03:00',
        'sr_ascendant': {'sign_local': 'Terazi', 'position': '8.1'},
        'sr_sun_house': 10,
        'sr_moon_local': 'Balık',
        'disclosure_texts': <String>[],
      },
    };

Map<String, dynamic> _dogumKapisiYuku() => {
      'report': _okuma,
      'gate_text': 'KAPIDOKUSU: temeli söküp yeniden döken bir damar.',
      'position': {'gate': 34, 'line': 5, 'longitude': '131.06'},
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

/// ⚠️ `missing_elements`, `notes` ve `shen_sha` BOŞ BIRAKILAMAZ, çünkü
/// sekme onları hoşgörüsüz cast ediyor (`chart['missing_elements'] as List`,
/// `bazi_tab.dart:230`): alan hiç gelmezse `Null is not a List` fırlar ve
/// ekranın TAMAMI çöker. Bu testin konusu bu değil — ama ölçüldü ve
/// kaydedildi: Yıl Haritası ekranı aynı riski bir üretim olayından sonra
/// hoşgörülü ayrıştırmayla kapatmış (`solar_return_screen.dart:69-71`),
/// BaZi kapatmamış.
Map<String, dynamic> _baziYuku() => {
      'report': _okuma,
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
        'notes': <String>[],
        'element_distribution': {'Ahşap': 2.4},
        'missing_elements': <String>[],
        'shen_sha': <Map<String, dynamic>>[],
        'luck_pillars': <Map<String, dynamic>>[],
      },
    };

void main() {
  // -------------------------------------------------------------------------
  group('İç Takvim', () {
    testWidgets('okuma progres Ay panelinin ÜSTÜNDE', (tester) async {
      _uzunYuzey(tester);
      await tester.pumpWidget(_sar(const InnerCalendarScreen(), overrides: [
        raporKapisiProvider.overrideWithValue(PlusHali.abone),
        innerCalendarProvider.overrideWith((ref) async => _icTakvimYuku()),
      ]));
      await _yerles(tester);

      // Ölçüm YERİNDE: progres Ay derecesi ve etkin açı silinmedi.
      expect(find.textContaining('12.4'), findsWidgets,
          reason: 'progres Ay derecesi kalkmış — ölçüm silinemez');
      expect(find.textContaining('Neptün'), findsWidgets);

      final okuma = find.byType(MarginNote);
      expect(okuma, findsOneWidget, reason: 'insan cümlesi ekrandan düşmüş');
      expect(tester.getTopLeft(okuma).dy,
          lessThan(tester.getTopLeft(find.textContaining('12.4').first).dy),
          reason: 'ekran yine bir SAYIYLA açılıyor');
    });

    testWidgets('"Rytho\'ya sor" var ve sohbeti O SORUYLA açıyor',
        (tester) async {
      _uzunYuzey(tester);
      final gozcu = _RotaGozcusu();
      await tester.pumpWidget(_sar(const InnerCalendarScreen(),
          gozcu: gozcu,
          overrides: [
            raporKapisiProvider.overrideWithValue(PlusHali.abone),
            innerCalendarProvider.overrideWith((ref) async => _icTakvimYuku()),
          ]));
      await _yerles(tester);

      final dugme = find.byType(RythoyaSor);
      expect(dugme, findsOneWidget);
      await tester.tap(dugme);
      expect(_tohum(tester, gozcu, find.byType(InnerCalendarScreen)),
          _tr.innerCalendarAskPrefill,
          reason: 'boş sohbet açılırsa kullanıcı neyi soracağını bilemez');
      await tester.pumpWidget(const SizedBox.shrink());
    });
  });

  // -------------------------------------------------------------------------
  group('Yıl Haritası', () {
    testWidgets('okuma dönüş anının ÜSTÜNDE', (tester) async {
      _uzunYuzey(tester);
      await tester.pumpWidget(_sar(const SolarReturnScreen(), overrides: [
        raporKapisiProvider.overrideWithValue(PlusHali.abone),
        solarReturnProvider.overrideWith((ref) async => _yilHaritasiYuku()),
      ]));
      await _yerles(tester);

      // Dakika hassasiyetli dönüş anı YERİNDE — yalnız okumanın arkasında.
      final an = find.textContaining('2026-05-12');
      expect(an, findsWidgets, reason: 'dönüş anı kalkmış — ölçüm silinemez');
      final okuma = find.byType(MarginNote);
      expect(okuma, findsOneWidget);
      expect(tester.getTopLeft(okuma).dy,
          lessThan(tester.getTopLeft(an.first).dy),
          reason: 'ekran yine bir TARİH-SAAT ile açılıyor');
    });

    testWidgets('"Rytho\'ya sor" sohbeti O SORUYLA açıyor', (tester) async {
      _uzunYuzey(tester);
      final gozcu = _RotaGozcusu();
      await tester.pumpWidget(_sar(const SolarReturnScreen(),
          gozcu: gozcu,
          overrides: [
            raporKapisiProvider.overrideWithValue(PlusHali.abone),
            solarReturnProvider.overrideWith((ref) async => _yilHaritasiYuku()),
          ]));
      await _yerles(tester);

      await tester.tap(find.byType(RythoyaSor));
      expect(_tohum(tester, gozcu, find.byType(SolarReturnScreen)),
          _tr.solarReturnAskPrefill);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  });

  // -------------------------------------------------------------------------
  group('Doğum Kapısı', () {
    testWidgets('sıra: glif → okuma → ölçüm (boylam)', (tester) async {
      _uzunYuzey(tester);
      await tester.pumpWidget(_sar(const BirthHexagramScreen(), overrides: [
        raporKapisiProvider.overrideWithValue(PlusHali.abone),
        birthHexagramProvider.overrideWith((ref) async => _dogumKapisiYuku()),
      ]));
      await _yerles(tester);

      final glif = find.text('䷡');
      final okuma = find.byType(MarginNote);
      final boylam = find.textContaining('131.06');
      expect(glif, findsOneWidget, reason: 'kapının yüzü ekrandan düşmüş');
      expect(okuma, findsOneWidget);
      expect(boylam, findsWidgets,
          reason: 'Güneş boylamı kalkmış — ölçüm silinemez');

      final glifY = tester.getTopLeft(glif).dy;
      final okumaY = tester.getTopLeft(okuma).dy;
      final boylamY = tester.getTopLeft(boylam.first).dy;
      // Glif ÖLÇÜM DEĞİL AD: önde kalması istenen hâl.
      expect(glifY, lessThan(okumaY), reason: 'kapının adı aşağı itilmiş');
      // Ölçüm okumanın ALTINDA: "bilginin geldiği yer" yorumdan sonra.
      expect(okumaY, lessThan(boylamY),
          reason: 'mono boylam satırı yine okumanın üstünde');
    });

    testWidgets('"Rytho\'ya sor" sohbeti O SORUYLA açıyor', (tester) async {
      _uzunYuzey(tester);
      final gozcu = _RotaGozcusu();
      await tester.pumpWidget(_sar(const BirthHexagramScreen(),
          gozcu: gozcu,
          overrides: [
            raporKapisiProvider.overrideWithValue(PlusHali.abone),
            birthHexagramProvider
                .overrideWith((ref) async => _dogumKapisiYuku()),
          ]));
      await _yerles(tester);

      await tester.tap(find.byType(RythoyaSor));
      expect(_tohum(tester, gozcu, find.byType(BirthHexagramScreen)),
          _tr.birthHexagramAskPrefill);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  });

  // -------------------------------------------------------------------------
  group('BaZi', () {
    testWidgets('okuma dört sütun tablosunun ÜSTÜNDE', (tester) async {
      _uzunYuzey(tester);
      await tester.pumpWidget(_sar(const BaziTab(), overrides: [
        raporKapisiProvider.overrideWithValue(PlusHali.abone),
        baziReportProvider.overrideWith((ref) async => _baziYuku()),
      ]));
      await _yerles(tester);

      // Dört sütun YERİNDE: gün gövdesi ekranda.
      final gunGovdesi = find.text('戊');
      expect(gunGovdesi, findsWidgets,
          reason: 'dört sütun kalkmış — deterministik hesap silinemez');
      final okuma = find.byType(MarginNote);
      expect(okuma, findsOneWidget);
      expect(tester.getTopLeft(okuma).dy,
          lessThan(tester.getTopLeft(gunGovdesi.first).dy),
          reason: 'ekran yine doğrudan TABLOYLA açılıyor');
    });

    testWidgets('"Rytho\'ya sor" sohbeti O SORUYLA açıyor', (tester) async {
      _uzunYuzey(tester);
      final gozcu = _RotaGozcusu();
      await tester.pumpWidget(_sar(const BaziTab(),
          gozcu: gozcu,
          overrides: [
            raporKapisiProvider.overrideWithValue(PlusHali.abone),
            baziReportProvider.overrideWith((ref) async => _baziYuku()),
          ]));
      await _yerles(tester);

      await tester.tap(find.byType(RythoyaSor));
      expect(_tohum(tester, gozcu, find.byType(BaziTab)), _tr.baziAskPrefill);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  });

  // -------------------------------------------------------------------------
  group('İ Ching (kaynak bekçisi)', () {
    // ⚠️ NEDEN WIDGET TESTİ DEĞİL — ve bu bir sınır beyanı, tembellik değil:
    // okumayı çizen `_HexagramView` ÖZEL bir sınıf ve ona ulaşmanın tek
    // yolu çekimin tamamını koşturmak (soru doğrulaması, cüzdan kapısı,
    // para animasyonu, ağ çağrısı). Diğer dördünde sağlayıcı override'ı
    // yettiği için oralarda gerçek yerleşim ÖLÇÜLÜYOR; burada sıra
    // kaynaktan çivileniyor.
    const yol = 'lib/features/oracle/iching_tab.dart';

    /// Gövde: `_HexagramView`in `build`i — iki SINIF BİLDİRİMİ arası.
    /// Proza değil kod tanımlayıcısına bağlı (emsal: `anlam_once_test`).
    String govde() {
      final k = _yorumsuz(yol);
      final bas = k.indexOf('class _HexagramView');
      final son = k.indexOf('class _LiuYaoTable');
      expect(bas, greaterThanOrEqualTo(0));
      expect(son, greaterThan(bas));
      return k.substring(bas, son);
    }

    // Okumanın işareti `OkumaKabi(` (D6): `MarginNote` artık kabın içinde
    // kuruluyor, kaynakta görünmüyor. Kap `fallback` bayrağını tek
    // noktadan okur; bu dosyanın sıra iddiası kabın konumuna bağlı.
    test('okuma klasik metinlerin ve Liu Yao tablosunun ÜSTÜNDE', () {
      final g = govde();
      final okuma = g.indexOf('OkumaKabi(');
      expect(okuma, greaterThanOrEqualTo(0), reason: 'okuma ekrandan düşmüş');
      // Üç bağımsız işaret: biri yer değiştirse diğerleri yine yakalar.
      for (final sonra in const [
        'iChingJudgmentTitle',
        'iChingImageTitle',
        'iChingLiuYaoTitle',
      ]) {
        final i = g.indexOf(sonra);
        expect(i, greaterThanOrEqualTo(0), reason: '$sonra kayboldu');
        expect(okuma, lessThan(i), reason: '$sonra okumadan önce geliyor');
      }
    });

    test('glif okumanın ÜSTÜNDE — kullanıcının kendi ürettiği şey', () {
      final g = govde();
      final glif = g.indexOf('_HexagramGlyph(');
      expect(glif, greaterThanOrEqualTo(0));
      expect(glif, lessThan(g.indexOf('OkumaKabi(')),
          reason: 'çekimin cevabı sayfadan aşağı itilmiş');
    });

    test('trigram ve nükleer ÖLÇÜMÜ okumanın ALTINDA', () {
      // Bu iki satır glif panelinin İÇİNDEYDİ, yani okumadan önce
      // geliyordu. Taşınmaları bu turun asıl işi; geri dönerlerse
      // ekran yine ölçümle açılır.
      final g = govde();
      final okuma = g.indexOf('OkumaKabi(');
      for (final olcum in const [
        'iChingTrigramsLabel',
        'iChingNuclearLabel',
        'iChingDayLabel',
      ]) {
        final i = g.indexOf(olcum);
        expect(i, greaterThanOrEqualTo(0), reason: '$olcum kayboldu');
        expect(okuma, lessThan(i), reason: '$olcum yine okumanın üstünde');
      }
    });

    test('"Rytho\'ya sor" var ve tohum KULLANICININ SORUSUNU taşıyor', () {
      final g = govde();
      // Kapı kabın `onSor` yuvasından geçiyor (`OkumaKabi` onu `RythoyaSor`
      // olarak çizer); ekran kendi `RythoyaSor(` çağrısını yazmaz.
      expect(g, contains('onSor:'));
      expect(g, contains('iChingAskPrefill('),
          reason: 'boş sohbet açılırsa kehanetin bağlamı kaybolur');
      // Tohumun içine giren şey çekimin kendi `question` alanı olmalı —
      // uydurulmuş bir soru değil (`iching_service.py` onu geri döndürüyor).
      expect(g, contains("cast['question']"),
          reason: 'tohum kullanıcının sorusundan KOPMUŞ');
    });
  });

  // -------------------------------------------------------------------------
  group('okuma GÖVDE LİSTESİNİN ilk kalemi — üstüne blok girmez', () {
    // ⚠️ BU GRUP NEDEN VAR, ölçülmüş bir boşluktan: yukarıdaki dy
    // bekçileri yalnız "okuma ŞU ÖLÇÜMÜN üstünde" diyor. Anlamın ÜSTÜNE
    // adı bilinmeyen YENİ bir teknik blok eklemek takımın tamamını YEŞİL
    // bırakırdı — ekran yine bir sayıyla açılır, o ölçüm ise hâlâ
    // okumadan sonra. Aynı boşluk `anlam_once_test`te Harita İnceleme
    // için ikinci doğrulama turunda yakalanmıştı; ders taşındı.
    //
    // Çapa adlara değil YAPIYA bağlı: yorumlar atıldıktan sonra
    // `children: [` ile okumanın işareti arasında, o ekran için İZİN
    // VERİLEN kalemlerden başka bir şey kalmamalı.
    void ilkKalem(String yol, String isaret,
        {List<String> izinli = const []}) {
      final k = _yorumsuz(yol);
      final cocuklar = k.indexOf('children: [');
      expect(cocuklar, greaterThanOrEqualTo(0), reason: '$yol: gövde listesi yok');
      final okuma = k.indexOf(isaret, cocuklar);
      expect(okuma, greaterThan(cocuklar), reason: '$yol: $isaret listede yok');
      var arasi = k.substring(cocuklar + 'children: ['.length, okuma);
      for (final i in izinli) {
        expect(arasi, contains(i), reason: '$yol: izinli kalem $i kaybolmuş');
        arasi = arasi.replaceFirst(i, '');
      }
      // İzinliler çıkarıldıktan sonra yalnız noktalama/boşluk kalmalı.
      expect(arasi.replaceAll(RegExp(r'[\s(),\[\]]'), ''), isEmpty,
          reason: '$yol: okumanın ÜSTÜNE başka bir blok girmiş');
    }

    // İzinli kalemler D6'dan sonra: kademeli giriş `RythoReveal(index: 0,`
    // (eski `blok(Padding(` kopyası silindi) ve kap `OkumaKabi(`. Boş
    // okuma koşulu (`if (okuma.isNotEmpty)`) da gitti — kap boş metni
    // kendi "üretilemedi" dalında karşılıyor, ekranın koşulu kalmadı.
    test('İç Takvim: okuma listenin ilk kalemi', () {
      ilkKalem('lib/features/atlas/inner_calendar_screen.dart',
          'OkumaKabi(',
          izinli: const [
            'RythoReveal(',
            'index: 0,',
            'child: Padding(',
            'padding:',
            'const EdgeInsets.symmetric(horizontal: RythoSpace.lg),',
            'child:',
          ]);
    });

    test('Yıl Haritası: okuma listenin ilk kalemi', () {
      ilkKalem('lib/features/atlas/solar_return_screen.dart', 'OkumaKabi(',
          izinli: const [
            'RythoReveal(',
            'index: 0,',
            'child: Padding(',
            'padding:',
            'const EdgeInsets.symmetric(horizontal: RythoSpace.lg),',
            'child:',
          ]);
    });

    test('BaZi: okumadan önce YALNIZ iki ad satırı var', () {
      // İzinliler ÖLÇÜM DEĞİL AD: ekran başlığı ve "Çin burcun" satırı.
      // Üçüncü bir kalem girerse — tablo, rozet, hüküm — bu test düşer.
      final k = _yorumsuz('lib/features/oracle/bazi_tab.dart');
      final cocuklar = k.indexOf('children: [');
      final okuma = k.indexOf('OkumaKabi(', cocuklar);
      expect(okuma, greaterThan(cocuklar));
      final arasi = k.substring(cocuklar, okuma);
      expect(arasi, contains('l10n.baziHeadline'));
      expect(arasi, contains('l10n.baziChineseSign'));
      // Hiçbir ÖLÇÜM bloğu okumadan önce kurulmuyor.
      for (final olcum in const [
        'l10n.baziFourPillars',
        '_StrengthPlaque(',
        'l10n.baziElements',
        'l10n.baziLuckTitle',
      ]) {
        expect(arasi, isNot(contains(olcum)),
            reason: '$olcum okumadan önce geliyor');
      }
    });
  });

  // -------------------------------------------------------------------------
  group('sohbet kapısı mekanizması', () {
    test('etiket TEK yerden okunuyor — beş kopya ayrışır', () {
      // Bu depoda ölçülmüş ders: bir metnin beş kopyası varsa dördü
      // ayrışır. Etiket `RythoyaSor` içinde `l10n.signalAsk`ten gelir;
      // ekranların hiçbiri kendi dizesini yazmaz.
      final w = _yorumsuz('lib/widgets/atlas_widgets.dart');
      final bas = w.indexOf('class RythoyaSor');
      expect(bas, greaterThanOrEqualTo(0), reason: 'paylaşılan kapı silinmiş');
      expect(w.substring(bas), contains('l10n.signalAsk'));

      // D6: beş ekran kapıyı `OkumaKabi(onSor:)` üzerinden kuruyor; kap
      // onu `RythoyaSor` olarak çizer (okuma_kabi.dart). Ekranda çıplak
      // `RythoyaSor(` YOK — ikinci bir kapı biçimi doğmasın.
      final kap = _yorumsuz('lib/widgets/okuma_kabi.dart');
      expect(kap, contains('RythoyaSor(onTap: sor)'),
          reason: 'kap sohbet kapısını paylaşılan bileşenle çizmiyor');
      for (final yol in const [
        'lib/features/atlas/inner_calendar_screen.dart',
        'lib/features/atlas/solar_return_screen.dart',
        'lib/features/atlas/birth_hexagram_screen.dart',
        'lib/features/oracle/bazi_tab.dart',
        'lib/features/oracle/iching_tab.dart',
      ]) {
        final k = _yorumsuz(yol);
        expect(k, contains('onSor:'), reason: '$yol: kapı yok');
        expect(k, isNot(contains('RythoyaSor(')),
            reason: '$yol: kabın dışında ikinci bir sohbet kapısı');
        expect(k, isNot(contains("'✦ ")),
            reason: '$yol: etiketin kendi kopyası doğmuş');
      }
      // Kap kullanmayan iki yüzey kapıyı DOĞRUDAN paylaşılan bileşenle
      // çizer (D6 dikişi: Harita İnceleme ve dayanak alt sayfası); satır içi
      // '✦ … →' kopyası burada da doğmaz — beş kopyanın dördü böyle ayrışmıştı.
      for (final yol in const [
        'lib/features/atlas/chart_inspector_screen.dart',
        'lib/widgets/basis_sheet.dart',
      ]) {
        final k = _yorumsuz(yol);
        expect(k, contains('RythoyaSor('), reason: '$yol: paylaşılan kapı yok');
        expect(k, isNot(contains("'✦ ")),
            reason: '$yol: etiketin kendi kopyası doğmuş');
      }
    });

    test('Kişi detayı: anlam cümlesi harita bölümünün ilk kalemi', () {
      // Altıncı ekran (D6, ajan C): dy ölçümü kisi_detay_test'te; burası ikinci
      // bağımsız işaret — `_HaritaBolumu` listesinde anlamın ÜSTÜNE adsız bir
      // blok eklenemez. Dosyanın ilk `children: [`'ı başka bir widget'a ait
      // olduğu için `ilkKalem` yerine sınıf gövdesine daraltılmış arama.
      final k = _yorumsuz('lib/features/people/person_detail_screen.dart');
      final bas = k.indexOf('class _HaritaBolumu');
      final son = k.indexOf('class _AnlamKarti');
      expect(bas, greaterThanOrEqualTo(0));
      expect(son, greaterThan(bas));
      final govde = k.substring(bas, son);
      final cocuklar = govde.indexOf('children: [');
      final anlam = govde.indexOf('_AnlamKarti(', cocuklar);
      expect(cocuklar, greaterThanOrEqualTo(0));
      expect(anlam, greaterThan(cocuklar), reason: 'anlam kartı listede yok');
      var arasi = govde.substring(cocuklar + 'children: ['.length, anlam);
      expect(arasi, contains('if (anlam != null)'),
          reason: 'anlam koşulu kaybolmuş');
      arasi = arasi.replaceFirst('if (anlam != null)', '');
      expect(arasi.replaceAll(RegExp(r'[\s(),\[\]]'), ''), isEmpty,
          reason: 'anlamın ÜSTÜNE başka bir blok girmiş');
    });

    test('tohum ÖN-DOLDURUR, GÖNDERMEZ', () {
      // `chat_screen.dart:33-34` doktrini: "giriş alanını ÖN-DOLDURUR,
      // göndermez — son söz kullanıcının." Tohum otomatik gönderilirse
      // kullanıcının ağzına soru konur VE her dokunuş jeton harcar.
      final k = _yorumsuz('lib/features/chat/chat_screen.dart');
      final bas = k.indexOf('void initState()');
      expect(bas, greaterThanOrEqualTo(0));
      final govde = k.substring(bas, k.indexOf('void _onTextChanged()'));
      expect(govde, contains('_controller.text = tohum'));
      expect(govde, isNot(contains('_send(')),
          reason: 'tohum otomatik gönderiliyor — jeton musluğu');
    });
  });
}
