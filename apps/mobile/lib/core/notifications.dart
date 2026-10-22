import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart'
    show StateNotifier, StateNotifierProvider;
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../features/shell/app_shell.dart' show shellTabProvider;
import 'analytics.dart';
import 'providers.dart';

/// Bildirim izni, cihaz bilgisi senkronu ve tercihler.
///
/// Bildirim metni **sunucuda** üretiliyor (backend/services/notification_service.py),
/// bu yüzden sunucunun üç şeyi bilmesi gerekir ve üçü de profile yazılır:
///
/// 1. **FCM token** — nereye gönderileceği.
/// 2. **Saat dilimi** — bildirimin kullanıcının sabahına denk gelmesi için.
///    Doğum şehri kullanılamaz; kişi doğduğu yerde yaşamıyor olabilir.
/// 3. **Dil** — sunucu istek başlığı görmediği için `Accept-Language` burada
///    işe yaramaz. Dilin yazıcısı BURASI DEĞİL: `core/language_sync.dart`
///    (PBZ) — buradan da yazıldığı dönemde soğuk açılışta iki yazım
///    yarışıyor ve profil dili gidip geliyordu.
///
/// İzin isteme zamanı da bilinçli: uygulama ilk açılışta değil, kullanıcı
/// onboarding'i bitirip ilk değeri gördükten sonra sorulur. Değer görmeden
/// sorulan izin reddediliyor ve bir daha sorulamıyor.

/// Bildirim tercihleri — profildeki alanların yazılabilir görünümü.
class NotificationPrefs {
  const NotificationPrefs({
    this.daily = true,
    this.streak = true,
    this.friends = true,
    this.quietFrom = 22,
    this.quietTo = 8,
  });

  final bool daily;
  final bool streak;
  final bool friends;
  final int quietFrom;
  final int quietTo;

  factory NotificationPrefs.fromProfile(Map<String, dynamic>? profile) {
    final p = profile ?? const {};
    return NotificationPrefs(
      // Alan yoksa AÇIK sayılır; sunucu tarafı da aynı varsayımı yapıyor.
      daily: p['notifyDaily'] != false,
      streak: p['notifyStreak'] != false,
      friends: p['notifyFriends'] != false,
      quietFrom: (p['quietFrom'] as num?)?.toInt() ?? 22,
      quietTo: (p['quietTo'] as num?)?.toInt() ?? 8,
    );
  }

  bool get quietDisabled => quietFrom == quietTo;
}

final notificationPrefsProvider = Provider<NotificationPrefs>((ref) {
  return NotificationPrefs.fromProfile(ref.watch(profileProvider).value);
});

Future<void> setNotificationPref(String field, Object? value) async {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) return;
  await FirebaseFirestore.instance
      .collection('users')
      .doc(uid)
      .set({field: value}, SetOptions(merge: true));
}

/// Cihazın IANA saat dilimi ("Europe/Istanbul").
///
/// `DateTime.now().timeZoneName` kullanılamaz: platforma göre "+03" ya da
/// "GMT+03:00" gibi kısaltmalar döner ve sunucudaki ZoneInfo bunları
/// çözemez. Ayrıca ham UTC farkı da yeterli değil — yaz saati değişiminde
/// uygulamayı açmayan kullanıcının bildirimi bir saat kayardı.
Future<String?> _deviceTimezone() async {
  try {
    // flutter_timezone 5.x düz string değil TimezoneInfo döndürüyor;
    // sunucunun beklediği IANA adı `identifier` alanında.
    final bilgi = await FlutterTimezone.getLocalTimezone();
    return bilgi.identifier;
  } catch (e) {
    debugPrint('Saat dilimi okunamadı: $e');
    return null;
  }
}

