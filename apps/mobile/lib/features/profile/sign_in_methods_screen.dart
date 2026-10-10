/// Giriş yöntemleri (F4): hesaba ikinci bir giriş yolu bağlama.
///
/// İki akış:
/// * Google/Apple kullanıcısı ŞİFRE oluşturur → e-posta+şifreyle de
///   girebilir (`linkWithCredential`, yeni hesap AÇILMAZ).
/// * E-posta/şifre kullanıcısı GOOGLE bağlar → tek dokunuş girişi kazanır.
///
/// Tamamen istemci tarafı: sağlayıcı listesi Firebase token'ında yaşar,
/// sunucuda ayrıca tutulmaz. Hata eşlemesi phone_verify_screen desenini
/// izler; bilinmeyen kodlar Crashlytics'e gider.
///
/// Hata YERLEŞİMİ (D4, ölçüldü 2026-10-10): eskiden tek bir `_hata` vardı
/// ve şifre alanının `errorText`ine basılıyordu — Google bağlanamayınca
/// kullanıcı ŞİFRE alanının kırmızı yandığını görüyordu. Şimdi iki yuva:
/// Google hatası Google satırının altında, şifre hatası şifre bölümünün
/// altında. Şifre belirleme de kayıt gibi: tekrar alanı + kural
/// (`SifreAlanlari`), çünkü yanlış yazılan yeni şifre hesabı düşürüyordu.
library;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../core/auth_service.dart';
import '../../theme/rytho_theme.dart';
import '../../theme/rytho_tokens.dart';
import '../../widgets/atlas_widgets.dart';
import '../../widgets/common.dart';
import '../../widgets/glass.dart';
import '../../widgets/sifre_alanlari.dart';
import '../../l10n/app_localizations.dart';
import 'phone_verify_screen.dart' show PhoneVerifyScreen;
import 'profile_sections.dart' show SettingsPage;

/// Profil satırındaki özet: "Google · Şifre" gibi.
String signInMethodsSummary(User? user, AppLocalizations l10n) {
  if (user == null) return '';
  final adlar = <String>[];
  for (final p in user.providerData) {
    switch (p.providerId) {
      case 'google.com':
        adlar.add('Google');
      case 'apple.com':
        adlar.add('Apple');
      case 'password':
        adlar.add(l10n.password);
      case 'phone':
        adlar.add(l10n.providerPhone);
    }
  }
  return adlar.join(' · ');
}

class SignInMethodsScreen extends StatefulWidget {
  const SignInMethodsScreen({
    super.key,
    this.baglilar,
    this.ilkEposta,
    this.googleBagla,
    this.sifreBagla,
  });

  /// Test dikişleri; üretimde Firebase'in sağlayıcı listesi ve e-postası,
  /// [linkGoogle] ve [linkPassword]. Hata yerleşimi (Google hatası şifre
  /// alanında DEĞİL) Firebase ayakta olmadan sabitlenebilsin. Testte
  /// [ilkEposta] boş dize de olsa VERİLİR; null Firebase'e düşer.
  final Set<String> Function()? baglilar;
  final String? ilkEposta;
  final Future<void> Function()? googleBagla;
  final Future<void> Function(String email, String sifre)? sifreBagla;

  @override
  State<SignInMethodsScreen> createState() => _SignInMethodsScreenState();
}

