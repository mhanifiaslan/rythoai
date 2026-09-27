import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/ai_consent.dart' show AiOnayKapaliKarti, aiOnayHatasiMi;
import '../../core/providers.dart';
import '../../theme/rytho_theme.dart';
import '../../widgets/atlas_widgets.dart';
import '../../widgets/frame_sequence.dart';
import '../../widgets/motion.dart';
import '../paywall/plus_locked_card.dart';
import '../../core/api.dart' show RaporUretilemedi, friendlyError;
import '../../widgets/common.dart' show ErrorCard;
import '../../l10n/app_localizations.dart';

/// BaZi — Dört Sütun tablosu, Day Master, element dağılımı, şans dönemleri.
class BaziTab extends ConsumerWidget {
  const BaziTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final bazi = ref.watch(baziReportProvider);

    return bazi.when(
      // Rapor LLM üretimi — bekleyiş uzun; sahne dört sütun diliyle (R12-B3).
      // Usturlap yerine bronz luopan kare dizisi (PBZ-K3): halkalar döner,
      // ibre titrer — BaZi'nin kendi aleti. Yalnız yüklenirken monte,
      // sonuçla sökülür; reduce-motion'da son kare statik.
      loading: () => StagedWaiting(
        visual: const Padding(
          padding: EdgeInsets.symmetric(horizontal: 24),
          child: AnimStage(
            child: FrameSequence(
                asset: 'assets/anim/bazi_wait.webp', loop: true),
          ),
        ),
        stages: [
          l10n.baziWaitStage1,
          l10n.baziWaitStage2,
          l10n.baziWaitStage3,
        ],
      ),
      // Duz metin CIKMAZ SOKAKTI: bu sekmede asagi cekme YOK, yani hatayi
      // goren kullanici uygulamayi yeniden acmak zorunda kaliyordu. ErrorCard
      // depodaki ortak desen (sky_screen, token_store_screen).
      error: (e, _) => Center(
        // U06: AI kapalıyken hata kartı değil onay kartı.
        child: aiOnayHatasiMi(e)
            ? const AiOnayKapaliKarti()
            : Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: ErrorCard(
                  message: friendlyError(e, l10n),
                  screen: 'oracle',
                  onRetry: () => ref.invalidate(baziReportProvider),
                ),
              ),
      ),
      data: (data) {
        if (data == null) {
          return PlusLockedCard(
            emoji: '🀄',
            title: l10n.baziLockedTitle,
            description: l10n.baziLockedBody,
            centered: true,
          );
        }
        final chart = Map<String, dynamic>.from(data['chart']);
        final pillars = Map<String, dynamic>.from(chart['pillars']);
        final elements =
            Map<String, dynamic>.from(chart['element_distribution']);
        final luck = List<Map<String, dynamic>>.from(chart['luck_pillars']);

        return ListView(
            padding: const EdgeInsets.only(top: 8, bottom: 110),
            children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(l10n.baziHeadline, style: RythoText.display(28)),
          ),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              l10n.baziChineseSign(chart['zodiac_animal'],
                  chart['day_master']['description']),
              style: RythoText.body(13, color: RythoColors.parchmentDim),
            ),
          ),
          Plaque(
            label: l10n.baziFourPillars,
            padding: const EdgeInsets.all(12),
            // IntrinsicHeight + stretch (Revize İ0): saatsiz doğumda "—"
            // sütunu dolu sütunlardan ~75 px kısa kalıyordu; fonta bağımlı
            // SizedBox dengeleyicisi yerine sütunlar birbirinin yüksekliğini
            // alıyor — CJK yedek font yüksekliği cihazdan cihaza değişse de
            // hiza bozulmaz.
            child: IntrinsicHeight(
                child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
              for (final (i, key) in [
                ('hour', l10n.baziPillarHour),
                ('day', l10n.baziPillarDay),
                ('month', l10n.baziPillarMonth),
                ('year', l10n.baziPillarYear),
              ].indexed)
                Expanded(
                  // Saat sütunu bilinmeyen doğumda null gelir (Revize B1):
                  // "—" gösterilir, uydurma bir öğle sütunu değil. Sebep
                  // beyan satırında (aşağıda `notes`).
                  child: _PillarColumn(
                    label: key.$2,
                    pillar: pillars[key.$1] == null
                        ? null
                        : Map<String, dynamic>.from(pillars[key.$1]),
                    // Gövdenin On Tanrısı (B9): gün gövdesi Day Master'ın
                    // kendisi — etiket almaz.
                    tenGod: key.$1 == 'day'
                        ? null
                        : (chart['ten_gods']?[key.$1]?['name'] as String?),
                    highlight: key.$1 == 'day',
                  )
                      .animate(delay: (i * 130).ms)
                      .fadeIn(duration: 380.ms)
                      .slideY(begin: 0.18, curve: Curves.easeOutCubic),
                ),
            ])),
          ),
          // ---------- GÜÇ HÜKMÜ (B3 → B9) ----------
          if (chart['strength'] != null)
            _StrengthPlaque(
              l10n: l10n,
              strength: Map<String, dynamic>.from(chart['strength']),
            ),
          // Hesap beyanları: TST dönüşümü, saatsiz mod, cinsiyet kuralı.
          // Sunucudan İSTEĞİN DİLİNDE hazır cümleler gelir (localize_bazi).
          if ((chart['notes'] as List?)?.isNotEmpty ?? false)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final not in chart['notes'] as List)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 3),
                      child: Text('• $not',
                          style: RythoText.body(11,
                              color: RythoColors.parchmentDim)),
                    ),
                ],
              ),
            ),
          Plaque(
            label: l10n.baziElementBalance,
            child: Column(children: [
              for (final e in elements.entries)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(children: [
                    SizedBox(
                        width: 64,
                        child: Text(e.key, style: RythoText.body(13))),
                    Expanded(
                      // Sekiz sabit genişlikli kutu esnemeyen bir `Row`daydı
                      // (8×17 = 136 px); büyük yazı ölçeğinde soldaki etiket
                      // ve sağdaki değer büyüyünce kutulara kalan yer
                      // yetmiyor ve satır taşıyordu. `Wrap` ölçek büyüdüğünde
                      // kutuları alt satıra indirir.
                      child: Wrap(children: [
                        // Dağılım B2'den beri gizli kök AĞIRLIKLI (float);
                        // kutu dolgusu yuvarlanmış değeri izler, tam değer
                        // sağda tek ondalıkla durur.
                        for (var i = 0; i < 8; i++)
                          Container(
                            width: 14,
                            height: 8,
                            margin: const EdgeInsets.only(right: 3),
                            decoration: BoxDecoration(
                              color: i < (e.value as num).round()
                                  ? RythoColors.gold
                                  : Colors.transparent,
                              border: Border.all(color: RythoColors.line),
                            ),
                          ),
                      ]),
                    ),
                    Flexible(
                      child: Text((e.value as num).toStringAsFixed(1),
                          style: RythoText.mono(12)),
                    ),
                  ]),
                ),
              if ((chart['missing_elements'] as List).isNotEmpty) ...[
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    l10n.baziNourish(
                        (chart['missing_elements'] as List).join(', ')),
                    style: RythoText.mono(11, color: RythoColors.copper),
                  ),
                ),
              ],
            ]),
          ),
          // ---------- YILDIZLAR (B4 → B9) ----------
          Plaque(
            label: l10n.baziStarsTitle,
            child: (chart['shen_sha'] as List?)?.isNotEmpty ?? false
                ? Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final y in chart['shen_sha'] as List)
                        Tooltip(
                          message: y['meaning'] ?? '',
                          triggerMode: TooltipTriggerMode.tap,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: RythoColors.gold.withValues(alpha: 0.10),
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(
                                  color:
                                      RythoColors.gold.withValues(alpha: 0.4)),
                            ),
                            child: Text('${y['name']} · ${y['pillar']}',
                                style: RythoText.body(11.5,
                                    color: RythoColors.goldBright)),
                          ),
                        ),
                    ],
                  )
                // Boş liste meşru sonuç — ve öyle SÖYLENİR; boş bir kutu
                // "veri gelmedi" okunurdu.
                : Text(l10n.baziNoStars,
                    style:
                        RythoText.body(12, color: RythoColors.parchmentDim)),
          ),
          Plaque(
            label: l10n.baziLuckPillars,
            padding: const EdgeInsets.all(8),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                children: [
              SizedBox(
                height: 104,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: luck.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 8),
                  itemBuilder: (_, i) {
                    final lp = luck[i];
                    // Aktif dönem vurgulanır (B5/B9): "şu an neredeyim"
                    // sorusu listeye bakarak cevaplanmamalı.
                    final aktif = chart['current_luck_index'] == i;
                    return Container(
                      width: 104,
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        border: Border.all(
                            color: aktif
                                ? RythoColors.gold
                                : RythoColors.line),
                        borderRadius: BorderRadius.circular(4),
                        color: aktif
                            ? RythoColors.gold.withValues(alpha: 0.06)
                            : null,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // FittedBox + maxLines 1: "1984-1993 · şimdi" 88
                          // px'lik karta sığmayıp ikinci satıra kırılıyor ve
                          // kartı ~2 px taşırıyordu (kullanıcının bildirdiği
                          // "bottom overflowed"). %95'lik görünmez ölçekleme,
                          // metni kırdırmadan sığdırır ve textScaler'a da
                          // dayanıklıdır (Revize İ0).
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Text(
                                '${lp['from_year']}-${lp['to_year']}'
                                '${aktif ? ' · ${l10n.baziCurrentTag}' : ''}',
                                maxLines: 1,
                                style: RythoText.mono(10,
                                    color: aktif
                                        ? RythoColors.goldBright
                                        : RythoColors.parchmentDim)),
                          ),
                          Text(l10n.baziAgeRange(lp['from_age'], lp['to_age']),
                              style: RythoText.mono(9,
                                  color: RythoColors.parchmentDim)),
                          const SizedBox(height: 2),
                          Text(
                              '${lp['stem']['cn']}${lp['branch']['cn']}',
                              style: RythoText.display(20)),
                          const Spacer(),
                          Text(lp['ten_god']['name'],
                              style: RythoText.body(10.5,
                                  color: RythoColors.parchmentDim),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis),
                        ],
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 8),
              if (chart['luck_start'] != null)
                Text(
                    l10n.baziLuckStartLabel(
                        chart['luck_start']['years'] as int,
                        chart['luck_start']['months'] as int,
                        chart['luck_start']['date'] as String),
                    style: RythoText.mono(10.5,
                        color: RythoColors.parchmentDim)),
              if (chart['current_year_pillar'] != null)
                Text(
                    l10n.baziThisYear(
                        chart['current_year_pillar']['label'] as String,
                        chart['current_year_pillar']['ten_god']?['name']
                                as String? ??
                            ''),
                    style: RythoText.mono(10.5,
                        color: RythoColors.parchmentDim)),
            ]),
          ),
          const SectionDivider(),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            // Yorum uretilemediyse (gz-2) HARITA YERINDE KALIR, yalniz bu
            // kalem durust cumleye doner. Ustteki her sey deterministik
            // hesap ve ucreti odendi; LLM paragrafi dustu diye onu da
            // silmek "olculeni soyle" doktrinini tersine cevirmek olurdu.
            // `screen` kapali kumeden ('bazi' sessizce dusurulurdu).
            child: data['fallback'] == true
                ? ErrorCard(
                    message: friendlyError(
                        RaporUretilemedi(
                            jetonIadeEdildi: data['refunded'] == true),
                        l10n),
                    screen: 'oracle',
                    onRetry: () => ref.invalidate(baziReportProvider),
                  )
                : MarginNote(
                    title: l10n.baziFateNote, text: data['report'] ?? ''),
          ),
          const SizedBox(height: 32),
        ]);
      },
    );
  }
}

