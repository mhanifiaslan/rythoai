// `openLegal` bekçisi — hukuk metnine giden ÜÇ yolun tek kapısı.
//
// Giriş ekranı, sihirbaz ve profil `LegalPage`i üç ayrı yoldan kuruyordu;
// sihirbaz dili sabitlerle seçiyordu. Kapı doğru başlıkla doğru metni iter;
// rota gözcüsüyle ölçülür.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rytho/features/profile/legal_page.dart';
import 'package:rytho/l10n/app_localizations.dart';
import 'package:rytho/l10n/app_localizations_en.dart';
import 'package:rytho/l10n/app_localizations_tr.dart';
import 'package:rytho/theme/rytho_theme.dart';
import 'package:rytho/theme/rytho_tokens.dart';

final _tr = AppLocalizationsTr();
final _en = AppLocalizationsEn();

class _RotaGozcusu extends NavigatorObserver {
  final itilenler = <Route<dynamic>>[];

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    itilenler.add(route);
  }
}

Widget _sar(LegalDoc doc, {required String dil, NavigatorObserver? gozcu}) =>
    MaterialApp(
      locale: Locale(dil),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: buildRythoTheme(),
      navigatorObservers: gozcu != null ? [gozcu] : const [],
      // Yıldız alanı sürekli animatör: ölçülen şey rota, hareket değil.
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: true),
        child: child!,
      ),
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
              onPressed: () => openLegal(context, doc),
              child: const Text('AÇ')),
        ),
      ),
    );

Future<LegalPage> _acVeBul(WidgetTester tester) async {
  await tester.tap(find.text('AÇ'));
  await tester.pump();
  await tester.pump(RythoMotion.route);
  return tester.widget<LegalPage>(find.byType(LegalPage));
}

void main() {
  testWidgets('terms → Kullanım Şartları sayfası itilir (TR)', (tester) async {
    final gozcu = _RotaGozcusu();
    await tester.pumpWidget(_sar(LegalDoc.terms, dil: 'tr', gozcu: gozcu));

    final sayfa = await _acVeBul(tester);
    // İlk rota ana sayfa, ikincisi bizim ittiğimiz.
    expect(gozcu.itilenler.length, 2);
    expect(sayfa.title, _tr.termsOfUse);
    expect(sayfa.sections, termsOfUseSections('tr'));
  });

  testWidgets('privacy → Gizlilik Politikası, dil İngilizceyse İngilizce metin',
      (tester) async {
    await tester.pumpWidget(_sar(LegalDoc.privacy, dil: 'en'));

    final sayfa = await _acVeBul(tester);
    expect(sayfa.title, _en.privacyPolicy);
    expect(sayfa.sections, privacyPolicySections('en'));
    expect(sayfa.sections, isNot(privacyPolicySections('tr')));
  });
}
