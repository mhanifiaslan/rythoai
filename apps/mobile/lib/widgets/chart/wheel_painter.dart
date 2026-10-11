/// Çark ressamı v2 (HI-turu HA5) — iki katman, tek geometri kaynağı.
///
/// STATİK katman (halkalar, derece cetveli, element tonlu burç bandı,
/// ev çizgileri, AC/MC eksenleri) [recordStaticLayer] ile `ui.Picture`a
/// bir kez kaydedilir — 360 cetvel çizgisini her dokunuşta yeniden
/// yayınlamamak için. DİNAMİK katman (açı ağı, seçim/izole modu, glif
/// ve işaretçiler) [RythoWheelPainter] her karede çizer.
///
/// Eski çarkın onarılan kusurları: shouldRepaint aspects/houses'ı
/// atlıyordu; TextPainter her karede yeniden kuruluyordu (~2400
/// layout/sn); burç bandının süpürme fazı diğer katmanlardan farklıydı;
/// kavuşum kiriş olarak çiziliyordu; açı çizgisi orb'dan bağımsız tek
/// kalınlıktı; magenta üç anlam taşıyordu.
///
/// Yazı boyutları `RythoType.chartLabel` (9) ve `chartMicro` (8) tabanından
/// `z` ile çarpılır — ressam 6,5–8,5 arası beş çıplak boyut kullanıyordu ve
/// mikro bile 8'in altına inmez (ölçüldü: 248 px çarkta 6,8 px okunmuyordu).
library;

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../theme/rytho_theme.dart';
import '../../theme/rytho_tokens.dart';
import 'chart_data.dart';
import 'chart_palette.dart';
import 'wheel_glyphs.dart';
import 'wheel_layout.dart';

/// Açı filtre kipleri (inspector çipleri).
enum WheelAspectFilter { all, major, applying, hard, soft }

/// Seçim durumu: gezegen (izole modu) YA DA tek açı.
class WheelSelection {
  const WheelSelection({this.pointName, this.pointRing, this.aspect});

  final String? pointName;
  final int? pointRing;
  final ChartAspect? aspect;

  bool get isEmpty => pointName == null && aspect == null;

  static const none = WheelSelection();

  bool involvesPoint(ChartAspect a) =>
      pointName != null &&
      ((a.p1 == pointName && a.p1Ring == pointRing) ||
          (a.p2 == pointName && a.p2Ring == pointRing));

  /// Bu yerleşim seçili gezegenin kendisi mi (lila halka onun etrafına).
  bool isPoint(GlyphPlacement g) =>
      pointName != null &&
      g.point.name == pointName &&
      g.ring == pointRing;
}

/// Açı görünür mü? Ressam, aspectarian ve testler AYNI kuralı kullanır.
bool aspectVisible(ChartAspect a, WheelAspectFilter filter, double maxOrb,
    {bool showMinors = false}) {
  if (a.orb > maxOrb) return false;
  if (!a.isMajor && !showMinors) return false;
  return switch (filter) {
    WheelAspectFilter.all => true,
    WheelAspectFilter.major => a.isMajor,
    WheelAspectFilter.applying => a.applying == true,
    WheelAspectFilter.hard => a.isHard,
    WheelAspectFilter.soft => a.isSoft,
  };
}

/// Derece etiketlerinin gizlendiği ham çark boyutu (zoom'suz, mantıksal px)
/// ve etiketleri geri getiren zoom eşiği.
const double kDereceEtiketiBoyutEsigi = 320.0;
const double kDereceEtiketiZoomEsigi = 1.5;

/// Derece etiketleri küçük çarkta ve yakınlaştırma yokken GİZLİ.
///
/// NEDEN: 248 px'lik gömülü çarkta 6,8 px etiket okunmuyordu ve 8 px
/// tabana çıkarmak glif diskleriyle çakışmayı artırırdı. Ham çark
/// ([rawSize] = `layout.size / zoom`) eşiğin altındaysa VE kullanıcı
/// yakınlaştırmadıysa etiket çizilmez; pinch ile 1,5× üstünde geri gelir.
/// Konum tablosu her boyutta tam dereceyi zaten yazıyor — bilgi kaybolmaz.
bool dereceEtiketleriGorunur({required double rawSize, required double zoom}) =>
    !(rawSize < kDereceEtiketiBoyutEsigi && zoom < kDereceEtiketiZoomEsigi);

/// Çark yazı rolleri — tokenden okunur, `z` ile büyür. `fontSize` tokende
/// her zaman dolu (RythoText.mono boyut ister); `!` o sözleşmeye yaslanır.
TextStyle _carkEtiketi(double z, {required Color color}) =>
    RythoType.chartLabel.copyWith(
        fontSize: RythoType.chartLabel.fontSize! * z, color: color);

