// Giriş İPTALİ hata değildir (D4) — isAuthCancelled, socialHataSonucu ve
// giriş ekranının sosyal düğme davranışı.
//
// Ölçülen kusur (HEAD login_screen.dart:103-130): Google/Apple penceresini
// kullanıcı kendi kapatınca istisna genel `catch`e düşüyor, "Bir şeyler
// ters gitti" basılıyor ve Crashlytics'e yazılıyordu. Reauth dalı ([16],
// iç test bulgusu B1) aynen korunur: o hata gerçek ve yol gösteren mesaj
// ister.
//
// İstisna türleri kurulu paketlerden ÖLÇÜLDÜ (bkz. auth_service.dart
// `isAuthCancelled` yorumu); burada uydurma kod yok.
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:rytho/core/auth_service.dart';
import 'package:rytho/features/auth/login_screen.dart';
import 'package:rytho/l10n/app_localizations.dart';
import 'package:rytho/l10n/app_localizations_tr.dart';
import 'package:rytho/theme/rytho_theme.dart';
import 'package:rytho/widgets/atlas_widgets.dart' show GoldButton;
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

final _tr = AppLocalizationsTr();

const _googleIptal =
    GoogleSignInException(code: GoogleSignInExceptionCode.canceled);
const _appleIptal = SignInWithAppleAuthorizationException(
    code: AuthorizationErrorCode.canceled,
    message: 'User canceled authorization');

/// Giriş ekranı için kap: reduceMotion AÇIK (yıldız alanı + RythoReveal
/// zamanlayıcı bırakmasın) ve viewport UZUN — Google düğmesi listenin
/// sonunda; kısa yüzeyde ListView onu hiç kurmaz, `find.text` bulamazdı.
Future<void> _ekran(WidgetTester tester, Widget home) async {
  tester.view.physicalSize = const Size(390 * 3, 1600 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    locale: const Locale('tr'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    theme: buildRythoTheme(),
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(disableAnimations: true),
      child: child!,
    ),
    home: home,
  ));
}

