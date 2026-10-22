// Abonelik ekranı: üç hâl, tek dolu düğme, paket düğmesi yalnız aboneye.
//
// Kapatılan kusurlar: durum `?? SubscriptionStatus.none` okunuyordu —
// yüklenirken ve okuma düştüğünde ABONEYE "Ücretsiz" plan kartı + "Rytho+'a
// geç" düğmesi; bakiye `?? WalletStatus.none` ile "0" (sıfır = "bitti");
// ücretsiz kullanıcıya "Kredi paketi al" (K2: paket aboneye satılır, düğme
// onu "aboneye özel" panelinden geri döndürüyordu); ekranda iki dolu düğme.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rytho/core/subscription.dart';
import 'package:rytho/core/wallet.dart';
import 'package:rytho/features/profile/subscription_screen.dart';
import 'package:rytho/l10n/app_localizations.dart';
import 'package:rytho/theme/rytho_theme.dart';
import 'package:rytho/widgets/atlas_widgets.dart' show GoldButton;
import 'package:rytho/widgets/common.dart' show ErrorCard;
import 'package:rytho/widgets/glass.dart' show SkeletonList;

import 'dart:io';

AppLocalizations _tr() => lookupAppLocalizations(const Locale('tr'));

String _yorumsuz(String yol) => File(yol)
    .readAsStringSync()
    .replaceAll('\r\n', '\n')
    .split('\n')
    .where((s) => !s.trimLeft().startsWith('//'))
    .join('\n');

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

/// `durum: null` = okuma HİÇ tamamlanmaz (yükleniyor);
/// `cuzdan: null` = bakiye hiç gelmez.
Future<void> _ciz(WidgetTester tester,
    {required SubscriptionStatus? durum, WalletStatus? cuzdan = WalletStatus.none}) async {
  tester.view.physicalSize = const Size(1200, 12000);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(
    retry: (_, _) => null,
    overrides: [
      subscriptionProvider.overrideWith((_) => durum == null
          ? Completer<SubscriptionStatus>().future
          : Future.value(durum)),
      walletProvider.overrideWith((_) => cuzdan == null
          ? Completer<WalletStatus>().future
          : Future.value(cuzdan)),
    ],
    child: _uygulama(const SubscriptionScreen()),
  ));
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
}

int _doluDugme(WidgetTester tester) => tester
    .widgetList<GoldButton>(find.byType(GoldButton))
    .where((b) => b.filled)
    .length;

void main() {
  testWidgets('yükleniyor → iskelet; "Ücretsiz" DENMEZ', (tester) async {
    final l10n = _tr();
    await _ciz(tester, durum: null);

    expect(find.byType(SkeletonList), findsOneWidget);
    expect(find.text(l10n.subPlanFree), findsNothing,
        reason: 'eski hâl aboneye yüklenirken "Ücretsiz" diyordu');
    expect(find.text(l10n.subGoPlus), findsNothing);
  });

  testWidgets('okunamadı → ErrorCard + tazeleme; "Ücretsiz" DENMEZ',
      (tester) async {
    final l10n = _tr();
    await _ciz(tester, durum: SubscriptionStatus.bilinmiyor);

    expect(find.byType(ErrorCard), findsOneWidget);
    expect(tester.widget<ErrorCard>(find.byType(ErrorCard)).onRetry,
        isNotNull);
    expect(find.text(l10n.subPlanFree), findsNothing);
  });

  testWidgets('ücretsiz: "Rytho+\'a geç" TEK dolu düğme, paket düğmesi YOK',
      (tester) async {
    final l10n = _tr();
    await _ciz(tester, durum: SubscriptionStatus.none);

    expect(find.text(l10n.subPlanFree), findsOneWidget);
    expect(find.text(l10n.subGoPlus), findsOneWidget);
    expect(find.text(l10n.subBuyTokens), findsNothing,
        reason: 'K2: paket aboneye satılır');
    expect(_doluDugme(tester), 1);
  });

  testWidgets('mağaza abonesi: "Kredi paketi al" dolu, "Yönet" ikincil',
      (tester) async {
    final l10n = _tr();
    await _ciz(tester,
        durum: const SubscriptionStatus(
            active: true, productId: 'rytho_plus_monthly'));

    expect(find.text(l10n.subBuyTokens), findsOneWidget);
    expect(find.text(l10n.subManage), findsOneWidget);
    expect(find.text(l10n.subGoPlus), findsNothing);
    expect(_doluDugme(tester), 1);
    final yonet = tester.widget<GoldButton>(
        find.widgetWithText(GoldButton, l10n.subManage));
    expect(yonet.filled, isFalse);
  });

  testWidgets('deneme: "Rytho+\'a geç" dolu, paket düğmesi var ama ikincil',
      (tester) async {
    final l10n = _tr();
    await _ciz(tester,
        durum: const SubscriptionStatus(active: true, trialDaysLeft: 2));

    expect(find.text(l10n.subGoPlus), findsOneWidget);
    expect(find.text(l10n.subBuyTokens), findsOneWidget,
        reason: 'denemedeki kullanıcı YALNIZ satın alınan bakiyeden harcar');
    expect(_doluDugme(tester), 1);
  });

  testWidgets('bakiye gelmeden "—", "0" YOK', (tester) async {
    await _ciz(tester, durum: SubscriptionStatus.none, cuzdan: null);

    expect(find.text('—'), findsWidgets);
    expect(find.text('0'), findsNothing,
        reason: 'sıfır "bitti" demek; yüklenirken söylenmez');
  });

  testWidgets('bakiye okunamadı → döküm de "—" (toplam ile tutarlı)',
      (tester) async {
    await _ciz(tester,
        durum: const SubscriptionStatus(
            active: true, productId: 'rytho_plus_monthly'),
        cuzdan: WalletStatus.unknown);

    expect(find.text('0'), findsNothing);
    expect(find.text('— / —'), findsOneWidget);
  });

  group('Kaynak bekçisi', () {
    test('"Yönet" launchUrl sonucunu okur ve düşerse kullanıcıya söyler', () {
      final k = _yorumsuz('lib/features/profile/subscription_screen.dart');
      // Açıcı U47'den beri bir test dikişinden geçiyor (aboneliğin alındığı
      // mağazanın adresi ölçülebilsin diye); üretimde `_varsayilanAcici` =
      // `launchUrl`. Bekçinin sabitlediği şey değişmedi: sonuç OKUNUR.
      expect(k, contains('acildi = await (widget.adresAcici ?? _varsayilanAcici)('));
      expect(k, contains('l10n.subManageOpenFailed'));
    });

    test('paywall yalnız acPaywall ile, kaynak etiketi abonelikEkrani', () {
      final k = _yorumsuz('lib/features/profile/subscription_screen.dart');
      expect(k, contains('kaynak: PaywallKaynak.abonelikEkrani'));
      expect(k, isNot(contains('PaywallScreen(')));
    });

    test('geri yükleme hatası tek kapıdan (purchaseErrorText)', () {
      final k = _yorumsuz('lib/features/profile/subscription_screen.dart');
      expect(k, contains('purchaseErrorText(e, l10n, abonelik: true)'));
      expect(k, isNot(contains('friendlyError(')));
    });
  });
}
