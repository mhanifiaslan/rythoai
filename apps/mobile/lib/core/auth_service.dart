import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart'
    show ProviderContainer, ProviderScope;
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

import '../l10n/app_localizations.dart';
import 'api.dart' show apiProvider, rythoNavigatorKey;
import 'device_session.dart' show deviceConflictProvider, releaseThisDevice;
import 'notifications.dart' show forgetPushToken;

/// Kimlik doğrulama işlemleri.
///
/// Ekrandan ayrı tutuluyor: giriş akışının kuralları (Apple zorunluluğu,
/// e-posta doğrulaması, sağlayıcı çakışması) arayüz düzeninden bağımsız ve
/// test edilebilir olmalı.

/// Apple ile Giriş bu platformda sunulmalı mı?
///
/// **App Store Guideline 4.8:** üçüncü taraf bir giriş yöntemi (Google)
/// sunuyorsan, iOS'ta Apple ile Giriş'i de sunmak ZORUNLUDUR. Tek başına red
/// sebebidir. Android'de gerekli değil ve göstermek kafa karıştırır.
bool get appleSignInAvailable =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

/// Kayıt için kabul edilebilir şifre mi?
///
/// Firebase'in mutlak alt sınırı 6 karakter; onu tek kural saymak "123456"yı
/// geçerli yapıyordu. Kural bilinçli olarak **uzunluk + çeşitlilik**:
/// 8 karakter ve en az iki farklı karakter sınıfı. Karmaşık bir kalıp
/// dayatmak (büyük harf + rakam + sembol) kullanıcıyı şifresini bir yere
/// yazmaya iter; uzunluk daha çok fayda sağlar.
PasswordIssue? validatePassword(String password) {
  if (password.length < 8) return PasswordIssue.tooShort;

  var siniflar = 0;
  if (RegExp(r'[a-zçğıöşü]').hasMatch(password.toLowerCase()) &&
      RegExp(r'[A-Za-zÇĞİÖŞÜçğıöşü]').hasMatch(password)) {
    siniflar++;
  }
  if (RegExp(r'[0-9]').hasMatch(password)) siniflar++;
  if (RegExp(r'[^A-Za-z0-9ÇĞİÖŞÜçğıöşü]').hasMatch(password)) siniflar++;

  if (siniflar < 2) return PasswordIssue.tooSimple;
  return null;
}

enum PasswordIssue { tooShort, tooSimple }

/// Kullanıcının KENDİ ELİYLE vazgeçtiği giriş denemesi mi?
///
/// Üç sağlayıcı üç ayrı istisna türüyle "vazgeçti" der ve hiçbiri hata
/// değildir. Giriş ekranı eskiden hepsini genel `catch`e düşürüp "Bir şeyler
/// ters gitti" basıyor ve Crashlytics'e yazıyordu — kullanıcı pencereyi
/// kapattı diye hem azar işitiyor hem hata sayacı şişiyordu.
///
/// Kaynaklar kurulu paketlerden ÖLÇÜLDÜ (2026-10-10):
/// * Google — `google_sign_in_platform_interface` 3.1.0 `types.dart:49`
///   `GoogleSignInExceptionCode.canceled`.
/// * Apple — `sign_in_with_apple_platform_interface` 2.0.0
///   `exceptions.dart:116` `AuthorizationErrorCode.canceled`.
/// * Firebase — Android SDK 24.1.0 AAR'ında (`~/.gradle` önbelleğinden
///   açılıp arandı) `ERROR_WEB_CONTEXT_CANCELED` ve `ERROR_USER_CANCELLED`;
///   iOS eklentisi (`firebase_auth` 6.5.6) `FLTFirebaseAuthPlugin.m:543`
///   `canceled`. Dart tarafı (`firebase_auth_platform_interface` 9.0.5,
///   `method_channel/utils/exception.dart:41-44`) `ERROR_` önekini atıp
///   küçük harfe ve tireye çeviriyor: `web-context-canceled`,
///   `user-cancelled`, `canceled`.
///   İki yazım (canceled / cancelled) iki SDK'dan geliyor; literal liste
///   yerine kodun tire ayrılmış parçalarından biri bu iki sözcükten biriyse
///   iptal sayılır — yazımı bu makinede ölçülemeyen iOS SDK sabiti de aynı
///   kurala düşer, uydurulmuş bir literal gerekmez.
bool isAuthCancelled(Object e) {
  if (e is GoogleSignInException) {
    return e.code == GoogleSignInExceptionCode.canceled;
  }
  if (e is SignInWithAppleAuthorizationException) {
    return e.code == AuthorizationErrorCode.canceled;
  }
  if (e is FirebaseAuthException) {
    return e.code
        .split('-')
        .any((parca) => parca == 'canceled' || parca == 'cancelled');
  }
  return false;
}

