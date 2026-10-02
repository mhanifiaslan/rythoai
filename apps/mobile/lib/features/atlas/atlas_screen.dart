import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../theme/rytho_theme.dart';
import '../../widgets/atlas_widgets.dart' show AstrolabeSpinner;
import '../../theme/rytho_tokens.dart';
import '../../widgets/common.dart';
import '../../widgets/glass.dart';
import '../../widgets/chart/chart_data.dart';
import '../../widgets/chart/chart_wheel.dart';
import '../../widgets/chart/wheel_painter.dart' show WheelAspectFilter;
import '../../widgets/nebula_widgets.dart';
import 'chart_inspector_screen.dart';
import '../../widgets/markdown_text.dart' show markdownToPlain;
import '../../widgets/reading_card.dart';
import '../share/share_card.dart' show shareReportCard;
import '../face/face_reading_flow.dart';
import '../shell/app_shell.dart' show shellTabProvider;
import '../oracle/oracle_screen.dart';
import '../paywall/paywall_screen.dart';
import 'birth_hexagram_screen.dart';
import 'atlas_detail_screens.dart';
import 'inner_calendar_screen.dart';
import 'solar_return_screen.dart';
import '../sky/sky_now_screen.dart' show SkyNowSummary;
import '../../widgets/motion.dart';
import '../../core/api.dart' show friendlyError;
import '../../l10n/app_localizations.dart';

/// ATLAS — **haritan**. Dizin ekranı.
///
/// ## Yeniden kurgulandı
///
/// Önceki hâli ~2000 px'di: çark, kişi kartı, gezegen ızgarası, kişilik
/// çubukları, katlanır açı listesi ve sınırsız uzunlukta AI raporu alt alta
/// duruyordu. Kullanıcının tarifi "her şey her yerde hissi var, tam bir kaos"
/// idi ve teşhis "çok özellik var" değildi — **hepsinin aynı seviyede
/// durmasıydı**.
///
/// Şimdi: üstte çark (haritanın bir bakışta özeti), altında dört giriş. Her
/// giriş kendi sayfasını açıyor (bkz. atlas_detail_screens.dart).
///
/// Kişi kartı buradan tamamen kalktı; doğum verisi profile taşındı ve orada
/// **düzenlenebilir** oldu (bkz. features/profile/birth_record_screen.dart).
class AtlasScreen extends ConsumerStatefulWidget {
  const AtlasScreen({super.key});

  @override
  ConsumerState<AtlasScreen> createState() => _AtlasScreenState();
}

