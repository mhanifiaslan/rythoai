/// Harita İnceleme (HI-turu HA7) — astrolog gözü için tam ekran çark.
///
/// Dört kip tek ekranda: natal | gökyüzü | bi-wheel | sinastri (Çevrem).
/// İçerik: anlam cümlesi, veri başlığı (ad/tarih/ev sistemi — güven, ev
/// sistemini görmekle başlar), etkileşimli çark (dokun→seç/izole, tekrar
/// dokun→alt-sayfa, pinch-zoom), seçim çubuğu, lejant (halka + açı sınıfı
/// çizgi dili), filtre çipleri + orb kaydırıcısı, açı tablosu (aspectarian:
/// tekilde üçgen, sinastride TAM dikdörtgen), konum tablosu (erişilebilir
/// temsil), en altta "Rytho'ya sor"; PNG paylaşım AppBar'da (tek beyanlı
/// istisna — çark görüntüsü okumanın altına inmez).
///
/// "Ölçülmeyen söylenmez": saatsiz haritada evler/eksenler çizilmez ve
/// beyan görünür; transit gezegene ev iddia edilmez; arkadaş sinastri
/// çarkı bilinçli yok (kullanıcı kararı — Çevrem v1).
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api.dart' show friendlyError;
import '../../core/people.dart';
import '../../core/providers.dart';
import '../../l10n/app_localizations.dart';
import '../../theme/rytho_theme.dart';
import '../../theme/rytho_tokens.dart';
import '../../widgets/atlas_widgets.dart' show RythoyaSor;
import '../../widgets/chart/aci_lejanti.dart';
import '../../widgets/chart/chart_data.dart';
import '../../widgets/chart/chart_palette.dart';
import '../../widgets/chart/chart_positions.dart';
import '../../widgets/chart/chart_wheel.dart';
import '../../widgets/chart/wheel_glyphs.dart';
import '../../widgets/chart/wheel_layout.dart';
import '../../widgets/chart/wheel_painter.dart';
import '../../widgets/common.dart' show ErrorCard;
import '../../widgets/cosmic_scaffold.dart';
import '../../widgets/glass.dart';
import '../../widgets/motion.dart' show StagedWaiting;
import '../../widgets/nebula_widgets.dart' show kSignNamesTr;
import '../chat/chat_screen.dart';
import '../people/person_form_screen.dart' show relationLabel;
import '../share/share_card.dart' show shareChartCard;
import 'atlas_detail_screens.dart'
    show
        aspectMeaningText,
        baskinElement,
        elementLine,
        elementName,
        showAspectSheet,
        showDagilimSheet,
        showPointSheet,
        temperamentLine;

enum ChartInspectorMode { natal, sky, biwheel, synastry }

/// Tam ekran çarkın üst tavanı: daha büyüğü tablet genişliğinde glifleri
/// seyreltiyor, parmak hedefleri zaten 22 px yarıçapta.
const double kCarkTavani = 460.0;

/// [ChartPoint] → mevcut `showPointSheet` yükü (atlas alt-sayfa ailesi
/// `sign_tr`/`name_tr` alanlarını okur — planetSignLabel sözleşmesi).
Map<String, dynamic> pointSheetMap(ChartPoint p) => {
      'name': p.name,
      'name_tr': p.localName,
      'name_local': p.localName,
      'sign': kSignCodes[p.signIndex],
      'sign_tr': kSignNamesTr[p.signIndex],
      'position': p.degreeInSign,
      'abs_position': p.absPosition,
      'house_no': p.houseNo,
      'retrograde': p.retrograde,
      'speed': p.speed,
    };

/// [ChartAspect] → mevcut `showAspectSheet` yükü.
Map<String, dynamic> aspectSheetMap(ChartAspect a) => {
      'p1': a.p1,
      'p2': a.p2,
      'p1_tr': a.p1Local,
      'p2_tr': a.p2Local,
      'aspect': a.kind,
      'aspect_tr': a.kindLocal,
      'orbit': a.orb,
      if (a.applying != null)
        'movement': a.applying! ? 'applying' : 'separating',
    };

class ChartInspectorScreen extends ConsumerStatefulWidget {
  const ChartInspectorScreen({
    super.key,
    required this.mode,
    this.person,
    this.natalOverride,
    this.titleOverride,
  });

  final ChartInspectorMode mode;

  /// Sinastri kipinde zorunlu; natal kipinde doluysa KİŞİNİN haritası
  /// incelenir (kendi haritası yerine).
  final Person? person;

  /// Kişi detayından gelen hazır natal yükü (yeniden istek atılmaz).
  final Map<String, dynamic>? natalOverride;

  final String? titleOverride;

  @override
  ConsumerState<ChartInspectorScreen> createState() =>
      _ChartInspectorScreenState();
}