/// Sunucunun bildirim gönderebilmesi için gereken cihaz bilgisini yazar:
/// yalnız saat dilimi + FCM token.
///
/// Her açılışta çağrılır: token yenilenebilir, kullanıcı seyahat edebilir,
/// yaz saati değişebilir. Dil BURADAN YAZILMAZ — tek yazıcısı
/// `LanguageSync` (language_sync.dart); ikinci bir yazıcı yarışı geri
/// getirir.
Future<void> syncNotificationContext() async {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) return;

  final guncelleme = <String, dynamic>{};

  final tz = await _deviceTimezone();
  if (tz != null && tz.isNotEmpty) guncelleme['timezone'] = tz;

  try {
    // Jeton alınamazsa sessizce geçilir: `onTokenRefresh`
    // ([listenForTokenRefresh]) ya da bir sonraki açılış yazar.
    final token = await cihazFcmJetonu();
    if (token != null) {
      guncelleme['fcmToken'] = token;
      // JT: jetonun bu hesaba EN SON ne zaman yazıldığı — sunucu aynı
      // jetonu taşıyan hesaplardan en yenisine gönderir (bkz.
      // api/notify.py `_jeton_sahipleri`).
      guncelleme['fcmTokenAt'] = FieldValue.serverTimestamp();
    }
  } catch (e) {
    debugPrint('FCM token alınamadı: $e');
  }

  if (guncelleme.isEmpty) return;
  try {
    await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .set(guncelleme, SetOptions(merge: true));
  } catch (e) {
    debugPrint('Bildirim bağlamı yazılamadı: $e');
  }
}

/// Cihazın FCM jetonu; iOS'ta APNs jetonu henüz gelmediyse `null` (U54).
///
/// firebase_messaging'in Dart kanalı iOS'ta `getToken`'dan önce APNs
/// jetonuna bakıyor ve yoksa `apns-token-not-set` FIRLATIYOR
/// (firebase_messaging_platform_interface 4.9.2
/// `method_channel_messaging.dart` `_APNSTokenCheck`). İlk kurulumda APNs
/// jetonu açılıştan bir süre sonra gelebildiği için bu olağan durum hata
/// yolundan geçiyordu. Jetonu o anda zorlamanın yolu yok; APNs jetonu
/// gelince FCM jetonu `onTokenRefresh` ile yazılır (denetimin kaynak
/// okuması, "Doğrulanmış olanlar"). Bu yolun cihazda ilk kurulumda
/// `fcmToken` yazdığı henüz ÖLÇÜLMEDİ — U54 o yüzden açık.
///
/// Android'de APNs yok; oraya hiç bakılmaz, eski çağrı aynen koşar.
/// İki kanca test dikişidir.
Future<String?> cihazFcmJetonu({
  Future<String?> Function()? apnsJetonu,
  Future<String?> Function()? fcmJetonu,
}) async {
  if (defaultTargetPlatform == TargetPlatform.iOS) {
    final apns =
        await (apnsJetonu ?? FirebaseMessaging.instance.getAPNSToken)();
    if (apns == null) return null;
  }
  return (fcmJetonu ?? FirebaseMessaging.instance.getToken)();
}

const String _kPermissionAskedKey = 'notificationPermissionAsked';

/// İzin daha önce istendi mi?
///
/// İşletim sistemi izni zaten bir kez soruyor; bu bayrak bizim tarafımızda
/// gereksiz çağrıyı ve her açılışta senkron denemesini engelliyor.
Future<bool> notificationPromptShown() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kPermissionAskedKey) ?? false;
  } catch (_) {
    // Okunamazsa sormuş gibi davran: kullanıcıyı her açılışta izin
    // diyaloğuyla karşılaştırma riski, bir kez sormamaktan kötü.
    return true;
  }
}

Future<void> markNotificationPromptShown() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kPermissionAskedKey, true);
  } catch (_) {}
}

/// İzin isteğinin ÜÇ sonucu — `bool` yetmiyordu.
///
/// NEDEN (test-raporu senaryo 99, ölçüldü 2026-10-10): istek her yolda bool
/// dönüyor ve [ensureNotificationPermissionAsked] her dönüşte bayrağı
/// yazıyordu. OS diyaloğu hiç AÇILMADAN düşen istek (`notDetermined` dönen
/// ya da fırlatan çağrı) da "soruldu" sayılıyor, ana ekrandaki ikinci şans
/// hiç çalışmıyordu. Kullanıcının bir KARAR verdiği iki hâl bayrak yazar;
/// soru sorulamadıysa bayrak yazılmaz ve sonraki açılışta yeniden sorulur.
enum IzinSonucu { verildi, reddedildi, sorulamadi }

