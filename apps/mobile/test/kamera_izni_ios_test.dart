// İzin reddinin iOS bekçileri (K2-yüz turu: U23).
//
// iOS bir izni yalnız BİR KEZ sorar. Kamera: ilk ret `CameraAccessDenied`,
// sonraki her deneme diyalogsuz `CameraAccessDeniedWithoutPrompt`
// (`camera_avfoundation` 0.9.23+2). Bu kodlar `Permission` içermediği için
// ret donanım arızası sayılıyordu: ekran "yüz algılama başarısız" diyor,
// "Yeniden çek" sonsuza dek aynı hataya dönüyor ve her deneme Crashlytics'e
// sahte kayıt yazıyordu. Rehberde aynı çıkmaz: "Tekrar dene" bir daha
// sormuyor. İki ekranda da iOS'ta tek çıkış Ayarlar.
//
// Android'e bu turda bilerek dokunulmadı — orası sağlıklı olduğu için DEĞİL:
// Android ekranları Windows oturumunun ve orada cihazda ölçüm yok. Android
// 11+ da ikinci retten sonra diyalogsuz reddediyor (aynı çıkmaz), kamera
// reddi ise izin katmanına hiç ulaşmayıp arıza sayılıyor
// (`docs/test-raporu.md` B11). Aşağıdaki Android testleri bir düzeltmeyi
// değil, BUGÜNKÜ davranışın bu turda değişmediğini sabitliyor.
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:rytho/core/ayarlar_kisayolu.dart';
import 'package:rytho/core/contact_match.dart';
import 'package:rytho/core/providers.dart';
import 'package:rytho/features/face/face_capture_screen.dart';
import 'package:rytho/features/friends/contacts_screen.dart';
import 'package:rytho/l10n/app_localizations.dart';
import 'package:rytho/widgets/atlas_widgets.dart';

final _tr = lookupAppLocalizations(const Locale('tr'));

/// Açılan adresleri kaydeden sahte `launchUrl`.
class _SahteAcici {
  final acilanlar = <Uri>[];

  Future<bool> ac(Uri adres) async {
    acilanlar.add(adres);
    return true;
  }
}

Widget _sar(Widget govde, {List<Override> overrides = const []}) =>
    ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('tr'),
        home: Scaffold(body: govde),
      ),
    );

