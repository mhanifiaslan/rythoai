/// Atlas'ın detay sayfaları: gezegenler, kişilik, açılar.
///
/// ## Neden ayrıldılar
///
/// Hepsi Atlas akışının içinde, alt alta duruyordu. Ölçülen ekran uzunluğu
/// ~2000 px'di ve kullanıcının tarifi şuydu:
///
/// > "atlas sayfası da tuhaf... herşey heryerde hissi var. tam bir kaos."
///
/// Teşhis "çok özellik var" değil, **hepsinin aynı seviyede durması**.
/// Artık Atlas bir dizin; her giriş kendi sayfasını açıyor.
///
/// ## R5: "bu veri nereden geliyor?"
///
/// Cihaz turunda üç ekran da aynı şikâyeti aldı: sayılar görünüyor, ne
/// oldukları görünmüyor. Üçü de aynı sözleşmeye geçti — **ölçüm görünür,
/// dayanağı bir dokunuş uzakta**:
///
/// * Kişilik: yüzde uydurmak yerine SUNUCUNUN kanonik sayımı (geleneksel
///   yedili + Yükselen) ve hangi noktadan geldiği. Eski `TraitBars`
///   formülü (`30 + 10·sayım`) silindi: yalnız sekiz değer üretebiliyordu,
///   dört elementin toplamı %260 ediyordu, Ay düğümlerini sayıp Yükselen'i
///   dışarıda bırakıyordu.
/// * Gezegenler: derece + ev artık görünür (veri hep elimizdeydi),
///   dokunuşla gündelik dil açıklaması.
/// * Açılar: en dar orb önce, sert/uyumlu/kavuşum diye gruplu, dokunuşla
///   açıklama.
library;

import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../theme/rytho_theme.dart';
import '../../theme/rytho_tokens.dart';
import '../../widgets/cosmic_scaffold.dart';
import '../../widgets/glass.dart';
import '../../widgets/motion.dart';
import '../../widgets/nebula_widgets.dart';
import 'atlas_screen.dart'
    show aspectKindLabel, aspectPairLabel, planetSignLabel;

/// kerykeion burç kodu -> zodyak indeksi (dilden bağımsız).
///
/// Eski kod glifi `kSignNamesTr.indexOf(sign_tr)` ile buluyordu: İngilizce
/// arayüzde ya da ad değişiminde sessizce boş glif veriyordu.
const _kSignCodeIndex = {
  'Ari': 0, 'Tau': 1, 'Gem': 2, 'Can': 3, 'Leo': 4, 'Vir': 5,
  'Lib': 6, 'Sco': 7, 'Sag': 8, 'Cap': 9, 'Aqu': 10, 'Pis': 11,
};

String _signGlyph(Map<String, dynamic> p) {
  final i = _kSignCodeIndex[p['sign']];
  if (i != null) return kSignGlyphs[i];
  final tr = kSignNamesTr.indexOf(p['sign_tr'] ?? '');
  return tr >= 0 ? kSignGlyphs[tr] : '';
}

/// Noktanın arayüz dilindeki adı — sunucu `name_local`'ı üretiyor.
String _pointName(Map<String, dynamic> p) =>
    (p['name_local'] ?? p['name_tr'] ?? p['name'] ?? '') as String;

/// Detay sayfalarının ortak iskeleti.
class _DetayIskelet extends StatelessWidget {
  const _DetayIskelet({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return CosmicScaffold(
      appBar: AppBar(title: Text(title)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(RythoSpace.lg, RythoSpace.md,
              RythoSpace.lg, RythoSpace.xxl),
          // Kademeli giriş (R12-C3): üç detay sayfası tek iskeletten
          // ısınır; uzun listede gecikme 8. blokta sabitlenir.
          children: [
            for (var i = 0; i < children.length; i++)
              RythoReveal(index: i.clamp(0, 7), child: children[i]),
          ],
        ),
      ),
    );
  }
}

/// Ekranların altındaki dürüstlük dipnotu — ölçümün sınırını söyler.
class _Dipnot extends StatelessWidget {
  const _Dipnot(this.metin);

  final String metin;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, RythoSpace.sm, 4, 0),
        child: Text(metin,
            style: RythoText.body(11,
                color: RythoColors.parchmentDim, height: 1.45)),
      );
}

// ---------------------------------------------------------------------------
// Gezegen Konumları
// ---------------------------------------------------------------------------

/// Klasik yedili + modern gezegenler; ek noktalar ayrı bölümde.
const _kPlanetEmojis = {
  'Sun': '☀️', 'Moon': '🌙', 'Mercury': '☿', 'Venus': '♀', 'Mars': '♂',
  'Jupiter': '♃', 'Saturn': '♄', 'Uranus': '♅', 'Neptune': '♆',
  'Pluto': '♇',
};

const _kExtraEmojis = {
  'Chiron': '⚷', 'Mean_Lilith': '⚸',
  'True_North_Lunar_Node': '☊', 'True_South_Lunar_Node': '☋',
};

class AtlasPlanetsScreen extends StatelessWidget {
  const AtlasPlanetsScreen({super.key, required this.points});

  final List<Map<String, dynamic>> points;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final klasik = points
        .where((p) => _kPlanetEmojis.containsKey(p['name']))
        .toList();
    // Ek noktalar artık SESSİZCE atılmıyor (eski filtre Kiron, Lilith ve
    // iki Ay düğümünü listeden düşürüyordu — hesaplanıp saklanan veri).
    final ek =
        points.where((p) => _kExtraEmojis.containsKey(p['name'])).toList();