class _AtlasScreenState extends ConsumerState<AtlasScreen> {
  /// Çark görünümü (R3-3): 0 = Haritam, 1 = Şu an gökyüzü, 2 = İkili çark.
  int _gorunum = 0;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    // R2-F1: çark ve dizin ÜCRETSİZ katmandan (LLM maliyeti sıfır olan
    // hesap). Rytho'nun derin okuması (natalReportProvider) Plus'ta kalır.
    final natal = ref.watch(natalChartProvider);

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(title: Text(l10n.atlasTitle)),
      // Kehanet satırı natal raporun DIŞINDA duruyor.
      //
      // Yüz okuma önce `data != null` dalının içindeydi; sonuç şuydu: natal
      // rapor kilitliyken firaset girişi de hiç görünmüyordu. Oysa üç araç
      // da natal rapordan bağımsız çalışıyor (İching ücretsiz bile).
      //
      // Madde 11 (Revize R6): İching + BaZi Gökyüzü'nden BURAYA taşındı —
      // Yüz Okuma ile tek satır. Gökyüzü'nden ARAÇLAR bölümü kalktı.
      body: natal.when(
            // Harita hesabı hızlı ama ilk açılışta ağ turu var; sahne
            // (R12-B3) yüzde çubuğu olmadan gerçek işi anlatıyor.
            loading: () => StagedWaiting(stages: [
              l10n.atlasWaitStage1,
              l10n.atlasWaitStage2,
              l10n.atlasWaitStage3,
            ]),
            error: (e, _) => Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text(friendlyError(e, l10n),
                    style:
                        RythoText.body(14, color: RythoColors.parchmentDim)),
              ),
            ),
            data: (data) {
              if (data == null) {
                // Doğum kaydı yoksa harita hesaplanamaz — bu bir kilit
                // DEĞİL, eksik veri durumu. Uzun süre `PlusLockedCard` +
                // "derin yorum Rytho+ ile açılır" gösteriliyordu: yorum
                // "kilit değil" diyor, ekran paywall gibi görünüyordu.
                // Kullanıcı ücretsiz olan çarkı parayla sanıyordu.
                return _BirthMissingCard(
                  onTap: () =>
                      ref.read(shellTabProvider.notifier).state = 3,
                );
              }
          final chart = Map<String, dynamic>.from(data);
          final points = List<Map<String, dynamic>>.from(chart['points'] ?? []);
          final houses = List<Map<String, dynamic>>.from(chart['houses'] ?? []);
          final aspects = List<Map<String, dynamic>>.from(chart['aspects'] ?? []);
          // Hesap beyanları (T0): ör. şehir çözülemedi → Yükselen yaklaşık.
          // Sunucu metni isteğin dilinde üretir; burada yalnız gösterilir.
          final beyanlar =
              List<String>.from(chart['disclosure_texts'] ?? const []);

          var stagger = 0;
          Duration next() => Duration(milliseconds: 70 * stagger++);

          void ac(Widget sayfa) => Navigator.of(context)
              .push(MaterialPageRoute(builder: (_) => sayfa));

          return ListView(
            padding:
                const EdgeInsets.only(bottom: RythoSpace.dockClearance),
            children: [
              const SizedBox(height: RythoSpace.sm),
              // Beyan notu — BirthHexagram sınır beyanıyla aynı dil (bakır).
              if (beyanlar.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 4),
                  child: Text(beyanlar.join('\n'),
                      style:
                          RythoText.body(11.5, color: RythoColors.copper)),
                ),
              // Çark (R3-3): üç görünüm — Haritam / Şu an gökyüzü / İkili
              // çark (bi-wheel). Gökyüzü görünümü EVSİZ çizilir: ev ve
              // Yükselen konuma bağlıdır, konumsuz gökyüzüne ev çizmek
              // veri uydurmak olur (çark altındaki not bunu söyler).
              GlassPanel(
                padding: const EdgeInsets.all(8),
                child: Column(children: [
                  _WheelSegment(
                    secili: _gorunum,
                    etiketler: [
                      l10n.atlasWheelNatal,
                      l10n.atlasWheelSky,
                      l10n.atlasWheelBiwheel,
                    ],
                    onChanged: (i) => setState(() => _gorunum = i),
                  ),
                  const SizedBox(height: 4),
                  // HI-turu: üç görünüm de ORTAK ChartWheel'e geçti. Eski
                  // satır-içi gezegen kartı kalktı — dokunma her yerde
                  // aynı alt-sayfa ailesini açar (showPointSheet), gökyüzü
                  // ve bi-wheel görünümleri de artık dokunulabilir.
                  Builder(builder: (context) {
                    final boyut = MediaQuery.of(context).size.width - 72;
                    final skyAsync = ref.watch(skyNowProvider);
                    final sky = skyAsync.value;
                    final transits = _gorunum == 2
                        ? ref.watch(transitsProvider).value
                        : null;
                    final yukleniyor = switch (_gorunum) {
                      1 => sky == null,
                      // Bi-wheel dış halkasızken SESSİZCE tek halkaya
                      // düşmez (eski kusur) — bekleme gösterilir.
                      2 => sky == null || transits == null,
                      _ => false,
                    };
                    if (yukleniyor) {
                      return const Padding(
                        padding: EdgeInsets.all(RythoSpace.xl),
                        child: AstrolabeSpinner(),
                      );
                    }
                    final veri = switch (_gorunum) {
                      1 => ChartData.fromSky(sky!,
                          label: l10n.chartLegendSkyNow),
                      2 => ChartData.fromTransits(chart, transits!,
                          innerLabel: l10n.chartLegendYou,
                          outerLabel: l10n.chartLegendSkyNow),
                      _ => ChartData.fromNatal(chart,
                          label: l10n.chartLegendYou),
                    };
                    return Column(children: [
                      Center(
                        child: ChartWheel(
                          key: ValueKey('cark-$_gorunum'),
                          data: veri,
                          size: boyut,
                          interactive: false,
                          filter: _gorunum == 0
                              ? WheelAspectFilter.all
                              : WheelAspectFilter.major,
                          maxOrb: _gorunum == 2 ? 3.0 : 8.0,
                          onPlanetTap: (g) => showPointSheet(
                              context, pointSheetMap(g.point)),
                          onAspectTap: (a) =>
                              showAspectSheet(context, aspectSheetMap(a)),
                        ),
                      ),
                      if (_gorunum != 0 || houses.isEmpty)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(10, 2, 10, 6),
                          child: Text(
                              _gorunum == 1
                                  ? l10n.atlasSkyWheelNote
                                  : _gorunum == 2
                                      ? l10n.atlasBiwheelNote
                                      : l10n.atlasHourUnknownWheelNote,
                              style: RythoText.body(11,
                                  color: RythoColors.parchmentDim,
                                  height: 1.4)),
                        ),
                      // Harita İnceleme girişi (HI-turu): astrolog gözü
                      // için tam ekran — zoom, filtreler, açı tablosu.
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton.icon(
                          onPressed: () => Navigator.of(context).push(
                              MaterialPageRoute(
                                  builder: (_) => ChartInspectorScreen(
                                      mode: switch (_gorunum) {
                                        1 => ChartInspectorMode.sky,
                                        2 => ChartInspectorMode.biwheel,
                                        _ => ChartInspectorMode.natal,
                                      }))),
                          icon: const Icon(Icons.open_in_full_rounded,
                              size: 15),
                          label: Text(l10n.chartExpandTooltip,
                              style: RythoText.label(11,
                                  color: RythoColors.goldBright)),
                        ),
                      ),
                    ]);
                  }),
                ]),
              ).animate(delay: next()).fadeIn(duration: 380.ms).slideY(
                  begin: 0.06, curve: Curves.easeOutCubic),

              // ---------- ŞU AN GÖKYÜZÜNDE ----------
              // Gökyüzü'nden buraya taşındı (R3-2): gökyüzü durumu haritanın
              // yanında yaşar; tek satır özet, dokununca tam sayfa.
              SectionHeader(l10n.skyNow)
                  .animate(delay: next())
                  .fadeIn(duration: 360.ms),
              ref.watch(skyNowProvider).when(
                    loading: () => const SizedBox.shrink(),
                    error: (e, _) => Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: RythoSpace.lg),
                      child: Text(friendlyError(e, l10n),
                          style: RythoText.body(12,
                              color: RythoColors.parchmentDim)),
                    ),
                    data: (sky) => SkyNowSummary(sky: sky)
                        .animate(delay: next())
                        .fadeIn(duration: 380.ms),
                  ),

              // ---------- DİZİN ----------
              //
              // Kişi kartı BURADAN KALKTI: doğum verisi profile taşındı ve
              // orada düzenlenebilir oldu. Aynı bilginin iki yerde durması
              // kullanıcının "profilimde olan bilgiler de var" şikayetinin
              // kaynağıydı; üstelik burada salt okunurdu.
              // ---------- BANA DAİR ----------
              // Ücretsiz katman: harita HESABI (çark, yerleşimler, açılar).
              // Ücretli olan Rytho'nun bu haritayı OKUMASI.
              SectionHeader(l10n.atlasSectionAbout)
                  .animate(delay: next())
                  .fadeIn(duration: 360.ms),
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: RythoSpace.lg),
                child: Column(children: [
                  _AtlasRow(
                    emoji: '🎭',
                    title: l10n.atlasTraits,
                    subtitle: l10n.atlasTraitsSubtitle,
                    // R5-1: ekran artık kendi sayımını yapmıyor; sunucunun
                    // kanonik dağılımını okuyor (chart'ın tamamı gerekli).
                    onTap: () => ac(AtlasTraitsScreen(chart: chart)),
                  ),
                  _AtlasRow(
                    emoji: '🪐',
                    title: l10n.atlasPlanetPositions,
                    subtitle: l10n.atlasPlanetsSubtitle,
                    onTap: () => ac(AtlasPlanetsScreen(points: points)),
                  ),
                  _AtlasRow(
                    emoji: '📐',
                    title: l10n.atlasAspects,
                    subtitle: l10n.atlasAspectsCount(aspects.length),
                    onTap: () => ac(AtlasAspectsScreen(aspects: aspects)),
                  ),
                  // Tam okuma: LLM üretimi → Rytho+ .
                  const _FullReportRow(),
                  Padding(
                    padding: const EdgeInsets.only(top: 6, left: 2),
                    child: Text(l10n.atlasFreeChartNote,
                        style: RythoText.body(11,
                            color: RythoColors.parchmentDim, height: 1.4)),
                  ),
                ]),
              ).animate(delay: next()).fadeIn(duration: 380.ms).slideY(
                  begin: 0.06, curve: Curves.easeOutCubic),

              // ---------- ZAMAN ----------
              // Natal "an"ın haritasıydı; bunlar yılın ve iç mevsimin.
              // Başlıklar insan dilinde (R2-I1), teknik ad alt satırda.
              SectionHeader(l10n.atlasSectionTime)
                  .animate(delay: next())
                  .fadeIn(duration: 360.ms),
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: RythoSpace.lg),
                child: Column(children: [
                  _AtlasRow(
                    emoji: '🌞',
                    title: l10n.atlasYearChart,
                    subtitle: l10n.atlasYearChartSubtitle,
                    onTap: () => ac(const SolarReturnScreen()),
                  ),
                  _AtlasRow(
                    emoji: '🌗',
                    title: l10n.atlasInnerCalendar,
                    subtitle: l10n.atlasInnerCalendarSubtitle,
                    onTap: () => ac(const InnerCalendarScreen()),
                  ),
                ]),
              ).animate(delay: next()).fadeIn(duration: 380.ms).slideY(
                  begin: 0.06, curve: Curves.easeOutCubic),

              // ---------- DİĞER SİSTEMLER ----------
              // Batı astrolojisi ana vaat; İching/BaZi/firaset onun yanında
              // duran keşif alanları — aynı seviyede değil, altında.
              SectionHeader(l10n.atlasSectionOther)
                  .animate(delay: next())
                  .fadeIn(duration: 360.ms),
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: _DivinationRow(),
              ),
            ],
          );
            },
          ),
    );
  }
}

