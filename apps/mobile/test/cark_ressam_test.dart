// Çark ressamı D6 bekçileri: derece etiketi gizleme, seçili halka, halka
// rengi tek kuralı, önbellek anahtarı.
//
// Çizilen şey ölçülür: ressam `implements Canvas` bir kaydediciye boyar ve
// paragraf/daire çağrıları sayılır — kaynak dizgisi değil, davranış.
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:rytho/widgets/chart/chart_data.dart';
import 'package:rytho/widgets/chart/chart_palette.dart';
import 'package:rytho/widgets/chart/wheel_layout.dart';
import 'package:rytho/widgets/chart/wheel_painter.dart';

String _yorumsuz(String yol) => File(yol)
    .readAsStringSync()
    .replaceAll('\r\n', '\n')
    .split('\n')
    .where((s) => !s.trimLeft().startsWith('//'))
    .join('\n');

ChartPoint _p(String name, double lon, {bool retro = false}) => ChartPoint(
      name: name,
      localName: name,
      absPosition: lon,
      signIndex: signIndexFromAny(null, lon),
      degreeInSign: lon % 30,
      retrograde: retro,
    );

List<ChartHouse> _evler() => [
      for (var i = 0; i < 12; i++)
        ChartHouse(house: i + 1, absPosition: (i * 30) % 360.0),
    ];

/// Dört nokta: üçü metin glifi, biri (Kiron) vektör. Retro yok — paragraf
/// sayımı yalnız glif + derece etiketinden oluşsun.
ChartData _natal() => ChartData(
      rings: [
        ChartRing(kind: ChartRingKind.natal, points: [
          _p('Sun', 10), _p('Moon', 95), _p('Saturn', 190), _p('Chiron', 250),
        ]),
      ],
      houses: _evler(),
      aspects: const [
        ChartAspect(p1: 'Sun', p2: 'Saturn', kind: 'opposition', orb: 0.5),
      ],
    );

/// Çağrıları sayan kanvas: paragraf (metin), daire, çizgi.
class _SayanKanvas implements Canvas {
  int paragraf = 0;
  final daireler = <(Offset, double, Paint)>[];

  @override
  void drawParagraph(ui.Paragraph paragraph, Offset offset) => paragraf++;