    return _DetayIskelet(
      title: l10n.atlasPlanetPositions,
      children: [
        GlassPanel(child: PlanetGrid(points: klasik)),
        if (ek.isNotEmpty) ...[
          const SizedBox(height: RythoSpace.sm),
          GlassPanel(
              label: l10n.planetsSectionExtra,
              child: PlanetGrid(points: ek)),
        ],
        _Dipnot(l10n.planetsFootnote),
      ],
    );
  }
}

/// Gezegen ızgarası — her hücre: emoji + ad + burç + derece + ev.
class PlanetGrid extends StatelessWidget {
  const PlanetGrid({super.key, required this.points});

  final List<Map<String, dynamic>> points;

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      for (final p in points)
        _PlanetRow(point: p),
    ]);
  }
}

class _PlanetRow extends StatelessWidget {
  const _PlanetRow({required this.point});

  final Map<String, dynamic> point;

  @override
  Widget build(BuildContext context) {
    final retro = point['retrograde'] == true;
    final derece = (point['position'] as num?)?.toDouble();
    final ev = point['house_no'] as int?;
    final l10n = AppLocalizations.of(context);

    // Alt satır: derece · ev — ikisi de zaten hesaplanıyordu ama hiç
    // gösterilmiyordu ("bu konumlar ne demek" şikâyetinin yarısı buydu).
    // Retro başlıkta ℞ ile (klasik sembol); ne demek olduğu detayda.
    // Saatsiz doğumda Ay BELİRSİZ (1.7.0): Yükselen hiç üretilmiyor ama
    // Ay öğle dolgusuyla hesaplanıyordu ve "senin Ay'ın" diye
    // duruyordu. Ay günde ~13° yol alır; ölçüldü — 16 tarihin 7'sinde
    // gün içinde burç değişiyor. Artık sunucu işaretliyor, ekran söylüyor.
    final belirsiz = point['uncertain'] == true;
    final altBurc = point['sign_alt'] as String?;

    final altSatir = [
      if (derece != null) '${derece.toStringAsFixed(1)}°',
      if (ev != null) l10n.houseN(ev),
    ].join(' · ');

    return Pressable(
      onTap: () => showPointSheet(context, point),
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 3),
        padding: const EdgeInsets.symmetric(
            horizontal: RythoSpace.md, vertical: 9),
        decoration: BoxDecoration(
          color: RythoColors.inkLighter,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
              color: retro
                  ? RythoColors.magenta.withValues(alpha: 0.4)
                  : RythoColors.glassStroke),
        ),
        child: Row(children: [
          Text(
              _kPlanetEmojis[point['name']] ??
                  _kExtraEmojis[point['name']] ??
                  '•',
              style: const TextStyle(fontSize: 15)),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${planetSignLabel(context, point)} '
                    '${_signGlyph(point)}${retro ? ' ℞' : ''}'
                    '${belirsiz ? ' ~' : ''}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: RythoText.body(13.5, w: FontWeight.w600),
                  ),
                  if (altSatir.isNotEmpty)
                    Text(altSatir,
                        style: RythoText.mono(10.5,
                            color: RythoColors.parchmentDim)),
                  // Belirsizlik SATIRDA da görünür: detay sayfasına
                  // dokunmayan kullanıcı da uyarıyı görmeli.
                  if (belirsiz)
                    Text(
                      // `sign_alt` sunucudan burç KODU olarak gelir
                      // ("Vir"); dile çeviren tablo `_kSignCodeIndex`.
                      _kSignCodeIndex[altBurc] != null
                          ? l10n.moonUncertainAlt(signDisplayName(
                              l10n, _kSignCodeIndex[altBurc]!))
                          : l10n.moonUncertainNote,
                      style: RythoText.body(10.5,
                          color: RythoColors.copper, height: 1.35),
                    ),
                ]),
          ),
          const Icon(Icons.chevron_right,
              size: 16, color: RythoColors.parchmentDim),
        ]),
      ),
    );
  }
}

/// Gezegen detay sayfası: ANLAM önce, ölçüm sonra.
///
/// Sıra bu turda TERSİNE çevrildi. Eski hâlde sayfa derece/ev/hız
/// satırlarıyla açılıyordu ve anlam cümleleri en altta duruyordu; sahibin
/// tarifi "kullanıcılar çamaşır makinesi kılavuzu muamelesi yapıyor"du.
/// Artık `basis_sheet` deseniyle aynı: önce insan cümlesi, sonra "Neye
/// dayanıyor?" başlığı altında ölçüm.
///
/// ⚠️ Eski dipnot (`pointSheetFootnote`) bu sayfada YAPILMAYAN bir şeyi
/// beyan ediyordu — ölçülen metni birebir şu: "Üstteki satırlar ölçümdür.
/// Altındaki iki cümle, o gezegenin klasik anlamı ile bulunduğu ev
/// alanını birleştirir…". İki cümle hiçbir zaman birleştirilmiyordu, yan
/// yana basılıyordu; yani kusur "biliyor ama göstermiyor" değil, YANLIŞ
/// BEYAN'dı. (Bu doktrinin ilk yazımında dipnot "bu satırlar ölçümdür,
/// kendisi yorum değildir" diye alıntılanmıştı — o cümle depoda hiç
/// olmadı; `git log -S` tek ekleme gösteriyor. Yanlış gerekçe kusurdur.)
/// Dipnot artık basılmıyor, çünkü konum beyanı da geçersizleşti; yerine
/// geçecek anahtar metni raporda önerildi, l10n paylaşımlı durum.
///
/// Açıklama SABİT TABLODAN gelir (gezegenin doğası × evin alanı) — LLM
/// yok, jeton yok. Uydurma da yok: cümle ölçülen yerleşimi anlatır.
Future<void> showPointSheet(
    BuildContext context, Map<String, dynamic> point) {
  return showModalBottomSheet<void>(
    context: context,
    // Gövde KAYDIRILABİLİR olmak zorunda: anlam katmanı eklenince sayfa
    // bir satır uzadı ve kaydırmasız gövdede içerik SESSİZCE kırpılıyordu
    // — dar ekranda alttaki ölçüm satırları hiç görünmezdi.
    //
    // ÖLÇÜLDÜ (doğrulama turu, 320×480, Ay · 1. ev · retro, yazı ölçeği
    // 1.0): sarmalayıcı olmadan taşma 131 px. Bu dosyanın ilk yazımında
    // "28 px" yazıyordu; o sayı hiçbir senaryoda ölçülmedi, düzeltildi.
    //
    // ⚠️ Kırpılmayı önleyen şey aşağıdaki `SingleChildScrollView`;
    // `isScrollControlled` ayrı bir şey yapıyor: sayfanın varsayılan
    // 9/16 tavanını kaldırıyor, yani içerik yarım sayfaya sıkışmak
    // yerine ekranı kullanıyor. Ölçüldü: sarmalayıcı dururken bunu
    // `false` yapmak hiçbir taşma üretmiyor (bekçi haklı olarak yeşil
    // kalır) — yani bu satır KONFOR, kapı değil.
    isScrollControlled: true,
    backgroundColor: RythoColors.inkLight,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      side: BorderSide(color: RythoColors.glassStroke),
    ),
    // Kaydırma SARMALAYICIDA, sayfanın gövdesinde değil: gövde
    // `mainAxisSize.min` bir Column ve içerik ekrandan uzun olduğunda
    // taşıyor. Sarmalayıcı hem içerik kadar yükseklik verir hem taşarsa
    // kaydırır.
    builder: (_) => SingleChildScrollView(child: _PointSheet(point: point)),
  );
}

