// SifreAlanlari bekçileri.
//
// Ölçülen kusur: şifre değiştirme (sign_in_methods) tek alan, kuralsız ve
// tekrarsızdı — yanlış yazılan yeni şifre hesabı düşürüyordu. Ortak alan
// çifti kayıtla aynı kuralı (`validatePassword`) ve eşleşme denetimini
// taşır; göz düğmesi her alanda ayrı.
//
// ⚠️ Metin `controller.text` ile yazılır, `tester.enterText` ile DEĞİL:
// bu makinedeki Flutter'da odaklı bir `TextField` çizilirken
// `RenderEditable.promptRectRange` NoSuchMethodError fırlatıyor (ölçüldü
// 2026-10-10, çıplak `TextField` + `enterText` ile de aynı). Odaksız alan
// temiz çiziliyor; doğrulama odak istemiyor.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rytho/l10n/app_localizations.dart';
import 'package:rytho/l10n/app_localizations_tr.dart';
import 'package:rytho/theme/rytho_theme.dart';
import 'package:rytho/widgets/sifre_alanlari.dart';

final _tr = AppLocalizationsTr();

Widget _sar(Widget child) => MaterialApp(
      locale: const Locale('tr'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: buildRythoTheme(),
      home: Scaffold(body: SingleChildScrollView(child: child)),
    );

void main() {
  testWidgets('şifreler uyuşmuyorsa form geçmez, hata tekrar alanında',
      (tester) async {
    final form = GlobalKey<FormState>();
    final sifre = TextEditingController(text: 'Abcdef12');
    final tekrar = TextEditingController(text: 'Abcdef13');
    await tester.pumpWidget(_sar(Form(
        key: form, child: SifreAlanlari(sifre: sifre, tekrar: tekrar))));

    expect(form.currentState!.validate(), isFalse);
    await tester.pump();

    expect(find.text(_tr.passwordsDoNotMatch), findsOneWidget);
  });

  testWidgets('kural ipucu görünür; zayıf şifre reddedilir', (tester) async {
    final form = GlobalKey<FormState>();
    final sifre = TextEditingController();
    final tekrar = TextEditingController();
    await tester.pumpWidget(_sar(
        Form(key: form, child: SifreAlanlari(sifre: sifre, tekrar: tekrar))));

    expect(find.text(_tr.passwordRuleHint), findsOneWidget);

    sifre.text = '1234';
    tekrar.text = '1234';
    await tester.pump();
    expect(form.currentState!.validate(), isFalse);
    await tester.pump();
    expect(find.text(_tr.passwordTooShort), findsOneWidget);

    sifre.text = '12345678';
    tekrar.text = '12345678';
    await tester.pump();
    expect(form.currentState!.validate(), isFalse);
    await tester.pump();
    expect(find.text(_tr.passwordTooSimple), findsOneWidget);
  });

  testWidgets('eşleşen güçlü şifre geçer; göz düğmesi gizliliği açar',
      (tester) async {
    final form = GlobalKey<FormState>();
    final sifre = TextEditingController(text: 'Abcdef12');
    final tekrar = TextEditingController(text: 'Abcdef12');
    await tester.pumpWidget(_sar(
        Form(key: form, child: SifreAlanlari(sifre: sifre, tekrar: tekrar))));

    expect(form.currentState!.validate(), isTrue);

    expect(
        tester.widget<EditableText>(find.byType(EditableText).first).obscureText,
        isTrue);
    await tester.tap(find.byTooltip(_tr.password));
    await tester.pump();
    expect(
        tester.widget<EditableText>(find.byType(EditableText).first).obscureText,
        isFalse);
    // Öteki alanın gözü bağımsız: hâlâ gizli.
    expect(
        tester.widget<EditableText>(find.byType(EditableText).last).obscureText,
        isTrue);
  });

  testWidgets('tekrarIste: false → tek alan', (tester) async {
    await tester.pumpWidget(_sar(
        SifreAlanlari(sifre: TextEditingController(), tekrarIste: false)));

    expect(find.byType(TextFormField), findsOneWidget);
    expect(find.text(_tr.passwordRepeat), findsNothing);
  });
}
