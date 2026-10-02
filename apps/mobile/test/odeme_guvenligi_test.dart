// SURUM 47 — ödeme akışı güvenliği bekçileri.
//
// Dört kusur sahibin iki günlük gerçek kullanımında ölçüldü ve ikisi PARA
// KAYBETTİRİYORDU. Bu dosya onların geri gelmesini sessiz bırakmıyor:
//
// 1. Geri tuşu ödeme uçarken kapalı mı? (`PopScope.canPop`) — depodaki üç
//    `PopScope`un hiçbiri ödeme ekranlarında değildi.
// 2. Onuncu saniyedeki çıkış, satın alma düğmesini YENİDEN BASILABİLİR
//    yapıyor mu? Eski hâl `_mesguliyet(false)` çağırıyordu ve `GoldButton`un
//    kuralı `enabled = onPressed != null && !busy` olduğu için düğme
//    canlanıyordu → ikinci satın alma.
// 3. Jeton paketi beklemesinin TOPLAM bütçesi var mı? Abonelikte 15 sn
//    kapısı vardı, jeton tarafına taşınmamıştı (en kötü ~40 sn) ve oradaki
//    yorum "abonelikteki desenle aynı bütçe" diyordu — yorumun gerekçesi de
//    yanlıştı.
// 4. Paketler yalnız aboneye görünüyor mu, BİLİNMİYOR hâlinde iskelet mi?
//
// Mağaza yolu dikişle kesiliyor (`paketSatinAliciProvider`,
// `jetonSatinAliciProvider`): `Purchases` eklentisi `flutter test` içinde
// çağrılamaz, oysa ölçülmek istenen şey satın almanın kendisi değil mağaza
// cevap VERMEZKEN ekranın hâli.
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:rytho/core/providers.dart' show authStateProvider;
import 'package:rytho/core/subscription.dart';
import 'package:rytho/core/wallet.dart';
import 'package:rytho/features/paywall/paywall_screen.dart';
import 'package:rytho/features/paywall/token_store_screen.dart';
import 'package:rytho/l10n/app_localizations.dart';
import 'package:rytho/theme/rytho_theme.dart';
import 'package:rytho/widgets/atlas_widgets.dart' show GoldButton;
import 'package:rytho/widgets/common.dart' show ErrorCard;
import 'package:rytho/widgets/glass.dart' show SkeletonPanel;

/// ARB'deki metin üretilen sınıftan okunur: metin değişince test kırılmaz,
/// anahtar silinirse derleme kırılır (magaza_hata_dali_test deseni).
AppLocalizations _tr() => lookupAppLocalizations(const Locale('tr'));

const _kUrunKimligi = 'rytho_plus_monthly';

/// Mağazadan gelmiş gibi bir paket. `Package` ve `StoreProduct`un const
/// kurucuları var (purchases_flutter 9.16.1'de ölçüldü), yani eklentiye hiç
/// dokunmadan gerçek tipler kurulabiliyor — sahte bir arayüz uydurmak
/// gerekmedi.
const _kPaket = Package(
  _kUrunKimligi,
  PackageType.monthly,
  StoreProduct(_kUrunKimligi, 'aylık', 'Aylık', 149.99, '₺149,99', 'TRY'),
  PresentedOfferingContext('default', null, null),
);

const _kJetonUrunu = StoreProduct(
    'rytho_tokens_small', '100 kredi', '100 kredi', 99.99, '₺99,99', 'TRY');