class _PointSheet extends StatelessWidget {
  const _PointSheet({required this.point});

  final Map<String, dynamic> point;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final ev = point['house_no'] as int?;
    final derece = (point['position'] as num?)?.toDouble();
    final hiz = (point['speed'] as num?)?.toDouble();
    // Saatsiz haritada `house_no` yok; `yerlesimCumlesi` o durumda yalnız
    // gezegen cümlesini döner — uydurulmuş bir ev alanı eklenmez.
    final anlam = yerlesimCumlesi(l10n, point['name'] as String?, ev);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
            RythoSpace.lg, RythoSpace.md, RythoSpace.lg, RythoSpace.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _SheetTutamak(),
            const SizedBox(height: RythoSpace.md),
            Text(
                '${planetSignLabel(context, point)} ${_signGlyph(point)}',
                style: RythoText.display(17, w: FontWeight.w600)),
            const SizedBox(height: RythoSpace.md),
            // ANLAM KATMANI — başlıktan sonra ilk gelen şey burada.
            if (anlam != null)
              Text(anlam, style: RythoText.body(14, height: 1.5)),
            if (point['retrograde'] == true) ...[
              const SizedBox(height: 6),
              Text(l10n.retrogradeMeaning,
                  style: RythoText.body(13.5,
                      color: RythoColors.copper, height: 1.45)),
            ],
            const SizedBox(height: RythoSpace.md),
            // DAYANAK — ölçüm artık anlamın ALTINDA ve kendi başlığı var.
            const _DayanakBasligi(),
            if (derece != null)
              _OlcumSatiri(
                  etiket: l10n.planetDegree,
                  deger: '${derece.toStringAsFixed(2)}°'),
            if (ev != null)
              _OlcumSatiri(etiket: l10n.planetHouse, deger: l10n.houseN(ev)),
            if (point['retrograde'] == true)
              _OlcumSatiri(
                  etiket: l10n.planetMotion,
                  deger: '℞ ${l10n.planetRetrograde}'),
            if (hiz != null)
              _OlcumSatiri(
                  etiket: l10n.planetSpeed,
                  deger: '${hiz.toStringAsFixed(3)}°/${l10n.perDay}'),
            // ⚠️ `pointSheetFootnote` BİLEREK basılmıyor: metni "üstteki
            // satırlar ölçümdür, ALTINDAKİ İKİ CÜMLE …" diyor ve bu sıra
            // artık yok (anlam üstte, tek cümle). Yanlış bir konum beyanı
            // basmak, hiç basmamaktan kötüdür — yerine geçecek anahtar
            // metni raporda önerildi, l10n bu turda paylaşımlı durum.
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Kişilik Özellikleri — ölçülen dağılım
// ---------------------------------------------------------------------------

/// Baskın element — ölçülen dağılımdan, KESİN üstünlükle. Yoksa null.
///
/// NEDEN üst düzeyde ve TEK: aynı kararı iki ekran veriyor (aşağıdaki
/// Kişilik Özellikleri ve Harita İnceleme'nin anlam katmanı). İki kopya
/// duruyordu ve doğrulama turunda ölçüldü: ikincisinin eşitlik kapısını
/// kaldırmak takımı YEŞİL bırakıyordu, yani kopyanın bekçisi yoktu.
/// `showDagilimSheet` bir tur önce aynı sebeple — "aynı sayının iki
/// farklı gerekçesi" riski — üst düzeye çıkarılmıştı; kural da öyle.
///
/// NEDEN eşitlikte null: iki element tepede eşitse bu haritanın baskın
/// elementi YOKTUR; birini seçmek ölçümün söylemediği bir şeyi söylemek
/// olurdu. Bu kapı aynı zamanda sıralamanın kararsızlığını zararsız
/// kılıyor — `List.sort` kararlı DEĞİL, ama tepedeki iki değer eşitken
/// sonuç her hâlükârda null olduğu için hangisinin önce geldiği hiçbir
/// şeyi değiştirmez. (Kapı kalkarsa sonuç sabit sıraya bağlı hâle gelir
/// ve ekran, girdi sırası değiştiğinde farklı cümle gösterebilir.)
String? baskinElement(Map<String, dynamic>? dagilim) {
  if (dagilim == null || dagilim.isEmpty) return null;
  final sirali = [
    for (final e in const ['fire', 'earth', 'air', 'water'])
      (e, (dagilim[e] as num?)?.toInt() ?? 0),
  ]..sort((x, y) => y.$2.compareTo(x.$2));
  if (sirali[0].$2 <= sirali[1].$2) return null;
  return sirali[0].$1;
}

/// Element ve nitelik dağılımı — **sunucunun kanonik sayımı**.
///
/// Eski hâli istemcide `30 + (sayım/14)*140` yüzdesi üretiyordu; bu formül
/// yalnız {30,40,50,60,70,80,90,97} verebiliyor, dört elementin toplamı
/// %260 ediyor ve sayıma Ay düğümlerini (tanım gereği zıt burçlar) katıp
/// Yükselen'i dışarıda bırakıyordu. Artık tek doğruluk kaynağı sunucu:
/// `element_distribution` / `modality_distribution` + üye listeleri.
class AtlasTraitsScreen extends StatelessWidget {
  const AtlasTraitsScreen({super.key, required this.chart});