TextStyle _carkMikro(double z, {required Color color, FontWeight? w}) =>
    RythoType.chartMicro.copyWith(
        fontSize: RythoType.chartMicro.fontSize! * z,
        color: color,
        fontWeight: w);

/// TextPainter önbelleği — anahtar metin + stilin ölçüme giren alanları.
///
/// Anahtar `fontFamilyFallback` ve `fontWeight`'i de taşır: aynı aile
/// farklı yedek zinciriyle (ya da aynı metin farklı ağırlıkla) istenirse
/// önbellek bayat ölçü döndürürdü. Bugün tek yedek var; yarın ikinci bir
/// glif fontu eklendiğinde bu satır sessiz bir kusuru önler.
class GlyphTextCache {
  final _cache = <String, TextPainter>{};

  TextPainter get(String text, TextStyle style) {
    final key = '$text|${style.fontSize}|${style.color?.toARGB32()}'
        '|${style.fontFamily}|${style.fontFamilyFallback?.join(',')}'
        '|${style.fontWeight?.value}';
    return _cache.putIfAbsent(key, () {
      final tp = TextPainter(
        text: TextSpan(text: text, style: style),
        textDirection: TextDirection.ltr,
      )..layout();
      return tp;
    });
  }

  void paintCentered(Canvas canvas, String text, TextStyle style,
      Offset center) {
    final tp = get(text, style);
    tp.paint(canvas,
        center - Offset(tp.width / 2, tp.height / 2));
  }

  void clear() => _cache.clear();
}

// ---------------------------------------------------------------------------
// STATİK KATMAN
// ---------------------------------------------------------------------------

/// Halkalar + cetvel + burç bandı + evler + eksenleri tek Picture'a kaydeder.
ui.Picture recordStaticLayer(WheelLayout l, GlyphTextCache metin) {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  final z = l.zoom;

  final halkaBoya = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.0
    ..color = kRingLine;

  // Halkalar.
  for (final r in [
    l.rimOuter, l.signInner, l.rulerInner, l.houseInner, l.aspectRadius,
    if (l.data.isBiWheel) l.outerBandInner,
  ]) {
    canvas.drawCircle(l.center, r, halkaBoya);
  }
  if (!l.data.isBiWheel) {
    canvas.drawCircle(l.center, l.signOuter, halkaBoya);
  }

  // Burç bandı: element tonlu 12 dilim + bölücüler + vektör glifler.
  for (var i = 0; i < 12; i++) {
    final baslangicLon = i * 30.0;
    final a0 = l.screenAngle(baslangicLon);
    final a1 = l.screenAngle(baslangicLon + 30.0);
    final dilim = Path()
      ..moveTo(l.center.dx + l.signInner * math.cos(a0),
          l.center.dy - l.signInner * math.sin(a0))
      ..lineTo(l.center.dx + l.signOuter * math.cos(a0),
          l.center.dy - l.signOuter * math.sin(a0))
      ..arcTo(Rect.fromCircle(center: l.center, radius: l.signOuter),
          -a0, -(a1 - a0), false)
      ..lineTo(l.center.dx + l.signInner * math.cos(a1),
          l.center.dy - l.signInner * math.sin(a1))
      ..arcTo(Rect.fromCircle(center: l.center, radius: l.signInner),
          -a1, a1 - a0, false)
      ..close();
    canvas.drawPath(
        dilim,
        Paint()
          ..style = PaintingStyle.fill
          ..color = elementTintFor(i).withValues(alpha: 0.10));
    canvas.drawLine(
        l.onCircle(baslangicLon, l.signInner),
        l.onCircle(baslangicLon, l.signOuter),
        halkaBoya);

    final glifMerkez =
        l.onCircle(baslangicLon + 15.0, (l.signInner + l.signOuter) / 2);
    canvas.drawPath(
        signGlyphPath(i, glifMerkez, 13.0 * z),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.3 * z
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..color = RythoColors.parchment.withValues(alpha: 0.9));
  }

  // Derece cetveli: 1° kısa, 5° orta, 10° uzun+parlak — profesyonel
  // çarkın bir numaralı görsel işareti.
  for (var derece = 0; derece < 360; derece++) {
    final onemli = derece % 10 == 0;
    final orta = derece % 5 == 0;
    final boy = onemli ? 1.0 : (orta ? 0.62 : 0.34);
    final ic = l.rulerInner;
    final dis = l.rulerInner + (l.signInner - l.rulerInner) * boy;
    canvas.drawLine(
        l.onCircle(derece.toDouble(), ic),
        l.onCircle(derece.toDouble(), dis),
        Paint()
          ..strokeWidth = onemli ? 1.1 : 0.6
          ..color = kTickColor.withValues(alpha: onemli ? 0.55 : 0.28));
  }

  // Bi-wheel dış bandının kendi ince cetveli (5°/10°).
  if (l.data.isBiWheel) {
    for (var derece = 0; derece < 360; derece += 5) {
      final onemli = derece % 10 == 0;
      canvas.drawLine(
          l.onCircle(derece.toDouble(), l.outerBandInner),
          l.onCircle(derece.toDouble(),
              l.outerBandInner + (onemli ? 6.0 : 3.5)),
          Paint()
            ..strokeWidth = onemli ? 1.0 : 0.6
            ..color = kTickColor.withValues(alpha: 0.35));
    }
  }

  // Ev çizgileri + numaralar + AC/MC eksenleri ve etiketleri.
  final evler = l.data.houses;
  if (evler.length == 12) {
    for (var i = 0; i < 12; i++) {
      final eksen = i % 3 == 0; // 1/4/7/10 = AC/IC/DC/MC
      canvas.drawLine(
          l.onCircle(evler[i].absPosition, l.aspectRadius),
          l.onCircle(evler[i].absPosition,
              eksen ? l.signOuter : l.rulerInner),
          Paint()
            ..strokeWidth = eksen ? 1.8 : 0.8
            ..color = eksen ? kAxisColor : kRingLine);

      // Ev numarası: ev ortasında, göbek kenarında.
      final sonraki = evler[(i + 1) % 12].absPosition;
      var orta = evler[i].absPosition +
          (((sonraki - evler[i].absPosition) % 360) / 2);
      metin.paintCentered(
          canvas,
          '${i + 1}',
          _carkEtiketi(z,
              color: RythoColors.parchmentDim.withValues(alpha: 0.75)),
          l.onCircle(orta % 360, (l.houseInner + l.aspectRadius) / 2));
    }

    // AS/DS/MC/IC etiketleri + köşe derece etiketi — astrolog çarka
    // önce bunlarla yön verir. Göbek kenarında mürekkep diskli.
    const etiketler = [(0, 'AS'), (3, 'IC'), (6, 'DS'), (9, 'MC')];
    for (final (i, ad) in etiketler) {
      final lon = evler[i].absPosition;
      final konum = l.onCircle(lon, l.aspectRadius - 13.0 * z);
      canvas.drawCircle(konum, 10.0 * z, Paint()..color = kGlyphDisc);
      metin.paintCentered(
          canvas, ad, _carkEtiketi(z, color: kAxisColor), konum);
      metin.paintCentered(
          canvas,
          '${(lon % 30).floor()}°',
          _carkMikro(z,
              color: RythoColors.parchmentDim.withValues(alpha: 0.8)),
          l.onCircle(lon, l.aspectRadius - 13.0 * z) +
              Offset(0, 12.0 * z));
    }
  }

  return recorder.endRecording();
}