/// Google ile giriş.
Future<void> signInWithGoogle() async {
  if (kIsWeb) {
    await FirebaseAuth.instance.signInWithPopup(GoogleAuthProvider());
    return;
  }
  final account = await GoogleSignIn.instance.authenticate();
  final auth = account.authentication;
  await FirebaseAuth.instance.signInWithCredential(
    GoogleAuthProvider.credential(idToken: auth.idToken),
  );
}

/// Apple ile giriş.
///
/// Nonce zorunlu: Apple'ın döndürdüğü kimlik belirtecinin **bu isteğe ait
/// olduğunu** doğrular. Nonce'un ham hâli Firebase'e, SHA-256 özeti Apple'a
/// gider; Apple özeti belirtecin içine gömer ve Firebase ikisini karşılaştırır.
/// Olmadan yeniden oynatma (replay) saldırısı mümkün olur.
///
/// [appleSayfasi] ve [kimlikleGir] test dikişi: girişin Firebase'e hangi
/// kimlikle gittiği ([appleKimligi]) ancak çağrı yerinde tutulabilir.
Future<void> signInWithApple({
  Future<AuthorizationCredentialAppleID> Function(String nonceOzeti)?
      appleSayfasi,
  Future<UserCredential> Function(AuthCredential kimlik)? kimlikleGir,
}) async {
  final rawNonce = _randomNonce();
  final credential =
      await (appleSayfasi ?? _girisSayfasiniAc)(_nonceOzeti(rawNonce));

  final idToken = credential.identityToken;
  if (idToken == null) {
    throw StateError('Apple kimlik belirteci boş döndü');
  }
  final userCredential =
      await (kimlikleGir ?? FirebaseAuth.instance.signInWithCredential)(
    appleKimligi(idToken, rawNonce,
        ad: credential.givenName, soyad: credential.familyName),
  );

  // Apple adı YALNIZCA ilk girişte döndürür; kaçırılırsa bir daha alınamaz.
  final ad = [credential.givenName, credential.familyName]
      .whereType<String>()
      .where((p) => p.trim().isNotEmpty)
      .join(' ')
      .trim();
  if (ad.isNotEmpty && (userCredential.user?.displayName ?? '').isEmpty) {
    await userCredential.user?.updateDisplayName(ad);
  }
}

/// Firebase'e giden Apple kimliği; giriş de silme öncesi yeniden doğrulama
/// da ([appleYetkisiniIptalEt]) buradan kurar — iki kopya ayrışırdı ve
/// ayrıştı: giriş onarıldığında silme yolu eski kimlikte kalmıştı.
///
/// Apple'a ÖZEL kimlik, genel `OAuthProvider('apple.com')` DEĞİL:
/// firebase_auth 6.5.6'nın iOS eklentisi genel kimliği `signInMethod =
/// oauth` dalından `credentialWithProviderID:...accessToken:nil` ile
/// kuruyor; iPad'de (iPadOS 17.5.1, 2026-10-28) bu yol her denemede
/// `invalid-credential — Invalid OAuth response from apple.com` aldı,
/// Apple sayfası ve belirteç sağlamken. Bu kimliğin `signInMethod`'u
/// `apple.com` ve eklenti onu `appleCredentialWithIDToken:rawNonce:fullName:`
/// ile kuruyor (FlutterFire belgesinin Apple platformu yolu).
OAuthCredential appleKimligi(String idToken, String hamNonce,
        {String? ad, String? soyad}) =>
    AppleAuthProvider.credentialWithIDToken(idToken, hamNonce,
        AppleFullPersonName(givenName: ad, familyName: soyad));

