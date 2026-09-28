/// Bildirim dili — `users/{uid}.language` alanının TEK yazıcısı (PBZ).
///
/// Bildirim metni sunucuda üretiliyor ve sunucu istek başlığı görmediği
/// için `Accept-Language` oraya ulaşmıyor; dil profile yazılır. Cihazda
/// ölçülen kusur: eski yazıcı (`syncNotificationContext`) soğuk açılışta
/// İKİ kez yazıyordu — auth dinleyicisi tercih daha SharedPreferences'tan
/// yüklenmeden okuyup sistem dilini, tercih yüklenince ikinci dinleyici
/// doğru dili. İkisi de ateşle-unut olduğu için ilk (bayat) yazım çoğu kez
/// SON düşüyor, profil her açılışta `tr`/`en` arasında gidip geliyor ve o
/// günün bildirimleri son yazımın diliyle çıkıyordu.
///
/// Yarış sıralamayla değil yapıyla bitirilir (K5):
/// 1. **Tek yazıcı, promise zinciri:** yazımlar art arda koşar, hiçbir
///    zaman örtüşmez.
/// 2. **Sıra numarası — son niyet kazanır:** kuyruktaki bir yazım sırası
///    geldiğinde daha yeni bir niyet varsa ATLANIR.
/// 3. **`LocaleController.ready` beklenir:** tercih yüklenmeden yazım YOK.
/// 4. **Güdüm `effectiveLocaleProvider`:** arayüzün ve `Accept-Language`ın
///    kullandığı dil — "Sistem" tercihinde telefon dili değişince de yazılır.
///
/// Bu yazım dokümanın DOĞDUĞU yer olduğu için kayıt damgasını da o koyar:
/// `createdAt` onboarding'in son adımını beklerse akışı yarım bırakan
/// kullanıcı panelin kullanıcı listesinde HİÇ görünmez (bkz.
/// [dogumAlanlari], [kayitDamgasi]).
///
/// ⚠️ **Sunucu artık bu doğuma DAYANIYOR** (bulgu B9, 2026-09-28).
/// Backend'in iki "en iyi çaba" aynası — `core/app_gate.remember_build`
/// (`appBuild`) ve `services/search_mirror.ensure` (`emailLower`/…) —
/// `set(merge: true)` yerine `update` kullanıyor, çünkü yaratan bir yazım
/// hesabı silinmiş bir kullanıcıyı diriltiyordu (kimlik jetonu bir saate
/// kadar geçerli kalıyor). `update` var olmayan dokümana YAZMAZ; yani
/// [_firestoreWrite] geciktirilirse, koşullu hâle getirilirse ya da
/// kaldırılırsa o iki ayna sessizce yazılmaz. Sunucuda ikinci bir doğum
/// yolu var (`consent_service.grant_terms_consent`) ama o sihirbazın
/// SONUNDA koşuyor, oturum açılışında değil: sihirbazı yarım bırakan
/// kullanıcıda aynalar HİÇ yazılmaz, bitirende de onaya kadar yazılmaz.
/// Sonucu panelde görünür — arama o kişiyi bulmaz, sürüm kırılımı onu
/// "bilinmiyor" sayar. Hiçbir test patlamaz; ikisi de best-effort.
library;

import 'dart:async' show unawaited;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show Locale;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'locale.dart';
import 'providers.dart';

typedef LanguageWriter = Future<void> Function(String uid, String lang);

/// Kayıt damgası — hesabın Auth'taki GERÇEK oluşma anı; yoksa sunucu damgası.
///
/// Damga UYDURULMAZ. Bu yazımın damgaladığı hesaplar tam da `createdAt` alanı
/// HİÇ olmayanlar: onboarding'i aylar önce yarım bırakmış testçiler. Sunucu
/// damgası tek başına konsaydı böyle bir hesap uygulamayı bir daha açtığında
/// BUGÜN kaydolmuş görünürdü ve backend `core/entitlements`
/// `_trial_remaining` ona SIFIRDAN 3 günlük Rytho+ denemesi açardı — bedava
/// Plus. Auth damgası yoksa alanı hiç yazmamak da çözüm değil: panelin
/// `order_by("createdAt")` listesinde görünmezlik sürerdi, o yüzden sunucu
/// damgasına düşülür.
Object kayitDamgasi(DateTime? authOlusma, Object sunucuDamgasi) =>
    authOlusma ?? sunucuDamgasi;

/// Doğum damgası — dokümanda `createdAt` YOKSA konacak alanlar; varsa boş.
///
/// `users/{uid}` dokümanı oturum açılışında [_firestoreWrite] ile DOĞUYOR,
/// `createdAt` ise onboarding'in SON adımında yazılıyordu: akışı yarım
/// bırakan kullanıcı kayıt tarihsiz kalıyor ve Firestore `order_by` alanı
/// bulunmayan dokümanı sonuç kümesinden düşürdüğü için panelin kullanıcı
/// listesinde HİÇ görünmüyordu — kapalı testte "kim takıldı" sorusu tam da o
/// kişide cevapsız kalıyor. E-posta/ad da aynı sebeple burada konur:
/// operatörün o testçiye ulaşabileceği tek adres o.
///
/// Var olan damga ASLA ezilmez: kayıt tarihi değişmez bir olgu ve 3 günlük
/// deneme penceresi ona bağlı — her oturum açılışında yeniden damgalansa
/// deneme sonsuza dek yenilenirdi.
///
/// [damga] dışarıdan geliyor ki karar Firebase'siz test edilebilsin.
Map<String, Object?> dogumAlanlari(Map<String, Object?>? mevcut, Object damga,
    {String? email, String? displayName}) {
  if ((mevcut ?? const <String, Object?>{})['createdAt'] != null) {
    return const <String, Object?>{};
  }
  return <String, Object?>{
    'createdAt': damga,
    // Null-aware `?`: anahtar HİÇ konmaz. Alanı `null` yazmak sonradan
    // gelen gerçek adı/e-postayı ezerdi.
    'email': ?email,
    'displayName': ?displayName,
  };
}

