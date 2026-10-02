// GECICI OLCUM — raporlanmadan once silinir.
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rytho/features/atlas/atlas_detail_screens.dart';
import 'package:rytho/l10n/app_localizations.dart';

final _tr = lookupAppLocalizations(const Locale('tr'));

Widget _sar(Widget child) => MaterialApp(
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('tr'),
      home: child,
    );

void main() {
  testWidgets('olcum', (tester) async {
    tester.view.physicalSize = const Size(320, 480);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_sar(Scaffold(
      body: Builder(
        builder: (context) => TextButton(
            onPressed: () => showAspectSheet(context, {
                  'p1': 'Sun', 'p1_tr': 'Güneş', 'p2': 'Mars',
                  'p2_tr': 'Mars', 'aspect': 'square', 'aspect_tr': 'Kare',
                  'orbit': 1.5, 'movement': 'applying',
                  'movement_local': 'Yaklaşıyor',
                }),
            child: const Text('ac')),
      ),
    )));
    await tester.tap(find.text('ac'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    final sv = find.byType(SingleChildScrollView);
    // ignore: avoid_print
    print('EKRAN=${tester.view.physicalSize} '
        'SV=${sv.evaluate().isEmpty ? "YOK" : tester.getSize(sv)} '
        'SAFEAREA=${tester.getSize(find.descendant(of: sv, matching: find.byType(SafeArea)).first)} '
        'DIPNOT=${tester.getRect(find.text(_tr.aspectSheetFootnote))}');
  });
}