/// Tam natal okuma satırı — Rytho+ .
///
/// Abone değilse istek ATILMAZ (natalReportProvider zaten null döner);
/// satır kilit rozetiyle görünür ve dokunuş paywall'ı açar. Abonede rapor
/// hazır olduğunda okuma sayfasına gider.
///
/// R5-0 (hata): eskiden `rapor.value` doğrudan okunuyordu ve `AsyncValue`
/// YÜKLENİRKEN de null olduğu için ABONE, rapor üretilirken (LLM çağrısı
/// saniyeler sürer) 🔒 görüyor ve dokununca paywall'a düşüyordu. Bu yüzden
/// yükleniyor → satır bekliyor der ve dokunuş yutulur; hata → tekrar
/// denenebilir.
///
/// ⚠️ O turda yazılan "yalnız gerçekten `null` veri kilittir" cümlesi
/// EKSİKTİ ve P2'de ölçüldü: `null`ın ÜÇÜNCÜ bir kaynağı var. Abonelik ya da
/// profil cevabı gelmemişken sağlayıcı istek atmadan `null` dönüyor ve satır
/// yine kilitli çiziliyordu — "ekran açılınca kilitli, bekleyince açılıyor"
/// şikâyetinin Atlas'taki yüzü buydu. Kapı artık [raporKapisiProvider]'dan
/// sorulur.
class _FullReportRow extends ConsumerWidget {
  const _FullReportRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final kapi = ref.watch(raporKapisiProvider);
    final rapor = ref.watch(natalReportProvider);
    final harita = ref.watch(natalChartProvider).value;

