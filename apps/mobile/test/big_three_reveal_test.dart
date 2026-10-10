import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rytho/l10n/app_localizations.dart';
import 'package:rytho/main.dart' show kMaxTextScale;
import 'package:rytho/theme/rytho_theme.dart';
import 'package:rytho/widgets/big_three_reveal.dart';

/// R12-B1: Büyük Üçlü perdesi — onboarding'in kayıp finali.
///
/// pumpAndSettle YOK (perde altında sonsuz animatör yok ama kural geneldir);
/// süreli pump adımlarıyla mühürlerin ve butonun gelişi beklenir.
void main() {
  testWidgets('perde üç mührü açar, buton kapatır', (tester) async {
    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: const [Locale('tr')],
      locale: const Locale('tr'),
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => showBigThreeReveal(context,
                sun: 'Kova ♒', moon: 'Balık ♓', ascendant: 'Koç ♈'),
            child: const Text('ac'),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('ac'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 3));

    // Profildeki "Kova ♒" biçimi ayrıştırılıp yerel ada çevrilmeli.
    expect(find.text('GÜNEŞ'), findsOneWidget);
    expect(find.text('Kova'), findsOneWidget);
    expect(find.text('Balık'), findsOneWidget);
    expect(find.text('Koç'), findsOneWidget);
    expect(find.text('Yolculuğa başla'), findsOneWidget);

    await tester.tap(find.text('Yolculuğa başla'));
    // Kapanış: bir kare pop'u başlatır, sonraki kareler ters geçişi bitirir.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('GÜNEŞ'), findsNothing);
  });

  testWidgets('320 dp × 1,3 yazı ölçeğinde üç mühür TAŞMAZ ve EZİLMEZ',
      (tester) async {
    // Eski satır 92+20+92+20+92 = 316 px sabitti; 28 px kenar dolgusuyla
    // 320 dp'de 52 px taşıyordu (plan §4 ölçümü). Şimdi her mühür üçte bir
    // pay alır. İki iddia birden: Flutter taşmayı çizimde fırlatır (taşma
    // yok) VE 64 px daire 64 px kalır (pay daraltılmış değil) — ikincisi
    // olmasa "aralığı büyüt, mühürleri ez" türü bir gerileme de yeşil
    // kalırdı, çünkü `Expanded` payı küçülünce Flex fırlatmaz, kırpar.
    tester.view.physicalSize = const Size(320 * 3, 800 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: const [Locale('tr')],
      locale: const Locale('tr'),
      theme: buildRythoTheme(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: const TextScaler.linear(kMaxTextScale),
          disableAnimations: true,
        ),
        child: child!,
      ),
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            // Yükselen bilinmiyor: en uzun etiket ("Yükselen bilinmiyor")
            // da sığmalı — saatsiz doğumun gerçek hâli.
            onPressed: () => showBigThreeReveal(context,
                sun: 'Kova ♒', moon: 'Balık ♓', ascendant: null),
            child: const Text('ac'),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('ac'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(tester.takeException(), isNull, reason: 'mühür satırı taşıyor');
    final daireler = find.byWidgetPredicate((w) =>
        w is Container &&
        w.decoration is BoxDecoration &&
        (w.decoration! as BoxDecoration).shape == BoxShape.circle);
    expect(daireler, findsNWidgets(3));
    for (var i = 0; i < 3; i++) {
      final r = tester.getRect(daireler.at(i));
      // Kayan nokta: 63.999… de 64'tür; ezilme tam sayılık fark değil.
      expect(r.width, closeTo(64, 0.01), reason: 'mühür $i ezildi: ${r.width}');
      expect(r.left, greaterThanOrEqualTo(0), reason: 'mühür $i soldan taştı');
      expect(r.right, lessThanOrEqualTo(320), reason: 'mühür $i sağdan taştı');
    }
    expect(
        find.text(lookupAppLocalizations(const Locale('tr'))
            .bigThreeAscendantUnknown),
        findsOneWidget);
  });
}