  final Map<String, dynamic> chart;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final elementler = Map<String, dynamic>.from(
        chart['element_distribution'] as Map? ?? const {});
    final nitelikler = Map<String, dynamic>.from(
        chart['modality_distribution'] as Map? ?? const {});
    final elementUye = Map<String, dynamic>.from(
        chart['element_members'] as Map? ?? const {});
    final nitelikUye = Map<String, dynamic>.from(
        chart['modality_members'] as Map? ?? const {});
    final points = [
      for (final p in (chart['points'] as List? ?? const []))
        Map<String, dynamic>.from(p as Map),
    ];

    // Eski sunucu yanıtı (dağılımsız) gelirse ekran boş kalmasın.
    if (elementler.isEmpty) {
      return _DetayIskelet(
        title: l10n.atlasTraits,
        children: [
          GlassPanel(
            child: Text(l10n.traitsUnavailable,
                style: RythoText.body(13, color: RythoColors.parchmentDim)),
          ),
        ],
      );
    }

    final toplam = elementler.values
        .fold<int>(0, (a, b) => a + ((b as num?)?.toInt() ?? 0));

    const elementRenk = {
      'fire': RythoColors.magenta,
      'earth': RythoColors.celadon,
      'air': RythoColors.lilac,
      'water': Color(0xFF5AC8FA),
    };
    const nitelikRenk = {
      'cardinal': RythoColors.gold,
      'fixed': RythoColors.lilac,
      'mutable': RythoColors.celadon,
    };

    // Eksik element: natal prompt'un da anlamlı saydığı bir ifade —
    // eski çubuklarda %30 gösterilip görünmez oluyordu.
    final eksikler = [
      for (final e in const ['fire', 'earth', 'air', 'water'])
        if (((elementler[e] as num?)?.toInt() ?? 0) == 0) e,
    ];

    // ANLAM KATMANI: ekran artık çubuklarla değil bir cümleyle açılıyor.
    //
    // ⚠️ Baskınlık KESİN ÜSTÜNLÜK ister ve kural `baskinElement`te tek
    // yerde duruyor (bkz. oranın gerekçesi orada): eşitlikte cümle hiç
    // çizilmez — "ölçülmeyen söylenmez"in bu ekrandaki hâli.
    final baskin = baskinElement(elementler);

    return _DetayIskelet(
      title: l10n.atlasTraits,
      children: [
        if (baskin != null)
          GlassPanel(
            label: elementName(l10n, baskin),
            onTap: () => _acDagilim(
              context,
              baslik: elementName(l10n, baskin),
              aciklama: elementLine(l10n, baskin),
              klasik: temperamentLine(l10n, baskin),
              uyeler:
                  List<String>.from((elementUye[baskin] as List? ?? const [])),
              points: points,
            ),
            child: Text(elementLine(l10n, baskin),
                style: RythoText.body(14, height: 1.5)),
          ),
        GlassPanel(
          label: l10n.traitsElements,
          child: Column(children: [
            for (final e in const ['fire', 'earth', 'air', 'water'])
              _OranSatiri(
                ad: elementName(l10n, e),
                sayi: (elementler[e] as num?)?.toInt() ?? 0,
                toplam: toplam,
                renk: elementRenk[e]!,
                onTap: () => _acDagilim(
                  context,
                  baslik: elementName(l10n, e),
                  aciklama: elementLine(l10n, e),
                  klasik: temperamentLine(l10n, e),
                  uyeler: List<String>.from(
                      (elementUye[e] as List? ?? const [])),
                  points: points,
                ),
              ),
          ]),
        ),
        if (eksikler.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 2, 4, 0),
            child: Text(
                l10n.traitsMissingElement(
                    eksikler.map((e) => elementName(l10n, e)).join(', ')),
                style: RythoText.body(12, color: RythoColors.copper,
                    height: 1.45)),
          ),
        const SizedBox(height: RythoSpace.sm),
        GlassPanel(
          label: l10n.traitsModalities,
          child: Column(children: [
            for (final m in const ['cardinal', 'fixed', 'mutable'])
              _OranSatiri(
                ad: modalityName(l10n, m),
                sayi: (nitelikler[m] as num?)?.toInt() ?? 0,
                toplam: toplam,
                renk: nitelikRenk[m]!,
                onTap: () => _acDagilim(
                  context,
                  baslik: modalityName(l10n, m),
                  aciklama: modalityLine(l10n, m),
                  klasik: null,
                  uyeler: List<String>.from(
                      (nitelikUye[m] as List? ?? const [])),
                  points: points,
                ),
              ),
          ]),
        ),
        _Dipnot('${l10n.traitsSetNote}\n${l10n.traitsTapHint}'),
      ],
    );
  }

  void _acDagilim(
    BuildContext context, {
    required String baslik,
    required String aciklama,
    required String? klasik,
    required List<String> uyeler,
    required List<Map<String, dynamic>> points,
  }) =>
      showDagilimSheet(context,
          baslik: baslik,
          aciklama: aciklama,
          klasik: klasik,
          uyeler: uyeler,
          points: points);
}

