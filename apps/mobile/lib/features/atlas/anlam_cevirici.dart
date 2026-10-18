// Ölçümü gündelik dile çeviren SAF fonksiyonlar — LLM yok, ağ yok.
//
// NEDEN ayrı dosya: Rytho'nun işi gökyüzü ile insan arasındaki aracıyı
// kaldırmak; "Ay ☍ Plüton 0°" ya da "Toprak 2/8" bilmeyene hiçbir şey
// söylemiyordu (sahip, cihazda, 2026-10-18). Çeviri ölçülmüş veri × sabit
// TR/EN metinden kurulur ve widget'tan bağımsız sınanır.
import '../../core/tr_metin.dart';
import '../../l10n/app_localizations.dart';
import '../../widgets/nebula_widgets.dart' show signDisplayName;
import '../../widgets/yolculuk.dart' show YolculukDuragi;

/// Açının gücü, orbdan. Eşikler ekranın kendi beyanına dayanır
/// (`aspectsSortNote`: orb ne kadar darsa açı o kadar güçlü) — sayı
/// kullanıcıya derece olarak değil söz olarak gider, derece dayanakta.
enum AciGucu { cokGuclu, guclu, hafif }

AciGucu? aciGucu(double? orb) {
  if (orb == null) return null;
  final o = orb.abs();
  if (o < 1) return AciGucu.cokGuclu;
  if (o < 3) return AciGucu.guclu;
  return AciGucu.hafif;
}

String aciGucuMetni(AppLocalizations l10n, AciGucu guc) => switch (guc) {
      AciGucu.cokGuclu => l10n.aspectStrengthVeryStrong,
      AciGucu.guclu => l10n.aspectStrengthStrong,
      AciGucu.hafif => l10n.aspectStrengthMild,
    };

/// Gezegenin cümlede ÖZNE olarak kısa adı ("duyguların", "dönüşüm gücün").
/// Tanınmayan nokta için null — cümle kurulmaz, uydurulmaz.
String? aciOznesi(AppLocalizations l10n, String? ad) => switch (ad) {
      'Sun' => l10n.aspectSubjectSun,
      'Moon' => l10n.aspectSubjectMoon,
      'Mercury' => l10n.aspectSubjectMercury,
      'Venus' => l10n.aspectSubjectVenus,
      'Mars' => l10n.aspectSubjectMars,
      'Jupiter' => l10n.aspectSubjectJupiter,
      'Saturn' => l10n.aspectSubjectSaturn,
      'Uranus' => l10n.aspectSubjectUranus,
      'Neptune' => l10n.aspectSubjectNeptune,
      'Pluto' => l10n.aspectSubjectPluto,
      'Chiron' => l10n.aspectSubjectChiron,
      'Mean_Lilith' => l10n.aspectSubjectLilith,
      'True_North_Lunar_Node' => l10n.aspectSubjectNorthNode,
      'True_South_Lunar_Node' => l10n.aspectSubjectSouthNode,
      'Ascendant' => l10n.aspectSubjectAscendant,
      'Medium_Coeli' => l10n.aspectSubjectMidheaven,
      'Descendant' => l10n.aspectSubjectDescendant,
      'Imum_Coeli' => l10n.aspectSubjectImumCoeli,
      _ => null,
    };

/// Açı satırının anlam cümlesi: iki gezegenin rolü × açı türü.
///
/// Yalnız beş büyük açı için kurulur — minör açıya anlam metni bilinçli
/// olarak YOK (`aspectMeaningText` de null döner; `anlam_once_test`
/// "uydurulmuyor"). Öyle bir satırda yalnız çift adı kalır.
String? aciCumlesi(AppLocalizations l10n, Map<String, dynamic> aci,
    {required bool turkce}) {
  final a = aciOznesi(l10n, aci['p1'] as String?);
  final b = aciOznesi(l10n, aci['p2'] as String?);
  if (a == null || b == null) return null;
  final cumle = switch (aci['aspect']) {
    'conjunction' => l10n.aspectSentenceConjunction(a, b),
    'opposition' => l10n.aspectSentenceOpposition(a, b),
    'square' => l10n.aspectSentenceSquare(a, b),
    'trine' => l10n.aspectSentenceTrine(a, b),
    'sextile' => l10n.aspectSentenceSextile(a, b),
    _ => null,
  };
  return cumle == null ? null : basHarfBuyuk(cumle, turkce: turkce);
}

/// Element / nitelik çubuğunun DÜZEY sözü — "Toprak 2/8" yerine.
///
/// Sekiz noktada element ortalaması 2 (8÷4), nitelik ~2,7 (8÷3): 2-3 ortada
/// = "dengeli", 4+ "güçlü", 1 "az", 0 "yok". Saatsiz haritada (7 nokta,
/// Yükselen yok) eşik aynı; payda metinde ayrıca yazılıyor. Sözün yargısı
/// yok — "iyi/kötü" değil (`traitsLevelNote`).
enum DengeDuzeyi { yok, az, dengeli, guclu }

