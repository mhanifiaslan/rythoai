// `ChartWheel.onTap` sözleşmesi (D6, salt önizleme) — yalnız çark grafiği.
//
// Bu dosya BİLEREK hiçbir ekranı içe almıyor: sözleşme çarkın kendisine
// ait ve ekranlar (chat, atlas) derlenemezken bile ölçülebilmeli. Ekran
// tüketicisi ("Şu an gökyüzünde") ayrı dosyada: cark_salt_onizleme_test.
//
// Sözleşme: `onTap` verilince çarkın neresine dokunulursa dokunulsun
// gezegen/açı çözümlemesi YAPILMAZ, yalnız `onTap` çağrılır ve çark
// ekran okuyucuya DÜĞME olur. `onTap` yokken eski davranış korunur —
// Atlas ve kişi detayı kendi turunda göçer.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:rytho/l10n/app_localizations.dart';
import 'package:rytho/widgets/chart/chart_data.dart';
import 'package:rytho/widgets/chart/chart_wheel.dart';
import 'package:rytho/widgets/chart/wheel_layout.dart';

ChartPoint _p(String name, double lon) => ChartPoint(
      name: name,
      localName: name,
      absPosition: lon,
      signIndex: signIndexFromAny(null, lon),
      degreeInSign: lon % 30,
    );

ChartData _natal() => ChartData(
      rings: [
        ChartRing(kind: ChartRingKind.natal, points: [
          _p('Sun', 10), _p('Moon', 95), _p('Saturn', 190),
        ]),
      ],
      houses: [
        for (var i = 0; i < 12; i++)
          ChartHouse(house: i + 1, absPosition: (i * 30) % 360.0),
      ],
      aspects: const [
        ChartAspect(p1: 'Sun', p2: 'Saturn', kind: 'opposition', orb: 0.5),
      ],
    );

Widget _sar(Widget child) => MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('tr'),
      home: Scaffold(body: Align(alignment: Alignment.topLeft, child: child)),
    );

/// Ay'ın GERÇEK yerleşimine dokunur (isabet == çizim, tek kaynak).
Future<void> _ayaDokun(WidgetTester tester, ChartData data) async {
  final layout = WheelLayout.compute(const Size(360, 360), data);
  final ay = layout.placements.first.firstWhere((g) => g.point.name == 'Moon');
  await tester.tapAt(tester.getTopLeft(find.byType(ChartWheel)) + ay.center);
  // onDoubleTap kayıtlı: tekli dokunuş çift-dokunuş zaman aşımından sonra.
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  GoogleFonts.config.allowRuntimeFetching = false;

  testWidgets('onTap varken gezegene dokunmak onPlanetTap\'i ÇAĞIRMAZ',
      (tester) async {
    final data = _natal();
    var dokunus = 0;
    String? gezegen;
    await tester.pumpWidget(_sar(ChartWheel(
      data: data,
      size: 360,
      animate: false,
      interactive: false,
      onTap: () => dokunus++,
      onPlanetTap: (g) => gezegen = g.point.name,
    )));
    await tester.pump();
    await _ayaDokun(tester, data);
    expect(dokunus, 1);
    expect(gezegen, isNull,
        reason: 'salt önizlemede gezegen çözümlemesi yapılmamalı');
  });

  testWidgets('onTap YOKKEN eski davranış: gezegen çözülür', (tester) async {
    final data = _natal();
    String? gezegen;
    await tester.pumpWidget(_sar(ChartWheel(
      data: data,
      size: 360,
      animate: false,
      interactive: false,
      onPlanetTap: (g) => gezegen = g.point.name,
    )));
    await tester.pump();
    await _ayaDokun(tester, data);
    expect(gezegen, 'Moon');
  });

  testWidgets('onTap varken çark ekran okuyucuya DÜĞME', (tester) async {
    final semantik = tester.ensureSemantics();
    await tester.pumpWidget(_sar(
        ChartWheel(data: _natal(), size: 300, animate: false, onTap: () {})));
    await tester.pump();
    expect(tester.getSemantics(find.byType(ChartWheel)),
        isSemantics(isButton: true, hasTapAction: true));
    semantik.dispose();
  });

  testWidgets('onTap yokken çark düğme DEĞİL (dokunulamayan şey duyurulmaz)',
      (tester) async {
    final semantik = tester.ensureSemantics();
    await tester.pumpWidget(
        _sar(ChartWheel(data: _natal(), size: 300, animate: false)));
    await tester.pump();
    expect(tester.getSemantics(find.byType(ChartWheel)),
        isSemantics(isButton: false));
    semantik.dispose();
  });
}