/// Dağılım dayanağı alt-sayfası — "bu sayı nereden geliyor?".
///
/// Üst düzeye çıkarıldı çünkü Harita İnceleme ekranı da aynı dayanağı
/// açıyor; iki yerde iki ayrı sayfa olması, aynı sayının iki farklı
/// gerekçesi gösterilmesi riskini doğururdu.
void showDagilimSheet(
  BuildContext context, {
  required String baslik,
  required String aciklama,
  required String? klasik,
  required List<String> uyeler,
  required List<Map<String, dynamic>> points,
}) {
  showModalBottomSheet<void>(
    context: context,
    // Üye çipleri `Wrap` içinde ve sekiz nokta dar ekranda üç satıra
    // çıkabiliyor; bu sayfa artık Harita İnceleme'den de açıldığı için
    // kırpılma riski ölçülmeden bırakılmadı (bkz. `showPointSheet`).
    // ÖLÇÜLDÜ (320×480, ateş · sekiz üye): sarmalayıcı olmadan taşma
    // 117 px, yazı ölçeği 1,3'te 474 px.
    isScrollControlled: true,
    backgroundColor: RythoColors.inkLight,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      side: BorderSide(color: RythoColors.glassStroke),
    ),
    builder: (_) => SingleChildScrollView(
      child: _DagilimSheet(
        baslik: baslik,
        aciklama: aciklama,
        klasik: klasik,
        uyeler: uyeler,
        points: points,
      ),
    ),
  );
}

/// "Bu sayı nereden geliyor?" — dağılımın üyeleri.
class _DagilimSheet extends StatelessWidget {
  const _DagilimSheet({
    required this.baslik,
    required this.aciklama,
    required this.klasik,
    required this.uyeler,
    required this.points,
  });

  final String baslik;
  final String aciklama;
  final String? klasik;
  final List<String> uyeler;
  final List<Map<String, dynamic>> points;

  /// Üye adını ("Sun", "Ascendant") ekranda okunur hâle getirir.
  String _uyeMetni(AppLocalizations l10n, String ad) {
    if (ad == 'Ascendant') return l10n.pointAscendant;
    for (final p in points) {
      if (p['name'] == ad) {
        final burc = (p['sign_local'] ?? p['sign_tr'] ?? '') as String;
        return burc.isEmpty
            ? _pointName(p)
            : '${_pointName(p)} · $burc';
      }
    }
    return ad;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
            RythoSpace.lg, RythoSpace.md, RythoSpace.lg, RythoSpace.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _SheetTutamak(),
            const SizedBox(height: RythoSpace.md),
            Text(l10n.traitsSheetTitle(baslik),
                style: RythoText.display(17, w: FontWeight.w600)),
            const SizedBox(height: 6),
            Text(aciklama, style: RythoText.body(13.5, height: 1.45)),
            const SizedBox(height: RythoSpace.md),
            Text(l10n.traitsMembersLabel.toUpperCase(),
                style: RythoType.dataSmall),
            const SizedBox(height: 4),
            if (uyeler.isEmpty)
              Text(l10n.traitsNoMember,
                  style: RythoText.body(13, color: RythoColors.copper))
            else
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final u in uyeler)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: RythoColors.glassFill,
                        borderRadius: BorderRadius.circular(999),
                        border:
                            Border.all(color: RythoColors.glassStroke),
                      ),
                      child: Text(_uyeMetni(l10n, u),
                          style: RythoText.body(12)),
                    ),
                ],
              ),
            if (klasik != null) ...[
              const SizedBox(height: RythoSpace.md),
              Text(klasik!,
                  style: RythoText.body(12.5,
                      color: RythoColors.parchmentDim, height: 1.45)),
            ],
            const SizedBox(height: RythoSpace.md),
            Text(l10n.traitsSheetFootnote,
                style: RythoText.body(11,
                    color: RythoColors.parchmentDim, height: 1.4)),
          ],
        ),
      ),
    );
  }
}

/// Oran satırı — "3/8" + orantılı çubuk. Yüzde YOK: dört elementin
/// yüzdesi toplamda 100 etmez, kesir dürüst olan biçim.
class _OranSatiri extends StatelessWidget {
  const _OranSatiri({
    required this.ad,
    required this.sayi,
    required this.toplam,
    required this.renk,
    required this.onTap,
  });

  final String ad;
  final int sayi;
  final int toplam;
  final Color renk;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final oran = toplam == 0 ? 0.0 : sayi / toplam;
    return Pressable(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Column(children: [
          Row(children: [
            Expanded(
                child: Text(ad,
                    style: RythoText.body(14, w: FontWeight.w600))),
            Text('$sayi/$toplam',
                style: RythoText.mono(12.5, color: renk)),
            const SizedBox(width: 6),
            const Icon(Icons.chevron_right,
                size: 15, color: RythoColors.parchmentDim),
          ]),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: oran,
              minHeight: 7,
              backgroundColor: RythoColors.inkLighter,
              valueColor: AlwaysStoppedAnimation(renk),
            ),
          ),
        ]),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Açılar
