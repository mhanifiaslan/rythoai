// Dar ekran + büyük yazı ölçeği taşma bekçileri — PROFİL turu (D5).
//
// Ölçüt `dar_ekran_test.dart` ile aynı: 320 dp × 1,3 (`kMaxTextScale`)
// altında hiçbir şey taşmamalı; Flutter taşmayı çizim anında fırlatır.
//
// `dar_ekran_ekranlar_test.darEkrandaEkran` BURADA KULLANILAMADI: o harness
// sağlayıcı override'ı almıyor ve bu ekranların hepsi sağlayıcı okuyor
// (profil akışı, abonelik, cüzdan, OS izni, API). İç içe `ProviderScope`
// ile override, bağımlılık beyanı olmayan sağlayıcılarda güvenilir değil;
// geometri aynen kopyalandı, ölçüt (`kDarGenislik`, `tasmaYok`) ortak
// dosyadan alınıyor ki iki dosya ayrı düşmesin.
//
// ⚠️ Test yazı tipi her harfi punto kadar geniş kare çizer; bekçi bilinçli
// TUTUCU — burada sığan cihazda da sığar, piksel konumu iddia edilmez.
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:firebase_messaging/firebase_messaging.dart'
    show AuthorizationStatus;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rytho/core/api.dart' show apiProvider;
import 'package:rytho/core/notifications.dart' show osBildirimDurumuProvider;
import 'package:rytho/core/providers.dart';
import 'package:rytho/core/subscription.dart';
import 'package:rytho/core/wallet.dart';
import 'package:rytho/features/profile/birth_record_screen.dart';
import 'package:rytho/features/profile/delete_account.dart';
import 'package:rytho/features/profile/diary_screen.dart';
import 'package:rytho/features/profile/feedback_screen.dart';
import 'package:rytho/features/profile/profile_screen.dart';
import 'package:rytho/features/profile/profile_sections.dart'
    show NotificationSettingsScreen;
import 'package:rytho/l10n/app_localizations.dart';
import 'package:rytho/l10n/app_localizations_tr.dart';
import 'package:rytho/main.dart' show kMaxTextScale;
import 'package:rytho/theme/rytho_theme.dart';

import 'dar_ekran_test.dart' show kDarGenislik, tasmaYok;

final _tr = AppLocalizationsTr();

class _SahteAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(RequestOptions options,
          Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async =>
      ResponseBody.fromString(
          '{"status":"ok","data":{"entries":[{"id":"d1","date":"2026-10-09",'
          '"theme":"relationships","text":"Uzun bir cümle yazdım, dar ekranda '
          'satır sarmalı ve taşmamalı."}]}}',
          200,
          headers: {
            Headers.contentTypeHeader: [Headers.jsonContentType],
          });

  @override
  void close({bool force = false}) {}
}

/// Gerçek uzunlukta değerler: kısa örnek metin kusuru görünmez kılar.
const _profil = <String, dynamic>{
  'displayName': 'Zeynep Aslanoğulları',
  'username': 'zeynepaslanogullari',
  'birthDate': '1988-03-07',
  'birthTime': '04:30',
  'birthCity': 'Gaziosmanpaşa',
  'birthNation': 'TR',
  'gender': 'female',
  'residenceCity': 'Hochschwarzwald',
  'sunSign': 'Balık ♓',
  'moonSign': 'Aslan ♌',
  'ascendant': 'Kova ♒',
  'streakCount': 12,
  'quietFrom': 22,
  'quietTo': 8,
};

