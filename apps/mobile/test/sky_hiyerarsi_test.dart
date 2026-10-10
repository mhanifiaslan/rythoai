// Ana ekranın OMURGA bekçileri (D5, plan §5 + K7).
//
// Ölçülen hâl: sayfada "bugün" ÜÇ kez başlık oluyordu (sinyallerin kendi
// `SectionHeader`ı, "Bugünün İçgörüsü", tarih); günlük düğmesi başlıkta
// ikon-tek bir degrade kareydi; sinyal ve takvim bölümleri `provider.value
// ?? []` okuyup HATAYI BOŞ GİBİ gösteriyordu (G1/G2) ve yükleme anında yer
// tutmuyordu; yedi `.animate(delay: next())` kopyası hareket azaltmayı
// okumuyordu; seri rozeti ile keşif halkası aynı kutlama sahnesini birebir
// kopya taşıyordu.
//
// Bekçiler iki sınıf: gerçek ağaç (SkyScreen sağlayıcı override'larıyla
// pump edilir) ve kaynak (yorumsuz metin). Kaynak bekçisi bir şeyin
// YOKLUĞUNU ararken kendi yorumuna takılmasın diye yorumlar atılır
// (depo kuralı; iki kez patladı).
//
// ⚠️ Test yazı tipi her harfi kare çizer; burada hiçbir piksel iddiası
// yok — yalnız SIRA (`getTopLeft().dy`) ve VARLIK.
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// `Override` flutter_riverpod 3'te misc.dart'tan geliyor.
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:rytho/core/providers.dart';
import 'package:rytho/core/subscription.dart'
    show SubscriptionStatus, subscriptionProvider;
import 'package:rytho/core/wallet.dart' show WalletStatus, walletProvider;
import 'package:rytho/features/paywall/plus_locked_card.dart';
import 'package:rytho/features/sky/sky_screen.dart';
import 'package:rytho/l10n/app_localizations.dart';
import 'package:rytho/l10n/app_localizations_tr.dart';
import 'package:rytho/theme/rytho_theme.dart';
import 'package:rytho/widgets/common.dart';
import 'package:rytho/widgets/glass.dart';
import 'package:rytho/widgets/liste_satiri.dart';
import 'package:rytho/widgets/reading_card.dart';
import 'package:shared_preferences/shared_preferences.dart';

final tr = AppLocalizationsTr();

String yorumsuz(String yol) => File(yol)
    .readAsStringSync()
    .replaceAll('\r\n', '\n')
    .split('\n')
    .where((s) => !s.trimLeft().startsWith('//'))
    .join('\n');

/// Onboarding'i bitmiş bir profil — seri bugün zaten sayılmış ki
/// `DailyStreak.touch` Firestore'a gitmesin (gitse de yutuluyor; ama
/// ölçülen şey ekran, ağ değil).
Map<String, dynamic> ornekProfil() => {
      'onboardingCompleted': true,
      'displayName': 'Deniz',
      'sunSign': 'leo',
      'streakCount': 3,
      'lastSeenDaily': DateTime.now().toIso8601String().substring(0, 10),
    };

Map<String, dynamic> ornekSinyal({int sira = 0}) => {
      'theme': 'career',
      'theme_local': 'Kariyer',
      'headline': 'Sinyal cümlesi $sira: işte görünürlük artıyor.',
      'timing_local': '15 Ekim günü netleşiyor',
      'exact_on': '2026-10-15',
      'exact_on_local': '15 Ekim',
    };

/// Ana ekranın sağlayıcı seti.
///
/// Hiçbir Firebase/RevenueCat çağrısı YOK: abonelik ve cüzdan sonsuz
/// yükleniyor (tanıtım paywall'ı kapısı "bilmiyorum" der ve açılmaz;
/// bakiye hapı iskelet çizer), profil tek yayınlık akış, günlük okuma
/// kilitli (`null`), takvim boş. [sinyaller] her tazelemede yeniden
/// koşar — "Tekrar dene" bekçisi ilk çağrıda fırlatıp ikincide veri verir.
List<Override> skyOverrides({
  required FutureOr<Map<String, dynamic>> Function() sinyaller,
  FutureOr<Map<String, dynamic>?> Function()? gunluk,
  FutureOr<Map<String, dynamic>?> Function()? takvim,
  PlusHali kapi = PlusHali.aboneDegil,
}) =>
    [
      profileProvider.overrideWith((ref) => Stream.value(ornekProfil())),
      raporKapisiProvider.overrideWithValue(kapi),
      dailyReadingProvider
          .overrideWith((ref) async => gunluk == null ? null : await gunluk()),
      signalsDataProvider.overrideWith((ref) async => await sinyaller()),
      transitCalendarProvider
          .overrideWith((ref) async => takvim == null ? null : await takvim()),
      subscriptionProvider
          .overrideWith((ref) => Completer<SubscriptionStatus>().future),
      walletProvider.overrideWith((ref) => Completer<WalletStatus>().future),
    ];

