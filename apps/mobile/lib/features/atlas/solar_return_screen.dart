import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api.dart' show friendlyError;
import '../../core/providers.dart';
import '../../l10n/app_localizations.dart';
import '../../theme/rytho_theme.dart';
import '../../widgets/atlas_widgets.dart';
import '../../widgets/cosmic_scaffold.dart';
import '../../widgets/glass.dart';
import '../../widgets/markdown_text.dart' show markdownToPlain;
import '../../widgets/motion.dart';
import '../paywall/plus_locked_card.dart';
import '../share/share_card.dart' show shareReportCard;

/// Yıl Haritası (T5): aktif güneş dönüşü — Güneş'in natal boylamına tam
/// döndüğü ana kurulan harita, bir sonraki doğum gününe kadar geçerli
/// yılın tonu. Saatsiz doğumda SR Yükseleni/evleri HİÇ gösterilmez;
/// sunucunun bakır beyanı aynen basılır (üretilmeyen şey söylenmez).
class SolarReturnScreen extends ConsumerWidget {
  const SolarReturnScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    // ÜÇ DURUMLU kapı (P2): sağlayıcının `null`ı artık YALNIZ "abone değil"
    // demek. Cevap gelmeden kilit çizmek, ödemiş kullanıcıya her girişte
    // "abone değilsin" demekti.
    final kapi = ref.watch(raporKapisiProvider);
    if (kapi == PlusHali.bilinmiyor) {
      return CosmicScaffold(
        appBar: AppBar(title: Text(l10n.solarReturnTitle)),
        body: const _Iskelet(),
      );
    }
    final veri = ref.watch(solarReturnProvider);

