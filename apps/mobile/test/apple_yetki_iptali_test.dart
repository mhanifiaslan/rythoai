// Hesap silmede Apple yetkisi iptali bekçileri (U15, App Store 5.1.1(v)).
//
// Eski akış doğrudan `DELETE /account/me` çağırıyordu: Firebase kullanıcısı
// gidiyor, Apple tarafındaki "Apple ile Giriş" yetkisi yerinde kalıyordu.
// Bu dosya dört sözleşmeyi sabitler:
// (1) adım yalnız iOS + `apple.com` bağlı hesapta koşar, Android'de hiçbir
//     şeye dokunmaz;
// (2) sıra Apple sayfası → yeniden doğrulama (aynı nonce) → iptal;
// (3) kullanıcı Apple sayfasını KAPATIRSA silme durur, sunucuya istek
//     gitmez;
// (4) başka her arızada hata `apple-revoke` diye kaydedilir ve silme SÜRER
//     — iptal adımı silmeyi rehin alamaz.
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rytho/core/api.dart' show apiProvider;
import 'package:rytho/core/auth_service.dart';
import 'package:rytho/features/profile/delete_account.dart';
import 'package:rytho/l10n/app_localizations.dart';
import 'package:rytho/widgets/atlas_widgets.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

final _tr = lookupAppLocalizations(const Locale('tr'));

AuthorizationCredentialAppleID _appleKimligi() =>
    const AuthorizationCredentialAppleID(
      userIdentifier: '001.abc',
      givenName: null,
      familyName: null,
      authorizationCode: 'yetki-kodu-1',
      email: null,
      identityToken: 'kimlik-jetonu',
      state: null,
    );

/// Adımların sırasını ve girdilerini kaydeden sahte dünya.
class _Kayit {
  final List<String> adimlar = [];
  String? nonceOzeti;
  AuthCredential? kimlik;
  String? iptalKodu;
  final List<Object> hatalar = [];

  Future<AuthorizationCredentialAppleID> sayfa(String ozet) async {
    adimlar.add('sayfa');
    nonceOzeti = ozet;
    return _appleKimligi();
  }

  Future<void> dogrula(AuthCredential k) async {
    adimlar.add('dogrula');
    kimlik = k;
  }

  Future<void> iptal(String kod) async {
    adimlar.add('iptal');
    iptalKodu = kod;
  }

  void kaydet(Object hata, StackTrace _) => hatalar.add(hata);
}

Future<AppleIptalSonucu> _calistir(
  _Kayit k, {
  Iterable<String> saglayicilar = const ['apple.com'],
  Future<AuthorizationCredentialAppleID> Function(String)? sayfa,
  Future<void> Function(AuthCredential)? dogrula,
  Future<void> Function(String)? iptal,
}) =>
    appleYetkisiniIptalEt(
      saglayicilar: saglayicilar,
      appleSayfasi: sayfa ?? k.sayfa,
      yenidenDogrula: dogrula ?? k.dogrula,
      iptalEt: iptal ?? k.iptal,
      hataKaydi: k.kaydet,
    );

/// Sabit yanıt veren sahte sunucu; istekleri saklar.
class _SahteAdapter implements HttpClientAdapter {
  final List<RequestOptions> istekler = [];

  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    istekler.add(options);
    return ResponseBody.fromString('{"status":"deleted","deleted":{}}', 200,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        });
  }

  @override
  void close({bool force = false}) {}
}

