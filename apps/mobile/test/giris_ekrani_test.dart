// Giriş ekranı şifre alanları (D4): KAYIT modunda `SifreAlanlari` tekrar +
// kuralla, GİRİŞ modunda tek alan ve kural YOK.
//
// Sahip uyarısı: eski hesapların şifresi bugünkü kurala uymayabilir; girişte
// `validatePassword` çağrılsa kullanıcı kendi hesabından dışarıda kalır.
// Kayıt `validatePassword`u kullanmaya devam eder — zayıf şifreyle hesap
// açılmaz.
//
// ⚠️ Metin `controller.text` ile yazılır, `tester.enterText` ile DEĞİL
// (sifre_alanlari_test notu: odaklı TextField bu makinede çizimde
// fırlatıyor). Denetleyiciler ekranın içinde; `EditableText.controller`
// üzerinden ulaşılır — alan sırası ağaç sırasıdır.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rytho/features/auth/login_screen.dart';
import 'package:rytho/l10n/app_localizations.dart';
import 'package:rytho/l10n/app_localizations_tr.dart';
import 'package:rytho/theme/rytho_theme.dart';
import 'package:rytho/widgets/atlas_widgets.dart' show GoldButton;
import 'package:rytho/widgets/sifre_alanlari.dart';

final _tr = AppLocalizationsTr();

Future<void> _ekran(WidgetTester tester) async {
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
    home: const LoginScreen(),
  ));
}

void _yaz(WidgetTester tester, int sira, String deger) {
  tester
      .widget<EditableText>(find.byType(EditableText).at(sira))
      .controller
      .text = deger;
}

void main() {
  testWidgets('GİRİŞ modu: tek şifre alanı, kural metni YOK, mevcut-şifre '
      'ipucu', (tester) async {
    await _ekran(tester);

    final alan = tester.widget<SifreAlanlari>(find.byType(SifreAlanlari));
    expect(alan.kuralDayat, isFalse, reason: 'girişte kural dayatılmaz');
    expect(alan.tekrarIste, isFalse);
    expect(find.text(_tr.passwordRuleHint), findsNothing);
    expect(find.text(_tr.passwordRepeat), findsNothing);
    // e-posta + şifre = 2 alan
    expect(find.byType(EditableText), findsNWidgets(2));
  });

  testWidgets('KAYIT modu: SifreAlanlari tekrar + kural ipucu ile',
      (tester) async {
    await _ekran(tester);
    await tester.tap(find.text(_tr.signUp));
    await tester.pump();

    final alan = tester.widget<SifreAlanlari>(find.byType(SifreAlanlari));
    expect(alan.kuralDayat, isTrue, reason: 'yeni şifre kurala tabi');
    expect(alan.tekrarIste, isTrue);
    expect(find.text(_tr.passwordRuleHint), findsOneWidget);
    expect(find.text(_tr.passwordRepeat), findsOneWidget);
  });

  testWidgets('girişte zayıf şifre form kapısını GEÇER — validatePassword '
      'çağrılmaz', (tester) async {
    await _ekran(tester);
    _yaz(tester, 0, 'eski@hesap.com');
    _yaz(tester, 1, '1234'); // bugünkü kurala göre "çok kısa"
    await tester.pump();

    await tester.tap(find.widgetWithText(GoldButton, _tr.signIn));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // Form geçti ve giriş DENENDİ: Firebase ayakta olmadığı için deneme
    // genel hataya düşer ve `authFailed` basılır — kural hatası değil.
    expect(find.text(_tr.passwordTooShort), findsNothing,
        reason: 'girişte kural hatası basıldı: eski hesap dışarıda kaldı');
    expect(find.text(_tr.passwordTooSimple), findsNothing);
    expect(find.text(_tr.authFailed), findsOneWidget,
        reason: 'form geçmedi — giriş hiç denenmedi');
  });

  testWidgets('kayıtta zayıf şifre form kapısında DURUR', (tester) async {
    await _ekran(tester);
    await tester.tap(find.text(_tr.signUp));
    await tester.pump();
    // ad(0), e-posta(1), şifre(2), tekrar(3)
    _yaz(tester, 0, 'Ad');
    _yaz(tester, 1, 'yeni@hesap.com');
    _yaz(tester, 2, '12345678');
    _yaz(tester, 3, '12345678');
    await tester.pump();
    // Yaş beyanı — form doğrulamasından önce ayrıca kontrol edilir.
    await tester.tap(find.byType(Checkbox));
    await tester.pump();

    // Kayıt modunda GoldButton da segment de "Üye ol" der; düğme hedef.
    await tester.tap(find.widgetWithText(GoldButton, _tr.signUp));
    await tester.pump();

    expect(find.text(_tr.passwordTooSimple), findsOneWidget,
        reason: 'kayıt validatePassword kullanmaya devam etmeli');
    expect(find.text(_tr.authFailed), findsNothing,
        reason: 'form geçmemeliydi, kayıt denenmemeli');
  });
}
