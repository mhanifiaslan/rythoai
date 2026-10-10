/// Astrolojik glif tabloları ve glif fontu — TEK KAYNAK.
///
/// ## Neden var
/// ♀/♂ ve burç glifleri Android'de RENKLİ EMOJİ olarak çıkıyordu; mağaza
/// karesinde (`store/play/shot-2-chart.png`) Venüs mor-pembe, Mars turkuaz,
/// Çevrem'de burç glifleri turuncu daire (`raw/04-cevrem.png`). Kök ölçüldü:
/// `wheel_painter.dart` gezegen glifini Manrope ile basıyor; Manrope'ta ♀♂
/// yok → Skia emoji fontuna düşüyor. Burç glifleri (U+2648–2653) ise
/// `Emoji_Presentation=Yes` taşıdığı için VS15 bile güvenilir değil
/// (`wheel_glyphs.dart` bunu ölçmüştü).
///
/// Çözüm: `RythoText.*` stillerinin tamamı `fontFamilyFallback`'e bu fontu
/// alır — ana font glifi tanımıyorsa Skia emoji fontuna değil BURAYA düşer.
/// Font `tools/font_paketi_uret.py` ile iki OFL kaynaktan (Noto Sans Symbols
/// + Noto Sans Symbols 2) YALNIZ gereken kod noktalarıyla kurulur (7,4 KB).
/// Kapsam iddia edilmez, ölçülür: `assets/fonts/RythoGlyphs.codepoints.txt`
/// ve `test/font_paketi_test.dart` bu dosyadaki her kod noktasını orada arar.
///
/// ⚠️ `GoogleFonts.x(fontFamilyFallback: …)` İŞE YARAMAZ — google_fonts
/// döndürdüğü stili `fontFamilyFallback: [aile]` ile ÜZERİNE YAZIYOR
/// (`google_fonts_base.dart:116-119`, ölçüldü). Fallback `RythoText`
/// kurucularında `.copyWith` ile SONRADAN eklenir.
///
/// ## Neden tablolar burada
/// `kSignGlyphs` nebula_widgets'ta, `kPlanetTextGlyphs`/`kAspectTextGlyphs`
/// wheel_glyphs'te, bir de atlas_detail'in kendi `_kPlanetEmojis`i (☀️🌙
/// renkli, gerisi metin — iki dil) vardı. Glif fontunun kapsamı bu tablolara
/// bağlı; tablolar üç yerde yaşarsa kapsam bekçisi birini kaçırır.
library;

/// `pubspec.yaml` `fonts:` altındaki aile adı.
const kRythoGlyphFont = 'RythoGlyphs';

/// Burç glifleri (Koç→Balık), U+2648–2653.
const kSignGlyphs = ['♈', '♉', '♊', '♋', '♌', '♍', '♎', '♏', '♐', '♑', '♒', '♓'];

/// Gezegen adı → metin glifi. ☉ (U+2609) BİLEREK ☀️ emojisi değil: Güneş
/// ekranda öteki gezegenlerle aynı dili konuşur. Kiron/Lilith (⚷⚸) burada
/// yok — çarkta vektör, listede [kExtraPointGlyphs].
const Map<String, String> kPlanetTextGlyphs = {
  'Sun': '☉', 'Moon': '☽', 'Mercury': '☿', 'Venus': '♀', 'Mars': '♂',
  'Jupiter': '♃', 'Saturn': '♄', 'Uranus': '♅', 'Neptune': '♆',
  'Pluto': '♇', 'True_Node': '☊', 'True_South_Node': '☋',
  'Mean_Node': '☊', 'Mean_South_Node': '☋',
};

/// Ek noktalar (liste ekranları için). Çark bunları vektörle çizer çünkü
/// 13 px bantta çizgi kalınlığı ressamda kontrol edilmeli; listede fonttan.
const Map<String, String> kExtraPointGlyphs = {
  'Chiron': '⚷', 'Mean_Lilith': '⚸',
  'True_North_Lunar_Node': '☊', 'True_South_Lunar_Node': '☋',
};

/// Açı glifleri. Altmışlık (⚹) BİLEREK yok: ressam ve açı tablosu "tabloda
/// yoksa vektör çiz" kuralıyla çalışıyor (`aspectGlyphPath`); buraya
/// eklemek o kuralı sessizce değiştirirdi. Glif fontu ⚹'ı yine de taşıyor
/// (lejant/metin için) — tabloya alınması D6'da ressamla birlikte kararlaşır.
const Map<String, String> kAspectTextGlyphs = {
  'conjunction': '☌', 'opposition': '☍', 'trine': '△', 'square': '□',
};

/// Glif fontunun kapsamak ZORUNDA olduğu her kod noktası. Bekçi bu listeyi
/// `RythoGlyphs.codepoints.txt` ile karşılaştırır; buraya glif ekleyen
/// `tools/font_paketi_uret.py`'yi yeniden koşturmak zorunda kalır.
const kRythoGlyphCodePoints = <int>[
  0x2648, 0x2649, 0x264A, 0x264B, 0x264C, 0x264D, // ♈–♍
  0x264E, 0x264F, 0x2650, 0x2651, 0x2652, 0x2653, // ♎–♓
  0x2609, 0x263D, 0x263F, 0x2640, 0x2642, // ☉ ☽ ☿ ♀ ♂
  0x2643, 0x2644, 0x2645, 0x2646, 0x2647, // ♃ ♄ ♅ ♆ ♇
  0x260A, 0x260B, // ☊ ☋
  0x26B7, 0x26B8, // ⚷ ⚸
  0x260C, 0x260D, 0x25B3, 0x25A1, 0x26B9, // ☌ ☍ △ □ ⚹
  0x2726, 0x2727, 0x25B4, 0x25BE, // ✦ ✧ ▴ ▾
  0x25CB, 0x2691, // ○ ⚑
];
