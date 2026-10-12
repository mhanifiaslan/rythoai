import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../l10n/app_localizations.dart';
import '../theme/rytho_theme.dart';
import '../theme/rytho_tokens.dart';
import 'chat_bubble_icon.dart';
import 'motion.dart';

/// Yükleme iskeleti (R12-B3): [GlassPanel] boyutlarında boş blok + yumuşak
/// shimmer döngüsü. Profil gibi "boş iskeletle açılan" ekranlar, veri
/// gelene kadar içeriğin HACMİNİ gösterir — beyaz boşluk değil.
/// Reduce-motion'da shimmer hiç kurulmaz, blok sabit durur.
class SkeletonPanel extends StatelessWidget {
  const SkeletonPanel({
    super.key,
    this.height = 96,
    this.margin = const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
  });

  final double height;
  final EdgeInsets margin;

  @override
  Widget build(BuildContext context) {
    final blok = Container(
      height: height,
      margin: margin,
      decoration: BoxDecoration(
        color: RythoColors.glassFill,
        borderRadius: BorderRadius.circular(RythoRadius.card),
        border: Border.all(color: RythoColors.glassStroke),
      ),
    );
    if (reduceMotion(context)) return blok;
    return blok.animate(onPlay: (c) => c.repeat()).shimmer(
        duration: RythoMotion.shimmer,
        color: RythoColors.lilac.withValues(alpha: 0.08));
  }
}

/// Sayfa iskeleti: alt alta [SkeletonPanel] blokları, kaydırılabilir.
///
/// NEDEN: aynı üç bloklu `_Iskelet` üç ekranda birebir kopyaydı
/// (solar_return, inner_calendar, birth_hexagram), BaZi bir türevini,
/// sohbet listesi de dört eşit satırlık hâlini taşıyordu. Beş kopya beş
/// ayrı alt boşluk demekti; şimdi tek kaynak ve alt boşluk dock payını
/// token'dan alıyor (kopyalar 120 yazıyordu, dock'un ölçülmüş payı 130).
///
/// Yükseklikler sayfanın GERÇEK bölüm hacimlerini taklit etmeli ki cevap
/// gelince düzen zıplamasın — varsayılan üçlü, kapı bilinmeyen rapor
/// sayfalarının ölçüsü.
class SkeletonList extends StatelessWidget {
  const SkeletonList({
    super.key,
    this.heights = const [150, 110, 90],
    this.padding,
  });

  /// Blokların yükseklikleri, üstten alta.
  final List<double> heights;

  /// Liste dolgusu; verilmezse üstte küçük nefes, altta dock payı.
  final EdgeInsets? padding;

  @override
  Widget build(BuildContext context) => ListView(
        padding: padding ??
            const EdgeInsets.only(
                top: RythoSpace.sm, bottom: RythoSpace.dockClearance),
        children: [for (final h in heights) SkeletonPanel(height: h)],
      );
}

/// Kart dolgusunun tonu.
///
/// NEDEN: yedi yerde çıplak `Container(color: inkLighter)` kart kabı vardı
/// (friends ×4, person_form ×2, person_detail ×1) — kontur, üst kenar ışığı
/// ve köşe yarıçapı her birinde elle tekrarlanıyor ya da eksik kalıyordu.
/// Ton bir parametre olunca kap tek, yalnız dolgu değişiyor.
enum GlassTone {
  /// Standart kart: hafif saydam koyu mor (`glassFill`).
  base,

  /// Yükseltilmiş yüzey: kart ÜSTÜNDE duran iç kart, giriş alanı zemini
  /// (`inkLighter`). Saydam değil — altındaki kartın dolgusuyla karışmasın.
  raised,
}

/// v3 kart: koyu mor dolgu, 22px köşe, %6 beyaz kontur, üst kenar ışığı.
/// Adı tarihsel — artık blur zorunlu değil (blur: 0 varsayılan davranış
/// için performans dostu düz dolgu kullanılır).
class GlassPanel extends StatelessWidget {
  const GlassPanel({
    super.key,
    required this.child,
    this.label,
    this.padding = const EdgeInsets.all(16),
    this.margin = const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    this.radius = RythoRadius.card,
    this.blur = 0,
    this.glow = false,
    this.onTap,
    this.tone = GlassTone.base,
  });