DengeDuzeyi dengeDuzeyi(int sayi) {
  if (sayi <= 0) return DengeDuzeyi.yok;
  if (sayi == 1) return DengeDuzeyi.az;
  if (sayi <= 3) return DengeDuzeyi.dengeli;
  return DengeDuzeyi.guclu;
}

String dengeDuzeyiMetni(AppLocalizations l10n, DengeDuzeyi d) => switch (d) {
      DengeDuzeyi.yok => l10n.traitsLevelNone,
      DengeDuzeyi.az => l10n.traitsLevelLow,
      DengeDuzeyi.dengeli => l10n.traitsLevelBalanced,
      DengeDuzeyi.guclu => l10n.traitsLevelStrong,
    };

/// Baskın nitelik — `baskinElement` ile AYNI kural: tepede eşitlik varsa
/// null, baskınlık söylenmez (ölçülmeyen söylenmez).
String? baskinNitelik(Map<String, dynamic>? dagilim) {
  if (dagilim == null || dagilim.isEmpty) return null;
  final sirali = [
    for (final m in const ['cardinal', 'fixed', 'mutable'])
      (m, (dagilim[m] as num?)?.toInt() ?? 0),
  ]..sort((x, y) => y.$2.compareTo(x.$2));
  if (sirali[0].$2 <= sirali[1].$2) return null;
  return sirali[0].$1;
}

/// Adın yanındaki tek kelimelik gündelik karşılık ("Toprak · somutluk").
String elementKelimesi(AppLocalizations l10n, String key) => switch (key) {
      'fire' => l10n.elementFireWord,
      'earth' => l10n.elementEarthWord,
      'air' => l10n.elementAirWord,
      'water' => l10n.elementWaterWord,
      _ => '',
    };

String nitelikKelimesi(AppLocalizations l10n, String key) => switch (key) {
      'cardinal' => l10n.modalityCardinalWord,
      'fixed' => l10n.modalityFixedWord,
      'mutable' => l10n.modalityMutableWord,
      _ => '',
    };

// ---------------------------------------------------------------------------
// Yolculuk haritaları (İç Mevsim, Yıl Haritası) — 2026-10-18
// ---------------------------------------------------------------------------
//
// Sahip: "makale gibi sıkıcı, bakmak bile istemiyorum — bu yıl hangi
// evrenlerde gezeceğim?" Harita ölçülmüş tarihlerden ve evlerden kurulur;
// cümleler sabit tablodan. Yeni LLM çağrısı YOK.

/// Burç kodu (`Ari`…`Pis`) → "iklim" cümlesi. Tanınmayan kod: null.
String? burcIklimi(AppLocalizations l10n, String? kod) => switch (kod) {
      'Ari' => l10n.signClimateAri,
      'Tau' => l10n.signClimateTau,
      'Gem' => l10n.signClimateGem,
      'Can' => l10n.signClimateCan,
      'Leo' => l10n.signClimateLeo,
      'Vir' => l10n.signClimateVir,
      'Lib' => l10n.signClimateLib,
      'Sco' => l10n.signClimateSco,
      'Sag' => l10n.signClimateSag,
      'Cap' => l10n.signClimateCap,
      'Aqu' => l10n.signClimateAqu,
      'Pis' => l10n.signClimatePis,
      _ => null,
    };

/// İlerlemiş Ay evresi kodu → anlam cümlesi (sunucunun 8 evre adı).
String? evreAnlami(AppLocalizations l10n, String? evre) => switch (evre) {
      'new_moon' => l10n.progPhaseMeaningNewMoon,
      'waxing_crescent' => l10n.progPhaseMeaningWaxingCrescent,
      'first_quarter' => l10n.progPhaseMeaningFirstQuarter,
      'waxing_gibbous' => l10n.progPhaseMeaningWaxingGibbous,
      'full_moon' => l10n.progPhaseMeaningFullMoon,
      'waning_gibbous' => l10n.progPhaseMeaningWaningGibbous,
      'last_quarter' => l10n.progPhaseMeaningLastQuarter,
      'waning_crescent' => l10n.progPhaseMeaningWaningCrescent,
      _ => null,
    };

const _burcKodlari = [
  'Ari', 'Tau', 'Gem', 'Can', 'Leo', 'Vir',
  'Lib', 'Sco', 'Sag', 'Cap', 'Aqu', 'Pis',
];

/// İlerlemiş Ay'ın SONRAKİ burcu. Ölçülmüş: ilerlemiş Ay hiç geri gitmez
/// (ikincil ilerlemede günde ~13° → yılda ~13°), yani bir sonraki burç
/// zodyak sırasındaki komşudur. Tanınmayan kod: null.
String? sonrakiBurc(String? kod) {
  final i = _burcKodlari.indexOf(kod ?? '');
  return i < 0 ? null : _burcKodlari[(i + 1) % 12];
}

int? burcIndeksi(String? kod) {
  final i = _burcKodlari.indexOf(kod ?? '');
  return i < 0 ? null : i;
}