    return CosmicScaffold(
      appBar: AppBar(title: Text(l10n.solarReturnTitle)),
      body: veri.when(
        // Rapor LLM üretimi — sahneli bekleyiş (R12-B3 kuralı).
        loading: () => StagedWaiting(stages: [
          l10n.solarReturnWaitStage1,
          l10n.solarReturnWaitStage2,
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
              emoji: '🌞',
              title: l10n.solarReturnTitle,
              description: l10n.solarReturnLockedBody,
              centered: true,
            );
          }
          final sr = Map<String, dynamic>.from(data['solar_return']);
          final beyanlar =
              List<String>.from(sr['disclosure_texts'] ?? const []);
          final asc = sr['sr_ascendant'] != null
              ? Map<String, dynamic>.from(sr['sr_ascendant'])
              : null;
          // Sert cast değil hoşgörülü ayrıştırma: alan beklenmedik tipte
          // gelirse satır GİZLENİR, ekran çökmez (üretimde yaşandı —
          // sunucu bir ara kerykeion'un "Tenth_House" metnini geçiriyordu).
          final evHam = sr['sr_sun_house'];
          final gunesEvi =
              evHam is int ? evHam : int.tryParse('${evHam ?? ''}');

          var sira = 0;
          Duration gecikme() => Duration(milliseconds: 130 * sira++);
          Widget blok(Widget w) => w
              .animate(delay: gecikme())
              .fadeIn(duration: 380.ms)
              .slideY(begin: 0.06, curve: Curves.easeOutCubic);

          final ascMetni = asc != null
              ? '${asc['sign_local'] ?? asc['sign']} ${asc['position']}°'
              : null;
          final ayMetni =
              '${sr['sr_moon_local'] ?? sr['sr_moon_sign'] ?? '-'}';
          final rapor = (data['report'] ?? '') as String;

          // Paylaşım rozetleri: yılın üç ölçülen işareti. Saat bilinmiyorsa
          // Yükselen/ev HİÇ hesaplanmıyor — o rozetler de kurulmaz.
          final rozetler = <(String, String)>[
            if (ascMetni != null) (l10n.solarReturnAsc, ascMetni),
            if (gunesEvi != null)
              (l10n.solarReturnSunHouse, l10n.solarReturnHouseN(gunesEvi)),
            (l10n.solarReturnMoon, ayMetni),
          ];

          return ListView(
            padding: const EdgeInsets.only(top: 8, bottom: 120),
            children: [
              // Dönüş anı — yılın açılış anı, ekranın en büyük tipografisi.
              // Dakika hassasiyetli bir hesap; büyük yazılması hak edilmiş.
              blok(_DonusKarti(
                label: l10n.solarReturnMoment,
                tarih: _tarih(sr['return_at_local']),
                saat: _saat(sr['return_at_local']),
                altYazi:
                    l10n.solarReturnNext(_an(sr['next_return_at_local'])),
              )),
              // Yılın kimliği: üç rozet yan yana. Eskiden etiket–değer
              // satırlarıydı; yılın işaretleri bir bakışta okunmalı.
              blok(Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: GlassPanel(
                  label: l10n.solarReturnIdentity,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final (etiket, deger) in rozetler)
                        Expanded(child: _Rozet(etiket: etiket, deger: deger)),
                    ],
                  ),
                ),
              )),
              // Saatsizlik/şehir beyanı — natal ekrandaki bakır dil.
              // Rozetlerin ALTINDA: hangi şehre kurulduğu, ancak neyin
              // hesaplandığı görüldükten sonra anlam taşıyor.
              if (beyanlar.isNotEmpty)
                blok(Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
                  child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Padding(
                          padding: EdgeInsets.only(top: 2, right: 8),
                          child: Icon(Icons.place_outlined,
                              size: 14, color: RythoColors.copper),
                        ),
                        Expanded(
                          child: Text(beyanlar.join('\n\n'),
                              style: RythoText.body(11.5,
                                  color: RythoColors.copper, height: 1.5)),
                        ),
                      ]),
                )),
              blok(const SectionDivider()),
              blok(Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: MarginNote(
                    title: l10n.solarReturnNote, text: rapor),
              )),
              if (rapor.trim().isNotEmpty)
                blok(Padding(
                  padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.ios_share_rounded, size: 18),
                    label: Text(l10n.shareReading),
                    onPressed: () => shareReportCard(
                      context,
                      title: l10n.solarReturnTitle,
                      body: markdownToPlain(rapor),
                      dateLabel: _tarih(sr['return_at_local']),
                      badges: rozetler,
                      glyph: '🌞',
                    ),
                  ),
                )),
            ],
          );
        },
      ),
    );
  }

  /// "2026-05-12T20:16:00+03:00" → "2026-05-12 20:16" — saniye ve dilim
  /// eki ekranda gürültü; hesap hassasiyeti raporun konusu değil.
  static String _an(Object? iso) {
    final s = (iso ?? '').toString();
    return s.length >= 16 ? '${s.substring(0, 10)} ${s.substring(11, 16)}' : s;
  }

  static String _tarih(Object? iso) {
    final s = (iso ?? '').toString();
    return s.length >= 10 ? s.substring(0, 10) : s;
  }

  static String _saat(Object? iso) {
    final s = (iso ?? '').toString();
    return s.length >= 16 ? s.substring(11, 16) : '';
  }
}

/// Yılın açılış anı — ekranın taşıyıcı görseli.
class _DonusKarti extends StatelessWidget {
  const _DonusKarti({
    required this.label,
    required this.tarih,
    required this.saat,
    required this.altYazi,
  });

  final String label;
  final String tarih;
  final String saat;
  final String altYazi;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: GlassPanel(
        label: label,
        glow: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
              const Text('🌞', style: TextStyle(fontSize: 34)),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(tarih,
                        style: RythoText.display(26,
                            color: RythoColors.goldBright)),
                    if (saat.isNotEmpty)
                      Text(saat,
                          style: RythoText.mono(15,
                              color: RythoColors.parchmentDim)),
                  ],
                ),
              ),
            ]),
            const SizedBox(height: 12),
            Text(altYazi,
                style: RythoText.body(12, color: RythoColors.parchmentDim)),
          ],
        ),
      ),
    );
  }
}

/// Yılın kimliğindeki tek rozet: küçük etiket + altın değer.
class _Rozet extends StatelessWidget {
  const _Rozet({required this.etiket, required this.deger});

  final String etiket;
  final String deger;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(etiket.toUpperCase(),
            style: RythoText.label(9, color: RythoColors.parchmentDim)),
        const SizedBox(height: 6),
        Text(deger,
            style: RythoText.body(14,
                w: FontWeight.w700, color: RythoColors.goldBright)),
      ],
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