class _ChartInspectorScreenState
    extends ConsumerState<ChartInspectorScreen> {
  late WheelAspectFilter _filter = switch (widget.mode) {
    // Karar 3: natal/gökyüzünde Tümü, çift halkalılarda Majör.
    ChartInspectorMode.biwheel ||
    ChartInspectorMode.synastry =>
      WheelAspectFilter.major,
    _ => WheelAspectFilter.all,
  };
  late double _maxOrb = switch (widget.mode) {
    ChartInspectorMode.biwheel => 3.0,
    ChartInspectorMode.synastry => 4.0,
    _ => 8.0,
  };
  bool _showMinors = false;
  bool _housesInner = true; // sinastri: evler A(sen)/B(kişi)
  WheelSelection _selection = WheelSelection.none;

  // ---------------------------------------------------------------------
  // Veri kurulumu
  // ---------------------------------------------------------------------

  /// (veri, yükleniyor-mu, hata). Yükleniyorsa bi-wheel SESSİZCE tek
  /// halkaya düşmez (eski atlas kusuru) — bekleme durumu gösterilir.
  ///
  /// Hata nesnesi de TAŞINIR: eski üçlü yalnız `value == null`a bakıyor,
  /// sağlayıcının hatasını DÜŞÜRÜYOR ve ekran boş bir gövdeyle
  /// (`SizedBox.shrink`) açılıyordu — hata ≠ boş. Gövde artık
  /// `ErrorCard(onRetry)`; mesaj `friendlyError` ile sağlayıcının kendi
  /// hatasından, hata nesnesi yoksa (profil tamamlanmamış, yük null) genel
  /// cümleden gelir.
  (ChartData?, bool, Object?) _buildData(AppLocalizations l10n) {
    final sen = l10n.chartLegendYou;
    switch (widget.mode) {
      case ChartInspectorMode.natal:
        if (widget.natalOverride != null) {
          return (
            ChartData.fromNatal(widget.natalOverride!, label: _personAd()),
            false,
            null
          );
        }
        final natal = ref.watch(natalChartProvider);
        if (natal.isLoading) return (null, true, null);
        final veri = natal.value;
        return (
          veri == null ? null : ChartData.fromNatal(veri, label: sen),
          false,
          natal.error
        );
      case ChartInspectorMode.sky:
        final sky = ref.watch(skyNowProvider);
        if (sky.isLoading) return (null, true, null);
        final veri = sky.value;
        return (
          veri == null
              ? null
              : ChartData.fromSky(veri, label: l10n.chartLegendSkyNow),
          false,
          sky.error
        );
      case ChartInspectorMode.biwheel:
        final natal = ref.watch(natalChartProvider);
        final transits = ref.watch(transitsProvider);
        if (natal.isLoading || transits.isLoading) return (null, true, null);
        if (natal.value == null || transits.value == null) {
          return (null, false, natal.error ?? transits.error);
        }
        return (
          ChartData.fromTransits(natal.value!, transits.value!,
              innerLabel: sen, outerLabel: l10n.chartLegendSkyNow),
          false,
          null
        );
      case ChartInspectorMode.synastry:
        final synastry =
            ref.watch(synastryChartProvider(widget.person!));
        if (synastry.isLoading) return (null, true, null);
        if (synastry.value == null) return (null, false, synastry.error);
        return (
          ChartData.fromSynastry(synastry.value!,
              innerLabel: sen,
              outerLabel: _personAd(),
              useInnerHouses: _housesInner),
          false,
          null
        );
    }
  }

  /// Hata kartının "tekrar dene"si: kipin okuduğu sağlayıcı(lar) tazelenir.
  void _tekrarDene() {
    switch (widget.mode) {
      case ChartInspectorMode.natal:
        ref.invalidate(natalChartProvider);
      case ChartInspectorMode.sky:
        ref.invalidate(skyNowProvider);
      case ChartInspectorMode.biwheel:
        ref.invalidate(natalChartProvider);
        ref.invalidate(transitsProvider);
      case ChartInspectorMode.synastry:
        ref.invalidate(synastryChartProvider(widget.person!));
    }
  }

  /// Natal kipin HAM yükü — anlam katmanı sunucunun kanonik element
  /// sayımını buradan okur.
  ///
  /// `ChartData` yalnız çizim için normalize ediliyor (nokta, ev, açı);
  /// dağılım sayımı orada YOK ve istemcide yeniden sayılMAZ — eski
  /// `TraitBars` tam bunu yapıp kanondan sapan ikinci bir hesap
  /// üretmişti.
  ///
  /// Kip kapısı bu metotta DEĞİL, `natalAnlamYuku`da: bu ekranın widget
  /// testi Firebase/profil sağlayıcılarını ister, yani kapı burada
  /// kalırsa davranış olarak çivilenemez. Doğrulama turunda ölçüldü —
  /// kapı buradan silindiğinde takım YEŞİL kalıyordu.
  Map<String, dynamic>? _natalYuk() => natalAnlamYuku(
        widget.mode,
        override: widget.natalOverride,
        // TEMBEL: sağlayıcı yalnız kapı geçilirse okunur. Doğrudan
        // `ref.watch(...)` yazılsa gökyüzü/sinastri kipi de natal
        // haritaya ABONE olurdu — kullanmadığı bir isteği doğurur.
        saglayici: () => ref.watch(natalChartProvider).value,
      );

  String _personAd() {
    final l10n = AppLocalizations.of(context);
    final p = widget.person;
    if (p == null) return '';
    return p.label ?? relationLabel(l10n, p.relation);
  }

  String _baslik(AppLocalizations l10n) {
    if (widget.titleOverride != null) return widget.titleOverride!;
    return switch (widget.mode) {
      ChartInspectorMode.natal => l10n.atlasWheelNatal,
      ChartInspectorMode.sky => l10n.atlasWheelSky,
      ChartInspectorMode.biwheel => l10n.atlasWheelBiwheel,
      ChartInspectorMode.synastry =>
        l10n.chartModeSynastry(_personAd()),
    };
  }

  /// Bekleme aşaması: dış halka yalnız çift halkalı kiplerde var.
  /// Natal/gökyüzü "Dış halka yükleniyor…" diyordu — olmayan bir şeyin
  /// beklendiğini beyan ediyordu (ölçüldü, app_tr.arb `chartOuterLoading`).
  String _beklemeMetni(AppLocalizations l10n) => switch (widget.mode) {
        ChartInspectorMode.biwheel ||
        ChartInspectorMode.synastry =>
          l10n.chartOuterLoading,
        _ => l10n.chartLoading,
      };

  // ---------------------------------------------------------------------
  // Etkileşim
  // ---------------------------------------------------------------------

  void _onPlanetTap(GlyphPlacement g) {
    final ayni = _selection.pointName == g.point.name &&
        _selection.pointRing == g.ring;
    if (ayni) {
      // İkinci dokunuş: ortak alt-sayfa ailesi (atlas listeleriyle aynı).
      showPointSheet(context, _pointAsMap(g.point));
      return;
    }
    setState(() => _selection =
        WheelSelection(pointName: g.point.name, pointRing: g.ring));
  }

  void _onAspectTap(ChartAspect a) {
    final ayni = _selection.aspect?.p1 == a.p1 &&
        _selection.aspect?.p2 == a.p2 &&
        _selection.aspect?.kind == a.kind;
    if (ayni) {
      showAspectSheet(context, _aspectAsMap(a));
      return;
    }
    setState(() => _selection = WheelSelection(aspect: a));
  }

  Map<String, dynamic> _pointAsMap(ChartPoint p) => pointSheetMap(p);

  Map<String, dynamic> _aspectAsMap(ChartAspect a) => aspectSheetMap(a);

  /// Sohbet tohumu kip başına ayrı anahtar: tek anahtar `{title}` ile
  /// "Şu an **Şu an gökyüzü** çarkını" ve "Şu an **Sen & Ayşe** çarkını"
  /// üretiyordu (ölçüldü). Kendi natal haritası için adsız anahtar
  /// `chartAskPrefillOwn` (D7): eski hâl `chartAskPrefill(atlasWheelNatal)`
  /// ile "Şu an Haritam çarkını inceliyorum" kuruyordu — kullanıcının
  /// ağzına ekran adı koyan bir cümle.
  /// Tohum ÖN-DOLDURUR, göndermez (`chat_screen.dart` doktrini).
  String _tohum(AppLocalizations l10n) => switch (widget.mode) {
        ChartInspectorMode.natal => widget.person == null
            ? l10n.chartAskPrefillOwn
            : l10n.chartAskPrefillNatal(_personAd()),
        ChartInspectorMode.sky => l10n.chartAskPrefillSky,
        ChartInspectorMode.biwheel => l10n.chartAskPrefillBiwheel,
        ChartInspectorMode.synastry =>
          l10n.chartAskPrefillSynastry(_personAd()),
      };

  void _sor(AppLocalizations l10n) {
    Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => ChatScreen(
              personId: widget.mode == ChartInspectorMode.synastry
                  ? widget.person?.id
                  : null,
              initialText: _tohum(l10n),
            )));
  }

  // ---------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final (veri, yukleniyor, hata) = _buildData(l10n);

    return CosmicScaffold(
      appBar: AppBar(
        title: Text(_baslik(l10n)),
        actions: [
          if (veri != null)
            IconButton(
              tooltip: l10n.chartShareTooltip,
              icon: const Icon(Icons.ios_share_rounded, size: 20),
              onPressed: () => shareChartCard(context,
                  data: veri,
                  title: _baslik(l10n),
                  filter: _filter,
                  maxOrb: _maxOrb,
                  showMinors: _showMinors),
            ),
        ],
      ),
      body: yukleniyor
          ? Center(child: StagedWaiting(stages: [_beklemeMetni(l10n)]))
          : veri == null
              ? Padding(
                  padding: const EdgeInsets.all(RythoSpace.xl),
                  child: ErrorCard(
                    message: hata == null
                        ? l10n.errorGeneric
                        : friendlyError(hata, l10n),
                    onRetry: _tekrarDene,
                    // Geri bildirim ekran kodu: gökyüzü kipi Gökyüzü
                    // sekmesinden, öteki üçü Atlas'tan açılır.
                    screen: widget.mode == ChartInspectorMode.sky
                        ? 'sky'
                        : 'atlas',
                  ),
                )
              // Çark boyu GERÇEK kısıttan: `MediaQuery` genişliği + 280
              // tabanı 320 dp'nin altında ve büyük yazı ölçeğinde çarkı
              // kenar dolgusuna taşırıp kırptırıyordu (ClipRect sessiz).
              : LayoutBuilder(builder: (context, kisit) {
                  final carkBoyu = math.min(
                      kisit.maxWidth - RythoSpace.xl * 2, kCarkTavani);
                  return ListView(
                    padding: const EdgeInsets.fromLTRB(RythoSpace.xl, 0,
                        RythoSpace.xl, RythoSpace.xxl),
                    children: [
                      // ANLAM ÖNCE (48-turu). Bu ekran ölçülen en kötü
                      // yüzeydi: gezegen tablosu + ev tablosu + açı
                      // ızgarası, SIFIR anlam cümlesi. Sıra artık
                      // `basis_sheet` deseniyle aynı — önce bir insan
                      // cümlesi, sonra ölçüm, dayanak bir dokunuş uzakta.
                      _AnlamKatmani(
                        mode: widget.mode,
                        data: veri,
                        natalYuk: _natalYuk(),
                        filter: _filter,
                        maxOrb: _maxOrb,
                      ),
                      _Baslik(mode: widget.mode, data: veri,
                          personAd: _personAd()),
                      if (!veri.hourKnown &&
                          widget.mode != ChartInspectorMode.sky)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Text(l10n.chartHourUnknownNote,
                              style: RythoText.body(11.5,
                                  color: RythoColors.caution)),
                        ),
                      Center(
                        child: ChartWheel(
                          data: veri,
                          size: carkBoyu,
                          filter: _filter,
                          maxOrb: _maxOrb,
                          showMinors: _showMinors,
                          selection: _selection,
                          onPlanetTap: _onPlanetTap,
                          onAspectTap: _onAspectTap,
                        ),
                      ),
                      _SecimCubugu(
                          selection: _selection,
                          data: veri,
                          onDetail: () {
                            if (_selection.aspect != null) {
                              showAspectSheet(context,
                                  _aspectAsMap(_selection.aspect!));
                            } else if (_selection.pointName != null) {
                              final p = veri.resolve(_selection.pointName!,
                                  _selection.pointRing ?? 0);
                              if (p != null) {
                                showPointSheet(context, _pointAsMap(p));
                              }
                            }
                          },
                          onClear: () => setState(
                              () => _selection = WheelSelection.none)),
                      _Lejant(data: veri, showMinors: _showMinors),
                      const SizedBox(height: RythoSpace.md),
                      _FiltreCubugu(
                        filter: _filter,
                        maxOrb: _maxOrb,
                        showMinors: _showMinors,
                        onFilter: (f) => setState(() => _filter = f),
                        onOrb: (o) => setState(() => _maxOrb = o),
                        onMinors: (v) => setState(() => _showMinors = v),
                      ),
                      if (widget.mode == ChartInspectorMode.synastry &&
                          (widget.person?.hourKnown ?? false))
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: FilterChip(
                              label: Text(_housesInner
                                  ? l10n.chartHousesYou
                                  : l10n.chartHousesOther(_personAd())),
                              selected: !_housesInner,
                              onSelected: (_) => setState(
                                  () => _housesInner = !_housesInner),
                            ),
                          ),
                        ),
                      const SizedBox(height: RythoSpace.lg),
                      _Aspectarian(
                          data: veri,
                          filter: _filter,
                          maxOrb: _maxOrb,
                          showMinors: _showMinors),
                      const SizedBox(height: RythoSpace.lg),
                      ChartPositionsTable(data: veri),
                      const SizedBox(height: RythoSpace.lg),
                      // Davet en altta, tek bileşenden (beş kopyanın dördü
                      // ayrışır): etiket `RythoyaSor` içinde `l10n.signalAsk`.
                      RythoyaSor(onTap: () => _sor(l10n)),
                    ],
                  );
                }),
    );
  }
}