/// Güneş dönüşü yılında neredesin: oran (0..1) ve kaçıncı ay (1..12).
/// Ay = geçen gün ÷ (yıl uzunluğu ÷ 12), tavan 12.
({double oran, int ay}) yilIlerlemesi(
    DateTime bas, DateTime son, DateTime simdi) {
  final toplam = son.difference(bas).inMinutes;
  if (toplam <= 0) return (oran: 0, ay: 1);
  final gecen = simdi.difference(bas).inMinutes.clamp(0, toplam);
  final oran = gecen / toplam;
  final ay = (oran * 12).floor() + 1;
  return (oran: oran, ay: ay > 12 ? 12 : ay);
}

/// Yılın en kalabalık üç evi — "bu yıl en çok gezeceğin evrenler".
///
/// Yalnız `house_no` taşıyan noktalar sayılır: saatsiz doğumda sunucu evi
/// HİÇ göndermez (2026-10-18), liste boş döner ve ekran ev uydurmaz.
/// Sıra: gezegen sayısı çoktan aza, eşitlikte ev numarası küçükten büyüğe
/// (kararlı ve ölçülmüş; "önemli ev" hükmü verilmez).
List<({int ev, List<Map<String, dynamic>> noktalar})> yilEvrenleri(
    List<Map<String, dynamic>> noktalar) {
  final kume = <int, List<Map<String, dynamic>>>{};
  for (final p in noktalar) {
    final ev = p['house_no'];
    if (ev is int && ev >= 1 && ev <= 12) {
      kume.putIfAbsent(ev, () => []).add(p);
    }
  }
  final sirali = kume.entries.toList()
    ..sort((x, y) {
      final s = y.value.length.compareTo(x.value.length);
      return s != 0 ? s : x.key.compareTo(y.key);
    });
  return [
    for (final e in sirali.take(3)) (ev: e.key, noktalar: e.value),
  ];
}

/// İç Mevsim yolculuk durakları: ŞU AN (ilerlemiş Ay'ın burcu = iç iklim +
/// evre) → SONRAKİ iç iklim (ölçülmüş `next_sign_at`) → dönüm noktaları
/// (güneş yayı kesinleşmeleri, yıl-ay hassasiyeti, bugünden sonrakiler).
///
/// Sonraki burç adı ÖLÇÜMDEN türetilir (ilerlemiş Ay geri gitmez →
/// zodyak komşusu); tarihi sunucunun. Daha uzak geçişler TAHMİN EDİLMEZ
/// (ekstrapolasyon ölçüm değildir).
List<YolculukDuragi> icYolculukDuraklari(
  AppLocalizations l10n,
  Map<String, dynamic> ay,
  List<Map<String, dynamic>> vurgular,
  DateTime simdi, {
  required bool turkce,
}) {
  String? cumle(String? s) =>
      s == null ? null : basHarfBuyuk(s, turkce: turkce);
  final kod = ay['sign'] as String?;
  final buAn = [
    cumle(burcIklimi(l10n, kod)),
    evreAnlami(l10n, ay['phase'] as String?),
  ].whereType<String>().join('\n');
  final duraklar = <YolculukDuragi>[
    YolculukDuragi(
      ust: l10n.innerJourneyNow,
      baslik: l10n.innerJourneyNowTitle(
          '${ay['sign_local'] ?? kod ?? ''}'),
      govde: buAn.isEmpty ? null : buAn,
      simdi: true,
    ),
  ];
  final sonraki = sonrakiBurc(kod);
  final sonrakiIndeks = burcIndeksi(sonraki);
  final tarih = ay['next_sign_at'] as String?;
  if (sonraki != null && sonrakiIndeks != null && tarih != null) {
    duraklar.add(YolculukDuragi(
      ust: l10n.innerJourneyNextWhen(tarih),
      baslik: l10n.innerJourneyNextTitle(
          signDisplayName(l10n, sonrakiIndeks)),
      govde: cumle(burcIklimi(l10n, sonraki)),
    ));
  }
  final buAy =
      '${simdi.year.toString().padLeft(4, '0')}-${simdi.month.toString().padLeft(2, '0')}';
  final gelecek = [
    for (final h in vurgular)
      if ('${h['exact_on'] ?? ''}'.length >= 7 &&
          '${h['exact_on']}'.substring(0, 7).compareTo(buAy) >= 0)
        h,
  ]..sort((x, y) => '${x['exact_on']}'.compareTo('${y['exact_on']}'));
  for (final h in gelecek) {
    final ham = aciCumlesi(
        l10n,
        {'p1': h['directed'], 'p2': h['natal'], 'aspect': h['aspect']},
        turkce: turkce);
    duraklar.add(YolculukDuragi(
      ust: l10n.innerJourneyMilestone('${h['exact_on']}'.substring(0, 7)),
      baslik: ham ??
          '${h['directed_local'] ?? ''} ${h['aspect_local'] ?? ''} '
              '${h['natal_local'] ?? ''}'.trim(),
    ));
  }
  return duraklar;
}
