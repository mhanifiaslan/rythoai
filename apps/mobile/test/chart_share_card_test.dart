// ChartShareCard ve share_card.dart kaynak bekçileri.
//
// Harita İnceleme 700×740'lık özel bir kare paylaşıyordu — öteki iki kartla
// ne oranı ne marka satırını paylaşıyordu. Üç kart artık aynı 9:16 tuvalde.
// Marka yazısı `kMarkaYazi`dan gelir: `'RYTHO'` literali altı dosyada
// dolaşıyordu, bu dosyada sıfır. Kullanıcı metni `trBuyuk` ile büyütülür —
// kartta "İKIZLER" ve "YIL HARITASI" bir kez ekrana çıktı.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:rytho/features/share/share_card.dart';
import 'package:rytho/l10n/app_localizations.dart';
import 'package:rytho/l10n/app_localizations_tr.dart';
import 'package:rytho/theme/rytho_tokens.dart';
import 'package:rytho/widgets/chart/chart_data.dart';
import 'package:rytho/widgets/chart/chart_wheel.dart';

final _tr = AppLocalizationsTr();

/// Kaynak bekçisi bir şeyin YOKLUĞUNU ararken kendi açıklama yorumuna
/// takılmasın (emsal: anlam_once_bes_ekran_test).
String _yorumsuz(String yol) => File(yol)
    .readAsStringSync()
    .replaceAll('\r\n', '\n')
    .split('\n')
    .where((s) => !s.trimLeft().startsWith('//'))
    .join('\n');

ChartPoint _p(String name, double lon) => ChartPoint(
      name: name,
      localName: name,
      absPosition: lon,
      signIndex: signIndexFromAny(null, lon),
      degreeInSign: lon % 30,
    );

ChartData _natal() => ChartData(
      rings: [
        ChartRing(kind: ChartRingKind.natal, points: [
          _p('Sun', 10),
          _p('Moon', 95),
          _p('Saturn', 190),
        ]),
      ],
      houses: [
        for (var i = 0; i < 12; i++)
          ChartHouse(house: i + 1, absPosition: (i * 30) % 360.0),
      ],
      aspects: const [
        ChartAspect(p1: 'Sun', p2: 'Saturn', kind: 'opposition', orb: 0.5),
      ],
    );