Future<void> _darEkranda(WidgetTester tester, Widget home) async {
  final dio = Dio(BaseOptions(baseUrl: 'https://test.invalid'))
    ..httpClientAdapter = _SahteAdapter();
  // Yükseklik gerçekçi: kısa tutmak ölçmek istemediğimiz DİKEY taşmaları
  // uydurur (dar_ekran_ekranlar_test ile aynı gerekçe).
  tester.view.physicalSize = const Size(kDarGenislik * 3, 800 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      apiProvider.overrideWithValue(dio),
      profileProvider.overrideWith((ref) => Stream.value(_profil)),
      subscriptionProvider.overrideWith(
          (ref) async => const SubscriptionStatus(active: true)),
      walletProvider.overrideWith((ref) async => const WalletStatus(
          allowance: 287, purchased: 1000, monthlyAllowance: 300)),
      // Band GÖRÜNÜR hâlde ölçülür: en uzun hâl bu.
      osBildirimDurumuProvider
          .overrideWith((ref) async => AuthorizationStatus.denied),
    ],
    child: MaterialApp(
      locale: const Locale('tr'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: buildRythoTheme(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: const TextScaler.linear(kMaxTextScale),
          disableAnimations: true,
        ),
        child: child!,
      ),
      home: home,
    ),
  ));
  await tester.pump();
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 600));
}

/// Listeyi sonuna kadar kaydırır ve HER adımda taşmayı ölçer: `ListView`
/// çocuklarını tembel kurar, 800 dp'lik pencerede alttaki satırlar hiç
/// çizilmez ve orada taşan bir şey görünmezdi (ölçüldü: profilin çıkış
/// satırı ilk karede ağaçta yoktu).
Future<void> _sonunaKadar(WidgetTester tester, {required String neden}) async {
  for (var i = 0; i < 6; i++) {
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -500));
    await tester.pump();
    tasmaYok(tester, neden: neden);
  }
}

void main() {
  testWidgets('Profil taşmaz', (tester) async {
    await _darEkranda(tester, ProfileScreen(kullanici: () => null));
    tasmaYok(tester, neden: 'profil 320 dp × 1,3 ölçekte taşıyor');
    expect(find.text('7 Mart 1988'), findsOneWidget);
    await _sonunaKadar(tester, neden: 'profilin alt grupları taşıyor');
    expect(find.text(_tr.signOut), findsOneWidget);
    expect(find.text(_tr.about), findsOneWidget);
  });

  testWidgets('Doğum kaydı taşmaz', (tester) async {
    await _darEkranda(tester, const BirthRecordScreen());
    tasmaYok(tester, neden: 'doğum kaydı formu taşıyor');
    await _sonunaKadar(tester, neden: 'doğum kaydı formunun altı taşıyor');
    expect(find.text(_tr.save), findsOneWidget);
    expect(find.text(_tr.birthTime), findsOneWidget);
    expect(find.text('04:30'), findsOneWidget);
  });

  testWidgets('Bildirim ayarları (band açık) taşmaz', (tester) async {
    await _darEkranda(tester, const NotificationSettingsScreen());
    tasmaYok(tester, neden: 'bildirim ayarları taşıyor');
    await _sonunaKadar(tester, neden: 'bildirim ayarlarının altı taşıyor');
    expect(find.text(_tr.notifPermissionOffTitle), findsOneWidget);
    expect(find.text(_tr.quietHoursRange('22', '08')), findsOneWidget);
  });

  testWidgets('Geri bildirim taşmaz', (tester) async {
    await _darEkranda(tester, const FeedbackScreen(screen: 'circle'));
    tasmaYok(tester, neden: 'geri bildirim formu taşıyor');
    await _sonunaKadar(tester, neden: 'geri bildirim formunun altı taşıyor');
    expect(find.text(_tr.feedbackSend), findsOneWidget);
    expect(find.text(_tr.tabFriends), findsOneWidget);
  });

  testWidgets('Hesap silme taşmaz', (tester) async {
    await _darEkranda(
        tester,
        Scaffold(
          body: SingleChildScrollView(
              child: DeleteAccountSheet(cikis: () async {})),
        ));
    tasmaYok(tester, neden: 'hesap silme sayfası taşıyor');
    await _sonunaKadar(tester, neden: 'hesap silme sayfasının altı taşıyor');
    expect(find.text(_tr.deleteAccountAction), findsOneWidget);
  });

  testWidgets('Günlük taşmaz', (tester) async {
    await _darEkranda(tester, const DiaryScreen());
    tasmaYok(tester, neden: 'günlük taşıyor');
    expect(find.textContaining(_tr.diaryThemeRelationships), findsOneWidget);
    expect(find.text(_tr.diarySave), findsOneWidget);
  });
}