    // Paylaşım kartındaki rozetler: Büyük Üçlü. HESAPLANMIŞ sonuçlar —
    // doğum tarihi/saati/yeri karta hiçbir koşulda yazılmaz.
    List<(String, String)> rozetler() {
      if (harita == null) return const [];
      final noktalar = List<Map<String, dynamic>>.from(
          (harita['points'] as List?) ?? const []);
      String? burc(String ad) {
        for (final p in noktalar) {
          if (p['name'] == ad) {
            final i = signIndexOf(p['sign_tr']);
            return i >= 0 ? signDisplayName(l10n, i) : null;
          }
        }
        return null;
      }

      // `ascendant` sunucudan "Aslan ♌" biçiminde METİN gelir (Map değil);
      // `signIndexOf` sembole toleranslı.
      final asc = signIndexOf(harita['ascendant'] as String?);
      final gunes = burc('Sun');
      final ay = burc('Moon');
      return [
        if (gunes != null) (l10n.bigThreeSun, gunes),
        if (ay != null) (l10n.bigThreeMoon, ay),
        if (asc >= 0) (l10n.bigThreeAscendant, signDisplayName(l10n, asc)),
      ];
    }

    void ac(String metin) => Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => ReadingScreen(
            title: l10n.atlasFullReport,
            label: l10n.atlasReadingNote,
            body: metin,
            onShare: (ctx) => shareReportCard(
              ctx,
              title: l10n.atlasFullReport,
              body: markdownToPlain(metin),
              dateLabel: bugununEtiketi(),
              badges: rozetler(),
              glyph: '✦',
            ),
          ),
        ));

    void paywall() => Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => const PaywallScreen(),
          fullscreenDialog: true,
        ));

    return rapor.when(
      loading: () => _AtlasRow(
        emoji: '📜',
        title: l10n.atlasFullReport,
        subtitle: l10n.atlasReportPreparing,
        onTap: () {},
      ),
      // Hata nesnesi ATILIYORDU: yedek metin artik `RaporUretilemedi` olarak
      // buraya duser (gz-2) ve sabit "tekrar dene" alt satiri kullaniciya ne
      // "su an uretemedik" ne "jetonun iade edildi" diyordu — yani durust
      // cumle ekrana HIC gelmiyordu. Alt satir bu dalda uc satira aciliyor:
      // iade cumlesi tek satira sigmiyor ve ellipsis tam da soylenmesi
      // gereken yeri kesiyordu.
      error: (e, _) => _AtlasRow(
        emoji: '📜',
        title: l10n.atlasFullReport,
        subtitle: friendlyError(e, l10n),
        subtitleLines: 3,
        onTap: () => ref.invalidate(natalReportProvider),
      ),
      data: (veri) {
        final metin = veri?['report'] as String?;
        // Kapı BİLİNMİYORken `null` "abone değil" DEMİYOR: cevap gelmemiş ve
        // ücretli uca henüz istek atılmamış. Kilit rozeti basmak ödemiş
        // kullanıcıya yalan, dokunuşu paywall'a göndermek ikinci yalan —
        // "hazırlanıyor" demek de üçüncüsü olurdu (hiçbir şey hazırlanmıyor).
        // Satır rozetsiz durur ve dokunuş yutulur, yükleniyor dalıyla aynı
        // duruş; kapı açılır açılmaz gerçek hâl çizilir.
        final bilinmiyor = kapi == PlusHali.bilinmiyor;
        return _AtlasRow(
          emoji: '📜',
          title: l10n.atlasFullReport,
          subtitle: l10n.atlasFullReportSubtitle,
          locked: metin == null && !bilinmiyor,
          onTap: () {
            if (bilinmiyor) return;
            if (metin == null) {
              paywall();
            } else {
              ac(metin);
            }
          },
        );
      },
    );
  }
}

