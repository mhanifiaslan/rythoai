// Giriş yöntemleri ekranı bekçileri (D4).
//
// Ölçülen kusur (HEAD sign_in_methods_screen.dart:116-118, 245): tek `_hata`
// değişkeni şifre alanının `errorText`ine basılıyordu — Google bağlanamayınca
// kullanıcı ŞİFRE alanının kırmızı yandığını görüyordu. İkinci kusur:
// şifre değiştirme tek alan, kuralsız ve tekrarsızdı; yanlış yazılan yeni
// şifre hesabı düşürüyordu.
//
// ⚠️ Metin `controller.text` ile yazılır (sifre_alanlari_test notu);
// alanlara `EditableText.controller` üzerinden ulaşılır, sıra ağaç sırası.
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:rytho/features/profile/sign_in_methods_screen.dart';
import 'package:rytho/l10n/app_localizations.dart';
import 'package:rytho/l10n/app_localizations_tr.dart';
import 'package:rytho/theme/rytho_theme.dart';
import 'package:rytho/widgets/atlas_widgets.dart' show GoldButton;

final _tr = AppLocalizationsTr();

Future<void> _ekran(WidgetTester tester, Widget home) async {
  tester.view.physicalSize = const Size(390 * 3, 1600 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    locale: const Locale('tr'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    theme: buildRythoTheme(),
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(disableAnimations: true),
      child: child!,
    ),
    home: home,
  ));
}

void _yaz(WidgetTester tester, int sira, String deger) {
  tester
      .widget<EditableText>(find.byType(EditableText).at(sira))
      .controller
      .text = deger;
}

Future<void> _bekle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

/// Google satırındaki "Bağla" — ağaçta telefon satırınınkinden önce gelir.
Finder get _googleBagla => find.widgetWithText(TextButton, _tr.linkAction).first;

void main() {
  testWidgets('Google bağlama hatası Google satırının altında — ŞİFRE '
      'bölümünde DEĞİL', (tester) async {
    await _ekran(
        tester,
        SignInMethodsScreen(
          baglilar: () => {'password'},
          ilkEposta: 'a@b.co',
          googleBagla: () async =>
              throw FirebaseAuthException(code: 'credential-already-in-use'),
        ));
    await tester.tap(_googleBagla);
    await _bekle(tester);

    final hata = find.text(_tr.linkCredentialInUse);
    expect(hata, findsOneWidget);
    expect(find.ancestor(of: hata, matching: find.byType(Form)), findsNothing,
        reason: 'Google hatası şifre bölümünde yanıyordu');
    expect(find.ancestor(of: hata, matching: find.byType(TextField)),
        findsNothing);
    for (final tf in tester.widgetList<TextField>(find.byType(TextField))) {
      expect(tf.decoration?.errorText, isNull,
          reason: 'hiçbir metin alanı Google hatasını taşımamalı');
    }
  });

  testWidgets('Google iptali hata değil: hiçbir yuvaya yazılmaz',
      (tester) async {
    await _ekran(
        tester,
        SignInMethodsScreen(
          baglilar: () => {'password'},
          ilkEposta: 'a@b.co',
          googleBagla: () async => throw const GoogleSignInException(
              code: GoogleSignInExceptionCode.canceled),
        ));
    await tester.tap(_googleBagla);
    await _bekle(tester);

    expect(find.text(_tr.authFailed), findsNothing);
    expect(find.byType(SnackBar), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('şifre belirleme KAYIT gibi: tekrar eşleşmesi + kural, '
      'ancak geçerliyse bağlanır', (tester) async {
    (String, String)? gonderilen;
    await _ekran(
        tester,
        SignInMethodsScreen(
          baglilar: () => {'google.com'},
          ilkEposta: '',
          sifreBagla: (e, s) async => gonderilen = (e, s),
        ));
    expect(find.text(_tr.passwordRepeat), findsOneWidget,
        reason: 'tekrar alanı yok: yanlış yazılan şifre hesabı düşürür');
    expect(find.text(_tr.passwordRuleHint), findsOneWidget);

    final dugme = find.widgetWithText(GoldButton, _tr.setPasswordAction);
    // e-posta(0), şifre(1), tekrar(2)
    _yaz(tester, 0, 'a@b.co');
    _yaz(tester, 1, 'Abcdef12');
    _yaz(tester, 2, 'Abcdef13');
    await tester.pump();
    await tester.tap(dugme);
    await _bekle(tester);
    expect(find.text(_tr.passwordsDoNotMatch), findsOneWidget);
    expect(gonderilen, isNull, reason: 'uyuşmayan şifre sunucuya gitmez');

    _yaz(tester, 1, '12345678');
    _yaz(tester, 2, '12345678');
    await tester.pump();
    await tester.tap(dugme);
    await _bekle(tester);
    expect(find.text(_tr.passwordTooSimple), findsOneWidget,
        reason: 'yeni şifre kayıt kuralına tabi');
    expect(gonderilen, isNull);

    _yaz(tester, 1, 'Abcdef12');
    _yaz(tester, 2, 'Abcdef12');
    await tester.pump();
    await tester.tap(dugme);
    await _bekle(tester);
    expect(gonderilen, ('a@b.co', 'Abcdef12'));
    expect(find.text(_tr.linkPasswordDone), findsOneWidget);
  });

  testWidgets('şifre bağlama hatası ŞİFRE bölümünde (Form içinde)',
      (tester) async {
    await _ekran(
        tester,
        SignInMethodsScreen(
          baglilar: () => {'password'},
          ilkEposta: 'a@b.co',
          sifreBagla: (_, _) async =>
              throw FirebaseAuthException(code: 'requires-recent-login'),
        ));
    // Şifre zaten bağlı: e-posta alanı yok; şifre(0), tekrar(1).
    _yaz(tester, 0, 'Abcdef12');
    _yaz(tester, 1, 'Abcdef12');
    await tester.pump();
    await tester.tap(find.widgetWithText(GoldButton, _tr.changePasswordAction));
    await _bekle(tester);

    final hata = find.text(_tr.linkRequiresRecentLogin);
    expect(hata, findsOneWidget);
    expect(find.ancestor(of: hata, matching: find.byType(Form)),
        findsOneWidget, reason: 'şifre hatası şifre bölümünün altında');
  });
}
