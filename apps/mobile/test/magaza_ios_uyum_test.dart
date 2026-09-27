// Satın alma akışının iOS uyum bekçileri (U33, U46, U47).
//
// U33 — RevenueCat'in iOS'ta sık ürettiği üç kod varsayılana düşüyordu:
// onay bekleyen ödeme (Ask to Buy) "Satın alma tamamlanamadı" + Crashlytics
// kaydı, Ekran Süresi kısıtı "birkaç dakika sonra tekrar dene", teklif
// okumasındaki kurulum hatası da henüz satın alma yokken "satın alma
// tamamlanamadı" gösteriyordu.
// U46 — iOS'ta gösterilen mağaza metinleri Google hesabını ve Play test
// kanalını anıyordu. Android metinleri BAYT BAYT korunur.
// U47 — "Aboneliği yönet" aboneliğin alındığı mağazayı değil çalışan
// platformu açıyordu.
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:rytho/core/purchase_errors.dart';
import 'package:rytho/core/subscription.dart';
import 'package:rytho/core/wallet.dart';
import 'package:rytho/features/paywall/paywall_screen.dart';
import 'package:rytho/features/paywall/token_store_screen.dart';
import 'package:rytho/features/profile/subscription_screen.dart';
import 'package:rytho/l10n/app_localizations.dart';
import 'package:rytho/theme/rytho_theme.dart';
import 'package:url_launcher/url_launcher.dart' show LaunchMode;

AppLocalizations _tr() => lookupAppLocalizations(const Locale('tr'));
AppLocalizations _en() => lookupAppLocalizations(const Locale('en'));

/// RevenueCat'in yerel köprüsünün ürettiği biçim: kod, enum SIRASI.
PlatformException _hata(PurchasesErrorCode kod) =>
    PlatformException(code: '${kod.index}', message: 'yerel ileti');

/// Android'e özgü mağaza izleri. Kelime başına bağlı (CLAUDE.md §5: ham
/// alt dizi araması "Display" içindeki "play"e takılırdı).
final _androidIzi =
    RegExp(r'\bGoogle\b|\bPlay\b|test kanal|test track', caseSensitive: false);

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

/// Yükseklik BOL: `ListView` tembel, görünmeyen çocuk ağaçta olmaz
/// (magaza_hata_dali_test deseni).
Future<void> _ciz(WidgetTester tester, Widget kapsam) async {
  tester.view.physicalSize = const Size(1200, 9000);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(kapsam);
  // `pumpAndSettle` YASAK: yıldız alanı sonsuz döner.
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
}

const _urun = StoreProduct('rytho_plus_monthly', 'aylık', 'Rytho+ aylık',
    99.99, '₺99,99', 'TRY');
const _paket = Package(r'$rc_monthly', PackageType.monthly, _urun,
    PresentedOfferingContext('default', null, null));
const _krediUrunu = StoreProduct('rytho_tokens_small', '100 kredi',
    '100 kredi', 49.99, '₺49,99', 'TRY');

/// Yalnız Rytho+ yetkisi taşıyan müşteri bilgisi.
CustomerInfo _musteri({Store? magaza}) {
  final yetkiler = <String, EntitlementInfo>{
    if (magaza != null)
      kPlusEntitlement: EntitlementInfo(kPlusEntitlement, true, true,
          '2026-09-27', '2026-09-27', 'rytho_plus_monthly', false,
          store: magaza),
  };
  return CustomerInfo(EntitlementInfos(yetkiler, yetkiler), const {},
      const [], const [], const [], '2026-09-27', 'uid', const {},
      '2026-09-27');
}

/// Sağlayıcının kaç kez KURULDUĞUNU sayar — geçersiz kılmanın ölçüsü.
class _Sayac {
  int abonelik = 0;
  int cuzdan = 0;
}

const _appleAbonelikleri = 'https://apps.apple.com/account/subscriptions';
const _playAboneligi = 'https://play.google.com/store/account/subscriptions'
    '?sku=rytho_plus_monthly&package=ai.rytho';

