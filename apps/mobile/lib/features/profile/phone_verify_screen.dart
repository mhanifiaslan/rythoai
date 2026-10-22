/// Telefon doğrulama — hesaba numara BAĞLAMA (ayrı giriş yöntemi değil).
///
/// ## Akış
///
/// 1. Kullanıcı numarasını girer → Firebase SMS gönderir
///    (`verifyPhoneNumber`; Android'de bazen SMS'siz otomatik doğrular).
/// 2. Kod girilir → `linkWithCredential` mevcut hesaba numarayı bağlar.
/// 3. Token TAZELENİR (`getIdToken(true)`) — `phone_number` claim'i ancak
///    yeni token'da görünür — ve sunucuya "bağladım, kaydet" denir
///    (`POST /account/phone/sync`, gövdesiz: sunucu numarayı TOKEN'dan okur,
///    istemci beyanına güvenmez).
///
/// Sunucu tarafında hash dizini rehber eşleşmesinin (R3) temelini kurar;
/// ham numara Firestore'a hiç yazılmaz.
library;

import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api.dart';
import '../../l10n/app_localizations.dart';
import '../../theme/rytho_theme.dart';
import '../../theme/rytho_tokens.dart';
import '../../widgets/atlas_widgets.dart';
import '../../widgets/cosmic_scaffold.dart';
import '../../widgets/phone_number_field.dart';

class PhoneVerifyScreen extends ConsumerStatefulWidget {
  const PhoneVerifyScreen({super.key});

  @override
  ConsumerState<PhoneVerifyScreen> createState() => _PhoneVerifyScreenState();
}

class _PhoneVerifyScreenState extends ConsumerState<PhoneVerifyScreen> {
  /// Alanın tam durumu — ülke DE lazım: SMS bölge kapısı ve ülkeye göre
  /// uzunluk kontrolü yalnız E.164 dizesiyle yapılamaz.
  PhoneEntry _giris = const PhoneEntry.bos();
  final _kod = TextEditingController();
  String? _verificationId;

  /// Firebase'in verdiği yeniden gönderme jetonu. Bu jetonla yapılan
  /// çağrı YENİ bir doğrulama değil, aynı doğrulamanın TEKRARIDIR —
  /// kötüye kullanım korumasını (17499 / Error code:39) tetiklemez.
  /// Eskiden atılıyordu ve kullanıcının tek çaresi "numarayı değiştir"
  /// ile sıfırdan doğrulama başlatmaktı; bu tam da korumayı tetikleyen
  /// davranıştı (2026-09-08 canlı bulgusu).
  int? _resendToken;

  bool _mesgul = false;
  String? _hata;

  /// Geri sayım: 0 ise "tekrar gönder" aktif.
  int _bekleme = 0;
  Timer? _sayac;

  /// Kod istendikten bu yana geçen saniye — yol gösterici metin bunun
  /// eşiğinde belirir.
  int _gecen = 0;

  static const _resendSaniye = 60;
  static const _ipucuSaniye = 45;

  /// SMS bölge listesi konsolda `allowlistOnly: ["TR"]`. Buraya yazılı
  /// olması bilinçli: liste konsolda genişletilirse burası da güncellenir,
  /// aksi hâlde kullanıcı boşuna gönderim yapıp ücret yakar ve "kod
  /// gelmiyor" ekranında kalır.
  static const _smsBolgeleri = {'TR'};

  @override
  void dispose() {
    _sayac?.cancel();
    _kod.dispose();
    super.dispose();
  }