Future<AuthorizationCredentialAppleID> _girisSayfasiniAc(String nonceOzeti) =>
    SignInWithApple.getAppleIDCredential(
      scopes: [
        AppleIDAuthorizationScopes.email,
        AppleIDAuthorizationScopes.fullName,
      ],
      nonce: nonceOzeti,
    );

String _randomNonce([int uzunluk = 32]) {
  const harfler =
      '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-._';
  final rastgele = Random.secure();
  return List.generate(
      uzunluk, (_) => harfler[rastgele.nextInt(harfler.length)]).join();
}

/// Apple'a giden yarı: ham nonce'un SHA-256 özeti (bkz. [signInWithApple]).
String _nonceOzeti(String hamNonce) =>
    sha256.convert(utf8.encode(hamNonce)).toString();

/// Google'ın "[16] Account reauth failed" hatası mı? (iç test bulgusu B1)
///
/// Cihazdaki Google oturumu bayatladığında düşer ve kullanıcının uygulama
/// içinde yapabileceği hiçbir şey yoktur; yol gösteren ayrı bir mesaj ister.
/// Android'in Credential Manager'ı bu hatayı İPTAL sınıfıyla
/// (`GetCredentialCancellationException`) bildirebiliyor; eklenti onu
/// `GoogleSignInExceptionCode.canceled`'a çeviriyor (google_sign_in_android
/// 7.2.15). Yani yalnız koda bakan bir iptal süzgeci bu hatayı da yutar —
/// [girisIptalEdildi] bu yüzden önce buna bakar.
bool googleYenidenDogrulamaGerekli(Object hata) {
  final metin = hata.toString();
  return metin.toLowerCase().contains('reauth') || metin.contains('[16]');
}

/// Kullanıcı Apple/Google giriş sayfasını KENDİSİ mi kapattı? (U49)
///
/// Kapatmak normal bir eylemdir; "giriş başarısız" göstermek olmamış bir
/// hatayı beyan etmek olur ve Crashlytics'i gerçek arızaları gizleyen sahte
/// kayıtlarla doldurur.
///
/// Apple'da yalnız `canceled` sayılır: iCloud hesabı olmayan cihaz ve
/// simülatörlerde kapatma `unknown` (1000) olarak da gelebiliyor, ama aynı
/// kod gerçek arızaları da taşıdığı için bastırılmaz.
///
/// Kod tanıma [isAuthCancelled]'da — iki ayrı kopya ayrışırdı. Buradaki tek
/// ek, iptal koduyla gelen reauth hatasını dışarıda tutmak (bkz.
/// [googleYenidenDogrulamaGerekli]).
bool girisIptalEdildi(Object hata) {
  return !googleYenidenDogrulamaGerekli(hata) && isAuthCancelled(hata);
}

/// Hesap silmeden önceki Apple yetkisi iptalinin sonucu (U15).
enum AppleIptalSonucu {
  /// Bu platformda ya da bu hesapta Apple yok — adım atlandı.
  gerekmedi,

  /// Yetki Apple tarafında iptal edildi.
  iptalEdildi,

  /// Kullanıcı Apple sayfasını kapattı — silme DURMALI.
  vazgecildi,

  /// Apple sayfası, yeniden doğrulama ya da iptal başarısız oldu; hata
  /// kaydedildi — silme SÜRMELİ.
  basarisiz,
}

/// Bu oturum iOS'ta Apple ile Giriş'e bağlı mı? Silme öncesi Apple adımının
/// ([appleYetkisiniIptalEt]) ve silme sayfasındaki "Apple onay isteyecek"
/// uyarısının ORTAK kapısı: ikisi ayrı hesaplasa sayfa, gelmeyecek bir
/// onayı haber verebilir ya da gelecek olanı saklayabilirdi.
///
/// [saglayicilar] test dikişi; varsayılanı oturumdaki sağlayıcılar.
bool appleHesabaBagli([Iterable<String>? saglayicilar]) {
  if (!appleSignInAvailable) return false;
  final kimlikler = saglayicilar ??
      (FirebaseAuth.instance.currentUser?.providerData
              .map((p) => p.providerId) ??
          const <String>[]);
  return kimlikler.contains('apple.com');
}

