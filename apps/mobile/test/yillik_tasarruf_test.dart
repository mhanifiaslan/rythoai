// Yıllık plan (K8): aylık önseçili, yıllığın yanında YALNIZ ölçülmüş
// "%N tasarruf", fiyat satırı dönemli, deneme satırı birim başına çoğul.
//
// Kapatılan kusurlar: "EN İYİ DEĞER" rozeti yıllığa KOŞULSUZ basılıyordu
// (fiyatlar ne derse desin); deneme satırı `"{count} {unit}"` ile
// İngilizcede "1 weeks free" üretiyordu; bilinmeyen deneme biriminde
// "gün" uyduruluyordu; denemesiz fiyat dönemsiz yazılıyordu ("₺149,99" —
// ayda mı yılda mı belli değil).
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:rytho/core/subscription.dart';
import 'package:rytho/core/wallet.dart';
import 'package:rytho/features/paywall/paywall_acilis.dart';
import 'package:rytho/features/paywall/paywall_screen.dart';
import 'package:rytho/l10n/app_localizations.dart';
import 'package:rytho/theme/rytho_theme.dart';

AppLocalizations _l10n(String dil) => lookupAppLocalizations(Locale(dil));

StoreProduct _urun(String id, double fiyat, String metin,
        {String para = 'TRY', IntroductoryPrice? deneme}) =>
    StoreProduct(id, id, id, fiyat, metin, para, introductoryPrice: deneme);

Package _paket(PackageType tur, StoreProduct urun) => Package(
    urun.identifier, tur, urun, const PresentedOfferingContext('default', null, null));

final _aylik = _urun('rytho_plus_monthly', 149.99, '₺149,99');
final _yillikUcuz = _urun('rytho_plus_yearly', 1199.99, '₺1.199,99');
final _yillikPahali = _urun('rytho_plus_yearly', 1999.99, '₺1.999,99');

Widget _uygulama(Widget ekran) => MaterialApp(
      locale: const Locale('tr'),
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      theme: buildRythoTheme(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: true),
        child: child!,
      ),
      home: ekran,
    );

Future<void> _ciz(WidgetTester tester, List<Package> paketler) async {
  tester.view.physicalSize = const Size(1200, 12000);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(
    retry: (_, _) => null,
    overrides: [
      subscriptionProvider.overrideWith((_) async => SubscriptionStatus.none),
      offeringsProvider.overrideWith((_) async => paketler),
      walletProvider.overrideWith((_) async => WalletStatus.unknown),
    ],
    child: _uygulama(const PaywallScreen(kaynak: PaywallKaynak.tanitim)),
  ));
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
}

