// Giriş ekranının iOS bekçileri (K1-giriş turu: U04, U31, U49).
//
// U04 — Apple ile Giriş düğmesi HIG'e uymalı: App Review düğmeyi logo,
// başlık ve siyah/beyaz stil üzerinden denetliyor; eski altın çerçeveli,
// logosuz metin düğmesi 4.0/4.8 reddi riskiydi. Android'de düğme hiç yok.
//
// U49 — Apple/Google sayfasını kapatmak hata DEĞİLDİR: eskiden "Bir şeyler
// ters gitti" gösteriliyor ve Crashlytics'e sahte kayıt düşüyordu. Ama
// Google'ın "[16] Account reauth failed" hatası Android'de İPTAL koduyla
// geliyor (google_sign_in_android 7.2.15) ve yol gösteren mesajını (B1)
// korumalı — iptal süzgeci onu yutmamalı.
//
// U31 — başka yöntemle açılmış e-postada genel hata yerine yol gösteren
// mesaj; otomatik bağlama yok.
import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/cupertino.dart' show CupertinoActivityIndicator;
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:rytho/core/auth_service.dart';
import 'package:rytho/features/auth/login_screen.dart';
import 'package:rytho/l10n/app_localizations.dart';
import 'package:rytho/widgets/atlas_widgets.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

final _tr = lookupAppLocalizations(const Locale('tr'));

const _appleIptal = SignInWithAppleAuthorizationException(
    code: AuthorizationErrorCode.canceled, message: 'kapatıldı');
const _appleBilinmeyen = SignInWithAppleAuthorizationException(
    code: AuthorizationErrorCode.unknown, message: '1000');
const _googleIptal =
    GoogleSignInException(code: GoogleSignInExceptionCode.canceled);
const _googleReauth = GoogleSignInException(
    code: GoogleSignInExceptionCode.canceled,
    description: '[16] Account reauth failed.');

/// Giriş ekranı, gerçekçi bir iPhone boyunda. Hareket kapalı: yıldız alanı
/// ve logo nefesi sonsuz döngü, `pumpAndSettle` bitmez.
Future<void> _girisEkrani(
  WidgetTester tester, {
  Future<void> Function()? apple,
  Future<void> Function()? google,
}) async {
  tester.view.physicalSize = const Size(390 * 3, 844 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: AppLocalizations.supportedLocales,
    locale: const Locale('tr'),
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(disableAnimations: true),
      child: child!,
    ),
    home: LoginScreen(appleGirisi: apple, googleGirisi: google),
  ));
  // Giriş animasyonlarının gecikme zamanlayıcıları boşalsın.
  await tester.pump(const Duration(seconds: 1));
}

Finder get _googleDugmesi =>
    find.widgetWithText(GoldButton, _tr.signInWithGoogle);

Future<void> _dokun(WidgetTester tester, Finder hedef) async {
  await tester.ensureVisible(hedef);
  await tester.pump();
  await tester.tap(hedef);
  await tester.pump();
  await tester.pump();
}