Future<void> _firestoreWrite(String uid, String lang) async {
  final dokuman = FirebaseFirestore.instance.collection('users').doc(uid);
  final veri = <String, Object?>{'language': lang};
  // Okuma DÜŞERSE dil yazımı yine gider: çevrimdışı ilk açılışta `get`
  // fırlatır ve eski davranış (kuyruğa giren `set`) korunmalı — damga bir
  // sonraki tetikte konur.
  try {
    final oturum = FirebaseAuth.instance.currentUser;
    // Oturum başka bir uid'ye geçmiş olabilir (hesap değişimi): kimlik
    // alanları ancak damgalanan doküman O oturumunsa alınır.
    final kimlik = oturum?.uid == uid ? oturum : null;
    veri.addAll(dogumAlanlari(
        (await dokuman.get()).data(),
        kayitDamgasi(
            kimlik?.metadata.creationTime, FieldValue.serverTimestamp()),
        email: kimlik?.email,
        displayName: kimlik?.displayName));
  } catch (e) {
    debugPrint('Kayıt damgası konamadı (dil yazımı sürer): $e');
  }
  await dokuman.set(veri, SetOptions(merge: true));
}

/// Tek yazıcı, son niyet kazanır.
///
/// [write] test dikişidir; üretimde `users/{uid}.set({'language'}, merge)`.
class LanguageSync {
  LanguageSync({LanguageWriter? write}) : _write = write ?? _firestoreWrite;

  final LanguageWriter _write;

  /// Promise zinciri: her yazım bir öncekinin bitmesini bekler.
  Future<void> _zincir = Future<void>.value();

  /// Sıra numarası: `push` her çağrıda artar; kuyruktaki yazım sırası
  /// geldiğinde kendi numarası güncel değilse (daha yeni niyet var) atlar.
  int _seq = 0;

  /// Son BAŞARIYLA yazılan `'$uid:$lang'` — aynı değer iki kez tetiklenirse
  /// (uid dinleyicisi + dil dinleyicisi aynı anda) tek yazım olur.
  String? _lastKey;

  /// Dili sıraya koyar; dönen future o niyetin (yazılsın ya da atlansın)
  /// işlenmesini bekler. Hata yutulur, zincir kopmaz: bir yazım düşerse
  /// sonraki niyet yine koşar ve `_lastKey` güncellenmediği için aynı değer
  /// yeniden denenir.
  Future<void> push(String uid, String lang) {
    final my = ++_seq;
    _zincir = _zincir.then((_) async {
      if (my != _seq) return; // daha yeni niyet kuyrukta — son niyet kazanır
      final key = '$uid:$lang';
      if (key == _lastKey) return; // çift tetik → tek yazım
      try {
        await _write(uid, lang);
        _lastKey = key;
      } catch (e) {
        debugPrint('Bildirim dili yazılamadı: $e');
      }
    });
    return _zincir;
  }
}

/// Profile yazılacak dil — arayüzün GÖSTERDİĞİ dille AYNI kural.
///
/// Desteklenen dil → kodu; değilse `kSupportedLocales.first` ('tr').
/// ⚠️ 'en' DEĞİL: main.dart'ta `localeResolutionCallback` yok, MaterialApp
/// desteklenmeyen sistem dilinde (ör. 'de') `supportedLocales.first` = TR
/// gösteriyor; backend varsayılanı da 'tr'. Bildirim arayüzden farklı dilde
/// gelmemeli.
String notificationLanguage(Locale effective) {
  final kod = effective.languageCode;
  if (kSupportedLocales.any((l) => l.languageCode == kod)) return kod;
  return kSupportedLocales.first.languageCode;
}

final languageSyncProvider = Provider<LanguageSync>((_) => LanguageSync());

/// Oturumdaki kullanıcının kimliği; oturum yoksa `null`.
final currentUidProvider =
    Provider<String?>((ref) => ref.watch(authStateProvider).value?.uid);

/// Geçerli dili [uid] için sıraya koyar.
///
/// `ready` ÖNCE beklenir, dil ondan SONRA okunur: tercih yüklenmeden okunan
/// dil sistem dili olur ve bayat yazım tam da buradan doğuyordu.
Future<void> syncLanguage(Ref ref, String uid) async {
  await ref.read(localeProvider.notifier).ready;
  final lang = notificationLanguage(ref.read(effectiveLocaleProvider));
  await ref.read(languageSyncProvider).push(uid, lang);
}

/// Dil senkronunu oturuma ve geçerli dile bağlar.
///
/// `notificationSyncProvider` ile aynı desen: izlenmezse hiç kurulmaz
/// (`_Gate` izler). İki tetik var — oturum açılışı ve dil değişimi — ikisi
/// de aynı yazıcıya düşer, bu yüzden aynı anda gelseler de tek yazım olur.
final languageSyncListenerProvider = Provider<void>((ref) {
  ref.listen<String?>(currentUidProvider, (_, uid) {
    if (uid != null) unawaited(syncLanguage(ref, uid));
  }, fireImmediately: true);

  // Locale NESNESİ değil DİL KODU izlenir (apiProvider'daki gerekçe):
  // "tr_TR" → "tr" geçişi sunucu için aynı dil.
  ref.listen<String>(effectiveLocaleProvider.select((l) => l.languageCode),
      (_, _) {
    final uid = ref.read(currentUidProvider);
    if (uid != null) unawaited(syncLanguage(ref, uid));
  });
});
