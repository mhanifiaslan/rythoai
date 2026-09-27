import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rytho/core/ai_consent.dart' show aiOnayHesabiProvider;
import 'package:rytho/core/providers.dart';
import 'package:rytho/features/face/face_consent.dart';
import 'package:rytho/features/profile/legal_page.dart';
import 'package:rytho/features/profile/profile_sections.dart';
import 'package:rytho/l10n/app_localizations.dart';
import 'package:rytho/widgets/common.dart';

/// Asama A4'un degismezleri.
///
/// Profil ~1400 px'di: yedi kart ve satir icine serpistirilmis ON DORT
/// kontrol. Kullanicinin tarifi "asagi dogru uzayan bir liste" idi. Gruplama
/// aslinda vardi, sorun TEK SEVIYELI olmasiydi -- yedi baslik hepsi acik
/// halde alt alta duruyordu.
///
/// Ayarlar alt sayfalara tasinirken bir seyin kaybolmamasi gerekiyor:
/// ozellikle biyometrik riza geri alma. GDPR Md.7/3 geri almanin vermek
/// kadar kolay olmasini istiyor; alt sayfaya tasinmasi kabul edilebilir ama
/// KAYBOLMASI degil. Asagidaki test onu tutuyor.

/// Yalnizca uygulama kabugu. `ProviderScope` cagri yerinde kuruluyor:
/// `Override` turu flutter_riverpod 3'te disa aktarilmadigi icin
/// `List<Override>` yazilamiyor, cikarima birakiliyor.
Widget _uygulama(Widget child) => MaterialApp(
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

Widget _sar(Widget child) => ProviderScope(child: _uygulama(child));

/// Yuz rizasi satirinin anahtari. `.last` DEGIL: U06'da altina AI onayi
/// satiri eklendi ve "son anahtar" artik o.
Finder _yuzAnahtari() => find.descendant(
    of: find.byType(FaceConsentRow), matching: find.byType(Switch));

/// Yildiz alani surekli animasyonlu — `pumpAndSettle` hicbir zaman donmez.
Future<void> _bekle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  group('gizlilik alt sayfasi', () {
    testWidgets('biyometrik riza geri alma KAYBOLMADI', (tester) async {
      await tester.pumpWidget(ProviderScope(
        overrides: [
          // Firebase kurulmadan: hesap yok → AI onayi kapali, aga gidilmez.
          aiOnayHesabiProvider.overrideWithValue(null),
          profileProvider.overrideWith(
              (ref) => Stream.value({'streakVisible': false})),
          faceConsentProvider.overrideWith(
              (ref) async => const FaceConsent(granted: true, version: 1)),
        ],
        child: _uygulama(const PrivacySettingsScreen()),
      ));
      await _bekle(tester);

      expect(find.text('Yüz okuma rızası'), findsOneWidget);
      // Riza VERILMISKEN anahtar acik ve kapatilabilir olmali.
      final anahtar = tester.widget<Switch>(_yuzAnahtari());
      expect(anahtar.value, isTrue);
      expect(anahtar.onChanged, isNotNull,
          reason: 'riza geri alinamiyor — GDPR Md.7/3');
    });

    testWidgets('riza yokken anahtar ACILAMAZ', (tester) async {
      // Riza ancak metnini gosteren ekrandan alinir; buradan acilmasi
      // bilgilendirilmis riza olmazdi.
      await tester.pumpWidget(ProviderScope(
        overrides: [
          // Firebase kurulmadan: hesap yok → AI onayi kapali, aga gidilmez.
          aiOnayHesabiProvider.overrideWithValue(null),
          profileProvider.overrideWith(
              (ref) => Stream.value({'streakVisible': false})),
          faceConsentProvider.overrideWith(
              (ref) async => const FaceConsent(granted: false, version: 1)),
        ],
        child: _uygulama(const PrivacySettingsScreen()),
      ));
      await _bekle(tester);

      final anahtar = tester.widget<Switch>(_yuzAnahtari());
      expect(anahtar.value, isFalse);
      expect(anahtar.onChanged, isNull,
          reason: 'riza buradan verilemez, yalnizca geri alinabilir');
    });

    testWidgets('dort gizlilik anahtari da burada', (tester) async {
      // Seri gorunurlugu + rehber eslesmesi (R3) + biyometrik riza + AI
      // aktarim onayi (U06). Sayi bilincli: yeni bir gizlilik anahtari
      // eklenirse bu test duser ve eklenenin varsayilaninin KAPALI oldugu
      // gozden gecirilir — AI onayi da kayit yokken KAPALI (asagida).
      await tester.pumpWidget(ProviderScope(
        overrides: [
          // Firebase kurulmadan: hesap yok → AI onayi kapali, aga gidilmez.
          aiOnayHesabiProvider.overrideWithValue(null),
          profileProvider
              .overrideWith((ref) => Stream.value({'streakVisible': true})),
          faceConsentProvider.overrideWith(
              (ref) async => const FaceConsent(granted: false, version: 1)),
        ],
        child: _uygulama(const PrivacySettingsScreen()),
      ));
      await _bekle(tester);

      expect(find.byType(Switch), findsNWidgets(4));
      final ai = tester.widget<Switch>(find.descendant(
          of: find.byType(AiConsentRow), matching: find.byType(Switch)));
      expect(ai.value, isFalse, reason: 'AI onayi varsayilan KAPALI');
    });
  });

  group('hakkinda alt sayfasi', () {
    testWidgets('her iki hukuki metin de ulasilabilir', (tester) async {
      // Magaza incelemesi ikisini de ariyor; alt sayfaya tasinirken birinin
      // dusmesi sessiz bir uyumsuzluk olurdu.
      await tester.pumpWidget(_sar(const AboutScreen()));
      await _bekle(tester);

      expect(find.text('Gizlilik Politikası'), findsOneWidget);
      expect(find.text('Kullanım Şartları'), findsOneWidget);
    });

    testWidgets('gizlilik politikasi acilir', (tester) async {
      await tester.pumpWidget(_sar(const AboutScreen()));
      await _bekle(tester);

      await tester.tap(find.text('Gizlilik Politikası'));
      await _bekle(tester);

      expect(find.byType(LegalPage), findsOneWidget);
    });

    testWidgets('efemeris atfi duruyor', (tester) async {
      // Swiss Ephemeris lisansi atfi zorunlu kiliyor.
      await tester.pumpWidget(_sar(const AboutScreen()));
      await _bekle(tester);

      expect(find.textContaining('Ephemeris'), findsOneWidget);
    });
  });

  group('SettingsRow', () {
    testWidgets('deger verilirse sagda gosterilir', (tester) async {
      await tester.pumpWidget(_sar(const Scaffold(
        body: SettingsRow(title: 'Doğum kaydı', value: '1988-03-07'),
      )));
      await _bekle(tester);

      expect(find.text('1988-03-07'), findsOneWidget);
    });

    testWidgets('onTap varsa chevron cikar, yoksa cikmaz', (tester) async {
      await tester.pumpWidget(_sar(Scaffold(
        body: SettingsRow(title: 'Hesap', onTap: () {}),
      )));
      await _bekle(tester);
      expect(find.byIcon(Icons.chevron_right_rounded), findsOneWidget);

      await tester.pumpWidget(_sar(const Scaffold(
        body: SettingsRow(title: 'Hesap'),
      )));
      await _bekle(tester);
      // Gosterge uyumu: dokunulamayan satir dokunulabilir GORUNMEMELI.
      expect(find.byIcon(Icons.chevron_right_rounded), findsNothing);
    });

    testWidgets('trailing verilirse chevron yerine o gosterilir',
        (tester) async {
      await tester.pumpWidget(_sar(Scaffold(
        body: SettingsRow(
          title: 'Sesler',
          onTap: () {},
          trailing: Switch(value: true, onChanged: (_) {}),
        ),
      )));
      await _bekle(tester);

      expect(find.byType(Switch), findsOneWidget);
      expect(find.byIcon(Icons.chevron_right_rounded), findsNothing);
    });
  });
}