void main() {
  // Ressam RythoText (GoogleFonts) kullanır; testte ağdan font çekme
  // denemesi arka planda fırlatıp izleyen teste sızıyordu (chart_wheel_test).
  GoogleFonts.config.allowRuntimeFetching = false;

  test("share_card.dart: 'RYTHO' literali YOK, çıplak büyütme YOK", () {
    final k = _yorumsuz('lib/features/share/share_card.dart');
    expect(k.contains("'RYTHO'"), isFalse,
        reason: 'marka yazısı kMarkaYazi (rytho_tokens) — literal değil');
    expect(RegExp(r'\.to(Upper|Lower)Case\(\)').hasMatch(k), isFalse,
        reason: 'kullanıcı metni trBuyuk ile büyür (İKIZLER kusuru)');
  });

  test('paylaşım metni kullanıcının dilinde (shareText), logo yazısı değil',
      () {
    // Görselin yanındaki metin "RYTHO" idi — paylaşım sayfasında bağlamsız
    // bir sözcük. Tanıtım cümlesi ARB'den, iki dilde.
    final k = _yorumsuz('lib/features/share/share_card.dart');
    expect(k, contains('text: l10n.shareText'));
    expect(k, isNot(contains('text: kMarkaYazi')));
    expect(_tr.shareText, contains(kMarka));
  });

  test('kart glifleri glif fontundan — ailesiz TextStyle yok', () {
    // ♈–♓ Emoji_Presentation=Yes: ailesiz stil kartta renkli emoji
    // basıyordu (rytho_glyphs.dart). Üç kartın glifi RythoText.glyph.
    final k = _yorumsuz('lib/features/share/share_card.dart');
    expect(k, isNot(contains('TextStyle(\n                        fontSize')));
    expect(RegExp(r'const TextStyle\(').hasMatch(k), isFalse,
        reason: 'ailesiz glif stili geri gelmiş');
    expect('RythoText.glyph('.allMatches(k).length, greaterThanOrEqualTo(2));
  });

  test('1080-px tuval dolguları adlı — üç kart aynı üst/alt payı kullanır',
      () {
    final k = _yorumsuz('lib/features/share/share_card.dart');
    expect(k, contains('_kTuvalDolgu'));
    expect(k, isNot(contains('fromLTRB(96, 150, 96, 110)')),
        reason: 'çıplak tuval dolgusu geri gelmiş');
  });

  test('halka lejantı çarkla aynı kuraldan (ringGlyphColor)', () {
    final k = _yorumsuz('lib/features/share/share_card.dart');
    expect(k, contains('ringGlyphColor(data, 1)'));
    expect(k, isNot(contains('kOuterPartnerColor')));
  });

  test('çark kartının tek tüketicisi: chart_inspector shareChartCard çağırır',
      () {
    final k = _yorumsuz('lib/features/atlas/chart_inspector_screen.dart');
    expect(k, contains('shareChartCard('));
    expect(k, isNot(contains("'RYTHO'")),
        reason: 'bu bekçi yalnız share_card.dart\'ı tarıyordu; literal '
            'chart_inspector\'da yaşıyordu (ölçüldü)');
  });

  testWidgets('ChartShareCard 1080×1920 tuval; çark, lejant ve marka satırı',
      (tester) async {
    tester.view.physicalSize = const Size(1080, 1920);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final veri = _natal();
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('tr'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: true),
        child: child!,
      ),
      home: ChartShareCard(data: veri, title: 'Harita İnceleme'),
    ));
    await tester.pump();

    expect(tester.getSize(find.byType(ChartShareCard)),
        const Size(1080, 1920));
    expect(tester.takeException(), isNull, reason: 'kart taşmamalı');
    expect(find.byType(ChartWheel), findsOneWidget);
    expect(tester.getSize(find.byType(ChartWheel)),
        const Size(ChartShareCard.wheelSize, ChartShareCard.wheelSize));
    expect(find.text(kMarkaYazi), findsOneWidget);
    expect(find.text(_tr.chartLegendInner(veri.rings.first.label)),
        findsOneWidget);
    expect(find.text('HARİTA İNCELEME'), findsOneWidget,
        reason: 'başlık Türkçe büyütülür (İ korunur)');
    // Konum tablosu kartta (sahip, 2026-10-16: "paylaşınca verilerin çoğu
    // siliniyor"): her gezegen adı ve ölçümü — burç, derece — kartta.
    for (final ad in ['Sun', 'Moon', 'Saturn']) {
      expect(find.text(ad), findsOneWidget, reason: '$ad satırı kartta yok');
    }
    expect(find.textContaining("10°00'"), findsWidgets,
        reason: 'derece ölçümü kartta yok');
  });

  group('rapor kartı: metin KESİLMEZ, sayfalanır', () {
    // Eski kural "kırpma KURAL — kart raporun yerine geçmez" idi; uzun natal
    // raporun yalnız ilk paragrafları karta giriyordu. Şimdi sayfa sayfa.
    String uzun(int n) => List.filled(
        n,
        'Güneş Yengeç burcunda ve dokuzuncu evde; bu yerleşim duygusal '
        'derinliği uzak ufuklara taşır. ').join();
    String kelimeler(String s) => s.split(RegExp(r'\s+')).join(' ').trim();

    testWidgets('uzun rapor birden çok sayfa; birleşince metin AYNEN geri',
        (tester) async {
      final govde = uzun(60);
      final sayfalar = ReportShareCard.sayfalar(govde, rozetli: true);
      expect(sayfalar.length, greaterThan(1));
      expect(sayfalar.length, lessThanOrEqualTo(ReportShareCard.azamiSayfa));
      expect(kelimeler(sayfalar.join(' ')), kelimeler(govde),
          reason: 'sayfa bölmede metin kayboldu ya da değişti');
      expect(sayfalar.any((s) => s.endsWith('…')), isFalse,
          reason: 'tavan aşılmadıkça "…" yok');
    });

    testWidgets('kısa rapor tek sayfa', (tester) async {
      final govde = uzun(2);
      expect(ReportShareCard.sayfalar(govde, rozetli: false),
          [govde.trim()]);
    });

    testWidgets('tavan aşılırsa son sayfa "…" ile biter, sayfa sayısı tavan',
        (tester) async {
      final sayfalar =
          ReportShareCard.sayfalar(uzun(400), rozetli: false);
      expect(sayfalar.length, ReportShareCard.azamiSayfa);
      expect(sayfalar.last.endsWith('…'), isTrue);
    });

    test('kaynak: paylaşım tüm sayfaları tek seferde gönderir', () {
      final k = _yorumsuz('lib/features/share/share_card.dart');
      expect(k, contains('ReportShareCard.sayfalar('));
      expect(k, contains('shareRenderedCards('));
      expect(k, isNot(contains('_sigdir(')),
          reason: 'eski kırpıcı geri geldi');
    });
  });
}
