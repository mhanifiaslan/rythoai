/// Çark veri modeli (HI-turu HA2) — SAF Dart, Flutter importsuz.
///
/// Üç sunucu yükü (natal / gökyüzü / transit / sinastri) TEK ortak modele
/// normalize edilir; ressam ve geometri katmanı yalnız bunu tanır. Yük
/// farklılıkları (natal `orbit` ↔ gökyüzü `orb`; natal `position` ↔ gökyüzü
/// `degree_in_sign`; kerykeion 'Ari' kodu ↔ gökyüzü 'aries' anahtarı)
/// BURADA ölür — ressama sızmaz.
///
/// "Ölçülmeyen söylenmez" uygulamaları:
/// * AC/MC natal yükünde `points` içinde YOKTUR (houses[0]/[9]'da yaşar);
///   burada birinci sınıf noktaya çevrilir — AC/MC açılarının sessizce
///   düşmesi (canlı kusur) böylece biter. Saatsiz haritada hiç üretilmez.
/// * Transit noktalarının `house_no`su Greenwich öznesinin artefaktıdır ve
///   ATILIR — transit gezegene ev iddia edilmez.
library;

/// Halka türü: iç (natal/kişi) ya da dış (gökyüzü/partner).
enum ChartRingKind { natal, transit, partner }

/// Açı türü kümesi — anahtarlar sunucuyla aynı (küçük-harf, HA1 sözleşmesi).
const Set<String> kMajorAspects = {
  'conjunction', 'opposition', 'square', 'trine', 'sextile',
};
const Set<String> kHardAspects = {'opposition', 'square'};
const Set<String> kSoftAspects = {'trine', 'sextile'};

/// kerykeion burç kodu ('Ari') ve gökyüzü anahtarı ('aries') → 0-11 indeks.
const Map<String, int> _kSignIndex = {
  'Ari': 0, 'Tau': 1, 'Gem': 2, 'Can': 3, 'Leo': 4, 'Vir': 5,
  'Lib': 6, 'Sco': 7, 'Sag': 8, 'Cap': 9, 'Aqu': 10, 'Pis': 11,
  'aries': 0, 'taurus': 1, 'gemini': 2, 'cancer': 3, 'leo': 4, 'virgo': 5,
  'libra': 6, 'scorpio': 7, 'sagittarius': 8, 'capricorn': 9,
  'aquarius': 10, 'pisces': 11,
};

/// 0-11 indeks → kerykeion kodu ('Ari'). Mevcut alt-sayfalar (showPointSheet)
/// burç adını bu koddan çözer.
const List<String> kSignCodes = [
  'Ari', 'Tau', 'Gem', 'Can', 'Leo', 'Vir',
  'Lib', 'Sco', 'Sag', 'Cap', 'Aqu', 'Pis',
];

int signIndexFromAny(String? code, double absPosition) {
  final i = _kSignIndex[code ?? ''];
  if (i != null) return i;
  return ((absPosition % 360) ~/ 30).clamp(0, 11);
}

/// Burç içi dereceyi `12°30'` biçimine çevirir — TEK tanım (konum tablosu
/// + ressamın zoom≥2 etiketi aynı hesabı iki yerde kopyalıyordu).
///
/// Dakika EN YAKINA yuvarlanır ve 60'a ulaşınca dereceye taşar: eski kopya
/// `floor(derece) + round(dakika)` yazıyordu ve 12,9999 için "12°60'"
/// basıyordu (ölçüldü) — olmayan bir dakika.
///
/// BURÇ SINIRI KARARI: 29,9999 → "29°59'", "30°00'" DEĞİL. Burç adı sunucunun
/// `sign` kodundan gelir (kerykeion `abs_position` tabanını alır) ve bu
/// formatlayıcı o adla ÇELİŞEMEZ — "Balık 30°00'" ölçüleni yanlış adla
/// sunmaktır (30° Balık diye bir konum yok, o 0° Koç'tur). Burç adını
/// yuvarlanmış boylamdan türetmek seçilmedi: `signIndex` element sayımı ve
/// alt-sayfalar için kanonik ve sunucuyla aynı kalmalı. Bedel: yalnız
/// sınıra 30 açı-saniyesinden yakın konumda hata 0,5' yerine 1' (astro.com
/// / Solar Fire'ın dakika KIRPMA konvansiyonu zaten bunu kabul eder).
String formatDegree(double degreeInSign) {
  final d = degreeInSign.clamp(0.0, 30.0);
  var derece = d.floor();
  var dakika = ((d - derece) * 60).round();
  if (dakika == 60) {
    derece += 1;
    dakika = 0;
  }
  if (derece >= 30) {
    derece = 29;
    dakika = 59;
  }
  return "$derece°${dakika.toString().padLeft(2, '0')}'";
}