// ---------------------------------------------------------------------------
// Parçalar
// ---------------------------------------------------------------------------

/// Anlam katmanına verilecek natal yük — kip kapısı BURADA, tek yerde.
///
/// NEDEN kapı var: natal yük bütün bir haritanın element dağılımıdır ve
/// ekranın konusu yalnız natal kipte o haritadır. Gökyüzü kipinde harita
/// yok; çift halkalı kiplerde (bi-wheel / sinastri) ekranın konusu bütün
/// harita değil İKİ ŞEYİN DEĞMESİ. O kiplerde kullanıcının natal baskın
/// elementini sayfanın en üstüne yazmak, ölçüleni YANLIŞ ADLA sunmak
/// olurdu: panel "Ateş" der ama ekran iki kişinin açılarını anlatıyordur.
///
/// NEDEN üst düzeyde ve saf: ekranın kendisi Firebase/profil
/// sağlayıcılarına bağlı, yani widget testi yazılamıyor. Kapı `State`
/// metodunda durduğu sürece KÖRDÜ — doğrulama turunda ölçüldü: kapı
/// silindiğinde takımın tamamı YEŞİL kalıyordu.
///
/// [saglayici] bir fonksiyon, değer değil: kapı geçilmedikçe çağrılmaz,
/// yoksa natal olmayan kipler `natalChartProvider`a abone olur.
Map<String, dynamic>? natalAnlamYuku(
  ChartInspectorMode mode, {
  required Map<String, dynamic>? override,
  required Map<String, dynamic>? Function() saglayici,
}) {
  if (mode != ChartInspectorMode.natal) return null;
  return override ?? saglayici();
}

