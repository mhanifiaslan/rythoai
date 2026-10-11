/// "Şu an gökyüzünde" — canlı gökyüzünün ANALİZ sayfası.
///
/// ## Neden yeniden kuruldu (KL-turu)
///
/// Sayfa, uygulamadaki son ESKİ çark tüketicisiydi: dekoratif `ZodiacRing`
/// (280 px, açı ağı yok, dokunulamaz) + altında sekiz düz açı çipi. HI-turu
/// bütün haritaları ortak `ChartWheel`e taşımıştı ama bu sayfa dışarıda
/// kalmış, yeni çark yalnız küçük bir "büyüt" bağlantısının arkasında
/// duruyordu. Cihaz bulgusu birebir buydu: "Atlas'tan Şu an gökyüzünde'ye
/// girince eski harita tasarımıyla karşılaşıyorum."
///
/// Artık sayfa doğum haritası analiziyle AYNI dili konuşuyor: ortak çark
/// (derece cetveli, orb-ağırlıklı açı ağı), gruplanmış açı listesi ve konum
/// tablosu. Gömülü çark SALT ÖNİZLEME (D6): dokunuş Harita İnceleme'yi
/// açar; gezegen/açı alt-sayfaları yalnız orada — aynı yüzeyde iki fiil
/// (gezegene dokun → alt-sayfa, altındaki düğme → İnceleme) bire indi.
/// Açı LİSTESİ satırı ise yine alt-sayfa açar: o satır tek bir açıyı
/// adlandırıyor, dayanağı bir dokunuş uzakta olmalı.
///
/// Değişmeyen doktrin: gökyüzü çarkı EVSİZDİR. Ev ve Yükselen konuma
/// bağlıdır; konumsuz gökyüzüne ev çizmek ölçülmemiş şeyi göstermek olurdu.
/// Çarkın altındaki not bunu söyler.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api.dart' show friendlyError;
import '../../core/providers.dart';
import '../../l10n/app_localizations.dart';
import '../../theme/rytho_theme.dart';
import '../../theme/rytho_tokens.dart';
import '../../widgets/atlas_widgets.dart';
import '../../widgets/chart/aci_lejanti.dart' show AciCizgiOrnegi;
import '../../widgets/chart/chart_data.dart';
import '../../widgets/chart/chart_palette.dart'
    show aspectColor, aspectDashFor;
import '../../widgets/chart/chart_positions.dart';
import '../../widgets/chart/chart_wheel.dart';
import '../../widgets/common.dart';
import '../../widgets/cosmic_scaffold.dart';
import '../../widgets/glass.dart';
import '../../widgets/nebula_widgets.dart' show InfoChip, Pressable;
import '../atlas/atlas_detail_screens.dart' show showAspectSheet;
import '../atlas/chart_inspector_screen.dart'
    show ChartInspectorMode, ChartInspectorScreen, aspectSheetMap, kCarkTavani;

/// Açı türü -> grup. Atlas'ın "Açılar" ekranıyla AYNI tasnif: kullanıcı iki
/// ekranda aynı açıyı aynı başlık altında bulmalı.
const Map<String, String> _kAspectGroup = {
  'conjunction': 'focus',
  'opposition': 'tension',
  'square': 'tension',
  'trine': 'flow',
  'sextile': 'flow',
};

class SkyNowScreen extends ConsumerWidget {
  const SkyNowScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final sky = ref.watch(skyNowProvider);

    return CosmicScaffold(
      appBar: AppBar(title: Text(l10n.skyNow)),
      body: SafeArea(
        child: sky.when(
          loading: () => const Center(child: AstrolabeSpinner()),
          error: (e, _) => Padding(
            padding: const EdgeInsets.all(RythoSpace.xl),
            child: ErrorCard(
              message: friendlyError(e, l10n),
              onRetry: () => ref.invalidate(skyNowProvider),
            ),
          ),
          data: (data) => _Govde(sky: data),
        ),
      ),
    );
  }
}

class _Govde extends StatelessWidget {
  const _Govde({required this.sky});

  final Map<String, dynamic> sky;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final veri = ChartData.fromSky(sky, label: l10n.chartLegendSkyNow);
    final retros = List<String>.from(sky['retrogrades'] ?? []);

    void incelemeyiAc() => Navigator.of(context).push(MaterialPageRoute(
        builder: (_) =>
            const ChartInspectorScreen(mode: ChartInspectorMode.sky)));