/// İzni GEREKİYORSA ister — sıra hatasının tek yerde onarımı (OT3).
///
/// Eski çağıranlar bayrağı istekten ÖNCE yazıyordu: kullanıcı OS
/// diyaloğunu kapatırsa (istek yarıda düşerse bile) bayrak yazılmış
/// oluyor ve uygulama BİR DAHA HİÇ sormuyordu — "bildirim gelmiyor"
/// şikâyetlerinin sessiz köklerinden biri. Artık: önce istenir, bayrak
/// ANCAK kullanıcı bir karar verdiyse ([IzinSonucu.verildi] ya da
/// [IzinSonucu.reddedildi]) yazılır; soru sorulamadıysa ya da istek
/// fırlatırsa bayrak yazılmaz ve bir sonraki fırsatta yeniden denenir.
///
/// [requester] test dikişidir; üretimde [requestNotificationPermission].
Future<void> ensureNotificationPermissionAsked(
    {Future<IzinSonucu> Function()? requester}) async {
  if (await notificationPromptShown()) return;
  final sonuc = await (requester ?? requestNotificationPermission)();
  if (sonuc == IzinSonucu.sorulamadi) return;
  await markNotificationPromptShown();
}

/// Bildirim iznini ister ve sonucu döndürür.
///
/// Ayrı bir fonksiyon: izin isteme ANI ürün kararıdır (bkz. sınıf açıklaması)
/// ve senkronizasyondan bağımsız tetiklenir. İstisna ve `notDetermined`
/// (diyalog açılmadı) → [IzinSonucu.sorulamadi]: ikisi de karar değildir.
Future<IzinSonucu> requestNotificationPermission() async {
  try {
    final ayar = await FirebaseMessaging.instance.requestPermission();
    final durum = ayar.authorizationStatus;
    if (durum == AuthorizationStatus.notDetermined) {
      return IzinSonucu.sorulamadi;
    }
    final verildi = durum == AuthorizationStatus.authorized ||
        durum == AuthorizationStatus.provisional;
    // İzin oranı ölçülmezse bildirim sisteminin işe yarayıp yaramadığı
    // bilinemez: gönderim başarılı görünür ama kimseye ulaşmıyordur.
    Analytics.notificationPermission(granted: verildi);
    if (verildi) await syncNotificationContext();
    return verildi ? IzinSonucu.verildi : IzinSonucu.reddedildi;
  } catch (e) {
    debugPrint('Bildirim izni istenemedi: $e');
    return IzinSonucu.sorulamadi;
  }
}

/// İşletim sistemi düzeyindeki bildirim izni (ayar ekranı bandı için).
///
/// `autoDispose`: izin durumu uygulama dışında değişir (kullanıcı sistem
/// ayarına gidip döner); izleyen ekran kapanınca önbellek düşer ve bir
/// sonraki açılış taze okur. Oturum boyu önbellek, düzeltilmiş izni
/// "hâlâ kapalı" gösterirdi (CLAUDE.md §5 Riverpod notu).
final osBildirimDurumuProvider =
    FutureProvider.autoDispose<AuthorizationStatus>((ref) async {
  final ayar = await FirebaseMessaging.instance.getNotificationSettings();
  return ayar.authorizationStatus;
});

/// Token yenilendiğinde profili güncel tutar.
///
/// FCM token'ı kendiliğinden dönebiliyor; dinlenmezse kullanıcı sessizce
/// bildirim almaz hâle gelir ve bunu kimse fark etmez.
void listenForTokenRefresh() {
  FirebaseMessaging.instance.onTokenRefresh.listen((token) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      await FirebaseFirestore.instance.collection('users').doc(uid).set({
        'fcmToken': token,
        'fcmTokenAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('Yenilenen token yazılamadı: $e');
    }
  });
}

/// Çıkışta cihaz jetonunu bu hesaptan söker (JT-turu).
///
/// Cihazda ölçülen kusur: aynı telefonda hesap değiştirilince eski hesabın
/// profilindeki `fcmToken` duruyordu — o telefona İKİ hesabın push'u
/// gidiyordu (biri Türkçe biri İngilizce). İki adım, ikisi de best-effort:
///
/// 1. Profildeki `fcmToken` / `fcmTokenAt` silinir (kimlik hâlâ varken —
///    çıkıştan SONRA çağrılsa kural yazımı reddeder).
/// 2. FCM jetonu geçersizlenir (`deleteToken`): profile yazamadığımız
///    başka bir hesapta kalsa bile o jetona push artık ulaşmaz; sunucu
///    bayat jetonu temizler. Bir sonraki giriş yeni jeton alır
///    ([syncNotificationContext]).
///
/// Çıkışı GECİKTİRMEZ: her adım ≤[timeout], hata yutulur. İki kanca test
/// dikişidir.
Future<void> forgetPushToken(
  String uid, {
  Future<void> Function(String uid)? clearProfile,
  Future<void> Function()? deleteDeviceToken,
  Duration timeout = const Duration(seconds: 3),
}) async {
  try {
    await (clearProfile ?? _jetonuProfildenSil)(uid).timeout(timeout);
  } catch (e) {
    debugPrint('Çıkışta jeton profilden silinemedi: $e');
  }
  try {
    await (deleteDeviceToken ?? FirebaseMessaging.instance.deleteToken)()
        .timeout(timeout);
  } catch (e) {
    debugPrint('Çıkışta FCM jetonu geçersizlenemedi: $e');
  }
}

