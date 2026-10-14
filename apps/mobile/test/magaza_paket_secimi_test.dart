// Jeton mağazası: paket seçilir, TEK dolu düğme fiyatı söyler, adet
// SUNUCUDAN, kredi başına fiyat satırda.
//
// Kapatılan kusurlar: üç paket üç dolu "Satın al" düğmesi taşıyordu; adet
// yalnız istemcideki `kPackDisplayAmounts` tablosundan okunuyordu (sunucu
// `packs` gönderiyor, okuyucusu yoktu); paketleri karşılaştıracak ölçü
// (kredi başına fiyat) ekranda yoktu.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:rytho/core/subscription.dart';
import 'package:rytho/core/wallet.dart';
import 'package:rytho/features/paywall/token_store_screen.dart';
import 'package:rytho/l10n/app_localizations.dart';
import 'package:rytho/theme/rytho_theme.dart';
import 'package:rytho/widgets/atlas_widgets.dart' show GoldButton;

AppLocalizations _tr() => lookupAppLocalizations(const Locale('tr'));

const _kucuk = StoreProduct(
    'rytho_tokens_small', 'k', 'Küçük', 99.99, '₺99,99', 'TRY');
const _orta = StoreProduct(
    'rytho_tokens_medium', 'o', 'Orta', 249.99, '₺249,99', 'TRY');

/// Sunucu `packs` gönderiyor ve istemci tablosundan FARKLI: 50 yerine 75.
const _cuzdan = WalletStatus(
    allowance: 10,
    purchased: 0,
    monthlyAllowance: 100,
    packs: {'rytho_tokens_small': 75});

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

/// `cuzdan: null` = bakiye HİÇ gelmez (yükleniyor).
Future<void> _ciz(WidgetTester tester, {WalletStatus? cuzdan = _cuzdan}) async {
  tester.view.physicalSize = const Size(1200, 12000);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(
    retry: (_, _) => null,
    overrides: [
      walletProvider.overrideWith((_) => cuzdan == null
          ? Completer<WalletStatus>().future
          : Future.value(cuzdan)),
      tokenPacksProvider.overrideWith((_) async => [_kucuk, _orta]),
      subscriptionProvider
          .overrideWith((_) async => const SubscriptionStatus(active: true)),
    ],
    child: _uygulama(const TokenStoreScreen()),
  ));
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
}

void main() {
  group('saf', () {
    test('paketAdedi: sunucu > yedek tablo > null', () {
      expect(paketAdedi(_cuzdan, 'rytho_tokens_small'), 75);
      expect(paketAdedi(_cuzdan, 'rytho_tokens_medium'),
          kPackDisplayAmounts['rytho_tokens_medium']);
      expect(paketAdedi(_cuzdan, 'bilinmeyen'), isNull);
    });

    test('krediBasinaFiyat: fiyat / adet, mağazanın para birimiyle', () {
      final s = krediBasinaFiyat(_kucuk, 100, 'tr');
      expect(s, isNotNull);
      expect(s, contains('1,00'), reason: '99,99 / 100 ≈ 1,00');
    });

    test('krediBasinaFiyat: adet ya da para birimi yoksa satır yok', () {
      expect(krediBasinaFiyat(_kucuk, null, 'tr'), isNull);
      expect(krediBasinaFiyat(_kucuk, 0, 'tr'), isNull);
      expect(
          krediBasinaFiyat(
              const StoreProduct('x', 'x', 'x', 10, '10', ''), 100, 'tr'),
          isNull);
    });
  });

  group('ekran', () {
    testWidgets('TEK dolu düğme, fiyatı taşır; küçük paket önseçili',
        (tester) async {
      final l10n = _tr();
      await _ciz(tester);

      final dolu = tester
          .widgetList<GoldButton>(find.byType(GoldButton))
          .where((b) => b.filled);
      expect(dolu.length, 1);
      expect(dolu.first.text, l10n.storeBuyWithPrice(_kucuk.priceString));
      expect(find.text('Satın al'), findsNothing,
          reason: 'üç ayrı "Satın al" gitti');
    });

    testWidgets('adet SUNUCUDAN: 50 değil 75; kredi başına fiyat var',
        (tester) async {
      final l10n = _tr();
      await _ciz(tester);

      expect(find.text(l10n.tokenPackAmount(75)), findsOneWidget);
      expect(find.text(l10n.tokenPackAmount(50)), findsNothing,
          reason: 'istemci tablosu yalnız yedek');
      expect(find.text(l10n.tokenPackAmount(100)), findsOneWidget,
          reason: 'sunucu göndermeyeni yedek tablo tamamlar');
      expect(find.textContaining('/ kredi'), findsNWidgets(2));
    });

    testWidgets('ikinci paket seçilince düğme onun fiyatını söyler',
        (tester) async {
      final l10n = _tr();
      await _ciz(tester);

      await tester.tap(find.text(l10n.tokenPackAmount(100)));
      await tester.pump();

      expect(find.text(l10n.storeBuyWithPrice(_orta.priceString)),
          findsOneWidget);
      expect(find.text(l10n.storeBuyWithPrice(_kucuk.priceString)),
          findsNothing);
    });

    testWidgets('bakiye GELMEDEN "—", "0" yok (sıfır "bitti" demek)',
        (tester) async {
      await _ciz(tester, cuzdan: null);
      expect(find.text('0'), findsNothing);
      expect(find.text('—'), findsWidgets);
    });

    testWidgets('bakiye okunamadı → "—", döküm "0" değil', (tester) async {
      await _ciz(tester, cuzdan: WalletStatus.unknown);
      expect(find.text('0'), findsNothing);
      expect(find.text('—'), findsWidgets);
    });
  });
}