/// Anlam katmanının konusu olacak açı: EN DAR GÖRÜNÜR açı. Yoksa null.
///
/// "Görünür" şart: kullanıcı filtre/orb kaydırıcısını kendi kurcalıyor;
/// çarkta çizilmeyen bir açıyı ekranın başında anlatmak gösterilmeyen bir
/// şeyi beyan etmek olurdu. Kapı çarkın kendi yüklemiyle AYNI
/// (`aspectVisible`), ikinci bir eşik tanımlanmadı.
///
/// Çift halkalıda çapraz açı tercih edilir: "Sen & Ayşe" ekranında tek
/// bir kişinin kendi içindeki açı yanlış özne olur. Çapraz açı yoksa
/// havuz bütün görünür açılara düşer — zorlama yapılmaz.
///
/// NEDEN üst düzeyde: `_AnlamKatmani`'nin özel metoduydu ve doğrulama
/// turunda ölçüldü — hem "en dar" seçimi hem çapraz tercihi TERSİNE
/// çevrildiğinde takım YEŞİL kalıyordu, yani bu ekranın tek anlam
/// cümlesini seçen kural hiç test görmüyordu. Harita İnceleme'nin widget
/// testi Firebase/profil sağlayıcılarını ister; kural saf bir fonksiyon
/// olarak çıkarılınca doğrudan çivilenebiliyor.
ChartAspect? liderGorunurAci(
  ChartData data,
  WheelAspectFilter filter,
  double maxOrb, {
  required bool showMinors,
}) {
  final gorunur = data.aspects
      .where((a) => aspectVisible(a, filter, maxOrb, showMinors: showMinors))
      .toList();
  if (gorunur.isEmpty) return null;
  final capraz = gorunur.where((a) => a.isCross).toList();
  final havuz = (data.isBiWheel && capraz.isNotEmpty) ? capraz : gorunur;
  havuz.sort((x, y) => x.orb.compareTo(y.orb));
  return havuz.first;
}

