// Şehir arama ekranı: dizin yüklemesi düşerse sonsuz spinner değil hata
// kartı (D4).
//
// Ölçülen kusur (city_search_field.dart:104, 2026-10-10): `_dizin == null`
// → spinner; yükleme düşünce `_dizin` sonsuza dek null kalıyor, kullanıcı
// ne sebebi görüyor ne yeniden deneyebiliyordu. Sihirbazın yer adımı bu
// ekrana kilitli — spinner "takıldı" demek, kurulum yarım demek.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rytho/core/city_directory.dart';
import 'package:rytho/l10n/app_localizations.dart';
import 'package:rytho/l10n/app_localizations_tr.dart';
import 'package:rytho/theme/rytho_theme.dart';
import 'package:rytho/theme/rytho_tokens.dart';
import 'package:rytho/widgets/city_search_field.dart';
import 'package:rytho/widgets/common.dart' show ErrorCard;

final _tr = AppLocalizationsTr();

Widget _sar(Future<CityDirectory> Function() yukle) => MaterialApp(
      locale: const Locale('tr'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: buildRythoTheme(),
      // Geçiş rotası animasyonlu; ölçülen şey ekranın hâli.
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: true),
        child: child!,
      ),
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
              onPressed: () => showCitySearch(context, yukle: yukle),
              child: const Text('AÇ')),
        ),
      ),
    );

Future<void> _ac(WidgetTester tester) async {
  await tester.tap(find.text('AÇ'));
  await tester.pump();
  await tester.pump(RythoMotion.route);
}

void main() {
  testWidgets('dizin düşerse spinner değil hata kartı; "Tekrar dene" '
      'yükleyiciyi yeniden çağırır', (tester) async {
    var cagri = 0;
    await tester.pumpWidget(_sar(() {
      cagri++;
      return Future.error(StateError('dizin okunamadı'));
    }));
    await _ac(tester);
    await tester.pump();

    expect(cagri, 1);
    expect(find.byType(CircularProgressIndicator), findsNothing,
        reason: 'hata hâlinde dönmeye devam eden spinner "bekle" der');
    expect(find.byType(ErrorCard), findsOneWidget);
    expect(find.text(_tr.errorGeneric), findsOneWidget);

    await tester.tap(find.text(_tr.retry));
    await tester.pump();
    await tester.pump();
    expect(cagri, 2, reason: 'Tekrar dene yükleyiciyi yeniden çağırmalı');
    expect(find.byType(ErrorCard), findsOneWidget,
        reason: 'ikinci deneme de düştü: kart kalır');
  });

  testWidgets('spinner YALNIZ yüklenirken; hata gelince gider',
      (tester) async {
    final bekleyen = Completer<CityDirectory>();
    await tester.pumpWidget(_sar(() => bekleyen.future));
    await _ac(tester);

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.byType(ErrorCard), findsNothing);

    bekleyen.completeError(StateError('dizin okunamadı'));
    await tester.pump();
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.byType(ErrorCard), findsOneWidget);
  });
}