  void _sayaciBaslat() {
    _sayac?.cancel();
    setState(() {
      _bekleme = _resendSaniye;
      _gecen = 0;
    });
    _sayac = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      setState(() {
        _gecen++;
        if (_bekleme > 0) _bekleme--;
      });
      if (_bekleme == 0 && _gecen > _ipucuSaniye) t.cancel();
    });
  }

  Future<void> _kodGonder({bool tekrar = false}) async {
    final l10n = AppLocalizations.of(context);
    final giris = _giris;
    final ulke = giris.country;

    if (ulke == null || !giris.plausible) {
      setState(() => _hata = l10n.phoneInvalid);
      return;
    }
    // Bölge kapısı: gönderilemeyecek numaraya gönderim denemesi yapma.
    if (!_smsBolgeleri.contains(ulke.iso2)) {
      setState(() => _hata = l10n.phoneRegionUnsupported);
      return;
    }

    setState(() {
      _mesgul = true;
      _hata = null;
    });

    // try/catch ŞART: eskiden yoktu ve fırlatan her istisna (eklenti/kanal
    // hatası, Play Services yokluğu) _mesgul'u true bırakıp ekranı sonsuz
    // spinner'da donduruyordu — ne mesaj ne kayıt.
    try {
      await FirebaseAuth.instance.verifyPhoneNumber(
        phoneNumber: giris.e164,
        forceResendingToken: tekrar ? _resendToken : null,
        // Android otomatik doğrulaması: SMS beklemeden kimlik gelebilir.
        verificationCompleted: (credential) {
          _iz('auto');
          _bagla(credential);
        },
        verificationFailed: (e) {
          _iz('failed', kod: e.code);
          if (!mounted) return;
          setState(() {
            _mesgul = false;
            _hata = _firebaseHatasi(e, l10n);
          });
        },
        codeSent: (verificationId, resendToken) {
          _iz('sent');
          if (!mounted) return;
          setState(() {
            _mesgul = false;
            _verificationId = verificationId;
            _resendToken = resendToken;
          });
          _sayaciBaslat();
        },
        codeAutoRetrievalTimeout: (verificationId) {
          _verificationId ??= verificationId;
        },
      );
    } on FirebaseAuthException catch (e) {
      _iz('failed', kod: e.code);
      if (!mounted) return;
      setState(() {
        _mesgul = false;
        _hata = _firebaseHatasi(e, l10n);
      });
    } catch (e) {
      _iz('failed', kod: 'throw');
      if (!kDebugMode) {
        FirebaseCrashlytics.instance.recordError(
            'phone-verify send: $e', StackTrace.current,
            fatal: false);
      }
      if (!mounted) return;
      setState(() {
        _mesgul = false;
        _hata = l10n.genericError;
      });
    }
  }

  /// Ateşle-unut teşhis kaydı. Tam numara GİTMEZ — yalnız maskeli biçim
  /// ("+90532***4567") ve ülke. Bugüne kadar başarı yolunda hiçbir iz
  /// yoktu; "operatör mü düşürdü, numara mı yanlıştı" sorusu bu yüzden
  /// cevaplanamıyordu.
  void _iz(String asama, {String? kod}) {
    final ulke = _giris.country;
    if (ulke == null) return;
    unawaited(() async {
      try {
        await ref.read(apiProvider).post(
          '/api/v1/account/phone/attempt',
          data: {
            'stage': asama,
            'iso2': ulke.iso2,
            'masked': _giris.masked,
            'code': ?kod,
          },
        );
      } catch (_) {
        // Teşhis kaydı doğrulama akışını ASLA düşüremez.
      }
    }());
  }

  Future<void> _kodOnayla() async {
    final id = _verificationId;
    if (id == null) return;
    await _bagla(PhoneAuthProvider.credential(
      verificationId: id,
      smsCode: _kod.text.trim(),
    ));
  }

  Future<void> _bagla(PhoneAuthCredential credential) async {
    final l10n = AppLocalizations.of(context);
    final gezgin = Navigator.of(context);
    final mesajci = ScaffoldMessenger.of(context);
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      // Eskiden burada sessizce return ediliyordu ve _mesgul true kalıyordu:
      // otomatik doğrulama yolunda ekran sonsuz spinner'da donuyordu.
      if (!mounted) return;
      setState(() {
        _mesgul = false;
        _hata = l10n.genericError;
      });
      return;
    }

    setState(() {
      _mesgul = true;
      _hata = null;
    });
    try {
      if (user.phoneNumber == null) {
        await user.linkWithCredential(credential);
      } else {
        // Numara değişikliği: bağlama değil güncelleme.
        await user.updatePhoneNumber(credential);
      }

      // Claim ancak TAZE token'da görünür; tazelenmeden sync 400 döner.
      await user.getIdToken(true);
      await ref.read(apiProvider).post('/api/v1/account/phone/sync');
      _iz('verified');

      if (!mounted) return;
      _sayac?.cancel();
      mesajci.showSnackBar(SnackBar(content: Text(l10n.phoneLinkedDone)));
      gezgin.pop();
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      setState(() {
        _mesgul = false;
        _hata = _firebaseHatasi(e, l10n);
      });
    } catch (e) {
      // Sunucu 409'u (numara başka hesapta) dahil: detail kullanıcının
      // dilinde geliyor.
      if (!mounted) return;
      setState(() {
        _mesgul = false;
        _hata = friendlyError(e, l10n);
      });
    }
  }

  String _firebaseHatasi(FirebaseAuthException e, AppLocalizations l10n) {
    switch (e.code) {
      case 'credential-already-in-use':
      case 'account-exists-with-different-credential':
        return l10n.phoneTakenError;
      case 'invalid-verification-code':
      case 'invalid-verification-id':
        return l10n.phoneCodeWrong;
      case 'invalid-phone-number':
        return l10n.phoneInvalid;
      case 'too-many-requests':
      case 'quota-exceeded':
        return l10n.phoneTooManyTries;
      // Aşağıdaki üçü KURULUM sorunlarıdır ve eskiden jenerik "bir şeyler
      // ters gitti"ye düşüyordu — kullanıcı "kod gelmiyor" diyor, neden
      // hiç görünmüyordu. Artık ayrışıyor: sağlayıcı kapalı / uygulama
      // doğrulaması (SHA-256, Play Integrity) eksik.
      case 'operation-not-allowed':
        return l10n.phoneSmsDisabled;
      case 'app-not-authorized':
      case 'missing-client-identifier':
        return l10n.phoneAppNotVerified;
      // 17499/39 (cihazda görüldü, 2026-08-07): Firebase'in kötüye
      // kullanım koruması — aynı numara/cihazla kısa sürede çok deneme.
      // Birkaç saatte kendiliğinden açılır; kullanıcıya bunu söylemek
      // "bir şeyler ters gitti"den çok daha az korkutucu.
      case 'internal-error':
        return l10n.phoneTemporarilyBlocked;
      default:
        // Aynı 17499/39 hatası her cihazda 'internal-error' koduyla
        // gelmiyor (2026-08-12'de 'unknown' kodla, mesajın içinde
        // "Error code:39" olarak görüldü) — koddan önce mesaja da bak.
        final mesaj = e.message ?? '';
        if (mesaj.contains('17499') || mesaj.contains('Error code:39')) {
          return l10n.phoneTemporarilyBlocked;
        }
        // Nedeni bilmiyorsak en azından BİZ öğrenelim: kod+mesaj
        // Crashlytics'e gider (eskiden hiçbir yere gitmiyordu).
        if (!kDebugMode) {
          FirebaseCrashlytics.instance.recordError(
              'phone-verify: ${e.code}: ${e.message}', StackTrace.current,
              fatal: false);
        }
        return l10n.genericError;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final kodAsamasi = _verificationId != null;

    return CosmicScaffold(
      appBar: AppBar(title: Text(l10n.phoneVerifyTitle)),
      body: SafeArea(
        child: ListView(
          // U48: iOS sayı tuş takımında kapatma tuşu yok (bkz. alan).
          keyboardDismissBehavior: sayiKlavyesiKaydirmaDavranisi,
          padding: const EdgeInsets.fromLTRB(RythoSpace.xl, RythoSpace.md,
              RythoSpace.xl, RythoSpace.xxl),
          children: [
            Text(l10n.phoneVerifyBody, style: RythoType.bodyDim),
            const SizedBox(height: RythoSpace.xl),
            if (!kodAsamasi) ...[
              PhoneNumberField(
                onChanged: (giris) => setState(() {
                  _giris = giris;
                  _hata = null;
                }),
              ),
              // Gönderim ÖNCESİ derlenmiş numarayı göster: yanlış derlenmiş
              // ya da yanlış yazılmış numaraya karşı en ucuz savunma bu.
              // Firebase yanlış numarayı da kabul edip faturalandırıyor,
              // kullanıcının gördüğü tek şey "kod gelmiyor" oluyor.
              if (_giris.plausible) ...[
                const SizedBox(height: RythoSpace.md),
                Text(l10n.phoneWillSendTo(_giris.e164),
                    style: RythoType.caption),
              ],
            ] else ...[
              Text(l10n.phoneCodeSentTo(_giris.e164), style: RythoType.body),
              const SizedBox(height: RythoSpace.md),
              TextField(
                controller: _kod,
                style: RythoType.body,
                keyboardType: TextInputType.number,
                autofillHints: const [AutofillHints.oneTimeCode],
                onTapOutside: sayiKlavyesiDisDokunus,
                decoration: InputDecoration(labelText: l10n.phoneCodeLabel),
                onChanged: (_) => setState(() => _hata = null),
              ),
              const SizedBox(height: RythoSpace.sm),
              // İki kurtarma düğmesi esnemeyen bir `Row`daydı: "Kodu
              // tekrar gönder (42)" + "Numarayı değiştir" dar ekranda tek
              // satıra sığmıyor, ikincisi ekran dışına taşıyordu. `Wrap`
              // sığdığında aynı görünür, sığmadığında alt satıra iner.
              // `SizedBox`: Wrap gevşek kısıtta büzülür, `spaceBetween`
              // yayacak boşluk bulamaz.
              SizedBox(
                width: double.infinity,
                child: Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                  // TEKRAR GÖNDER: forceResendingToken ile, yani AYNI
                  // doğrulamanın tekrarı. "Numarayı değiştir" yolu sıfırdan
                  // yeni doğrulama başlatır ve Firebase'in kötüye kullanım
                  // korumasını tetikler — kurtarma yolu bu olmalı, o değil.
                  TextButton(
                    onPressed: (_mesgul || _bekleme > 0)
                        ? null
                        : () => _kodGonder(tekrar: true),
                    child: Text(
                      _bekleme > 0
                          ? l10n.phoneResendIn(_bekleme)
                          : l10n.phoneResend,
                      style: RythoType.caption,
                    ),
                  ),
                  TextButton(
                    onPressed: _mesgul
                        ? null
                        : () {
                            _sayac?.cancel();
                            setState(() {
                              _verificationId = null;
                              _bekleme = 0;
                              _gecen = 0;
                              _kod.clear();
                            });
                          },
                    child: Text(l10n.phoneChangeNumber,
                        style: RythoType.caption),
                  ),
                ],
              ),
              ),
              // Kod gelmediğinde kullanıcı ne yapacağını bilsin. Bugünkü
              // canlı olayda kullanıcı 8 dakika bekleyip kaydı bıraktı;
              // ekranda ne tekrar gönderme ne yönlendirme vardı.
              if (_gecen >= _ipucuSaniye) ...[
                const SizedBox(height: RythoSpace.md),
                Text(l10n.phoneNoCodeHelp, style: RythoType.caption),
              ],
            ],
            if (_hata != null) ...[
              const SizedBox(height: RythoSpace.md),
              Text(_hata!,
                  style: RythoText.body(13, color: RythoColors.madder)),
            ],
            const SizedBox(height: RythoSpace.xxl),
            GoldButton(
              text: kodAsamasi ? l10n.phoneConfirmCode : l10n.phoneSendCode,
              busy: _mesgul,
              onPressed: _mesgul
                  ? null
                  : (kodAsamasi ? _kodOnayla : _kodGonder),
            ),
          ],
        ),
      ),
    );
  }
}