void main() {
  group('girisIptalEdildi — U49', () {
    test('Apple sayfasını kapatmak iptaldir', () {
      expect(girisIptalEdildi(_appleIptal), isTrue);
    });

    test('Apple unknown (1000) iptal SAYILMAZ — gerçek arızayı da taşır', () {
      expect(girisIptalEdildi(_appleBilinmeyen), isFalse);
    });

    test('Google sayfasını kapatmak iptaldir', () {
      expect(girisIptalEdildi(_googleIptal), isTrue);
    });

    test('iptal koduyla gelen [16] reauth hatası iptal SAYILMAZ (B1)', () {
      expect(googleYenidenDogrulamaGerekli(_googleReauth), isTrue);
      expect(girisIptalEdildi(_googleReauth), isFalse);
    });

    test('başka hatalar iptal sayılmaz', () {
      expect(
          girisIptalEdildi(const GoogleSignInException(
              code: GoogleSignInExceptionCode.unknownError)),
          isFalse);
      expect(girisIptalEdildi(FirebaseAuthException(code: 'internal-error')),
          isFalse);
      expect(girisIptalEdildi(StateError('x')), isFalse);
    });
  });

  group('authErrorText — U31', () {
    test('başka yöntemle açılmış hesap kendi mesajını alır', () {
      final metin = authErrorText(
          _tr,
          FirebaseAuthException(
              code: 'account-exists-with-different-credential'));
      expect(metin, _tr.authAccountExistsOtherMethod);
      expect(metin, isNot(_tr.authFailed));
    });

    test('mesaj yöntemleri sayar ama hangisi olduğunu iddia etmez', () {
      // Firebase hangi sağlayıcının kullanıldığını söylemiyor (kullanıcı
      // sayımı koruması); metin tahmin yürütmemeli.
      expect(_tr.authAccountExistsOtherMethod, contains('Google'));
      expect(_tr.authAccountExistsOtherMethod, contains('Apple'));
    });
  });

  group('Apple düğmesi — U04', () {
    testWidgets('iOS: HIG düğmesi beyaz, 52 yüksek, Google\'ın üstünde',
        (tester) async {
      await _girisEkrani(tester);

      final dugme = find.byType(SignInWithAppleButton);
      expect(dugme, findsOneWidget);
      final w = tester.widget<SignInWithAppleButton>(dugme);
      // whiteOutlined koyu zeminde HIG'e aykırı; siyah koyu zeminde kaybolur.
      expect(w.style, SignInWithAppleButtonStyle.white);
      expect(w.height, 52, reason: 'Google düğmesiyle (GoldButton) eş boy');
      expect(w.borderRadius, BorderRadius.circular(18));
      expect(w.text, 'Apple ile Giriş Yap');
      // Logo paketin kendi ressamıyla çiziliyor.
      expect(
          find.descendant(
              of: dugme,
              matching: find.byWidgetPredicate((x) =>
                  x is CustomPaint && x.painter is AppleLogoPainter)),
          findsOneWidget);

      expect(tester.getSize(dugme).height, 52);
      expect(tester.getTopLeft(dugme).dy,
          lessThan(tester.getTopLeft(_googleDugmesi).dy),
          reason: 'Apple düğmesi Google\'ın üstünde durmalı');
    }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

    testWidgets('Android: Apple düğmesi YOK, Google düğmesi yerinde',
        (tester) async {
      await _girisEkrani(tester);

      expect(find.byType(SignInWithAppleButton), findsNothing);
      expect(find.text(_tr.signInWithApple), findsNothing);
      expect(_googleDugmesi, findsOneWidget);
    }, variant: TargetPlatformVariant.only(TargetPlatform.android));

    testWidgets('meşgulken gösterge çıkar, ikinci dokunuş akış başlatmaz',
        (tester) async {
      final bekleyen = Completer<void>();
      var cagri = 0;
      await _girisEkrani(tester, apple: () {
        cagri++;
        return bekleyen.future;
      });

      final dugme = find.byType(SignInWithAppleButton);
      expect(find.byType(CupertinoActivityIndicator), findsNothing);
      await _dokun(tester, dugme);
      expect(cagri, 1);
      expect(find.byType(CupertinoActivityIndicator), findsOneWidget);

      await tester.tap(dugme, warnIfMissed: false);
      await tester.pump();
      expect(cagri, 1, reason: 'ikinci OAuth akışı başladı');
      // Öteki yollar da kilitli.
      expect(tester.widget<GoldButton>(_googleDugmesi).onPressed, isNull);

      bekleyen.complete();
      await tester.pump();
      await tester.pump();
      expect(find.byType(CupertinoActivityIndicator), findsNothing);
      expect(tester.widget<GoldButton>(_googleDugmesi).onPressed, isNotNull);
    }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));
  });

  group('sosyal giriş hataları — U49 / U31', () {
    testWidgets('Apple sayfasını kapatmak hata göstermez', (tester) async {
      await _girisEkrani(tester, apple: () async => throw _appleIptal);

      await _dokun(tester, find.byType(SignInWithAppleButton));
      expect(find.byType(SnackBar), findsNothing);
      expect(find.text(_tr.authFailed), findsNothing);
    }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

    testWidgets('Apple unknown hatası yine anlatılır', (tester) async {
      await _girisEkrani(tester, apple: () async => throw _appleBilinmeyen);

      await _dokun(tester, find.byType(SignInWithAppleButton));
      expect(find.text(_tr.authFailed), findsOneWidget);
    }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

    testWidgets('Google sayfasını kapatmak hata göstermez (Android da)',
        (tester) async {
      await _girisEkrani(tester, google: () async => throw _googleIptal);

      await _dokun(tester, _googleDugmesi);
      expect(find.byType(SnackBar), findsNothing);
    }, variant: TargetPlatformVariant.only(TargetPlatform.android));

    testWidgets('iptal koduyla gelen [16] hatası yol gösterir (B1 korunur)',
        (tester) async {
      await _girisEkrani(tester, google: () async => throw _googleReauth);

      await _dokun(tester, _googleDugmesi);
      expect(find.text(_tr.authReauthNeeded), findsOneWidget);
    }, variant: TargetPlatformVariant.only(TargetPlatform.android));

    testWidgets('başka yöntemle açılmış e-posta yol gösteren mesaj alır',
        (tester) async {
      await _girisEkrani(tester,
          apple: () async => throw FirebaseAuthException(
              code: 'account-exists-with-different-credential'));

      await _dokun(tester, find.byType(SignInWithAppleButton));
      expect(find.text(_tr.authAccountExistsOtherMethod), findsOneWidget);
    }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));
  });
}