Future<void> _jetonuProfildenSil(String uid) =>
    FirebaseFirestore.instance.collection('users').doc(uid).update({
      'fcmToken': FieldValue.delete(),
      'fcmTokenAt': FieldValue.delete(),
    });

// ---------------------------------------------------------------------------
// Ön plan bildirimi
//
// Android'de FCM'in `notification` yükü YALNIZCA uygulama arka plandayken
// sistem tepsisinde gösterilir. Uygulama açıkken bildirim `onMessage`'a
// teslim edilir ve göstermek uygulamanın işidir — bu yapılmazsa bildirim
// sessizce düşer ve kullanıcı hiçbir şey görmez.
//
// Kanal ayrıca arka plan için de önemli: Android 8+ bildirimi bir kanala
// bağlar ve FCM'in varsayılan kanalı "default" öneme sahiptir. Yüksek
// öncelikli kanal olmadan bildirim ekranın üstünde belirmez, sessizce
// tepsiye düşer.
//
// iOS'ta ön plan banner'ını YEREL bildirim değil FCM'in kendisi çıkarır
// (U14, bkz. [iosOnPlanSunumunuAc]); bu bölümün yerel gösterimi yalnız
// Android içindir.
// ---------------------------------------------------------------------------

const AndroidNotificationChannel _kChannel = AndroidNotificationChannel(
  'rytho_default',
  'Rytho',
  description: 'Günlük okuma, seri hatırlatması ve arkadaş tepkileri.',
  importance: Importance.high,
);

final FlutterLocalNotificationsPlugin _localNotifications =
    FlutterLocalNotificationsPlugin();

bool _yerelBildirimHazir = false;

/// Yerel bildirim kurulum ayarları.
///
/// iOS'ta üç izin bayrağı KAPALI (U11). `DarwinInitializationSettings`'in
/// varsayılanı üçünü de `true` getiriyor ve flutter_local_notifications
/// 22.2.0 bunu `initialize()` anında sistem diyaloğuna çeviriyor
/// (`FlutterLocalNotificationsPlugin.m` `initialize:` →
/// `requestPermissionsImpl`; üçü de kapalıysa diyalog açmadan döner).
/// `initialize` oturum açılır açılmaz koşuyor ([notificationSyncProvider]),
/// yani diyalog girişin hemen ardından, bildirimlerin neye yarayacağı hiç
/// anlatılmadan çıkıyordu. iOS bir kez sorar; o anki refleks "İzin Verme"
/// kalıcıdır.
///
/// Tek istek yolu [ensureNotificationPermissionAsked] kalır (onboarding'in
/// bildirim adımı ve Gökyüzü'ndeki ilk değer anı). O yol
/// `Analytics.notificationPermission`'ı da yazıyor: diyalog önceden çıkmış
/// olsaydı metrik, diyalog GÖSTERMEYEN bir isteğin sonucunu onboarding
/// cevabı gibi sayardı.
///
/// `defaultPresent*` bayraklarına dokunulmadı: iOS'ta ön plan sunumuna bu
/// eklenti değil, bildirim merkezi delegesi olan firebase_messaging karar
/// veriyor (U14). Android ayarı değişmedi; Darwin ayarı Android'de okunmaz.
const InitializationSettings yerelBildirimAyarlari = InitializationSettings(
  android: AndroidInitializationSettings('@mipmap/ic_launcher'),
  iOS: DarwinInitializationSettings(
    requestAlertPermission: false,
    requestBadgePermission: false,
    requestSoundPermission: false,
  ),
);

/// Yerel bildirim altyapısını kurar (kanal + dokunma yönlendirmesi).
Future<void> _initLocalNotifications(ValueChanged<int> onSelectTab,
    ValueChanged<Map<String, dynamic>> onIntent) async {
  if (_yerelBildirimHazir) return;
  _yerelBildirimHazir = true;

  try {
    await _localNotifications.initialize(
      settings: yerelBildirimAyarlari,
      onDidReceiveNotificationResponse: (yanit) {
        final ham = yanit.payload;
        if (ham == null || ham.isEmpty) return;
        final veri = decodeNotificationPayload(ham);
        onIntent(veri);
        onSelectTab(tabForNotification(veri));
      },
    );

    await _localNotifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(_kChannel);
  } catch (e) {
    debugPrint('Yerel bildirim kurulamadı: $e');
  }
}