/// Türkçe, animasyonsuz kabuk.
///
/// [gezgin] verilirse ekran İKİNCİ rota olarak itilebilir. Gerektiği
/// ölçüldü: `home` olarak kurulan tek rota pop EDİLEMEZ (altında rota
/// kalmaz), yani "çıkış ekranı kapatır" sözleşmesi `home` kabuğunda hiç
/// ölçülemiyordu — aşağıdaki bekçiye bak.
Widget _uygulama(Widget ekran,
        {GlobalKey<NavigatorState>? gezgin}) =>
    MaterialApp(
      navigatorKey: gezgin,
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

/// Ekranı çizer.
///
/// Yükseklik BOL: test yazı tipi her harfi punto kadar geniş kare çizdiği
/// için içerik gerçek cihazdan uzun, `ListView` ise tembel — görünme alanına
/// hiç girmeyen çocuk AĞAÇTA OLMAZ ve finder onu bulamaz.
Future<void> _ciz(WidgetTester tester, Widget kapsam) async {
  tester.view.physicalSize = const Size(1200, 12000);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(kapsam);
  // `pumpAndSettle` YASAK: yıldız alanı sonsuz döner (bkz.
  // widgets/cosmic_scaffold.dart StarfieldBackground).
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
}

/// Ekrandaki `PopScope`un geri tuşuna ne dediği.
///
/// `canPop` SÖZLEŞME olarak okunuyor: geri jestini taklit etmek testte
/// platform kanalı ister ve kırılgan olur. `PopScope` yokken bu finder
/// düşer — kapının SİLİNMESİ de yakalanıyor.
bool _geriTusuGecer(WidgetTester tester, Type ekran) {
  final kapi = find.descendant(
      of: find.byType(ekran), matching: find.byType(PopScope));
  expect(kapi, findsOneWidget, reason: 'ödeme ekranında PopScope ŞART');
  return tester.widget<PopScope>(kapi).canPop;
}

/// Metnine göre bulunan `GoldButton` basılabilir mi?
///
/// Kural `GoldButton`un gövdesinde: `enabled = onPressed != null && !busy`.
/// Test o kuralı TEKRAR ETMİYOR, ikisini birden soruyor — düğme hangi
/// yoldan canlanırsa yakalanır.
///
/// Düğme `text` ALANINDAN bulunuyor, ekrandaki metinden değil: `busy` iken
/// `GoldButton` etiketi hiç çizmiyor (yerine spinner koyuyor), yani
/// `find.text` tam da ölçmek istediğimiz anda düğmeyi bulamıyor.
bool _dugmeBasilabilir(WidgetTester tester, String metin) {
  final dugme = tester
      .widgetList<GoldButton>(find.byType(GoldButton))
      .singleWhere((d) => d.text == metin);
  return dugme.onPressed != null && !dugme.busy;
}

/// AppBar'ın kapatma/geri düğmesi.
IconButton _kapatmaDugmesi(WidgetTester tester) => tester.widget<IconButton>(
    find.descendant(of: find.byType(AppBar), matching: find.byType(IconButton)));

void main() {
  group('paywall: ödeme uçarken ekran KİLİTLİ', () {
    testWidgets('geri tuşu kapalı, kapatma düğmesi ölü, düğme basılamaz',
        (tester) async {
      final l10n = _tr();
      // Mağaza HİÇ dönmüyor: tam olarak kullanıcının "ödeme adımını
      // geçemiyorum" dediği hâl.
      final asilmisMagaza = Completer<SatinAlmaSonucu>();
      addTearDown(() => asilmisMagaza.complete(SatinAlmaSonucu.yetkiYok));

      await _ciz(
          tester,
          ProviderScope(
            retry: (_, _) => null,
            overrides: [
              subscriptionProvider
                  .overrideWith((_) async => SubscriptionStatus.none),
              offeringsProvider.overrideWith((_) async => [_kPaket]),
              paketSatinAliciProvider
                  .overrideWithValue((_, _) => asilmisMagaza.future),
            ],
            child: _uygulama(const PaywallScreen()),
          ));

      // Ödeme başlamadan önce ekran kapanabilir olmalı: kilit KOŞULLU.
      expect(_geriTusuGecer(tester, PaywallScreen), isTrue,
          reason: 'meşgul değilken paywall kapatılabilir');
      expect(_kapatmaDugmesi(tester).onPressed, isNotNull);

      await tester.tap(find.text(l10n.paywallContinue));
      await tester.pump();

      expect(_geriTusuGecer(tester, PaywallScreen), isFalse,
          reason: 'ödeme uçarken geri tuşu ekranı kapatmamalı');
      expect(_kapatmaDugmesi(tester).onPressed, isNull,
          reason: 'kapatma düğmesinde _busy kapısı HİÇ YOKTU');
      expect(_dugmeBasilabilir(tester, l10n.paywallContinue), isFalse);
      // Para istenen ekranın en pahalı saniyeleri 22 piksellik bir halkaya
      // emanetti; artık ne olduğunu söyleyen bir satır var.
      expect(find.text(l10n.purchaseWaitingStore), findsOneWidget);
    });

    testWidgets('onuncu saniye: çıkış açılır ama düğme CANLANMAZ',
        (tester) async {
      final l10n = _tr();
      final asilmisMagaza = Completer<SatinAlmaSonucu>();
      addTearDown(() => asilmisMagaza.complete(SatinAlmaSonucu.yetkiYok));

      await _ciz(
          tester,
          ProviderScope(
            retry: (_, _) => null,
            overrides: [
              subscriptionProvider
                  .overrideWith((_) async => SubscriptionStatus.none),
              offeringsProvider.overrideWith((_) async => [_kPaket]),
              paketSatinAliciProvider
                  .overrideWithValue((_, _) => asilmisMagaza.future),
            ],
            child: _uygulama(const PaywallScreen()),
          ));

      await tester.tap(find.text(l10n.paywallContinue));
      await tester.pump();
      // Sabırsızlık zamanlayıcısı 10 saniyede dolar.
      await tester.pump(const Duration(seconds: 11));

      // Eski hâlde buradaki düğme `_mesguliyet(false)` çağırıyordu: spinner
      // duruyor, ekran BİTMİŞ görünüyor ve düğme ikinci satın almaya açık
      // hale geliyordu. Ölçülen kusur tam buydu.
      expect(find.text(l10n.purchaseLeaveScreen), findsOneWidget,
          reason: 'bekleyiş uzarsa kullanıcıya bir yol gösterilmeli');
      expect(_dugmeBasilabilir(tester, l10n.paywallContinue), isFalse,
          reason: 'ÇİFT SATIN ALMA: düğme yeniden basılabilir OLMAMALI');
      expect(_geriTusuGecer(tester, PaywallScreen), isFalse,
          reason: 'çıkış kasıtlı düğmeden; kaza ile geri tuşundan değil');
      expect(find.text(l10n.purchaseWaitingLong), findsOneWidget,
          reason: 'metin sertleşir: "kapatsan da kaybolmaz"');
      // "Vazgeç" metni bir dönem bu ekranda meşguliyeti silen düğmenin
      // etiketiydi; geri gelirse yanlış vaat geri gelmiş olur.
      expect(find.text(l10n.cancel), findsNothing);
    });

    testWidgets('çıkış düğmesi EKRANI pop eder — meşguliyeti SİLMEZ',
        (tester) async {
      // ⚠️ Bu bekçi bir BEKÇİ BOŞLUĞUNU kapatıyor ve boşluk ÖLÇÜLDÜ:
      // yukarıdaki test çıkış düğmesine HİÇ BASMIYOR, yalnız 11. saniyedeki
      // çizimi soruyor. Onarımı geri alsan (`onPressed: () =>
      // _mesguliyet(false)`) o test YEŞİL kalıyordu — yani turun en pahalı
      // kusuru (düğme yeniden basılabilir hale gelip İKİNCİ SATIN ALMA)
      // bekçisiz duruyordu.
      //
      // Sözleşme: düğme ekranı POP eder. Eski kusurlu hâlde ekran YERINDE
      // KALIR (yalnız spinner durur), yani `findsNothing` o hâlde düşer.
      final l10n = _tr();
      final gezgin = GlobalKey<NavigatorState>();
      final asilmisMagaza = Completer<SatinAlmaSonucu>();
      addTearDown(() => asilmisMagaza.complete(SatinAlmaSonucu.yetkiYok));

      await _ciz(
          tester,
          ProviderScope(
            retry: (_, _) => null,
            overrides: [
              subscriptionProvider
                  .overrideWith((_) async => SubscriptionStatus.none),
              offeringsProvider.overrideWith((_) async => [_kPaket]),
              paketSatinAliciProvider
                  .overrideWithValue((_, _) => asilmisMagaza.future),
            ],
            // Paywall İKİNCİ rota: pop edilebilmesi için altında bir rota
            // durmak zorunda.
            child: _uygulama(const Scaffold(body: SizedBox.shrink()),
                gezgin: gezgin),
          ));
      gezgin.currentState!
          .push(MaterialPageRoute(builder: (_) => const PaywallScreen()));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      await tester.tap(find.text(l10n.paywallContinue));
      await tester.pump();
      await tester.pump(const Duration(seconds: 11));
      await tester.tap(find.text(l10n.purchaseLeaveScreen));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      expect(find.byType(PaywallScreen), findsNothing,
          reason: 'çıkış EKRANI kapatır; meşguliyeti indirmek '
              'İKİNCİ SATIN ALMANIN kapısını açıyordu');
    });

    testWidgets('paywall yedi değil DOKUZ fayda sayıyor', (tester) async {
      final l10n = _tr();
      await _ciz(
          tester,
          ProviderScope(
            retry: (_, _) => null,
            overrides: [
              subscriptionProvider
                  .overrideWith((_) async => SubscriptionStatus.none),
              offeringsProvider.overrideWith((_) async => [_kPaket]),
            ],
            child: _uygulama(const PaywallScreen()),
          ));

      // Son turların eklediği her Plus özelliği bu ekranda YOKTU. Hepsinin
      // sunucudaki kapısı ölçüldü (require_plus / people_service).
      for (final baslik in [
        l10n.benefitFaceTitle,
        l10n.benefitTimingTitle,
        l10n.benefitIchingTitle,
        l10n.benefitPeopleTitle,
      ]) {
        expect(find.text(baslik), findsOneWidget, reason: baslik);
      }
      // Aylık hak 300'den 100'e indi (K1); satış ekranındaki sayı sunucunun
      // sabitiyle aynı cümleyi kurmalı.
      expect(l10n.benefitChatTitle, contains('100'));
      expect(l10n.benefitChatTitle, isNot(contains('300')));
    });
  });

  group('jeton mağazası', () {
    /// Abonelik durumu verili kapsam.
    ///
    /// `durum: null` = okuma HİÇ TAMAMLANMAZ, yani "BİLİNMİYOR"un ta
    /// kendisi; `SubscriptionStatus.bilinmiyor` ise "okuma düştü".
    Widget jetonKapsami(
            {required SubscriptionStatus? durum, JetonSatinAlici? satinAlici}) =>
        ProviderScope(
          retry: (_, _) => null,
          overrides: [
            walletProvider.overrideWith((_) async => WalletStatus.none),
            tokenPacksProvider.overrideWith((_) async => [_kJetonUrunu]),
            subscriptionProvider.overrideWith((_) =>
                durum == null
                    ? Completer<SubscriptionStatus>().future
                    : Future.value(durum)),
            if (satinAlici != null)
              jetonSatinAliciProvider.overrideWithValue(satinAlici),
          ],
          child: _uygulama(const TokenStoreScreen()),
        );

    testWidgets('abone olmayana paket GÖSTERİLMEZ', (tester) async {
      final l10n = _tr();
      await _ciz(tester, jetonKapsami(durum: SubscriptionStatus.none));

      // Ölçüldü: `charge_metered` tüm depoda yalnız `api/chat.py`'de
      // çağrılıyor ve beş jetonluk raporların hepsi `require_plus`
      // arkasında — abone olmayanın aldığı paketin tek kullanım senaryosu
      // "günün 6. sohbet mesajı"ydı.
      expect(find.byType(GoldButton), findsOneWidget,
          reason: 'tek düğme kalmalı: Rytho+ yolu');
      expect(find.text(l10n.tokenBuy), findsNothing,
          reason: 'satın alma düğmesi abone olmayana çizilmez');
      expect(find.text(l10n.tokenPacksPlusOnlyTitle), findsOneWidget);
      expect(find.text(l10n.tokenPacksSeePlus), findsOneWidget);
      // Bakiye kartı KALIYOR: elinde kredisi olan ücretsiz kullanıcı
      // sayısını görmeye devam etmeli.
      expect(find.text(l10n.tokenBalanceLabel), findsOneWidget);
    });

    testWidgets('aboneye paket GÖSTERİLİR', (tester) async {
      final l10n = _tr();
      await _ciz(tester,
          jetonKapsami(durum: const SubscriptionStatus(active: true)));

      expect(find.text(l10n.tokenBuy), findsOneWidget);
      expect(find.text(l10n.tokenPacksPlusOnlyTitle), findsNothing);
    });

    testWidgets('denemedeki kullanıcı ABONE sayılır — paket onun için anlamlı',
        (tester) async {
      final l10n = _tr();
      // `/billing/status` gövdesindeki `active`, sunucudaki `is_subscriber`
      // ile birebir aynı ve deneme onu `true` yapıyor
      // (core/entitlements.py). Denemedeki kullanıcıya `get_wallet`
      // `allowance: 0` veriyor ve raporlar `wallet.spender` ile doğrudan
      // cüzdandan harcıyor, yani o YALNIZ `purchased`tan harcar: paketi
      // ondan saklamak, ürünü gerçekten kullanabilecek kişiden saklamak
      // olurdu.
      await _ciz(
          tester,
          jetonKapsami(
              durum: const SubscriptionStatus(
                  active: true, isTrial: true, trialDaysLeft: 2)));

      expect(find.text(l10n.tokenBuy), findsOneWidget);
    });

    testWidgets('abonelik BİLİNMİYORKEN iskelet var, karar YOK',
        (tester) async {
      final l10n = _tr();
      await _ciz(tester, jetonKapsami(durum: null));

      // Yükleniyorken paketleri gizlemek de göstermek de yanlış olurdu:
      // biri aboneden ürünü saklar, öteki abone olmayana karşılığı olmayan
      // bir bakiye satar (`paywallKarariVerilebilir` tam bunun için var).
      expect(find.byType(SkeletonPanel), findsWidgets);
      expect(find.text(l10n.tokenBuy), findsNothing);
      expect(find.text(l10n.tokenPacksPlusOnlyTitle), findsNothing,
          reason: 'bilmediğin şeyi söylemek, susmaktan kötü');
    });

    testWidgets('abonelik OKUNAMADIYSA iskelet değil tazeleme yolu',
        (tester) async {
      // Sonsuza kadar yüklenen bir ekran kullanıcıya uygulamanın bozuk
      // olduğunu söyler; `subscriptionProvider` auto-dispose DEĞİL, yani
      // ekranı kapatıp açmak bayat sonucu kurtarmaz.
      await _ciz(
          tester, jetonKapsami(durum: SubscriptionStatus.bilinmiyor));

      expect(find.byType(ErrorCard), findsOneWidget);
      expect(tester.widget<ErrorCard>(find.byType(ErrorCard)).onRetry,
          isNotNull);
    });

    testWidgets('satın alma uçarken geri tuşu kapalı', (tester) async {
      final l10n = _tr();
      final asilmisMagaza = Completer<bool>();
      addTearDown(() => asilmisMagaza.complete(true));

      await _ciz(
          tester,
          jetonKapsami(
              durum: const SubscriptionStatus(active: true),
              satinAlici: (_, _) => asilmisMagaza.future));

      expect(_geriTusuGecer(tester, TokenStoreScreen), isTrue);
      expect(_kapatmaDugmesi(tester).onPressed, isNotNull);

      await tester.tap(find.text(l10n.tokenBuy));
      await tester.pump();

      expect(_geriTusuGecer(tester, TokenStoreScreen), isFalse,
          reason: 'bu ekranda AppBar hiç özelleştirilmemişti');
      expect(_kapatmaDugmesi(tester).onPressed, isNull);
      expect(_dugmeBasilabilir(tester, l10n.tokenBuy), isFalse);
    });

    testWidgets('sunucu yüklemediyse "yüklendi" DENMEZ', (tester) async {
      final l10n = _tr();
      await _ciz(
          tester,
          jetonKapsami(
              durum: const SubscriptionStatus(active: true),
              // `false` = bütçe doldu, bakiye sunucuda henüz görünmüyor.
              satinAlici: (_, _) async => false));

      await tester.tap(find.text(l10n.tokenBuy));
      await tester.pump();
      await tester.pump();

      expect(find.text(l10n.purchasePendingServer), findsOneWidget,
          reason: 'ölçülmeyen söylenmez: bakiye henüz yüklenmedi');
      expect(find.text(l10n.tokenPurchaseDone), findsNothing);
    });
  });

  group('sunucuyuYokla: TOPLAM bütçe', () {
    test('bütçe dolunca durur — jeton tarafında bu kapı YOKTU', () async {
      // Ölçülen kusur: jeton beklemesi yalnız gecikme merdivenini
      // kopyalamıştı, 15 saniyelik üst sınırı değil. Beş tur × 6 sn yoklama
      // sınırı + 10,4 sn gecikme ≈ 40 sn, ve kullanıcı o süreyi ödeme
      // ekranında tek bir dönen halkaya bakarak geçiriyordu.
      var tur = 0;
      final sonuc = await sunucuyuYokla(
        tazele: () => tur++,
        // Hiç yakalamayan sunucu: bütçe tek fren.
        yakalandi: () async => false,
        butce: const Duration(milliseconds: 300),
        yoklamaSiniri: const Duration(milliseconds: 50),
      );

      expect(sonuc, isFalse, reason: 'yakalanmadı → dürüst "false"');
      // Merdiven beş adım + bir kapanış tazelemesi, yani bütçesiz hâlde
      // `tazele` ALTI kez çağrılır. Bütçe ilk gecikmede (400 ms) kesiyor.
      //
      // Tam sayı yerine üst sınır ölçülüyor: ilk tur ÖNCESİNDE de bütçe
      // kontrol ediliyor, yani yavaş bir makinede o tek tur da düşebilir.
      // Ölçülen şey "bütçe freni var mı", "kaç tur koştu" değil.
      expect(tur, lessThanOrEqualTo(2),
          reason: 'bütçesiz hâlde altı tazeleme koşuyordu (~40 sn)');
      expect(tur, greaterThanOrEqualTo(1), reason: 'kapanış tazelemesi şart');
    });

    test('sunucu yakalarsa erken çıkar ve true döner', () async {
      var tur = 0;
      final sonuc = await sunucuyuYokla(
        tazele: () => tur++,
        yakalandi: () async => true,
      );

      expect(sonuc, isTrue);
      expect(tur, 1, reason: 'yakalandıysa merdivenin kalanı koşmaz');
    });

    test('düşen yoklama satın alma hatası DEĞİL — bekleme sürer', () async {
      var deneme = 0;
      final sonuc = await sunucuyuYokla(
        tazele: () {},
        yakalandi: () async {
          deneme++;
          if (deneme < 3) throw StateError('ağ');
          return true;
        },
      );

      expect(sonuc, isTrue);
      expect(deneme, 3);
    });
  });

  group('kaynak bekçisi: jeton tarafı ORTAK kapıdan geçiyor', () {
    // Neden kaynaktan: `purchaseTokenPack`ın kendisi hiçbir testte
    // KOŞAMIYOR — `ensureBillingIdentity` → `FirebaseAuth.instance` ve
    // `Purchases.purchase` `flutter test` içinde çağırılamaz, ekran testi de
    // `jetonSatinAliciProvider` dikisinden geçip onu atlıyor. Yani turun
    // dördüncü kusuru (15 sn bütçe kapısı jeton tarafına HİÇ
    // taşınmamıştı, en kötü hâl ~40 sn) bekçisiz duruyordu: ortak işlevi
    // geri çıkarsan bütün takım YEŞİL kalıyor.
    //
    // ⚠️ Yorumlar EŞLEŞMEDEN ÖNCE atılıyor: dosyanın kendi açıklaması
    // `sunucuyuYokla`dan ikinci kez söz ediyor (kütüphane başlığında ve
    // işlevin dartdoc'unda), yani ham arama onarım sökülse bile EŞLEŞİRDİ
    // — depoda iki kez yanan tuzak bu (bkz. CLAUDE.md §5).
    test('purchaseTokenPack bütçeli ortak işlevi ÇAĞIRIYOR', () {
      final kaynak = File('lib/core/wallet.dart').readAsStringSync();
      final yorumsuz = kaynak
          .split('\n')
          .where((satir) {
            final k = satir.trimLeft();
            return !k.startsWith('//') && !k.startsWith('///');
          })
          .join('\n');
      final govde =
          yorumsuz.substring(yorumsuz.indexOf('Future<bool> purchaseTokenPack'));

      expect(govde, contains('sunucuyuYokla('),
          reason: 'jeton beklemesi abonelikle AYNI bütçe kapısından geçmeli; '
              'kendi merdivenini kurarsa 15 sn üst sınırı kaybolur');
    });

    /// Yorumsuz kaynaktan tek bir üst düzey işlevin gövdesi.
    ///
    /// Yorumlar EŞLEŞMEDEN ÖNCE atılıyor (depoda iki kez yanan tuzak): aranan
    /// adlar bu dosyanın kendi açıklamalarında da geçiyor, ham arama onarım
    /// sökülse bile EŞLEŞİRDİ. Gövde ilk sütundaki `}` ile kesiliyor; iç
    /// bloklar girintili olduğu için yalnız işlevin kapanışına denk gelir.
    String islevGovdesi(String yol, String imza) {
      final yorumsuz = File(yol)
          .readAsStringSync()
          .split('\n')
          .where((satir) {
            final k = satir.trimLeft();
            return !k.startsWith('//') && !k.startsWith('///');
          })
          .join('\n');
      final bas = yorumsuz.indexOf(imza);
      expect(bas, greaterThanOrEqualTo(0), reason: '$imza bulunamadı: $yol');
      final son = yorumsuz.indexOf('\n}', bas);
      expect(son, greaterThan(bas), reason: '$imza gövdesi kapanmıyor');
      return yorumsuz.substring(bas, son);
    }

    // ⚠️ BEKÇİ BOŞLUĞU: yukarıdaki davranış bekçileri temeli
    // `yetkiTemeliniKurulmusSay()`ı DOĞRUDAN çağırarak kuruyor, çünkü
    // `purchasePackage`/`restorePurchases` hiçbir testte koşamıyor
    // (`FirebaseAuth.instance` ve `Purchases.purchase` `flutter test` içinde
    // çağrılamaz). Yani çağrıyı üretim yolundan silsen bütün takım YEŞİL
    // kalır ve B1'in deliği geri açılır — tam olarak bu turda bir kez yaşanan
    // "yeşil kalan bekçi" durumu.
    for (final imza in const [
      'Future<SatinAlmaSonucu> purchasePackage',
      'Future<bool> restorePurchases',
    ]) {
      test('$imza temeli KURUYOR', () {
        expect(islevGovdesi('lib/core/subscription.dart', imza),
            contains('yetkiTemeliniKurulmusSay()'),
            reason: 'yetki kazandıran yol temeli kurmazsa, süreçteki ilk '
                'bildirim satın almanın kendisi olur ve YUTULUR');
      });
    }
  });

  group('kalıcı toplayıcı (P1-2)', () {
    /// Dinleyiciyi kuran dikiş: testin elinde `CustomerInfo` üretmenin yolu
    /// yok, kararın ihtiyacı olan bilgi ise yalnız aktif yetki kümesi.
    ///
    /// [yanki] verilirse dikiş, dinleyiciyi kaydedilir kaydedilmez SENKRON
    /// çağırır — paketin gerçekte yaptığı şey (purchases_flutter 9.16.1,
    /// `addCustomerInfoUpdateListener`: `_lastReceivedCustomerInfo` doluysa
    /// dinleyiciyi inline çağırıyor; gövde bu turda yeniden okundu).
    /// Verilmezse "önbellekte `CustomerInfo` YOK" hâli taklit edilir — turun
    /// kapattığı delik tam olarak orada yaşıyordu.
    ({ProviderContainer kapsam, void Function(Set<String>) bildir}) kurulum(
        {List<Set<String>> yanki = const []}) {
      void Function(Set<String>)? dinleyici;
      final kapsam = ProviderContainer(retry: (_, _) => null, overrides: [
        yetkiDinleyiciKurucuProvider.overrideWithValue((d) {
          dinleyici = d;
          for (final kume in yanki) {
            d(kume);
          }
        }),
      ]);
      kapsam.read(yetkiToplayiciProvider);
      expect(dinleyici, isNotNull, reason: 'toplayıcı kurulmadı');
      return (kapsam: kapsam, bildir: dinleyici!);
    }

    /// Sayaç yazımları artık build'in DIŞINDA (mikrotaskta) koşuyor; okumadan
    /// önce kuyruğun boşalması gerekiyor. Gerekçenin tamamı
    /// `yetkiToplayiciProvider` gövdesinde.
    Future<void> kuyrukBosalsin() => Future<void>.delayed(Duration.zero);

    test('kayıt anındaki SENKRON yankı temel alınır, sayacı artırmaz',
        () async {
      final (kapsam: kapsam, bildir: _) =
          kurulum(yanki: [{kPlusEntitlement}]);
      addTearDown(kapsam.dispose);
      await kuyrukBosalsin();

      // Yankıyı değişiklik saymak her açılışta gereksiz bir
      // /billing/status + /billing/wallet turu, abonede ayrıca iki adımlık
      // merdiven üretirdi.
      expect(kapsam.read(yetkiDegisimProvider), 0);
    });

    test('yetki KAZANILINCA sayaç artar — ekran ömründen bağımsız', () async {
      final (kapsam: kapsam, bildir: bildir) = kurulum();
      addTearDown(kapsam.dispose);

      bildir(const <String>{}); // temel: abone değil
      bildir({kPlusEntitlement}); // mağaza satın almayı bildirdi
      await kuyrukBosalsin();

      // Bu, paketin en pahalı kusurunun bekçisi: ekran sökülmüşken satın
      // almanın sonucunu toplayan HİÇBİR ŞEY yoktu ve
      // `subscriptionProvider` auto-dispose olmadığı için bayat "abone
      // değil" oturum boyunca kalıyordu.
      expect(kapsam.read(yetkiDegisimProvider), greaterThan(0));
      // Aylık jeton hakkını aynı webhook yazıyor; cüzdan da tazelenmeli.
      expect(kapsam.read(cuzdanTazelemeProvider), greaterThan(0));
    });

    test('aynı yetki tekrar bildirilirse sayaç ARTMAZ', () async {
      final (kapsam: kapsam, bildir: bildir) = kurulum();
      addTearDown(kapsam.dispose);

      bildir(const <String>{});
      bildir({kPlusEntitlement});
      await kuyrukBosalsin();
      final sonra = kapsam.read(yetkiDegisimProvider);
      bildir({kPlusEntitlement});
      await kuyrukBosalsin();

      expect(kapsam.read(yetkiDegisimProvider), sonra,
          reason: 'SDK aynı bilgiyi yineleyebilir; her yineleme istek üretmemeli');
    });

    test('yetki KAYBINDA da sayaç artar — abonelik bitişi sessiz kalmaz',
        () async {
      final (kapsam: kapsam, bildir: bildir) = kurulum();
      addTearDown(kapsam.dispose);

      bildir({kPlusEntitlement});
      bildir(const <String>{});
      await kuyrukBosalsin();

      expect(kapsam.read(yetkiDegisimProvider), greaterThan(0));
    });

    test('sayaç BAYRAK değil: ikinci değişim de tazeler', () async {
      final (kapsam: kapsam, bildir: bildir) = kurulum();
      addTearDown(kapsam.dispose);

      bildir(const <String>{});
      bildir({kPlusEntitlement});
      await kuyrukBosalsin();
      final birinci = kapsam.read(yetkiDegisimProvider);
      bildir(const <String>{});
      await kuyrukBosalsin();

      // `bool` olsaydı ikinci olayda `true`→`true` olurdu, Riverpod
      // "değişmedi" sayardı ve durum bir daha hiç tazelenmezdi
      // (`cuzdanTazelemeProvider` ile birebir aynı gerekçe).
      expect(kapsam.read(yetkiDegisimProvider), greaterThan(birinci));
    });

    test('SENKRON yankı AÇILIŞI DÜŞÜRMEZ — yazım build dışında', () async {
      // ⚠️ Bu bekçi B1'in AĞIR yarısı ve iddia yeniden ölçüldü (Riverpod
      // 3.3.2): bir sağlayıcının build'i içinde `StateProvider`a yazmak
      // `ProviderException: Tried to use a provider that is in error state`
      // fırlatıyor ve hata o sağlayıcıda KALMIYOR — `ref.watch` eden
      // sağlayıcı da fırlıyor. Üretimdeki zincir
      // `yetkiToplayiciProvider` → `billingIdentityProvider` →
      // `main.dart`'taki kapı, yani bedeli AÇILIŞIN KENDİSİ olurdu.
      //
      // Yankı İKİ kez geliyor: ilki temel, İKİNCİSİ değişim — yani yazım
      // kayıt sırasında, build'in TAM İÇİNDE tetikleniyor. Eskiden bunu
      // önleyen tek şey "ilk bildirimi yut" kuralıydı; yani bir istek
      // tasarrufu açılışın ayakta kalmasını taşıyordu.
      final izleyen = Provider<int>((ref) {
        ref.watch(yetkiToplayiciProvider);
        return 1;
      });
      void Function(Set<String>)? dinleyici;
      final kapsam = ProviderContainer(retry: (_, _) => null, overrides: [
        yetkiDinleyiciKurucuProvider.overrideWithValue((d) {
          dinleyici = d;
          d(const <String>{});
          d({kPlusEntitlement});
        }),
      ]);
      addTearDown(kapsam.dispose);

      expect(() => kapsam.read(izleyen), returnsNormally,
          reason: 'build içinde sayaç yazımı açılışı düşürüyordu');
      expect(dinleyici, isNotNull);
      await kuyrukBosalsin();

      // Yazım yutulmuyor, yalnız ERTELENİYOR: değişim yine sayılmalı.
      expect(kapsam.read(yetkiDegisimProvider), greaterThan(0));
    });

    test('satın alma BAŞLARKEN temel kurulur — ilk olay artık yutulmuyor',
        () async {
      // B1'in deliği: süreçte hiç `CustomerInfoUpdated` olmamışsa (dikişte
      // yankı YOK, yani SDK önbelleği boş) satın almanın ürettiği olay İLK
      // olay olur ve temel sayılıp yutulurdu — sayaç artmaz, merdiven
      // kurulmaz. Toplayıcı tam da var olma sebebinde susuyordu.
      final (kapsam: kapsam, bildir: bildir) = kurulum();
      addTearDown(kapsam.dispose);

      yetkiTemeliniKurulmusSay();
      bildir({kPlusEntitlement});
      await kuyrukBosalsin();

      expect(kapsam.read(yetkiDegisimProvider), greaterThan(0),
          reason: 'satın almanın ürettiği olay YUTULUYOR');
      expect(kapsam.read(cuzdanTazelemeProvider), greaterThan(0));
    });

    test('eski kapsamın sökülmesi YAŞAYAN kancayı koparmaz', () async {
      // Kanca modül düzeyinde (gerekçesi `yetkiTemeliniKurulmusSay`'da) ve
      // kapanış KİMLİĞİYLE geri alınıyor. Körlemesine `null` atansaydı
      // ÖLEN kapsam, ayakta duran toplayıcının kancasını söker ve o toplayıcı
      // sessizce eski (delikli) hâline dönerdi — testlerde art arda kapsam
      // kurulduğu için bu sessizce olurdu.
      final (kapsam: eski, bildir: _) = kurulum();
      final (kapsam: yeni, bildir: bildir) = kurulum();
      addTearDown(yeni.dispose);
      eski.dispose();

      yetkiTemeliniKurulmusSay();
      bildir({kPlusEntitlement});
      await kuyrukBosalsin();

      expect(yeni.read(yetkiDegisimProvider), greaterThan(0));
    });

    /// Merdiveni SAHTE SAAT altında kuran yardımcı.
    ///
    /// `testWidgets` seçildi çünkü merdiven zamana bağlı: `Future.delayed`
    /// `tester.pump(süre)` ile sahte saatten besleniyor (ölçüldü) ve bekleyen
    /// zamanlayıcı kalırsa test DÜŞÜYOR — yani "merdiven kendini topluyor mu"
    /// sorusu bedavaya soruluyor.
    ///
    /// Yankı YOK ve temel elle kuruluyor: ölçülmek istenen şey merdivenin
    /// ÖMRÜ, temel kuralı değil (onun kendi bekçileri yukarıda).
    Future<({ProviderContainer kapsam, void Function(Set<String>) bildir})>
        merdivenKur(WidgetTester tester) async {
      await tester.pumpWidget(const SizedBox.shrink());
      void Function(Set<String>)? dinleyici;
      final kapsam = ProviderContainer(retry: (_, _) => null, overrides: [
        yetkiDinleyiciKurucuProvider.overrideWithValue((d) => dinleyici = d),
      ]);
      kapsam.read(yetkiToplayiciProvider);
      dinleyici!(const <String>{}); // temel: abone değil
      await tester.pump();
      return (kapsam: kapsam, bildir: dinleyici!);
    }

    testWidgets('ekran yokluyorken merdiven ÖLMEZ, adımını ERTELER',
        (tester) async {
      // B2: `purchaseWaitingLong` metni "bu ekranı kapatsan da satın alman
      // kaybolmaz" diye söz veriyor. Eski hâlde `_ekranBekliyor` BİLDİRİM
      // ANINDA sorulup çıkılıyordu, yani merdiven HİÇ kurulmuyordu ve geriye
      // tek bir anlık bump kalıyordu. Ekran kapanınca kendi yoklaması da
      // ölüyor (sökülmüş `WidgetRef` → `ref.invalidate` fırlatıyor; ölçüldü),
      // yani söz TUTULMUYORDU.
      final (kapsam: kapsam, bildir: bildir) = await merdivenKur(tester);
      addTearDown(kapsam.dispose);

      // Ekranın yoklama penceresi AÇIK ve kapanmıyor: kullanıcı ekranda.
      final ekran = Completer<bool>();
      unawaited(ekranYoklarken(() => ekran.future));

      bildir({kPlusEntitlement});
      await tester.pump();
      final anlik = kapsam.read(yetkiDegisimProvider);
      expect(anlik, 1, reason: 'bildirim anındaki tek bump');

      // Merdivenin iki adımı +1 ve +5. saniyede. Ekran hâlâ yokluyor:
      // adımlar HARCANMAMALI.
      await tester.pump(const Duration(seconds: 6));
      expect(kapsam.read(yetkiDegisimProvider), anlik,
          reason: 'ekran yoklarken istek sayısı İKİYE KATLANMAMALI');

      // Kullanıcı 10. saniyede ekranı kapattı: ekranın yoklaması öldü.
      // "Adımı atla" yetmezdi — iki adım da çoktan tükenmiş olurdu.
      await tester.pump(const Duration(seconds: 4));
      ekran.complete(false);
      await tester.pump(const Duration(seconds: 2));

      expect(kapsam.read(yetkiDegisimProvider), greaterThan(anlik),
          reason: 'ekran öldükten sonra geriye kalan TEK mekanizma merdiven');

      // Kalan adım da boşalsın; bekleyen zamanlayıcı testi düşürür.
      await tester.pump(const Duration(seconds: 6));
      expect(kapsam.read(yetkiDegisimProvider), 3,
          reason: 'üç tazeleme: merdiven BÜYÜMEDİ');
      expect(kapsam.read(cuzdanTazelemeProvider), 3);
    });

    testWidgets('ekran hiç boşalmazsa merdiven VAZGEÇER — tavan var',
        (tester) async {
      // Tavansız bir bekleyiş oturum boyunca zamanlayıcı döndürürdü. Tavan
      // ekranın kendi sınırlarından türetiliyor (bütçe + tek yoklamanın üst
      // sınırı); dolduğu hâlde ekran hâlâ yokluyorsa işi O yapıyor.
      final (kapsam: kapsam, bildir: bildir) = await merdivenKur(tester);
      addTearDown(kapsam.dispose);

      final ekran = Completer<bool>();
      unawaited(ekranYoklarken(() => ekran.future));

      bildir({kPlusEntitlement});
      await tester.pump();
      // Ekranın en uzun hâli 15 sn bütçe + 6 sn yoklama sınırı; tavan onun
      // üstünde. Bol pump: bekleyen zamanlayıcı kalırsa test düşer.
      await tester.pump(const Duration(seconds: 40));

      expect(kapsam.read(yetkiDegisimProvider), 1,
          reason: 'ekran işi yapıyorken merdiven ikinci kez yoklamamalı');

      ekran.complete(false);
      await tester.pump();
    });

    testWidgets('sunucu YAKALADIYSA merdiven durur — istek sayısı artmıyor',
        (tester) async {
      // Bu erken çıkış onarımın ZORUNLU parçası: adım artık ekranı atlamak
      // yerine beklediği için, ekranın başarıyla bitirdiği her satın almada
      // merdiven uyanıp iki tazeleme daha koşturacaktı. `aboneAynasiProvider`
      // sunucunun SON `/billing/status` gövdesinden yazılıyor (`api.dart`,
      // `_yanitiNotEt`) ve hiçbir şeyi izlemiyor — B10'un halkası
      // `subscriptionProvider`a uzanmaktan geliyordu, oraya uzanmak gerekmedi.
      final (kapsam: kapsam, bildir: bildir) = await merdivenKur(tester);
      addTearDown(kapsam.dispose);

      bildir({kPlusEntitlement});
      await tester.pump();
      // Sunucu yakaladı: ekranın yoklaması `/billing/status`ı okudu ve
      // interceptor aynayı yazdı.
      kapsam.read(aboneAynasiProvider.notifier).state = true;

      await tester.pump(const Duration(seconds: 10));

      expect(kapsam.read(yetkiDegisimProvider), 1,
          reason: 'sunucu gördüyse beklenecek bir şey yok');
    });

    testWidgets('ayna HENÜZ bilmiyorsa merdiven koşar', (tester) async {
      // `null` = durum bu oturumda hiç okunamadı; "abone değil" ile aynı şey
      // DEĞİL. Erken çıkış `== true` soruyor, "doğru değil mi" sormuyor —
      // yoksa bilmediğini bilmeyen bir karar merdiveni öldürürdü.
      final (kapsam: kapsam, bildir: bildir) = await merdivenKur(tester);
      addTearDown(kapsam.dispose);

      expect(kapsam.read(aboneAynasiProvider), isNull);
      bildir({kPlusEntitlement});
      await tester.pump(const Duration(seconds: 7));

      expect(kapsam.read(yetkiDegisimProvider), 3);
    });

    test('GERÇEK subscriptionProvider sayacı İZLİYOR', () async {
      // Zincirin en kritik halkası: sayaç izlenmiyorsa toplayıcının yazdığı
      // her şey hiçbir yere ulaşmaz ve kusur onarılmamış olur. Bu yüzden
      // `subscriptionProvider` BURADA override EDİLMİYOR — gerçek gövdesi
      // koşuyor. Oturum null verilince gövde `none` döndürüp çıkıyor, yani
      // Dio'ya ve Firebase'e hiç dokunulmuyor (sahte `User` gerekmedi).
      final kapsam = ProviderContainer(retry: (_, _) => null, overrides: [
        authStateProvider.overrideWith((_) => Stream.value(null)),
      ]);
      addTearDown(kapsam.dispose);

      await kapsam.read(subscriptionProvider.future);

      var olay = 0;
      kapsam.listen(subscriptionProvider, (_, _) => olay++);
      kapsam.read(yetkiDegisimProvider.notifier).state++;
      await kapsam.read(subscriptionProvider.future);

      expect(olay, greaterThan(0),
          reason: 'sayaç izlenmiyorsa durum bir daha hiç yeniden okunmaz');
    });
  });
}