void main() {
  group('kameraIzniReddi — hangi kod izin reddi', () {
    tearDown(() => debugDefaultTargetPlatformOverride = null);

    test('iOS: CameraAccess kodlarının üçü de ret, arıza DEĞİL', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      for (final kod in const [
        'CameraAccessDenied',
        'CameraAccessDeniedWithoutPrompt',
        'CameraAccessRestricted',
      ]) {
        expect(kameraIzniReddi(kod), isTrue, reason: kod);
      }
    });

    test('iOS: gerçek arıza kodları arıza kalıyor', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      for (final kod in const ['IOError', 'VideoError', 'Error']) {
        expect(kameraIzniReddi(kod), isFalse, reason: kod);
      }
    });

    test('Permission içeren kod iki platformda da ret', () {
      for (final p in const [TargetPlatform.iOS, TargetPlatform.android]) {
        debugDefaultTargetPlatformOverride = p;
        expect(kameraIzniReddi('CameraPermissionsRequestOngoing'), isTrue,
            reason: p.name);
      }
    });

    test('Android sınıflandırması bu turda DEĞİŞMEDİ', () {
      // `camera_android_camerax` 0.6.30'un ret kodu da `CameraAccessDenied`
      // ve bugün arıza sayılıyor. Onu izin katmanına almak Android'in
      // `resumed` yeniden denemesiyle diyalog döngüsü kurabilir; cihazda
      // ölçülmeden değiştirilmedi. Bu test Android açık kalemi (B11)
      // kapatılırken bilinçli güncellensin diye var.
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      expect(kameraIzniReddi('CameraAccessDenied'), isFalse);
      expect(kameraIzniReddi('IOError'), isFalse);
    });
  });

  group('uygulamaAyarlariniAc', () {
    test('uygulamanın kendi Ayarlar adresini açar', () async {
      final acici = _SahteAcici();
      expect(await uygulamaAyarlariniAc(acici: acici.ac), isTrue);
      expect(acici.acilanlar, [Uri.parse('app-settings:')]);
    });

    test("açılış fırlatırsa hata yutulur, Crashlytics'e sahte FATAL gitmez",
        () async {
      // Yutulmayan hata `onPressed`'in Future'ından `PlatformDispatcher
      // .onError`'a çıkar; `main.dart` onu release'de FATAL diye yazar.
      final sonuc = await uygulamaAyarlariniAc(
          acici: (_) async => throw StateError('açılamadı'));
      expect(sonuc, isFalse);
    });

    test("kısayol yalnız iOS'ta", () {
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      expect(ayarlarKisayoluVar, isTrue);
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      expect(ayarlarKisayoluVar, isFalse);
    });
  });

  group('yüz okuma: kamera izni katmanı', () {
    testWidgets('iOS: asıl eylem Ayarlar, yeniden deneme ikincil',
        (tester) async {
      final acici = _SahteAcici();
      var yeniden = 0;
      await tester.pumpWidget(_sar(YuzKameraEngeli(
        izinYok: true,
        onYenidenDene: () => yeniden++,
        ayarlarAcici: acici.ac,
      )));

      expect(find.text(_tr.faceCameraDenied), findsOneWidget);
      expect(find.text(_tr.faceCameraDeniedHint), findsOneWidget);
      final ayarlar = find.widgetWithText(FilledButton, _tr.openSystemSettings);
      expect(ayarlar, findsOneWidget);

      await tester.tap(ayarlar);
      await tester.pump();
      expect(acici.acilanlar, [Uri.parse('app-settings:')]);
      expect(yeniden, 0, reason: 'Ayarlar düğmesi yeniden denemeyi tetiklemez');

      final tekrar = find.widgetWithText(TextButton, _tr.faceOpenSettings);
      expect(tekrar, findsOneWidget);
      await tester.tap(tekrar);
      await tester.pump();
      expect(yeniden, 1);
    }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

    testWidgets('Android: izin katmanı eskisi gibi — Ayarlar düğmesi yok',
        (tester) async {
      final acici = _SahteAcici();
      var yeniden = 0;
      await tester.pumpWidget(_sar(YuzKameraEngeli(
        izinYok: true,
        onYenidenDene: () => yeniden++,
        ayarlarAcici: acici.ac,
      )));

      expect(find.text(_tr.openSystemSettings), findsNothing);
      expect(find.byType(TextButton), findsNothing);
      expect(find.text(_tr.faceCameraDeniedHint), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, _tr.faceOpenSettings));
      await tester.pump();
      expect(yeniden, 1);
      expect(acici.acilanlar, isEmpty);
    }, variant: TargetPlatformVariant.only(TargetPlatform.android));

    testWidgets('iOS arıza katmanında Ayarlar YOK — izin sorunu değil',
        (tester) async {
      var yeniden = 0;
      await tester.pumpWidget(_sar(YuzKameraEngeli(
        izinYok: false,
        onYenidenDene: () => yeniden++,
      )));

      expect(find.text(_tr.faceDetectFailed), findsOneWidget);
      expect(find.text(_tr.openSystemSettings), findsNothing);
      expect(find.text(_tr.faceCameraDeniedHint), findsNothing);
      await tester.tap(find.widgetWithText(FilledButton, _tr.faceRetake));
      await tester.pump();
      expect(yeniden, 1);
    }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));
  });

  group('rehber: izin kartı', () {
    /// Rehber ekranı, izin reddedilmiş eşleşmeyle. Profil boş: ret kartı
    /// kullanıcı adına hiç bakmıyor, Firebase'e gitmesin diye yine de sabit.
    Future<({_SahteAcici acici, int Function() calisma})> rehber(
        WidgetTester tester) async {
      final acici = _SahteAcici();
      var calisma = 0;
      await tester.pumpWidget(_sar(ContactsScreen(ayarlarAcici: acici.ac),
          overrides: [
            contactMatchesProvider.overrideWith((ref) async {
              calisma++;
              return const ContactMatchResult(
                  blocker: ContactMatchBlocker.izinYok);
            }),
            profileProvider.overrideWith((ref) => Stream.value(null)),
          ]));
      await tester.pump();
      await tester.pump();
      return (acici: acici, calisma: () => calisma);
    }

    testWidgets('iOS: Ayarlar açılıyor, "Tekrar dene" ikincil kalıyor',
        (tester) async {
      final r = await rehber(tester);
      expect(find.text(_tr.contactMatchPermTitle), findsOneWidget);

      final ayarlar = find.widgetWithText(GoldButton, _tr.openSystemSettings);
      expect(ayarlar, findsOneWidget);
      await tester.tap(ayarlar);
      await tester.pump();
      expect(r.acici.acilanlar, [Uri.parse('app-settings:')]);

      final once = r.calisma();
      await tester.tap(find.widgetWithText(TextButton, _tr.contactMatchRetry));
      await tester.pump();
      await tester.pump();
      expect(r.calisma(), once + 1,
          reason: 'tekrar dene eşleşmeyi yeniden koşturur');
    }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

    testWidgets('Android: kart eskisi gibi — yalnız "Tekrar dene"',
        (tester) async {
      final r = await rehber(tester);
      expect(find.text(_tr.openSystemSettings), findsNothing);
      expect(find.byType(TextButton), findsNothing);

      final once = r.calisma();
      await tester.tap(find.widgetWithText(GoldButton, _tr.contactMatchRetry));
      await tester.pump();
      await tester.pump();
      expect(r.calisma(), once + 1);
      expect(r.acici.acilanlar, isEmpty);
    }, variant: TargetPlatformVariant.only(TargetPlatform.android));
  });
}
