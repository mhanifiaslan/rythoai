/// Eklenen kişinin ekranı — mini Atlas (P-turu).
///
/// ## Neden ana Atlas'ın kişi seçicisi değil
///
/// Ana Atlas'ın altındaki her şey — günlük okuma, sinyaller, takvim,
/// yıl haritası — "sen"e ait. Oraya bir kişi seçici koymak her ekranda
/// "bu kimin günü?" belirsizliği yaratırdı. Kişi kendi ekranında yaşar.
///
/// ## Ücretsiz olan ne
///
/// Çark, Büyük Üçlü ve yerleşimler: hepsi LLM'siz hesap, hepsi ücretsiz
/// ("hesap bedava, yorum paralı"). Kilitlenen yalnız YORUM.
///
/// ## Sıra: anlam önce, ölçüm sonra (lifestyle kuralı)
///
/// Ekran üç tablo + çarkla açılıyordu, tek cümle yoktu. Artık ilk görünen
/// şey haritanın KENDİ ölçümünden seçilen bir anlam cümlesi
/// (`kisiAnlamCumlesi`), sonra Büyük Üçlü ve çark; en altta "Rytho'ya sor".
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api.dart';
import '../../core/discovery.dart';
import '../../core/people.dart';
import '../../l10n/app_localizations.dart';
import '../../theme/rytho_theme.dart';
import '../../theme/rytho_tokens.dart';
import '../../widgets/atlas_widgets.dart';
import '../../widgets/basis_sheet.dart' show OlcumSatiri;
import '../../widgets/chart/chart_data.dart';
import '../../widgets/chart/chart_wheel.dart';
import '../../widgets/chart/wheel_painter.dart' show WheelAspectFilter;
import '../../widgets/common.dart';
import '../../widgets/cosmic_scaffold.dart';
import '../../widgets/glass.dart';
import '../../widgets/liste_satiri.dart';
import '../../widgets/nebula_widgets.dart' show localizedSignName;
import '../../widgets/onay.dart' show onayla;
import '../atlas/atlas_detail_screens.dart'
    show
        aspectMeaningText,
        baskinElement,
        elementLine,
        elementName,
        showAspectSheet,
        showDagilimSheet,
        temperamentLine;
import '../atlas/chart_inspector_screen.dart';
import '../chat/chat_screen.dart';
import '../friends/relationship_screen.dart' show RelationshipScreen;
import '../share/share_card.dart' show shareChartCard;
import 'person_form_screen.dart' show PersonFormScreen, relationLabel;

/// Kişinin haritası. Anahtar kişinin kimliği + doğum verisi: kullanıcı
/// kaydı düzeltince harita da tazelenir.
final personChartProvider =
    FutureProvider.family<Map<String, dynamic>, Person>((ref, kisi) async {
  final dio = ref.watch(apiProvider);
  final response = await dio.post('/api/v1/astrology/natal-chart',
      data: kisi.toBirthPayload());
  return Map<String, dynamic>.from(response.data['data'] as Map);
});

/// Geri bildirim kanalındaki ekran kodu (`FeedbackScreen.screen` kapalı
/// kümesi): kişi ekranı Çevrem sekmesinin altında yaşar.
const String kKisiEkranKodu = 'circle';

/// Gömülü çarkın filtre/orb/minör ayarı — anlam cümlesinin "görünür açı"
/// kapısı bu üçlüyle AYNI olmak zorunda, yoksa çizilmeyen bir açı ekranın
/// başında anlatılır.
const WheelAspectFilter _kCarkFiltre = WheelAspectFilter.all;
const double _kCarkOrb = 8.0;
const bool _kCarkMinor = false;

/// Kişi ekranının anlam cümlesi: etiket + cümle + dayanağı.
///
/// [element] doluysa dayanak element dağılımı sayfası, [aci] doluysa açı
/// sayfası. İkisi birden asla dolu değil.
class KisiAnlam {
  const KisiAnlam._(
      {required this.etiket, required this.cumle, this.element, this.aci});

  final String etiket;
  final String cumle;
  final String? element;
  final ChartAspect? aci;
}

