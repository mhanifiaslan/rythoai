import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/app_localizations.dart';
import '../theme/rytho_theme.dart';
import '../theme/rytho_tokens.dart';
import 'markdown_text.dart';
import 'motion.dart';
import 'nebula_widgets.dart' show Pressable;

/// CTA butonu — iki ağırlıkta.
///
/// `filled: true` (varsayılan) birincil: mor→magenta degrade, glow.
/// `filled: false` ikincil: dolgusuz, ince kontur, glow yok.
///
/// **İkincil varyant bir dönem YOKTU.** Parametre tanımlıydı ama gövdede hiç
/// okunmuyordu; `filled: false` geçen çağrılar sessizce birincil buton
/// üretiyordu. Sonucu giriş ekranında görülüyordu: e-posta, Apple ve Google
/// butonları birebir aynı degradede alt alta duruyor, hangisinin asıl yol
/// olduğu anlaşılmıyordu. Bir ekranda birden fazla "birincil" varsa hiçbiri
/// birincil değildir.
///
/// Adı tarihsel (v1 "altın buton"); renk v3'te mor.
///
/// **Degrade `ctaGradient`, `primaryGradient` DEĞİL** (sahip kararı K5):
/// beyaz metin `primaryGradient`'ın magenta ucunda 3,36:1 ölçüldü, AA
/// eşiği 4,5. Bu düğme METİN taşıyor, o yüzden koyu kardeşe geçti (her
/// durak ≥ 4,6, `kontrast_test` bekçili). Dekoratif yüzeyler (dock merkezi,
/// avatar halkası) `primaryGradient`'ta kalır — onların üstünde metin yok.
///
/// `destructive: true` → hesap silme gibi geri dönüşsüz eylem: düz
/// `madder` dolgu, degrade YOK, glow YOK (design-system: "hesap silme:
/// süs yok" — parıltı davet eder, bu eylem davet edilmez). Metin `ink`:
/// `onGradient` (beyaz) madder üstünde 2,74:1 ölçüldü — AA'nın (4,5)
/// altı, büyük metin eşiğinin (3,0) bile altı. `ink` 7,29:1. K5'in
/// gerekçesi tam da buydu: metin taşıyan yüzey, metnin okunduğu renkte.
class GoldButton extends StatefulWidget {
  const GoldButton({
    super.key,
    required this.text,
    this.onPressed,
    this.busy = false,
    this.filled = true,
    this.destructive = false,
    this.icon,
  });

  final String text;
  final VoidCallback? onPressed;
  final bool busy;

  /// `false` → ikincil ağırlık. Bir ekranda yalnızca BİR tane `true` olmalı.
  final bool filled;

  /// Yıkıcı eylem (hesap silme). `filled`in önüne geçer: ne degrade ne glow.
  final bool destructive;

  /// Metnin solunda küçük bir işaret (ör. sağlayıcı logosu).
  final Widget? icon;

  @override
  State<GoldButton> createState() => _GoldButtonState();
}

