// Şifre panosu bekçileri (OT2).
//
// Eski akışın kusuru: TÜM hatalar yutulup her durumda "gönderildi"
// gösteriliyordu — kullanıcı e-postayı hiç alamıyordu ve ekranda hiçbir
// ipucu yoktu. Bu dosya panonun üç sözleşmesini sabitler: (1) gerçek
// hatalar ANLATILIR; (2) `user-not-found` BAŞARI gibi görünür
// (anti-enumeration); (3) tekrar-gönder bekleme süresine bağlıdır.
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rytho/features/auth/forgot_password_screen.dart';
import 'package:rytho/l10n/app_localizations.dart';

Widget _sar(Widget child) => MaterialApp(
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('tr'),
      home: child,
    );

void main() {
  testWidgets('e-posta login ekranından önceden dolu gelir', (tester) async {
    await tester.pumpWidget(_sar(const ForgotPasswordScreen(
        initialEmail: 'aslan.mh@gmail.com', sender: _hicGonderme)));
    expect(
        find.widgetWithText(TextField, 'aslan.mh@gmail.com'), findsOneWidget);
  });

  testWidgets('başarı görünümü: maskeli adres + spam ipucu + bekleme',
      (tester) async {
    await tester.pumpWidget(_sar(const ForgotPasswordScreen(
        initialEmail: 'aslan.mh@gmail.com', sender: _basarili)));
    await tester.tap(find.text('Bağlantıyı gönder'));
    await tester.pump();

    expect(find.text('Bağlantı yolda'), findsOneWidget);
    expect(find.textContaining('as•••@gmail.com'), findsOneWidget);
    expect(find.textContaining('spam'), findsOneWidget);
    // Bekleme süresi dolana dek düğme "Tekrar gönder (N sn)" der.
    expect(find.textContaining('Tekrar gönder ('), findsOneWidget);
    await tester.pump(const Duration(seconds: 31));
    expect(find.text('Tekrar gönder'), findsOneWidget);
  });

  testWidgets('user-not-found BAŞARI gibi görünür (anti-enumeration)',
      (tester) async {
    await tester.pumpWidget(_sar(const ForgotPasswordScreen(
        initialEmail: 'yok@ornek.com', sender: _kayitsizAdres)));
    await tester.tap(find.text('Bağlantıyı gönder'));
    await tester.pump();
    // "Bu adres kayıtlı mı" bilgisi sızmaz: aynı başarı görünümü.
    expect(find.text('Bağlantı yolda'), findsOneWidget);
    await tester.pump(const Duration(seconds: 31)); // zamanlayıcı kapanışı
  });

  testWidgets('gerçek hata ANLATILIR — eski davranışın ölümü',
      (tester) async {
    await tester.pumpWidget(_sar(const ForgotPasswordScreen(
        initialEmail: 'aslan.mh@gmail.com', sender: _agHatasi)));
    await tester.tap(find.text('Bağlantıyı gönder'));
    await tester.pump();
    expect(find.text('Bağlantı yolda'), findsNothing);
    // authNetwork metni (tr): bağlantı sorunu anlatılır.
    expect(find.textContaining('Bağlantı kurulamadı'), findsOneWidget);
  });

  testWidgets('e-posta ipucu sözlükten (emailHint) — sabit Türkçe adres değil',
      (tester) async {
    // 'ornek@eposta.com' sabitti: İngilizce arayüzde Türkçe örnek adres
    // kalıyordu (D4). initialEmail dolu ki alan odak almasın — odaklı
    // TextField bu makinede çizimde fırlatıyor (sifre_alanlari_test notu).
    await tester.pumpWidget(_sar(const ForgotPasswordScreen(
        initialEmail: 'aslan.mh@gmail.com', sender: _hicGonderme)));
    final alan = tester.widget<TextField>(find.byType(TextField));
    expect(alan.decoration?.hintText,
        lookupAppLocalizations(const Locale('tr')).emailHint);
    expect(alan.decoration?.hintText, isNot(contains('ornek')));
  });

  testWidgets('geçersiz biçimli e-posta gönderim yapmadan uyarır',
      (tester) async {
    var cagri = 0;
    await tester.pumpWidget(_sar(ForgotPasswordScreen(
        initialEmail: 'gecersiz-adres',
        sender: (_) async {
          cagri++;
        })));
    await tester.tap(find.text('Bağlantıyı gönder'));
    await tester.pump();
    expect(cagri, 0);
    expect(find.text('Bağlantı yolda'), findsNothing);
  });
}

Future<void> _hicGonderme(String email) async =>
    throw StateError('gönderilmemeliydi');

Future<void> _basarili(String email) async {}

Future<void> _kayitsizAdres(String email) async =>
    throw FirebaseAuthException(code: 'user-not-found');

Future<void> _agHatasi(String email) async =>
    throw FirebaseAuthException(code: 'network-request-failed');
