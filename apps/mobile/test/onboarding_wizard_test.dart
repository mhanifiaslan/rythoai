import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rytho/features/onboarding/onboarding_wizard.dart';
import 'package:rytho/l10n/app_localizations.dart';

/// Yıldız Yolu sihirbazının değişmezleri (O3).
///
/// * İki rıza kutusu da (şartlar + yapay zeka onayı) işaretlenmeden
///   İLERLENEMEZ — Google/Apple girişindeki onay boşluğunu kapatan adım
///   atlanabilir olsaydı boşluk geri gelirdi; yapay zeka onayının sorulduğu
///   tek yer de burası.
/// * Adımlar kaydırmayla atlanamaz (NeverScrollableScrollPhysics) —
///   zorunlu alanların kapısı düğme.
/// * Tarih seçilmeden tarih adımından çıkılamaz.
Widget _sar() => const ProviderScope(
      child: MaterialApp(
        localizationsDelegates: [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: [Locale('tr'), Locale('en')],
        locale: Locale('tr'),
        home: OnboardingWizard(),
      ),
    );

Future<void> _pompala(WidgetTester tester) async {
  await tester.pumpWidget(_sar());
  await _bekle(tester);
}

/// Takımyıldız nabzı sonsuz animasyon: pumpAndSettle YASAK (R12 kuralı);
/// sayfa geçişi + RythoReveal girişleri zamanlı karelerle ilerletilir.
Future<void> _bekle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 300));
  }
}

void main() {
  testWidgets('riza isaretlenmeden ilerlenemez', (tester) async {
    await _pompala(tester);

    expect(find.text('Yolculuk başlıyor'), findsOneWidget);
    await tester.tap(find.text('Devam ✦'));
    await _bekle(tester);
    // Hâlâ karşılamadayız — kutu işaretlenmedi.
    expect(find.text('Yolculuk başlıyor'), findsOneWidget);

    // Yalnız şartlar kutusu YETMEZ.
    await tester.tap(find.byType(Checkbox).at(0));
    await _bekle(tester);
    await tester.tap(find.text('Devam ✦'));
    await _bekle(tester);
    expect(find.text('Yolculuk başlıyor'), findsOneWidget);

    await tester.tap(find.byType(Checkbox).at(1));
    await _bekle(tester);
    await tester.tap(find.text('Devam ✦'));
    await _bekle(tester);
    expect(find.text('Hangi gün doğdun?'), findsOneWidget);
  });

  testWidgets('tarih secilmeden tarih adimindan cikilamaz',
      (tester) async {
    await _pompala(tester);
    await tester.tap(find.byType(Checkbox).at(0));
    await tester.tap(find.byType(Checkbox).at(1));
    await _bekle(tester);
    await tester.tap(find.text('Devam ✦'));
    await _bekle(tester);

    await tester.tap(find.text('Devam ✦'));
    await _bekle(tester);
    // Tarih boş — adım değişmedi.
    expect(find.text('Hangi gün doğdun?'), findsOneWidget);
  });

  testWidgets('kaydirma ile adim atlanamaz', (tester) async {
    await _pompala(tester);
    await tester.drag(find.byType(PageView), const Offset(-400, 0));
    await _bekle(tester);
    expect(find.text('Yolculuk başlıyor'), findsOneWidget);
  });
}