class _PillarColumn extends StatelessWidget {
  const _PillarColumn(
      {required this.label,
      required this.pillar,
      this.tenGod,
      this.highlight = false});
  final String label;

  /// null = sütun HESAPLANMADI (doğum saati bilinmiyor). "—" gösterilir;
  /// boş harita kutusu "veri gelmedi" okunurdu, "—" ise "ölçülmedi" diyor.
  final Map<String, dynamic>? pillar;

  /// Gövdenin On Tanrısı (B9); gün sütunu Day Master olduğu için null.
  final String? tenGod;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final p = pillar;
    if (p == null) {
      // Yükseklik IntrinsicHeight + stretch'ten geliyor (İ0): dolu
      // sütunlarla aynı boy; "—" içeriği ortada durur, fonta bağımlı
      // SizedBox dengeleyicisi kalktı.
      return Container(
        margin: const EdgeInsets.symmetric(horizontal: 3),
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          border: Border.all(color: RythoColors.line),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Column(children: [
          Text(label,
              style: RythoText.mono(9, color: RythoColors.parchmentDim)),
          const Spacer(),
          Text('—',
              style:
                  RythoText.display(24, color: RythoColors.parchmentDim)),
          const Spacer(),
        ]),
      );
    }
    final stem = Map<String, dynamic>.from(p['stem']);
    final branch = Map<String, dynamic>.from(p['branch']);
    // Gizli kökler (B2 → B9): dalın içindeki gövdeler, ana qi önce.
    final hidden = (branch['hidden'] as List?)
            ?.map((h) => h['pinyin'] as String)
            .join('·') ??
        '';
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 3),
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        border: Border.all(
            color: highlight ? RythoColors.gold : RythoColors.line),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(children: [
        Text(label, style: RythoText.mono(9, color: RythoColors.parchmentDim)),
        const SizedBox(height: 4),
        Text(tenGod ?? ' ',
            style: RythoText.mono(8.5, color: RythoColors.lilac),
            maxLines: 1,
            overflow: TextOverflow.ellipsis),
        const SizedBox(height: 2),
        Text(stem['cn'], style: RythoText.display(24, color: RythoColors.goldBright)),
        Text(stem['element'],
            style: RythoText.body(10, color: RythoColors.parchmentDim)),
        const SizedBox(height: 6),
        Text(branch['cn'], style: RythoText.display(24)),
        Text(branch['animal'],
            style: RythoText.body(10, color: RythoColors.parchmentDim)),
        if (hidden.isNotEmpty) ...[
          const SizedBox(height: 3),
          Text(hidden,
              style: RythoText.mono(8, color: RythoColors.parchmentDim),
              maxLines: 1,
              overflow: TextOverflow.ellipsis),
        ],
      ]),
    );
  }
}