  final Widget child;
  final String? label;
  final EdgeInsets padding;
  final EdgeInsets margin;
  final double radius;
  final double blur;
  final bool glow;
  final VoidCallback? onTap;

  /// Dolgu tonu — bkz. [GlassTone].
  final GlassTone tone;

  @override
  Widget build(BuildContext context) {
    final borderRadius = BorderRadius.circular(radius);
    Widget content = Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: borderRadius,
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: borderRadius,
            color: tone == GlassTone.raised
                ? RythoColors.inkLighter
                : RythoColors.glassFill,
            border: Border.all(color: RythoColors.glassStroke),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Üst kenar ışığı
              Container(
                height: 1,
                margin: EdgeInsets.symmetric(horizontal: radius * 0.8),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(colors: [
                    Colors.transparent,
                    RythoColors.glassEdge,
                    Colors.transparent,
                  ]),
                ),
              ),
              if (label != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: Text(label!,
                      style: RythoText.label(11,
                          color: RythoColors.parchmentDim)),
                ),
              Padding(padding: padding, child: child),
            ],
          ),
        ),
      ),
    );

    if (blur > 0) {
      content = BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: content,
      );
    }

    return Container(
      margin: margin,
      decoration: glow
          ? BoxDecoration(borderRadius: borderRadius, boxShadow: const [
              BoxShadow(color: RythoColors.goldGlow, blurRadius: 26, spreadRadius: -6),
            ])
          : null,
      child: ClipRRect(borderRadius: borderRadius, child: content),
    );
  }
}

/// v3 alt gezinme: ince koyu saydam bar, 4 sade outline ikon + ORTADA
/// yukarı taşan, degrade dolgulu, glow'lu dairesel AI butonu.
class CosmicDock extends StatelessWidget {
  const CosmicDock({
    super.key,
    required this.items,
    required this.index,
    required this.onChanged,
    required this.onCenterTap,
  });

  /// 4 öğe beklenir: ilk 2'si merkezin solunda, son 2'si sağında.
  final List<({IconData icon, IconData activeIcon, String label})> items;
  final int index;
  final ValueChanged<int> onChanged;
  final VoidCallback onCenterTap;

  @override
  Widget build(BuildContext context) {
    final bottomPad = MediaQuery.of(context).padding.bottom;
    return SizedBox(
      height: 86 + bottomPad,
      child: Stack(clipBehavior: Clip.none, alignment: Alignment.bottomCenter, children: [
        // Bar
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          height: 64 + bottomPad,
          child: ClipRect(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
              child: Container(
                padding: EdgeInsets.only(bottom: bottomPad),
                decoration: const BoxDecoration(
                  color: Color(0xCC120B1C),
                  border: Border(top: BorderSide(color: RythoColors.glassStroke)),
                ),
                child: Row(children: [
                  for (var i = 0; i < 2; i++)
                    Expanded(child: _DockItem(
                      item: items[i],
                      active: index == i,
                      onTap: () {
                        HapticFeedback.selectionClick();
                        onChanged(i);
                      },
                    )),
                  // Merkez buton boşluğu
                  const SizedBox(width: 72),
                  for (var i = 2; i < items.length; i++)
                    Expanded(child: _DockItem(
                      item: items[i],
                      active: index == i,
                      onTap: () {
                        HapticFeedback.selectionClick();
                        onChanged(i);
                      },
                    )),
                ]),
              ),
            ),
          ),
        ),
        // Merkez AI butonu — yukarı taşar, sürekli yumuşak glow pulse
        Positioned(
          bottom: 26 + bottomPad,
          child: _CenterAiButton(onTap: onCenterTap),
        ),
      ]),
    );
  }
}

/// Nefes alan merkez sohbet butonu: jest, haptic, erişilebilirlik ve
/// basma tepkisi burada; ÇİZİMİN TAMAMI `ChatBubblesIcon`'da (PZ3).
///
/// Kap da glif de o widget'ın işi — burada yalnız ölçek nefesi var ve o
/// da aynı kosinüsten sürülür, böylece iki hareket tek fazda kalır.
/// reduceMotion'da faz sabitlenir (t = 0) ve denetleyici hiç kurulmaz.
class _CenterAiButton extends StatefulWidget {
  const _CenterAiButton({required this.onTap});
  final VoidCallback onTap;

