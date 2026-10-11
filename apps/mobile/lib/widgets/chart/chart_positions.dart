/// Konum tablosu — çarkın erişilebilir (TalkBack) ve okunabilir temsili.
///
/// ## Neden ayrı dosya
///
/// Tablo, Harita İnceleme ekranının içinde ÖZEL bir sınıf olarak doğdu
/// (HI-turu). "Şu an gökyüzünde" sayfası da aynı tabloyu isteyince tek
/// gerçek seçenek onu ortak bir bileşene çıkarmaktı: kopyalasaydık, glif
/// kümesi ya da derece biçimi değiştiğinde biri güncellenip diğeri geride
/// kalırdı — bu kod tabanında iki kez yaşanmış bir kusur sınıfı.
///
/// Kanvas TalkBack'e görünmez; ekran okuyucu kullanan kişi için çarkın
/// karşılığı BU tablodur. Bu yüzden her noktanın adı, burcu, derecesi ve
/// (varsa) evi düz metin olarak yazılır.
library;

import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../theme/rytho_theme.dart';
import '../glass.dart';
import '../nebula_widgets.dart' show signDisplayName;
import 'chart_data.dart';
import 'chart_palette.dart';
import 'wheel_glyphs.dart';

/// Gezegen glifi için mini çizim — güvenli kümede olmayan semboller
/// (♅ ⚷ ⚸ gibi) Android'de renkli emojiye dönebildiği için vektör.
class MiniGlyphPainter extends CustomPainter {
  const MiniGlyphPainter(this.name, this.color);

  final String name;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawPath(
        specialGlyphPath(
            name, Offset(size.width / 2, size.height / 2), size.width),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.1
          ..strokeCap = StrokeCap.round
          ..color = color);
  }

  @override
  bool shouldRepaint(MiniGlyphPainter old) =>
      old.name != name || old.color != color;
}

/// [ChartData]'daki noktaları burç + derece + ev + retro olarak listeler.
///
/// [showTitle] kapatılabilir: çağıran ekran kendi başlığını çiziyorsa
/// (modül dili) tablo başlıksız gelir.
class ChartPositionsTable extends StatelessWidget {
  const ChartPositionsTable({
    super.key,
    required this.data,
    this.showTitle = true,
  });

  final ChartData data;
  final bool showTitle;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (showTitle) ...[
        Text(l10n.chartPositionsTitle,
            style: RythoText.mono(10, color: RythoColors.parchmentDim)),
        const SizedBox(height: 6),
      ],
      GlassPanel(
        child: Column(children: [
          for (var r = 0; r < data.rings.length; r++) ...[
            if (data.isBiWheel)
              Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Text(
                      r == 0
                          ? l10n.chartLegendInner(data.rings[r].label)
                          : l10n.chartLegendOuter(data.rings[r].label),
                      style: RythoText.label(10,
                          color: RythoColors.parchmentDim)),
                ),
              ),
            for (final p in data.rings[r].points.where((p) => !p.isAngle))
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2.5),
                child: Row(children: [
                  SizedBox(
                    width: 22,
                    // Halka rengi çarkla AYNI kuraldan (ringGlyphColor):
                    // tablo sinastri partnerini lila, çark altın çiziyordu.
                    child: kPlanetTextGlyphs.containsKey(p.name)
                        ? Text(kPlanetTextGlyphs[p.name]!,
                            style: RythoText.glyph(13,
                                color: ringGlyphColor(data, r)))
                        : CustomPaint(
                            size: const Size(13, 13),
                            painter: MiniGlyphPainter(
                                p.name, ringGlyphColor(data, r))),
                  ),
                  Expanded(
                      child: Text(p.localName, style: RythoText.body(13))),
                  // Derece dizgisi (burç adı + derece + ev + R) uzun ve
                  // dile bağlı; esnemeyince `Expanded` gezegen adı sıfıra
                  // inse bile satır taşıyordu. `Flexible` sarmasına izin
                  // verir — sayı kırpılmaz.
                  Flexible(
                      child: Text(
                    '${signDisplayName(l10n, p.signIndex)} '
                    '${formatDegree(p.degreeInSign)}'
                    '${p.houseNo != null ? ' · ${p.houseNo}' : ''}'
                    '${p.retrograde ? ' · R' : ''}',
                    style: RythoText.mono(11, color: RythoColors.lilac),
                  )),
                ]),
              ),
          ],
        ]),
      ),
    ]);
  }
}