/// Doğum kaydı eksikken gösterilen kart — **paywall değil**.
///
/// Çark, yerleşimler ve açılar ücretsiz; eksik olan tek şey doğum
/// kaydının kendisi. Bu yüzden kilit rozeti, kilit rengi ve "Rytho+ ile
/// açılır" dili KULLANILMAZ; kart doğrudan kaydı tamamlamaya götürür.
class _BirthMissingCard extends StatelessWidget {
  const _BirthMissingCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.all(RythoSpace.lg),
      child: GlassPanel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              const Text('🗺️', style: TextStyle(fontSize: 22)),
              const SizedBox(width: 10),
              Expanded(
                child: Text(l10n.birthMissingTitle,
                    style: RythoText.display(16, w: FontWeight.w700)),
              ),
            ]),
            const SizedBox(height: RythoSpace.sm),
            Text(l10n.birthMissingBody,
                style: RythoText.body(13, height: 1.5,
                    color: RythoColors.parchmentDim)),
            const SizedBox(height: RythoSpace.md),
            Pressable(
              onTap: onTap,
              // Eylem metni + ok esnemiyordu; uzun çeviri ("Doğum
              // bilgilerini tamamla") dar ekranda oku dışarı itiyordu.
              // `Wrap`: sığmazsa ok alt satıra iner, metin kısaltılmaz.
              child: Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 6,
                runSpacing: 4,
                children: [
                  Text(l10n.birthMissingAction,
                      style: RythoText.body(13,
                          w: FontWeight.w700, color: RythoColors.lilac)),
                  const Icon(Icons.arrow_forward_rounded,
                      size: 15, color: RythoColors.lilac),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Paylaşım kartının tarih satırı: raporun ÜRETİM günü.
///
/// Doğum tarihi DEĞİL — kartın gizlilik kuralı ham doğum verisini dışarıda
/// tutar; bu satır yalnız "bu okuma ne zaman alındı"yı söyler.
String bugununEtiketi() {
  final t = DateTime.now();
  return '${t.year}-${t.month.toString().padLeft(2, '0')}-'
      '${t.day.toString().padLeft(2, '0')}';
}

/// Gezegen + burç etiketi, arayüz diline göre.
///
/// Backend her iki adı da döndürüyor (`name` İngilizce, `name_tr` Türkçe);
/// burç adı yalnızca Türkçe geldiği için indekse çevrilip yerelleştiriliyor.
String planetSignLabel(BuildContext context, Map<String, dynamic> p) {
  final l10n = AppLocalizations.of(context);
  final ingilizce = Localizations.localeOf(context).languageCode == 'en';
  final signIndex = kSignNamesTr.indexOf(p['sign_tr'] ?? '');
  final gezegen = (ingilizce ? p['name'] : p['name_tr']) ?? p['name'] ?? '';
  final burc = signIndex >= 0
      ? signDisplayName(l10n, signIndex)
      : (p['sign_tr'] ?? '');
  return '$gezegen — $burc';
}

/// Açıdaki iki gezegen: "Güneş — Satürn" / "Sun — Saturn".
///
/// Natal harita ucu her iki adı da döndürüyor (`p1` İngilizce, `p1_tr`).
String aspectPairLabel(BuildContext context, Map<String, dynamic> a) {
  final ingilizce = Localizations.localeOf(context).languageCode == 'en';
  final p1 = (ingilizce ? a['p1'] : a['p1_tr']) ?? a['p1'] ?? '';
  final p2 = (ingilizce ? a['p2'] : a['p2_tr']) ?? a['p2'] ?? '';
  return '$p1 — $p2';
}

/// Açı türü: "Kare" / "Square".
///
/// İngilizce alan kerykeion'dan küçük harfle geliyor ("square"), gösterirken
/// baş harfi büyütülür.
String aspectKindLabel(BuildContext context, Map<String, dynamic> a) {
  final ingilizce = Localizations.localeOf(context).languageCode == 'en';
  if (!ingilizce) return (a['aspect_tr'] ?? a['aspect'] ?? '').toString();
  final ham = (a['aspect'] ?? '').toString();
  if (ham.isEmpty) return '';
  return ham[0].toUpperCase() + ham.substring(1);
}

// `localizedSign` KALDIRILDI: tek çağıran `_PersonCard`'dı, o da profile
// taşındı. Analiz aracı kullanılmayan üst düzey fonksiyonu uyarmıyor, bu
// yüzden elle temizlendi.

/// Atlas dizin karosu — emoji + başlık + tek satır alt bilgi.
///
/// `_PersonCard`, `_PlanetGrid`, `_TraitBars` ve `_FoldSection` buradan
/// kalktı. İlki profile taşındı (orada düzenlenebilir), diğer üçü kendi
/// sayfalarına (bkz. atlas_detail_screens.dart). Katlanır bölüm de gitti:
/// aynı ekranda hem katlanan hem katlanmayan bölümler olması, neyin nereye
/// açılacağını tahmin edilemez kılıyordu.
/// Çark görünüm seçici (R3-3): üç hap — Haritam / Şu an / İkili çark.
class _WheelSegment extends StatelessWidget {
  const _WheelSegment({
    required this.secili,
    required this.etiketler,
    required this.onChanged,
  });

  final int secili;
  final List<String> etiketler;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 4, 6, 2),
      child: Row(children: [
        for (var i = 0; i < etiketler.length; i++) ...[
          if (i > 0) const SizedBox(width: 6),
          Expanded(
            child: Pressable(
              onTap: () => onChanged(i),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 7),
                decoration: BoxDecoration(
                  color: secili == i
                      ? RythoColors.lilac.withValues(alpha: 0.16)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                      color: secili == i
                          ? RythoColors.lilac
                          : RythoColors.glassStroke),
                ),
                child: Center(
                  child: Text(etiketler[i],
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: RythoText.label(10.5,
                          color: secili == i
                              ? RythoColors.lilac
                              : RythoColors.parchmentDim)),
                ),
              ),
            ),
          ),
        ],
      ]),
    );
  }
}

