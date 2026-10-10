// Profil ekranı bekçileri (D5 §6).
//
// Ölçülen kusurlar (2026-10-10): "Oturumu kapat" ekranın tek dolu CTA'sı,
// ONAYSIZ ve dock'un hemen üstündeydi; abonelik satırı yüklenirken aboneye
// "Ücretsiz" diyordu (`.value ?? none`); doğum tarihi ham ISO basılıyordu;
// grup başlıkları `toUpperCase()` ile bağırıyordu (Türkçe bilmez);
// "Hakkında" Rytho+ plakasının içindeydi.
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rytho/core/providers.dart';
import 'package:rytho/core/subscription.dart';
import 'package:rytho/core/wallet.dart';
import 'package:rytho/features/profile/profile_screen.dart';
import 'package:rytho/l10n/app_localizations.dart';
import 'package:rytho/l10n/app_localizations_tr.dart';
import 'package:rytho/theme/rytho_theme.dart';
import 'package:rytho/theme/rytho_tokens.dart';
import 'package:rytho/widgets/atlas_widgets.dart' show GoldButton;
import 'package:rytho/widgets/common.dart' show SettingsRow;

final _tr = AppLocalizationsTr();

/// Kaynak bekçisi bir şeyin YOKLUĞUNU ararken kendi açıklama yorumuna
/// takılmasın: tam satır yorumları atılır.
String _yorumsuz(String yol) => File(yol)
    .readAsStringSync()
    .replaceAll('\r\n', '\n')
    .split('\n')
    .where((s) => !s.trimLeft().startsWith('//'))
    .join('\n');

const _profil = <String, dynamic>{
  'displayName': 'Zeynep',
  'birthDate': '1988-03-07',
  'streakCount': 3,
};

/// Ekranı pompalar. Sağlayıcılar burada; `Override` türü flutter_riverpod
/// 3'te dışa aktarılmadığı için liste parametre olarak alınamıyor.
/// Yükseklik uzun: çıkış satırı listenin sonunda, kısa pencerede
/// dokunulamazdı.
Future<void> _ekran(
  WidgetTester tester, {
  Future<SubscriptionStatus>? abonelik,
  Future<WalletStatus>? cuzdan,
}) async {
  tester.view.physicalSize = const Size(390 * 3, 2000 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      profileProvider.overrideWith((ref) => Stream.value(_profil)),
      subscriptionProvider.overrideWith(
          (ref) => abonelik ?? Future.value(SubscriptionStatus.none)),
      walletProvider
          .overrideWith((ref) => cuzdan ?? Future.value(WalletStatus.none)),
    ],
    child: MaterialApp(
      locale: const Locale('tr'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: buildRythoTheme(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: true),
        child: child!,
      ),
      // `kullanici`: Firebase başlatılmadan ekran — oturum yok, ad profilden.
      home: ProfileScreen(kullanici: () => null),
    ),
  ));
  await tester.pump();
  await tester.pump(RythoMotion.base);
}

