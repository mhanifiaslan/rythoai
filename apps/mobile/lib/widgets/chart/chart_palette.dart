/// Çark paleti (HI-turu HA5) — koyu zemin + konvansiyona demirli renkler.
///
/// Profesyonel yazılım konvansiyonu: SERT = kırmızı ailesi, YUMUŞAK =
/// mavi/yeşil, kavuşum nötr/altın, minörler gri KESİK. Saf #FF0000 koyu
/// morda titreşir; bu palet parlaklığı yükseltip doymayı düşürür ve
/// mevcut tema tonlarını kullanır. Eski çarkın kusuru buradan da
/// görülür: magenta AYNI ANDA kare + karşıt + retro demekti — üç anlam
/// tek renk. Renk artık tek anlam taşır; sert/yumuşak/minör ayrımı AYRICA
/// çizgi diliyle verilir ([aspectDashFor]: sert düz, yumuşak uzun kesik,
/// minör kısa kesik) — renk körlüğünde de okunur. D6'ya kadar bu cümle
/// yanlıştı: yumuşak da düz çiziliyordu, yalnız minör kesikti.
///
/// Çizgi dili TEK tanımdır ve üç tüketicisi vardır: ressam (`wheel_painter`),
/// lejant ve açı tablosu hücresi (`aci_lejanti`). Üçü de [drawAspectLine]
/// ile çizer; ayrışırlarsa lejant çarkta olmayan bir çizgiyi anlatır.
library;

import 'dart:math' as math;
import 'dart:ui';

import '../../theme/rytho_theme.dart';
import 'chart_data.dart';

/// Açı türü → renk. Anahtarlar sunucuyla aynı (küçük-harf, HA1).
const Map<String, Color> kAspectColors = {
  'conjunction': Color(0xFFFFC24B), // altın — nötr/vurgulu
  'opposition': Color(0xFFFF5C7A),  // kırmızı okunur, koyuda yaşar
  'square': Color(0xFFFF8A5C),      // turuncu-kırmızı, karşıttan ayrışır
  'trine': Color(0xFF5AC8FA),       // serin mavi
  'sextile': Color(0xFF7FD8A4),     // celadon — "kolay" okunur
};

/// Minör açılar (yarım-altmışlık, yarım-kare, quincunx, sesqui, quintile).
const Color kMinorAspectColor = Color(0xFF8E8EA8);

/// Element tonları — burç bandının %12 alfa zemini (4 ton; 12'li
/// signColors bilerek DEĞİL: 12 renkli bant gökkuşağına dönüyor).
const List<Color> kElementTints = [
  Color(0xFFFF6B81), // ateş  (Koç/Aslan/Yay)
  Color(0xFFFFC24B), // toprak (Boğa/Başak/Oğlak)
  Color(0xFF5AC8FA), // hava  (İkizler/Terazi/Kova)
  Color(0xFF7FD8A4), // su    (Yengeç/Akrep/Balık)
];

Color elementTintFor(int signIndex) => kElementTints[signIndex % 4];

/// Halka kimliği: iç doğal (parşömen), dış transit (lila), partner
/// (altın-parlak) — bi-wheel lejantıyla aynı aile.
const Color kInnerGlyphColor = RythoColors.parchment;
const Color kOuterTransitColor = RythoColors.lilac;
const Color kOuterPartnerColor = Color(0xFFFFD98A);

/// Halkanın glif rengi — TEK kural. Ressam, konum tablosu, lejant,
/// açı tablosu başlığı ve paylaşım kartı hepsi buradan okur.
///
/// NEDEN: kural altı yerde kopyalanmıştı ve ikisi yanlıştı (ölçüldü,
/// 2026-10-10): konum tablosu sinastri partnerini lila çizerken çark altın
/// çiziyordu; açı tablosu bi-wheel transit sütununu altın başlıklarken çark
/// lila çiziyordu. Lejant "dış: Ayşe" deyip bir rengi gösteriyor, çark
/// başka bir rengi — ölçülen, yanlış adla sunuluyordu.
Color ringGlyphColor(ChartData data, int ring) {
  if (ring == 0 || ring >= data.rings.length) return kInnerGlyphColor;
  return data.rings[ring].kind == ChartRingKind.partner
      ? kOuterPartnerColor
      : kOuterTransitColor;
}