// ---------------------------------------------------------------------------

/// Açı türü -> grup anahtarı. Sinyal kartlarındaki ton diliyle aynı.
const _kAspectGroup = {
  'conjunction': 'focus',
  'opposition': 'tension',
  'square': 'tension',
  'trine': 'flow',
  'sextile': 'flow',
};

class AtlasAspectsScreen extends StatelessWidget {
  const AtlasAspectsScreen({super.key, required this.aspects});

  final List<Map<String, dynamic>> aspects;

  double _orb(Map<String, dynamic> a) =>
      ((a['orbit'] as num?)?.toDouble() ?? 99).abs();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    // Gruplama + sıralama: eskiden motor sırası aynen basılıyordu.
    // En dar orb en güçlü açıdır; listenin başında durmalı.
    final gruplar = <String, List<Map<String, dynamic>>>{
      'tension': [], 'flow': [], 'focus': [], 'other': [],
    };
    for (final a in aspects) {
      final grup = _kAspectGroup[a['aspect']] ?? 'other';
      gruplar[grup]!.add(a);
    }
    for (final liste in gruplar.values) {
      liste.sort((x, y) => _orb(x).compareTo(_orb(y)));
    }

    // ANLAM KATMANI: ekran artık ızgarayla değil bir cümleyle açılıyor.
    //
    // "En dar açı" seçimi keyfî değil — ekranın kendi dipnotu
    // (`aspectsSortNote`) orb ne kadar darsa açının o kadar güçlü
    // olduğunu zaten BEYAN ediyor. Yani liderlik ölçülen bir sıradan
    // geliyor, seçilmiş bir örnekten değil; ve harita başına değiştiği
    // için iki kullanıcı aynı cümleyi görmüyor. Orbu olmayan açı lider
    // OLAMAZ: `_orb` onlara 99 veriyor, yani gerçek ölçümlerin arkasına
    // düşerler ve yalnız başka hiç açı yoksa öne geçerler.
    final siraliTum = [...aspects]
      ..sort((x, y) => _orb(x).compareTo(_orb(y)));
    final lider = siraliTum.isEmpty ? null : siraliTum.first;
    final liderAnlam = lider == null
        ? null
        : aspectMeaningText(l10n, lider['aspect'] as String?);

    Widget bolum(String anahtar, String baslik) {
      final liste = gruplar[anahtar]!;
      if (liste.isEmpty) return const SizedBox.shrink();
      return GlassPanel(
        label: baslik,
        child: Column(children: [
          for (final a in liste) _AspectRow(aspect: a),
        ]),
      );
    }

    return _DetayIskelet(
      title: l10n.atlasAspects,
      children: [
        if (lider != null && liderAnlam != null)
          GlassPanel(
            label: aspectPairLabel(context, lider),
            onTap: () => showAspectSheet(context, lider),
            child: Text(liderAnlam, style: RythoText.body(14, height: 1.5)),
          ),
        bolum('tension', l10n.aspectsGroupTension),
        bolum('focus', l10n.aspectsGroupFocus),
        bolum('flow', l10n.aspectsGroupFlow),
        bolum('other', l10n.aspectsGroupOther),
        _Dipnot('${l10n.aspectsSortNote}\n${l10n.traitsTapHint}'),
      ],
    );
  }
}

class _AspectRow extends StatelessWidget {
  const _AspectRow({required this.aspect});

  final Map<String, dynamic> aspect;

  @override
  Widget build(BuildContext context) {
    // Korumasız `as num` cast'i çöküyordu (orb eksikse ekran kapanıyordu).
    final orb = (aspect['orbit'] as num?)?.toDouble();
    final hareket = aspect['movement_local'] as String?;

    return Pressable(
      onTap: () => showAspectSheet(context, aspect),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(children: [
          Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(aspectPairLabel(context, aspect),
                      style: RythoType.body),
                  if (hareket != null)
                    Text(hareket,
                        style: RythoText.body(10.5,
                            color: RythoColors.parchmentDim)),
                ]),
          ),
          // Açı türü adı ("Karşıtlık", "Üçgen") dile bağlı ve esnemiyordu;
          // soldaki `Expanded` sıfıra inse bile bu metin + orb + chevron
          // dar ekranda taşıyordu. `Flexible` metnin sarmasına izin verir.
          Flexible(
            child: Text(aspectKindLabel(context, aspect),
                style: RythoType.bodyDim),
          ),
          const SizedBox(width: RythoSpace.md),
          Text(orb == null ? '—' : '${orb.toStringAsFixed(1)}°',
              style: RythoType.dataSmall),
          const SizedBox(width: 4),
          const Icon(Icons.chevron_right,
              size: 15, color: RythoColors.parchmentDim),
        ]),
      ),
    );
  }
}

Future<void> showAspectSheet(
    BuildContext context, Map<String, dynamic> aspect) {
  return showModalBottomSheet<void>(
    context: context,
    // Bkz. `showPointSheet`. ⚠️ Bu sayfanın gerekçesi oradakiyle AYNI
    // DEĞİL ve ilk yazımında öyle sanılmıştı: 320×480'de yazı ölçeği
    // 1.0 iken bu sayfa HİÇ taşmıyor (beş açı türü × iki hareket,
    // hepsi 0 px — ölçüldü). Taşma uygulamanın kendi yazı ölçeği
    // tavanında başlıyor (`kMaxTextScale` = 1,3): ölçülen 141–247 px,
    // türe ve harekete göre (en azı Üçgen·ayrılan, en çoğu
    // Kavuşum·yaklaşan).
    //
    // ⚠️ Bu aralık bir tur "200–279 px" yazıyordu ve YENİDEN ÖLÇÜLDÜ:
    // on senaryonun yedisi 200'ün ALTINDA ve 279 px hiç görülmedi.
    // Ölçüm yöntemi de kusurluydu — `RenderFlex` taşmayı render nesnesi
    // BAŞINA BİR KEZ bildiriyor ve `pumpWidget` aynı widget tiplerinde
    // o nesneleri yeniden kullanıyor, yani tek testte döngüyle ölçmek
    // ilk senaryodan sonra hep "0 px" veriyor. Her senaryo AYRI test
    // olmak zorunda.
    // Yani sarmalayıcı burada BÜYÜK YAZI için duruyor; bekçisi de o
    // ölçekte koşmak zorunda, 1.0'da kör kalır.
    isScrollControlled: true,
    backgroundColor: RythoColors.inkLight,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      side: BorderSide(color: RythoColors.glassStroke),
    ),
    builder: (_) =>
        SingleChildScrollView(child: _AspectSheet(aspect: aspect)),
  );
}