/// Dizin satırı (R2-I1): karo ızgarası yerine okunur liste.
///
/// Karolar iki sütunda yan yana durunca başlıklar tek satıra sığmıyor ve
/// teknik ad ("Solar return") başlığın kendisi oluyordu. Satır düzeninde
/// başlık İNSAN dilinde, teknik ad altında ikinci satır olarak duruyor:
/// astroloji bilmeyen ne olduğunu anlıyor, bilen aradığını buluyor.
class _AtlasRow extends StatelessWidget {
  const _AtlasRow({
    required this.emoji,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.subtitleLines = 1,
    this.locked = false,
  });

  final String emoji;
  final String title;
  final String subtitle;

  /// Alt satirin tavani. Varsayilan 1: satirlar tek bakista taranan bir
  /// listede duruyor. Hata dalinda 3 (gz-2) — "harcanan jeton iade edildi"
  /// cumlesi tek satira sigmiyor ve ellipsis tam da soylenmesi gereken yeri
  /// kesiyordu.
  final int subtitleLines;
  final VoidCallback onTap;

  /// Rytho+ kilidi — rozet gösterilir, dokunuş paywall'a gider.
  final bool locked;

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: RythoColors.glassFill,
          borderRadius: BorderRadius.circular(RythoRadius.card),
          border: Border.all(color: RythoColors.glassStroke),
        ),
        child: Row(children: [
          Text(emoji, style: const TextStyle(fontSize: 19)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: RythoType.cardTitle),
                const SizedBox(height: 2),
                Text(subtitle,
                    maxLines: subtitleLines,
                    overflow: TextOverflow.ellipsis,
                    style: RythoType.caption),
              ],
            ),
          ),
          if (locked)
            const Padding(
              padding: EdgeInsets.only(right: 4),
              child: Text('🔒', style: TextStyle(fontSize: 13)),
            ),
          const Icon(Icons.chevron_right,
              size: 18, color: RythoColors.parchmentDim),
        ]),
      ),
    );
  }
}

