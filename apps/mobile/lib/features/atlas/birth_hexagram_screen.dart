import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/ai_consent.dart' show AiOnayKapaliKarti, aiOnayHatasiMi;
import '../../core/api.dart' show friendlyError;
import '../../core/providers.dart';
import '../../l10n/app_localizations.dart';
import '../../theme/rytho_theme.dart';
import '../../widgets/atlas_widgets.dart';
import '../../widgets/cosmic_scaffold.dart';
import '../paywall/plus_locked_card.dart';

/// Doğum Heksagramı ekranı (Revize İ5): doğum anındaki Güneş'in 64 kapı
/// çarkındaki yeri — çekim değil, kalıcı kimlik katmanı. Saatsiz doğumda
/// iki adaylı sınır beyanı gösterilir; kesinlik iddia edilmez.
class BirthHexagramScreen extends ConsumerWidget {
  const BirthHexagramScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final veri = ref.watch(birthHexagramProvider);

    return CosmicScaffold(
      appBar: AppBar(title: Text(l10n.birthHexagramTitle)),
      body: veri.when(
        loading: () => const Center(child: AstrolabeSpinner()),
        error: (e, _) => Center(
          // U06: AI kapalıyken düz hata metni değil, tek dokunuşla onay
          // sayfasını açan kart.
          child: aiOnayHatasiMi(e)
              ? const AiOnayKapaliKarti()
              : Padding(
                  padding: const EdgeInsets.all(32),
                  child: Text(friendlyError(e, l10n),
                      style: RythoText.body(14,
                          color: RythoColors.parchmentDim)),
                ),
        ),
        data: (data) {
          if (data == null) {
            return PlusLockedCard(
              emoji: '☯',
              title: l10n.birthHexagramTitle,
              description: l10n.birthHexagramLockedBody,
              centered: true,
            );
          }
          final konum = Map<String, dynamic>.from(data['position']);
          final hexagram = Map<String, dynamic>.from(data['hexagram']);
          final alternatif = data['alternate_hexagram'] != null
              ? Map<String, dynamic>.from(data['alternate_hexagram'])
              : null;
          final cizgi = konum['line'] as int?;

          var sira = 0;
          Duration gecikme() => Duration(milliseconds: 130 * sira++);
          Widget blok(Widget w) => w
              .animate(delay: gecikme())
              .fadeIn(duration: 380.ms)
              .slideY(begin: 0.06, curve: Curves.easeOutCubic);

          return ListView(
              padding: const EdgeInsets.only(top: 8, bottom: 120),
              children: [
                blok(Plaque(
                  label: cizgi != null
                      ? l10n.birthHexagramGateLine(
                          konum['gate'] as int, cizgi)
                      : l10n.birthHexagramGateOnly(konum['gate'] as int),
                  child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Text(hexagram['unicode'] ?? '',
                            style: const TextStyle(
                                fontSize: 56,
                                color: RythoColors.goldBright)),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                    '${hexagram['name_local'] ?? hexagram['name_tr']}',
                                    style: RythoText.display(24)),
                                Text(
                                    '${hexagram['name']} ${hexagram['name_cn']}',
                                    style: RythoText.body(12.5,
                                        color: RythoColors.parchmentDim)),
                                const SizedBox(height: 4),
                                Text(
                                    l10n.birthHexagramSunAt(
                                        '${konum['longitude']}'),
                                    style: RythoText.mono(10.5,
                                        color: RythoColors.parchmentDim)),
                              ]),
                        ),
                      ]),
                )),
                // Sınır beyanı: saatsiz doğumda kapı kesin bildirilemezse
                // İKİ aday da söylenir — kesinlik yanılsaması yok.
                if (alternatif != null)
                  blok(Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                    child: Text(
                        l10n.birthHexagramBoundary(
                            konum['gate'] as int,
                            konum['alternate_gate'] as int),
                        style: RythoText.body(11.5,
                            color: RythoColors.copper)),
                  )),
                // Kapının Dokusu (İ8): Rytho'nun kapıya özgü karakter
                // aktarımı — gölgesiyle birlikte.
                if ((data['gate_text'] as String?)?.isNotEmpty ?? false)
                  blok(Plaque(
                    label: l10n.birthHexagramGatePassage,
                    child: Text(data['gate_text'] as String,
                        style: RythoText.body(14,
                            color: RythoColors.parchment)),
                  )),
                blok(Plaque(
                  label: l10n.iChingJudgmentTitle,
                  child: Text(hexagram['judgment'] ?? '',
                      style: RythoText.body(14,
                          color: RythoColors.parchment)),
                )),
                blok(Plaque(
                  label: l10n.iChingImageTitle,
                  child: Text(hexagram['image'] ?? '',
                      style: RythoText.body(13.5,
                          color: RythoColors.parchmentDim)),
                )),
                // Doğum çizgisinin metni (İ1 verisi) — saat biliniyorsa.
                if (cizgi != null &&
                    (hexagram['line_texts'] as List?)?.length == 6)
                  blok(Plaque(
                    label: l10n.iChingLineLabel(cizgi),
                    child: Text(
                        (hexagram['line_texts'] as List)[cizgi - 1]
                            as String,
                        style: RythoText.body(13.5,
                            color: RythoColors.parchment)),
                  )),
                blok(const SectionDivider()),
                blok(Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: MarginNote(
                      title: l10n.birthHexagramNote,
                      text: data['report'] ?? ''),
                )),
              ]);
        },
      ),
    );
  }
}
