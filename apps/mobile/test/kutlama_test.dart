// `Kutlama` bekçileri (D3).
//
// `sky_screen`de seri rozeti ve keşif halkası aynı kutlama sahnesini
// (StarBurst arkada + iki fazlı ölçek vuruşu) birebir kopya taşıyordu.
// Tek tanım artık `star_burst.dart`'ta; burası üç hâlini çiviler:
// kutlama yok → çocuk çıplak; kutlama var → patlama + Animate; hareket
// azaltma → yine çıplak (patlama da, Animate de yok).
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rytho/theme/rytho_tokens.dart';
import 'package:rytho/widgets/star_burst.dart';

/// `StarBurst` tek atışlık ama 1,1 sn sürer; `pumpAndSettle` yerine
/// token sürelerle adım atılır.
Widget _sar(Widget child, {bool hareketAzalt = false}) => MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(disableAnimations: hareketAzalt),
        child: child!,
      ),
      home: Scaffold(body: Center(child: child)),
    );

const _rozet = Text('🔥 3');

void main() {
  testWidgets('celebrate=false → çocuk çıplak: patlama yok, Animate yok',
      (tester) async {
    await tester.pumpWidget(
        _sar(const Kutlama(celebrate: false, child: _rozet)));

    expect(find.text('🔥 3'), findsOneWidget);
    expect(find.byType(StarBurst), findsNothing);
    expect(find.byType(Animate), findsNothing);
  });

  testWidgets('celebrate=true → patlama arkada + ölçek zinciri önde',
      (tester) async {
    await tester.pumpWidget(
        _sar(const Kutlama(celebrate: true, child: _rozet)));

    expect(find.byType(StarBurst), findsOneWidget);
    expect(find.byType(Animate), findsOneWidget);
    expect(find.text('🔥 3'), findsOneWidget);

    // İki faz da token süresinde; zincir bitince çocuk hâlâ ekranda.
    await tester.pump(RythoMotion.celebrate);
    await tester.pump(RythoMotion.celebrate);
    expect(find.text('🔥 3'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('hareket azaltmada Animate YOK, patlama YOK', (tester) async {
    // Kutlamanın bilgisini rozetin kendisi taşır; vestibüler rahatsızlığı
    // olan kullanıcı için patlama süs değil, engel.
    await tester.pumpWidget(_sar(
        const Kutlama(celebrate: true, child: _rozet),
        hareketAzalt: true));

    expect(find.text('🔥 3'), findsOneWidget);
    expect(find.byType(Animate), findsNothing);
    expect(find.byType(StarBurst), findsNothing);
  });
}
