import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../l10n/app_localizations.dart';
import '../theme/rytho_glyphs.dart' show kSignGlyphs;
import '../theme/rytho_theme.dart';
import '../theme/rytho_tokens.dart';
import 'motion.dart';

// Eski çağıranlar `kSignGlyphs`i buradan alıyor; tablo tek kaynağa taşındı.
export '../theme/rytho_glyphs.dart' show kSignGlyphs;

/// Basınca 0.96'ya küçülen + hafif haptic veren sarmalayıcı — v3 hareket
/// dilinin standart "dokunuş" tepkisi.
class Pressable extends StatefulWidget {
  const Pressable({super.key, required this.child, this.onTap});
  final Widget child;
  final VoidCallback? onTap;

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: widget.onTap != null ? (_) => setState(() => _pressed = true) : null,
      onTapCancel: () => setState(() => _pressed = false),
      onTapUp: widget.onTap != null
          ? (_) {
              setState(() => _pressed = false);
              HapticFeedback.lightImpact();
              widget.onTap!();
            }
          : null,
      child: AnimatedScale(
        scale: _pressed ? 0.96 : 1.0,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}

// Burç glifleri artık `theme/rytho_glyphs.dart`'ta (TEK kaynak: glif fontunun
// kapsam bekçisi o tabloyu okuyor); import/export dosyanın başında.

/// Türkçe burç adları (Koç→Balık).
///
/// Bu liste **eşleştirme içindir, ekranda gösterim için değildir**: backend
/// ve Firestore profilleri burç adını Türkçe tutuyor (`sign_tr`, `sunSign`),
/// dolayısıyla gelen veriyi indekse çevirmek için Türkçe tabloya ihtiyaç var.
/// Kullanıcıya gösterilecek ad için [signDisplayName] kullanılır.
const kSignNamesTr = [
  'Koç', 'Boğa', 'İkizler', 'Yengeç', 'Aslan', 'Başak',
  'Terazi', 'Akrep', 'Yay', 'Oğlak', 'Kova', 'Balık',
];

/// Burç adının kullanıcının dilindeki karşılığı (0 = Koç).
///
/// ARB tarafında harita tutulamadığı için indeksten anahtara eşleme burada.
String signDisplayName(AppLocalizations l10n, int index) =>
    switch (index % 12) {
      0 => l10n.signAries,
      1 => l10n.signTaurus,
      2 => l10n.signGemini,
      3 => l10n.signCancer,
      4 => l10n.signLeo,
      5 => l10n.signVirgo,
      6 => l10n.signLibra,
      7 => l10n.signScorpio,
      8 => l10n.signSagittarius,
      9 => l10n.signCapricorn,
      10 => l10n.signAquarius,
      _ => l10n.signPisces,
    };

/// Backend'in burç anahtarları — [kSignNamesTr] ile AYNI SIRADA.
/// /api/v1/reports/horoscope/{sign} bu anahtarları bekler.
const kSignKeys = [
  'aries', 'taurus', 'gemini', 'cancer', 'leo', 'virgo',
  'libra', 'scorpio', 'sagittarius', 'capricorn', 'aquarius', 'pisces',
];

/// Burç adını indekse çevirir; bulunamazsa -1.
///
/// Backend `sun_sign` alanını ad + sembol olarak döndürüyor ("Kova ♒") ve bu
/// biçim profillerde kayıtlı. Birebir karşılaştırma yapılırsa hiçbir kullanıcının
/// kendi burcu tanınmaz ve ana ekranda herkese Koç gösterilir. Bu yüzden
/// eşleştirme sembole toleranslıdır.
int signIndexOf(String? name) {
  if (name == null) return -1;
  final cleaned = name.trim();
  for (var i = 0; i < kSignNamesTr.length; i++) {
    if (cleaned == kSignNamesTr[i] || cleaned.startsWith('${kSignNamesTr[i]} ')) {
      return i;
    }
  }
  return -1;
}

/// Ham burç adını kullanıcının diline çevirir.
///
/// Firestore ve backend burç adını **Türkçe** tutuyor (`sunSign: "Oğlak ♑"`,
/// `sun_sign`) — bunu ekrana olduğu gibi basmak, arayüz İngilizceyken
/// "Oğlak" yazdırıyordu. Cihazda ölçüldü (KL-turu): İngilizce hesapta ana
/// ekranın günlük okuma kartı Türkçe burç adı gösteriyordu, hemen altındaki
/// AI cümlesi ise doğru şekilde "Capricorn" diyordu.
///
/// Tanınmayan değer AYNEN döner: biçim değişirse ad kaybolmaz, yalnız
/// çevrilmemiş kalır — boş bir çip göstermekten iyidir.
String localizedSignName(AppLocalizations l10n, String? raw) {
  final i = signIndexOf(raw);
  if (i < 0) return raw?.trim() ?? '';
  final ad = signDisplayName(l10n, i);
  // Glif dilden bağımsız ve tasarımın parçası: ham değer taşıyorsa korunur.
  return raw!.contains(kSignGlyphs[i]) ? '$ad ${kSignGlyphs[i]}' : ad;
}

/// Yuvarlak burç çipi: renkli degrade daire içinde glif + altta ad.
class ZodiacChip extends StatelessWidget {
  const ZodiacChip({
    super.key,
    required this.signIndex,
    this.selected = false,
    this.onTap,
    this.size = 52,
  });

