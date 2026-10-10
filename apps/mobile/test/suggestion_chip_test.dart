// `SuggestionChip.selected` bekçileri (D3).
//
// Geri bildirimin `_EkranCipi`si ve günlüğün emoji çipleri "seçili çip"
// görünümünü ayrı ayrı elle yazıyordu; göç sonrası tek tanım burada.
// Seçili hâl DEGRADE DEĞİL: degrade ve glow eyleme ait
// (`login_hierarchy_test` "segment buton gibi görünmez"); çip bir durum
// gösterir — ince lila kontur + %18 dolgu.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rytho/theme/rytho_theme.dart';
import 'package:rytho/theme/rytho_tokens.dart';
import 'package:rytho/widgets/nebula_widgets.dart';

Widget _sar(Widget child) => MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: true),
        child: child!,
      ),
      home: Scaffold(body: Center(child: child)),
    );

BoxDecoration _dekor(WidgetTester tester) => tester
    .widget<Container>(find.descendant(
        of: find.byType(SuggestionChip), matching: find.byType(Container)))
    .decoration! as BoxDecoration;

void main() {
  testWidgets('seçili: %18 lila dolgu, lila kontur, degrade YOK',
      (tester) async {
    await tester.pumpWidget(
        _sar(SuggestionChip(text: 'Bugün', selected: true, onTap: () {})));

    final d = _dekor(tester);
    expect(d.color, RythoColors.lilac.withValues(alpha: 0.18));
    expect(d.gradient, isNull, reason: 'çip durum gösterir, eylem değil');
    final kontur = (d.border! as Border).top.color;
    expect(kontur.withValues(alpha: 1), RythoColors.lilac);
    expect(kontur.a, greaterThan(0.5), reason: 'seçili kontur belirgin olmalı');
  });

  testWidgets('seçili değil: nötr dolgu, soluk kontur', (tester) async {
    await tester.pumpWidget(_sar(SuggestionChip(text: 'Bugün', onTap: () {})));

    final d = _dekor(tester);
    expect(d.color, RythoColors.inkLight);
    expect(d.gradient, isNull);
    expect((d.border! as Border).top.color.a, lessThan(0.5));
  });

  testWidgets('dokunuş onTap tetikler', (tester) async {
    var sayac = 0;
    await tester.pumpWidget(
        _sar(SuggestionChip(text: 'Bugün', onTap: () => sayac++)));
    await tester.tap(find.text('Bugün'));
    await tester.pump(RythoMotion.press);
    expect(sayac, 1);
  });

  testWidgets('ekran okuyucu düğme duyar, etiket çipin metni', (tester) async {
    // Rol `Pressable`dan miras; çip ayrıca etiket vermez, metni birleşir.
    final semantik = tester.ensureSemantics();
    await tester.pumpWidget(_sar(SuggestionChip(text: 'Bugün', onTap: () {})));

    expect(tester.getSemantics(find.byType(SuggestionChip)),
        isSemantics(isButton: true, isEnabled: true, label: 'Bugün'));
    semantik.dispose();
  });
}