/// Ön planda gelen bildirimi ekranda gösterir.
Future<void> _showForeground(RemoteMessage mesaj) async {
  final bildirim = mesaj.notification;
  if (bildirim == null) return;

  final yuk = encodeNotificationPayload(mesaj.data);
  try {
    await _localNotifications.show(
      // Kimlik olarak zaman damgası: aynı anda birden fazla bildirim
      // gelirse birbirinin üstüne yazmasın. 32 bit sınırına sığması için
      // saniye çözünürlüğünde ve mod alınmış.
      id: (DateTime.now().millisecondsSinceEpoch ~/ 1000) % 0x7FFFFFFF,
      title: bildirim.title,
      body: bildirim.body,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          _kChannel.id,
          _kChannel.name,
          channelDescription: _kChannel.description,
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: const DarwinNotificationDetails(),
      ),
      payload: yuk,
    );
  } catch (e) {
    debugPrint('Ön plan bildirimi gösterilemedi: $e');
  }
}

/// Ön planda gelen FCM mesajı: Android'de yerel bildirimle gösterilir,
/// iOS'ta hiçbir şey yapılmaz (U14).
///
/// iOS'ta bildirim merkezinin delegesi firebase_messaging (AppDelegate'te
/// delege satırı yok). Yerel bildirim gönderildiğinde iOS sunumu yine ona
/// soruyordu ve sunum seçeneği kayıtlı değilken cevap "hiçbiri"ydi: banner
/// sessizce atılıyor, Bildirim Merkezi'ne de düşmüyordu. Artık banner'ı FCM
/// gösteriyor ([iosOnPlanSunumunuAc]); burada ayrıca yerel bildirim
/// gönderilseydi İKİ banner çıkardı, çünkü delege kayıtlı seçeneği FCM
/// olmayan bildirime de uyguluyor (firebase_messaging 16.4.3
/// `FLTFirebaseMessagingPlugin.m` `willPresentNotification`). O ikinci
/// banner'a dokunmak da hiçbir yere gitmezdi: delege `gcm.message_id`
/// taşımayan dokunuşu Dart'a iletmiyor.
///
/// [goster] test dikişidir; üretimde yerel gösterim.
Future<void> onPlanMesajiniIsle(RemoteMessage mesaj,
    {Future<void> Function(RemoteMessage mesaj)? goster}) async {
  if (defaultTargetPlatform == TargetPlatform.iOS) return;
  await (goster ?? _showForeground)(mesaj);
}

/// iOS'ta ön plan push'unu FCM'in kendisi göstersin (U14).
///
/// Seçenek firebase_messaging'in iOS delegesinde `NSUserDefaults`'a yazılır
/// ve kalıcıdır; her kurulumda yeniden yazmak zararsız. Bu banner'a dokunuş
/// delegenin `didReceiveNotificationResponse`'undan `onMessageOpenedApp`'e
/// (soğuk açılışta `getInitialMessage`'a) gelir — arka plandaki push'la
/// aynı yol, yönlendirme değişmez.
///
/// Delege satırı AppDelegate'e EKLENMEZ: `FlutterAppDelegate` delege
/// olursa `willPresent` iki eklentiye de iletilir
/// (`FlutterPluginAppLifeCycleDelegate.mm`) ve ikisi de aynı, bir kez
/// çağrılması gereken tamamlayıcıyı çağırır. Denetimin beklediği sonuç çift
/// banner; cihazda ölçülmedi, ölçmeye de gerek yok — bu yol tek delegeyle
/// çalışıyor.
///
/// Hata yutulur: fırlatsaydı [handleNotificationTaps]'in arkasındaki
/// kurulum (ön plan dinleyicisi, dokunuş yolları) hiç koşmazdı ve hata,
/// kimsenin beklemediği bir Future'dan ([notificationSyncProvider])
/// yayında Crashlytics'e FATAL diye düşerdi. [ayarla] test dikişidir.
Future<void> iosOnPlanSunumunuAc({
  Future<void> Function(
          {required bool alert, required bool badge, required bool sound})?
      ayarla,
}) async {
  if (defaultTargetPlatform != TargetPlatform.iOS) return;
  try {
    await (ayarla ??
        FirebaseMessaging
            .instance.setForegroundNotificationPresentationOptions)(
        alert: true, badge: true, sound: true);
  } catch (e) {
    debugPrint('iOS ön plan sunumu ayarlanamadı: $e');
  }
}