/// Haritanın KENDİ ölçümünden seçilen tek cümle — Harita İnceleme'nin
/// `_AnlamKatmani`sıyla aynı iki kural, aynı saf fonksiyonlar:
///
/// 1. Sunucunun kanonik element sayımında KESİN baskınlık varsa
///    (`baskinElement`, eşitlikte null) element cümlesi.
/// 2. Yoksa en dar GÖRÜNÜR açı (`liderGorunurAci`, çarkın kendi filtresi ve
///    orbuyla) ve o açının anlam cümlesi; minör açıya cümle UYDURULMAZ
///    (`aspectMeaningText` null döner).
///
/// Hiçbiri yoksa null → panel hiç çizilmez. Boş yer, uydurma cümleden
/// iyidir. Saf: ekran ağdan beslendiği için kural burada çivilenir
/// (emsal: `liderGorunurAci`nin kendisi).
KisiAnlam? kisiAnlamCumlesi(
    AppLocalizations l10n, Map<String, dynamic> chart, ChartData veri) {
  final element = baskinElement(Map<String, dynamic>.from(
      chart['element_distribution'] as Map? ?? const {}));
  if (element != null) {
    return KisiAnlam._(
      etiket: elementName(l10n, element),
      cumle: elementLine(l10n, element),
      element: element,
    );
  }
  final aci =
      liderGorunurAci(veri, _kCarkFiltre, _kCarkOrb, showMinors: _kCarkMinor);
  if (aci == null) return null;
  final cumle = aspectMeaningText(l10n, aci.kind);
  if (cumle == null) return null;
  return KisiAnlam._(
    etiket: aci.localLabel ?? '${aci.p1} — ${aci.p2}',
    cumle: cumle,
    aci: aci,
  );
}

class PersonDetailScreen extends ConsumerWidget {
  const PersonDetailScreen({super.key, required this.person});

  final Person person;