/// Yapı çizgileri.
const Color kRingLine = Color(0x387B62B8);      // lila ~%22
const Color kTickColor = Color(0x66B79CFF);     // cetvel işaretleri
const Color kAxisColor = Color(0xD9B79CFF);     // AC/MC eksenleri
const Color kGlyphDisc = Color(0xE614091E);     // glif altı mürekkep diski

/// Açı tablosu hücre kenarı: `RythoColors.line` %8 alfa. Sabit olarak
/// burada çünkü `const DecoratedBox` içinde `withValues` kullanılamıyor;
/// aynı literal iki hücre dalında yazılıydı.
const Color kAspectGridLine = Color(0x142C1F40);

/// Seçili gezegenin halkası (izole modu). Diğerleri 0,3 alfaya düşer ama
/// tek gezegenli çarkta solacak kimse yoktu — seçim GÖRÜNMEZDİ (ölçüldü).
const Color kSelectedGlyphRing = RythoColors.lilac;

/// Açı çizgisi görünümü: orb daraldıkça kalınlaşır ve belirginleşir
/// (Astrodienst konvansiyonu). [selected] izole modunda vurgulanan uç.
({double width, double alpha}) aspectStroke(double orb, double maxOrb,
    {bool dimmed = false, bool selected = false}) {
  final sikilik = (1 - (orb / maxOrb)).clamp(0.0, 1.0);
  var width = 0.6 + 1.6 * sikilik;
  var alpha = 0.25 + 0.55 * sikilik;
  if (selected) {
    width += 0.6;
    alpha = alpha < 0.55 ? 0.75 : alpha + 0.2;
  }
  if (dimmed) alpha *= 0.25;
  return (width: width, alpha: alpha.clamp(0.12, 1.0));
}

Color aspectColor(String kind) =>
    kAspectColors[kind] ?? kMinorAspectColor;

/// Açı sınıfının çizgi dili. Üç sınıf, üç çizgi; renk körü de ayırır.
enum AspectDash {
  /// Sert (karşıt, kare) ve kavuşum: düz.
  solid,

  /// Yumuşak (üçgen, altmışlık): uzun kesik.
  long,

  /// Minör: kısa kesik.
  short;

  /// Kesik uzunluğu (zoom 1, mantıksal px). Düz çizgide 0.
  double get dash => switch (this) {
        AspectDash.solid => 0,
        AspectDash.long => 7,
        AspectDash.short => 3,
      };

  /// Kesikler arası boşluk (zoom 1). Düz çizgide 0.
  double get gap => switch (this) {
        AspectDash.solid => 0,
        AspectDash.long => 4,
        AspectDash.short => 3,
      };
}

/// Açı türü → çizgi dili. Kavuşum "sert" sınıfında değil ama düz: çarkta
/// zaten kiriş değil jant braketi olarak çizilir, kesik bir braket okunmaz.
AspectDash aspectDashFor(String kind) {
  if (kHardAspects.contains(kind) || kind == 'conjunction') {
    return AspectDash.solid;
  }
  if (kSoftAspects.contains(kind)) return AspectDash.long;
  return AspectDash.short;
}

/// [a]→[b] arasına açı çizgisini verilen dilde çizer. [zoom] kesik
/// uzunluklarını geometriyle birlikte büyütür ("zoom = geometriyi büyüt"
/// stratejisi, metin gibi kesik de ölçekle keskin kalır).
void drawAspectLine(Canvas canvas, Offset a, Offset b, Paint paint,
    AspectDash dil, {double zoom = 1.0}) {
  if (dil == AspectDash.solid) {
    canvas.drawLine(a, b, paint);
    return;
  }
  final toplam = (b - a).distance;
  if (toplam <= 0) return;
  final yon = (b - a) / toplam;
  final dash = dil.dash * zoom;
  final gap = dil.gap * zoom;
  var m = 0.0;
  while (m < toplam) {
    final son = math.min(m + dash, toplam);
    canvas.drawLine(a + yon * m, a + yon * son, paint);
    m = son + gap;
  }
}