/// Ön plan bildirimi yükünü `anahtar=deger` çiftlerine kodlar.
///
/// Değerler URL-kodlu (KA5 onarımı): check-in sorusu serbest metin ve
/// `&`/`=` içerebilir — kodlanmazsa dokunma ayrıştırması sessizce bozulur.
String encodeNotificationPayload(Map<String, dynamic> data) => data.entries
    .map((e) => '${e.key}=${Uri.encodeComponent('${e.value}')}')
    .join('&');

/// [encodeNotificationPayload] ile yazılan yükü geri çözer.
Map<String, dynamic> decodeNotificationPayload(String ham) {
  final veri = <String, dynamic>{};
  for (final parca in ham.split('&')) {
    final i = parca.indexOf('=');
    if (i > 0) {
      var deger = parca.substring(i + 1);
      try {
        deger = Uri.decodeComponent(deger);
      } catch (_) {} // eski biçim kodlanmamış olabilir
      veri[parca.substring(0, i)] = deger;
    }
  }
  return veri;
}

/// Bildirime dokunulduğunda hangi sekmenin açılacağı.
///
/// Sunucu her bildirime `type` alanı koyuyor (daily / checkin / streak /
/// friend). Eşleşmeyen bir tür gelirse ana ekranda kalınır — bilinmeyen bir
/// değer yüzünden uygulama boş bir ekrana düşmemeli.
int tabForNotification(Map<String, dynamic> data) {
  switch (data['type']) {
    case 'friend':
      return 2; // Arkadaşlar
    case 'daily':
    case 'checkin': // sohbet kabuğun üstüne açılır; zemin Gökyüzü kalır
    case 'streak':
    case 'feedback': // GB-turu: yanıt bildirimi yalnız uygulamayı açar
    default:
      return 0; // Gökyüzü
  }
}

// ---------------------------------------------------------------------------
// Dokunuş yönlendirme çözücüsü (BY-turu)
//
// Cihaz bulgusu: "öğle bildirimine tıkladım, sadece uygulama açıldı."
// Sekme atamak yetmiyor — HER bildirim türünün anlamlı bir hedefi olmalı:
// günlük okuma → okumanın kendisi, check-in → soru yazılı sohbet,
// arkadaş/çift ânı → o ilişkinin ekranı. Karar SAF bir fonksiyonda yaşar
// (testli); AppShell ve SkyScreen yalnız uygular.
// ---------------------------------------------------------------------------

enum NotificationRouteKind {
  /// daily + route=signal: ilgili sinyal kartının dayanak sayfası —
  /// sinyaller yüklü olmalı, bu yüzden SkyScreen tüketir.
  signalSheet,

  /// Günlük okumanın kendisi (hikâye): route=story, yedek-daily, streak.
  dailyStory,

  /// Soru yazılı sohbet — ESKİ yol: soru kullanıcının giriş kutusuna
  /// yazılır. Yalnız `cid` taşımayan (eski sunucu) yükler için kalıyor.
  checkinChat,

  /// RYTHO SORDU: soru zaten sohbette Rytho'nun mesajı olarak duruyor;
  /// dokunuş o konuşmayı açar ve kullanıcı CEVAPLAR (SS-turu).
  ///
  /// Ayrım bildirimin TÜRÜNDEN değil gövdesinin biçiminden geliyor:
  /// sunucu, gövdesi soru olan bildirime `route=chat_answer` + `cid`
  /// koyuyor. Yarın başka bir tür de soru sorarsa buraya kendiliğinden
  /// düşer.
  rythoAsks,

  /// Arkadaşla ilişki ekranı (bugün aranıza dokunan gökyüzü).
  friendRelation,

  /// Çevrem kişisiyle ilişki ekranı.
  personRelation,

  /// Yalnız Çevrem sekmesi (davet en üstte / tepki kutusu orada).
  circleTab,

  /// Yalnız ana sekme.
  homeTab,
}

class NotificationRoute {
  const NotificationRoute(this.kind,
      {this.sign, this.friendUid, this.personId, this.question,
      this.questionDate, this.conversationId});

  final NotificationRouteKind kind;
  final String? sign;
  final String? friendUid;
  final String? personId;
  final String? question;
  final String? questionDate;