/// Anlam katmanı — ekranda ilk görünen şey.
///
/// ## Neden var
/// Sahibin tarifi: "açılar, elementler, sinastriler ÖNCE TEKNİK DETAY
/// veriyor… kullanıcılar çamaşır makinesi kılavuzu muamelesi yapıyor."
/// Bu ekran ölçülen en kötü yüzeydi: üç tablo, sıfır cümle.
///
/// ## Cümle NEREDEN geliyor — ve nereden GELMİYOR
/// Sunucudan gelen hazır yorum metni kullanılMADI. Tek böyle metin
/// `/api/v1/reports/natal` (natalReportProvider) ve üç nedenle buraya
/// uymuyor: (1) Plus kapısının arkasında, bu ekran ise bilerek ÜCRETSİZ
/// katman — `natalChartProvider`ın belgesi "bunlar hesaptır, LLM maliyeti
/// YOKTUR" diyor; (2) her açılışta LLM maliyeti doğurur; (3) gökyüzü,
/// bi-wheel ve sinastri kiplerinde böyle bir metin hiç yok. Yeni bir uç
/// istemek backend işi ve bu paketin dışında (raporda önerildi).
///
/// Bunun yerine cümle SEÇİLİYOR: hepsi zaten var olan anlam dizelerinden
/// biri, bu haritanın KENDİ ölçümüne göre. Yani yeni bir sabit cümle
/// tablosu doğmuyor ve seçim harita başına değiştiği için iki kullanıcı
/// aynı cümleyi görmüyor — jenerikliğin kaynağı tam olarak buydu.
///
/// ## Lider açı MAJÖRLER arasından seçilir
/// `liderGorunurAci` çağrısı `showMinors: false` ile yapılır, kullanıcı
/// minörleri açmış olsa bile. NEDEN: minör açıların anlam cümlesi YOK
/// (`aspectMeaningText` null döner, uydurulmaz) ve minörler açıkken en dar
/// görünür açı bir quincunx çıkınca panel sessizce KAYBOLUYORDU (ölçüldü)
/// — çarkta çizili bir üçgen dururken ekranın tek cümlesi yok oluyordu.
/// Majörler her zaman çizildiği için seçilen açı yine görünür bir açıdır;
/// "çizilmeyeni anlatma" kuralı bozulmaz.
///
/// ## Hiçbir şey ölçülemezse
/// Hiç çizilmez. Boş bir yer, uydurulmuş bir cümleden iyidir.
class _AnlamKatmani extends StatelessWidget {
  const _AnlamKatmani({
    required this.mode,
    required this.data,
    required this.natalYuk,
    required this.filter,
    required this.maxOrb,
  });