/// SkyScreen'i gerçek ağaç olarak çizer.
///
/// Animasyonlar KAPALI: `RythoReveal` çocuğu çıplak döndürür, iskelet
/// shimmer'ı kurulmaz; `getTopLeft` ölçümü kaymış ara karelere değil
/// nihai yerleşime bakar. Boy uzun tutuldu ki tembel `ListView` en alttaki
/// günlük satırını da kursun — kısa boyda satır hiç inşa edilmez ve
/// "yok" diye yanlış kırmızı olurdu.
Future<void> skyPump(
  WidgetTester tester, {
  required List<Override> overrides,
  double genislik = 400,
  double yukseklik = 1800,
  double olcek = 1,
}) async {
  SharedPreferences.setMockInitialValues({
    // Tanıtım paywall'ı ve bildirim izni bu ekranın kapsamı dışı; ikisi
    // de "zaten yapıldı" ki ağaç üstüne modal binmesin.
    'introPaywallShown': true,
    'notificationPermissionAsked': true,
  });
  tester.view.physicalSize = Size(genislik * 2, yukseklik * 2);
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(
    overrides: overrides,
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
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(olcek),
          disableAnimations: true,
        ),
        child: child!,
      ),
      home: const SkyScreen(),
    ),
  ));
  // Sağlayıcılar async; iki kare + kısa süre, `pumpAndSettle` DEĞİL
  // (usturlap döner, settle hiç bitmez).
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  group('omurga — gerçek ağaç', () {
    testWidgets('TEK bölüm başlığı var ve o "Bugün"; sinyal etiketi başlık '
        'DEĞİL', (tester) async {
      await skyPump(tester,
          overrides: skyOverrides(
              sinyaller: () => {'signals': [ornekSinyal()]}));

      final basliklar = find.byType(SectionHeader);
      expect(basliklar, findsOneWidget,
          reason: 'üç "bugün" bire indi; ikinci bir SectionHeader geri geldi');
      expect(tester.widget<SectionHeader>(basliklar).title, tr.todaysInsight);

      // Sinyal etiketi sayfada VAR ama bölüm başlığının içinde DEĞİL.
      expect(find.text(tr.signalsSection), findsOneWidget);
      expect(
          find.descendant(
              of: basliklar, matching: find.text(tr.signalsSection)),
          findsNothing,
          reason: 'sinyal etiketi alt etiket rolünde kalmalı');
    });

    testWidgets('günlük satırı okumanın ALTINDA; başlıkta günlük düğmesi YOK',
        (tester) async {
      await skyPump(tester,
          overrides: skyOverrides(sinyaller: () => {'signals': []}));

      final gunluk = find.widgetWithText(ListeSatiri, tr.diaryTitle);
      expect(gunluk, findsOneWidget, reason: 'K7: günlük satırı');
      expect(find.text(tr.diaryRowSubtitle), findsOneWidget);

      // Sıra EKRAN KOORDİNATINDAN: kilit kartı (okumanın yeri) üstte,
      // günlük satırı altında; bölüm başlığı ikisinin de üstünde.
      final yOkuma = tester.getTopLeft(find.byType(PlusLockedCard)).dy;
      final yGunluk = tester.getTopLeft(gunluk).dy;
      final yBaslik = tester.getTopLeft(find.byType(SectionHeader)).dy;
      expect(yBaslik, lessThan(yOkuma));
      expect(yOkuma, lessThan(yGunluk),
          reason: 'günlük düğmesi okumanın altına iner (K7)');

      // Başlık satırında (bölüm başlığının ÜSTÜNDE) günlük yok: ilk
      // günlük metni bölüm başlığından aşağıda.
      expect(yGunluk, greaterThan(yBaslik));
    });

    testWidgets('sinyal hatası → ErrorCard + Tekrar dene; tekrar dene '
        'KAYNAĞI yeniden ister', (tester) async {
      var cagri = 0;
      await skyPump(tester,
          overrides: skyOverrides(sinyaller: () {
            cagri++;
            if (cagri == 1) throw StateError('ağ düştü');
            return {'signals': [ornekSinyal()]};
          }));

      // G1: hata BOŞ gibi gizlenmez.
      expect(find.byType(ErrorCard), findsOneWidget,
          reason: 'sinyal hatası boş bölüm gibi gizleniyor (G1)');
      expect(find.textContaining('Sinyal cümlesi'), findsNothing);

      await tester.tap(find.text('Tekrar dene'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300));

      expect(cagri, 2, reason: 'tekrar dene signalsDataProvider\'ı koşturmalı');
      expect(find.byType(ErrorCard), findsNothing);
      expect(find.textContaining('Sinyal cümlesi'), findsOneWidget);
    });

    testWidgets('sinyaller yüklenirken İSKELET yer tutar', (tester) async {
      await skyPump(tester,
          overrides: skyOverrides(
              sinyaller: () => Completer<Map<String, dynamic>>().future));

      final bolum = find.byType(AsyncBolum<List<Map<String, dynamic>>>);
      expect(bolum, findsOneWidget);
      expect(
          find.descendant(of: bolum, matching: find.byType(SkeletonPanel)),
          findsOneWidget,
          reason: 'yükleme anında bölüm yer tutmalı, kaybolmamalı');
      expect(find.byType(ErrorCard), findsNothing);
    });

    testWidgets('keşif halkası "n/3" sayacı taşır — gökyüzü açıldı: 1/3',
        (tester) async {
      await skyPump(tester,
          overrides: skyOverrides(sinyaller: () => {'signals': []}));
      // `_touchStreak` günün ilk dilimini işaretler (prefs mock, async).
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('1/$kKesifDilimi'), findsOneWidget);
    });

    testWidgets('abone: okuma kartı çizilir, günlük satırı onun altında',
        (tester) async {
      await skyPump(tester,
          overrides: skyOverrides(
            sinyaller: () => {'signals': []},
            kapi: PlusHali.abone,
            gunluk: () => {
              'reading': 'Bugün sakin bir gün.',
              'sun_sign': 'Aslan',
              'moon_sign': 'Balık',
              'ascendant': 'Terazi',
            },
          ));
      expect(find.byType(ReadingCard), findsOneWidget);
      expect(find.byType(PlusLockedCard), findsNothing);
      final yOkuma = tester.getTopLeft(find.byType(ReadingCard)).dy;
      final yGunluk = tester
          .getTopLeft(find.widgetWithText(ListeSatiri, tr.diaryTitle))
          .dy;
      expect(yOkuma, lessThan(yGunluk));
    });
  });

  group('kaynak bekçisi — sky_screen.dart', () {
    final k = yorumsuz('lib/features/sky/sky_screen.dart');

    test('hata boş gibi gösterilmiyor: `.value ??` sinyal okuması yok', () {
      expect(k, isNot(contains('signalsProvider).value ??')),
          reason: 'G1 geri geldi: hata ile boş aynı yoldan geçer');
      expect(k, contains('AsyncBolum<List<Map<String, dynamic>>>('));
    });

    test('kademeli giriş tek yoldan: next() ve .animate(delay: yok, '
        'RythoReveal var', () {
      expect(k, isNot(contains('next()')));
      expect(k, isNot(contains('.animate(delay:')));
      expect('RythoReveal('.allMatches(k).length, greaterThanOrEqualTo(5));
    });

    test('kutlama tek tanım: Kutlama( ≥2, StarBurst( yalnız star_burst.dart',
        () {
      expect('Kutlama('.allMatches(k).length, greaterThanOrEqualTo(2),
          reason: 'seri rozeti ve keşif halkası ikisi de Kutlama ile');
      expect(k, isNot(contains('StarBurst(')),
          reason: 'patlama kopyası geri geldi; tek tanım star_burst.dart');
      expect(yorumsuz('lib/widgets/star_burst.dart'), contains('StarBurst('));
    });

    test('tek SectionHeader; başlık sınıfında günlük yok', () {
      expect('SectionHeader('.allMatches(k), hasLength(1));
      final bas = k.indexOf('class _Header');
      final son = k.indexOf('class _SignalsSection');
      expect(bas, greaterThan(0));
      expect(son, greaterThan(bas));
      expect(k.substring(bas, son), isNot(contains('DiaryScreen')),
          reason: 'K7: başlıktaki günlük düğmesi kalktı');
      expect(k, contains('subtitle: l10n.diaryRowSubtitle'));
    });

    test('paywall tek kapıdan: PaywallScreen( yok, acPaywall tanıtım', () {
      expect(k, isNot(contains('PaywallScreen(')));
      expect(k, contains('acPaywall(context, kaynak: PaywallKaynak.tanitim)'));
    });
  });
}
