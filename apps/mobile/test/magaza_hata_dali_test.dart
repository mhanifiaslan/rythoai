// Mağaza/ağ hatasının "mağazada ürün tanımlı değil" diye görünmesini
// engelleyen bekçiler (para-2).
//
// Eskiden hem paywall (`offeringsProvider`) hem Kredi Mağazası
// (`tokenPacksProvider`) sağlayıcısı hatayı yutup BOŞ LİSTE dönüyordu. İki
// sonucu vardı: (1) sağlayıcılar auto-dispose DEĞİL (Riverpod 3 varsayılanı) —
// boş liste oturum boyunca önbellekte kalıyor, ekranı kapatıp açmak
// kurtarmıyordu; (2) paywall'ın `error:` dalı ÖLÜ KOD'du ve ekran ağ sorununu
// "Mağazada tanımlı paket bulunamadı" diye mağazaya yıkıyordu.
//
// Sağlayıcı gövdesi test içinde `Purchases`e ulaşamaz ve dart-define olmadığı
// için `billingConfigured` false; bu yüzden gövdeye bir GETİRİCİ DİKİŞİ
// konuldu. Dikişsiz hâlde "try/catch geri geldi" hiçbir yerde ölçülemiyordu.
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
import 'package:rytho/l10n/app_localizations.dart';
import 'package:rytho/theme/rytho_theme.dart';
import 'package:rytho/widgets/common.dart' show ErrorCard;

/// ARB'deki metin üretilen sınıftan okunur: metin değişince test kırılmaz,
/// anahtar silinirse derleme kırılır (device_conflict_screen_test deseni).
AppLocalizations _tr() => lookupAppLocalizations(const Locale('tr'));

/// Türkçe, animasyonsuz kabuk.
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

/// Ekranı çizer.
///
/// Yükseklik BOL: test yazı tipi her harfi punto kadar geniş kare çizdiği için
/// içerik gerçek cihazdan uzun, `ListView` ise tembel — görünme alanına hiç
/// girmeyen çocuk AĞAÇTA OLMAZ ve finder onu bulamaz.
Future<void> _ciz(WidgetTester tester, Widget kapsam) async {
  tester.view.physicalSize = const Size(1200, 9000);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(kapsam);
  // `pumpAndSettle` YASAK: yıldız alanı sonsuz döner (bkz.
  // widgets/cosmic_scaffold.dart StarfieldBackground).
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
}

/// Hata kartının yeniden deneme yolu SÖZLEŞMEYE bağlı kontrol edilir; etiket
/// metni ErrorCard gövdesinde sabit, yani `find.text` davranış değişmeden
/// kırılırdı.
void _tekrarYoluVar(WidgetTester tester) {
  expect(tester.widget<ErrorCard>(find.byType(ErrorCard)).onRetry, isNotNull,
      reason: 'önbellekte kalan hatanın tek çıkışı elle tazeleme');
}

