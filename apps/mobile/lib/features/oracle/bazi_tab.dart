import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api.dart' show friendlyError;
import '../../core/okuma_durumu.dart';
import '../../core/providers.dart';
import '../../l10n/app_localizations.dart';
import '../../theme/rytho_theme.dart';
import '../../theme/rytho_tokens.dart';
import '../../widgets/atlas_widgets.dart';
import '../../widgets/common.dart' show ErrorCard;
import '../../widgets/frame_sequence.dart';
import '../../widgets/glass.dart';
import '../../widgets/motion.dart';
import '../../widgets/okuma_kabi.dart';
import '../chat/chat_screen.dart';
import '../paywall/bedel_onayi.dart';
import '../paywall/ozellik_katalogu.dart';
import '../paywall/plus_locked_card.dart';

/// BaZi — Dört Sütun tablosu, Day Master, element dağılımı, şans dönemleri.
class BaziTab extends ConsumerWidget {
  const BaziTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    // ÜÇ DURUMLU kapı (P2): sağlayıcının `null`ı artık YALNIZ "abone
    // değil" demek. Cevap gelmeden kilit çizmek, ödemiş kullanıcıya her
    // girişte "abone değilsin" demekti — ve `loading:` dalı o pencerede
    // hiç koşmuyordu, çünkü sağlayıcı `AsyncData(null)` ile TAMAMLANIYOR.
    //
    // Ne kilit ne harita: ikisi de bir hüküm ve o hüküm henüz yok. Bekleyiş
    // sahnesi (`StagedWaiting` + luopan) de KULLANILMIYOR — o sahne "şu an
    // senin için hesaplanıyor" diyor ve hiçbir istek atılmamışken yalan
    // olurdu. Bloklar dört sütun tablosunun gerçek hacmini taklit ediyor.
    final kapi = ref.watch(raporKapisiProvider);
    if (kapi == PlusHali.bilinmiyor) {
      return const SkeletonList(heights: [72, 160, 110]);
    }
    // Bedel kapısı (D7): sağlayıcı kapının İÇİNDE izlenir — 5 kredilik
    // üretim sekmeye girildiği an değil, ilk "Devam"dan sonra başlar
    // (`bedel_onayi.dart`).
    return BedelKapisi(
      ozellik: PlusOzellik.bazi,
      builder: (context, ref) => ref.watch(baziReportProvider).when(
      // Rapor LLM üretimi — bekleyiş uzun; sahne dört sütun diliyle (R12-B3).
      // Usturlap yerine bronz luopan kare dizisi (PBZ-K3): halkalar döner,
      // ibre titrer — BaZi'nin kendi aleti. Yalnız yüklenirken monte,
      // sonuçla sökülür; reduce-motion'da son kare statik.
      loading: () => StagedWaiting(
        visual: const Padding(
          padding: EdgeInsets.symmetric(horizontal: RythoSpace.xl),
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
        child: ErrorCard(
          message: friendlyError(e, l10n),
          screen: 'oracle',
          onRetry: () => ref.invalidate(baziReportProvider),
        ),
      ),
      data: (data) {
        if (data == null) {
          const ozellik = PlusOzellik.bazi;
          return PlusLockedCard(
            ozellik: ozellik,
            title: ozellik.baslik(l10n),
            description: ozellik.kilitGovdesi(l10n),
            centered: true,
          );
        }
        final chart = Map<String, dynamic>.from(data['chart']);
        final pillars = Map<String, dynamic>.from(chart['pillars']);
        final elements =
            Map<String, dynamic>.from(chart['element_distribution']);
        // Hoşgörülü ayrıştırma (Yıl Haritası emsali): yön bilinmeyen
        // doğumda `luck_pillars` BOŞ gelir, eski sunucuda alan hiç
        // gelmeyebilir — sert cast sekmenin TAMAMINI çökertiyordu.
        final luck = List<Map<String, dynamic>>.from(
            (chart['luck_pillars'] as List?) ?? const []);
        final eksikElementler =
            (chart['missing_elements'] as List?) ?? const [];
        final gun = pillars['day'] == null
            ? null
            : Map<String, dynamic>.from(pillars['day']);

        // Şans yönü ÖLÇÜLMEDİYSE (cinsiyet belirtilmedi) sunucu iki adayı
        // `luck_pillar_candidates` altında yollar; bugüne kadar okuyucusu
        // yoktu ve sekme 104 px'lik BOŞ bir şerit çiziyordu — beyansız.
        final yonBilinmiyor = chart['luck_direction_known'] == false;
        final adaylarHam = chart['luck_pillar_candidates'];
        final adaylar = <List<Map<String, dynamic>>>[
          if (adaylarHam is Map)
            for (final yon in const ['forward', 'backward'])
              if (adaylarHam[yon] is Map)
                List<Map<String, dynamic>>.from(
                    ((adaylarHam[yon] as Map)['luck_pillars'] as List?) ??
                        const []),
        ];

        // Paylaşım rozetleri ÖLÇÜLMÜŞ kalemler: gün sütunu ve güç hükmü.
        final rozetler = <(String, String)>[
          if (gun != null)
            (l10n.baziPillarDay, '${gun['stem']['cn']}${gun['branch']['cn']}'),
          if (chart['strength']?['verdict_name'] is String)
            (l10n.baziStrengthTitle, chart['strength']['verdict_name']),
        ];

        return ListView(
            padding: const EdgeInsets.only(
                top: RythoSpace.sm, bottom: RythoSpace.dockClearance),
            children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: RythoSpace.lg),
            child: Text(l10n.baziHeadline, style: RythoType.hero),
          ),
          const SizedBox(height: RythoSpace.xs),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: RythoSpace.lg),
            child: Text(
              l10n.baziChineseSign(chart['zodiac_animal'],
                  chart['day_master']['description']),
              style: RythoText.body(13, color: RythoColors.parchmentDim),
            ),
          ),
          // ⚠️ OKUMA ÖNDE, ÖLÇÜM ARKADA (sahip kararı, lifestyle turu).
          //
          // Ekran başlıktan sonra DOĞRUDAN dört sütun tablosuna giriyordu;
          // kader notu (insan cümlesi) altı bloğun arkasında, sayfanın en
          // sonundaydı. Üstteki iki satır (başlık + "Çin burcun") KALDI
          // çünkü onlar ölçüm değil AD — konunun kendisi.
          //
          // Kap `OkumaKabi`: yorum üretilemediyse HARİTA YERİNDE KALIR
          // (aşağıda), yalnız bu kalem dürüst cümleye döner — hesabın
          // ücreti ödendi, LLM paragrafı düştü diye onu da silmek "ölçüleni
          // söyle"yi tersine çevirmek olurdu. Bayrağı okuyan tek nokta
          // `okumaDurumuFromYanit`; eski elle `fallback ? ErrorCard :
          // MarginNote` dalı bu kabın içinde. `screen` kapalı kümeden
          // ('bazi' sessizce düşürülürdü).
          const SizedBox(height: RythoSpace.md),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: RythoSpace.lg),
            child: OkumaKabi(
              durum: okumaDurumuFromYanit(data),
              ekranKodu: 'oracle',
              baslik: l10n.baziFateNote,
              onTekrarDene: () => ref.invalidate(baziReportProvider),
              onSor: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) =>
                      ChatScreen(initialText: l10n.baziAskPrefill))),
              paylasim: PaylasimTarifi(
                title: l10n.baziHeadline,
                dateLabel: bugununEtiketi(),
                badges: rozetler,
                glyph: PlusOzellik.bazi.emoji,
              ),
            ),
          ),
          const SectionDivider(),
          GlassPanel(
            label: l10n.baziFourPillars,
            padding: const EdgeInsets.all(RythoSpace.md),
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
                  // Sütunlar kademeli belirir (tek stagger, reduce-motion
                  // kapılı). Saat sütunu bilinmeyen doğumda null gelir
                  // (Revize B1): "—" gösterilir, uydurma bir öğle sütunu
                  // değil. Sebep beyan satırında (aşağıda `notes`).
                  child: RythoReveal(
                    index: i,
                    slide: 0.18,
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
                    ),
                  ),
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
              padding: const EdgeInsets.fromLTRB(
                  RythoSpace.lg, RythoSpace.xs, RythoSpace.lg, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final not in chart['notes'] as List)
                    Padding(
                      padding: const EdgeInsets.only(bottom: RythoSpace.xxs),
                      child: Text('• $not',
                          style: RythoText.body(11,
                              color: RythoColors.parchmentDim)),
                    ),
                ],
              ),
            ),
          GlassPanel(
            label: l10n.baziElementBalance,
            child: Column(children: [
              for (final e in elements.entries)
                Padding(
                  padding:
                      const EdgeInsets.symmetric(vertical: RythoSpace.xs),
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
              if (eksikElementler.isNotEmpty) ...[
                const SizedBox(height: RythoSpace.sm),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    l10n.baziNourish(eksikElementler.join(', ')),
                    style: RythoText.mono(11, color: RythoColors.copper),
                  ),
                ),
              ],
            ]),
          ),
          // ---------- YILDIZLAR (B4 → B9) ----------
          GlassPanel(
            label: l10n.baziStarsTitle,
            child: (chart['shen_sha'] as List?)?.isNotEmpty ?? false
                ? Wrap(
                    spacing: RythoSpace.sm,
                    runSpacing: RythoSpace.sm,
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
                              borderRadius:
                                  BorderRadius.circular(RythoRadius.pill),
                              border: Border.all(
                                  color:
                                      RythoColors.gold.withValues(alpha: 0.4)),
                            ),
                            // `pillar` sunucudan makine anahtarı gelir
                            // (bazi_stars.py); çevrilmeden basılınca TR
                            // arayüzde "Tao Hua · day" kalıyordu.
                            child: Text(
                                '${y['name']} · '
                                '${baziSutunAdi(l10n, '${y['pillar']}')}',
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
          GlassPanel(
            label: l10n.baziLuckPillars,
            padding: const EdgeInsets.all(RythoSpace.sm),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                children: [
              if (yonBilinmiyor) ...[
                // Beyan: yön hesaplanmadı. Boş bir şerit "veri gelmedi"
                // okunurdu; iki aday "iki olası yol" diye gösterilir,
                // yorumlanmaz (hangisi olduğu bilinmiyor, biri seçilmez).
                Text(l10n.baziLuckDirectionUnknown,
                    style: RythoText.body(11.5, color: RythoColors.copper)),
                if (adaylar.isNotEmpty) ...[
                  const SizedBox(height: RythoSpace.sm),
                  Text(l10n.baziLuckCandidatesLabel, style: RythoType.label),
                  for (final dizi in adaylar) ...[
                    const SizedBox(height: RythoSpace.xs),
                    _SansSeridi(l10n: l10n, luck: dizi, aktifIndex: null),
                  ],
                ],
              ] else if (luck.isNotEmpty)
                _SansSeridi(
                    l10n: l10n,
                    luck: luck,
                    aktifIndex: chart['current_luck_index'] as int?),
              const SizedBox(height: RythoSpace.sm),
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
          const SizedBox(height: RythoSpace.xxl),
        ]);
      },
      ),
    );
  }
}

