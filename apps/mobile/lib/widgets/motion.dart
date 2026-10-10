import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../theme/rytho_theme.dart';
import '../theme/rytho_tokens.dart';
import 'atlas_widgets.dart' show AstrolabeSpinner;

/// Hareket yardımcıları (R12-A0).
///
/// Bu dosyadan önce beş ekran aynı stagger yardımcısını kopyalayıp farklı
/// adımlarla (40/60/70/130/140ms) çalıştırıyordu ve sistemin "animasyonları
/// azalt" tercihi hiçbir yerde okunmuyordu. Giriş animasyonunun tek varisi
/// [RythoReveal], uzun bekleyişlerin tek sahnesi [StagedWaiting], erişilebilir
/// hareketin tek kapısı [reduceMotion] artık burada.

/// Sistem "animasyonları azalt" diyor mu — merkezi kapı.
///
/// Sürekli dönen animatörler (yıldız alanı, usturlap, nefes butonu) bu kapı
/// açıkken TEK statik karede durur; giriş animasyonları hiç kurulmaz.
/// Vestibüler rahatsızlığı olan kullanıcı için bu bir süs tercihi değil,
/// kullanılabilirlik şartı.
bool reduceMotion(BuildContext context) =>
    MediaQuery.of(context).disableAnimations;

/// Örtük animatörler için kapı: `AnimatedScale`, `AnimatedOpacity`,
/// `AnimatedCrossFade`, `animateToPage` gibi süre alan her çağrı süresini
/// buradan alır — hareket azaltma açıkken `Duration.zero` (anında).
///
/// NEDEN: [reduceMotion] yalnız `.animate()` zincirlerini kapatıyordu;
/// örtük animatörler çıplak süreyle kapısız çalışıyordu (ölçüldü: dock
/// ölçeği 320 ms, sekme geçişi 280 ms, hikâye sayfa kaydırması). Kapı tek
/// satır olunca çağrı yerinde gerekçe aramak gerekmiyor.
Duration kapili(BuildContext context, Duration sure) =>
    reduceMotion(context) ? Duration.zero : sure;

/// Kademeli giriş — kopyala-yapıştır stagger sayaçlarının tek varisi.
///
/// `RythoReveal(index: i, child: ...)`: öğe [index] sırasına göre
/// `RythoMotion.stagger` katıyla gecikir, `slow` sürede belirir ve
/// [slide] kadar aşağıdan `enter` eğrisiyle yerine oturur.
/// Reduce-motion açıkken çocuk çıplak döner — gecikme dahil hiçbir şey yok
/// (geciken görünmezlik, animasyonsuzluktan daha rahatsız edicidir).
class RythoReveal extends StatelessWidget {
  const RythoReveal({
    super.key,
    required this.child,
    this.index = 0,
    this.slide = 0.06,
  });

  final Widget child;

  /// Stagger sırası: 0 ilk blok, 1 bir adım gecikir...
  final int index;

  /// slideY başlangıcı (yükseklik oranı). 0 verilirse yalnız fade.
  final double slide;

  @override
  Widget build(BuildContext context) {
    if (reduceMotion(context)) return child;
    var zincir = child
        .animate(delay: RythoMotion.stagger * index)
        .fadeIn(duration: RythoMotion.slow);
    if (slide != 0) {
      zincir = zincir.slideY(begin: slide, curve: RythoMotion.enter);
    }
    return zincir;
  }
}

/// Aşama metinli bekleme sahnesi — `_FirasaWaiting`'in genelleştirilmiş hâli
/// (Revize R5'te yüz okuma için bulunan çözüm, R12'de tüm uzun bekleyişlere).
///
/// Usturlap döner, altında [stages] metinleri [interval] arayla değişir ve
/// SON aşamada DURUR: dönüp başa saran metin "takıldı" hissi verir. Uydurma
/// yüzde çubuğu yok — sürecin süresi LLM'e bağlı ve bilinmiyor; bilmediğimiz
/// şeyi biliyormuş gibi göstermiyoruz.
class StagedWaiting extends StatefulWidget {
  const StagedWaiting({
    super.key,
    required this.stages,
    this.interval = RythoMotion.asamaAraligi,
    this.spinnerSize = 44,
    this.visual,
  });

  /// Sırayla gösterilecek aşama metinleri (en az 1).
  final List<String> stages;

  /// İki aşama arasındaki süre.
  final Duration interval;

  final double spinnerSize;

  /// Usturlap yerine geçen sahne (PBZ): BaZi luopan kare dizisi gibi.
  /// Düz alan, varsayılan yok — kurucu `const` kalsın; null ise
  /// `AstrolabeSpinner(size: spinnerSize)`.
  final Widget? visual;

  @override
  State<StagedWaiting> createState() => _StagedWaitingState();
}

class _StagedWaitingState extends State<StagedWaiting> {
  int _asama = 0;
  Timer? _sayac;

  @override
  void initState() {
    super.initState();
    _sayac = Timer.periodic(widget.interval, (t) {
      if (!mounted) return;
      if (_asama >= widget.stages.length - 1) {
        t.cancel();
        return;
      }
      setState(() => _asama++);
    });
  }

  @override
  void dispose() {
    _sayac?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          widget.visual ?? AstrolabeSpinner(size: widget.spinnerSize),
          const SizedBox(height: 20),
          AnimatedSwitcher(
            duration: RythoMotion.slow,
            transitionBuilder: (child, anim) => FadeTransition(
              opacity: anim,
              child: SlideTransition(
                position:
                    Tween(begin: const Offset(0, 0.3), end: Offset.zero)
                        .animate(CurvedAnimation(
                            parent: anim, curve: RythoMotion.enter)),
                child: child,
              ),
            ),
            child: Text(
              widget.stages[_asama],
              key: ValueKey(_asama),
              textAlign: TextAlign.center,
              style: RythoText.body(14, color: RythoColors.parchmentDim),
            ),
          ),
        ],
      ),
    );
  }
}