  @override
  void drawCircle(Offset c, double radius, Paint paint) =>
      daireler.add((c, radius, paint));

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

/// Ham boyutta (zoom 1) dinamik katmanı sayan kanvasa boyar.
Future<_SayanKanvas> _boya(ChartData data, double hamBoyut,
    {WheelSelection secim = WheelSelection.none, double zoom = 1.0}) async {
  final k = _SayanKanvas();
  Object? hata;
  // GoogleFonts font sızıntısı (chart_wheel_test emsali): guarded bölge
  // yalnız asenkron font hatasını yutar, paint() istisnası senkron
  // yakalanıp aşağıda raporlanır.
  await runZonedGuarded(() async {
    try {
      final layout = WheelLayout.compute(
          Size.square(hamBoyut * zoom), data, zoom: zoom);
      final cache = GlyphTextCache();
      final statik = recordStaticLayer(layout, cache);
      RythoWheelPainter(
        layout: layout,
        staticLayer: statik,
        textCache: cache,
        progress: 1.0,
        selection: secim,
      ).paint(k, Size.square(hamBoyut * zoom));
    } catch (e) {
      hata = e;
    }
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }, (e, s) {});
  expect(hata, isNull);
  return k;
}

void main() {
  GoogleFonts.config.allowRuntimeFetching = false;

  group('derece etiketleri — küçük çark ve zoomsuz GİZLİ', () {
    test('kural: ham boyut < 320 VE zoom < 1,5 → gizli', () {
      expect(dereceEtiketleriGorunur(rawSize: 300, zoom: 1.0), isFalse);
      expect(dereceEtiketleriGorunur(rawSize: 248, zoom: 1.4), isFalse);
      // Yakınlaştırma etiketi geri getirir.
      expect(dereceEtiketleriGorunur(rawSize: 300, zoom: 1.5), isTrue);
      expect(dereceEtiketleriGorunur(rawSize: 250, zoom: 2.0), isTrue);
      // Yeterince büyük çark her zoomda gösterir.
      expect(dereceEtiketleriGorunur(rawSize: 320, zoom: 1.0), isTrue);
      expect(dereceEtiketleriGorunur(rawSize: 460, zoom: 1.0), isTrue);
    });

    test('ressam kuralı GERÇEKTEN uyguluyor: küçük çarkta nokta başına bir '
        'paragraf eksik', () async {
      final data = _natal();
      final buyuk = await _boya(data, 360);
      final kucuk = await _boya(data, 300);
      final noktaSayisi = data.rings.first.points.length;
      // 360: 3 metin glifi + 4 derece etiketi; 300: yalnız 3 glif.
      expect(buyuk.paragraf, greaterThan(noktaSayisi));
      expect(kucuk.paragraf, buyuk.paragraf - noktaSayisi,
          reason: 'küçük çarkta derece etiketleri hâlâ çiziliyor');
    });

    test('küçük çark yakınlaştırılınca etiketler geri gelir', () async {
      final data = _natal();
      final zoomlu = await _boya(data, 300, zoom: 2.0);
      final duz = await _boya(data, 300);
      expect(zoomlu.paragraf, duz.paragraf + data.rings.first.points.length);
    });
  });

  group('seçili gezegene lila halka', () {
    bool lilaHalka(_SayanKanvas k) => k.daireler.any((d) =>
        d.$3.style == PaintingStyle.stroke &&
        d.$3.color.toARGB32() == kSelectedGlyphRing.toARGB32());

    test('seçimsizde halka YOK', () async {
      expect(lilaHalka(await _boya(_natal(), 360)), isFalse);
    });

    test('seçimde TEK halka, seçili glifin merkezinde', () async {
      final data = _natal();
      final k = await _boya(data, 360,
          secim: const WheelSelection(pointName: 'Sun', pointRing: 0));
      final halkalar = k.daireler
          .where((d) =>
              d.$3.style == PaintingStyle.stroke &&
              d.$3.color.toARGB32() == kSelectedGlyphRing.toARGB32())
          .toList();
      expect(halkalar, hasLength(1),
          reason: 'tek gezegenli çarkta seçim GÖRÜNMELİ (solacak kimse yok)');
      final layout = WheelLayout.compute(const Size(360, 360), data);
      final gunes =
          layout.placements.first.firstWhere((g) => g.point.name == 'Sun');
      expect(halkalar.single.$1, gunes.center);
      // Halka mürekkep diskinden (10,5) dışarıda — glifi örtmez.
      expect(halkalar.single.$2, greaterThan(10.5));
    });
  });

  group('ringGlyphColor — altı kopyanın tek kuralı', () {
    test('iç parşömen, transit lila, partner altın', () {
      final transit = ChartData(
        rings: [
          ChartRing(kind: ChartRingKind.natal, points: [_p('Sun', 10)]),
          ChartRing(kind: ChartRingKind.transit, points: [_p('Mars', 50)]),
        ],
        houses: const [],
        aspects: const [],
      );
      final partner = ChartData(
        rings: [
          ChartRing(kind: ChartRingKind.natal, points: [_p('Sun', 10)]),
          ChartRing(kind: ChartRingKind.partner, points: [_p('Mars', 50)]),
        ],
        houses: const [],
        aspects: const [],
      );
      expect(ringGlyphColor(transit, 0), kInnerGlyphColor);
      expect(ringGlyphColor(transit, 1), kOuterTransitColor);
      expect(ringGlyphColor(partner, 1), kOuterPartnerColor);
      // Olmayan halka iç renge düşer — fırlatmaz.
      expect(ringGlyphColor(_natal(), 1), kInnerGlyphColor);
    });

    test('kaynak: partner/transit üçlüsü yalnız paletin içinde', () {
      // Ölçülmüş kusur: konum tablosu partneri lila, çark altın çiziyordu.
      // Üçlü `kind == partner ? partner : transit` tek dosyada kalır.
      final ihlal = <String>[];
      for (final f in Directory('lib').listSync(recursive: true).whereType<File>()) {
        final yol = f.path.replaceAll('\\', '/');
        if (!yol.endsWith('.dart') ||
            yol.endsWith('widgets/chart/chart_palette.dart')) {
          continue;
        }
        if (_yorumsuz(yol).contains('kOuterPartnerColor')) ihlal.add(yol);
      }
      expect(ihlal, isEmpty,
          reason: 'halka rengi kuralı kopyalanmış — ringGlyphColor kullan');
    });
  });

  group('GlyphTextCache anahtarı', () {
    test('aynı aile, farklı yedek zinciri → ayrı ölçü', () {
      final c = GlyphTextCache();
      const a = TextStyle(fontSize: 10, fontFamily: 'X', fontFamilyFallback: ['A']);
      const b = TextStyle(fontSize: 10, fontFamily: 'X', fontFamilyFallback: ['B']);
      expect(identical(c.get('☿', a), c.get('☿', b)), isFalse,
          reason: 'yedek zinciri anahtarda değil — bayat ölçü döner');
      expect(identical(c.get('☿', a), c.get('☿', a)), isTrue);
    });

    test('aynı metin, farklı ağırlık → ayrı ölçü', () {
      final c = GlyphTextCache();
      const a = TextStyle(fontSize: 10, fontWeight: FontWeight.w400);
      const b = TextStyle(fontSize: 10, fontWeight: FontWeight.w700);
      expect(identical(c.get('R', a), c.get('R', b)), isFalse);
    });
  });

  group('kaynak: yazı tabanı tokenden', () {
    test('ressamda çıplak mono boyutu yok; gezegen glifi glif fontundan', () {
      final k = _yorumsuz('lib/widgets/chart/wheel_painter.dart');
      expect(RegExp(r'RythoText\.mono\(\s*[\d.]+').hasMatch(k), isFalse,
          reason: 'ressam çıplak yazı boyutu kullanıyor — chartLabel/chartMicro');
      expect(k, contains('RythoType.chartLabel'));
      expect(k, contains('RythoType.chartMicro'));
      expect(k, contains('RythoText.glyph('));
      expect(k, isNot(contains('RythoText.body(')),
          reason: 'gezegen glifi gövde fontuyla basılıyor (♀♂ emoji kökü)');
    });

    test('açı tablosu hücresi: glif fontu, mikro taban, tema rengi', () {
      final k = _yorumsuz('lib/features/atlas/chart_inspector_screen.dart');
      final hucre = k.substring(k.indexOf('class _AspectCell'));
      expect(hucre, contains('RythoText.glyph('));
      expect(hucre, contains('RythoType.chartMicro'));
      expect(hucre, isNot(contains('TextStyle(fontSize')),
          reason: 'ailesiz TextStyle geri gelmiş (☌☍△□ emoji riski)');
      expect(k, isNot(contains('Color(0x')),
          reason: 'tema dışı renk literali — kAspectGridLine');
      // ⚹ tablodan: özel vektör dalı silindi (rytho_glyphs.dart kararı).
      expect(hucre, isNot(contains("'sextile'")));
    });
  });
}