/// Hesap silinmeden önce "Apple ile Giriş" yetkisini Apple'da iptal eder
/// (U15, App Store 5.1.1(v)).
///
/// Olmasaydı: backend Firebase kullanıcısını siliyor ama Apple tarafındaki
/// yetki yerinde kalıyordu — kullanıcı Ayarlar → Apple Kimliği → "Apple ile
/// Giriş" altında Rytho'yu görmeye devam eder, yeniden girişte ad/e-posta
/// bir daha gelmez. Apple, SIWA sunan uygulamalardan silmede jeton iptali
/// bekliyor.
///
/// Sıra ZORUNLU ve Firebase kullanıcısı hâlâ varken koşar:
/// 1. Apple sayfası (nonce ile, kapsam yok): taze `authorizationCode`. Kod
///    tek kullanımlık ve kısa ömürlü, o yüzden iptalden hemen önce istenir.
/// 2. Aynı kimlikle `reauthenticateWithCredential`: sayfada seçilen Apple
///    Kimliğinin BU hesaba bağlı olan olduğunu kanıtlar (başkası seçildiyse
///    Firebase `user-mismatch` verir) — başka birinin yetkisi iptal edilmez.
/// 3. `revokeTokenWithAuthorizationCode`.
///
/// Kapatma ile arıza BİLEREK farklı ele alınır (sahibin kararı): kullanıcı
/// sayfayı kapattıysa geri adım atmıştır, silme durur ([vazgecildi]). Başka
/// her hata (ağ, Firebase'de Apple "OAuth code flow" ayarının eksikliği,
/// `user-mismatch`) Crashlytics'e `apple-revoke` diye yazılır ve silme
/// sürer ([basarisiz]) — 5.1.1(v) silmenin ÇALIŞMASINI şart koşar; iptal
/// adımı silmeyi rehin alamaz.
///
/// Kapı: yalnız iOS ([appleSignInAvailable]) VE sağlayıcılarda `apple.com`.
/// Android'de ve Apple'sız hesapta hiçbir şeye dokunmadan döner.
///
/// [onayVerildi]: kullanıcı Apple sayfasını onayladığı an (yeniden
/// doğrulama ve iptal ağ çağrılarından ÖNCE) çağrılır — silme sayfası
/// "siliniyor" satırını ancak o andan sonra gösterir; onaydan önce henüz
/// hiçbir şey silinmiyor ve sayfa kapatılırsa silinmeyebilir.
///
/// Diğer parametreler test dikişi; varsayılanlar gerçek Firebase/Apple.
Future<AppleIptalSonucu> appleYetkisiniIptalEt({
  Iterable<String>? saglayicilar,
  Future<AuthorizationCredentialAppleID> Function(String nonceOzeti)?
      appleSayfasi,
  Future<void> Function(AuthCredential kimlik)? yenidenDogrula,
  Future<void> Function(String yetkiKodu)? iptalEt,
  void Function(Object hata, StackTrace iz)? hataKaydi,
  void Function()? onayVerildi,
}) async {
  if (!appleHesabaBagli(saglayicilar)) return AppleIptalSonucu.gerekmedi;

  final kaydet = hataKaydi ?? _appleIptalHatasiniKaydet;
  final hamNonce = _randomNonce();

  final AuthorizationCredentialAppleID apple;
  try {
    apple = await (appleSayfasi ?? _appleSayfasiniAc)(_nonceOzeti(hamNonce));
  } catch (e, iz) {
    if (girisIptalEdildi(e)) return AppleIptalSonucu.vazgecildi;
    kaydet(e, iz);
    return AppleIptalSonucu.basarisiz;
  }
  onayVerildi?.call();

  try {
    final idToken = apple.identityToken;
    if (idToken == null) {
      throw StateError('Apple kimlik belirteci boş döndü');
    }
    await (yenidenDogrula ?? _mevcutKullaniciyiYenidenDogrula)(
        appleKimligi(idToken, hamNonce));
    await (iptalEt ?? FirebaseAuth.instance.revokeTokenWithAuthorizationCode)(
        apple.authorizationCode);
    return AppleIptalSonucu.iptalEdildi;
  } catch (e, iz) {
    kaydet(e, iz);
    return AppleIptalSonucu.basarisiz;
  }
}