  final int signIndex; // 0 = Koç ... 11 = Balık
  final bool selected;
  final VoidCallback? onTap;
  final double size;

  @override
  Widget build(BuildContext context) {
    final color = RythoColors.signColors[signIndex % 12];
    return Pressable(
      onTap: onTap,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutCubic,
          width: size,
          height: size,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                color.withValues(alpha: selected ? 0.55 : 0.28),
                RythoColors.inkLight,
              ],
            ),
            border: Border.all(
              color: selected ? color : Colors.white.withValues(alpha: 0.10),
              width: selected ? 1.6 : 1,
            ),
            boxShadow: selected
                ? [BoxShadow(color: color.withValues(alpha: 0.45), blurRadius: 16)]
                : null,
          ),
          child: Text(kSignGlyphs[signIndex % 12],
              style: TextStyle(fontSize: size * 0.42, color: color)),
        ),
        const SizedBox(height: 5),
        Text(signDisplayName(AppLocalizations.of(context), signIndex),
            style: RythoText.body(10.5,
                color: selected ? RythoColors.parchment : RythoColors.parchmentDim,
                w: selected ? FontWeight.w700 : FontWeight.w500)),
      ]),
    );
  }
}

// `PromoBanner` KALDIRILDI (Tasarım A2). Gökyüzü akışında burç şeridi ile
// içgörü kartının arasında duruyordu: şeride dokunuluyor, sonuç bandın
// ÖTESİNDE değişiyordu. Satış mesajı artık yalnızca `PlusLockedCard`'da —
// yani kullanıcının kilitli içeriğe baktığı yerde.

/// Animasyonlu degrade ilerleme çubuğu — 800ms'de dolar.
class GradientProgressBar extends StatelessWidget {
  const GradientProgressBar({
    super.key,
    required this.label,
    required this.percent,
    this.delay = Duration.zero,
    this.color,
  });

  final String label;
  final int percent; // 0..100
  final Duration delay;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final accent = color ?? RythoColors.magenta;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Eski hâl `Row` + `Spacer` idi: iki metin de esnemiyordu, uzun
        // etiket (sunucudan gelen eksen adı) + yüzde dar ekranda satırı
        // taşırıyordu. `Wrap` sığdığında aynı görünür, sığmadığında yüzdeyi
        // alt satıra indirir. `SizedBox`: Wrap gevşek kısıtta büzülür ve
        // `spaceBetween` yayacak boşluk bulamaz.
        SizedBox(
          width: double.infinity,
          child: Wrap(
            spacing: RythoSpace.md,
            runSpacing: 2,
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.end,
            children: [
              Text(label, style: RythoText.body(13, w: FontWeight.w600)),
              Text('%$percent', style: RythoText.mono(12, color: accent))
                  .animate(delay: delay)
                  .fadeIn(duration: 500.ms),
            ],
          ),
        ),
        const SizedBox(height: 7),
        LayoutBuilder(
          builder: (_, constraints) => Stack(children: [
            Container(
              height: 7,
              width: constraints.maxWidth,
              decoration: BoxDecoration(
                color: RythoColors.inkLighter,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            Container(
              height: 7,
              width: constraints.maxWidth * (percent.clamp(0, 100) / 100),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                    colors: [RythoColors.violet, accent]),
                borderRadius: BorderRadius.circular(4),
                boxShadow: [
                  BoxShadow(
                      color: accent.withValues(alpha: 0.4), blurRadius: 8),
                ],
              ),
            )
                .animate(delay: delay)
                .scaleX(
                    begin: 0,
                    end: 1,
                    alignment: Alignment.centerLeft,
                    duration: 800.ms,
                    curve: Curves.easeOutCubic),
          ]),
        ),
      ]),
    );
  }
}