  /// SS-turu: Rytho'nun sorusunun YAZILI OLDUĞU konuşma.
  final String? conversationId;
}

/// Yükten hedef kararı. Eski sunucu yükleri (route'suz daily, src'siz
/// friend) en yakın anlamlı hedefe düşer — hiçbir tür "yalnız uygulamayı
/// aç"ta bırakılmaz.
NotificationRoute resolveNotificationRoute(Map<String, String> data) {
  switch (data['type']) {
    case 'checkin':
      // Gövde bir SORUysa sunucu onu sohbete zaten yazdı ve konuşmanın
      // kimliğini yolladı: dokunuş o konuşmayı açar, kullanıcı cevaplar.
      // `cid` yoksa eski sunucu yükü demektir — eski davranışa düşülür
      // (soru giriş kutusuna yazılır). Bu dalın türe değil YÜKE bakması
      // bilinçli: yarın başka bir tür de soru sorarsa aynı yoldan geçer.
      final cid = data['cid'];
      if (data['route'] == 'chat_answer' && cid != null && cid.isNotEmpty) {
        return NotificationRoute(NotificationRouteKind.rythoAsks,
            conversationId: cid, question: data['q']);
      }
      return NotificationRoute(NotificationRouteKind.checkinChat,
          question: data['q'], questionDate: data['q_date']);
    case 'daily':
      if (data['route'] == 'signal') {
        return const NotificationRoute(NotificationRouteKind.signalSheet);
      }
      // route=story (yeni yedek yol) ya da route'suz eski yük: bildirim
      // "okuman hazır" diyor — okumanın kendisi açılır.
      return NotificationRoute(NotificationRouteKind.dailyStory,
          sign: data['sign']);
    case 'streak':
      // "Bugün okumanı açmadın" — dokunuş istenen eylemi YAPAR.
      return const NotificationRoute(NotificationRouteKind.dailyStory);
    case 'friend':
      final pid = data['pid'];
      if (pid != null && pid.isNotEmpty) {
        return NotificationRoute(NotificationRouteKind.personRelation,
            personId: pid);
      }
      final uid = data['fromUid'];
      switch (data['src']) {
        case 'midday':
        case 'invite_accepted':
          // Öğle çift ânı / kabul: o ilişkinin ekranı (ölçüm ücretsiz).
          if (uid != null && uid.isNotEmpty) {
            return NotificationRoute(NotificationRouteKind.friendRelation,
                friendUid: uid);
          }
          return const NotificationRoute(NotificationRouteKind.circleTab);
        case 'invite':
        case 'reaction':
        default:
          // Davet isteği ve tepki kutusu Çevrem'de en üstte; eski
          // src'siz yükler de buraya düşer.
          return const NotificationRoute(NotificationRouteKind.circleTab);
      }
    case 'feedback':
      // GB-turu: geri bildirime verilen yanıt. Hedef ekran yok — bildirim
      // gövdesi yanıtın kendisi; dokunuş yalnız uygulamayı açar. Açıkça
      // yazılı olması bilinçli: bilinmeyen-tür yoluna DÜŞMEZ, yarın o yol
      // günlük kaydı/uyarı alırsa bu tür ona karışmaz.
      return const NotificationRoute(NotificationRouteKind.homeTab);
    default:
      return const NotificationRoute(NotificationRouteKind.homeTab);
  }
}

// ---------------------------------------------------------------------------
// Bekleyen bildirim niyeti (KA5)
//
// `deep_links.dart`'taki PendingInvite deseninin ikizi: dokunma anında
// uygulama henüz hazır olmayabilir (soğuk açılış, oturum yüklenmemiş) —
// niyet burada bekler, tüketen ekran hazır olunca işler ve temizler.
// Eskiden dokunma yalnızca sekme numarası atıyordu ve R2-S4'ün "tıklanınca
// ilgili sinyal kartı açılır" vaadi hiç yazılmamıştı.
// ---------------------------------------------------------------------------

class PendingNotification {
  const PendingNotification(this.data);

  final Map<String, String> data;

  String? get type => data['type'];
}

class PendingNotificationIntent extends StateNotifier<PendingNotification?> {
  PendingNotificationIntent() : super(null);

  void set(Map<String, dynamic> data) {
    state = PendingNotification(
        data.map((k, v) => MapEntry(k, v?.toString() ?? '')));
  }

  void clear() => state = null;
}

final pendingNotificationProvider =
    StateNotifierProvider<PendingNotificationIntent, PendingNotification?>(
        (_) => PendingNotificationIntent());