void main() {
  group('sağlayıcı hatayı YUTMUYOR', () {
    test('offeringsProvider mağaza hatasını FIRLATIR', () async {
      // Yutulursa `const []` döner ve ekran "paket yok" der: aşağıdaki
      // `throwsA` düşer. Bu, para-2'nin asıl ürün değişikliğinin bekçisi.
      final kapsam = ProviderContainer(retry: (_, _) => null, overrides: [
        teklifGetiriciProvider.overrideWithValue(
            () => throw StateError('magazaya ulasilamadi')),
      ]);
      addTearDown(kapsam.dispose);

      await expectLater(kapsam.read(offeringsProvider.future),
          throwsA(isA<StateError>()));
      expect(kapsam.read(offeringsProvider).hasError, isTrue);
    });

    test('tokenPacksProvider mağaza hatasını FIRLATIR', () async {
      final kapsam = ProviderContainer(retry: (_, _) => null, overrides: [
        urunGetiriciProvider.overrideWithValue(
            (_) => throw PlatformException(code: '10', message: 'network')),
      ]);
      addTearDown(kapsam.dispose);

      await expectLater(kapsam.read(tokenPacksProvider.future),
          throwsA(isA<PlatformException>()));
      expect(kapsam.read(tokenPacksProvider).hasError, isTrue);
    });
  });

  group('paywall', () {
    testWidgets('mağaza hatası → çevrilmiş metin + tekrar dene',
        (tester) async {
      final l10n = _tr();
      await _ciz(
          tester,
          ProviderScope(
            // Hatalı sağlayıcı varsayılan politikayla yeniden denenir ve
            // testte bekleyen zamanlayıcı bırakır. Ölçülen şey hata DALI.
            retry: (_, _) => null,
            overrides: [
              subscriptionProvider
                  .overrideWith((_) async => SubscriptionStatus.none),
              offeringsProvider.overrideWith(
                  (_) async => throw StateError('magazaya ulasilamadi')),
            ],
            child: _uygulama(const PaywallScreen()),
          ));

      expect(find.byType(ErrorCard), findsOneWidget,
          reason: 'error: dalı ölü koddu');
      _tekrarYoluVar(tester);
      expect(find.text(l10n.errorGeneric), findsOneWidget,
          reason: 'ham hata metni değil, kullanıcının dilinde');
      expect(find.textContaining('magazaya ulasilamadi'), findsNothing,
          reason: 'eski hâli ekrana ham hata nesnesini basıyordu');
      // Yanlış teşhis: ağ sorununda mağazayı suçlayan metin.
      expect(find.text(l10n.billingNoPackages), findsNothing);
      expect(find.text(l10n.billingNotConfigured), findsNothing);
    });

    testWidgets('hatasız ama boş teklif → dürüst "yok" metni', (tester) async {
      final l10n = _tr();
      await _ciz(
          tester,
          ProviderScope(
            retry: (_, _) => null,
            overrides: [
              subscriptionProvider
                  .overrideWith((_) async => SubscriptionStatus.none),
              offeringsProvider.overrideWith((_) async => const <Package>[]),
            ],
            child: _uygulama(const PaywallScreen()),
          ));

      // Testte RevenueCat anahtarı yok, bu yüzden dürüst metin "bu derlemede
      // anahtar yok" olandır. Ölçülen şey: hata dalı DEĞİL, boş dal çiziliyor.
      expect(find.text(l10n.billingUnavailable), findsOneWidget);
      expect(find.text(l10n.billingNotConfigured), findsOneWidget);
      expect(find.byType(ErrorCard), findsNothing);
    });
  });

  testWidgets('kredi mağazası: hata dalı artık ERİŞİLEBİLİR', (tester) async {
    final l10n = _tr();
    await _ciz(
        tester,
        ProviderScope(
          retry: (_, _) => null,
          overrides: [
            // SURUM 47: durum ABONE'ye çevrildi. Paketler artık yalnız
            // aboneye gösteriliyor (karar K2), yani abone olmayan bir
            // kapsamda mağaza hata dalına HİÇ ulaşılmıyor ve bu test
            // ölçmek istediği şeyi değil görünürlük kapısını ölçerdi.
            // Ölçülen sözleşme değişmedi: mağaza hatası çevrilmiş metin +
            // yeniden deneme düğmesi üretiyor mu?
            subscriptionProvider.overrideWith(
                (_) async => const SubscriptionStatus(active: true)),
            walletProvider.overrideWith((_) async => WalletStatus.none),
            // Mağaza hatası PlatformException'dır; bu ekran eskiden
            // `friendlyError` kullanıyordu ve onu tanımadığı için ağ
            // sorununda "beklenmeyen sorun" diyordu.
            tokenPacksProvider.overrideWith((_) async =>
                throw PlatformException(code: '10', message: 'network')),
          ],
          child: _uygulama(const TokenStoreScreen()),
        ));

    expect(find.byType(ErrorCard), findsOneWidget,
        reason: 'boş liste dönerken bu dal hiç tetiklenmiyordu');
    _tekrarYoluVar(tester);
    expect(find.text(l10n.authNetwork), findsOneWidget,
        reason: 'çeviri paywall ile AYNI kapıdan geçmeli');
    expect(find.text(l10n.errorGeneric), findsNothing,
        reason: 'mağaza kodu "beklenmeyen sorun"a düşmez');
    expect(find.text(l10n.tokenPacksUnavailable), findsNothing,
        reason: 'yeniden deneme düğmesi OLMAYAN boşluk gösterilmez');
  });

  group('magazaVeyaAgHatasi', () {
    setUp(magazaHataKaydiniSifirla);
    tearDown(magazaHataKaydiniSifirla);

    test('mağaza kodu da ağ hatası da çevrilir — İKİ ekran AYNI kapı', () {
      final l10n = _tr();
      // Denetimin bulduğu asimetri: jeton mağazası `friendlyError`
      // kullanıyordu ve mağaza hatasında "beklenmeyen sorun" diyordu,
      // paywall doğru metni gösterirken.
      expect(magazaVeyaAgHatasi(StateError('x'), l10n), l10n.errorGeneric);
      expect(
          magazaVeyaAgHatasi(
              PlatformException(code: '10', message: 'network'), l10n),
          l10n.authNetwork);
    });

    test('ÇİZİM yolunda bilinmeyen kod KOD BAŞINA BİR KEZ kaydedilir', () {
      // Çeviri `build()` içinden çağrılıyor: hata kartı ekranda durduğu SÜRECE
      // her yeniden çizim yeni bir Crashlytics kaydı üretirdi.
      final kayitlar = <String>[];
      magazaHatasiKaydedici = kayitlar.add;
      final l10n = _tr();
      final hata = PlatformException(code: '9998', message: 'bilinmeyen');

      expect(magazaVeyaAgHatasi(hata, l10n), l10n.purchaseFailed);
      expect(magazaVeyaAgHatasi(hata, l10n), l10n.purchaseFailed);
      expect(magazaVeyaAgHatasi(hata, l10n), l10n.purchaseFailed);

      expect(kayitlar, hasLength(1),
          reason: 'her yeniden çizim yeni kayıt üretmemeli');
    });

    test('SATIN ALMA yolunda her deneme kaydedilir — yaygınlık ölçümü', () {
      // Süzgeç `storeErrorText`in içine konsaydı, ödeme sırasında aynı
      // bilinmeyen kodu beş kez yiyen kullanıcı 5 değil 1 kayıt üretirdi ve
      // "sorunun YAYGINLIĞINI gösteren telemetri" amacı bozulurdu. `_buy` ve
      // `_restore` bu fonksiyonu DOĞRUDAN çağırıyor.
      final kayitlar = <String>[];
      magazaHatasiKaydedici = kayitlar.add;
      final l10n = _tr();
      final hata = PlatformException(code: '9998', message: 'bilinmeyen');

      for (var i = 0; i < 3; i++) {
        expect(storeErrorText(hata, l10n), l10n.purchaseFailed);
      }

      expect(kayitlar, hasLength(3),
          reason: 'satın alma akışındaki tekrar sayısı bilginin kendisi');
    });

    test('bilinen kod hiç kaydedilmez', () {
      final kayitlar = <String>[];
      magazaHatasiKaydedici = kayitlar.add;
      magazaVeyaAgHatasi(
          PlatformException(code: '10', message: 'network'), _tr());
      expect(kayitlar, isEmpty);
    });
  });
}
