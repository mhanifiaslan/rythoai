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
import '../paywall/ozellik_katalogu.dart';
import '../paywall/plus_locked_card.dart';

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
        // Ne kilit ne içerik: ikisi de bir hüküm ve o hüküm henüz yok.
        body: const SkeletonList(),
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
        // Çıplak metin ÇIKMAZ SOKAKTI: bu sayfada aşağı çekme yok, hatayı
        // gören kullanıcı geri dönüp yeniden girmek zorundaydı.
        error: (e, _) => Center(
          child: ErrorCard(
            message: friendlyError(e, l10n),
            screen: 'atlas',
            onRetry: () => ref.invalidate(solarReturnProvider),
          ),
        ),
        data: (data) {
          if (data == null) {
            const ozellik = PlusOzellik.solarReturn;
            return PlusLockedCard(
              ozellik: ozellik,
              title: ozellik.baslik(l10n),
              description: ozellik.kilitGovdesi(l10n),
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

          final ascMetni = asc != null
              ? '${asc['sign_local'] ?? asc['sign']} ${asc['position']}°'
              : null;
          final ayMetni =
              '${sr['sr_moon_local'] ?? sr['sr_moon_sign'] ?? '-'}';

          // Paylaşım rozetleri: yılın üç ölçülen işareti. Saat bilinmiyorsa
          // Yükselen/ev HİÇ hesaplanmıyor — o rozetler de kurulmaz.
          final rozetler = <(String, String)>[
            if (ascMetni != null) (l10n.solarReturnAsc, ascMetni),
            if (gunesEvi != null)
              (l10n.solarReturnSunHouse, l10n.solarReturnHouseN(gunesEvi)),
            (l10n.solarReturnMoon, ayMetni),
          ];

          return ListView(
            padding: const EdgeInsets.only(
                top: RythoSpace.sm, bottom: RythoSpace.dockClearance),
            children: [
              // ⚠️ OKUMA ÖNDE, ÖLÇÜM ARKADA (sahip kararı, lifestyle turu).
              //
              // Ekran bir TARİH-SAAT ile açılıyordu ve yılın okuması dört
              // bloğun arkasında, sayfanın en sonundaydı. Dönüş anı doğru
              // ve hak edilmiş bir ölçüm — kaldırılmadı, yalnız okumanın
              // ARKASINA alındı: "bu yıl bana ne getiriyor" önce,
              // "hangi dakikada başlıyor" sonra.
              //
              // Kap `OkumaKabi`: paylaşım yalnız hazır okumada kurulur.
              // Eski hâl `fallback` bayrağını okumuyor ve sunucunun şablon
              // paragrafını paylaşım KARTINA bile basıyordu (ölçüldü).
              RythoReveal(
                index: 0,
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: RythoSpace.lg),
                  child: OkumaKabi(
                    durum: okumaDurumuFromYanit(data),
                    ekranKodu: 'atlas',
                    baslik: l10n.solarReturnNote,
                    onTekrarDene: () => ref.invalidate(solarReturnProvider),
                    onSor: () => Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => ChatScreen(
                            initialText: l10n.solarReturnAskPrefill))),
                    paylasim: PaylasimTarifi(
                      title: l10n.solarReturnTitle,
                      // Kartın tarihi yılın AÇILIŞ anı — üretim günü değil;
                      // yıl haritası o tarihle anılır.
                      dateLabel: _tarih(sr['return_at_local']),
                      badges: rozetler,
                      glyph: PlusOzellik.solarReturn.emoji,
                    ),
                  ),
                ),
              ),
              const RythoReveal(index: 1, child: SectionDivider()),
              // Dönüş anı — yılın açılış anı, ekranın en büyük tipografisi.
              // Dakika hassasiyetli bir hesap; büyük yazılması hak edilmiş.
              RythoReveal(
                index: 2,
                child: _DonusKarti(
                  label: l10n.solarReturnMoment,
                  tarih: _tarih(sr['return_at_local']),
                  saat: _saat(sr['return_at_local']),
                  altYazi:
                      l10n.solarReturnNext(_an(sr['next_return_at_local'])),
                ),
              ),
              // Yılın kimliği: üç rozet yan yana. Eskiden etiket–değer
              // satırlarıydı; yılın işaretleri bir bakışta okunmalı.
              RythoReveal(
                index: 3,
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
              ),
              // Saatsizlik/şehir beyanı — natal ekrandaki bakır dil.
              // Rozetlerin ALTINDA: hangi şehre kurulduğu, ancak neyin
              // hesaplandığı görüldükten sonra anlam taşıyor.
              if (beyanlar.isNotEmpty)
                RythoReveal(
                  index: 4,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(RythoSpace.lg,
                        RythoSpace.sm, RythoSpace.lg, RythoSpace.xs),
                    child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Padding(
                            padding: EdgeInsets.only(
                                top: RythoSpace.xxs, right: RythoSpace.sm),
                            child: Icon(Icons.place_outlined,
                                size: 14, color: RythoColors.copper),
                          ),
                          Expanded(
                            child: Text(beyanlar.join('\n\n'),
                                style: RythoText.body(11.5,
                                    color: RythoColors.copper, height: 1.5)),
                          ),
                        ]),
                  ),
                ),
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
    return GlassPanel(
      label: label,
      glow: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
            // Bilinçli renkli emoji: katalogdaki yıl haritası simgesi.
            Text(PlusOzellik.solarReturn.emoji, style: RythoText.emoji(34)),
            const SizedBox(width: RythoSpace.md),
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
          const SizedBox(height: RythoSpace.md),
          Text(altYazi,
              style: RythoText.body(12, color: RythoColors.parchmentDim)),
        ],
      ),
    );
  }
}

/// Yılın kimliğindeki tek rozet: küçük etiket + altın değer.
///
/// Etiket BÜYÜK HARFE ÇEVRİLMEZ: eski hâl `toUpperCase()` çağırıyordu ve
/// Türkçe'de `i` → `I` düşüyordu ("Güneş'in yıl evi" → "GÜNEŞ'IN YIL EVI",
/// ölçüldü). Rol tipografisi (`RythoType.label`) etiket ağırlığını zaten
/// taşıyor.
class _Rozet extends StatelessWidget {
  const _Rozet({required this.etiket, required this.deger});

  final String etiket;
  final String deger;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(etiket, style: RythoType.label),
        const SizedBox(height: RythoSpace.xs),
        Text(deger,
            style: RythoText.body(14,
                w: FontWeight.w700, color: RythoColors.goldBright)),
      ],
    );
  }
}
