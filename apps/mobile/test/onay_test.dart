// Onay diyaloğu ve onaylı çıkış bekçileri.
//
// Ölçülen kusur: profildeki "Oturumu kapat" onaysızdı ve dock'un hemen
// üstündeydi; arkadaş çıkarma/engelleme de onaysızdı. `onayla` yalnız onay
// düğmesinde true döner — dışarı dokunma, geri ve "Vazgeç" hepsi false.
// `onayliCikis` çıkışı ANCAK onaydan sonra çağırır.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rytho/l10n/app_localizations.dart';
import 'package:rytho/l10n/app_localizations_tr.dart';
import 'package:rytho/theme/rytho_theme.dart';
import 'package:rytho/theme/rytho_tokens.dart';
import 'package:rytho/widgets/atlas_widgets.dart' show GoldButton;
import 'package:rytho/widgets/onay.dart';

final _tr = AppLocalizationsTr();

Widget _sar(Widget child) => MaterialApp(
      locale: const Locale('tr'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: buildRythoTheme(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: true),
        child: child!,
      ),
      home: Scaffold(body: child),
    );

/// Diyaloğu açan düğme; sonuç dışarıya yazılır.
Widget _acici(void Function(BuildContext) ac) => Builder(
      builder: (context) => TextButton(
          onPressed: () => ac(context), child: const Text('AÇ')),
    );

Future<void> _ac(WidgetTester tester) async {
  await tester.tap(find.text('AÇ'));
  await tester.pump();
  await tester.pump(RythoMotion.base);
}

void main() {
  testWidgets('vazgeç → false; onay → true; dışarı dokunma → false',
      (tester) async {
    bool? sonuc;
    await tester.pumpWidget(_sar(_acici((c) async {
      sonuc = await onayla(c,
          title: 'Arkadaşlıktan çıkar?',
          body: 'Bu kişi listenden silinecek.',
          confirmLabel: 'Çıkar');
    })));

    await _ac(tester);
    expect(find.text('Arkadaşlıktan çıkar?'), findsOneWidget);
    expect(find.text('Bu kişi listenden silinecek.'), findsOneWidget);
    await tester.tap(find.text(_tr.cancel));
    await tester.pump(RythoMotion.base);
    expect(sonuc, isFalse);

    sonuc = null;
    await _ac(tester);
    await tester.tap(find.text('Çıkar'));
    await tester.pump(RythoMotion.base);
    expect(sonuc, isTrue);

    sonuc = null;
    await _ac(tester);
    // Perde: belirsiz kapanış asla onay değildir.
    await tester.tapAt(const Offset(4, 4));
    await tester.pump(RythoMotion.base);
    expect(sonuc, isFalse);
  });

  testWidgets('yıkıcı onay: GoldButton(destructive), vazgeç metin düğmesi',
      (tester) async {
    bool? sonuc;
    await tester.pumpWidget(_sar(_acici((c) async {
      sonuc = await onayla(c,
          title: 'Hesabını sil', confirmLabel: 'Sil', destructive: true);
    })));

    await _ac(tester);
    final dugme = tester.widget<GoldButton>(find.byType(GoldButton));
    expect(dugme.destructive, isTrue);
    expect(dugme.text, 'Sil');
    expect(find.widgetWithText(TextButton, _tr.cancel), findsOneWidget);
    expect(tester.takeException(), isNull, reason: 'diyalog taşmamalı');

    await tester.tap(find.byType(GoldButton));
    await tester.pump(RythoMotion.base);
    expect(sonuc, isTrue);
  });

  testWidgets('onayliCikis: çıkış YALNIZ onaydan sonra', (tester) async {
    var cikis = 0;
    await tester.pumpWidget(_sar(_acici((c) =>
        onayliCikis(c, cikis: () async => cikis++))));

    await _ac(tester);
    expect(find.text(_tr.signOut), findsOneWidget);
    await tester.tap(find.text(_tr.cancel));
    await tester.pump(RythoMotion.base);
    expect(cikis, 0, reason: 'vazgeçildi, çıkış çağrılmamalı');

    await _ac(tester);
    await tester.tap(find.text(_tr.deviceConflictSignOut));
    await tester.pump(RythoMotion.base);
    expect(cikis, 1);
  });

  testWidgets('onayliCikis(onay: false): sormadan çıkar', (tester) async {
    var cikis = 0;
    await tester.pumpWidget(_sar(_acici((c) =>
        onayliCikis(c, onay: false, cikis: () async => cikis++))));

    await _ac(tester);
    expect(find.byType(AlertDialog), findsNothing);
    expect(cikis, 1);
  });
}
