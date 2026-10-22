// iOS sayı tuş takımı kapatma bekçileri (U48).
//
// iPhone'un sayı ve telefon tuş takımında "Bitti"/Return tuşu da sistem
// geri tuşu da yok; klavye açık kalıp telefon doğrulama ekranındaki "Kod
// gönder"/"Doğrula" düğmelerini örtüyordu. iOS'ta alan dışına dokunmak ve
// sayfayı sürüklemek klavyeyi kapatır. Android'de Flutter'ın varsayılanı
// (dokunmayla odak bırakılmaz, kaydırma klavyeye dokunmaz) BAYT BAYT kalır.
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rytho/features/profile/phone_verify_screen.dart';
import 'package:rytho/l10n/app_localizations.dart';
import 'package:rytho/widgets/phone_number_field.dart';

Widget _sar(Widget child) => ProviderScope(
      child: MaterialApp(
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('tr'),
        builder: (context, c) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: true),
          child: c!,
        ),
        home: child,
      ),
    );

/// Telefon alanı + altında boş bir dokunma bölgesi.
Widget _alanVeBosluk() => _sar(Scaffold(
      body: Column(children: [
        PhoneNumberField(onChanged: (_) {}),
        const Expanded(
            child: SizedBox.expand(key: ValueKey('bosluk'))),
      ]),
    ));

bool _alanOdakta(WidgetTester tester) => tester
    .widget<EditableText>(find.byType(EditableText))
    .focusNode
    .hasFocus;

void main() {
  group('yardımcılar', () {
    tearDown(() => debugDefaultTargetPlatformOverride = null);

    test('iOS: dış dokunuş ve sürükleme klavyeyi kapatır', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      expect(sayiKlavyesiDisDokunus, isNotNull);
      expect(sayiKlavyesiKaydirmaDavranisi,
          ScrollViewKeyboardDismissBehavior.onDrag);
    });

    test('Android: ikisi de null — Flutter varsayılanı kalır', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      expect(sayiKlavyesiDisDokunus, isNull);
      expect(sayiKlavyesiKaydirmaDavranisi, isNull);
    });
  });

  group('telefon alanı', () {
    testWidgets('iOS: alan dışına dokunmak klavyeyi kapatır',
        (tester) async {
      await tester.pumpWidget(_alanVeBosluk());
      await tester.pump();
      await tester.tap(find.byType(TextField));
      await tester.pump();
      expect(_alanOdakta(tester), isTrue);

      await tester.tap(find.byKey(const ValueKey('bosluk')));
      await tester.pump();
      expect(_alanOdakta(tester), isFalse,
          reason: 'iOS sayı tuş takımı kapatılamıyor');
    }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

    testWidgets('Android: alan dışına dokunmak odağı DEĞİŞTİRMEZ',
        (tester) async {
      await tester.pumpWidget(_alanVeBosluk());
      await tester.pump();
      await tester.tap(find.byType(TextField));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('bosluk')));
      await tester.pump();
      expect(_alanOdakta(tester), isTrue,
          reason: 'Android davranışı değişti');
    }, variant: TargetPlatformVariant.only(TargetPlatform.android));
  });

  group('telefon doğrulama ekranı', () {
    testWidgets('iOS: sürüklemek klavyeyi kapatır', (tester) async {
      await tester.pumpWidget(_sar(const PhoneVerifyScreen()));
      await tester.pump();
      final liste = tester.widget<ListView>(find.byType(ListView));
      expect(liste.keyboardDismissBehavior,
          ScrollViewKeyboardDismissBehavior.onDrag);
    }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

    testWidgets('Android: ListView varsayılanında', (tester) async {
      await tester.pumpWidget(_sar(const PhoneVerifyScreen()));
      await tester.pump();
      final liste = tester.widget<ListView>(find.byType(ListView));
      expect(liste.keyboardDismissBehavior, isNull);
    }, variant: TargetPlatformVariant.only(TargetPlatform.android));
  });
}
