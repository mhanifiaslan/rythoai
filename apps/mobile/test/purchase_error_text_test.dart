// Satın alma hatası TEK kapıdan: `purchaseErrorText(e, l10n, abonelik:)`.
//
// Kapatılan kusurlar: "zaten satın alınmış" kodu tüketilebilir pakette de
// abonelik cümlesini ("…zaten etkin bir abonelik var") söylüyordu — oysa
// Play consumable'ı tüketilmeden ikinci kez satmaz, o hâl "ilk alımın
// yolda" demektir; metin "Google hesabı" diyordu (iOS'ta yanlış); abonelik
// ekranının geri yüklemesi `friendlyError`dan geçip mağazanın ağ hatasına
// "beklenmeyen sorun" diyordu.
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:rytho/core/purchase_errors.dart';
import 'package:rytho/core/subscription.dart';
import 'package:rytho/core/wallet.dart';
import 'package:rytho/features/paywall/token_store_screen.dart';
import 'package:rytho/l10n/app_localizations.dart';
import 'package:rytho/theme/rytho_theme.dart';

AppLocalizations _tr() => lookupAppLocalizations(const Locale('tr'));

/// RevenueCat kodu `PlatformException.code`ta enum SIRASI olarak taşınır
/// (`PurchasesErrorHelper.getErrorCode`); sıra elle yazılmaz, enum'dan okunur.
PlatformException _hata(PurchasesErrorCode kod) =>
    PlatformException(code: '${PurchasesErrorCode.values.indexOf(kod)}');

const _urun = StoreProduct(
    'rytho_tokens_small', '100 kredi', '100 kredi', 99.99, '₺99,99', 'TRY');

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

void main() {
  setUp(magazaHataKaydiniSifirla);

  group('purchaseErrorText (saf)', () {
    test('zaten satın alınmış: abonelikte geri yükleme cümlesi', () {
      final l10n = _tr();
      expect(
          purchaseErrorText(
              _hata(PurchasesErrorCode.productAlreadyPurchasedError), l10n,
              abonelik: true),
          l10n.purchaseAlreadyOwnedSubscription);
    });

    test('zaten satın alınmış: pakette "işleniyor" — abonelik cümlesi DEĞİL',
        () {
      final l10n = _tr();
      final metin = purchaseErrorText(
          _hata(PurchasesErrorCode.productAlreadyPurchasedError), l10n,
          abonelik: false);
      expect(metin, l10n.purchasePackRefreshing);
      expect(metin, isNot(contains('abonelik')));
    });

    test('"Google" kelimesi hiçbir cümlede yok (iOS\'ta yanlıştı)', () {
      final l10n = _tr();
      expect(l10n.purchaseAlreadyOwnedSubscription, isNot(contains('Google')));
      expect(l10n.purchasePackRefreshing, isNot(contains('Google')));
    });

    test('mağaza ağ hatası → bağlantı cümlesi (iki sınıfta da)', () {
      final l10n = _tr();
      for (final abonelik in [true, false]) {
        expect(
            purchaseErrorText(_hata(PurchasesErrorCode.networkError), l10n,
                abonelik: abonelik),
            l10n.authNetwork);
      }
    });

    test('mağaza dışı hata friendlyError\'dan: Dio bağlantı → errorConnection',
        () {
      final l10n = _tr();
      final e = DioException(
          requestOptions: RequestOptions(path: '/x'),
          type: DioExceptionType.connectionError);
      expect(purchaseErrorText(e, l10n, abonelik: true), l10n.errorConnection);
    });

    test('bilinmeyen mağaza kodu → genel cümle + kayıt', () {
      final l10n = _tr();
      final kayitlar = <String>[];
      magazaHatasiKaydedici = kayitlar.add;
      expect(
          purchaseErrorText(PlatformException(code: '9998'), l10n,
              abonelik: false),
          l10n.purchaseFailed);
      expect(kayitlar, hasLength(1));
    });

    test('ürün sunulmuyor cümlesi test kanalı dili taşımaz', () {
      final l10n = _tr();
      expect(l10n.purchaseItemUnavailable, isNot(contains('test')));
      expect(l10n.purchaseItemUnavailable, isNot(contains('kanal')));
    });
  });

  group('jeton mağazası (widget)', () {
    testWidgets('pakette "zaten satın alınmış" → bakiye yeniden sorulur, '
        '"işleniyor" denir', (tester) async {
      final l10n = _tr();
      var cuzdanOkuma = 0;
      tester.view.physicalSize = const Size(1200, 12000);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(ProviderScope(
        retry: (_, _) => null,
        overrides: [
          walletProvider.overrideWith((_) async {
            cuzdanOkuma++;
            return WalletStatus.none;
          }),
          tokenPacksProvider.overrideWith((_) async => [_urun]),
          subscriptionProvider.overrideWith(
              (_) async => const SubscriptionStatus(active: true)),
          jetonSatinAliciProvider.overrideWithValue((_, _) async =>
              throw _hata(PurchasesErrorCode.productAlreadyPurchasedError)),
        ],
        child: _uygulama(const TokenStoreScreen()),
      ));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      final onceki = cuzdanOkuma;

      await tester.tap(find.text(l10n.storeBuyWithPrice(_urun.priceString)));
      await tester.pump();
      await tester.pump();

      expect(find.text(l10n.purchasePackRefreshing), findsOneWidget);
      expect(find.text(l10n.purchaseAlreadyOwnedSubscription), findsNothing,
          reason: 'paket alımında abonelik cümlesi yanlış teşhis');
      expect(cuzdanOkuma, greaterThan(onceki),
          reason: 'ilk alım yoldaysa bakiye yeniden sorulur');
    });
  });
}