  Future<void> _sil(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    // Yıkıcı eylem tek kapıdan (`onayla`): başlık eylemin adı, gövde
    // bedeli ("geri alınamaz"), onay düğmesi madder.
    final onay = await onayla(
      context,
      title: l10n.peopleRemove,
      body: l10n.peopleRemoveConfirm,
      confirmLabel: l10n.peopleRemove,
      destructive: true,
    );
    if (!onay || !context.mounted) return;

    final gezgin = Navigator.of(context);
    final mesajci = ScaffoldMessenger.of(context);
    try {
      await deletePerson(ref.read(apiProvider), person.id);
      ref.invalidate(personSlotsProvider);
      mesajci.showSnackBar(SnackBar(content: Text(l10n.peopleRemoved)));
      gezgin.pop();
    } catch (e) {
      mesajci.showSnackBar(SnackBar(content: Text(friendlyError(e, l10n))));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final ad = person.label ?? relationLabel(l10n, person.relation);
    final iliskiEtiketi = relationLabel(l10n, person.relation);
    final harita = ref.watch(personChartProvider(person));
    final chart = harita.value;

    // OB4: çevreden birine bakmak keşif halkasının üçüncü dilimi.
    // build İÇİNDE provider değiştirilemez; kare sonrasına ertelenir
    // (mark idempotent — yeniden çizimde tekrar çağrılması zararsız).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (context.mounted) {
        ref.read(discoveryProvider.notifier).mark(DiscoveryTask.circle);
      }
    });

    return CosmicScaffold(
      appBar: AppBar(
        title: Text(ad),
        actions: [
          // Çark görüntüsü paylaşımı AppBar'da kalır (tek beyanlı istisna;
          // plan §7). Karta kişinin ADI değil ilişki etiketi basılır:
          // ad cihazda kalan bir sırdır, kart dışarı gider.
          IconButton(
            tooltip: l10n.shareReading,
            icon: const Icon(Icons.ios_share_rounded, size: 20),
            onPressed: chart == null
                ? null
                : () => shareChartCard(
                      context,
                      data: ChartData.fromNatal(chart, label: iliskiEtiketi),
                      title: iliskiEtiketi,
                      filter: _kCarkFiltre,
                      maxOrb: _kCarkOrb,
                      showMinors: _kCarkMinor,
                    ),
          ),
          IconButton(
            tooltip: l10n.edit,
            icon: const Icon(Icons.edit_outlined, size: 20),
            onPressed: () async {
              final degisti = await Navigator.of(context).push<bool>(
                  MaterialPageRoute(
                      builder: (_) => PersonFormScreen(existing: person)));
              if (degisti == true) ref.invalidate(personChartProvider(person));
            },
          ),
          IconButton(
            tooltip: l10n.peopleRemove,
            icon: const Icon(Icons.delete_outline_rounded, size: 20),
            onPressed: () => _sil(context, ref),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: RythoSpace.xxl),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
                RythoSpace.lg, RythoSpace.md, RythoSpace.lg, 0),
            // İlişki adı bir ölçüm değil AD; mono (veri) rolü yanlıştı.
            child: Text(iliskiEtiketi, style: RythoType.label),
          ),
          const SizedBox(height: RythoSpace.md),

          harita.when(
            loading: () => const SkeletonPanel(height: 320),
            error: (e, _) => Padding(
              padding: const EdgeInsets.all(RythoSpace.lg),
              child: ErrorCard(
                  message: friendlyError(e, l10n),
                  screen: kKisiEkranKodu,
                  onRetry: () =>
                      ref.invalidate(personChartProvider(person))),
            ),
            data: (h) => _HaritaBolumu(person: person, chart: h),
          ),

          const SizedBox(height: RythoSpace.xl),
          Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: RythoSpace.lg),
            child: ListeSatiri(
              leading: const Icon(Icons.public_rounded,
                  size: 18, color: RythoColors.lilac),
              title: l10n.relationshipTitle(ad),
              margin: EdgeInsets.zero,
              onTap: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) =>
                      RelationshipScreen.forPerson(person: person))),
            ),
          ),
          // TOHUM: giriş alanını ÖN-DOLDURUR, GÖNDERMEZ (`chat_screen.dart`:
          // "son söz onun"). Kip başına anahtar: eski `chartAskPrefill(ad)`
          // "Şu an {title} çarkını" kalıbıyla her kipte aynı cümleyi
          // üretiyordu; natal kipin kendi anahtarı var. `ad` = etiket ya da
          // ilişki sözcüğü, yani tohum ekranın başlığında okunan sözcüğü
          // kullanır. `personId` KALIYOR: yetki kapısı ve bağlam fısıltısı
          // tohumdan bağımsız.
          Padding(
            padding: const EdgeInsets.fromLTRB(
                RythoSpace.sm, RythoSpace.sm, RythoSpace.lg, 0),
            child: Align(
              alignment: Alignment.centerLeft,
              child: RythoyaSor(
                onTap: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => ChatScreen(
                        personId: person.id,
                        initialText: l10n.chartAskPrefillNatal(ad)))),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HaritaBolumu extends StatelessWidget {
  const _HaritaBolumu({required this.person, required this.chart});

  final Person person;
  final Map<String, dynamic> chart;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final ad = person.label ?? relationLabel(l10n, person.relation);
    final veri = ChartData.fromNatal(chart, label: ad);
    final anlam = kisiAnlamCumlesi(l10n, chart, veri);

    // Gömülü çark SALT ÖNİZLEME: dokunuş İnceleme'yi açar, gezegen/açı
    // alt-sayfaları yalnız orada. Eski hâli iki etkileşim modeli
    // taşıyordu (gezegene dokun → alt-sayfa, altındaki düğme → İnceleme)
    // ve dokunan kişi hangisini aldığını bilemiyordu (sky_now emsali).
    void incelemeyiAc() => Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => ChartInspectorScreen(
            mode: ChartInspectorMode.natal,
            person: person,
            natalOverride: chart,
            titleOverride: ad)));

    return Column(children: [
      // ANLAM ÖNCE: cümle varsa ekranın ilk kartı; dokununca dayanağı açar.
      if (anlam != null)
        _AnlamKarti(anlam: anlam, chart: chart),
      // Büyük Üçlü: Yükselen saatsizken sunucu ZATEN üretmiyor, bu yüzden
      // burada "—" değil, satır hiç çizilmiyor ve altta beyan duruyor
      // (`OlcumSatiri` boş değerde kendini gizler).
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: RythoSpace.lg),
        child: GlassPanel(
          label: l10n.bigThreeTitle,
          child: Column(children: [
            OlcumSatiri(
                etiket: l10n.bigThreeSun,
                deger: localizedSignName(l10n, chart['sun_sign'] as String?)),
            OlcumSatiri(
                etiket: l10n.bigThreeMoon,
                deger: localizedSignName(l10n, chart['moon_sign'] as String?)),
            OlcumSatiri(
                etiket: l10n.bigThreeAscendant,
                deger:
                    localizedSignName(l10n, chart['ascendant'] as String?)),
          ]),
        ),
      ),
      if (!person.hourKnown) ...[
        const SizedBox(height: RythoSpace.sm),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: RythoSpace.lg),
          child: Text(l10n.peopleHourUnknownBadge,
              style: RythoType.caption.copyWith(color: RythoColors.caution)),
        ),
      ],
      const SizedBox(height: RythoSpace.lg),
      if (veri.rings.first.points.isNotEmpty) ...[
        Center(
          child: ChartWheel(
            data: veri,
            size: 320,
            interactive: false,
            filter: _kCarkFiltre,
            maxOrb: _kCarkOrb,
            showMinors: _kCarkMinor,
            onTap: incelemeyiAc,
          ),
        ),
        // Harita İnceleme girişleri (HI-turu): kişinin kendi çarkı tam
        // ekran (çarkın kendisiyle aynı kapı) + kullanıcıyla İKİLİ
        // (sinastri) çark — her ikisi de kullanıcının kendi girdiği
        // veriyle (gizlilik sözleşmesi aynı).
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: RythoSpace.lg),
          // İki düğme esnemeyen bir `Row`daydı ve etiketlerden biri KİŞİ
          // ADINI taşıyor ("Ayşe ile ikili harita"); dar ekranda ikincisi
          // ekran dışına çıkıyordu. `Wrap` sığmayanı alt satıra indirir.
          // ⚠️ `Wrap` gevşek kısıtta içeriğine büzülür; `end` hizasının
          // işe yaraması için tam genişlik gerekir.
          child: SizedBox(
            width: double.infinity,
            child: Wrap(
                alignment: WrapAlignment.end,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
              TextButton.icon(
                onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                        builder: (_) => ChartInspectorScreen(
                            mode: ChartInspectorMode.synastry,
                            person: person))),
                icon: const Icon(Icons.join_left_rounded, size: 15),
                label: Text(l10n.chartModeSynastry(ad),
                    style: RythoText.label(11, color: RythoColors.lilac)),
              ),
              TextButton.icon(
                onPressed: incelemeyiAc,
                icon: const Icon(Icons.open_in_full_rounded, size: 15),
                label: Text(l10n.chartExpandTooltip,
                    style:
                        RythoText.label(11, color: RythoColors.goldBright)),
              ),
            ]),
          ),
        ),
      ],
    ]);
  }
}

