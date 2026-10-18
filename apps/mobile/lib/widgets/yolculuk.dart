// Yolculuk şeridi + katlanır bölüm (2026-10-18).
//
// NEDEN: İç Mevsim ve Yıl Haritası "makale gibi" açılıyordu; sahip
// "bakmak bile istemiyorum — bu yıl hangi evrenlerde gezeceğim?" dedi.
// Şerit ölçülmüş durakları (tarih, burç, ev) zaman sırasıyla gösterir;
// uzun okuma `Katlanir` içinde, isteyene açılır. İki ekran TEK bileşen
// kullanır — aynı kavramın iki kopyası ayrışır (tekleştirme doktrini).
import 'package:flutter/material.dart';

import '../theme/rytho_theme.dart';
import '../theme/rytho_tokens.dart';
import 'motion.dart';
import 'nebula_widgets.dart' show Pressable;

/// Şeridin tek durağı. `simdi` olan durak altınla vurgulanır.
class YolculukDuragi {
  const YolculukDuragi({
    required this.ust,
    required this.baslik,
    this.govde,
    this.simdi = false,
  });

  /// Küçük üst etiket: "Şu an", bir tarih, "Dönüm noktası · 2027-03".
  final String ust;
  final String baslik;
  final String? govde;
  final bool simdi;
}

/// Dikey yolculuk şeridi: solda nokta + çizgi, sağda durak.
class YolculukSeridi extends StatelessWidget {
  const YolculukSeridi({super.key, required this.duraklar});

  final List<YolculukDuragi> duraklar;

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      for (var i = 0; i < duraklar.length; i++)
        RythoReveal(
          index: i,
          child: _Durak(
            durak: duraklar[i],
            son: i == duraklar.length - 1,
          ),
        ),
    ]);
  }
}

class _Durak extends StatelessWidget {
  const _Durak({required this.durak, required this.son});

  final YolculukDuragi durak;
  final bool son;

  @override
  Widget build(BuildContext context) {
    final vurgu = durak.simdi ? RythoColors.goldBright : RythoColors.lilac;
    return IntrinsicHeight(
      child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SizedBox(
          width: RythoSpace.xl,
          child: Column(children: [
            const SizedBox(height: RythoSpace.xs),
            Container(
              width: durak.simdi ? RythoSpace.md : RythoSpace.sm,
              height: durak.simdi ? RythoSpace.md : RythoSpace.sm,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: vurgu,
                boxShadow: durak.simdi
                    ? [BoxShadow(color: vurgu, blurRadius: RythoSpace.md)]
                    : null,
              ),
            ),
            if (!son)
              Expanded(
                child: Container(
                  width: RythoSpace.xxs,
                  margin: const EdgeInsets.symmetric(vertical: RythoSpace.xs),
                  color: RythoColors.glassStroke,
                ),
              ),
          ]),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(bottom: RythoSpace.lg),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(durak.ust,
                      style: RythoType.label.copyWith(color: vurgu)),
                  const SizedBox(height: RythoSpace.xxs),
                  Text(durak.baslik, style: RythoType.cardTitle),
                  if (durak.govde != null) ...[
                    const SizedBox(height: RythoSpace.xs),
                    Text(durak.govde!, style: RythoType.bodyDim),
                  ],
                ]),
          ),
        ),
      ]),
    );
  }
}

/// Katlanır bölüm — başlık satırına dokununca açılır. Varsayılan KAPALI:
/// uzun okuma isteyene açılır, ekranı açılışta duvar gibi kaplamaz.
///
/// `baslangicAcik`: okuma HAZIR DEĞİLSE (üretilemedi / hata / bekliyor)
/// ekranlar bölümü AÇIK başlatır — "Tekrar dene" kartı katın içinde
/// saklanırsa kullanıcı başarısızlığı hiç görmez (bekçi
/// `atlas_derinlik_kabi_test` tam bunu yakaladı).
class Katlanir extends StatefulWidget {
  const Katlanir({
    super.key,
    required this.baslik,
    required this.child,
    this.baslangicAcik = false,
  });

  final String baslik;
  final Widget child;
  final bool baslangicAcik;

  @override
  State<Katlanir> createState() => _KatlanirState();
}

class _KatlanirState extends State<Katlanir> {
  late bool _acik = widget.baslangicAcik;

  @override
  Widget build(BuildContext context) {
    final sure = kapili(context, RythoMotion.base);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Pressable(
        semanticLabel: widget.baslik,
        onTap: () => setState(() => _acik = !_acik),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: RythoSpace.sm),
          child: Row(children: [
            Expanded(child: Text(widget.baslik, style: RythoType.label)),
            AnimatedRotation(
              turns: _acik ? 0.5 : 0,
              duration: sure,
              child: const Icon(Icons.expand_more,
                  color: RythoColors.parchmentDim),
            ),
          ]),
        ),
      ),
      // Sıfır sürede (hareket azaltma, `kapili`) AnimatedSize kendi
      // yerleşimi içinde kendini kirletip assert atıyor (ölçüldü) — o hâlde
      // animasyonsuz dal. `animateToPage` dersiyle aynı sınıf (CLAUDE.md §5).
      if (sure == Duration.zero)
        _acik ? widget.child : const SizedBox.shrink()
      else
        AnimatedSize(
          duration: sure,
          alignment: Alignment.topCenter,
          child:
              _acik ? widget.child : const SizedBox(width: double.infinity),
        ),
    ]);
  }
}