class _AspectSheet extends StatelessWidget {
  const _AspectSheet({required this.aspect});

  final Map<String, dynamic> aspect;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final orb = (aspect['orbit'] as num?)?.toDouble();
    final aciklama = aspectMeaningText(l10n, aspect['aspect'] as String?);
    final hareketAciklama =
        movementMeaningText(l10n, aspect['movement'] as String?);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
            RythoSpace.lg, RythoSpace.md, RythoSpace.lg, RythoSpace.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _SheetTutamak(),
            const SizedBox(height: RythoSpace.md),
            Text(aspectPairLabel(context, aspect),
                style: RythoText.display(17, w: FontWeight.w600)),
            const SizedBox(height: RythoSpace.md),
            // ANLAM KATMANI — eskiden bu blok orb satırlarının ALTINDAYDI.
            if (aciklama != null)
              Text(aciklama, style: RythoText.body(14, height: 1.5)),
            if (hareketAciklama != null) ...[
              const SizedBox(height: 6),
              Text(hareketAciklama,
                  style: RythoText.body(13.5, height: 1.45)),
            ],
            const SizedBox(height: RythoSpace.md),
            // DAYANAK
            const _DayanakBasligi(),
            _OlcumSatiri(
                etiket: l10n.basisAspect,
                deger: aspectKindLabel(context, aspect)),
            if (orb != null)
              _OlcumSatiri(
                  etiket: l10n.basisOrb,
                  deger: '${orb.toStringAsFixed(2)}°'),
            if (aspect['movement_local'] != null)
              _OlcumSatiri(
                  etiket: l10n.basisMovement,
                  deger: aspect['movement_local'] as String),
            const SizedBox(height: RythoSpace.md),
            // Bu dipnot KALDI çünkü konumdan bağımsız: "açı ve orb
            // ölçülür; açıklama klasik yorum geleneğidir" sıra değişince
            // de doğru kalıyor (`pointSheetFootnote` kalmadı, o konum
            // beyanı taşıyor).
            Text(l10n.aspectSheetFootnote,
                style: RythoText.body(11,
                    color: RythoColors.parchmentDim, height: 1.4)),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Ortak küçük parçalar
// ---------------------------------------------------------------------------

class _SheetTutamak extends StatelessWidget {
  const _SheetTutamak();

  @override
  Widget build(BuildContext context) => Center(
        child: Container(
          width: 36,
          height: 4,
          decoration: BoxDecoration(
            color: RythoColors.glassStroke,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      );
}

/// Ölçüm bloğunun başlığı — "Neye dayanıyor?".
///
/// NEDEN ayrı widget: aynı başlık iki alt-sayfada ve harita inceleme
/// ekranında birden kullanılıyor; anlam ile ölçümü ayıran çizgi tek
/// yerden gelsin. `signalWhy` anahtarı sinyal kartlarından geliyor ama
/// metni ("Neye dayanıyor?" / "What's behind this?") sinyale ÖZEL DEĞİL —
/// yeni bir anahtar uydurmak yerine bu kullanıldı.
class _DayanakBasligi extends StatelessWidget {
  const _DayanakBasligi();

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 2),
        child: Text(AppLocalizations.of(context).signalWhy.toUpperCase(),
            style: RythoType.dataSmall),
      );
}

/// Etiket + değer satırı (basis_sheet ile aynı görsel dil).
class _OlcumSatiri extends StatelessWidget {
  const _OlcumSatiri({required this.etiket, required this.deger});

  final String etiket;
  final String deger;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(
            width: 108,
            child: Text(etiket.toUpperCase(), style: RythoType.dataSmall),
          ),
          const SizedBox(width: RythoSpace.sm),
          Expanded(child: Text(deger, style: RythoText.body(13.5))),
        ]),
      );
}

// ---------------------------------------------------------------------------
// Metin tabloları — hepsi SABİT, LLM yok
// ---------------------------------------------------------------------------

String elementName(AppLocalizations l10n, String key) => switch (key) {
      'fire' => l10n.elementFire,
      'earth' => l10n.elementEarth,
      'air' => l10n.elementAir,
      'water' => l10n.elementWater,
      _ => key,
    };

String elementLine(AppLocalizations l10n, String key) => switch (key) {
      'fire' => l10n.elementFireLine,
      'earth' => l10n.elementEarthLine,
      'air' => l10n.elementAirLine,
      'water' => l10n.elementWaterLine,
      _ => '',
    };

/// Klasik mizaç karşılığı — ölçülen element dağılımının geleneksel adı.
String temperamentLine(AppLocalizations l10n, String key) => switch (key) {
      'fire' => l10n.temperamentFire,
      'earth' => l10n.temperamentEarth,
      'air' => l10n.temperamentAir,
      'water' => l10n.temperamentWater,
      _ => '',
    };

