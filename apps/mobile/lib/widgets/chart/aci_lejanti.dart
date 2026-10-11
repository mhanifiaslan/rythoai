/// Açı sınıfı lejantı ve çizgi örneği — çizgi dilinin ressam DIŞINDAKİ iki
/// tüketicisi (lejant satırı, açı tablosu hücresi / açı listesi satırı).
///
/// NEDEN ayrı dosya: `chart_palette.dart` saf `dart:ui` kalır (ressam ve
/// testler Flutter widget ağacı olmadan okur); burası widget. Örnek çizgi
/// ressamla AYNI [drawAspectLine]'ı çağırır — lejantın gösterdiği kesik,
/// çarkta çizilen kesiğin kendisidir, ikinci bir çizim yolu yok.
library;

import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../theme/rytho_theme.dart';
import '../../theme/rytho_tokens.dart';
import 'chart_palette.dart';

/// Yatay kısa çizgi: [dil] ile kesilir, [renk] ile boyanır.
class AciCizgiOrnegi extends StatelessWidget {
  const AciCizgiOrnegi({
    super.key,
    required this.dil,
    required this.renk,
    this.genislik = 22,
    this.kalinlik = 1.6,
  });

  final AspectDash dil;
  final Color renk;
  final double genislik;
  final double kalinlik;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(genislik, kalinlik + 2),
      painter: _CizgiRessami(dil: dil, renk: renk, kalinlik: kalinlik),
    );
  }
}

class _CizgiRessami extends CustomPainter {
  const _CizgiRessami(
      {required this.dil, required this.renk, required this.kalinlik});

  final AspectDash dil;
  final Color renk;
  final double kalinlik;

  @override
  void paint(Canvas canvas, Size size) {
    final y = size.height / 2;
    drawAspectLine(
        canvas,
        Offset(0, y),
        Offset(size.width, y),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = kalinlik
          ..strokeCap = StrokeCap.round
          ..color = renk,
        dil);
  }

  @override
  bool shouldRepaint(_CizgiRessami old) =>
      old.dil != dil || old.renk != renk || old.kalinlik != kalinlik;
}

/// Açı sınıfı satırı: "— Sert · – – Yumuşak · ·· Minör" + Y/A dipnotu.
///
/// Minör satırı yalnız [showMinors] açıkken: minörler kapalıyken çarkta
/// kısa kesik çizgi YOK, lejantta anlatmak çizilmeyen şeyi beyan etmek
/// olurdu. Y/A dipnotu yalnız [hareketVar] ise — harf hiçbir hücrede
/// basılmıyorsa açıklaması da basılmaz (sinastri/natal yükü `movement`
/// taşımıyor; yalnız transit açıları taşır).
///
/// Sınıf adları filtre çiplerinin anahtarlarını (`chartFilterHard/Soft/
/// Minors`) yeniden kullanır: lejant ile çip aynı sözcüğü söyler.
class AciSinifiLejanti extends StatelessWidget {
  const AciSinifiLejanti({
    super.key,
    required this.showMinors,
    required this.hareketVar,
  });

  final bool showMinors;
  final bool hareketVar;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    Widget satir(AspectDash dil, Color renk, String ad) =>
        Row(mainAxisSize: MainAxisSize.min, children: [
          AciCizgiOrnegi(dil: dil, renk: renk),
          const SizedBox(width: RythoSpace.xs),
          Flexible(
            child: Text(ad,
                style: RythoText.body(11.5, color: RythoColors.parchmentDim)),
          ),
        ]);

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Wrap(spacing: RythoSpace.lg, runSpacing: RythoSpace.xs, children: [
        satir(AspectDash.solid, aspectColor('square'), l10n.chartFilterHard),
        satir(AspectDash.long, aspectColor('trine'), l10n.chartFilterSoft),
        if (showMinors)
          satir(AspectDash.short, kMinorAspectColor, l10n.chartFilterMinors),
      ]),
      if (hareketVar)
        Padding(
          padding: const EdgeInsets.only(top: RythoSpace.xs),
          child: Text(l10n.chartMovementLegend,
              style: RythoText.mono(10, color: RythoColors.parchmentDim)),
        ),
    ]);
  }
}
