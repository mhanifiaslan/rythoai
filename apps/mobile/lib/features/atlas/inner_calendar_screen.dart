import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api.dart' show friendlyError;
import '../../core/providers.dart';
import '../../l10n/app_localizations.dart';
import '../../theme/rytho_theme.dart';
import '../../widgets/atlas_widgets.dart';
import '../../widgets/cosmic_scaffold.dart';
import '../../widgets/glass.dart' show SkeletonPanel;
import '../../widgets/motion.dart';
import '../chat/chat_screen.dart';
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
        body: const _Iskelet(),
      );
    }
    final veri = ref.watch(innerCalendarProvider);

    return CosmicScaffold(
      appBar: AppBar(title: Text(l10n.innerCalendarTitle)),
      body: veri.when(
        loading: () => StagedWaiting(stages: [
          l10n.innerCalendarWaitStage1,
          l10n.innerCalendarWaitStage2,
        ]),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Text(friendlyError(e, l10n),
                style: RythoText.body(14, color: RythoColors.parchmentDim)),
          ),
        ),
        data: (data) {
          if (data == null) {
            return PlusLockedCard(
              emoji: '🌗',
              title: l10n.innerCalendarTitle,
              description: l10n.innerCalendarLockedBody,
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

          var sira = 0;
          Duration gecikme() => Duration(milliseconds: 110 * sira++);
          Widget blok(Widget w) => w
              .animate(delay: gecikme())
              .fadeIn(duration: 380.ms)
              .slideY(begin: 0.06, curve: Curves.easeOutCubic);

          final okuma = (prog['report'] as String? ?? '').trim();

          return ListView(
            padding: const EdgeInsets.only(top: 8, bottom: 120),
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
              // NEDEN boşsa hiç çizilmiyor: okuma üretilemediğinde (LLM
              // reddi) üstte boş bir blok kalırdı ve sayfa yine bir sayıyla
              // açılırdı — ama bu kez bir de boşlukla. Boş yer, uydurulmuş
              // cümleden iyidir; uydurulmuş BOŞLUKTAN da iyidir.
              //
              // ⚠️ Burada `fallback` bayrağı OKUNAMIYOR çünkü bu uç onu
              // HİÇ DÖNDÜRMÜYOR (altı uçtan biri; bkz. CLAUDE.md). BaZi
              // sekmesindeki dürüst `ErrorCard` dalı burada kurulamaz —
              // kurmak, gönderilmeyen bir bayrağa dayanmak olurdu.
              if (okuma.isNotEmpty) ...[
                blok(Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: MarginNote(
                      title: l10n.innerCalendarNote, text: okuma),
                )),
                blok(const SectionDivider()),
              ],
              // Progres Ay — iç mevsimin omurgası.
              blok(Plaque(
                label: l10n.innerCalendarProgMoon,
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                          '${ay['sign_local'] ?? ay['sign']} '
                          '${ay['position']}°',
                          style: RythoText.display(24)),
                      const SizedBox(height: 4),
                      Text('${ay['phase_local'] ?? ay['phase'] ?? ''}',
                          style: RythoText.body(13,
                              color: RythoColors.lilac)),
                      const SizedBox(height: 6),
                      Text(
                          l10n.innerCalendarNextSign(
                              '${ay['next_sign_at']}'),
                          style: RythoText.mono(11.5,
                              color: RythoColors.parchmentDim)),
                    ]),
              )),
              if (beyanlar.isNotEmpty)
                blok(Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                  child: Text(beyanlar.join('\n'),
                      style:
                          RythoText.body(11.5, color: RythoColors.copper)),
                )),
              // Şu an etkin açılar: yaklaşan lila, ayrılan soluk.
              if (aktif.isNotEmpty)
                blok(Plaque(
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
                )),
              // 30 günlük olay listesi BURADAN KALKTI (R5-6): aynı veri
              // artık ana ekrandaki yatay takvim şeridinde yaşıyor.
              // Kullanıcı "önündeki günler"i görmek için bu ekranı
              // aramak zorunda değil; burası artık YALNIZ iç mevsim —
              // progres Ay, etkin açılar, yaşam yayı ve okuma.
              //
              // Yaşam yayı: solar arc kesinleşmeleri (yıl/ay hassasiyeti).
              if (vurgular.isNotEmpty)
                blok(Plaque(
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
                )),
              // Sayfanın birincil eylemi en alt kenarda (tasarım doktrini):
              // kullanıcı okumayı ve ölçümü gördükten SONRA soruyla gelir.
              blok(RythoyaSor(
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => ChatScreen(
                          initialText: l10n.innerCalendarAskPrefill))))),
            ],
          );
        },
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
      padding: const EdgeInsets.symmetric(vertical: 4),
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

/// Kapı BİLİNMİYORken çizilen iskelet (P2).
///
/// Ne kilit ne içerik: ikisi de bir hüküm ve o hüküm henüz yok. Bloklar
/// sayfanın gerçek bölüm hacimlerini taklit ediyor, böylece cevap gelince
/// düzen zıplamıyor. Shimmer `SkeletonPanel`in içinde ve reduce-motion'da
/// kendiliğinden kapanıyor.
class _Iskelet extends StatelessWidget {
  const _Iskelet();

  @override
  Widget build(BuildContext context) => ListView(
        padding: const EdgeInsets.only(top: 8, bottom: 120),
        children: const [
          SkeletonPanel(height: 150),
          SkeletonPanel(height: 110),
          SkeletonPanel(height: 90),
        ],
      );
}