String modalityName(AppLocalizations l10n, String key) => switch (key) {
      'cardinal' => l10n.modalityCardinal,
      'fixed' => l10n.modalityFixed,
      'mutable' => l10n.modalityMutable,
      _ => key,
    };

String modalityLine(AppLocalizations l10n, String key) => switch (key) {
      'cardinal' => l10n.modalityCardinalLine,
      'fixed' => l10n.modalityFixedLine,
      'mutable' => l10n.modalityMutableLine,
      _ => '',
    };

String? planetRoleText(AppLocalizations l10n, String? name) =>
    switch (name) {
      'Sun' => l10n.roleSun,
      'Moon' => l10n.roleMoon,
      'Mercury' => l10n.roleMercury,
      'Venus' => l10n.roleVenus,
      'Mars' => l10n.roleMars,
      'Jupiter' => l10n.roleJupiter,
      'Saturn' => l10n.roleSaturn,
      'Uranus' => l10n.roleUranus,
      'Neptune' => l10n.roleNeptune,
      'Pluto' => l10n.rolePluto,
      'Chiron' => l10n.roleChiron,
      'Mean_Lilith' => l10n.roleLilith,
      'True_North_Lunar_Node' => l10n.roleNorthNode,
      'True_South_Lunar_Node' => l10n.roleSouthNode,
      _ => null,
    };

String? houseAreaText(AppLocalizations l10n, int house) => switch (house) {
      1 => l10n.house1,
      2 => l10n.house2,
      3 => l10n.house3,
      4 => l10n.house4,
      5 => l10n.house5,
      6 => l10n.house6,
      7 => l10n.house7,
      8 => l10n.house8,
      9 => l10n.house9,
      10 => l10n.house10,
      11 => l10n.house11,
      12 => l10n.house12,
      _ => null,
    };

/// `<Etiket>: <gövde>.` kalıbını ikiye böler.
///
/// İki metin tablosunun da (`planetRoleText`, `houseAreaText`) sözleşmesi
/// bu kalıp ve TR ile EN'de birebir aynı. Ayırıcı ASCII iki nokta, yani
/// Türkçe harf tuzağı YOK: hiçbir yerde `toLowerCase` çağrılmıyor
/// (`"İ".toLowerCase()` iki kod noktasına açılır) ve alt dize araması
/// yapılmıyor. İki nokta bulunmazsa etiket boş döner ve dize OLDUĞU GİBİ
/// gövde sayılır — bir çeviri kalıbı bırakırsa kırık parça basmaktansa tam
/// cümle basılsın.
({String etiket, String govde}) _ikiyeBol(String cumle) {
  final i = cumle.indexOf(':');
  final govdeHam = i < 0 ? cumle : cumle.substring(i + 1);
  final govde = govdeHam.trim();
  return (
    etiket: i < 0 ? '' : cumle.substring(0, i).trim(),
    govde: govde.endsWith('.')
        ? govde.substring(0, govde.length - 1)
        : govde,
  );
}

/// Yerleşim cümlesi: gezegenin klasik anlamı × bulunduğu evin alanı, TEK
/// cümlede.
///
/// NEDEN birleştirme: eski hâl iki tablo cümlesini YAN YANA basıyordu
/// ("Mars: …" ve altına "6. ev: …"). 14 gezegen metni ile 12 ev metni
/// ikişer ikişer seçildiği için 168 yerleşimin tamamı 26 dizeden iki
/// tanesiyle anlatılıyordu: teknik bilgi ÇARPILMIYOR, TOPLANIYORDU. İki
/// farklı kullanıcı aynı iki ansiklopedi maddesini yan yana görüyor ve
/// jeneriklik hissinin kaynağı buydu. Birleştirme 168 ayrı cümle üretir ve
/// YENİ bir sabit cümle tablosu DOĞURMAZ — tek bir dilbilgisel birleşme
/// var, tablo yok.
///
/// Etiket solda bir kez durur: alt-sayfanın başlığı zaten "Mars — Başak"
/// yazıyor, cümlenin de "Mars:" diye başlaması aynı adın üçüncü tekrarıydı.
///
/// ⚠️ EKSİK KALAN: "şu yetenek şu alanda İŞLER" ilişkisini kuran bir
/// bağlaç (TR "… alanında işler", EN "… at work in …") yeni bir l10n
/// anahtarı ister; l10n bu turda paylaşımlı durum olduğu için
/// birleştirme noktalama düzeyinde kaldı. Anahtar önerisi raporda.
String? yerlesimCumlesi(AppLocalizations l10n, String? name, int? house) {
  final rol = planetRoleText(l10n, name);
  final alan = house == null ? null : houseAreaText(l10n, house);
  if (rol == null) return alan;
  if (alan == null) return rol;
  final r = _ikiyeBol(rol);
  final a = _ikiyeBol(alan);
  final etiket =
      [r.etiket, a.etiket].where((e) => e.isNotEmpty).join(' · ');
  final govde = [r.govde, a.govde].where((g) => g.isNotEmpty).join('; ');
  return etiket.isEmpty ? '$govde.' : '$etiket — $govde.';
}

String? aspectMeaningText(AppLocalizations l10n, String? key) =>
    switch (key) {
      'conjunction' => l10n.aspectMeaningConjunction,
      'opposition' => l10n.aspectMeaningOpposition,
      'square' => l10n.aspectMeaningSquare,
      'trine' => l10n.aspectMeaningTrine,
      'sextile' => l10n.aspectMeaningSextile,
      _ => null,
    };

String? movementMeaningText(AppLocalizations l10n, String? key) =>
    switch (key) {
      'applying' => l10n.movementMeaningApplying,
      'separating' => l10n.movementMeaningSeparating,
      _ => null,
    };