void main() {
  group('Oturumu kapat', () {
    testWidgets('GoldButton YOK, Hesap plakasında SettingsRow VAR',
        (tester) async {
      await _ekran(tester);

      expect(find.widgetWithText(GoldButton, _tr.signOut), findsNothing,
          reason: 'dock üstündeki onaysız dolu CTA geri gelmiş');
      expect(find.widgetWithText(SettingsRow, _tr.signOut), findsOneWidget);
      expect(find.byType(GoldButton), findsNothing,
          reason: 'profilde dolu CTA yok; her satır kendi sayfasını açar');
    });

    testWidgets('dokununca onay diyaloğu: gövde signOutConfirmBody; '
        'vazgeç → diyalog kapanır', (tester) async {
      await _ekran(tester);

      await tester.tap(find.widgetWithText(SettingsRow, _tr.signOut));
      await tester.pump();
      await tester.pump(RythoMotion.base);

      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.text(_tr.signOutConfirmBody), findsOneWidget,
          reason: 'çıkışın bedeli (bildirimler durur) söylenmeli');
      // Başlık + onay düğmesi, ikisi de `signOut`; satırın kendisi de.
      expect(find.text(_tr.signOut), findsNWidgets(3));

      await tester.tap(find.widgetWithText(TextButton, _tr.cancel));
      await tester.pump();
      await tester.pump(RythoMotion.base);
      expect(find.byType(AlertDialog), findsNothing);
    });
  });

  group('abonelikOzetiMetni — okunmamış plana ad verilmez', () {
    const plus = SubscriptionStatus(active: true);
    const w = WalletStatus(allowance: 12, purchased: 0, monthlyAllowance: 100);

    test('yükleniyor → "—" (eski hâl "Ücretsiz" diyordu)', () {
      expect(
          abonelikOzetiMetni(const AsyncValue.loading(),
              const AsyncValue.loading(), _tr),
          '— · —');
    });

    test('hata → "—"', () {
      expect(
          abonelikOzetiMetni(AsyncValue.error('x', StackTrace.empty),
              AsyncValue.error('x', StackTrace.empty), _tr),
          '— · —');
    });

    test('sunucudan okunamadı (okunabildi=false) → "—"', () {
      expect(
          abonelikOzetiMetni(const AsyncValue.data(SubscriptionStatus.bilinmiyor),
              const AsyncValue.data(WalletStatus.unknown), _tr),
          '— · —');
    });

    test('abone → kPlusAdi · kredi; ücretsiz → subPlanFree', () {
      expect(
          abonelikOzetiMetni(
              const AsyncValue.data(plus), const AsyncValue.data(w), _tr),
          '$kPlusAdi · ${_tr.tokenBalanceChip(12)}');
      expect(
          abonelikOzetiMetni(const AsyncValue.data(SubscriptionStatus.none),
              const AsyncValue.data(w), _tr),
          '${_tr.subPlanFree} · ${_tr.tokenBalanceChip(12)}');
    });

    testWidgets('ekranda: abonelik gelmemişken satır "—" yazar, "Ücretsiz" '
        'YAZMAZ', (tester) async {
      await _ekran(tester,
          abonelik: Completer<SubscriptionStatus>().future,
          cuzdan: Completer<WalletStatus>().future);

      expect(find.text('— · —'), findsOneWidget);
      expect(find.textContaining(_tr.subPlanFree), findsNothing,
          reason: 'yüklenirken aboneye "Ücretsiz" denmez');
    });
  });

  group('dördüncü grup markanın kendisi', () {
    testWidgets('başlık kMarka; abonelik, geri bildirim ve hakkında altında; '
        'başlıklar bağırmaz', (tester) async {
      await _ekran(tester);

      expect(find.text(kMarka), findsOneWidget);
      expect(find.text(_tr.profileSubscriptionRow), findsOneWidget);
      expect(find.text(_tr.profileFeedback), findsOneWidget);
      expect(find.text(_tr.about), findsOneWidget);
      // Rol tipografisi: "Tercihler" olduğu gibi — "TERCIHLER" değil.
      expect(find.text(_tr.profileSectionPrefs), findsOneWidget);
      // "Hesap" hem grup başlığı hem satır (accountSection) — en az bir.
      expect(find.text(_tr.profileSectionAccount), findsAtLeastNWidgets(1));
      expect(find.text('TERCİHLER'), findsNothing);
      expect(find.text('TERCIHLER'), findsNothing);
    });

    test('kaynak: toUpperCase yok, dolu CTA yok, onayliCikis var (yorumsuz)',
        () {
      final k = _yorumsuz('lib/features/profile/profile_screen.dart');
      expect(k, isNot(contains('toUpperCase(')));
      expect(k, isNot(contains('GoldButton(')));
      expect(k, contains('onayliCikis(context)'));
      expect(k, contains('_grupBaslik(kMarka)'));
    });
  });

  group('doğum tarihi satırı', () {
    testWidgets('ISO değil, dilde tarih: 7 Mart 1988', (tester) async {
      await _ekran(tester);
      expect(find.text('7 Mart 1988'), findsOneWidget);
      expect(find.text('1988-03-07'), findsNothing);
    });

    test('dogumTarihiYazisi: null → null; bozuk → olduğu gibi', () {
      expect(dogumTarihiYazisi(null, 'tr'), isNull);
      expect(dogumTarihiYazisi('bilmemne', 'tr'), 'bilmemne');
    });
  });
}