/// Güç hükmü plaketi (B9): hüküm + oran çubuğu + yararlı elementler +
/// dayanağın en ağır kalemleri. "Neden bu hüküm?" sorusunun cevabı
/// ekranda durur — sunucu bileşen dökümünü tam veriyor, biz okunur ilk
/// üçünü gösteriyoruz.
class _StrengthPlaque extends StatelessWidget {
  const _StrengthPlaque({required this.l10n, required this.strength});
  final AppLocalizations l10n;
  final Map<String, dynamic> strength;

  /// Kompakt kaynak kodunu okunur cümleye çevirir.
  /// "month_command" · "root:day:Ren" · "stem:year:Wu" biçimleri geliyor.
  String _kaynak(String source) {
    if (source == 'month_command') return l10n.baziSrcMonthCommand;
    final parca = source.split(':');
    if (parca.length == 3) {
      final sutun = switch (parca[1]) {
        'year' => l10n.baziPillarYear,
        'month' => l10n.baziPillarMonth,
        'day' => l10n.baziPillarDay,
        'hour' => l10n.baziPillarHour,
        _ => parca[1],
      };
      return parca[0] == 'root'
          ? l10n.baziSrcRoot(sutun, parca[2])
          : l10n.baziSrcStem(sutun, parca[2]);
    }
    return source;
  }