/// Kehanet satırı: Yüz Okuma · İching · BaZi · Doğum Kapısı — eşit karolar.
///
/// Madde 11 (Revize R6): İching + BaZi Gökyüzü'ndeki ARAÇLAR bölümünden
/// buraya taşındı; kullanıcının istediği "tek satırda yan yana" düzen bu.
/// R10: sekmeli `OracleScreen` kalktı — her karo kendi bağımsız sayfasını
/// açıyor (karodan sonra sayfada aynı iki seçeneğin sekme olarak tekrar
/// çıkması kafa karıştırıyordu).
///
/// Yüz Okuma karosu ücretli uca **istek atmadan** kilit gösteriyor: abone
/// olmayan biri karoda 🔒 görür, dokununca paywall açılır, kamera hiç
/// başlamaz. Kamerayı açıp sonunda 402 almak, kullanıcıya yüzünü boşuna
/// taratmak olurdu. (Eski tam genişlik `FaceReadingEntry` kartının kuralı,
/// karo biçiminde devam ediyor.)
class _DivinationRow extends ConsumerWidget {
  const _DivinationRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    // Dört karo da Rytho+ (V2: İching ve BaZi de kilitlendi) — tek kapı.
    //
    // Eski hâl `abonelik.value?.active ?? false` idi ve abonelik cevabı
    // gelmeden DÖRT KARO BİRDEN kilitli çiziliyordu: ödemiş kullanıcı Atlas'ı
    // açtığında dört kilit rozeti görüp birkaç yüz ms sonra hepsinin
    // kaybolmasını izliyordu. Üçüncü hâl artık ayrı çiziliyor.
    final kapi = ref.watch(aboneHaliProvider);
    final plus = kapi == PlusHali.abone;

