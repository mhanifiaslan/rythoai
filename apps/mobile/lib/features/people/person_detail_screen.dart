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
import '../../widgets/common.dart';
import '../../widgets/cosmic_scaffold.dart';
import '../../widgets/glass.dart';
import '../../widgets/chart/chart_data.dart';
import '../../widgets/chart/chart_wheel.dart';
import '../../widgets/nebula_widgets.dart' show Pressable, localizedSignName;
import '../atlas/atlas_detail_screens.dart'
    show showAspectSheet, showPointSheet;
import '../atlas/chart_inspector_screen.dart';
import '../chat/chat_screen.dart';
import '../friends/relationship_screen.dart' show RelationshipScreen;
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

class PersonDetailScreen extends ConsumerWidget {
  const PersonDetailScreen({super.key, required this.person});

  final Person person;

  Future<void> _sil(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    final onay = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        backgroundColor: RythoColors.inkLight,
        content: Text(l10n.peopleRemoveConfirm, style: RythoText.body(14)),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(c).pop(false),
              child: Text(l10n.cancel)),
          TextButton(
              onPressed: () => Navigator.of(c).pop(true),
              child: Text(l10n.peopleRemove,
                  style: const TextStyle(color: RythoColors.copper))),
        ],
      ),
    );
    if (onay != true || !context.mounted) return;

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
    final harita = ref.watch(personChartProvider(person));

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
          IconButton(
            icon: const Icon(Icons.edit_outlined, size: 20),
            onPressed: () async {
              final degisti = await Navigator.of(context).push<bool>(
                  MaterialPageRoute(
                      builder: (_) => PersonFormScreen(existing: person)));
              if (degisti == true) ref.invalidate(personChartProvider(person));
            },
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline_rounded, size: 20),
            onPressed: () => _sil(context, ref),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 60),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
                RythoSpace.lg, RythoSpace.md, RythoSpace.lg, 0),
            child: Text(relationLabel(l10n, person.relation),
                style: RythoText.mono(11.5, color: RythoColors.parchmentDim)),
          ),
          const SizedBox(height: RythoSpace.md),

          harita.when(
            loading: () => const Padding(
              padding: EdgeInsets.only(top: 60),
              child: Center(child: AstrolabeSpinner()),
            ),
            error: (e, _) => Padding(
              padding: const EdgeInsets.all(RythoSpace.lg),
              child: ErrorCard(
                  message: friendlyError(e, l10n),
                  onRetry: () =>
                      ref.invalidate(personChartProvider(person))),
            ),
            data: (h) => _HaritaBolumu(person: person, chart: h),
          ),

          const SizedBox(height: RythoSpace.xl),
          Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: RythoSpace.lg),
            child: Column(children: [
              _EylemSatiri(
                icon: Icons.public_rounded,
                label: l10n.relationshipTitle(ad),
                onTap: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) =>
                        RelationshipScreen.forPerson(person: person))),
              ),
              const SizedBox(height: RythoSpace.sm),
              _EylemSatiri(
                icon: Icons.auto_awesome_rounded,
                label: l10n.signalAsk,
                // TOHUM: etiket "Rytho'ya sor" diyordu ama sohbet BOŞ
                // açılıyordu — çağrı vardı, soru yoktu. `initialText`
                // giriş alanını ÖN-DOLDURUR, GÖNDERMEZ
                // (`chat_screen.dart`: "son söz onun"), yani tohum bir
                // teklif; kullanıcı silip kendi sorusunu yazabilir.
                //
                // NEDEN yeni bir dize değil `chartAskPrefill`: bu
                // ekranın gövdesi kişinin ÇARKI (Büyük Üçlü +
                // `ChartWheel`) ve aynı çarkı tam ekran açan düğme
                // ZATEN bu anahtarı bu adla kullanıyor — oraya
                // `titleOverride: ad` geçiyor, `ChartInspectorScreen._sor`
                // da `chartAskPrefill(_baslik)` kuruyor. Yani aynı
                // kişinin iki girişi aynı cümleyi üretiyor; ayrı bir
                // dize ikisini sebepsiz AYRIŞTIRIRDI.
                //
                // `ad` = `person.label ?? relationLabel(...)`: kullanıcı
                // bir ad yazmadıysa ilişki sözcüğü geçer, yani tohum her
                // hâlde ekranın başlığında okunan sözcüğü kullanır ve
                // sohbete yeni bir sözlük sokmaz. `personId` KALIYOR:
                // yetki kapısı ve bağlam fısıltısı tohumdan bağımsız.
                onTap: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => ChatScreen(
                        personId: person.id,
                        initialText: l10n.chartAskPrefill(ad)))),
              ),
            ]),
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

    return Column(children: [
      // Büyük Üçlü: Yükselen saatsizken sunucu ZATEN üretmiyor, bu yüzden
      // burada "—" değil, satır hiç çizilmiyor ve altta beyan duruyor.
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: RythoSpace.lg),
        child: GlassPanel(
          label: l10n.bigThreeTitle,
          child: Column(children: [
            _MuhurSatiri(
                etiket: l10n.bigThreeSun,
                deger: localizedSignName(l10n, chart['sun_sign'] as String?)),
            _MuhurSatiri(
                etiket: l10n.bigThreeMoon,
                deger: localizedSignName(l10n, chart['moon_sign'] as String?)),
            if ((chart['ascendant'] as String?) != null)
              _MuhurSatiri(
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
              style: RythoText.body(11.5, color: RythoColors.copper)),
        ),
      ],
      const SizedBox(height: RythoSpace.lg),
      if (veri.rings.first.points.isNotEmpty) ...[
        Center(
          child: ChartWheel(
            data: veri,
            size: 320,
            interactive: false,
            onPlanetTap: (g) =>
                showPointSheet(context, pointSheetMap(g.point)),
            onAspectTap: (a) =>
                showAspectSheet(context, aspectSheetMap(a)),
          ),
        ),
        // Harita İnceleme girişleri (HI-turu): kişinin kendi çarkı tam
        // ekran + kullanıcıyla İKİLİ (sinastri) çark — her ikisi de
        // kullanıcının kendi girdiği veriyle (gizlilik sözleşmesi aynı).
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
              onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                      builder: (_) => ChartInspectorScreen(
                          mode: ChartInspectorMode.natal,
                          person: person,
                          natalOverride: chart,
                          titleOverride: ad))),
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

class _MuhurSatiri extends StatelessWidget {
  const _MuhurSatiri({required this.etiket, required this.deger});

  final String etiket;
  final String? deger;

  @override
  Widget build(BuildContext context) {
    if (deger == null || deger!.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      // `Row` + `Spacer` ile iki esnemeyen metin: uzun etiket + uzun değer
      // dar ekranda satırı taşırıyordu. `Wrap` sığdığında eski görünümü
      // korur, sığmadığında değeri alt satıra indirir; metin kırpılmaz.
      // `SizedBox`: Wrap gevşek kısıtta büzülür, `spaceBetween` işlemez.
      child: SizedBox(
        width: double.infinity,
        child: Wrap(
          spacing: 12,
          runSpacing: 2,
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.end,
          children: [
            Text(etiket, style: RythoType.label),
            Text(deger!, style: RythoText.body(14, w: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}

class _EylemSatiri extends StatelessWidget {
  const _EylemSatiri(
      {required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(
            horizontal: RythoSpace.lg, vertical: 14),
        decoration: BoxDecoration(
          color: RythoColors.inkLighter,
          border: Border.all(color: RythoColors.glassStroke),
          borderRadius: BorderRadius.circular(RythoRadius.md),
        ),
        child: Row(children: [
          Icon(icon, size: 18, color: RythoColors.lilac),
          const SizedBox(width: RythoSpace.md),
          Expanded(
              child: Text(label, style: RythoText.body(14.5))),
          const Icon(Icons.chevron_right_rounded,
              size: 18, color: RythoColors.parchmentDim),
        ]),
      ),
    );
  }
}