  @override
  Widget build(BuildContext context) {
    final oran = (strength['ratio'] as num?)?.toDouble() ?? 0.5;
    final bilesenler =
        List<Map<String, dynamic>>.from(strength['components'] ?? const []);
    return Plaque(
      label: l10n.baziStrengthTitle,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Hüküm adı + mevsim durumu sunucudan gelir ve ikisi de
        // esnemiyordu; 22 punto ad + parantezli durum dar ekranda satırı
        // taşırıyordu. `Wrap` sığmayanı alt satıra indirir.
        Wrap(
          spacing: 8,
          runSpacing: 2,
          crossAxisAlignment: WrapCrossAlignment.end,
          children: [
            Text(strength['verdict_name'] ?? '',
                style: RythoText.display(22, color: RythoColors.goldBright)),
            Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: Text('(${strength['season_state_name'] ?? ''})',
                  style:
                      RythoText.body(12, color: RythoColors.parchmentDim)),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: LinearProgressIndicator(
                value: oran,
                minHeight: 4,
                backgroundColor: RythoColors.line,
                valueColor:
                    const AlwaysStoppedAnimation(RythoColors.gold),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text('${l10n.baziRatioLabel} ${(oran * 100).round()}%',
              style: RythoText.mono(10, color: RythoColors.parchmentDim)),
        ]),
        const SizedBox(height: 10),
        if ((strength['favorable_names'] as List?)?.isNotEmpty ?? false)
          Text(
              '${l10n.baziFavorable}: '
              '${(strength['favorable_names'] as List).join(', ')}',
              style: RythoText.body(12.5)),
        if ((strength['unfavorable_names'] as List?)?.isNotEmpty ?? false)
          Text(
              '${l10n.baziUnfavorable}: '
              '${(strength['unfavorable_names'] as List).join(', ')}',
              style:
                  RythoText.body(12, color: RythoColors.parchmentDim)),
        if (strength['climate_element_name'] != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
                l10n.baziClimateNote(
                    strength['climate_element_name'] as String),
                style: RythoText.body(12, color: RythoColors.copper)),
          ),
        if (bilesenler.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text(l10n.baziBasisTitle,
              style: RythoText.label(10, color: RythoColors.parchmentDim)),
          const SizedBox(height: 4),
          for (final c in bilesenler.take(3))
            Text(
                '${c['side'] == 'support' ? '+' : '−'}'
                '${c['points']}  ${_kaynak(c['source'] as String? ?? '')}',
                style: RythoText.mono(10.5,
                    color: c['side'] == 'support'
                        ? RythoColors.parchment
                        : RythoColors.parchmentDim)),
        ],
      ]),
    );
  }
}