Future<AuthorizationCredentialAppleID> _appleSayfasiniAc(String nonceOzeti) =>
    SignInWithApple.getAppleIDCredential(scopes: const [], nonce: nonceOzeti);

Future<void> _mevcutKullaniciyiYenidenDogrula(AuthCredential kimlik) async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) throw StateError('Oturum yok');
  await user.reauthenticateWithCredential(kimlik);
}

void _appleIptalHatasiniKaydet(Object hata, StackTrace iz) {
  debugPrint('Apple yetkisi iptal edilemedi: $hata');
  if (kDebugMode || kIsWeb) return;
  FirebaseCrashlytics.instance
      .recordError(hata, iz, reason: 'apple-revoke', fatal: false);
}

/// E-posta ile giriş.
Future<void> signInWithEmail(String email, String password) =>
    FirebaseAuth.instance
        .signInWithEmailAndPassword(email: email, password: password);

/// E-posta ile kayıt.
///
/// Kayıttan hemen sonra **doğrulama e-postası** gönderilir. Gönderilmezse
/// kimse sahibi olmadığı bir adresle hesap açabilir — ve o adresin gerçek
/// sahibi sonradan kaydolmak isteyince "e-posta kullanımda" duvarına çarpar.
Future<void> registerWithEmail({
  required String email,
  required String password,
  required String displayName,
}) async {
  final credential = await FirebaseAuth.instance
      .createUserWithEmailAndPassword(email: email, password: password);
  await credential.user?.updateDisplayName(displayName);
  try {
    await credential.user?.sendEmailVerification();
  } catch (e) {
    // Doğrulama e-postası gönderilemezse kayıt yine de geçerli; kullanıcıyı
    // burada durdurmak, hesabı olan birini dışarıda bırakmak olurdu.
    debugPrint('Doğrulama e-postası gönderilemedi: $e');
  }
}

/// Şifre sıfırlama — hatayı YENİDEN FIRLATIR (OT2).
///
/// Eski davranış TÜM istisnaları yutup çağırana "başarılı" gibi
/// dönüyordu; offline/kota/yapılandırma hatalarında bile kullanıcı
/// "gönderildi" görüyor ve e-posta asla gelmiyordu — "şifremi unuttum
/// çalışmıyor" cihaz bulgusunun bir numaralı nedeni. Kullanıcı sayımı
/// koruması EKRANIN işidir: yalnız `user-not-found` başarı gibi
/// gösterilir (bkz. ForgotPasswordScreen), gerçek hatalar anlatılır.
Future<void> sendPasswordReset(String email) =>
    FirebaseAuth.instance.sendPasswordResetEmail(email: email.trim());

/// FirebaseAuth hata kodunu kullanıcı diline çevirir.
///
/// LoginScreen'in özel kopyasıydı (OT2'de buraya çıkarıldı): şifre panosu
/// da aynı haritayı kullanır; iki kopya kaçınılmaz olarak ayrışırdı.
String authErrorText(AppLocalizations l10n, FirebaseAuthException e) {
  switch (e.code) {
    case 'user-not-found':
    case 'wrong-password':
    case 'invalid-credential':
      return l10n.authWrongCredentials;
    case 'email-already-in-use':
      return l10n.authEmailInUse;
    case 'weak-password':
      return l10n.passwordTooShort;
    case 'invalid-email':
      return l10n.authInvalidEmail;
    case 'too-many-requests':
      return l10n.authTooManyRequests;
    case 'operation-not-allowed':
      return l10n.authDisabled;
    case 'network-request-failed':
      return l10n.authNetwork;
    // U31: Google'la (ya da şifreyle) açılmış hesabın e-postasıyla Apple'a
    // basmak tipik iOS geçişidir. Genel "giriş yapılamadı" kullanıcıya eski
    // yöntemini kullanması gerektiğini söylemiyordu. Hangi yöntem olduğunu
    // SORMAYIZ (bkz. aşağıdaki sağlayıcı çakışması notu) ve hesapları
    // OTOMATİK BAĞLAMAYIZ: Apple, Apple hesabının başka verilere
    // bağlanmasından önce kullanıcının açık onayını istiyor (Firebase'in
    // Apple ile Giriş belgesindeki not).
    case 'account-exists-with-different-credential':
      return l10n.authAccountExistsOtherMethod;
    default:
      return l10n.authFailed;
  }
}

