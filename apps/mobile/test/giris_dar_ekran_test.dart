// Dar ekran + büyük yazı ölçeği taşma bekçileri — GİRİŞ/AUTH turu (D4).
//
// Ölçüt `dar_ekran_test.dart` ile aynı: 320 dp genişlik × 1,3 yazı ölçeği
// (`kMaxTextScale`) altında hiçbir şey taşmamalı. Harness
// `dar_ekran_ekranlar_test.dart`taki `darEkrandaEkran` deseninin kopyası
// (o dosya başka ajanın; ortak harness'a taşınması D8'e kalır).
//
// ⚠️ Yazı tipi varsayımı YAPILMAZ. Eski dar ekran bekçileri "Ahem her harfi
// punto kadar geniş kare çizer, ~2 kat tutucu" diyordu; D1'den beri Sora /
// Manrope pakette ve test ortamında da yükleniyor — ölçüldü (2026-10-10):
// 14 harflik 22 px başlık esnemeyen kutuda ~240 px'e sığdı, Ahem olsaydı
// 309 px olurdu. Yani piksel genişliği iddiası iki yönde de kurulamaz;
// testler yalnız "taştı mı?" ve "metin ekranda mı?" sorar.
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:rytho/core/device_session.dart';
import 'package:rytho/features/auth/device_conflict_screen.dart';
import 'package:rytho/features/auth/forgot_password_screen.dart';
import 'package:rytho/features/auth/login_screen.dart';
import 'package:rytho/features/profile/sign_in_methods_screen.dart';
import 'package:rytho/l10n/app_localizations.dart';
import 'package:rytho/l10n/app_localizations_tr.dart';
import 'package:rytho/main.dart' show kMaxTextScale;
import 'package:rytho/theme/rytho_theme.dart';

final _tr = AppLocalizationsTr();
const double _kDarGenislik = 320;

/// Tam ekran widget'ları (kendi `Scaffold`'ıyla gelenler) için harness.
/// Yükseklik GERÇEKÇİ (800): kısa tutmak ölçmek istemediğimiz DİKEY
/// taşmaları uydurur. [kap] verilirse Riverpod durumu oradan gelir.
Future<void> _darEkrandaEkran(WidgetTester tester, Widget home,
    {ProviderContainer? kap}) async {
  tester.view.physicalSize = const Size(_kDarGenislik * 3, 800 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  final app = MaterialApp(
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
        textScaler: const TextScaler.linear(kMaxTextScale),
        // Ölçülen şey YERLEŞİM, hareket değil.
        disableAnimations: true,
      ),
      child: child!,
    ),
    home: home,
  );
  await tester.pumpWidget(kap == null
      ? ProviderScope(child: app)
      : UncontrolledProviderScope(container: kap, child: app));
}

void _tasmaYok(WidgetTester tester, {String? neden}) {
  expect(tester.takeException(), isNull, reason: neden);
}

/// Listeyi sonuna kadar kaydır: ListView tembel kurar, görünmeyen blok
/// çizilmez ve taşması ölçülmez.
Future<void> _sonaKaydir(WidgetTester tester) async {
  await tester.drag(find.byType(Scrollable).first, const Offset(0, -3000));
  await tester.pump();
}

void main() {
  setUpAll(() => initializeDateFormatting());

  group('LoginScreen', () {
    testWidgets('giriş modu 320 dp × 1,3: üst ve alt bloklar taşmaz',
        (tester) async {
      await _darEkrandaEkran(tester, const LoginScreen());
      _tasmaYok(tester, neden: 'giriş formu taşıyor');
      await _sonaKaydir(tester);
      _tasmaYok(tester, neden: 'sosyal düğmeler / hukuki onay taşıyor');
      // Ölçüldü (800 dp yükseklikte): Google düğmesi kaydırmadan da
      // kuruluyor; hukuki onay metni listenin dibinde, kaydırma onun için.
      expect(find.text(_tr.signInWithGoogle), findsOneWidget);
      expect(find.text(_tr.insightNote), findsOneWidget,
          reason: 'liste sonuna kadar kurulmadı; dip bloğun taşması ölçülmedi');
    });

    testWidgets('kayıt modu 320 dp × 1,3: tekrar alanı + yaş beyanı taşmaz',
        (tester) async {
      await _darEkrandaEkran(tester, const LoginScreen());
      await tester.tap(find.text(_tr.signUp));
      await tester.pump();
      _tasmaYok(tester, neden: 'kayıt formu taşıyor');
      expect(find.text(_tr.passwordRepeat), findsOneWidget);
      await _sonaKaydir(tester);
      _tasmaYok(tester);
    });
  });

  group('ForgotPasswordScreen', () {
    testWidgets('form ve başarı görünümü 320 dp × 1,3 taşmaz', (tester) async {
      await _darEkrandaEkran(
          tester,
          ForgotPasswordScreen(
              initialEmail: 'cokuzunbirkullaniciadi@ornekalanadi.com',
              sender: (_) async {}));
      _tasmaYok(tester, neden: 'şifre panosu formu taşıyor');
      await tester.tap(find.text(_tr.forgotPasswordSend));
      await tester.pump();
      _tasmaYok(tester, neden: 'başarı görünümü taşıyor');
      expect(find.text(_tr.forgotPasswordSentTitle), findsOneWidget);
      await tester.pump(const Duration(seconds: 31)); // zamanlayıcı kapanışı
    });
  });

  group('DeviceConflictScreen', () {
    testWidgets('bilinmeyen cihaz: bilgisiz gövde 320 dp × 1,3 taşmaz',
        (tester) async {
      await _darEkrandaEkran(tester, const DeviceConflictScreen());
      _tasmaYok(tester);
      expect(find.text(_tr.deviceConflictBodyUnknown), findsOneWidget);
    });

    testWidgets('bilinen cihaz + saat: gövde 320 dp × 1,3 taşmaz',
        (tester) async {
      final kap = ProviderContainer();
      addTearDown(kap.dispose);
      kap.read(deviceConflictProvider.notifier).state = DeviceConflict(
          platform: 'android', claimedAt: DateTime.utc(2026, 9, 12, 10));
      await _darEkrandaEkran(tester, const DeviceConflictScreen(), kap: kap);
      _tasmaYok(tester);
      expect(find.text(_tr.deviceConflictUseHere), findsOneWidget);
    });
  });

  group('SignInMethodsScreen', () {
    testWidgets('şifre bağlı DEĞİL (e-posta alanı var) 320 dp × 1,3 taşmaz',
        (tester) async {
      await _darEkrandaEkran(
          tester,
          SignInMethodsScreen(
              baglilar: () => {'google.com'},
              ilkEposta: 'cokuzunbirkullaniciadi@ornekalanadi.com'));
      _tasmaYok(tester);
      await _sonaKaydir(tester);
      _tasmaYok(tester, neden: 'şifre bölümü taşıyor');
      expect(find.text(_tr.setPasswordAction), findsOneWidget);
    });

    testWidgets('şifre bağlı (değiştirme) 320 dp × 1,3 taşmaz',
        (tester) async {
      await _darEkrandaEkran(
          tester,
          SignInMethodsScreen(
              baglilar: () => {'password', 'phone'}, ilkEposta: 'a@b.co'));
      _tasmaYok(tester);
      await _sonaKaydir(tester);
      _tasmaYok(tester);
      expect(find.text(_tr.changePasswordAction), findsOneWidget);
    });
  });
}
