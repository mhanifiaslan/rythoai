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
import '../../widgets/cosmic_scaffold.dart';
import '../../widgets/glass.dart';
import '../../widgets/motion.dart';
import '../../widgets/okuma_kabi.dart';
import '../chat/chat_screen.dart';
import '../paywall/bedel_onayi.dart';
import '../paywall/ozellik_katalogu.dart';
import '../paywall/plus_locked_card.dart';

/// **İç mevsim** (T5, R5-6'da yeniden adlandırıldı): ikincil progresyon.
///
/// Progres Ay'ın mevsimi, şu an etkin açılar, yaşam yayı ve okuma. Otuz
/// günlük olay listesi buradan ÇIKTI — ana ekrandaki takvim şeridine
/// taşındı; "önündeki günler" bir dizin ekranında aranmamalı.
///
/// Renk dili tahmin doktrininden: yaklaşan (applying) LİLA, ayrılan
/// (separating) soluk. Bütün adlar sunucudan isteğin dilinde gelir
/// (`*_local`); ekran çeviri yapmaz.
class InnerCalendarScreen extends ConsumerWidget {
  const InnerCalendarScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    // ÜÇ DURUMLU kapı (P2): sağlayıcının `null`ı artık YALNIZ "abone değil"
    // demek. Cevap gelmeden kilit çizmek, ödemiş kullanıcıya her girişte
    // "abone değilsin" demekti.
    final kapi = ref.watch(raporKapisiProvider);
    if (kapi == PlusHali.bilinmiyor) {
      return CosmicScaffold(
        appBar: AppBar(title: Text(l10n.innerCalendarTitle)),
        // Ne kilit ne içerik: ikisi de bir hüküm ve o hüküm henüz yok.
        body: const SkeletonList(),
      );
    }
    return CosmicScaffold(
      appBar: AppBar(title: Text(l10n.innerCalendarTitle)),
      // Bedel kapısı (D7): 5 kredilik üretim ekrana GİRİLDİĞİ AN
      // başlıyordu. Sağlayıcı artık kapının İÇİNDE izleniyor — istek ilk
      // "Devam"dan sonra gider (`bedel_onayi.dart`); abone olmayana ve
      // eşik altı bedele kapı görünmez.
      body: BedelKapisi(
        ozellik: PlusOzellik.progressions,
        builder: (context, ref) => ref.watch(innerCalendarProvider).when(
        loading: () => StagedWaiting(stages: [
          l10n.innerCalendarWaitStage1,
          l10n.innerCalendarWaitStage2,
        ]),
        // Çıplak metin ÇIKMAZ SOKAKTI: bu sayfada aşağı çekme yok, hatayı
        // gören kullanıcı geri dönüp yeniden girmek zorundaydı.
        error: (e, _) => Center(
          child: ErrorCard(
            message: friendlyError(e, l10n),
            screen: 'atlas',
            onRetry: () => ref.invalidate(innerCalendarProvider),
          ),
        ),
        data: (data) {
          if (data == null) {
            const ozellik = PlusOzellik.progressions;
            return PlusLockedCard(
              ozellik: ozellik,
              title: ozellik.baslik(l10n),
              description: ozellik.kilitGovdesi(l10n),
              centered: true,
            );
          }
          final prog = Map<String, dynamic>.from(data['progressions']);
          final progresyon =
              Map<String, dynamic>.from(prog['progressions']);
          final ay = Map<String, dynamic>.from(progresyon['prog_moon']);
          final vurgular = List<Map<String, dynamic>>.from(
              progresyon['solar_arc_hits'] ?? const []);
          final takvim = Map<String, dynamic>.from(data['calendar']);
          final aktif = List<Map<String, dynamic>>.from(
              takvim['active_now'] ?? const []);
          final beyanlar = <String>{
            ...List<String>.from(
                progresyon['disclosure_texts'] ?? const []),
            ...List<String>.from(takvim['disclosure_texts'] ?? const []),
          };
          final ayMetni =
              '${ay['sign_local'] ?? ay['sign']} ${ay['position']}°';

          return ListView(
            padding: const EdgeInsets.only(
                top: RythoSpace.sm, bottom: RythoSpace.dockClearance),
            children: [
              // ⚠️ OKUMA ÖNDE, ÖLÇÜM ARKADA — ve bu sıra bir sahip kararı.
              //
              // Bu ekran "progres Ay Yay'da 12°" ile açılıyordu; insan
              // cümlesi (LLM okuması) sayfanın EN SONUNDAYDI, dört ölçüm
              // bloğunun arkasında. Sahibin tarifi: "bu bir lifestyle
              // uygulaması, daha anlaşılırdan isteyenler için daha teknik
              // bir yapıya gidilmeli." Ölçüm KALDIRILMADI — yalnız sıra
              // tersine döndü: ne olduğu önce, nasıl ölçüldüğü sonra.
              //
              // Kap `OkumaKabi`: `fallback` bayrağını okuyan tek nokta
              // `okumaDurumuFromYanit` — sunucu şablona düştüğünde dürüst
              // cümle + tekrar dene gelir, paylaşım kurulmaz. Eski hâl
              // bayrağı HİÇ okumuyordu ve gerekçesi "bu uç bayrak
              // döndürmüyor" diye çivilenmişti; D0'dan beri döndürüyor.
              RythoReveal(
                index: 0,
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: RythoSpace.lg),
                  child: OkumaKabi(
                    durum: okumaDurumuFromYanit(prog),
                    ekranKodu: 'atlas',
                    baslik: l10n.innerCalendarNote,
                    onTekrarDene: () => ref.invalidate(innerCalendarProvider),
                    onSor: () => Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => ChatScreen(
                            initialText: l10n.innerCalendarAskPrefill))),
                    paylasim: PaylasimTarifi(
                      title: l10n.innerCalendarTitle,
                      dateLabel: bugununEtiketi(),
                      // Rozet ÖLÇÜLMÜŞ bir değer: progres Ay'ın konumu.
                      badges: [(l10n.innerCalendarProgMoon, ayMetni)],
                      glyph: PlusOzellik.progressions.emoji,
                    ),
                  ),
                ),
              ),
              const RythoReveal(index: 1, child: SectionDivider()),
              // Progres Ay — iç mevsimin omurgası.
              RythoReveal(
                index: 2,
                child: GlassPanel(
                  label: l10n.innerCalendarProgMoon,
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(ayMetni, style: RythoType.heroSmall),
                        const SizedBox(height: RythoSpace.xs),
                        Text('${ay['phase_local'] ?? ay['phase'] ?? ''}',
                            style: RythoText.body(13,
                                color: RythoColors.lilac)),
                        const SizedBox(height: RythoSpace.xs),
                        Text(
                            l10n.innerCalendarNextSign(
                                '${ay['next_sign_at']}'),
                            style: RythoText.mono(11.5,
                                color: RythoColors.parchmentDim)),
                      ]),
                ),
              ),
              if (beyanlar.isNotEmpty)
                RythoReveal(
                  index: 3,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(
                        RythoSpace.lg, 0, RythoSpace.lg, RythoSpace.xs),
                    child: Text(beyanlar.join('\n'),
                        style: RythoText.body(11.5,
                            color: RythoColors.copper)),
                  ),
                ),
              // Şu an etkin açılar: yaklaşan lila, ayrılan soluk.
              if (aktif.isNotEmpty)
                RythoReveal(
                  index: 4,
                  child: GlassPanel(
                    label: l10n.innerCalendarActive,
                    child: Column(
                        children: aktif
                            .map((a) => _AcikSatir(
                                  metin: '${a['transit_local']} '
                                      '${a['aspect_local']} '
                                      '${a['natal_local']}',
                                  ek: '${a['orb']}°',
                                  renk: a['movement'] == 'applying'
                                      ? RythoColors.lilac
                                      : RythoColors.parchmentDim,
                                ))
                            .toList()),
                  ),
                ),
              // 30 günlük olay listesi BURADAN KALKTI (R5-6): aynı veri
              // artık ana ekrandaki yatay takvim şeridinde yaşıyor.
              // Kullanıcı "önündeki günler"i görmek için bu ekranı
              // aramak zorunda değil; burası artık YALNIZ iç mevsim —
              // progres Ay, etkin açılar, yaşam yayı ve okuma.
              //
              // Yaşam yayı: solar arc kesinleşmeleri (yıl/ay hassasiyeti).
              if (vurgular.isNotEmpty)
                RythoReveal(
                  index: 5,
                  child: GlassPanel(
                    label: l10n.innerCalendarArc,
                    child: Column(
                        children: vurgular
                            .map((h) => _AcikSatir(
                                  metin: '${h['directed_local']} '
                                      '${h['aspect_local']} '
                                      '${h['natal_local']}',
                                  // Gün değil AY hassasiyeti: doktrin gereği
                                  // tarihi yıl-ay olarak kırpıyoruz.
                                  ek: '${h['exact_on']}'.substring(0, 7),
                                  renk: RythoColors.parchmentDim,
                                ))
                            .toList()),
                  ),
                ),
            ],
          );
        },
        ),
      ),
    );
  }
}

/// Tek satırlık açı/vurgu görünümü: metin + sağda mono ek bilgi.
class _AcikSatir extends StatelessWidget {
  const _AcikSatir(
      {required this.metin, required this.ek, required this.renk});

  final String metin;
  final String ek;
  final Color renk;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: RythoSpace.xs),
      child: Row(children: [
        Expanded(child: Text(metin, style: RythoText.body(13, color: renk))),
        // Sağdaki ek (tarih/derece) esnemiyordu: `Expanded` sıfıra inse
        // bile uzun ek dar ekranda satırı taşırıyordu.
        Flexible(
          child: Text(ek,
              style: RythoText.mono(11, color: RythoColors.parchmentDim)),
        ),
      ]),
    );
  }
}