    // Gruplama + sıralama: en dar orb en güçlü açıdır, başta durur.
    final gruplar = <String, List<ChartAspect>>{
      'tension': [],
      'focus': [],
      'flow': [],
      'other': [],
    };
    for (final a in veri.aspects) {
      gruplar[_kAspectGroup[a.kind] ?? 'other']!.add(a);
    }
    for (final liste in gruplar.values) {
      liste.sort((x, y) => x.orb.abs().compareTo(y.orb.abs()));
    }

    Widget aciBolumu(String anahtar, String baslik) {
      final liste = gruplar[anahtar]!;
      if (liste.isEmpty) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.only(bottom: RythoSpace.md),
        child: GlassPanel(
          label: baslik,
          child: Column(children: [
            for (final a in liste) _AciSatiri(aspect: a),
          ]),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(
          RythoSpace.lg, RythoSpace.md, RythoSpace.lg, RythoSpace.xxl),
      children: [
        _AnSeridi(sky: sky),
        const SizedBox(height: RythoSpace.md),

        // ---------- Çark: Atlas'takiyle AYNI bileşen ----------
        GlassPanel(
          padding: const EdgeInsets.all(RythoSpace.sm),
          child: Column(children: [
            // Boyut GERÇEK kısıttan: `genişlik - 72` panelin kendi
            // dolgularını (liste 32 + kart kenarı 32 + iç 16 = 80) 8 px
            // eksik sayıyordu ve ClipRect çarkı sessizce kırpıyordu
            // (ölçüldü). LayoutBuilder dolgu varsayımını kaldırır.
            LayoutBuilder(builder: (context, kisit) {
              return Center(
                child: ChartWheel(
                  data: veri,
                  size: math.min(kisit.maxWidth, kCarkTavani),
                  interactive: false,
                  onTap: incelemeyiAc,
                ),
              );
            }),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 2, 10, 6),
              child: Text(l10n.atlasSkyWheelNote,
                  style: RythoText.body(11,
                      color: RythoColors.parchmentDim, height: 1.4)),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: incelemeyiAc,
                icon: const Icon(Icons.open_in_full_rounded, size: 15),
                label: Text(l10n.chartExpandTooltip,
                    style: RythoText.label(11, color: RythoColors.goldBright)),
              ),
            ),
          ]),
        ),
        const SizedBox(height: RythoSpace.md),

        // ---------- Retrolar ----------
        if (retros.isNotEmpty) ...[
          GlassPanel(
            label: l10n.retrogradeCount(retros.length),
            child: Wrap(
              spacing: RythoSpace.sm,
              runSpacing: 6,
              children: [
                for (final r in retros)
                  InfoChip(
                      text: '↩️ ${l10n.retrogradeChip(r)}',
                      color: RythoColors.magenta),
              ],
            ),
          ),
          const SizedBox(height: RythoSpace.md),
        ],

        // ---------- Açılar (natal analiziyle aynı tasnif) ----------
        aciBolumu('tension', l10n.aspectsGroupTension),
        aciBolumu('focus', l10n.aspectsGroupFocus),
        aciBolumu('flow', l10n.aspectsGroupFlow),
        aciBolumu('other', l10n.aspectsGroupOther),
        if (veri.aspects.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, RythoSpace.md),
            child: Text(l10n.aspectsSortNote, style: RythoType.caption),
          ),

        // ---------- Konum tablosu (çarkın erişilebilir temsili) ----------
        ChartPositionsTable(data: veri),
      ],
    );
  }
}

/// Ayın evresi ve ölçüm ANI — sayfanın dürüstlük şeridi.
class _AnSeridi extends StatelessWidget {
  const _AnSeridi({required this.sky});