  final ChartInspectorMode mode;
  final ChartData data;
  final Map<String, dynamic>? natalYuk;
  final WheelAspectFilter filter;
  final double maxOrb;

  /// Baskın element — sunucunun kanonik sayımından.
  ///
  /// Kural (kesin üstünlük, eşitlikte null) `baskinElement`te TEK yerde
  /// duruyor; burada kendi kopyası vardı ve doğrulama turunda ölçüldü:
  /// kopyanın eşitlik kapısını kaldırmak takımı yeşil bırakıyordu.
  String? _baskinElement(Map<String, dynamic> yuk) => baskinElement(
      Map<String, dynamic>.from(
          yuk['element_distribution'] as Map? ?? const {}));

  Widget _panel(
      {required String etiket,
      required String cumle,
      required VoidCallback dayanak}) {
    return GlassPanel(
      label: etiket,
      margin: const EdgeInsets.only(top: 6, bottom: RythoSpace.sm),
      onTap: dayanak,
      child: Text(cumle, style: RythoText.body(14, height: 1.5)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    // Natal kipte ekranın konusu haritanın BÜTÜNÜ, o yüzden önce bütünü
    // anlatan ölçüm konuşur. Kesin baskınlık yoksa aşağıdaki açı dalına
    // düşülür — zorlama yapılmaz.
    final yuk = natalYuk;
    if (yuk != null) {
      final element = _baskinElement(yuk);
      if (element != null) {
        final noktalar = [
          for (final p in (yuk['points'] as List? ?? const []))
            Map<String, dynamic>.from(p as Map),
        ];
        return _panel(
          etiket: elementName(l10n, element),
          cumle: elementLine(l10n, element),
          dayanak: () => showDagilimSheet(
            context,
            baslik: elementName(l10n, element),
            aciklama: elementLine(l10n, element),
            klasik: temperamentLine(l10n, element),
            uyeler: List<String>.from(
                (yuk['element_members'] as Map?)?[element] as List? ??
                    const []),
            points: noktalar,
          ),
        );
      }
    }

    final aci = liderGorunurAci(data, filter, maxOrb, showMinors: false);
    if (aci != null) {
      final cumle = aspectMeaningText(l10n, aci.kind);
      // Minör açıların anlam cümlesi YOK; olmayan cümle uydurulmaz.
      if (cumle != null) {
        return _panel(
          etiket: aci.localLabel ?? '${aci.p1} — ${aci.p2}',
          cumle: cumle,
          dayanak: () => showAspectSheet(context, aspectSheetMap(aci)),
        );
      }
    }

    return const SizedBox.shrink();
  }
}

/// Veri başlığı: kim/ne zaman + ev sistemi (astrolog önce bunu okur).
class _Baslik extends ConsumerWidget {
  const _Baslik(
      {required this.mode, required this.data, required this.personAd});

  final ChartInspectorMode mode;
  final ChartData data;
  final String personAd;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final satirlar = <String>[];

    if (mode == ChartInspectorMode.sky) {
      final sky = ref.watch(skyNowProvider).value;
      final iso = sky?['timestamp_utc'] as String?;
      final t = iso == null ? null : DateTime.tryParse(iso)?.toLocal();
      if (t != null) {
        String iki(int n) => n.toString().padLeft(2, '0');
        satirlar.add(l10n.chartAsOf(
            '${iki(t.day)}.${iki(t.month)} ${iki(t.hour)}:${iki(t.minute)}'));
      }
    } else {
      final profil = ref.watch(profileProvider).value ?? {};
      final ad = mode == ChartInspectorMode.natal && personAd.isNotEmpty
          ? personAd
          : (profil['displayName'] as String? ?? '');
      final dogum = mode == ChartInspectorMode.natal && personAd.isNotEmpty
          ? null
          : profil['birthDate'] as String?;
      final sehir = mode == ChartInspectorMode.natal && personAd.isNotEmpty
          ? null
          : profil['birthCity'] as String?;
      satirlar.add([ad, dogum, sehir]
          .where((s) => s != null && s.isNotEmpty)
          .join(' · '));
    }
    if (data.hourKnown) satirlar.add(l10n.chartHouseSystem);

    return Padding(
      padding: const EdgeInsets.only(top: 6, bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final s in satirlar.where((s) => s.isNotEmpty))
            Text(s,
                style: RythoText.mono(10.5,
                    color: RythoColors.parchmentDim)),
        ],
      ),
    );
  }
}

/// Lejant: halka rozetleri (adsız bi-wheel'e astrolog güvenmez) + açı
/// sınıfı çizgi dili + Y/A dipnotu. Halka rengi çarkla AYNI kuraldan
/// (`ringGlyphColor`); açı satırı ressamla aynı `drawAspectLine`.
class _Lejant extends StatelessWidget {
  const _Lejant({required this.data, required this.showMinors});