// ---------------------------------------------------------------------------
// DİNAMİK KATMAN
// ---------------------------------------------------------------------------

class RythoWheelPainter extends CustomPainter {
  RythoWheelPainter({
    required this.layout,
    required this.staticLayer,
    required this.textCache,
    required this.progress,
    this.filter = WheelAspectFilter.all,
    this.maxOrb = 8.0,
    this.showMinors = false,
    this.selection = WheelSelection.none,
  });

  final WheelLayout layout;
  final ui.Picture staticLayer;
  final GlyphTextCache textCache;

  /// Giriş süpürmesi 0..1 (reduceMotion'da sabit 1).
  final double progress;

  final WheelAspectFilter filter;
  final double maxOrb;
  final bool showMinors;
  final WheelSelection selection;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawPicture(staticLayer);

    final z = layout.zoom;
    // Açı ağı süpürmenin son %30'unda belirir (eski davranış korunur).
    final agAlfa = ((progress - 0.7) / 0.3).clamp(0.0, 1.0);

    // --- Açı ağı ---
    if (agAlfa > 0) {
      for (final s in layout.segments) {
        if (!aspectVisible(s.aspect, filter, maxOrb,
            showMinors: showMinors)) {
          continue;
        }
        final secili = identical(selection.aspect, s.aspect) ||
            (selection.aspect != null &&
                selection.aspect!.p1 == s.aspect.p1 &&
                selection.aspect!.p2 == s.aspect.p2 &&
                selection.aspect!.kind == s.aspect.kind);
        final soluk = !selection.isEmpty &&
            !secili &&
            !(selection.pointName != null &&
                selection.involvesPoint(s.aspect));
        final stil = aspectStroke(s.aspect.orb, maxOrb,
            dimmed: soluk, selected: secili);
        final renk = aspectColor(s.aspect.kind)
            .withValues(alpha: stil.alpha * agAlfa);
        final boya = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = stil.width * z
          ..color = renk;

        if (s.isConjunction) {
          // Kavuşum kiriş DEĞİL: jantta kısa braket yayı + nokta.
          final orta = s.rimMidLon!;
          final yay = Path()
            ..addArc(
                Rect.fromCircle(
                    center: layout.center,
                    radius: layout.aspectRadius + 3.0),
                -layout.screenAngle(orta - 3),
                -(layout.screenAngle(orta + 3) -
                    layout.screenAngle(orta - 3)));
          canvas.drawPath(yay, boya);
          canvas.drawCircle(
              layout.onCircle(orta, layout.aspectRadius + 3.0),
              2.0 * z,
              Paint()..color = renk);
          continue;
        }

        // Çizgi dili TEK tanımdan (chart_palette): lejant ve açı tablosu
        // aynı fonksiyonla çizer, ressam ayrı bir kural tutmaz.
        drawAspectLine(canvas, s.a, s.b, boya, aspectDashFor(s.aspect.kind),
            zoom: z);
      }
    }