/// Açılan adresleri ve açılış kipini kaydeden sahte `launchUrl`
/// (kamera_izni_ios_test deseni).
class _SahteAcici {
  final acilanlar = <(Uri, LaunchMode)>[];

  Future<bool> ac(Uri adres, {LaunchMode mode = LaunchMode.platformDefault}) async {
    acilanlar.add((adres, mode));
    return true;
  }
}

void main() {
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  group('storeErrorText — iOS metinleri (U46)', () {
    setUp(() {
      magazaHataKaydiniSifirla();
      magazaHatasiKaydedici = (_) {};
    });
    tearDown(magazaHataKaydiniSifirla);

    test('iOS: HİÇBİR mağaza kodu Google/Play/test kanalı anmaz (TR + EN)',
        () {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      // Tüm kodlar gezilir: yarın bir dal Android metnine yönlendirilirse
      // hangi kod olduğu fark etmeksizin bu bekçi düşer.
      for (final l10n in [_tr(), _en()]) {
        for (final kod in PurchasesErrorCode.values) {
          final metin = storeErrorText(_hata(kod), l10n);
          expect(_androidIzi.hasMatch(metin), isFalse,
              reason: '$kod iOS\'ta Android talimatı veriyor: "$metin"');
        }
      }
    });

    test('iOS: sahiplik ve ürün yok dalları iOS anahtarlarına gider', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      final l10n = _tr();
      expect(
          storeErrorText(
              _hata(PurchasesErrorCode.productAlreadyPurchasedError), l10n),
          l10n.purchaseAlreadyOwnedIos);
      expect(
          storeErrorText(
              _hata(PurchasesErrorCode.productNotAvailableForPurchaseError),
              l10n),
          l10n.purchaseItemUnavailableIos);
      expect(storeErrorText(_hata(PurchasesErrorCode.purchaseInvalidError), l10n),
          l10n.purchaseItemUnavailableIos);
    });

    test('Android: eski metinler BAYT BAYT — test kanalı ipucu korunur', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final l10n = _tr();
      expect(
          storeErrorText(
              _hata(PurchasesErrorCode.productAlreadyPurchasedError), l10n),
          l10n.purchaseAlreadyOwned);
      expect(
          storeErrorText(
              _hata(PurchasesErrorCode.productNotAvailableForPurchaseError),
              l10n),
          l10n.purchaseItemUnavailable);
      expect(storeErrorText(_hata(PurchasesErrorCode.purchaseInvalidError), l10n),
          l10n.purchaseItemUnavailable);
      expect(storeErrorText(_hata(PurchasesErrorCode.storeProblemError), l10n),
          l10n.purchaseStoreProblem);
      // Erkan vakasının (2026-08-12) çaresi bu metin; iOS dalı onu silmemeli.
      expect(l10n.purchaseItemUnavailable, contains('Test kanalı'));
    });
  });

  group('storeErrorText — iOS kodları (U33)', () {
    late List<String> kayitlar;
    setUp(() {
      magazaHataKaydiniSifirla();
      kayitlar = <String>[];
      magazaHatasiKaydedici = kayitlar.add;
    });
    tearDown(magazaHataKaydiniSifirla);

    for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
      test('${platform.name}: onay bekleyen ödeme bilgi metni, KAYITSIZ', () {
        debugDefaultTargetPlatformOverride = platform;
        final l10n = _tr();
        final hata = _hata(PurchasesErrorCode.paymentPendingError);
        expect(odemeOnayBekliyor(hata), isTrue);
        expect(storeErrorText(hata, l10n), l10n.purchasePending);
        expect(magazaVeyaAgHatasi(hata, l10n), l10n.purchasePending);
        expect(kayitlar, isEmpty,
            reason: 'Ask to Buy saatler sürebilir; her bekleyen alım '
                'Crashlytics\'te sahte bir hata olurdu');
      });

      test('${platform.name}: kurulum hatası "paket yok" der ve KAYDEDİLİR',
          () {
        debugDefaultTargetPlatformOverride = platform;
        final l10n = _tr();
        final hata = _hata(PurchasesErrorCode.configurationError);
        expect(storeErrorText(hata, l10n), l10n.billingNoPackages);
        expect(storeErrorText(hata, l10n), isNot(l10n.purchaseFailed),
            reason: 'teklif okumasında henüz satın alma YOK');
        expect(kayitlar, hasLength(2),
            reason: 'satın alma yolunda her deneme kaydedilir');
      });
    }

    test('kurulum hatası çizim yolunda KOD BAŞINA BİR KEZ kaydedilir', () {
      // iOS'ta bu kodun asıl yeri paywall'ın teklif okuması; hata kartı
      // `build()` içinden çevrildiği için her yeniden çizim kayıt üretirdi.
      final l10n = _tr();
      final hata = _hata(PurchasesErrorCode.configurationError);
      for (var i = 0; i < 3; i++) {
        expect(magazaVeyaAgHatasi(hata, l10n), l10n.billingNoPackages);
      }
      expect(kayitlar, hasLength(1));
    });

    test('iOS: satın alma kısıtı kendi metni — "birkaç dakika sonra" DEĞİL',
        () {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      final l10n = _tr();
      final metin =
          storeErrorText(_hata(PurchasesErrorCode.purchaseNotAllowedError), l10n);
      expect(metin, l10n.purchaseNotAllowedIos);
      expect(metin, isNot(l10n.purchaseStoreProblem),
          reason: 'Ekran Süresi kısıtı kalkmadıkça tekrar denemek boşuna');
      expect(kayitlar, isEmpty);
    });

    test('Android: satın alma kısıtı eski metninde kalır', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final l10n = _tr();
      expect(
          storeErrorText(_hata(PurchasesErrorCode.purchaseNotAllowedError), l10n),
          l10n.purchaseStoreProblem);
    });

    test('odemeOnayBekliyor yalnız bekleyen ödemede doğru', () {
      for (final kod in PurchasesErrorCode.values) {
        expect(odemeOnayBekliyor(_hata(kod)),
            kod == PurchasesErrorCode.paymentPendingError,
            reason: '$kod');
      }
    });
  });

  group('onay bekleyen ödeme ekranda (U33)', () {
    late List<String> kayitlar;
    setUp(() {
      magazaHataKaydiniSifirla();
      kayitlar = <String>[];
      magazaHatasiKaydedici = kayitlar.add;
    });
    tearDown(magazaHataKaydiniSifirla);

    Widget paywall(_Sayac sayac, PurchasesErrorCode kod) => ProviderScope(
          retry: (_, _) => null,
          overrides: [
            subscriptionProvider.overrideWith((_) async {
              sayac.abonelik++;
              return SubscriptionStatus.none;
            }),
            walletProvider.overrideWith((_) async {
              sayac.cuzdan++;
              return WalletStatus.none;
            }),
            offeringsProvider.overrideWith((_) async => const [_paket]),
            paketSatinAliciProvider
                .overrideWithValue((_, _) async => throw _hata(kod)),
          ],
          child: _uygulama(const PaywallScreen()),
        );

    Future<void> satinAl(WidgetTester tester) async {
      await tester.tap(find.text(_tr().paywallContinue));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
    }

    Color? renk(WidgetTester tester, String metin) =>
        tester.widget<Text>(find.text(metin)).style?.color;

    testWidgets('paywall: bilgi rengiyle gösterilir, hata DEĞİL',
        (tester) async {
      final l10n = _tr();
      final sayac = _Sayac();
      await _ciz(tester, paywall(sayac, PurchasesErrorCode.paymentPendingError));
      final oncekiAbonelik = sayac.abonelik;

      await satinAl(tester);

      expect(find.text(l10n.purchasePending), findsOneWidget);
      expect(renk(tester, l10n.purchasePending), isNot(RythoColors.magenta),
          reason: 'macenta "olmadı, yeniden dene" der; yeniden denemek '
              'ikinci bir onay isteği açar');
      expect(find.text(l10n.purchaseFailed), findsNothing);
      expect(kayitlar, isEmpty);
      expect(sayac.abonelik, greaterThan(oncekiAbonelik),
          reason: 'abonelik önbelleği düşürülmeli');
    });

    testWidgets('paywall: gerçek mağaza hatası hâlâ macenta', (tester) async {
      // Karşı örnek: bilgi dalı hata dalını YUTMAMALI.
      final l10n = _tr();
      await _ciz(tester, paywall(_Sayac(), PurchasesErrorCode.storeProblemError));

      await satinAl(tester);

      expect(renk(tester, l10n.purchaseStoreProblem), RythoColors.magenta);
      expect(find.text(l10n.purchasePending), findsNothing);
    });

    testWidgets('kredi mağazası: bilgi gösterilir, cüzdan düşer, abonelik '
        'düşmez', (tester) async {
      final l10n = _tr();
      final sayac = _Sayac();
      await _ciz(
          tester,
          ProviderScope(
            retry: (_, _) => null,
            overrides: [
              subscriptionProvider.overrideWith((_) async {
                sayac.abonelik++;
                return SubscriptionStatus.none;
              }),
              walletProvider.overrideWith((_) async {
                sayac.cuzdan++;
                return WalletStatus.none;
              }),
              tokenPacksProvider.overrideWith((_) async => const [_krediUrunu]),
              krediPaketiSatinAliciProvider.overrideWithValue((_, _) async =>
                  throw _hata(PurchasesErrorCode.paymentPendingError)),
            ],
            child: _uygulama(const TokenStoreScreen()),
          ));
      final oncekiAbonelik = sayac.abonelik;
      final oncekiCuzdan = sayac.cuzdan;

      await tester.tap(find.text(l10n.tokenBuy));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text(l10n.purchasePending), findsOneWidget);
      expect(find.text(l10n.purchaseFailed), findsNothing);
      expect(kayitlar, isEmpty);
      expect(sayac.cuzdan, greaterThan(oncekiCuzdan));
      expect(sayac.abonelik, oncekiAbonelik,
          reason: 'kredi alımı aboneliği değiştirmez; abonelik sağlayıcısını '
              'düşürmek ona bağlı ücretli sağlayıcıları da yeniden kurardı');
    });
  });

  group('Abonelik ekranı', () {
    Widget ekran(SubscriptionStatus durum,
            {GeriYukleyici? geriYukleyici,
            MusteriBilgisiGetirici? musteriGetirici,
            AbonelikSayfasiAcici? adresAcici}) =>
        ProviderScope(
          retry: (_, _) => null,
          overrides: [
            subscriptionProvider.overrideWith((_) async => durum),
            walletProvider.overrideWith((_) async => WalletStatus.none),
            if (geriYukleyici != null)
              geriYukleyiciProvider.overrideWithValue(geriYukleyici),
            if (musteriGetirici != null)
              musteriBilgisiGetiriciProvider.overrideWithValue(musteriGetirici),
          ],
          child: _uygulama(SubscriptionScreen(adresAcici: adresAcici)),
        );

    testWidgets('geri yükleme hatası mağaza çevirmeninden geçer (U33)',
        (tester) async {
      final l10n = _tr();
      await _ciz(
          tester,
          ekran(SubscriptionStatus.none,
              geriYukleyici: (_) async =>
                  throw _hata(PurchasesErrorCode.networkError)));

      await tester.tap(find.text(l10n.restorePurchases));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text(l10n.authNetwork), findsOneWidget,
          reason: 'paywall\'daki aynı düğme bu metni gösteriyor');
      expect(find.text(l10n.errorGeneric), findsNothing,
          reason: '`friendlyError` PlatformException\'ı tanımıyordu');
    });

    // Apple 3.1.1: aboneliği satan ve yöneten ekranda geri yükleme ŞART.
    for (final (ad, durum) in [
      ('ücretsiz', SubscriptionStatus.none),
      (
        'abone',
        const SubscriptionStatus(active: true, productId: 'rytho_plus_monthly')
      ),
    ]) {
      testWidgets('"Satın alımları geri yükle" görünür — $ad', (tester) async {
        await _ciz(tester, ekran(durum));
        expect(find.text(_tr().restorePurchases), findsOneWidget);
      });
    }

    // U47'nin ekrandaki hâli: saf eşleme fonksiyonunun testleri `_manage`
    // eski `storeSubscriptionUri`'ye dönse de yeşil kalırdı.
    const abone =
        SubscriptionStatus(active: true, productId: 'rytho_plus_monthly:monthly');

    Future<void> yonet(WidgetTester tester) async {
      await tester.tap(find.text(_tr().subManage));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
    }

    testWidgets('iOS: Play\'de alınmış abonelik Play sayfasını açar',
        (tester) async {
      final acici = _SahteAcici();
      await _ciz(
          tester,
          ekran(abone,
              musteriGetirici: () async => _musteri(magaza: Store.playStore),
              adresAcici: acici.ac));

      await yonet(tester);

      expect(acici.acilanlar,
          [(Uri.parse(_playAboneligi), LaunchMode.externalApplication)],
          reason: 'Apple sayfasında bu abonelik yok; iptal yolu bulunamaz');
    }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

    testWidgets('Android: App Store\'da alınmış abonelik Apple sayfasını açar',
        (tester) async {
      final acici = _SahteAcici();
      await _ciz(
          tester,
          ekran(abone,
              musteriGetirici: () async => _musteri(magaza: Store.appStore),
              adresAcici: acici.ac));

      await yonet(tester);

      expect(acici.acilanlar,
          [(Uri.parse(_appleAbonelikleri), LaunchMode.externalApplication)]);
    }, variant: TargetPlatformVariant.only(TargetPlatform.android));

    testWidgets('iOS: kaynak okunamazsa yine de çalışan platformun sayfası '
        'açılır', (tester) async {
      final acici = _SahteAcici();
      await _ciz(
          tester,
          ekran(abone,
              musteriGetirici: () async =>
                  throw _hata(PurchasesErrorCode.networkError),
              adresAcici: acici.ac));

      await yonet(tester);

      expect(acici.acilanlar,
          [(Uri.parse(_appleAbonelikleri), LaunchMode.externalApplication)],
          reason: 'düğme ölü kalmamalı; eski davranış');
    }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

    testWidgets('sorgu sürerken ikinci dokunuş ikinci sayfa açmaz',
        (tester) async {
      final acici = _SahteAcici();
      final cevap = Completer<CustomerInfo>();
      await _ciz(
          tester,
          ekran(abone,
              musteriGetirici: () => cevap.future, adresAcici: acici.ac));

      await yonet(tester);
      await yonet(tester);
      cevap.complete(_musteri(magaza: Store.appStore));
      await tester.pump();

      expect(acici.acilanlar, hasLength(1));
    });

    testWidgets('paywall\'da "Satın alımları geri yükle" görünür',
        (tester) async {
      await _ciz(
          tester,
          ProviderScope(
            retry: (_, _) => null,
            overrides: [
              subscriptionProvider
                  .overrideWith((_) async => SubscriptionStatus.none),
              offeringsProvider.overrideWith((_) async => const [_paket]),
            ],
            child: _uygulama(const PaywallScreen()),
          ));
      expect(find.text(_tr().restorePurchases), findsOneWidget);
    });
  });

  group('aboneligiYonetAdresi — kaynak mağaza (U47)', () {
    const apple = _appleAbonelikleri;
    const play = _playAboneligi;

    test('Play aboneliği iPhone\'da Play sayfasını açar', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      expect(
          aboneligiYonetAdresi(Store.playStore, 'rytho_plus_monthly:monthly')
              .toString(),
          play,
          reason: 'Apple sayfasında bu abonelik yok; iptal yolu bulunamaz');
    });

    test('App Store aboneliği Android\'de Apple sayfasını açar', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      expect(
          aboneligiYonetAdresi(Store.appStore, 'rytho_plus_monthly').toString(),
          apple);
      expect(aboneligiYonetAdresi(Store.macAppStore, null).toString(), apple);
    });

    test('kaynak bilinmiyorsa ya da mağaza değilse çalışan platform', () {
      for (final kaynak in [
        null,
        Store.promotional,
        Store.testStore,
        Store.unknownStore,
      ]) {
        debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
        expect(aboneligiYonetAdresi(kaynak, 'rytho_plus_monthly').toString(),
            apple,
            reason: '$kaynak');
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        expect(aboneligiYonetAdresi(kaynak, 'rytho_plus_monthly').toString(),
            play,
            reason: '$kaynak');
      }
    });
  });

  group('abonelikKaynakMagazasi (U47)', () {
    test('Rytho+ yetkisinin mağazasını döner', () async {
      expect(
          await abonelikKaynakMagazasi(
              () async => _musteri(magaza: Store.playStore)),
          Store.playStore);
      expect(
          await abonelikKaynakMagazasi(
              () async => _musteri(magaza: Store.appStore)),
          Store.appStore);
    });

    test('etkin Rytho+ yetkisi yoksa null', () async {
      expect(await abonelikKaynakMagazasi(() async => _musteri()), isNull);
    });

    test('sorgu düşerse null — çalışan platform açılır', () async {
      expect(
          await abonelikKaynakMagazasi(
              () async => throw _hata(PurchasesErrorCode.networkError)),
          isNull);
    });

    test('mağaza anahtarı yoksa RevenueCat hiç sorulmaz', () async {
      // `null` dönmesi TEK BAŞINA kanıt DEĞİL: işlev her hatayı yutup null
      // döndüğü için kapı sökülse de `Purchases.getCustomerInfo` testte
      // fırlatır (eklenti yok), yakalanır ve sonuç yine null olur. İki yolu
      // ayıran, yakalama dalının bıraktığı `debugPrint` izi — kapı yerindeyse
      // çağrı hiç yapılmaz, iz de çıkmaz.
      final onceki = debugPrint;
      final basilanlar = <String>[];
      debugPrint = (mesaj, {wrapWidth}) => basilanlar.add(mesaj ?? '');
      addTearDown(() => debugPrint = onceki);

      expect(billingConfigured, isFalse);
      expect(await abonelikKaynakMagazasi(null), isNull);
      expect(basilanlar, isEmpty,
          reason: 'anahtarsız yapıda RevenueCat çağrılmış ve düşmüş');
    });

    test('yakalama dalı iz bırakır — üstteki bekçinin ölçüsü', () async {
      // Karşı örnek: iz hiç basılmasaydı "iz yok" hiçbir şey ölçmezdi.
      final onceki = debugPrint;
      final basilanlar = <String>[];
      debugPrint = (mesaj, {wrapWidth}) => basilanlar.add(mesaj ?? '');
      addTearDown(() => debugPrint = onceki);

      await abonelikKaynakMagazasi(
          () async => throw _hata(PurchasesErrorCode.networkError));
      expect(basilanlar, [startsWith('Abonelik mağazası okunamadı')]);
    });

    testWidgets('cevap gelmezse süre sınırında null', (tester) async {
      // Kullanıcı "Aboneliği yönet"e dokunmuş bekliyor; asılı bir SDK
      // çağrısı düğmeyi sonsuza dek ölü bırakmamalı.
      Store? sonuc = Store.stripe;
      var bitti = false;
      unawaited(abonelikKaynakMagazasi(() => Completer<CustomerInfo>().future)
          .then((s) {
        sonuc = s;
        bitti = true;
      }));
      await tester.pump(const Duration(seconds: 2));
      expect(bitti, isFalse);
      await tester.pump(const Duration(seconds: 2));
      expect(bitti, isTrue);
      expect(sonuc, isNull);
    });
  });
}