/// "Yazıyor..." üç nokta animasyonu — sohbette Rytho yanıt beklerken.
class TypingDots extends StatefulWidget {
  const TypingDots({super.key});

  @override
  State<TypingDots> createState() => _TypingDotsState();
}

class _TypingDotsState extends State<TypingDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 900))
    ..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Reduce-motion (R12-A0): noktalar sabit kalır; "yazıyor" bilgisini
    // balonun varlığı taşır.
    if (reduceMotion(context)) {
      _controller.stop();
    } else if (!_controller.isAnimating) {
      _controller.repeat();
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        gradient: RythoColors.primaryGradient,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(20),
          topRight: Radius.circular(20),
          bottomLeft: Radius.circular(6),
          bottomRight: Radius.circular(20),
        ),
      ),
      child: AnimatedBuilder(
        animation: _controller,
        builder: (_, _) => Row(mainAxisSize: MainAxisSize.min, children: [
          for (var i = 0; i < 3; i++)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2.5),
              child: Opacity(
                opacity: 0.35 +
                    0.65 *
                        (0.5 +
                            0.5 *
                                _wave(_controller.value, i)),
                child: const CircleAvatar(radius: 3.4, backgroundColor: Colors.white),
              ),
            ),
        ]),
      ),
    );
  }

  double _wave(double t, int i) {
    final phase = (t - i * 0.18) % 1.0;
    return phase < 0.5 ? (phase * 2) : (2 - phase * 2);
  }
}

/// Günlük seri rozeti: 🔥 + gün sayısı.
class StreakBadge extends StatelessWidget {
  const StreakBadge({super.key, required this.count, this.compact = true});
  final int count;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    if (count <= 0) return const SizedBox.shrink();
    return Container(
      padding: EdgeInsets.symmetric(horizontal: compact ? 10 : 14, vertical: compact ? 5 : 8),
      decoration: BoxDecoration(
        color: RythoColors.gold.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: RythoColors.gold.withValues(alpha: 0.4)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Text('🔥', style: TextStyle(fontSize: compact ? 12 : 15)),
        const SizedBox(width: 4),
        Text(AppLocalizations.of(context).streakDays(count),
            style: RythoText.label(compact ? 11 : 13, color: RythoColors.goldBright)),
      ]),
    ).animate().scale(
        begin: const Offset(0.7, 0.7),
        curve: Curves.easeOutBack,
        duration: 400.ms);
  }
}

/// Öneri çipi: sohbette tıklanınca gönderilen hazır sorular.
class SuggestionChip extends StatelessWidget {
  const SuggestionChip({super.key, required this.text, required this.onTap});
  final String text;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: RythoColors.inkLight,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: RythoColors.lilac.withValues(alpha: 0.30)),
        ),
        child: Text(text, style: RythoText.body(12.5, w: FontWeight.w600)),
      ),
    );
  }
}

/// Küçük bilgi çipi (gezegen konumu, retro vb.): koyu mor dolgu,
/// ince parlak kontur.
class InfoChip extends StatelessWidget {
  const InfoChip({super.key, required this.text, this.color});
  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final accent = color ?? RythoColors.lilac;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: RythoColors.inkLighter,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: accent.withValues(alpha: 0.35)),
      ),
      child: Text(text,
          style: RythoText.body(12, color: RythoColors.parchment, w: FontWeight.w600)),
    );
  }
}