class ChartPoint {
  const ChartPoint({
    required this.name,
    required this.localName,
    required this.absPosition,
    required this.signIndex,
    required this.degreeInSign,
    this.retrograde = false,
    this.houseNo,
    this.speed,
    this.isAngle = false,
  });

  /// Kararlı ad ("Sun", "Ascendant") — açı uçları bununla çözülür.
  final String name;

  /// Görünen ad (sunucu `name_local`; yoksa kararlı ad).
  final String localName;

  final double absPosition;
  final int signIndex;
  final double degreeInSign;
  final bool retrograde;
  final int? houseNo;
  final double? speed;

  /// AC/MC gibi eksen noktası — glif değil etiketle çizilir.
  final bool isAngle;
}

class ChartHouse {
  const ChartHouse(
      {required this.house, required this.absPosition, this.signIndex});

  final int house;
  final double absPosition;
  final int? signIndex;
}

class ChartAspect {
  const ChartAspect({
    required this.p1,
    required this.p2,
    required this.kind,
    required this.orb,
    this.p1Ring = 0,
    this.p2Ring = 0,
    this.applying,
    this.p1Local,
    this.p2Local,
    this.kindLocal,
  });

  final String p1;
  final String p2;

  /// Küçük-harf açı anahtarı ("trine") — renk/stil bununla çözülür.
  final String kind;

  final double orb;

  /// Uçların halka indeksi (0 = iç). Çapraz açıda p2Ring = 1.
  final int p1Ring;
  final int p2Ring;

  /// true = yaklaşan (applying), false = ayrılan; null = bilinmiyor.
  final bool? applying;

  /// Sunucu `*_local` alanları (HA1) — alt-sayfa/çip etiketleri.
  final String? p1Local;
  final String? p2Local;
  final String? kindLocal;

  /// "Venüs Üçgen Mars" gibi hazır yerel etiket (seçim çubuğu).
  String? get localLabel => (p1Local != null && kindLocal != null)
      ? '$p1Local $kindLocal ${p2Local ?? p2}'
      : null;

  bool get isMajor => kMajorAspects.contains(kind);
  bool get isHard => kHardAspects.contains(kind);
  bool get isSoft => kSoftAspects.contains(kind);
  bool get isCross => p1Ring != p2Ring;
}

class ChartRing {
  const ChartRing({
    required this.kind,
    required this.points,
    this.label = '',
  });

  final ChartRingKind kind;
  final List<ChartPoint> points;

  /// Lejant etiketi ("sen", "gökyüzü", kişi adı).
  final String label;

  ChartPoint? pointByName(String name) {
    for (final p in points) {
      if (p.name == name) return p;
    }
    return null;
  }
}

class ChartData {
  const ChartData({
    required this.rings,
    required this.houses,
    required this.aspects,
    this.hourKnown = true,
  });

  /// 1 halka = tekil çark; 2 halka = bi-wheel/sinastri (0 = iç).
  final List<ChartRing> rings;

  /// Evler HER ZAMAN iç halkanındır (bi-wheel konvansiyonu). Boş liste =
  /// evsiz düzen (saatsiz natal ya da gökyüzü — 0° Koç solda).
  final List<ChartHouse> houses;

  final List<ChartAspect> aspects;

  final bool hourKnown;

