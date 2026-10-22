// iOS bildirim bekçileri (K3-bildirim turu: U11, U14, U54).
//
// Üçü de derleme ve simülatörde görünmeyen, yalnız gerçek cihazda ortaya
// çıkan kusurlar:
// - U11: yerel bildirim kurulumu girişin hemen ardından sistem izin
//   diyaloğunu açıyordu; iOS bir kez sorar, refleks ret kalıcıdır.
// - U14: uygulama açıkken gelen push iOS'ta hiç görünmüyordu (bildirim
//   merkezinin delegesi firebase_messaging, yerel bildirime "hiçbiri"
//   diyordu).
// - U54: APNs jetonu gelmeden `getToken` iOS'ta fırlatıyordu.
//
// Firebase ve bildirim eklentileri test ortamında yok; davranış test
// dikişleriyle, bağlantı noktaları kaynak metniyle sabitleniyor (aynı desen:
// face_ariza_kanit_test.dart).
import 'dart:io';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rytho/core/notifications.dart';

/// Satır sonu normalize edilir ve TAM SATIR yorumları atılır.
///
/// Bir şeyin YOKLUĞUNU arayan bekçi, onu ANLATAN yorumu görmemeli — bu depoda
/// iki kez patlamış bir tuzak. Burada AppDelegate'te `UNUserNotificationCenter`
/// yokluğu aranıyor ve gerekçesini anlatan bir yorum yarın oraya yazılabilir.
String _yorumsuz(String yol) => File(yol)
    .readAsStringSync()
    .replaceAll('\r\n', '\n')
    .split('\n')
    .where((s) => !s.trimLeft().startsWith('//'))
    .join('\n');