    // Cevap yokken ne kilit rozeti ne de açık karo: ikisi de bir hüküm.
    // Dokunma da YOK — paywall açmak "abone değilsin" demek, sayfayı açmak
    // ise ücretli uca 402'ye koşmak olurdu.
    if (kapi == PlusHali.bilinmiyor) {
      return SizedBox(
        height: 100,
        child: Row(children: [
          for (var i = 0; i < 4; i++) ...[
            if (i > 0) const SizedBox(width: 10),
            const Expanded(
                child: SkeletonPanel(height: 100, margin: EdgeInsets.zero)),
          ],
        ]),
      );
    }

    void paywall() => Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => const PaywallScreen(),
          fullscreenDialog: true,
        ));

    void ac(Widget sayfa) => Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => sayfa));

    return SizedBox(
      height: 100,
      child: Row(children: [
        Expanded(
          child: _DivinationTile(
            emoji: '👁️',
            title: l10n.faceReadingTitle,
            subtitle: l10n.faceReadingTileSubtitle,
            locked: !plus,
            onTap: () =>
                plus ? startFaceReading(context, ref) : paywall(),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _DivinationTile(
            emoji: '🪙',
            title: l10n.iChing,
            subtitle: l10n.iChingSubtitle,
            locked: !plus,
            onTap: () => plus ? ac(const IChingScreen()) : paywall(),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _DivinationTile(
            emoji: '🀄',
            title: l10n.baZi,
            subtitle: l10n.baZiSubtitle,
            locked: !plus,
            onTap: () => plus ? ac(const BaziScreen()) : paywall(),
          ),
        ),
        const SizedBox(width: 10),
        // Doğum Kapısı (İ5): çekim değil kimlik katmanı — abone değilken
        // kilit rozeti, dokununca paywall (Yüz Okuma karosuyla aynı kural).
        Expanded(
          child: _DivinationTile(
            emoji: '☯',
            title: l10n.birthHexagram,
            subtitle: l10n.birthHexagramSubtitle,
            locked: !plus,
            onTap: () =>
                plus ? ac(const BirthHexagramScreen()) : paywall(),
          ),
        ),
      ]),
    );
  }
}

/// Kehanet karosu — Gökyüzü'ndeki eski `_OracleCard`'ın üçlü satıra
/// sıkıştırılmış hâli. Üç karo yan yana ~110 px genişlik bırakır; alt yazı
/// tek satıra kırpılır, başlık taşarsa üç nokta alır.
class _DivinationTile extends StatelessWidget {
  const _DivinationTile({
    required this.emoji,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.locked = false,
  });

  final String emoji;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool locked;

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: RythoColors.glassFill,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: RythoColors.glassStroke),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Text(emoji, style: const TextStyle(fontSize: 22)),
            const Spacer(),
            if (locked)
              const Icon(Icons.lock_rounded,
                  size: 13, color: RythoColors.parchmentDim),
          ]),
          const Spacer(),
          Text(title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: RythoText.body(13.5, w: FontWeight.w700)),
          const SizedBox(height: 2),
          Text(subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: RythoText.body(10.5, color: RythoColors.parchmentDim)),
        ]),
      ),
    );
  }
}