  bool get isBiWheel => rings.length > 1;
  bool get houseless => houses.isEmpty;

  /// Açı ucunu çözer; bulunamazsa null (o açı çizilmez — uydurma uç yok).
  ChartPoint? resolve(String name, int ring) =>
      ring < rings.length ? rings[ring].pointByName(name) : null;

  // ---------------------------------------------------------------------
  // Fabrikalar
  // ---------------------------------------------------------------------

  /// Natal yükü (POST /astrology/natal-chart yanıtındaki `data`).
  factory ChartData.fromNatal(Map<String, dynamic> json,
      {String label = ''}) {
    final houses = _houses(json['houses']);
    final points = _natalPoints(json['points']);
    // AC/MC birinci sınıf nokta olur (yalnız saatliyken evler var).
    points.addAll(_anglesFromHouses(houses));
    return ChartData(
      rings: [ChartRing(kind: ChartRingKind.natal, points: points,
          label: label)],
      houses: houses,
      aspects: _aspects(json['aspects'], orbKey: 'orbit'),
      hourKnown: houses.isNotEmpty,
    );
  }

  /// Gökyüzü yükü (GET /sky/now yanıtındaki `data`) — evsiz, tek halka.
  factory ChartData.fromSky(Map<String, dynamic> json, {String label = ''}) {
    return ChartData(
      rings: [ChartRing(kind: ChartRingKind.transit,
          points: _skyPoints(json['planets']), label: label)],
      houses: const [],
      aspects: _aspects(json['aspects'], orbKey: 'orb'),
      hourKnown: true,
    );
  }

  /// Bi-wheel: iç = natal, dış = bugünün transitleri
  /// (POST /astrology/transits). Çapraz açılar `aspects_to_natal`dan —
  /// p1 = TRANSİT gezegen (dış halka), p2 = natal nokta (iç halka).
  /// Transit noktalarının ev alanları BURADA atılır (Greenwich artefaktı).
  factory ChartData.fromTransits(Map<String, dynamic> natalJson,
      Map<String, dynamic> transitsJson,
      {String innerLabel = '', String outerLabel = ''}) {
    final natal = ChartData.fromNatal(natalJson, label: innerLabel);
    final transit = _natalPoints(transitsJson['transiting_points'],
        stripHouses: true);
    return ChartData(
      rings: [
        natal.rings.first,
        ChartRing(kind: ChartRingKind.transit, points: transit,
            label: outerLabel),
      ],
      houses: natal.houses,
      aspects: _aspects(transitsJson['aspects_to_natal'],
          orbKey: 'orbit', p1Ring: 1, p2Ring: 0),
      hourKnown: natal.hourKnown,
    );
  }

  /// Sinastri: iç = kullanıcı (points1), dış = kişi (points2); YALNIZ
  /// çapraz açılar (p1 → iç, p2 → dış). Ev görünümü [useInnerHouses] ile
  /// A/B arasında seçilir (ikisi birden asla — okunmaz).
  factory ChartData.fromSynastry(Map<String, dynamic> json,
      {String innerLabel = '',
      String outerLabel = '',
      bool useInnerHouses = true}) {
    final houses1 = _houses(json['houses1']);
    final houses2 = _houses(json['houses2']);
    final points1 = _natalPoints(json['points1']);
    final points2 = _natalPoints(json['points2']);
    final evler = useInnerHouses ? houses1 : houses2;
    // Eksenler yalnız ev sahibinin halkasına eklenir: açı uçlarında
    // Ascendant görünebilir ve saatli tarafın ekseni gerçektir.
    if (useInnerHouses) {
      points1.addAll(_anglesFromHouses(houses1));
    } else {
      points2.addAll(_anglesFromHouses(houses2));
    }
    return ChartData(
      rings: [
        ChartRing(kind: ChartRingKind.natal, points: points1,
            label: innerLabel),
        ChartRing(kind: ChartRingKind.partner, points: points2,
            label: outerLabel),
      ],
      houses: evler,
      aspects: _aspects(json['aspects'],
          orbKey: 'orbit', p1Ring: 0, p2Ring: 1),
      hourKnown: evler.isNotEmpty,
    );
  }
}

