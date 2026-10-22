import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/ai_consent.dart' show AiOnayKapaliKarti, aiOnayHatasiMi;
import '../../core/api.dart' show friendlyError;
import '../../core/okuma_durumu.dart';
import '../../core/providers.dart';
import '../../l10n/app_localizations.dart';
import '../../theme/rytho_theme.dart';
import '../../theme/rytho_tokens.dart';
import '../../widgets/atlas_widgets.dart';
import '../../widgets/common.dart' show ErrorCard;
import '../../widgets/cosmic_scaffold.dart';
import '../../widgets/glass.dart';
import '../../widgets/motion.dart';
import '../../widgets/okuma_kabi.dart';
import '../chat/chat_screen.dart';
import '../paywall/bedel_onayi.dart';
import '../paywall/ozellik_katalogu.dart';
import '../paywall/plus_locked_card.dart';

/// Doğum Heksagramı ekranı (Revize İ5): doğum anındaki Güneş'in 64 kapı
/// çarkındaki yeri — çekim değil, kalıcı kimlik katmanı. Saatsiz doğumda
/// iki adaylı sınır beyanı gösterilir; kesinlik iddia edilmez.
class BirthHexagramScreen extends ConsumerWidget {
  const BirthHexagramScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    // ÜÇ DURUMLU kapı (P2): sağlayıcının `null`ı artık YALNIZ "abone değil"
    // demek. Cevap gelmeden kilit çizmek, ödemiş kullanıcıya her girişte
    // "abone değilsin" demekti.
    final kapi = ref.watch(raporKapisiProvider);
    if (kapi == PlusHali.bilinmiyor) {
      return CosmicScaffold(
        appBar: AppBar(title: Text(l10n.birthHexagramTitle)),
        // Ne kilit ne içerik: ikisi de bir hüküm ve o hüküm henüz yok.
        body: const SkeletonList(),
      );
    }
    return CosmicScaffold(
      appBar: AppBar(title: Text(l10n.birthHexagramTitle)),
      // Bedel kapısı (D7): 5 kredilik üretim ekrana GİRİLDİĞİ AN
      // başlıyordu. Sağlayıcı artık kapının İÇİNDE izleniyor — istek ilk
      // "Devam"dan sonra gider (`bedel_onayi.dart`); abone olmayana ve
      // eşik altı bedele kapı görünmez.
      body: BedelKapisi(
        ozellik: PlusOzellik.birthHexagram,
        builder: (context, ref) => ref.watch(birthHexagramProvider).when(
        // Dört kardeş ekran sahneli bekliyor, burası çıplak usturlaptı;
        // okuma LLM üretimi ve bekleyiş aynı uzunlukta.
        loading: () => StagedWaiting(stages: [
          l10n.birthHexagramWaitStage1,
          l10n.birthHexagramWaitStage2,
        ]),
        // Çıplak metin ÇIKMAZ SOKAKTI: bu sayfada aşağı çekme yok, hatayı
        // gören kullanıcı geri dönüp yeniden girmek zorundaydı.
        error: (e, _) => Center(
          // U06: AI kapalıyken hata kartı değil, tek dokunuşla onay
          // sayfasını açan kart — reddetmek bir arıza değil, kararın kendisi.
          child: aiOnayHatasiMi(e)
              ? const AiOnayKapaliKarti()
              : ErrorCard(
                  message: friendlyError(e, l10n),
                  screen: 'atlas',
                  onRetry: () => ref.invalidate(birthHexagramProvider),
                ),
        ),
        data: (data) {
          if (data == null) {
            const ozellik = PlusOzellik.birthHexagram;
            return PlusLockedCard(
              ozellik: ozellik,
              title: ozellik.baslik(l10n),
              description: ozellik.kilitGovdesi(l10n),
              centered: true,
            );
          }
          final konum = Map<String, dynamic>.from(data['position']);
          final hexagram = Map<String, dynamic>.from(data['hexagram']);
          final alternatif = data['alternate_hexagram'] != null
              ? Map<String, dynamic>.from(data['alternate_hexagram'])
              : null;
          final cizgi = konum['line'] as int?;
          final kapiAdi =
              '${hexagram['name_local'] ?? hexagram['name_tr']}';

          return ListView(
              padding: const EdgeInsets.only(
                  top: RythoSpace.sm, bottom: RythoSpace.dockClearance),
              children: [
                RythoReveal(
                  index: 0,
                  child: GlassPanel(
                    label: cizgi != null
                        ? l10n.birthHexagramGateLine(
                            konum['gate'] as int, cizgi)
                        : l10n.birthHexagramGateOnly(konum['gate'] as int),
                    child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          // Tek başına duran glif: glif rolü, çıplak
                          // `TextStyle` değil (Android'de emoji fontuna
                          // düşmesin).
                          Text(hexagram['unicode'] ?? '',
                              style: RythoText.glyph(56,
                                  color: RythoColors.goldBright)),
                          const SizedBox(width: RythoSpace.lg),
                          Expanded(
                            child: Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                children: [
                                  Text(kapiAdi, style: RythoType.heroSmall),
                                  Text(
                                      '${hexagram['name']} ${hexagram['name_cn']}',
                                      style: RythoText.body(12.5,
                                          color: RythoColors.parchmentDim)),
                                ]),
                          ),
                        ]),
                  ),
                ),
                // ⚠️ AD ÖNDE KALDI, ÖLÇÜM ARKAYA GİTTİ — ayrım bilinçli.
                //
                // Lifestyle turunda diğer dört ekranda okuma en başa alındı;
                // burada glif panelı önde BIRAKILDI çünkü glif + kapının adı
                // bir ÖLÇÜM DEĞİL, konunun KENDİSİ: kullanıcı "kapım hangisi"
                // diye giriyor ve 56 px'lik glif bu sayfanın yüzü. Teknik
                // olan şey panelin İÇİNDEKİ mono boylam satırıydı
                // (`birthHexagramSunAt`) — o aşağıdaki dayanak bölümüne
                // taşındı. Yani kaldırılan şey ad değil ÖLÇÜM.
                //
                // Sıra: kapının adı → bugünün okuması → kalıcı kapı dokusu →
                // dayanak (boylam + sınır) → klasik kaynak metinleri.
                // "Bugün" önce geliyor çünkü kullanıcı bu ekranı bugün açtı;
                // kalıcı doku onun arkasında, çünkü o her gün aynı.
                //
                // Kap `OkumaKabi`: `fallback` bayrağı tek noktadan okunur,
                // şablon paylaşılamaz. Eski hâl bayrağı hiç okumuyordu.
                RythoReveal(
                  index: 1,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: RythoSpace.lg),
                    child: OkumaKabi(
                      durum: okumaDurumuFromYanit(data),
                      ekranKodu: 'atlas',
                      baslik: l10n.birthHexagramNote,
                      onTekrarDene: () =>
                          ref.invalidate(birthHexagramProvider),
                      onSor: () => Navigator.of(context).push(
                          MaterialPageRoute(
                              builder: (_) => ChatScreen(
                                  initialText:
                                      l10n.birthHexagramAskPrefill))),
                      paylasim: PaylasimTarifi(
                        title: l10n.birthHexagramTitle,
                        dateLabel: bugununEtiketi(),
                        // Rozet ölçülmüş olan: kapının numarası ve adı.
                        badges: [
                          (
                            l10n.birthHexagramGateOnly(konum['gate'] as int),
                            kapiAdi
                          ),
                        ],
                        glyph: PlusOzellik.birthHexagram.emoji,
                      ),
                    ),
                  ),
                ),
                // Kapının Dokusu (İ8): Rytho'nun kapıya özgü karakter
                // aktarımı — gölgesiyle birlikte. Her gün aynı: ölçülmüş
                // sabit çekirdek, bugüne ait olan değil.
                if ((data['gate_text'] as String?)?.isNotEmpty ?? false)
                  RythoReveal(
                    index: 2,
                    child: GlassPanel(
                      label: l10n.birthHexagramGatePassage,
                      child: Text(data['gate_text'] as String,
                          style: RythoText.body(14,
                              color: RythoColors.parchment)),
                    ),
                  ),
                const RythoReveal(index: 3, child: SectionDivider()),
                // Dayanak: Güneş'in boylamı ve — gerekiyorsa — sınır beyanı.
                // Glif panelinden buraya indi; "bilginin geldiği yer"
                // okumanın ALTINDA durur (sahibin istediği sıra).
                RythoReveal(
                  index: 4,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(
                        RythoSpace.lg, 0, RythoSpace.lg, RythoSpace.xs),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                              l10n.birthHexagramSunAt(
                                  '${konum['longitude']}'),
                              style: RythoText.mono(10.5,
                                  color: RythoColors.parchmentDim)),
                          // Sınır beyanı: saatsiz doğumda kapı kesin
                          // bildirilemezse İKİ aday da söylenir — kesinlik
                          // yanılsaması yok.
                          if (alternatif != null) ...[
                            const SizedBox(height: RythoSpace.xs),
                            Text(
                                l10n.birthHexagramBoundary(
                                    konum['gate'] as int,
                                    konum['alternate_gate'] as int),
                                style: RythoText.body(11.5,
                                    color: RythoColors.copper)),
                          ],
                        ]),
                  ),
                ),
                RythoReveal(
                  index: 5,
                  child: GlassPanel(
                    label: l10n.iChingJudgmentTitle,
                    child: Text(hexagram['judgment'] ?? '',
                        style: RythoText.body(14,
                            color: RythoColors.parchment)),
                  ),
                ),
                RythoReveal(
                  index: 6,
                  child: GlassPanel(
                    label: l10n.iChingImageTitle,
                    child: Text(hexagram['image'] ?? '',
                        style: RythoText.body(13.5,
                            color: RythoColors.parchmentDim)),
                  ),
                ),
                // Doğum çizgisinin metni (İ1 verisi) — saat biliniyorsa.
                if (cizgi != null &&
                    (hexagram['line_texts'] as List?)?.length == 6)
                  RythoReveal(
                    index: 7,
                    child: GlassPanel(
                      label: l10n.iChingLineLabel(cizgi),
                      child: Text(
                          (hexagram['line_texts'] as List)[cizgi - 1]
                              as String,
                          style: RythoText.body(13.5,
                              color: RythoColors.parchment)),
                    ),
                  ),
              ]);
        },
        ),
      ),
    );
  }
}