/// Sayfayı gerçek akıştaki gibi alt sayfa olarak açar ve silmeyi onaylar.
Future<void> _silmeyiOnayla(
  WidgetTester tester, {
  required _SahteAdapter adapter,
  required Future<AppleIptalSonucu> Function() apple,
  required Future<void> Function() cikis,
}) async {
  final dio = Dio(BaseOptions(baseUrl: 'https://test.invalid'))
    ..httpClientAdapter = adapter;
  await tester.pumpWidget(ProviderScope(
    overrides: [apiProvider.overrideWithValue(dio)],
    child: MaterialApp(
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('tr'),
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => showModalBottomSheet<void>(
              context: context,
              isScrollControlled: true,
              builder: (_) =>
                  DeleteAccountSheet(appleIptali: apple, cikis: cikis),
            ),
            child: const Text('aç'),
          ),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('aç'));
  await tester.pumpAndSettle();
  await tester.enterText(find.byType(TextField), _tr.deleteAccountConfirmWord);
  await tester.pump();
  await tester.tap(find.widgetWithText(GoldButton, _tr.deleteAccountAction));
  await tester.pump();
  await tester.pump();
}

void main() {
  group('appleYetkisiniIptalEt — kapı', () {
    test('Android: hiçbir adım koşmaz', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      final k = _Kayit();
      expect(await _calistir(k), AppleIptalSonucu.gerekmedi);
      expect(k.adimlar, isEmpty);
    });

    test('iOS ama Apple bağlı değil: hiçbir adım koşmaz', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      final k = _Kayit();
      expect(await _calistir(k, saglayicilar: const ['google.com', 'password']),
          AppleIptalSonucu.gerekmedi);
      expect(k.adimlar, isEmpty);
    });
  });

  group('appleYetkisiniIptalEt — iOS + apple.com', () {
    setUp(() => debugDefaultTargetPlatformOverride = TargetPlatform.iOS);
    tearDown(() => debugDefaultTargetPlatformOverride = null);

    test('sıra: sayfa → yeniden doğrulama → iptal', () async {
      final k = _Kayit();
      expect(await _calistir(k), AppleIptalSonucu.iptalEdildi);
      expect(k.adimlar, ['sayfa', 'dogrula', 'iptal']);
      expect(k.iptalKodu, 'yetki-kodu-1');
      expect(k.hatalar, isEmpty);
    });

    test('yeniden doğrulama Apple kimliğiyle ve AYNI nonce ile yapılır',
        () async {
      // Ham nonce Firebase'e, özeti Apple'a gider; eşleşmezse Firebase
      // kimliği reddeder ve iptal hiç koşmaz.
      final k = _Kayit();
      await _calistir(k);
      final kimlik = k.kimlik as OAuthCredential;
      expect(kimlik.providerId, 'apple.com');
      expect(kimlik.idToken, 'kimlik-jetonu');
      expect(sha256.convert(utf8.encode(kimlik.rawNonce!)).toString(),
          k.nonceOzeti);
    });

    test('Apple sayfasını kapatmak: vazgeçildi, kayıt yok, iptal yok',
        () async {
      final k = _Kayit();
      final sonuc = await _calistir(k,
          sayfa: (_) async => throw const SignInWithAppleAuthorizationException(
              code: AuthorizationErrorCode.canceled, message: 'kapatıldı'));
      expect(sonuc, AppleIptalSonucu.vazgecildi);
      expect(k.adimlar, isEmpty);
      expect(k.hatalar, isEmpty, reason: 'kapatmak arıza değil');
    });

    test('Apple sayfası arızası: kaydedilir, silme sürer', () async {
      final k = _Kayit();
      final sonuc = await _calistir(k,
          sayfa: (_) async => throw const SignInWithAppleAuthorizationException(
              code: AuthorizationErrorCode.unknown, message: '1000'));
      expect(sonuc, AppleIptalSonucu.basarisiz);
      expect(k.hatalar, hasLength(1));
    });

    test('başka Apple Kimliği seçildi (user-mismatch): iptal KOŞMAZ',
        () async {
      // Yeniden doğrulamanın varlık sebebi: başka birinin yetkisini iptal
      // etmemek.
      final k = _Kayit();
      final sonuc = await _calistir(k,
          dogrula: (_) async =>
              throw FirebaseAuthException(code: 'user-mismatch'));
      expect(sonuc, AppleIptalSonucu.basarisiz);
      expect(k.adimlar, ['sayfa']);
      expect(k.iptalKodu, isNull);
      expect(k.hatalar, hasLength(1));
    });

    test('iptal çağrısı düşerse (OAuth code flow eksik): kaydedilir, silme '
        'sürer', () async {
      final k = _Kayit();
      final sonuc = await _calistir(k,
          iptal: (_) async =>
              throw FirebaseAuthException(code: 'invalid-credential'));
      expect(sonuc, AppleIptalSonucu.basarisiz);
      expect(k.hatalar, hasLength(1));
    });
  });

  group('DeleteAccountSheet — silme akışı', () {
    testWidgets('Apple onayı kapatılırsa sunucuya silme GİTMEZ',
        (tester) async {
      final adapter = _SahteAdapter();
      var cikis = 0;
      await _silmeyiOnayla(tester,
          adapter: adapter,
          apple: () async => AppleIptalSonucu.vazgecildi,
          cikis: () async => cikis++);

      expect(adapter.istekler, isEmpty);
      expect(cikis, 0);
      expect(find.text(_tr.deleteAccountAppleCanceled), findsOneWidget);
      // Sayfa açık kalır; kullanıcı tekrar deneyebilir.
      expect(find.byType(DeleteAccountSheet), findsOneWidget);
    });

    testWidgets('Apple iptali başarısız olsa da silme sürer',
        (tester) async {
      final adapter = _SahteAdapter();
      var cikis = 0;
      await _silmeyiOnayla(tester,
          adapter: adapter,
          apple: () async => AppleIptalSonucu.basarisiz,
          cikis: () async => cikis++);
      await tester.pumpAndSettle();

      expect(adapter.istekler.map((r) => '${r.method} ${r.path}'),
          ['DELETE /api/v1/account/me']);
      expect(cikis, 1);
      expect(find.byType(DeleteAccountSheet), findsNothing);
    });

    testWidgets('Apple gerekmiyorsa (Android, Apple\'sız hesap) akış aynen',
        (tester) async {
      final adapter = _SahteAdapter();
      var cikis = 0;
      await _silmeyiOnayla(tester,
          adapter: adapter,
          apple: () async => AppleIptalSonucu.gerekmedi,
          cikis: () async => cikis++);
      await tester.pumpAndSettle();

      expect(adapter.istekler, hasLength(1));
      expect(cikis, 1);
      expect(find.text(_tr.deleteAccountAppleCanceled), findsNothing);
    });
  });
}
