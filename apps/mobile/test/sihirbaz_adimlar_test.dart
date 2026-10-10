// Sihirbaz adımlarının widget bekçileri (D4).
//
// Seçiciler test dikişiyle (`SihirbazSeciciler`) sabit değer döndürür:
// ölçülen şey sihirbazın KURALI (hangi adım neyle geçer, düğme ne zaman
// açılır, ekran okuyucu neyi duyar), seçicilerin diyaloğu değil.
//
// `_bitir` burada ÇALIŞTIRILMAZ: Firebase ister. Onun kuralları
// `sihirbaz_mantik_test` kaynak bekçilerinde.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rytho/core/city_directory.dart' show CityPick;
import 'package:rytho/features/onboarding/constellation_progress.dart';
import 'package:rytho/features/onboarding/onboarding_wizard.dart';
import 'package:rytho/l10n/app_localizations.dart';
import 'package:rytho/l10n/app_localizations_tr.dart';
import 'package:rytho/theme/rytho_theme.dart';
import 'package:rytho/widgets/atlas_widgets.dart' show GoldButton;
import 'package:rytho/widgets/dogum_formu.dart' show CinsiyetSecici;
import 'package:rytho/widgets/izin_kapisi.dart' show IzinKapisi;

final _tr = AppLocalizationsTr();

const _saat = TimeOfDay(hour: 4, minute: 30);

/// Seçiciler diyalog açmadan sabit değer döndürür; [saat] null → kullanıcı
/// seçiciyi seçmeden kapattı.
SihirbazSeciciler _seciciler({TimeOfDay? saat = _saat}) => SihirbazSeciciler(
      tarih: (_, _) async => DateTime(1990, 3, 7),
      saat: (_, _) async => saat,
      sehir: (_, _) async => const CityPick(
          name: 'Kahramanmaraş', nation: 'TR', admin1: 'Kahramanmaraş'),
    );

Widget _sar(SihirbazSeciciler seciciler) => ProviderScope(
      child: MaterialApp(
        locale: const Locale('tr'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: buildRythoTheme(),
        // Takımyıldız nabzı sonsuz animatör (constellation_progress): hareket
        // kapalıyken statik çizilir, sayfa geçişi `kapili` ile anında olur.
        // Ölçülen şey kural, hareket değil.
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: true),
          child: child!,
        ),
        home: OnboardingWizard(seciciler: seciciler),
      ),
    );

Future<void> _pompala(WidgetTester tester,
    {SihirbazSeciciler? seciciler}) async {
  await tester.pumpWidget(_sar(seciciler ?? _seciciler()));
  await tester.pump();
}

/// Alt düğme — adım sayfalarında tek GoldButton bu.
GoldButton _dugme(WidgetTester tester) =>
    tester.widget<GoldButton>(find.byType(GoldButton));

Future<void> _dokun(WidgetTester tester, Finder f) async {
  await tester.tap(f);
  await tester.pump();
  await tester.pump();
}

Future<void> _devam(WidgetTester tester) => _dokun(tester, find.byType(GoldButton));

/// Karşılama → tarih.
Future<void> _tariheGit(WidgetTester tester) async {
  await _dokun(tester, find.byType(Checkbox).first);
  await _devam(tester);
  expect(find.text(_tr.wizardDateTitle), findsOneWidget);
}

/// Tarih → saat.
Future<void> _saateGit(WidgetTester tester) async {
  await _dokun(tester, find.text(_tr.birthDate));
  await _devam(tester);
  expect(find.text(_tr.wizardTimeTitle), findsOneWidget);
}

/// Saat → yer ("bilmiyorum" ile).
Future<void> _yereGit(WidgetTester tester) async {
  await _dokun(tester, find.byType(Checkbox));
  await _devam(tester);
  expect(find.text(_tr.wizardPlaceTitle), findsOneWidget);
}

/// Yer → cinsiyet.
Future<void> _cinsiyeteGit(WidgetTester tester) async {
  await _dokun(tester, find.text(_tr.onboardingCity));
  await _devam(tester);
  expect(find.text(_tr.wizardGenderTitle), findsOneWidget);
}

/// Cinsiyet → bildirim ("belirtmedim" ile).
Future<void> _bildirimeGit(WidgetTester tester) async {
  await _dokun(tester, find.text(_tr.genderUnspecified));
  await _devam(tester);
  expect(find.text(_tr.wizardNotifyTitle), findsOneWidget);
}

/// Seçili segment dolgusu (`GlassSegments`), yalnız [of] altında.
int _dolguluSegment(WidgetTester tester, Finder of) => tester
    .widgetList<AnimatedContainer>(
        find.descendant(of: of, matching: find.byType(AnimatedContainer)))
    .where((c) => (c.decoration as BoxDecoration?)?.color != null)
    .length;