class _GoldButtonState extends State<GoldButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null && !widget.busy;
    final yikici = widget.destructive;
    final birincil = widget.filled && !yikici;

    // Dolgu tek yerde çözülür; dört hâl (devre dışı / yıkıcı / birincil /
    // ikincil) birbirini dışlar. Devre dışı hâl eskiden "iki durağı aynı
    // olan degrade" idi — degrade sayan bekçiler onu birincil sanırdı.
    final Gradient? degrade = birincil && enabled ? RythoColors.ctaGradient : null;
    final Color? dolgu = degrade != null
        ? null
        : (yikici && enabled ? RythoColors.madder : RythoColors.inkLighter);
    final Color metin = !enabled
        ? RythoColors.parchmentDim
        : yikici
            ? RythoColors.ink
            : birincil
                ? RythoColors.onGradient
                : RythoColors.parchment;

    return GestureDetector(
      onTapDown: enabled ? (_) => setState(() => _pressed = true) : null,
      onTapCancel: () => setState(() => _pressed = false),
      onTapUp: enabled
          ? (_) {
              setState(() => _pressed = false);
              HapticFeedback.lightImpact();
              widget.onPressed!();
            }
          : null,
      // Rol ve etiket düğümde: meşgulken metin yerine usturlap çiziliyor,
      // yani ekran okuyucu etiketi ÇOCUKTAN alamaz — düğüm taşır.
      // `excludeSemantics`: çocuk metni ayrıca duyurulursa etiket iki kez
      // okunur. Jest dedektörü dışarıda kalır ki dokunma eylemi düğüme
      // birleşsin. `liveRegion` meşguliyette açılır: düğme devre dışına
      // düşerken düğüm canlı bölge olur, etiket korunur.
      child: Semantics(
        button: true,
        enabled: enabled,
        liveRegion: widget.busy,
        label: widget.text,
        excludeSemantics: true,
        child: AnimatedScale(
          scale: _pressed ? 0.96 : 1.0,
          duration: kapili(context, RythoMotion.press),
          curve: RythoMotion.settle,
          child: Container(
            height: 52,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              gradient: degrade,
              color: dolgu,
              border: Border.all(
                color: birincil || yikici
                    ? RythoColors.onGradient.withValues(alpha: 0.12)
                    : RythoColors.lilac.withValues(alpha: 0.26),
              ),
              // Glow YALNIZCA birincilde. İkincil butonun da parlaması,
              // hiyerarşiyi yeniden siler; yıkıcının parlaması davet eder.
              boxShadow: birincil && enabled
                  ? const [
                      BoxShadow(
                          color: RythoColors.goldGlow,
                          blurRadius: 22,
                          spreadRadius: -4)
                    ]
                  : null,
            ),
            child: widget.busy
                ? const SizedBox(
                    width: 22, height: 22, child: AstrolabeSpinner(size: 22))
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (widget.icon != null) ...[
                        widget.icon!,
                        const SizedBox(width: 10),
                      ],
                      // Düğme metni esnemiyordu: bu düğme yer yer sabit
                      // genişlikli kutuya (ör. `SizedBox(width: 104)`)
                      // konuyor; uzun etiket + büyük yazı ölçeğinde sağdan
                      // taşıyordu. `Flexible` metni sarmalarına izin verir.
                      Flexible(
                        child: Text(widget.text,
                            textAlign: TextAlign.center,
                            style: RythoText.label(14, color: metin)),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

/// Bölüm ayracı: ince çizgi, merkezde ✦.
class SectionDivider extends StatelessWidget {
  const SectionDivider({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
      child: Row(children: [
        const Expanded(child: Divider()),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text('✦', style: RythoText.mono(10, color: RythoColors.lilac)),
        ),
        const Expanded(child: Divider()),
      ]),
    );
  }
}

/// AI metni: sol kenarı mor degrade çizgili not bloğu.
class MarginNote extends StatelessWidget {
  const MarginNote({super.key, required this.text, this.title});

  final String text;
  final String? title;

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            width: 3,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [RythoColors.violet, RythoColors.magenta],
              ),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (title != null) ...[
                  Text(title!,
                      style: RythoText.label(11, color: RythoColors.lilac)),
                  const SizedBox(height: 6),
                ],
                // Beş çağıranın beşi de LLM rapor metni basıyor; düz `Text`
                // modelin `### Başlık` ve `**vurgu**` işaretlerini ham
                // gösteriyordu (cihaz turu bulgusu).
                MarkdownText(text,
                    baseStyle: RythoText.body(15, height: 1.65)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Okumanın altındaki sohbet kapısı — "✦ Rytho'ya sor →".
///
/// NEDEN TEK YERDE: beş teknik ekranın beşine de aynı satır giriyor ve bu
/// depoda ölçülmüş bir ders var — bir metnin beş kopyası varsa dördü
/// ayrışır (gizlilik politikası, `test_besinci_kopya_geri_dogmaz`).
/// Etiket de `l10n.signalAsk`'ten okunuyor: sinyal kartı, ilişki ekseni ve
/// bu beş ekran aynı sözcüğü kullanmalı.
///
/// NEDEN `GoldButton` DEĞİL: altın düğme satın alma/onay gibi gerçek
/// birincil eylemlere ayrılmış. Bu bir DAVET — sayfanın sonunda duran,
/// isteyenin dokunduğu bir kapı. Kullanıcı bu ekrana zaten okumak için
/// geldi; davet okumayı gölgelemez.
///
/// ⚠️ Dokunma alanı ayrı ayarlandı: emsal (`relationship_screen`) satırı
/// 11.5 px çıplak metindi ve uzun bir kaydırmanın dibinde 17 px'lik bir
/// hedef bırakıyordu. Dikey 14 px dolgu alanı ~44 px'e çıkarıyor —
/// Material'ın en küçük dokunulabilir hedefi.
class RythoyaSor extends StatelessWidget {
  const RythoyaSor({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    // DÜĞME GİBİ GÖRÜNÜR (cihaz bulgusu, 2026-10-14): eski hâl çıplak lila
    // metindi ("✦ Rytho'ya sor →") ve kullanıcı dokunulabilir olduğunu
    // anlamıyordu. Hap: lila kontur + hafif dolgu + ikon + ok. Altın CTA
    // DEĞİL — bu bir sohbet kapısı, satın alma değil; ikisi aynı görünse
    // "Rytho'ya sor" para ister gibi okunurdu.
    return Pressable(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(
            horizontal: RythoSpace.lg, vertical: RythoSpace.sm),
        decoration: BoxDecoration(
          color: RythoColors.lilac.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(RythoRadius.pill),
          border: Border.all(color: RythoColors.lilac.withValues(alpha: 0.55)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.auto_awesome_rounded,
              size: 16, color: RythoColors.lilac),
          const SizedBox(width: RythoSpace.sm),
          Flexible(
            child: Text(l10n.signalAsk,
                style: RythoText.body(13,
                    color: RythoColors.lilac, w: FontWeight.w600)),
          ),
          const SizedBox(width: RythoSpace.xs),
          const Icon(Icons.arrow_forward_rounded,
              size: 16, color: RythoColors.lilac),
        ]),
      ),
    );
  }
}

// `TypewriterText` KALDIRILDI (Tasarım A2). Uzun okuma metnini harf harf
// yazdırmak, metin akıştan kendi sayfasına taşındıktan sonra okumayı
// yavaşlatan bir süse dönüştü.


/// Yükleme göstergesi: dönen usturlap kadranı.
class AstrolabeSpinner extends StatefulWidget {
  const AstrolabeSpinner({super.key, this.size = 44});
  final double size;

  @override
  State<AstrolabeSpinner> createState() => _AstrolabeSpinnerState();
}

class _AstrolabeSpinnerState extends State<AstrolabeSpinner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller =
      AnimationController(vsync: this, duration: RythoMotion.spinnerTur)
        ..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Reduce-motion (R12-A0): ibre durur, kadran statik kalır — "bekleniyor"
    // bilgisini kadranın varlığı taşımaya devam eder.
    if (reduceMotion(context)) {
      _controller.stop();
    } else if (!_controller.isAnimating) {
      _controller.repeat();
    }
    return DecoratedBox(
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(color: RythoColors.goldGlow, blurRadius: 24, spreadRadius: -4),
        ],
      ),
      child: AnimatedBuilder(
        animation: _controller,
        builder: (_, _) => CustomPaint(
          size: Size.square(widget.size),
          painter: _AstrolabePainter(angle: _controller.value * 2 * math.pi),
        ),
      ),
    );
  }
}

