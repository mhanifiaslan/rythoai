// Bildirim izni akışı bekçileri (OT3).
//
// Kusurun kökü SIRAydı: bayrak istekten ÖNCE yazılıyordu — kullanıcı OS
// diyaloğunu kapatınca (ya da istek düşünce) uygulama BİR DAHA HİÇ
// sormuyordu. `ensureNotificationPermissionAsked` sırayı tek yerde
// sabitler: önce iste, bayrağı ancak istek TAMAMLANINCA yaz.
import 'package:flutter_test/flutter_test.dart';
import 'package:rytho/core/notifications.dart';
import 'package:rytho/features/onboarding/onboarding_wizard.dart'
    show kOnboardingSteps;
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('istek bayraktan ÖNCE koşar; bayrak sonra yazılır', () async {
    SharedPreferences.setMockInitialValues({});
    final sira = <String>[];
    await ensureNotificationPermissionAsked(requester: () async {
      // İstek anında bayrak HENÜZ yazılmamış olmalı.
      sira.add('istek');
      expect(await notificationPromptShown(), isFalse);
      return IzinSonucu.verildi;
    });
    sira.add('bitti');
    expect(sira, ['istek', 'bitti']);
    expect(await notificationPromptShown(), isTrue);
  });

  test('istek düşerse bayrak YAZILMAZ — sonraki fırsatta yeniden sorulur',
      () async {
    SharedPreferences.setMockInitialValues({});
    await expectLater(
        ensureNotificationPermissionAsked(
            requester: () async => throw StateError('os hatası')),
        throwsStateError);
    // Eski davranış burada bayrağı yazmıştı: kullanıcı sonsuza dek
    // bildirimsiz kalıyordu.
    expect(await notificationPromptShown(), isFalse);
  });

  // Senaryo 99 (test-raporu): "sonraki açılışta yeniden sorulur". Bayrak
  // her dönüşte yazılıyordu; OS diyaloğu hiç açılmadan dönen istek de
  // "soruldu" sayılıyor ve ana ekrandaki ikinci şans hiç çalışmıyordu.
  test('soru SORULAMADIYSA bayrak yazılmaz — ikinci şans yaşar', () async {
    SharedPreferences.setMockInitialValues({});
    await ensureNotificationPermissionAsked(
        requester: () async => IzinSonucu.sorulamadi);
    expect(await notificationPromptShown(), isFalse);
  });

  test('ret de bir KARAR: bayrak yazılır, bir daha sorulmaz', () async {
    SharedPreferences.setMockInitialValues({});
    await ensureNotificationPermissionAsked(
        requester: () async => IzinSonucu.reddedildi);
    expect(await notificationPromptShown(), isTrue);
  });

  test('ikinci çağrı no-op: istek bir daha koşmaz', () async {
    SharedPreferences.setMockInitialValues(
        {'notificationPermissionAsked': true});
    var cagri = 0;
    await ensureNotificationPermissionAsked(requester: () async {
      cagri++;
      return IzinSonucu.verildi;
    });
    expect(cagri, 0);
  });

  // K6 (2026-10-10): telefon sihirbazdan çıktı — rehber eşleşmesi kurulumun
  // işi değil, numara Çevrem'de ihtiyaç anında ve Giriş yöntemleri'nde
  // doğrulanır. Altı adım, hiçbiri atlanamaz; bildirim son adım ve OS'a
  // yalnız "Haber ver" seçilince sorulur.
  test('sihirbaz adım sözleşmesi (K6): altı adım, telefon yok', () {
    expect(kOnboardingSteps, [
      'welcome', 'date', 'time', 'place', 'gender', 'notify',
    ]);
  });
}