/// Anlam kartı: etiket + cümle; dokunuş dayanağı açar (element dağılımı
/// ya da açı sayfası). Cümle burada SEÇİLMİYOR — `kisiAnlamCumlesi` seçti;
/// bu widget yalnız çizer ve dayanak sayfasını bağlar.
class _AnlamKarti extends StatelessWidget {
  const _AnlamKarti({required this.anlam, required this.chart});

  final KisiAnlam anlam;
  final Map<String, dynamic> chart;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final element = anlam.element;
    final aci = anlam.aci;
    return GlassPanel(
      label: anlam.etiket,
      margin: const EdgeInsets.fromLTRB(
          RythoSpace.lg, 0, RythoSpace.lg, RythoSpace.sm),
      onTap: () {
        if (element != null) {
          showDagilimSheet(
            context,
            baslik: elementName(l10n, element),
            aciklama: elementLine(l10n, element),
            klasik: temperamentLine(l10n, element),
            uyeler: List<String>.from(
                (chart['element_members'] as Map?)?[element] as List? ??
                    const []),
            points: [
              for (final p in (chart['points'] as List? ?? const []))
                Map<String, dynamic>.from(p as Map),
            ],
          );
        } else if (aci != null) {
          showAspectSheet(context, aspectSheetMap(aci));
        }
      },
      child: Text(anlam.cumle, style: RythoType.body),
    );
  }
}