/// Sosyal girişte (Google/Apple) gelen FirebaseAuth hatasının metni.
///
/// [authErrorText] şifre formu için yazıldı: orada `invalid-credential`
/// "e-posta ya da şifre yanlış" demek. Sosyal girişte kullanıcı ne e-posta
/// ne şifre yazdı; aynı kod SAĞLAYICI belirtecinin reddidir. iPad'de Apple
/// girişi `invalid-credential — Invalid OAuth response from apple.com`
/// alırken ekranda "E-posta veya şifre hatalı." yazıyordu (2026-10-28) —
/// kullanıcıyı şifresinden şüphelendiren yanlış bir beyan. Anlamı aynı
/// kalan kodlar (hesap başka yöntemle açılmış, ağ, çok deneme) haritadan
/// gelir. `operation-not-allowed` şifre formunda "e-posta girişi kapalı"
/// demek; sosyal girişte kapalı olan SAĞLAYICIDIR, e-posta değil.
String sosyalGirisHataMetni(AppLocalizations l10n, FirebaseAuthException e) =>
    switch (e.code) {
      'invalid-credential' ||
      'wrong-password' ||
      'user-not-found' ||
      'operation-not-allowed' => l10n.authFailed,
      _ => authErrorText(l10n, e),
    };

/// Sosyal giriş hatası Crashlytics'e yazılsın mı?
///
/// Yalnız yapılandırma ya da sağlayıcı arızası anlamına gelen kodlar: bunlar
/// yayında hiçbir yerde görünmüyordu (genel `catch` yalnız Firebase DIŞI
/// istisnaları yazıyor), yani Apple girişi canlıda bozulsa kimse fark
/// etmezdi. Kullanıcının kendi hâli olan kodlar (hesap başka yöntemle açık,
/// ağ, çok deneme) arıza değil; yazılırsa sayaç şişer ve gerçek arıza
/// gömülür.
bool sosyalGirisHatasiKaydedilir(String kod) => const {
  'invalid-credential',
  'operation-not-allowed',
  'internal-error',
  'unknown',
}.contains(kod);

// Sağlayıcı çakışması hakkında bir not:
//
// Google ile açılmış bir hesaba şifreyle girilmeye çalışıldığında Firebase
// yalnızca "geçersiz kimlik" diyor ve kullanıcı çıkmaza giriyor. Önce
// `fetchSignInMethodsForEmail` ile hangi sağlayıcının kullanıldığını sormayı
// denedim — o API **kaldırıldı**, çünkü tam da kaçınmaya çalıştığımız şeyi
// yapıyordu: bir e-postanın kayıtlı olup olmadığını dışarıya sızdırıyordu
// (kullanıcı sayımı). Firebase artık bunu "email enumeration protection" ile
// varsayılan olarak kapatıyor.
//
// Bu yüzden çözüm istemcide sorgu değil, DOĞRU YAZILMIŞ HATA MESAJI: giriş
// başarısız olduğunda kullanıcıya her iki olasılık birden söyleniyor
// (şifre yanlış olabilir ya da hesap sosyal giriş ile açılmış olabilir).
// Bilgi sızdırmadan çıkmazı çözer.

/// Hesaba e-posta/şifre girişi bağlar (F4).
///
/// Google/Apple ile açılmış hesapta `password` sağlayıcısı yoktur;
/// `updatePassword` çağrısı orada anlamsızdır — doğru araç
/// `linkWithCredential`: aynı hesaba ikinci bir giriş yolu ekler.
/// Şifre zaten bağlıysa `updatePassword` ile değiştirilir.
///
/// E-posta parametre olarak alınır ve `user.email` varsayılmaz: Apple
/// "Hide My Email" kullanıcısında adres privaterelay olabilir ya da hiç
/// gelmeyebilir; kullanıcı giriş için KULLANACAĞI adresi kendi yazar.
Future<void> linkPassword(String email, String password) async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) throw StateError('Oturum yok');

  final sifreBagli =
      user.providerData.any((p) => p.providerId == 'password');
  if (sifreBagli) {
    await user.updatePassword(password);
    return;
  }
  await user.linkWithCredential(
      EmailAuthProvider.credential(email: email.trim(), password: password));
  // Sağlayıcı listesi token'da taşınır; tazelenmezse arayüz eski kalır.
  await user.getIdToken(true);
}