  @override
  State<_CenterAiButton> createState() => _CenterAiButtonState();
}

class _CenterAiButtonState extends State<_CenterAiButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
      vsync: this, duration: RythoMotion.breath)
    // Tek yönlü döngü: faz 0→1, sonra başa. `ChatBubblesIcon` t=0 ile
    // t=1'de AYNI kareyi çizdiği için dikiş görünmez. Süre 1600'den
    // 3000'e çıktı — geri sarma kalkınca tam tur yarı yarıya kısalırdı.
    ..repeat();
  bool _pressed = false;

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Reduce-motion (R12-A0): nefes durur; basma tepkisi (kullanıcının kendi
    // eylemine anlık cevap) kalır — rahatsız eden şey kendiliğinden hareket.
    if (reduceMotion(context)) {
      _pulse.stop();
    } else if (!_pulse.isAnimating) {
      _pulse.repeat();
    }
    final hareketsiz = reduceMotion(context);
    return Semantics(
      button: true,
      label: AppLocalizations.of(context).chatOpenLabel,
      child: GestureDetector(
        onTapDown: (_) => setState(() => _pressed = true),
        onTapCancel: () => setState(() => _pressed = false),
        onTapUp: (_) {
          setState(() => _pressed = false);
          HapticFeedback.mediumImpact();
          widget.onTap();
        },
        child: AnimatedBuilder(
        animation: _pulse,
        builder: (_, _) {
          // Faz HAM verilir (easeInOut YOK) ve denetleyici `repeat()` ile
          // tek yönlü döner: `ChatBubblesIcon` yumuşatmayı kendi içinde
          // kosinüsle yapıyor ve t=0 ile t=1 aynı kareyi veriyor, yani
          // sarma yerinde sıçrama olmuyor. Eski `repeat(reverse: true)`
          // daktilo ritmini geri sarıyordu — noktalar ileri yazıp geri
          // silmiş gibi okunuyordu.
          final t = _pulse.value;
          // Ölçek nefesi de aynı kosinüsten: glow ile birlikte alıp verir,
          // döngü başında zıplamaz.
          final nefes = 0.5 - 0.5 * math.cos(2 * math.pi * t);
          final scale = (_pressed ? 0.94 : 1.0) * (1.0 + 0.05 * nefes);
          // Görselin TAMAMI (balon kap + çift balon glifi + glow) artık
          // `ChatBubblesIcon`'ın işi (PZ3); burada yalnız jest, haptic,
          // erişilebilirlik ve basma tepkisi kalıyor. Eski hâli üç
          // animasyonlu noktaydı ve kullanıcı "kafa karıştırıyor" dedi —
          // üç nokta tek başına "yükleniyor" da demektir.
          return Transform.scale(
            scale: scale,
            child: ChatBubblesIcon(t: hareketsiz ? 0.0 : t),
          );
        },
        ),
      ),
    );
  }
}

class _DockItem extends StatelessWidget {
  const _DockItem({
    required this.item,
    required this.active,
    required this.onTap,
  });