  final Map<String, dynamic> sky;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final moon = sky['moon_phase'] as Map<String, dynamic>? ?? {};
    return GlassPanel(
      child: Row(children: [
        // Ay evresi BİLİNÇLİ renkli emoji (sunucu evre simgesini veriyor);
        // rol adı niyeti kodda görünür kılar — çıplak TextStyle değil.
        Text(moon['emoji'] as String? ?? '🌙', style: RythoText.emoji(34)),
        const SizedBox(width: RythoSpace.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${moon['name'] ?? ''}', style: RythoText.display(18)),
              const SizedBox(height: 2),
              Text(l10n.moonIllumination(moon['illumination'] ?? '—'),
                  style: RythoType.dataSmall),
              // Aydınlanma oranı ANA bağlıdır: bir gün içinde 10 puana kadar
              // değişir. Başka bir kaynakla kıyaslayanın ilk sorusu "hangi
              // ana ait?" oluyor — cevabı ekranda duruyor.
              if (moon['as_of_utc'] != null) ...[
                const SizedBox(height: 2),
                Text(
                    l10n.moonIlluminationAsOf(
                        _yerelAn('${moon['as_of_utc']}')),
                    style: RythoType.caption),
              ],
            ],
          ),
        ),
      ]),
    );
  }

  /// UTC ISO damgasını cihazın yerel saatinde "07.08 06:12" biçimine çevirir.
  static String _yerelAn(String iso) {
    final t = DateTime.tryParse(iso)?.toLocal();
    if (t == null) return '';
    String iki(int n) => n.toString().padLeft(2, '0');
    return '${iki(t.day)}.${iki(t.month)} ${iki(t.hour)}:${iki(t.minute)}';
  }
}

/// Tek açı satırı — dokununca dayanak alt-sayfası açılır.
///
/// Başta açı SINIFININ çizgi örneği (ressam ve lejantla aynı
/// `aspectDashFor`): renk noktası sınıfı yalnız renkle ayırıyordu, çarkta
/// çizilen düz/kesik dili satırda görünmüyordu.
class _AciSatiri extends StatelessWidget {
  const _AciSatiri({required this.aspect});

  final ChartAspect aspect;

  @override
  Widget build(BuildContext context) {
    final renk = aspectColor(aspect.kind);
    return Pressable(
      onTap: () => showAspectSheet(context, aspectSheetMap(aspect)),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Row(children: [
          Padding(
            padding: const EdgeInsets.only(right: RythoSpace.sm),
            child: AciCizgiOrnegi(
                dil: aspectDashFor(aspect.kind), renk: renk),
          ),
          Expanded(
            child: Text(
              '${aspect.p1Local ?? aspect.p1} '
              '${aspect.kindLocal ?? aspect.kind} '
              '${aspect.p2Local ?? aspect.p2}',
              style: RythoText.body(13.5),
            ),
          ),
          // Orb değeri esnemiyordu: soldaki açı cümlesi `Expanded` içinde
          // sıfıra inse bile derece + chevron dar ekranda taşıyordu.
          Flexible(
            child: Text('${aspect.orb.abs().toStringAsFixed(1)}°',
                style: RythoText.mono(11, color: RythoColors.lilac)),
          ),
          const SizedBox(width: 6),
          const Icon(Icons.chevron_right_rounded,
              size: 16, color: RythoColors.parchmentDim),
        ]),
      ),
    );
  }
}

/// Akıştaki tek satırlık özet — dokununca [SkyNowScreen] açar.
///
/// Gösterge uyumu: kart gibi görünüyor, kart gibi davranıyor, sağında chevron
/// var. "Görünüşü X, davranışı Y" sorunu tam olarak buradan doğuyordu.
class SkyNowSummary extends StatelessWidget {
  const SkyNowSummary({super.key, required this.sky});

  final Map<String, dynamic> sky;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final moon = sky['moon_phase'] as Map<String, dynamic>? ?? {};
    final retros = List<String>.from(sky['retrogrades'] ?? []);
    final aspects = List<Map<String, dynamic>>.from(sky['aspects'] ?? []);

    // Tek bir açı gösteriliyor: sekiz çipin hepsi bir bakışta okunmuyordu,
    // biri okunuyor.
    final oneCikan = aspects.isEmpty
        ? null
        : '${aspects.first['p1_local'] ?? aspects.first['p1']} '
            '${aspects.first['aspect_local'] ?? aspects.first['aspect']} '
            '${aspects.first['p2_local'] ?? aspects.first['p2']}';

    return GlassPanel(
      onTap: () => Navigator.of(context)
          .push(MaterialPageRoute(builder: (_) => const SkyNowScreen())),
      child: Row(
        children: [
          Text(moon['emoji'] as String? ?? '🌙', style: RythoText.emoji(26)),
          const SizedBox(width: RythoSpace.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${moon['name'] ?? ''} · '
                  '${l10n.moonIllumination(moon['illumination'] ?? '—')}',
                  style: RythoType.body,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  [
                    if (retros.isNotEmpty) l10n.retrogradeCount(retros.length),
                    ?oneCikan,
                  ].join(' · '),
                  style: RythoType.caption,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const Icon(Icons.chevron_right_rounded,
              size: 20, color: RythoColors.parchmentDim),
        ],
      ),
    );
  }
}