    // Derece etiketleri: ham boyut küçük ve zoom yokken çizilmez.
    final dereceGorunur = dereceEtiketleriGorunur(
        rawSize: layout.size.shortestSide / z, zoom: z);

    // --- Glifler + işaretçiler ---
    for (final ring in layout.placements) {
      for (final g in ring) {
        // Süpürme: ekran açısına göre kademeli giriş.
        final rel =
            ((g.trueLon - layout.ascLon) % 360 + 360) % 360 / 360.0;
        if (progress < 1.0 && rel > progress) continue;

        final secili = selection.isPoint(g);
        final soluk = selection.pointName != null && !secili;
        final alfa = soluk ? 0.3 : 1.0;

        final halkaRengi = ringGlyphColor(layout.data, g.ring);
        final renk = halkaRengi.withValues(alpha: alfa);

        // Gerçek dereceye işaretçi (yelpaze dürüstlüğü).
        canvas.drawLine(
            g.pointerFrom,
            g.pointerTo,
            Paint()
              ..strokeWidth = 0.7
              ..color = halkaRengi.withValues(alpha: 0.30 * alfa));

        // Mürekkep diski: açı çizgileri glifin altından geçmesin.
        canvas.drawCircle(g.center, 10.5 * z,
            Paint()..color = kGlyphDisc.withValues(alpha: 0.9 * alfa));

        // Seçili gezegene lila halka — seçim yalnız ötekileri
        // soldurarak gösteriliyordu; tek gezegenli çarkta görünmezdi.
        if (secili) {
          canvas.drawCircle(
              g.center,
              12.0 * z,
              Paint()
                ..style = PaintingStyle.stroke
                ..strokeWidth = 1.2 * z
                ..color = kSelectedGlyphRing);
        }

        final vektor =
            planetGlyphPathOrNull(g.point.name, g.center, 13.0 * z);
        if (vektor != null) {
          canvas.drawPath(
              vektor,
              Paint()
                ..style = PaintingStyle.stroke
                ..strokeWidth = 1.2 * z
                ..strokeCap = StrokeCap.round
                ..color = renk);
        } else {
          // Doğrudan glif fontu: Manrope ♀♂ taşımıyor, yedek zinciri
          // çalışır ama ölçü ana fontun satır yüksekliğinden geliyordu.
          textCache.paintCentered(
              canvas,
              kPlanetTextGlyphs[g.point.name] ?? '•',
              RythoText.glyph(13.0 * z, color: renk),
              g.center);
        }

        // Derece etiketi (mono) — zoom ≥ 2'de dakika da açılır.
        if (dereceGorunur) {
          final derece = g.point.degreeInSign;
          final etiket = z >= 2.0
              ? formatDegree(derece)
              : '${derece.floor()}°';
          textCache.paintCentered(
              canvas,
              etiket,
              _carkMikro(z,
                  color: RythoColors.parchmentDim.withValues(alpha: alfa)),
              g.center + Offset(0, 12.5 * z));
        }

        // Retro işareti: renk DEĞİL glif — ℞ fontu güvenilmez, "R" yeter.
        if (g.point.retrograde) {
          textCache.paintCentered(
              canvas,
              'R',
              _carkMikro(z,
                  color: RythoColors.madder.withValues(alpha: alfa),
                  w: FontWeight.w700),
              g.center + Offset(9.0 * z, -8.0 * z));
        }
      }
    }
  }

  @override
  bool shouldRepaint(RythoWheelPainter old) =>
      old.progress != progress ||
      old.layout != layout ||
      old.staticLayer != staticLayer ||
      old.filter != filter ||
      old.maxOrb != maxOrb ||
      old.showMinors != showMinors ||
      old.selection != selection;
}