/// Şans dönemleri şeridi: yatay kartlar, aktif dönem vurgulu.
///
/// Ayrı widget çünkü yön bilinmeyen doğumda AYNI şerit iki aday dizi için
/// iki kez çiziliyor; [aktifIndex] o hâlde null — hangi dizinin gerçek
/// olduğu bilinmezken "şimdi" etiketi basılamaz.
class _SansSeridi extends StatelessWidget {
  const _SansSeridi(
      {required this.l10n, required this.luck, required this.aktifIndex});

  final AppLocalizations l10n;
  final List<Map<String, dynamic>> luck;
  final int? aktifIndex;

  @override
  Widget build(BuildContext context) {
    // Yatay liste sınırlı yükseklik ister; 104 px 1,0 ölçeğin ölçüsü ve
    // kartın dört satırı büyük yazıda (1,3) 2,9 px taşıyordu (ölçüldü,
    // 320 dp). Sabit yazıyla büyür: 1,0'da aynı kart, 1,3'te 135 px.
    final yukseklik = MediaQuery.textScalerOf(context).scale(104);
    return SizedBox(
      height: yukseklik,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: luck.length,
        separatorBuilder: (_, _) => const SizedBox(width: RythoSpace.sm),
        itemBuilder: (_, i) {
          final lp = luck[i];
          // Aktif dönem vurgulanır (B5/B9): "şu an neredeyim" sorusu
          // listeye bakarak cevaplanmamalı.
          final aktif = aktifIndex == i;
          return Container(
            width: 104,
            padding: const EdgeInsets.all(RythoSpace.sm),
            decoration: BoxDecoration(
              border: Border.all(
                  color: aktif ? RythoColors.gold : RythoColors.line),
              borderRadius: BorderRadius.circular(RythoRadius.xs),
              color: aktif ? RythoColors.gold.withValues(alpha: 0.06) : null,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // FittedBox + maxLines 1: "1984-1993 · şimdi" 88 px'lik
                // karta sığmayıp ikinci satıra kırılıyor ve kartı ~2 px
                // taşırıyordu (kullanıcının bildirdiği "bottom overflowed").
                // %95'lik görünmez ölçekleme, metni kırdırmadan sığdırır ve
                // textScaler'a da dayanıklıdır (Revize İ0).
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
                    style:
                        RythoText.mono(9, color: RythoColors.parchmentDim)),
                const SizedBox(height: RythoSpace.xxs),
                Text('${lp['stem']['cn']}${lp['branch']['cn']}',
                    style: RythoText.display(20)),
                const Spacer(),
                Text(lp['ten_god']?['name'] ?? '',
                    style: RythoText.body(10.5,
                        color: RythoColors.parchmentDim),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
              ],
            ),
          );
        },
      ),
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
          borderRadius: BorderRadius.circular(RythoRadius.xs),
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
        borderRadius: BorderRadius.circular(RythoRadius.xs),
      ),
      child: Column(children: [
        Text(label, style: RythoText.mono(9, color: RythoColors.parchmentDim)),
        const SizedBox(height: RythoSpace.xs),
        Text(tenGod ?? ' ',
            style: RythoText.mono(8.5, color: RythoColors.lilac),
            maxLines: 1,
            overflow: TextOverflow.ellipsis),
        const SizedBox(height: RythoSpace.xxs),
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

/// Sunucunun sütun anahtarını ("year" · "month" · "day" · "hour") dört
/// sütun tablosunun başlığıyla adlandırır — yıldız yongası ve hüküm
/// dayanağı aynı sütunu tablodaki adıyla anar. Bilinmeyen anahtar olduğu
/// gibi döner: yeni bir sütun türü sessizce yutulmasın.
String baziSutunAdi(AppLocalizations l10n, String anahtar) =>
    switch (anahtar) {
      'year' => l10n.baziPillarYear,
      'month' => l10n.baziPillarMonth,
      'day' => l10n.baziPillarDay,
      'hour' => l10n.baziPillarHour,
      _ => anahtar,
    };

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
      final sutun = baziSutunAdi(l10n, parca[1]);
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
    return GlassPanel(
      label: l10n.baziStrengthTitle,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Hüküm adı + mevsim durumu sunucudan gelir ve ikisi de
        // esnemiyordu; 22 punto ad + parantezli durum dar ekranda satırı
        // taşırıyordu. `Wrap` sığmayanı alt satıra indirir.
        Wrap(
          spacing: RythoSpace.sm,
          runSpacing: RythoSpace.xxs,
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
        const SizedBox(height: RythoSpace.sm),
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
          const SizedBox(width: RythoSpace.sm),
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
            padding: const EdgeInsets.only(top: RythoSpace.xs),
            child: Text(
                l10n.baziClimateNote(
                    strength['climate_element_name'] as String),
                style: RythoText.body(12, color: RythoColors.copper)),
          ),
        if (bilesenler.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text(l10n.baziBasisTitle,
              style: RythoText.label(10, color: RythoColors.parchmentDim)),
          const SizedBox(height: RythoSpace.xs),
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
