// Sihirbazın altı adımı dar ekranda (320 dp × 1,3 yazı ölçeği) taşmamalı.
//
// `dar_ekran_ekranlar_test` yalnız ilk sayfayı ölçüyordu; D4'te beş adım
// paylaşılan bileşenlere geçti (SecimSatiri, CinsiyetSecici dört segment,
// SaatBilinmiyorKutusu, IzinKapisi) ve her biri bu sayfada ilk kez
// tam genişlikte duruyor. Ölçüt ve harness emsalle aynı (ölçüt tek yerde
// durmalı): `kDarGenislik`, `tasmaYok` oradan.
//
// ⚠️ Test yazı tipi (Ahem) her harfi punto kadar geniş çizer; ölçüm cihazdan
// ~2 kat tutucu. Burada geçen yerleşim cihazda da geçer.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rytho/core/city_directory.dart' show CityPick;
import 'package:rytho/features/onboarding/onboarding_wizard.dart';
import 'package:rytho/l10n/app_localizations.dart';
import 'package:rytho/l10n/app_localizations_tr.dart';
import 'package:rytho/main.dart' show kMaxTextScale;
import 'package:rytho/theme/rytho_theme.dart';
import 'package:rytho/widgets/atlas_widgets.dart' show GoldButton;

import 'dar_ekran_test.dart' show kDarGenislik, tasmaYok;

final _tr = AppLocalizationsTr();

/// Gerçek uzunlukta değerler: uzun şehir adı + bayrak, tam saat.
final _seciciler = SihirbazSeciciler(
  tarih: (_, _) async => DateTime(1990, 12, 27),
  saat: (_, _) async => const TimeOfDay(hour: 23, minute: 45),
  sehir: (_, _) async => const CityPick(
      name: 'Afyonkarahisar', nation: 'TR', admin1: 'Afyonkarahisar'),
);

/// Tam ekran widget için dar ekran harness'ı (emsal: dar_ekran_ekranlar_test
/// `darEkrandaEkran`). Yükseklik gerçekçi: kısa tutmak ölçmek istemediğimiz
/// dikey taşmaları uydurur.
Future<void> _darEkranda(WidgetTester tester, Widget home) async {
  tester.view.physicalSize = Size(kDarGenislik * 3, 800 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(
    child: MaterialApp(
      locale: const Locale('tr'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: buildRythoTheme(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: const TextScaler.linear(kMaxTextScale),
          // Ölçülen şey YERLEŞİM, hareket değil.
          disableAnimations: true,
        ),
        child: child!,
      ),
      home: home,
    ),
  ));
  await tester.pump();
}

Future<void> _dokun(WidgetTester tester, Finder f) async {
  await tester.tap(f);
  await tester.pump();
  await tester.pump();
}

Future<void> _devam(WidgetTester tester) => _dokun(tester, find.byType(GoldButton));

void main() {
  testWidgets('altı adımın her sayfası 320 dp × 1,3 ölçekte taşmaz',
      (tester) async {
    await _darEkranda(tester, OnboardingWizard(seciciler: _seciciler));
    tasmaYok(tester, neden: 'karşılama');
    expect(find.text(_tr.wizardWelcomeTitle), findsOneWidget);

    await _dokun(tester, find.byType(Checkbox).first);
    await _devam(tester);
    expect(find.text(_tr.wizardDateTitle), findsOneWidget);
    await _dokun(tester, find.text(_tr.birthDate));
    tasmaYok(tester, neden: 'tarih adımı (dolu değerle)');
    expect(find.text('27 Aralık 1990'), findsOneWidget);

    await _devam(tester);
    expect(find.text(_tr.wizardTimeTitle), findsOneWidget);
    await _dokun(tester, find.text(_tr.birthTime));
    tasmaYok(tester, neden: 'saat adımı (dolu değerle)');
    // Kutu işaretli hâli de ölçülür: not satırı ancak o zaman çıkar.
    await _dokun(tester, find.byType(Checkbox));
    expect(find.text(_tr.wizardTimeUnknownNote), findsOneWidget);
    tasmaYok(tester, neden: 'saat adımı ("bilmiyorum" + not)');

    await _devam(tester);
    expect(find.text(_tr.wizardPlaceTitle), findsOneWidget);
    await _dokun(tester, find.text(_tr.onboardingCity));
    tasmaYok(tester, neden: 'yer adımı (bayrak + uzun şehir)');
    expect(find.textContaining('Afyonkarahisar'), findsOneWidget);

    await _devam(tester);
    expect(find.text(_tr.wizardGenderTitle), findsOneWidget);
    tasmaYok(tester, neden: 'cinsiyet adımı (dört segment)');
    await _dokun(tester, find.text(_tr.genderUnspecified));
    tasmaYok(tester, neden: 'cinsiyet adımı (seçili)');

    await _devam(tester);
    expect(find.text(_tr.wizardNotifyTitle), findsOneWidget);
    tasmaYok(tester, neden: 'bildirim adımı');
    await _dokun(tester, find.text(_tr.wizardNotifyNotNow));
    tasmaYok(tester, neden: 'bildirim adımı (seçili, "Haritamı çiz")');
    expect(find.text(_tr.wizardFinish), findsOneWidget);
  });
}