/// Hesaba Google girişini bağlar (F4) — e-posta/şifre kullanıcısı için.
Future<void> linkGoogle() async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) throw StateError('Oturum yok');

  final account = await GoogleSignIn.instance.authenticate();
  final auth = account.authentication;
  await user.linkWithCredential(
      GoogleAuthProvider.credential(idToken: auth.idToken));
  await user.getIdToken(true);
}

/// Çıkış yolunun uygulamaya köprüsü: sağlayıcı kabı kök navigatörün
/// bağlamından bulunur (`rythoNavigatorKey` — paywall da aynı köprüyle
/// açılıyor, bkz. api.dart).
///
/// `signOutEverywhere` üst düzey bir fonksiyon; `ref`'i, dolayısıyla
/// uygulamanın Dio'su ve kapı bayrağı yok. Üç çağıranı (profil, hesap silme,
/// onboarding) tear-off geçiyor; imzayı bozmak ya da `_Gate`'e kanca kurmak
/// yerine var olan köprü kullanılır. Navigatör yoksa (testler, Firebase'siz
/// yollar) null: çıkış kilide dokunmadan sürer.
ProviderContainer? _uygulamaKabi() {
  final context = rythoNavigatorKey.currentContext;
  if (context == null || !context.mounted) return null;
  try {
    return ProviderScope.containerOf(context, listen: false);
  } catch (_) {
    return null;
  }
}

Future<void> _oturumuKapat() async {
  try {
    await GoogleSignIn.instance.signOut();
  } catch (_) {}
  await FirebaseAuth.instance.signOut();
}

/// Çıkışta cihaz jetonunu bu hesaptan söker (JT-turu); kimlik yoksa ya da
/// Firebase ayakta değilse (testler) sessizce geçer.
Future<void> _jetonuUnut() async {
  try {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) await forgetPushToken(uid);
  } catch (e) {
    debugPrint('Çıkışta jeton unutulamadı: $e');
  }
}

/// Her yerden çıkış: önce cihaz kilidi bırakılır, sonra cihaz jetonu bu
/// hesaptan sökülür, sonra Google + Firebase oturumu kapanır, en son
/// çakışma kapısı düşer.
///
/// SIRA ZORUNLU (TC-turu K7 → JT): `DELETE /device/claim` Firebase
/// kimliğiyle gider — çıkıştan sonra çağrılsa 401 yer ve eski cihaz kilidi
/// elinde tutar; "A çıkış yaptı, B hâlâ kilitli" (B4) tam buydu. Jeton
/// sökme de kimlik ister: çıkıştan sonra profil yazımını kural reddeder ve
/// eski hesabın push'u bu telefona gelmeye devam ederdi (cihazda ölçüldü:
/// aynı jeton iki profilde, biri Türkçe biri İngilizce). İkisi de ≤3 sn ve
/// hata yutulur; çıkış hiçbir koşulda engellenmez. Kapı bayrağı ÇIKIŞTAN
/// SONRA iner: hiç inmese bir sonraki giriş aynı çakışma ekranına düşerdi;
/// önce inse `_Gate` bir kare kabuğu gösterirdi.
///
/// [signOut] ve [forgetToken] test dikişi.
Future<void> signOutEverywhere({
  Future<void> Function()? signOut,
  Future<void> Function()? forgetToken,
}) async {
  final kap = _uygulamaKabi();
  if (kap != null) await releaseThisDevice(kap.read(apiProvider));
  await (forgetToken ?? _jetonuUnut)();
  await (signOut ?? _oturumuKapat)();
  kap?.read(deviceConflictProvider.notifier).state = null;
}
