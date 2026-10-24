// Harita İnceleme veri başlığı — GERÇEK AĞAÇ bekçileri (mağaza çekimi,
// 2026-10-24).
//
// Ölçülen kusur: başlık satırı profilin `birthDate`/`birthCity` alanlarını
// ham basıyordu — "Deniz · 1997-01-09 · Istanbul", iki dilde de. Aynı iki
// sınıf (ham ISO tarih, GeoNames adı) profil, sihirbaz ve doğum kaydında
// kapatılmıştı; bu satır profilin tek kalan ham kopyasıydı. Natal ve
// sinastri kipi Firebase'e değil sağlayıcılara bağlı — profil ve harita
// yükü üzerine yazılır, ekran gerçekten kurulur (`anlam_once_test`in
// kaynaktan çivilediği kip burada ağaçta ölçülür).
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:rytho/core/people.dart';
import 'package:rytho/core/providers.dart';
import 'package:rytho/features/atlas/chart_inspector_screen.dart';
import 'package:rytho/l10n/app_localizations.dart';
import 'package:rytho/theme/rytho_theme.dart';

/// Demo hesabın kayıtlı hâli: `birthCity` sunucunun çözdüğü GeoNames adı
/// ("Istanbul", İ'siz), `birthDate` ISO.
const _profil = <String, dynamic>{
  'displayName': 'Deniz',
  'birthDate': '1997-01-09',
  'birthTime': '22:00',
  'birthCity': 'Istanbul',
  'birthNation': 'TR',
  'onboardingCompleted': true,
};

/// Boş harita yeterli: başlık yalnız profili okur; çark boş halkayla kurulur.
const _bosNatal = <String, dynamic>{
  'points': <Map<String, dynamic>>[],
  'houses': <Map<String, dynamic>>[],
  'aspects': <Map<String, dynamic>>[],
};

const _bosSinastri = <String, dynamic>{
  'points1': <Map<String, dynamic>>[],
  'points2': <Map<String, dynamic>>[],
  'houses1': <Map<String, dynamic>>[],
  'houses2': <Map<String, dynamic>>[],
  'aspects': <Map<String, dynamic>>[],
};

const _kisi = Person(
    id: 'p1',
    relation: 'partner',
    birthDate: '1990-05-03',
    birthCity: 'Izmir',
    birthNation: 'TR',
    label: 'Ada');

Future<void> _kur(WidgetTester tester,
    {required String dil, required ChartInspectorScreen ekran}) async {
  tester.view.physicalSize = const Size(400 * 3, 1200 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      profileProvider.overrideWith((ref) => Stream.value(_profil)),
      natalChartProvider.overrideWith((ref) async => _bosNatal),
      synastryChartProvider.overrideWith((ref, kisi) async => _bosSinastri),
    ],
    child: MaterialApp(
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      locale: Locale(dil),
      theme: buildRythoTheme(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: true),
        child: child!,
      ),
      home: ekran,
    ),
  ));
  // Akış → profil, gelecek → harita: iki mikro görev turu.
  await tester.pump();
  await tester.pump();
}

/// Ham kusurun iki parçası: hiçbir başlık satırında görünmemeli.
void _hamYok() {
  expect(find.textContaining('1997-01-09'), findsNothing,
      reason: 'doğum tarihi ham ISO basılıyor');
  expect(find.textContaining('Istanbul'), findsNothing,
      reason: 'şehir GeoNames adıyla (İ\'siz) basılıyor');
}

void main() {
  GoogleFonts.config.allowRuntimeFetching = false;

  group('kendi haritan', () {
    testWidgets('TR: tarih dilde, şehir Türkçe yazımla', (tester) async {
      await _kur(tester,
          dil: 'tr',
          ekran: const ChartInspectorScreen(mode: ChartInspectorMode.natal));
      expect(find.text('Deniz · 9 Ocak 1997 · İstanbul'), findsOneWidget);
      _hamYok();
    });

    testWidgets('EN: tarih İngilizce, şehir yine "İstanbul"', (tester) async {
      // Şehir yazımı dilden bağımsız (`sehirGorunenAdi`): veri TR
      // şehirlerini EN arayüzde de Türkçe yazımla taşıyor.
      await _kur(tester,
          dil: 'en',
          ekran: const ChartInspectorScreen(mode: ChartInspectorMode.natal));
      expect(find.text('Deniz · 9 January 1997 · İstanbul'), findsOneWidget);
      _hamYok();
    });
  });

  group('sinastri — başlık senin doğum verini taşır', () {
    for (final (dil, beklenen) in const [
      ('tr', 'Deniz · 9 Ocak 1997 · İstanbul'),
      ('en', 'Deniz · 9 January 1997 · İstanbul'),
    ]) {
      testWidgets('$dil: $beklenen', (tester) async {
        await _kur(tester,
            dil: dil,
            ekran: const ChartInspectorScreen(
                mode: ChartInspectorMode.synastry, person: _kisi));
        expect(find.text(beklenen), findsOneWidget);
        _hamYok();
      });
    }
  });

  testWidgets('kişinin haritası: başlıkta yalnız kişinin adı — senin doğum '
      'verin oraya sızmaz', (tester) async {
    // Ölçüldü: bu kipte satır yalnız adı taşır; düzeltme onu profilin
    // tarihine/şehrine bağlarsa başka birinin haritası senin künyenle
    // etiketlenirdi.
    await _kur(tester,
        dil: 'tr',
        ekran: const ChartInspectorScreen(
            mode: ChartInspectorMode.natal,
            person: _kisi,
            natalOverride: _bosNatal));
    expect(find.text('Ada'), findsOneWidget);
    expect(find.textContaining('Deniz'), findsNothing);
    expect(find.textContaining('9 Ocak 1997'), findsNothing);
    expect(find.textContaining('İstanbul'), findsNothing);
    _hamYok();
  });
}