void main() {
  group('yillikTasarrufYuzdesi (saf)', () {
    test('12 aylıktan ucuzsa yüzde — mağazanın iki fiyatından', () {
      // 1199,99 / (149,99 × 12) = 0,6667 → %33 tasarruf.
      expect(yillikTasarrufYuzdesi(aylik: _aylik, yillik: _yillikUcuz), 33);
    });

    test('12 aylıktan pahalı ya da eşitse rozet YOK', () {
      expect(yillikTasarrufYuzdesi(aylik: _aylik, yillik: _yillikPahali),
          isNull);
      expect(
          yillikTasarrufYuzdesi(
              aylik: _aylik, yillik: _urun('y', 149.99 * 12, 'x')),
          isNull);
    });

    test('para birimi farklıysa karşılaştırılmaz', () {
      expect(
          yillikTasarrufYuzdesi(
              aylik: _aylik, yillik: _urun('y', 1199.99, r'$', para: 'USD')),
          isNull);
    });

    test('sıfır fiyat → yok (bölme yok, uydurma yok)', () {
      expect(
          yillikTasarrufYuzdesi(aylik: _urun('a', 0, '0'), yillik: _yillikUcuz),
          isNull);
    });
  });

  group('aylikEsdeger (saf)', () {
    test('yıllık fiyat 12\'ye bölünüp aynı para birimiyle biçimlenir', () {
      final s = aylikEsdeger(_yillikUcuz, 'tr');
      expect(s, isNotNull);
      expect(s, contains('100'), reason: '1199,99 / 12 ≈ 100,00');
      expect(s, isNot(contains('1199')));
    });

    test('para birimi yoksa eşdeğer yok', () {
      expect(aylikEsdeger(_urun('y', 1199.99, 'x', para: ''), 'tr'), isNull);
    });
  });

  group('fiyatSatiri (saf)', () {
    test('denemesiz: fiyat + dönem, dönem paket türünden', () {
      expect(fiyatSatiri(_l10n('tr'), _aylik, PackageType.monthly),
          _l10n('tr').priceWithPeriod('₺149,99', _l10n('tr').unitMonth));
      expect(fiyatSatiri(_l10n('en'), _yillikUcuz, PackageType.annual),
          '₺1.199,99 / year');
    });

    test('bilinmeyen paket türünde dönem UYDURULMAZ', () {
      expect(fiyatSatiri(_l10n('tr'), _aylik, PackageType.custom), '₺149,99');
    });

    test('deneme: birim başına anahtar, İngilizce tekil/çoğul doğru', () {
      const hafta1 = IntroductoryPrice(0, '0', 'P1W', 1, PeriodUnit.week, 1);
      const gun3 = IntroductoryPrice(0, '0', 'P3D', 1, PeriodUnit.day, 3);
      final en = _l10n('en');
      expect(
          fiyatSatiri(
              en, _urun('a', 149.99, '₺149,99', deneme: hafta1), PackageType.monthly),
          '1 week free, then ₺149,99');
      expect(
          fiyatSatiri(
              en, _urun('a', 149.99, '₺149,99', deneme: gun3), PackageType.monthly),
          '3 days free, then ₺149,99');
      expect(
          fiyatSatiri(_l10n('tr'), _urun('a', 149.99, '₺149,99', deneme: gun3),
              PackageType.monthly),
          '3 gün ücretsiz, sonra ₺149,99');
    });

    test('bilinmeyen deneme biriminde deneme İDDİA EDİLMEZ', () {
      const bilinmez =
          IntroductoryPrice(0, '0', 'P1X', 1, PeriodUnit.unknown, 1);
      expect(
          fiyatSatiri(_l10n('en'),
              _urun('a', 149.99, '₺149,99', deneme: bilinmez), PackageType.monthly),
          '₺149,99 / month');
    });
  });

  test('yıllık teklif KODDA açık (K3/K8)', () {
    expect(kOfferedPackageTypes, contains(PackageType.annual));
    expect(kOfferedPackageTypes, contains(PackageType.monthly));
  });

  group('paywall (widget)', () {
    testWidgets('iki plan: AYLIK önseçili (listede ikinci olsa da)',
        (tester) async {
      await _ciz(tester, [
        _paket(PackageType.annual, _yillikUcuz),
        _paket(PackageType.monthly, _aylik),
      ]);
      final secili = tester.getTopLeft(find.byIcon(Icons.radio_button_checked_rounded));
      final bos = tester.getTopLeft(find.byIcon(Icons.radio_button_unchecked_rounded));
      expect(secili.dy, greaterThan(bos.dy),
          reason: 'yıllık üstte listelendi ama seçili olan alttaki AYLIK');
    });

    testWidgets('ucuz yıllık → %33 rozeti + aylık eşdeğer', (tester) async {
      final l10n = _l10n('tr');
      await _ciz(tester, [
        _paket(PackageType.monthly, _aylik),
        _paket(PackageType.annual, _yillikUcuz),
      ]);
      expect(find.text(l10n.annualSavingsBadge(33)), findsOneWidget);
      expect(find.text(l10n.annualPerMonth(aylikEsdeger(_yillikUcuz, 'tr')!)),
          findsOneWidget);
      // Eski sabit rozet GİTTİ.
      expect(find.text('EN İYİ DEĞER'), findsNothing);
    });

    testWidgets('pahalı yıllık → rozet YOK', (tester) async {
      await _ciz(tester, [
        _paket(PackageType.monthly, _aylik),
        _paket(PackageType.annual, _yillikPahali),
      ]);
      expect(find.textContaining('tasarruf'), findsNothing);
      expect(find.text('EN İYİ DEĞER'), findsNothing);
    });
  });
}
