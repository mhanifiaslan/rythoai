import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../l10n/app_localizations.dart';
import '../theme/rytho_theme.dart';
import '../theme/rytho_tokens.dart';
import 'atlas_widgets.dart' show GoldButton;
import 'motion.dart';
import 'nebula_widgets.dart' show kSignGlyphs, signDisplayName, signIndexOf;

/// Büyük Üçlü perdesi (R12-B1): onboarding'in kayıp finali.
///
/// Kullanıcı doğum verisini verir, sunucu Güneş/Ay/Yükselen'i hesaplar ve
/// eskiden HİÇBİR ŞEY gösterilmeden ana ekrana düşülürdü — uygulamanın
/// vaadini ilk kez teslim ettiği an sessizdi. Perde üç mührü sırayla açar;
/// bir kere, yalnızca onboarding'in bittiği oturumda görünür.
///
/// Harita hesaplanamadıysa (savedWithoutChart) perde HİÇ açılmaz — yalan
/// rozet göstermeme kuralı (bkz. core/birth_record.dart baş yorumu).
Future<void> showBigThreeReveal(
  BuildContext context, {
  required String sun,
  required String moon,
  String? ascendant,
}) {
  return showGeneralDialog(
    context: context,
    barrierDismissible: false,
    barrierLabel: 'big-three',
    barrierColor: RythoColors.ink.withValues(alpha: 0.92),
    transitionDuration: RythoMotion.base,
    transitionBuilder: (_, anim, _, child) =>
        FadeTransition(opacity: anim, child: child),
    pageBuilder: (_, _, _) =>
        _BigThreeReveal(sun: sun, moon: moon, ascendant: ascendant),
  );
}

class _BigThreeReveal extends StatelessWidget {
  const _BigThreeReveal({
    required this.sun,
    required this.moon,
    required this.ascendant,
  });

  final String sun;
  final String moon;
  final String? ascendant;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final sabit = reduceMotion(context);
    final hamYukselen = ascendant ?? '';
    final yukselenMetni = hamYukselen.isEmpty
        ? l10n.bigThreeAscendantUnknown
        : hamYukselen;

    // Mühürler sırayla: her biri bir öncekinden 350ms sonra açılır; buton
    // üçü de yerine oturduktan sonra gelir.
    Widget muhur(int sira, String etiket, String burc) {
      final w = _Seal(etiket: etiket, burc: burc);
      if (sabit) return w;
      return w
          .animate(delay: Duration(milliseconds: 250 + 350 * sira))
          .fadeIn(duration: RythoMotion.base)
          .scale(
              begin: const Offset(0.2, 0.2),
              end: const Offset(1, 1),
              duration: const Duration(milliseconds: 500),
              curve: RythoMotion.pop);
    }

    Widget baslik = Text(l10n.bigThreeTitle,
        textAlign: TextAlign.center, style: RythoText.display(26));
    Widget buton = GoldButton(
        text: l10n.bigThreeStart,
        onPressed: () => Navigator.of(context).pop());
    if (!sabit) {
      baslik = baslik.animate().fadeIn(duration: RythoMotion.slow);
      buton = buton
          .animate(delay: const Duration(milliseconds: 1550))
          .fadeIn(duration: RythoMotion.slow)
          .slideY(begin: 0.2, curve: RythoMotion.enter);
    }

    return Material(
      type: MaterialType.transparency,
      child: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                baslik,
                const SizedBox(height: 40),
                // Üç mühür ESNEK: eski satır 92+20+92+20+92 = 316 px sabitti
                // ve 320 dp'de 28 px kenar dolgusuyla taşıyordu (ölçüldü:
                // 372 dp altında taşma, 320'de 52 px). Her mühür üçte bir
                // pay alır, içinde `_Seal` üst sınırına kadar genişler.
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                        child: Center(child: muhur(0, l10n.bigThreeSun, sun))),
                    const SizedBox(width: RythoSpace.lg),
                    Expanded(
                        child:
                            Center(child: muhur(1, l10n.bigThreeMoon, moon))),
                    const SizedBox(width: RythoSpace.lg),
                    Expanded(
                        child: Center(
                            child: muhur(
                                2, l10n.bigThreeAscendant, yukselenMetni))),
                  ],
                ),
                const SizedBox(height: 48),
                buton,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Bir mührün ÜST genişlik sınırı. Sabit genişlik değil: dar ekranda
/// `Expanded` payı bundan küçükse mühür paya sığar, geniş ekranda bu
/// değerde durur (üç mühür yan yana 316 px'i geçmez, eski görünüm korunur).
const double kMuhurGenisligi = 92;

/// Tek mühür: burç renginde daire içinde glif + altta rol ve burç adı.
class _Seal extends StatelessWidget {
  const _Seal({required this.etiket, required this.burc});

  final String etiket;

  /// Profildeki biçim: "Kova ♒" — indekse [signIndexOf] ile çevrilir.
  final String burc;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final i = signIndexOf(burc);
    final renk = i >= 0 ? RythoColors.signColors[i] : RythoColors.gold;
    final glif = i >= 0 ? kSignGlyphs[i] : '✦';
    final ad = i >= 0 ? signDisplayName(l10n, i) : burc;

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: kMuhurGenisligi),
      child: Column(children: [
        Container(
          width: 64,
          height: 64,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [renk, renk.withValues(alpha: 0.55)],
            ),
            border:
                Border.all(color: Colors.white.withValues(alpha: 0.25)),
            boxShadow: [
              BoxShadow(
                  color: renk.withValues(alpha: 0.45),
                  blurRadius: 22,
                  spreadRadius: 1),
            ],
          ),
          child: Text(glif,
              style: const TextStyle(fontSize: 28, color: Colors.white)),
        ),
        const SizedBox(height: 10),
        Text(etiket,
            style: RythoText.label(10.5, color: RythoColors.parchmentDim)),
        const SizedBox(height: 2),
        Text(ad,
            textAlign: TextAlign.center,
            style: RythoText.body(13.5, w: FontWeight.w700)),
      ]),
    );
  }
}