class _AstrolabePainter extends CustomPainter {
  _AstrolabePainter({required this.angle});
  final double angle;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.width / 2 - 1;
    final line = Paint()
      ..color = RythoColors.line
      ..style = PaintingStyle.stroke;
    final gold = Paint()
      ..color = RythoColors.lilac
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;

    canvas.drawCircle(center, radius, line);
    canvas.drawCircle(center, radius * 0.62, line);

    // Tik işaretleri
    for (var i = 0; i < 24; i++) {
      final a = i * math.pi / 12;
      final isMajor = i % 6 == 0;
      final start = center + Offset(math.cos(a), math.sin(a)) * radius;
      final end = center +
          Offset(math.cos(a), math.sin(a)) * (radius - (isMajor ? 5 : 2.5));
      canvas.drawLine(start, end, isMajor ? gold : line);
    }

    // Dönen ibre (alidade)
    final tip = center + Offset(math.cos(angle), math.sin(angle)) * radius * 0.85;
    final tail = center - Offset(math.cos(angle), math.sin(angle)) * radius * 0.35;
    canvas.drawLine(tail, tip, gold);
    canvas.drawCircle(center, 1.6, gold..style = PaintingStyle.fill);
  }

  @override
  bool shouldRepaint(_AstrolabePainter old) => old.angle != angle;
}

// `ZodiacRing` SİLİNDİ (KL-turu): dekoratif çemberdi — açı ağı yok, dokunma
// yok, ev yok. Son tüketicisi "Şu an gökyüzünde" sayfasıydı; o sayfa doğum
// haritası analiziyle aynı dile geçince (`ChartWheel` + `ChartData.fromSky`)
// çemberin işlevi kalmadı. Gökyüzü çarkını arayan `widgets/chart/` altına
// bakmalı; ölçüm ve çizim orada tek yerde.