// -------------------------------------------------------------------------
// Yük ayrıştırıcıları
// -------------------------------------------------------------------------

double _d(dynamic v) => (v as num?)?.toDouble() ?? 0.0;

List<ChartHouse> _houses(dynamic raw) {
  final list = (raw as List?) ?? const [];
  return [
    for (final h in list.cast<Map>())
      ChartHouse(
        house: (h['house'] as num?)?.toInt() ?? 0,
        absPosition: _d(h['abs_position']),
        signIndex: _kSignIndex[h['sign'] ?? ''],
      ),
  ];
}

List<ChartPoint> _natalPoints(dynamic raw, {bool stripHouses = false}) {
  final list = (raw as List?) ?? const [];
  return [
    for (final p in list.cast<Map>())
      ChartPoint(
        name: p['name'] as String? ?? '?',
        localName: (p['name_local'] ?? p['name_tr'] ?? p['name'] ?? '?')
            as String,
        absPosition: _d(p['abs_position']),
        signIndex: signIndexFromAny(
            p['sign'] as String?, _d(p['abs_position'])),
        degreeInSign: _d(p['position']),
        retrograde: p['retrograde'] == true,
        houseNo: stripHouses ? null : (p['house_no'] as num?)?.toInt(),
        speed: (p['speed'] as num?)?.toDouble(),
      ),
  ];
}

List<ChartPoint> _skyPoints(dynamic raw) {
  final list = (raw as List?) ?? const [];
  return [
    for (final p in list.cast<Map>())
      ChartPoint(
        name: p['name'] as String? ?? '?',
        localName: (p['name_local'] ?? p['name'] ?? '?') as String,
        absPosition: _d(p['longitude']),
        signIndex: signIndexFromAny(
            p['sign'] as String?, _d(p['longitude'])),
        degreeInSign: _d(p['degree_in_sign']),
        retrograde: p['retrograde'] == true,
        speed: (p['speed'] as num?)?.toDouble(),
      ),
  ];
}

List<ChartAspect> _aspects(dynamic raw,
    {required String orbKey, int p1Ring = 0, int p2Ring = 0}) {
  final list = (raw as List?) ?? const [];
  return [
    for (final a in list.cast<Map>())
      if (a['p1'] != null && a['p2'] != null && a['aspect'] != null)
        ChartAspect(
          p1: a['p1'] as String,
          p2: a['p2'] as String,
          // HA1 sözleşmesi: tür küçük-harf kararlı anahtardır; eski bir
          // sunucu büyük harfle döndürse bile normalize edilir.
          kind: (a['aspect'] as String).toLowerCase(),
          orb: _d(a[orbKey] ?? a['orbit'] ?? a['orb']),
          p1Ring: p1Ring,
          p2Ring: p2Ring,
          applying: switch (a['movement']) {
            'applying' => true,
            'separating' => false,
            _ => null,
          },
          p1Local: a['p1_local'] as String?,
          p2Local: a['p2_local'] as String?,
          kindLocal: a['aspect_local'] as String?,
        ),
  ];
}

/// AC/MC: houses[0]/[9] `abs_position`dan türetilir. Ev listesi boşsa
/// (saatsiz) HİÇ üretilmez — öğle dolgusu ekseni çizilmez.
List<ChartPoint> _anglesFromHouses(List<ChartHouse> houses) {
  if (houses.length < 12) return const [];
  ChartPoint eksen(String name, String localFallback, ChartHouse h) =>
      ChartPoint(
        name: name,
        localName: localFallback,
        absPosition: h.absPosition,
        signIndex:
            h.signIndex ?? signIndexFromAny(null, h.absPosition),
        degreeInSign: h.absPosition % 30,
        isAngle: true,
      );
  return [
    eksen('Ascendant', 'AC', houses[0]),
    eksen('Medium_Coeli', 'MC', houses[9]),
  ];
}
