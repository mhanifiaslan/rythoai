// Bakiye hapının üç hâli: iskelet / "—" / sayı — ve "0" ASLA yüklenirken.
//
// B10 dersi: okunamayan bakiye sıfır DEĞİL. Eski hap `value ?? none` ile
// yüklenme anında "0" basıyordu; sıfır "jetonun bitti" demek ve 198
// jetonlu kullanıcı o anda mağazaya yönleniyordu. Bu dosya ayrıca düşük
// bakiye rengini `WalletStatus.dusuk`a bağlar (elle 30 eşiği yok) ve
// hedefin TEK olduğunu (mağaza) rotadan doğrular.
//
// `TokenStoreScreen` ÇİZDİRİLMEZ (mağaza sağlayıcıları ister): rotanın
// kurucusu elle çağrılıp dönen widget okunuyor — `yeni_konusma_fab_test`.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rytho/core/wallet.dart';
import 'package:rytho/features/paywall/token_store_screen.dart';
import 'package:rytho/l10n/app_localizations.dart';
import 'package:rytho/theme/rytho_theme.dart';
import 'package:rytho/widgets/fade_through_route.dart';
import 'package:rytho/widgets/glass.dart' show SkeletonPanel;
import 'package:rytho/widgets/token_chip.dart';

class _RotaGozcusu extends NavigatorObserver {
  final itilenler = <Route<dynamic>>[];

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    itilenler.add(route);
  }
}

Widget _sar(Widget govde,
        {required Future<WalletStatus> cuzdan, NavigatorObserver? gozcu}) =>
    ProviderScope(
      overrides: [walletProvider.overrideWith((_) => cuzdan)],
      child: MaterialApp(
        locale: const Locale('tr'),
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        theme: buildRythoTheme(),
        navigatorObservers: gozcu != null ? [gozcu] : const [],
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: true),
          child: child!,
        ),
        home: Scaffold(body: Center(child: govde)),
      ),
    );

Future<void> _bekle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

Color? _renk(WidgetTester tester, String metin) =>
    tester.widget<Text>(find.text(metin)).style?.color;

void main() {
  testWidgets('yükleniyor → iskelet hap, "0" YOK, ikon YOK', (tester) async {
    await tester.pumpWidget(_sar(const TokenChip(),
        cuzdan: Completer<WalletStatus>().future));
    await _bekle(tester);

    expect(find.byType(SkeletonPanel), findsOneWidget);
    expect(find.textContaining('0'), findsNothing,
        reason: 'yüklenirken sıfır "jetonun bitti" demektir');
    expect(find.byType(Text), findsNothing);
    expect(find.byIcon(Icons.toll_rounded), findsNothing);
  });

  testWidgets('bilinmiyor → "—", düşük bakiye rengi YOK', (tester) async {
    await tester.pumpWidget(
        _sar(const TokenChip(), cuzdan: Future.value(WalletStatus.unknown)));
    await _bekle(tester);

    expect(find.text('—'), findsOneWidget);
    expect(find.byType(SkeletonPanel), findsNothing);
    expect(_renk(tester, '—'), isNot(RythoColors.copper),
        reason: 'total 0 diye bakır yanarsa dolu cüzdan "bitmek üzere" okunur');
  });

  testWidgets('okundu → "{n} kredi", altın', (tester) async {
    await tester.pumpWidget(_sar(const TokenChip(),
        cuzdan: Future.value(const WalletStatus(
            allowance: 50, purchased: 0, monthlyAllowance: 100))));
    await _bekle(tester);

    expect(find.text('50 kredi'), findsOneWidget);
    expect(_renk(tester, '50 kredi'), RythoColors.goldBright);
    expect(find.byIcon(Icons.toll_rounded), findsOneWidget);
    expect(find.text('🪙'), findsNothing,
        reason: 'aynı emoji İ Ching ve finans anlamında da kullanılıyor');
  });

  testWidgets('düşük (hakkın %10\'u) → bakır', (tester) async {
    await tester.pumpWidget(_sar(const TokenChip(),
        cuzdan: Future.value(const WalletStatus(
            allowance: 5, purchased: 5, monthlyAllowance: 100))));
    await _bekle(tester);

    expect(_renk(tester, '10 kredi'), RythoColors.copper);
  });

  testWidgets('compact → yalnız sayı', (tester) async {
    await tester.pumpWidget(_sar(const TokenChip(compact: true),
        cuzdan: Future.value(const WalletStatus(
            allowance: 50, purchased: 0, monthlyAllowance: 100))));
    await _bekle(tester);

    expect(find.text('50'), findsOneWidget);
    expect(find.text('50 kredi'), findsNothing);
  });

  testWidgets('erişilebilirlik: tek düğme, etiketi bakiye', (tester) async {
    final semantik = tester.ensureSemantics();
    await tester.pumpWidget(_sar(const TokenChip(),
        cuzdan: Future.value(const WalletStatus(
            allowance: 50, purchased: 0, monthlyAllowance: 100))));
    await _bekle(tester);

    expect(find.bySemanticsLabel('50 kredi'), findsOneWidget);
    semantik.dispose();
  });

  testWidgets('dokunuş → mağaza (tek hedef)', (tester) async {
    final gozcu = _RotaGozcusu();
    await tester.pumpWidget(_sar(const TokenChip(),
        cuzdan: Future.value(const WalletStatus(
            allowance: 50, purchased: 0, monthlyAllowance: 100)),
        gozcu: gozcu));
    await _bekle(tester);

    await tester.tap(find.byType(TokenChip));

    expect(gozcu.itilenler.length, 2, reason: 'ana rota + itilen rota');
    final rota = gozcu.itilenler.last;
    expect(rota, isA<FadeThroughRoute<dynamic>>());
    final sayfa = (rota as PageRouteBuilder).pageBuilder(
        tester.element(find.byType(TokenChip)),
        kAlwaysCompleteAnimation,
        kAlwaysDismissedAnimation);
    expect(sayfa, isA<TokenStoreScreen>(),
        reason: 'abonelik ekranı profilden; bakiyeyi görenin işi doldurmak');

    await tester.pumpWidget(const SizedBox.shrink());
  });
}