/// Düğmeye dokun, async hata yolunun ve SnackBar girişinin bitmesini bekle.
///
/// Apple düğmesi `GoldButton` DEĞİL (U04): Apple'ın kendi
/// `SignInWithAppleButton`ı (Guideline 4.8 / HIG — logolu, siyah/beyaz).
/// Metinle bulunur; o metin ekranda yalnız o düğmede geçiyor.
Future<void> _dokun(WidgetTester tester, String metin) async {
  await tester.tap(metin == _tr.signInWithApple
      ? find.text(metin)
      : find.widgetWithText(GoldButton, metin));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

/// `signInWithApple`ın dönüşünden yalnız `user` okunuyor (ad yazımı).
class _SahteGiris implements UserCredential {
  @override
  User? get user => null;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      super.noSuchMethod(invocation);
}

AuthorizationCredentialAppleID _appleSayfasi({String? jeton = 'jeton'}) =>
    AuthorizationCredentialAppleID(
      userIdentifier: '001.abc',
      givenName: null,
      familyName: null,
      authorizationCode: 'kod',
      email: null,
      identityToken: jeton,
      state: null,
    );

void main() {
  group('isAuthCancelled', () {
    test('Google iptali, Apple iptali ve Firebase iptal kodları → true', () {
      expect(isAuthCancelled(_googleIptal), isTrue);
      expect(isAuthCancelled(_appleIptal), isTrue);
      // Android SDK (ERROR_WEB_CONTEXT_CANCELED, ERROR_USER_CANCELLED) ve
      // iOS eklentisi ("canceled") — Dart tarafı öneki atıp tireye çevirir.
      for (final kod in ['web-context-canceled', 'user-cancelled', 'canceled']) {
        expect(isAuthCancelled(FirebaseAuthException(code: kod)), isTrue,
            reason: kod);
      }
    });

    test('gerçek hatalar → false (iptal kılığına girmez)', () {
      expect(isAuthCancelled(FirebaseAuthException(code: 'wrong-password')),
          isFalse);
      expect(
          isAuthCancelled(
              FirebaseAuthException(code: 'network-request-failed')),
          isFalse);
      expect(
          isAuthCancelled(const GoogleSignInException(
              code: GoogleSignInExceptionCode.interrupted)),
          isFalse);
      expect(
          isAuthCancelled(const SignInWithAppleAuthorizationException(
              code: AuthorizationErrorCode.failed, message: 'x')),
          isFalse);
      expect(isAuthCancelled(Exception('x')), isFalse);
      expect(isAuthCancelled(StateError('[16] Account reauth failed')),
          isFalse);
    });
  });

  group('socialHataSonucu — saf sınıflandırma', () {
    test('iptal / reauth / genel', () {
      expect(socialHataSonucu(_googleIptal), AuthHataSonucu.iptal);
      expect(socialHataSonucu(_appleIptal), AuthHataSonucu.iptal);
      expect(socialHataSonucu(FirebaseAuthException(code: 'canceled')),
          AuthHataSonucu.iptal);
      expect(socialHataSonucu(Exception('[16] Account reauth failed')),
          AuthHataSonucu.reauth);
      expect(socialHataSonucu(Exception('Account REAUTH failed')),
          AuthHataSonucu.reauth);
      expect(socialHataSonucu(Exception('x')), AuthHataSonucu.genel);
      expect(socialHataSonucu(FirebaseAuthException(code: 'wrong-password')),
          AuthHataSonucu.genel);
    });
  });

  group('LoginScreen sosyal düğme', () {
    testWidgets('Google iptali: SnackBar YOK, düğme yeniden basılabilir',
        (tester) async {
      await _ekran(
          tester, LoginScreen(googleSignIn: () async => throw _googleIptal));
      await _dokun(tester, _tr.signInWithGoogle);

      expect(find.byType(SnackBar), findsNothing,
          reason: 'vazgeçen kullanıcıya "Bir şeyler ters gitti" basılıyordu');
      expect(find.text(_tr.authFailed), findsNothing);
      // Meşgul kilidi düştü: ikinci deneme mümkün.
      final dugme = tester.widget<GoldButton>(
          find.widgetWithText(GoldButton, _tr.signInWithGoogle));
      expect(dugme.onPressed, isNotNull, reason: 'düğme kilitli kaldı');
      expect(tester.takeException(), isNull);
    });

    testWidgets('Apple iptali de sessiz (iOS)', (tester) async {
      // Apple düğmesi yalnız iOS'ta (Guideline 4.8); platform `variant` ile
      // — `addTearDown` binding'in değişmez denetiminden SONRA koşar ve
      // "debug variable changed" fırlatır (ölçüldü).
      await _ekran(
          tester, LoginScreen(appleSignIn: () async => throw _appleIptal));
      await _dokun(tester, _tr.signInWithApple);

      expect(find.byType(SnackBar), findsNothing);
      expect(tester.takeException(), isNull);
    }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

    testWidgets('reauth [16] → yol gösteren mesaj (B1 korunur)',
        (tester) async {
      await _ekran(
          tester,
          LoginScreen(
              googleSignIn: () async =>
                  throw Exception('[16] Account reauth failed')));
      await _dokun(tester, _tr.signInWithGoogle);

      expect(find.text(_tr.authReauthNeeded), findsOneWidget);
      expect(find.text(_tr.authFailed), findsNothing);
    });

    testWidgets('genel hata → authFailed (sessizlik genele yayılmaz)',
        (tester) async {
      await _ekran(
          tester, LoginScreen(googleSignIn: () async => throw Exception('x')));
      await _dokun(tester, _tr.signInWithGoogle);
      expect(find.text(_tr.authFailed), findsOneWidget,
          reason: 'gerçek hata hâlâ söylenmeli — iptal onarımı sessizliği '
              'genele yaymamalı');
    });

    // Ayrı test: aynı testte ikinci `pumpWidget` aynı ScaffoldMessenger'ı
    // yeniden kullanıyor ve ikinci SnackBar ilkinin (4 sn) arkasında
    // kuyruğa giriyordu (ölçüldü).
    testWidgets('FirebaseAuthException → authErrorText haritasından',
        (tester) async {
      await _ekran(
          tester,
          LoginScreen(
              googleSignIn: () async =>
                  throw FirebaseAuthException(code: 'network-request-failed')));
      await _dokun(tester, _tr.signInWithGoogle);
      expect(find.text(_tr.authNetwork), findsOneWidget);
      expect(find.text(_tr.authFailed), findsNothing);
    });

    // iPad'de ölçülen (2026-10-28): Apple belirteci Firebase'de
    // `invalid-credential` ile reddedilince ekranda "E-posta veya şifre
    // hatalı." yazıyordu — kullanıcı ne e-posta ne şifre yazmıştı.
    testWidgets('Apple belirteci reddi şifre hatası gibi gösterilmez (iOS)',
        (tester) async {
      await _ekran(
          tester,
          LoginScreen(
              appleSignIn: () async => throw FirebaseAuthException(
                  code: 'invalid-credential',
                  message: 'Invalid OAuth response from apple.com')));
      await _dokun(tester, _tr.signInWithApple);

      expect(find.text(_tr.authFailed), findsOneWidget);
      expect(find.text(_tr.authWrongCredentials), findsNothing);
      expect(tester.takeException(), isNull);
    }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));
  });

  group('Apple kimliği', () {
    test('Apple\'a özel kimlik: signInMethod apple.com, nonce ve ad taşınır',
        () {
      // Genel `OAuthProvider('apple.com')` kimliği `oauth` taşır; iOS
      // eklentisinde o dal iPad'de `invalid-credential` aldı (2026-10-28).
      final k = appleKimligi('jeton', 'ham', ad: 'Ada', soyad: 'Yıldız');
      expect(k.providerId, 'apple.com');
      expect(k.signInMethod, 'apple.com');
      expect(k.idToken, 'jeton');
      expect(k.rawNonce, 'ham');
      expect(k.appleFullPersonName?.givenName, 'Ada');
      expect(k.appleFullPersonName?.familyName, 'Yıldız');
    });

    // Çağrı yeri: `appleKimligi`nin gövdesi doğru olsa da giriş onu
    // çağırmazsa (eski `OAuthProvider` satırı geri gelirse) iPad'deki red
    // geri gelir ve yalnız kurucuyu sınayan test yeşil kalırdı.
    test('signInWithApple Firebase\'e Apple\'a özel kimlikle ve AYNI nonce '
        'ile gider', () async {
      String? ozet;
      AuthCredential? giden;
      await signInWithApple(
        appleSayfasi: (o) async {
          ozet = o;
          return _appleSayfasi();
        },
        kimlikleGir: (k) async {
          giden = k;
          return _SahteGiris();
        },
      );
      final k = giden! as OAuthCredential;
      expect(k.signInMethod, 'apple.com');
      expect(k.providerId, 'apple.com');
      expect(k.idToken, 'jeton');
      expect(sha256.convert(utf8.encode(k.rawNonce!)).toString(), ozet);
    });

    test('Apple belirteci boşsa Firebase\'e hiç gidilmez', () async {
      var gidildi = false;
      await expectLater(
        signInWithApple(
          appleSayfasi: (_) async => _appleSayfasi(jeton: null),
          kimlikleGir: (_) async {
            gidildi = true;
            return _SahteGiris();
          },
        ),
        throwsStateError,
      );
      expect(gidildi, isFalse);
    });
  });

  group('sosyal giriş hata haritası', () {
    test('şifreye özgü kodlar sosyal girişte genel metne iner', () {
      for (final kod in ['invalid-credential', 'wrong-password', 'user-not-found']) {
        expect(sosyalGirisHataMetni(_tr, FirebaseAuthException(code: kod)),
            _tr.authFailed,
            reason: kod);
        // Şifre formunun haritası değişmedi: orada aynı kod şifre hatası.
        expect(authErrorText(_tr, FirebaseAuthException(code: kod)),
            _tr.authWrongCredentials,
            reason: kod);
      }
    });

    test('anlamı aynı kalan kodlar ortak haritadan gelir', () {
      expect(
          sosyalGirisHataMetni(_tr,
              FirebaseAuthException(
                  code: 'account-exists-with-different-credential')),
          _tr.authAccountExistsOtherMethod);
      expect(
          sosyalGirisHataMetni(
              _tr, FirebaseAuthException(code: 'network-request-failed')),
          _tr.authNetwork);
    });

    test('operation-not-allowed sosyal girişte "e-posta girişi kapalı" '
        'demez', () {
      // Sosyal girişte kapalı olan sağlayıcıdır, e-posta değil.
      expect(
          sosyalGirisHataMetni(
              _tr, FirebaseAuthException(code: 'operation-not-allowed')),
          _tr.authFailed);
      // Şifre formunun haritası değişmedi.
      expect(
          authErrorText(
              _tr, FirebaseAuthException(code: 'operation-not-allowed')),
          _tr.authDisabled);
    });

    test('yalnız arıza kodları Crashlytics\'e yazılır', () {
      for (final kod in [
        'invalid-credential',
        'operation-not-allowed',
        'internal-error',
        'unknown',
      ]) {
        expect(sosyalGirisHatasiKaydedilir(kod), isTrue, reason: kod);
      }
      // Kullanıcının kendi hâli: yazılırsa sayaç şişer, arıza gömülür.
      for (final kod in [
        'account-exists-with-different-credential',
        'network-request-failed',
        'too-many-requests',
        'canceled',
      ]) {
        expect(sosyalGirisHatasiKaydedilir(kod), isFalse, reason: kod);
      }
    });
  });
}