const _mesaj = RemoteMessage(
  messageId: 'm1',
  notification: RemoteNotification(title: 'Rytho', body: 'Okuman hazır'),
  data: {'type': 'daily', 'route': 'story'},
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  group('U11 — izin diyaloğu girişte açılmaz', () {
    test('Darwin ayarı hiçbir izni istemiyor', () {
      final ios = yerelBildirimAyarlari.iOS!;
      expect(ios.requestAlertPermission, isFalse);
      expect(ios.requestBadgePermission, isFalse);
      expect(ios.requestSoundPermission, isFalse);
      expect(ios.requestProvisionalPermission, isFalse);
      expect(ios.requestCriticalPermission, isFalse);
      expect(ios.requestProvidesAppNotificationSettings, isFalse);
    });

    test('sunum bayraklarına dokunulmadı', () {
      final ios = yerelBildirimAyarlari.iOS!;
      expect(
          [
            ios.defaultPresentAlert,
            ios.defaultPresentBadge,
            ios.defaultPresentSound,
            ios.defaultPresentBanner,
            ios.defaultPresentList,
          ],
          everyElement(isTrue));
    });

    test('kanala giden initialize çağrısında izin isteği yok', () async {
      // Eklentinin yerel tarafı üç bayrak da kapalıysa diyalog açmadan
      // dönüyor (`requestPermissionsImpl`); kanıt, telden geçen argümanlar.
      const kanal =
          MethodChannel('dexterous.com/flutter/local_notifications');
      final cagrilar = <MethodCall>[];
      final haberci =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      haberci.setMockMethodCallHandler(kanal, (cagri) async {
        cagrilar.add(cagri);
        return false;
      });
      addTearDown(() => haberci.setMockMethodCallHandler(kanal, null));

      await IOSFlutterLocalNotificationsPlugin()
          .initialize(settings: yerelBildirimAyarlari.iOS!);

      final kurulum = cagrilar.singleWhere((c) => c.method == 'initialize');
      final arguman = (kurulum.arguments as Map).cast<String, Object?>();
      for (final anahtar in const [
        'requestAlertPermission',
        'requestBadgePermission',
        'requestSoundPermission',
        'requestProvisionalPermission',
        'requestCriticalPermission',
        'requestProvidesAppNotificationSettings',
      ]) {
        expect(arguman[anahtar], isFalse, reason: anahtar);
      }
      expect(cagrilar.where((c) => c.method == 'requestPermissions'), isEmpty);
    });

    test('kurulum bu ayarı kullanıyor; varsayılan Darwin yapıcısı yok', () {
      final kaynak = _yorumsuz('lib/core/notifications.dart');
      expect(kaynak, contains('settings: yerelBildirimAyarlari,'));
      expect(kaynak, isNot(contains('DarwinInitializationSettings()')),
          reason: 'varsayılan yapıcı üç izni de true getirir');
    });
  });

  group('U14 — ön plan push\'u iOS\'ta FCM gösterir', () {
    test('iOS: FCM sunum seçenekleri alert + badge + sound, bir kez', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      final cagrilar = <Map<String, bool>>[];
      await iosOnPlanSunumunuAc(ayarla: (
          {required bool alert, required bool badge, required bool sound}) async {
        cagrilar.add({'alert': alert, 'badge': badge, 'sound': sound});
      });
      expect(cagrilar, [
        {'alert': true, 'badge': true, 'sound': true},
      ]);
    });

    test('Android: FCM sunum seçeneğine hiç dokunulmaz', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      var cagri = 0;
      await iosOnPlanSunumunuAc(ayarla: (
          {required bool alert, required bool badge, required bool sound}) async {
        cagri++;
      });
      expect(cagri, 0);
    });

    test('ayar fırlatırsa yutulur — çağıran beklemiyor', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      await expectLater(
          iosOnPlanSunumunuAc(ayarla: (
                  {required bool alert,
                  required bool badge,
                  required bool sound}) async =>
              throw PlatformException(code: 'kanal-yok')),
          completes);
    });

    test('iOS: ön plan mesajı YEREL bildirim doğurmaz (çift banner olurdu)',
        () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      final gosterilen = <RemoteMessage>[];
      await onPlanMesajiniIsle(_mesaj, goster: (m) async => gosterilen.add(m));
      expect(gosterilen, isEmpty);
    });

    test('Android: ön plan mesajı yerel bildirimle gösterilir — değişmedi',
        () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final gosterilen = <RemoteMessage>[];
      await onPlanMesajiniIsle(_mesaj, goster: (m) async => gosterilen.add(m));
      expect(gosterilen, [same(_mesaj)]);
    });

    test('kurulum sırası: önce FCM sunumu, sonra ön plan dinleyicisi', () {
      final kaynak = _yorumsuz('lib/core/notifications.dart');
      final sunum = kaynak.indexOf('await iosOnPlanSunumunuAc();');
      final dinleyici =
          kaynak.indexOf('FirebaseMessaging.onMessage.listen(onPlanMesajiniIsle);');
      expect(sunum, greaterThan(0));
      expect(dinleyici, greaterThan(sunum));
      expect(kaynak, isNot(contains('onMessage.listen(_showForeground)')),
          reason: 'iOS dalını atlayan doğrudan bağlantı çift banner üretir');
    });

    test('dokunuş yolu değişmedi: onMessageOpenedApp + getInitialMessage', () {
      // iOS'ta FCM'in gösterdiği banner'a dokunuş delegenin
      // didReceiveNotificationResponse'undan bu iki yola geliyor.
      final kaynak = _yorumsuz('lib/core/notifications.dart');
      expect(
          kaynak,
          contains('FirebaseMessaging.onMessageOpenedApp\n'
              '      .listen((mesaj) => _bildirimAcildi(mesaj, onSelectTab, onIntent));'));
      expect(kaynak,
          contains('if (ilk != null) _bildirimAcildi(ilk, onSelectTab, onIntent);'));
    });

    test('AppDelegate bildirim merkezi delegesini SAHİPLENMİYOR', () {
      // Sahiplenirse `willPresent` iki eklentiye de gider ve ikisi de aynı,
      // bir kez çağrılması gereken tamamlayıcıyı çağırır (denetimin
      // beklediği sonuç çift banner). Bu turun düzeltmesi tek delegeye,
      // firebase_messaging'e dayanıyor.
      final kaynak = _yorumsuz('ios/Runner/AppDelegate.swift');
      expect(kaynak, isNot(contains('UNUserNotificationCenter')));
    });
  });

  group('U54 — iOS\'ta APNs jetonu yokken getToken çağrılmaz', () {
    test('iOS, APNs yok: null döner, FCM jetonu İSTENMEZ', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      var fcm = 0;
      final jeton = await cihazFcmJetonu(
        apnsJetonu: () async => null,
        fcmJetonu: () async {
          fcm++;
          return 'fcm';
        },
      );
      expect(jeton, isNull);
      expect(fcm, 0);
    });

    test('iOS, APNs var: FCM jetonu döner', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      final jeton = await cihazFcmJetonu(
        apnsJetonu: () async => 'apns',
        fcmJetonu: () async => 'fcm',
      );
      expect(jeton, 'fcm');
    });

    test('Android: APNs sorulmaz, eski çağrı aynen koşar', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      var apns = 0;
      final jeton = await cihazFcmJetonu(
        apnsJetonu: () async {
          apns++;
          return null;
        },
        fcmJetonu: () async => 'fcm',
      );
      expect(jeton, 'fcm');
      expect(apns, 0);
    });

    test('senkron yolu APNs kapısından geçiyor', () {
      final kaynak = _yorumsuz('lib/core/notifications.dart');
      expect(kaynak, contains('final token = await cihazFcmJetonu();'));
      expect(kaynak, isNot(contains('FirebaseMessaging.instance.getToken()')),
          reason: 'doğrudan çağrı iOS kapısını atlar');
    });
  });
}