  final ChartData data;
  final bool showMinors;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    Widget rozet(Color renk, String metin) =>
        Row(mainAxisSize: MainAxisSize.min, children: [
          Container(
              width: 9,
              height: 9,
              decoration:
                  BoxDecoration(color: renk, shape: BoxShape.circle)),
          const SizedBox(width: 6),
          // Rozet `Wrap` içinde duruyor; gevşek kısıtta uzun etiket
          // esnemeyince kendi satırından taşıyordu.
          Flexible(
            child: Text(metin,
                style:
                    RythoText.body(11.5, color: RythoColors.parchmentDim)),
          ),
        ]);

    return Padding(
      padding: const EdgeInsets.only(top: RythoSpace.md),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Wrap(spacing: RythoSpace.lg, runSpacing: 4, children: [
          rozet(ringGlyphColor(data, 0),
              l10n.chartLegendInner(data.rings.first.label)),
          if (data.isBiWheel)
            rozet(ringGlyphColor(data, 1),
                l10n.chartLegendOuter(data.rings[1].label)),
        ]),
        const SizedBox(height: RythoSpace.xs),
        AciSinifiLejanti(
          showMinors: showMinors,
          // Y/A harfi yalnız `movement` taşıyan açılarda basılır; hiçbiri
          // taşımıyorsa (natal/sinastri yükü) dipnot da basılmaz.
          hareketVar: data.aspects.any((a) => a.applying != null),
        ),
      ]),
    );
  }
}

/// Seçili gezegen/açı bilgisi + "Detay →" + "Seçimi kaldır".
///
/// Kaldırma düğmesi GÖRÜNÜR: eski yol çarkı saran çıplak bir
/// `GestureDetector`dı — ekran okuyucuya hiç duyurulmayan, görmeyen
/// kullanıcı için var olmayan bir eylem (semantik rolü yok).
class _SecimCubugu extends StatelessWidget {
  const _SecimCubugu(
      {required this.selection,
      required this.data,
      required this.onDetail,
      required this.onClear});

  final WheelSelection selection;
  final ChartData data;
  final VoidCallback onDetail;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    if (selection.isEmpty) return const SizedBox.shrink();

    String metin;
    if (selection.aspect != null) {
      final a = selection.aspect!;
      final hareket = a.applying == null
          ? ''
          : ' · ${a.applying! ? l10n.chartApplyingLetter : l10n.chartSeparatingLetter}';
      metin =
          '${a.localLabel ?? '${a.p1} ${a.kind} ${a.p2}'} · orb ${a.orb.toStringAsFixed(1)}°$hareket';
    } else {
      final p = data.resolve(
          selection.pointName!, selection.pointRing ?? 0);
      if (p == null) return const SizedBox.shrink();
      metin =
          '${p.localName} · ${p.degreeInSign.toStringAsFixed(1)}°'
          '${p.houseNo != null ? ' · ${l10n.houseN(p.houseNo!)}' : ''}';
    }

    return Padding(
      padding: const EdgeInsets.only(top: RythoSpace.sm),
      child: GlassPanel(
        child: Row(children: [
          Expanded(
              child: Text(metin,
                  style: RythoText.mono(11.5,
                      color: RythoColors.parchment))),
          IconButton(
            tooltip: l10n.chartSelectionClear,
            onPressed: onClear,
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.close_rounded,
                size: 16, color: RythoColors.parchmentDim),
          ),
          // Düğme esnemiyordu: soldaki `Expanded` sıfıra inse bile uzun
          // düğme etiketi + iç dolgu dar ekranda satırı taşırıyordu.
          Flexible(
            child: TextButton(
                onPressed: onDetail,
                child: Text(l10n.chartSelectedDetail,
                    style: RythoText.label(11,
                        color: RythoColors.goldBright))),
          ),
        ]),
      ),
    );
  }
}

/// Filtre çipleri + orb kaydırıcısı.
class _FiltreCubugu extends StatelessWidget {
  const _FiltreCubugu({
    required this.filter,
    required this.maxOrb,
    required this.showMinors,
    required this.onFilter,
    required this.onOrb,
    required this.onMinors,
  });

  final WheelAspectFilter filter;
  final double maxOrb;
  final bool showMinors;
  final ValueChanged<WheelAspectFilter> onFilter;
  final ValueChanged<double> onOrb;
  final ValueChanged<bool> onMinors;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final adlar = {
      WheelAspectFilter.all: l10n.chartFilterAll,
      WheelAspectFilter.major: l10n.chartFilterMajor,
      WheelAspectFilter.applying: l10n.chartFilterApplying,
      WheelAspectFilter.hard: l10n.chartFilterHard,
      WheelAspectFilter.soft: l10n.chartFilterSoft,
    };
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Wrap(spacing: 8, runSpacing: 6, children: [
        for (final e in adlar.entries)
          ChoiceChip(
            label: Text(e.value),
            selected: filter == e.key,
            onSelected: (_) => onFilter(e.key),
            labelStyle: RythoText.label(11,
                color: filter == e.key
                    ? RythoColors.parchment
                    : RythoColors.parchmentDim),
          ),
        FilterChip(
          label: Text(l10n.chartFilterMinors),
          selected: showMinors,
          onSelected: onMinors,
          labelStyle: RythoText.label(11,
              color: showMinors
                  ? RythoColors.parchment
                  : RythoColors.parchmentDim),
        ),
      ]),
      Row(children: [
        // Etiket esnemiyordu; `Slider` `Expanded` içinde sıfıra kadar
        // küçülse bile uzun etiket + büyük ölçek satırı taşırıyordu.
        Flexible(
          child: Text(l10n.chartOrbLabel(maxOrb.round()),
              style: RythoText.mono(11, color: RythoColors.parchmentDim)),
        ),
        Expanded(
          child: Slider(
            value: maxOrb,
            min: 1,
            max: 8,
            divisions: 7,
            onChanged: onOrb,
          ),
        ),
      ]),
    ]);
  }
}