  final ({IconData icon, IconData activeIcon, String label}) item;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // Ekran okuyucu her sekmeyi "düğme, seçili" diye duymalı (GlassSegments
    // ile aynı gerekçe): çıplak `GestureDetector` rol vermiyordu, TalkBack
    // dock'u dört etiketsiz ikon olarak okuyordu. Alt ağaç dışlanır ki
    // etiket iki kez okunmasın.
    return Semantics(
      button: true,
      selected: active,
      label: item.label,
      excludeSemantics: true,
      onTap: onTap,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: AnimatedScale(
          scale: active ? 1.0 : 0.92,
          // Süre token'dan ve hareket azaltma KAPISINDAN: dock ölçeği
          // depodaki son çıplak+kapısız örtük animatördü (D5 ölçümü).
          duration: kapili(context, RythoMotion.slow),
          curve: Curves.easeOutBack,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ShaderMask(
                shaderCallback: (bounds) => (active
                        ? RythoColors.primaryGradient
                        : const LinearGradient(colors: [
                            RythoColors.parchmentDim,
                            RythoColors.parchmentDim,
                          ]))
                    .createShader(bounds),
                child: Icon(active ? item.activeIcon : item.icon,
                    size: 23, color: Colors.white),
              ),
              const SizedBox(height: 3),
              Text(item.label,
                  style: RythoType.label.copyWith(
                      color: active
                          ? RythoColors.parchment
                          : RythoColors.parchmentDim)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Segment seçici — seçili segment **ince bir zemin farkıyla** belirtilir.
///
/// ## Neden degrade değil
///
/// Seçili segment eskiden `primaryGradient` + `goldGlow` alıyordu; yani
/// birincil butonla **birebir aynı** görsel muameleyi. Giriş ekranında
/// sonucu şuydu — kullanıcının kendi ifadesi:
///
/// > "giriş yap, üye ol tab isimleri giriş yap butonlarına benziyor ve
/// > tıklanılarak girileceğini çağrıştırıyor, bu yanlış bir his."
///
/// Doğru teşhis: segment bir **durum göstergesi**, buton bir **eylem**.
/// İkisine aynı ağırlığı verirsen kullanıcı sekmeye basınca giriş yapacağını
/// sanır. Degrade ve glow yalnızca eyleme ait.
class GlassSegments extends StatelessWidget {
  const GlassSegments({
    super.key,
    required this.labels,
    this.index,
    required this.onChanged,
    this.compact = false,
    this.margin = const EdgeInsets.symmetric(horizontal: RythoSpace.lg),
  });

  final List<String> labels;

  /// Dış kenar. Varsayılan ekran kenarı (`lg`); form ya da panel İÇİNDE
  /// kullanan çağıran `EdgeInsets.zero` verir — eski sabit kenar sihirbazda
  /// 40 dp, İ Ching'de 32 dp içeri itiyordu (ölçüldü, D3/D6 notları).
  final EdgeInsets margin;

  /// Seçili segment; `null` = hiçbiri seçili. NEDEN nullable: cinsiyet
  /// seçici gibi "henüz seçilmedi" hâli olan formlar ilk açılışta bir
  /// segmenti seçili GÖSTEREMEZ — kullanıcı seçmediği şeyi beyan etmiş
  /// olurdu (ölçülmeyen söylenmez). Eski çağıranlar `index: 0` geçmeye
  /// devam ediyor.
  final int? index;
  final ValueChanged<int> onChanged;

  /// Sıkışık boy: 36 dp, 11 pt etiket. Form içi seçiciler (cinsiyet, saat
  /// biliniyor mu) tam boy sekme çubuğunun ağırlığını taşımamalı.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: compact ? 36 : 42,
      margin: margin,
      padding: const EdgeInsets.all(RythoSpace.xs),
      decoration: BoxDecoration(
        color: RythoColors.glassFill,
        borderRadius: BorderRadius.circular(RythoRadius.md),
        border: Border.all(color: RythoColors.glassStroke),
      ),
      child: Row(children: [
        for (var i = 0; i < labels.length; i++)
          Expanded(
            // Ekran okuyucu her segmenti "düğme, seçili" diye duymalı;
            // çıplak Text yalnız metni okur ve kullanıcı hangi sekmede
            // olduğunu bilemez. Alt ağaç dışlanır ki etiket iki kez
            // okunmasın (Semantics + Text).
            child: Semantics(
              button: true,
              selected: index == i,
              label: labels[i],
              excludeSemantics: true,
              onTap: () => _sec(i),
              child: GestureDetector(
                onTap: () => _sec(i),
                child: AnimatedContainer(
                  duration: kapili(context, RythoMotion.base),
                  curve: RythoMotion.enter,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    // Degrade ve glow YOK — bkz. sınıf açıklaması.
                    color: index == i
                        ? RythoColors.parchment.withValues(alpha: 0.10)
                        : null,
                    borderRadius: BorderRadius.circular(RythoRadius.sm),
                  ),
                  child: Text(labels[i],
                      style: RythoText.label(compact ? 11 : 12,
                          color: index == i
                              ? RythoColors.parchment
                              : RythoColors.parchmentDim)),
                ),
              ),
            ),
          ),
      ]),
    );
  }

  void _sec(int i) {
    HapticFeedback.selectionClick();
    onChanged(i);
  }
}