/// Bildirim alımını ve dokunma yönlendirmesini kurar.
///
/// Üç yol da bağlanır, çünkü Android üçünü farklı ele alıyor:
/// - **Ön plan:** sistem hiçbir şey göstermez, biz gösteririz. iOS'ta
///   FCM gösterir ve dokunuş arka plan yolundan gelir (U14).
/// - **Arka plan:** sistem gösterir, dokunma `onMessageOpenedApp`'e gelir.
/// - **Kapalı:** sistem gösterir, dokunma uygulamayı açar ve
///   `getInitialMessage` ile okunur.
Future<void> handleNotificationTaps(ValueChanged<int> onSelectTab,
    ValueChanged<Map<String, dynamic>> onIntent) async {
  await _initLocalNotifications(onSelectTab, onIntent);
  await iosOnPlanSunumunuAc();

  // Ön planda gelen bildirim: Android'de göstermezsek kullanıcı hiçbir şey
  // görmez; iOS'ta FCM zaten gösteriyor.
  FirebaseMessaging.onMessage.listen(onPlanMesajiniIsle);

  // BY-turu onarımı — DÖRDÜNCÜ yol eksikti: ön plandayken gösterdiğimiz
  // YEREL bildirim tepside dururken süreç ölür, kullanıcı sonra dokunursa
  // uygulama SOĞUK açılır ve dokunuş `onDidReceiveNotificationResponse`a
  // DEĞİL buraya düşer. Bağlanmadığı için yük kayboluyordu — "öğle
  // bildirimine tıkladım, sadece uygulama açıldı" cihaz bulgusunun kökü.
  try {
    final acilis =
        await _localNotifications.getNotificationAppLaunchDetails();
    final ham = acilis?.didNotificationLaunchApp == true
        ? acilis!.notificationResponse?.payload
        : null;
    if (ham != null && ham.isNotEmpty) {
      final veri = decodeNotificationPayload(ham);
      Analytics.notificationOpened('${veri['type'] ?? 'unknown'}');
      onIntent(veri);
      onSelectTab(tabForNotification(veri));
    }
  } catch (e) {
    debugPrint('Yerel açılış bildirimi okunamadı: $e');
  }

  try {
    final ilk = await FirebaseMessaging.instance.getInitialMessage();
    if (ilk != null) _bildirimAcildi(ilk, onSelectTab, onIntent);
  } catch (e) {
    debugPrint('Açılış bildirimi okunamadı: $e');
  }

  FirebaseMessaging.onMessageOpenedApp
      .listen((mesaj) => _bildirimAcildi(mesaj, onSelectTab, onIntent));
}

void _bildirimAcildi(RemoteMessage mesaj, ValueChanged<int> onSelectTab,
    ValueChanged<Map<String, dynamic>> onIntent) {
  // Bildirimden dönüş, bu kategoride retention'ın ana ölçüsü.
  Analytics.notificationOpened('${mesaj.data['type'] ?? 'unknown'}');
  // Niyet SEKMEDEN ÖNCE yazılır: tüketen ekran sekme değişimiyle
  // kurulurken niyeti hazır bulmalı.
  onIntent(mesaj.data);
  onSelectTab(tabForNotification(mesaj.data));
}

/// Bildirim altyapısını oturuma bağlar.
///
/// [billingIdentityProvider] ile aynı desen: izlenmezse hiç kurulmaz.
/// Oturum açıldığında cihaz bilgisi (saat dilimi + token) sunucuya yazılır,
/// token yenilemesi dinlenir ve bildirime dokunma yönlendirmesi kurulur.
/// Dil ayrı yolda: `languageSyncListenerProvider` (language_sync.dart) —
/// eskiden burada hem auth hem `localeProvider` dinleyicisi dil yazıyor,
/// soğuk açılışta ikisi yarışıyordu.
final notificationSyncProvider = Provider<void>((ref) {
  var dinleyiciKuruldu = false;

  ref.listen<AsyncValue<User?>>(authStateProvider, (previous, next) {
    final user = next.value;
    if (user == null) return;

    syncNotificationContext();

    if (dinleyiciKuruldu) return;
    dinleyiciKuruldu = true;
    listenForTokenRefresh();
    handleNotificationTaps((tab) {
      ref.read(shellTabProvider.notifier).state = tab;
    }, (veri) {
      ref.read(pendingNotificationProvider.notifier).set(veri);
    });
  }, fireImmediately: true);
});