void main() {
  testWidgets('saat: seçilmeden Devam kapalı ve "—"; seçici boş dönerse hâlâ '
      'kapalı; seçince HH:mm ve açık', (tester) async {
    await _pompala(tester, seciciler: _seciciler(saat: null));
    await _tariheGit(tester);
    await _saateGit(tester);

    expect(_dugme(tester).onPressed, isNull,
        reason: '"biliyorum" + saat yok → 12:00 yazılmasın');
    expect(find.text('—'), findsOneWidget);
    await _dokun(tester, find.text(_tr.birthTime));
    expect(_dugme(tester).onPressed, isNull,
        reason: 'seçici boş döndü: hâlâ seçilmemiş');
    expect(find.text('—'), findsOneWidget);
    expect(find.text('12:00'), findsNothing);
  });

  testWidgets('saat seçilince satır HH:mm gösterir ve Devam açılır',
      (tester) async {
    await _pompala(tester);
    await _tariheGit(tester);
    await _saateGit(tester);

    await _dokun(tester, find.text(_tr.birthTime));
    expect(find.text('04:30'), findsOneWidget);
    expect(_dugme(tester).onPressed, isNotNull);
  });

  testWidgets('cinsiyet: hiçbir segment seçili değil, Devam kapalı; seçince '
      'tek dolgu ve açık', (tester) async {
    await _pompala(tester);
    await _tariheGit(tester);
    await _saateGit(tester);
    await _yereGit(tester);
    await _cinsiyeteGit(tester);

    final secici = find.byType(CinsiyetSecici);
    expect(_dolguluSegment(tester, secici), 0,
        reason: 'seçilmeyen cinsiyet beyan edilmez (eski: female önseçili)');
    expect(_dugme(tester).onPressed, isNull);
    expect(find.text(_tr.genderUnspecified), findsOneWidget);

    await _dokun(tester, find.text(_tr.genderMale));
    expect(_dolguluSegment(tester, secici), 1);
    expect(_dugme(tester).onPressed, isNotNull);
  });

  testWidgets('bildirim: "Şimdi değil" etiketi; seçimsiz bitir kapalı; '
      'seçince "Haritamı çiz" açılır', (tester) async {
    await _pompala(tester);
    await _tariheGit(tester);
    await _saateGit(tester);
    await _yereGit(tester);
    await _cinsiyeteGit(tester);
    await _bildirimeGit(tester);

    expect(find.byType(IzinKapisi), findsOneWidget);
    expect(find.text(_tr.wizardNotifyNotNow), findsOneWidget);
    expect(find.text(_tr.wizardNotifyAllow), findsOneWidget);
    expect(_dugme(tester).text, _tr.wizardFinish);
    expect(_dugme(tester).onPressed, isNull,
        reason: 'karar verilmeden yolculuk bitmez');

    await _dokun(tester, find.text(_tr.wizardNotifyNotNow));
    expect(_dolguluSegment(tester, find.byType(IzinKapisi)), 1);
    expect(_dugme(tester).onPressed, isNotNull);
  });

  testWidgets('alt düğme hiçbir adımda "Sonra" demez: son adım "Haritamı çiz", '
      'diğerleri "Devam"', (tester) async {
    await _pompala(tester);
    final adimlar = [_tariheGit, _saateGit, _yereGit, _cinsiyeteGit, _bildirimeGit];
    expect(_dugme(tester).text, _tr.wizardNext);
    for (final git in adimlar) {
      await git(tester);
      expect(find.text(_tr.wizardLater), findsNothing);
    }
    expect(_dugme(tester).text, _tr.wizardFinish);
  });

  testWidgets('takımyıldız: adım+1 yıldız, ilki yanmış başlar; ekran okuyucuya '
      '"Adım i/6" der', (tester) async {
    final semantik = tester.ensureSemantics();
    await _pompala(tester);
    ConstellationProgress yildizlar() => tester
        .widget<ConstellationProgress>(find.byType(ConstellationProgress));
    // Altı adım, yedi yıldız: sonuncusu kayıt sahnesinde yanar (takımyıldız
    // harita gerçekten çizilirken tamamlanır); ilki yanmış başlar — endowed
    // progress, "hesabını açtın bile".
    expect(yildizlar().total, kOnboardingSteps.length + 1);
    expect(yildizlar().lit, 1);
    expect(find.bySemanticsLabel(_tr.wizardStepOf(1, 6)), findsOneWidget);

    await _tariheGit(tester);
    expect(yildizlar().lit, 2);
    expect(find.bySemanticsLabel(_tr.wizardStepOf(2, 6)), findsOneWidget);
    expect(find.bySemanticsLabel(_tr.wizardStepOf(1, 6)), findsNothing);
    semantik.dispose();
  });

  testWidgets('geri tuşu bir adım geri gider, ilk adımda çıkmaz',
      (tester) async {
    await _pompala(tester);
    await _tariheGit(tester);
    await _dokun(tester, find.byIcon(Icons.arrow_back_rounded));
    expect(find.text(_tr.wizardWelcomeTitle), findsOneWidget);
    expect(find.byIcon(Icons.arrow_back_rounded), findsNothing);
  });
}