/// Aspectarian: tekil haritada alt-üçgen, sinastride TAM dikdörtgen
/// (satır = iç halka, sütun = dış halka). Hücre: açı glifi + çizgi dili
/// örneği + orb + Y/A.
class _Aspectarian extends StatelessWidget {
  const _Aspectarian(
      {required this.data,
      required this.filter,
      required this.maxOrb,
      required this.showMinors});

  final ChartData data;
  final WheelAspectFilter filter;
  final double maxOrb;
  final bool showMinors;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cross = data.isBiWheel;
    final satirlar = data.rings.first.points;
    final sutunlar = cross ? data.rings[1].points : satirlar;

    // (satır adı, sütun adı) → açı.
    final hucre = <(String, String), ChartAspect>{};
    for (final a in data.aspects) {
      if (!aspectVisible(a, filter, maxOrb, showMinors: showMinors)) {
        continue;
      }
      if (cross) {
        // p1 iç halkada olacak şekilde normalize et.
        if (a.p1Ring == 0) {
          hucre[(a.p1, a.p2)] = a;
        } else {
          hucre[(a.p2, a.p1)] = a;
        }
      } else {
        hucre[(a.p1, a.p2)] = a;
        hucre[(a.p2, a.p1)] = a;
      }
    }
    if (hucre.isEmpty) return const SizedBox.shrink();

    const kenar = 34.0;
    Widget baslikHucre(ChartPoint p, Color renk) => SizedBox(
          width: kenar,
          height: kenar,
          child: Center(
            child: kPlanetTextGlyphs.containsKey(p.name)
                ? Text(kPlanetTextGlyphs[p.name]!,
                    style: RythoText.glyph(13, color: renk))
                : CustomPaint(
                    size: const Size(13, 13),
                    painter: MiniGlyphPainter(p.name, renk)),
          ),
        );

    // Sütun başlığı dış halkanın GERÇEK rengi (ringGlyphColor): bi-wheel
    // transit sütunu altın başlıklanırken çark lila çiziyordu.
    final sutunRengi = ringGlyphColor(data, cross ? 1 : 0);

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(l10n.chartAspectarianTitle,
          style: RythoText.mono(10, color: RythoColors.parchmentDim)),
      const SizedBox(height: 6),
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Column(children: [
          Row(children: [
            const SizedBox(width: kenar, height: kenar),
            for (final s in sutunlar) baslikHucre(s, sutunRengi),
          ]),
          for (var i = 0; i < satirlar.length; i++)
            Row(children: [
              baslikHucre(satirlar[i], ringGlyphColor(data, 0)),
              for (var j = 0; j < sutunlar.length; j++)
                SizedBox(
                  width: kenar,
                  height: kenar,
                  child: (!cross && j >= i)
                      ? const SizedBox.shrink()
                      : _AspectCell(
                          aspect: hucre[(
                            satirlar[i].name,
                            sutunlar[j].name
                          )],
                          l10n: l10n),
                ),
            ]),
        ]),
      ),
    ]);
  }
}

class _AspectCell extends StatelessWidget {
  const _AspectCell({required this.aspect, required this.l10n});

  final ChartAspect? aspect;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final a = aspect;
    if (a == null) {
      return const DecoratedBox(
          decoration: BoxDecoration(
              border: Border.fromBorderSide(
                  BorderSide(color: kAspectGridLine))));
    }
    final renk = aspectColor(a.kind);
    final harf = a.applying == null
        ? ''
        : (a.applying!
            ? l10n.chartApplyingLetter
            : l10n.chartSeparatingLetter);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: renk.withValues(alpha: 0.08),
        border: const Border.fromBorderSide(
            BorderSide(color: kAspectGridLine)),
      ),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        // Beş majör glifin beşi de glif fontundan (⚹ dahil): aile
        // verilmeyen `TextStyle` sistem fontuna, Android'de emojiye
        // düşüyordu; ⚹ için ayrı bir vektör dalı ikinci bir yoldu.
        Text(kAspectTextGlyphs[a.kind] ?? '·',
            style: RythoText.glyph(11, color: renk)),
        // Sınıf, renkten BAĞIMSIZ okunsun: çarktaki çizginin kendisi.
        AciCizgiOrnegi(
            dil: aspectDashFor(a.kind), renk: renk, genislik: 16, kalinlik: 1.2),
        Text('${a.orb.toStringAsFixed(1)}$harf',
            style: RythoType.chartMicro
                .copyWith(color: RythoColors.parchmentDim)),
      ]),
    );
  }
}