class _SignInMethodsScreenState extends State<SignInMethodsScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _pass2Ctrl = TextEditingController();
  bool _busy = false;

  /// İki hata yuvası — bkz. dosya başı. Aynı değişkene yazılsa Google
  /// hatası yine şifre bölümünde belirir.
  String? _googleHata;
  String? _sifreHata;

  @override
  void initState() {
    super.initState();
    _emailCtrl.text =
        widget.ilkEposta ?? FirebaseAuth.instance.currentUser?.email ?? '';
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passCtrl.dispose();
    _pass2Ctrl.dispose();
    super.dispose();
  }

  Set<String> _bagliSaglayicilar() =>
      widget.baglilar?.call() ??
      (FirebaseAuth.instance.currentUser?.providerData
              .map((p) => p.providerId)
              .toSet() ??
          const <String>{});

  bool _bagli(String providerId) => _bagliSaglayicilar().contains(providerId);

  String _baglamaHatasi(FirebaseAuthException e, AppLocalizations l10n) {
    switch (e.code) {
      case 'provider-already-linked':
        return l10n.linkAlreadyLinked;
      case 'credential-already-in-use':
      case 'email-already-in-use':
        return l10n.linkCredentialInUse;
      case 'requires-recent-login':
        return l10n.linkRequiresRecentLogin;
      case 'weak-password':
        return l10n.passwordTooShort;
      case 'invalid-email':
        return l10n.authInvalidEmail;
      default:
        if (!kDebugMode) {
          FirebaseCrashlytics.instance.recordError(
              'link-provider: ${e.code}: ${e.message}', StackTrace.current,
              fatal: false);
        }
        return l10n.authFailed;
    }
  }

  /// [hataya]: hatanın yazılacağı yuva — çağıran seçer, çünkü hangi işin
  /// koştuğunu yalnız o bilir.
  Future<void> _calistir(Future<void> Function() is_,
      {required String basarili,
      required void Function(String?) hataya}) async {
    final l10n = AppLocalizations.of(context);
    final mesajci = ScaffoldMessenger.of(context);
    setState(() {
      _busy = true;
      hataya(null);
    });
    try {
      await is_();
      if (!mounted) return;
      mesajci.showSnackBar(SnackBar(content: Text(basarili)));
      setState(() {}); // sağlayıcı listesi değişti; ✓ rozetleri tazelensin
    } catch (e) {
      if (!mounted) return;
      // Google penceresini kullanıcı kendi kapattıysa hata değil
      // (giriş ekranıyla aynı kural, bkz. isAuthCancelled).
      if (isAuthCancelled(e)) return;
      final metin = e is FirebaseAuthException
          ? _baglamaHatasi(e, l10n)
          : l10n.authFailed;
      setState(() => hataya(metin));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _googleBaglaTikla() => _calistir(
        widget.googleBagla ?? linkGoogle,
        basarili: AppLocalizations.of(context).linkGoogleDone,
        hataya: (m) => _googleHata = m,
      );

  Future<void> _sifreKaydet() async {
    if (_busy) return;
    final l10n = AppLocalizations.of(context);
    // Kural (`validatePassword`), tekrar eşleşmesi ve e-posta biçimi
    // `Form` doğrulayıcılarında — kayıt formuyla aynı yol, elle kopya yok.
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final email = _emailCtrl.text.trim();
    final sifre = _passCtrl.text;
    await _calistir(
      () => (widget.sifreBagla ?? linkPassword)(email, sifre),
      basarili: l10n.linkPasswordDone,
      hataya: (m) => _sifreHata = m,
    );
    if (mounted && _sifreHata == null) {
      _passCtrl.clear();
      _pass2Ctrl.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final sifreBagli = _bagli('password');
    final googleBagli = _bagli('google.com');
    final appleBagli = _bagli('apple.com');
    final telefonBagli = _bagli('phone');

    Widget rozet(bool bagli) => bagli
        ? const Icon(Icons.check_circle_rounded,
            size: 18, color: RythoColors.goldBright)
        : const Icon(Icons.radio_button_unchecked,
            size: 18, color: RythoColors.parchmentDim);

    return SettingsPage(title: l10n.signInMethodsTitle, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(
            RythoSpace.lg, 0, RythoSpace.lg, RythoSpace.md),
        child: Text(l10n.signInMethodsBody, style: RythoType.caption),
      ),
      GlassPanel(
        child: Column(children: [
          SettingsRow(
            icon: Icons.g_mobiledata_rounded,
            title: 'Google',
            trailing: googleBagli
                ? rozet(true)
                : TextButton(
                    onPressed: _busy ? null : _googleBaglaTikla,
                    child: Text(l10n.linkAction),
                  ),
          ),
          // Google hatası Google satırının ALTINDA — şifre alanında değil.
          _HataMetni(_googleHata,
              padding: const EdgeInsets.fromLTRB(
                  RythoSpace.lg, 0, RythoSpace.lg, RythoSpace.md)),
          if (appleSignInAvailable || appleBagli) ...[
            const Divider(height: 1, indent: RythoSpace.lg),
            SettingsRow(
              icon: Icons.apple_rounded,
              title: 'Apple',
              trailing: rozet(appleBagli),
            ),
          ],
          const Divider(height: 1, indent: RythoSpace.lg),
          SettingsRow(
            icon: Icons.sms_outlined,
            title: l10n.providerPhone,
            // OT4: bağsız satır eskiden salt rozetti — telefonunu burada
            // arayan kullanıcı çıkmaz sokağa giriyordu. Google satırı
            // deseniyle eylem kazandı.
            trailing: telefonBagli
                ? rozet(true)
                : TextButton(
                    onPressed: _busy
                        ? null
                        : () async {
                            await Navigator.of(context).push(
                                MaterialPageRoute(
                                    builder: (_) =>
                                        const PhoneVerifyScreen()));
                            if (mounted) setState(() {});
                          },
                    child: Text(l10n.linkAction),
                  ),
          ),
          const Divider(height: 1, indent: RythoSpace.lg),
          SettingsRow(
            icon: Icons.key_outlined,
            title: l10n.password,
            trailing: rozet(sifreBagli),
          ),
        ]),
      ),
      const SizedBox(height: RythoSpace.md),
      GlassPanel(
        label: sifreBagli
            ? l10n.changePasswordSection
            : l10n.setPasswordSection,
        child: Form(
          key: _formKey,
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  sifreBagli ? l10n.changePasswordBody : l10n.setPasswordBody,
                  style: RythoType.caption,
                ),
                const SizedBox(height: RythoSpace.md),
                if (!sifreBagli) ...[
                  // Apple "Hide My Email" gerçeği: adres varsayılmaz,
                  // düzenlenir.
                  TextFormField(
                    controller: _emailCtrl,
                    keyboardType: TextInputType.emailAddress,
                    autocorrect: false,
                    autofillHints: const [AutofillHints.email],
                    style: RythoType.body,
                    decoration: InputDecoration(labelText: l10n.email),
                    validator: (v) {
                      final deger = v?.trim() ?? '';
                      return deger.isEmpty || !deger.contains('@')
                          ? l10n.authInvalidEmail
                          : null;
                    },
                  ),
                  const SizedBox(height: RythoSpace.md),
                ],
                // Yeni şifre belirleme KAYIT gibidir: tekrar + kural.
                SifreAlanlari(
                  sifre: _passCtrl,
                  tekrar: _pass2Ctrl,
                  onSubmitted: _sifreKaydet,
                ),
                _HataMetni(_sifreHata,
                    padding: const EdgeInsets.only(top: RythoSpace.sm)),
                const SizedBox(height: RythoSpace.md),
                GoldButton(
                  text: sifreBagli
                      ? l10n.changePasswordAction
                      : l10n.setPasswordAction,
                  busy: _busy,
                  onPressed: _busy ? null : _sifreKaydet,
                ),
              ]),
        ),
      ),
    ]);
  }
}

/// Bölüm altı hata satırı; metin yoksa hiç yer kaplamaz.
class _HataMetni extends StatelessWidget {
  const _HataMetni(this.metin, {required this.padding});

  final String? metin;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final m = metin;
    if (m == null) return const SizedBox.shrink();
    return Padding(
      padding: padding,
      child: Text(m, style: RythoType.caption.copyWith(color: RythoColors.madder)),
    );
  }
}
