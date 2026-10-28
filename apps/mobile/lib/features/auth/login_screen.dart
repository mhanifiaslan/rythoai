import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/cupertino.dart' show CupertinoActivityIndicator;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart'
    show SignInWithAppleButton, SignInWithAppleButtonStyle;

import '../../core/auth_service.dart';
import '../../l10n/app_localizations.dart';
import '../../theme/rytho_theme.dart';
import '../../theme/rytho_tokens.dart';
import '../../widgets/atlas_widgets.dart';
import '../../widgets/cosmic_scaffold.dart';
import '../../widgets/glass.dart';
import '../../widgets/motion.dart';
import '../../widgets/sifre_alanlari.dart';
import '../profile/legal_page.dart';
import 'forgot_password_screen.dart';

/// Sosyal giriş hatasının üç sınıfı — [socialHataSonucu]nun dönüşü.
enum AuthHataSonucu {
  /// Kullanıcı pencereyi kendi kapattı: ne mesaj ne Crashlytics.
  iptal,

  /// GMS "[16] Account reauth failed": kullanıcının uygulama içinde
  /// yapabileceği bir şey yok, yol gösteren mesaj gerekir.
  reauth,

  /// Geri kalan her şey.
  genel,
}

/// `_runSocial`in karar veren SAF parçası — Firebase'siz test edilsin diye
/// ekran durumundan ayrı.
///
/// İptal hata DEĞİLDİR (bkz. [isAuthCancelled]): eskiden genel `catch`e
/// düşüp "Bir şeyler ters gitti" basıyor ve Crashlytics'e yazılıyordu.
/// Reauth dalı aynen korunur (iç test bulgusu B1): cihazdaki Google oturumu
/// bayatladığında düşer ve nötr mesaj kullanıcıyı çıkmaza sokar.
///
/// Sıra ÖNEMLİ — reauth iptalden ÖNCE: Android'in Credential Manager'ı bu
/// hatayı iptal sınıfıyla bildirebiliyor ve eklenti onu
/// `GoogleSignInExceptionCode.canceled`'a çeviriyor (google_sign_in_android
/// 7.2.15, bkz. [googleYenidenDogrulamaGerekli]). Önce iptale bakılsaydı B1
/// "kullanıcı vazgeçti" sayılıp sessizce yutulurdu.
AuthHataSonucu socialHataSonucu(Object e) {
  if (googleYenidenDogrulamaGerekli(e)) return AuthHataSonucu.reauth;
  if (isAuthCancelled(e)) return AuthHataSonucu.iptal;
  return AuthHataSonucu.genel;
}

/// Giriş ve kayıt.
///
/// Düzen kararı: **form önce, sosyal giriş sonra.** Sosyal düğmeler üstteyken
/// e-posta akışı ikincil görünüyordu; ayrıca Apple'ın kuralı Apple ile
/// Giriş'in diğer sağlayıcılardan daha az görünür olmamasını istiyor.
///
/// Mağaza zorunlulukları burada karşılanıyor:
/// - **Guideline 4.8:** Google sunuluyorsa iOS'ta Apple ile Giriş de zorunlu.
/// - Hukuki metinlere **tıklanabilir** bağlantı: kullanıcı kabul ettiğini
///   okuyabilmeli. Eskiden yalnızca "kabul etmiş olursun" yazıyordu.
/// - Kayıtta yaş beyanı: kullanım şartlarındaki 13 yaş sınırının arayüzdeki
///   karşılığı. Sözleşmede olup ekranda olmayan şart yok hükmündedir.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, this.googleSignIn, this.appleSignIn});

  /// Test dikişleri; üretimde [signInWithGoogle] / [signInWithApple].
  /// İptal/hata sınıflandırması Firebase ayakta olmadan sabitlenebilsin.
  final Future<void> Function()? googleSignIn;
  final Future<void> Function()? appleSignIn;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  /// 0: Giriş yap, 1: Üye ol
  int _segment = 0;

  bool _googleBusy = false;
  bool _appleBusy = false;
  bool _emailBusy = false;

  /// Herhangi bir giriş sürüyorsa tüm yollar kilitlenir; aksi halde iki
  /// giriş aynı anda başlatılabiliyordu.
  bool get _busy => _googleBusy || _appleBusy || _emailBusy;

  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _pass2Ctrl = TextEditingController();

  // Klavyedeki "Sonraki" tuşunun çalışması için odak zinciri gerekiyor;
  // Flutter alanlar arası geçişi kendiliğinden yapmaz. Şifre → tekrar
  // geçişi `SifreAlanlari`nin içinde.
  final _emailFocus = FocusNode();
  final _passFocus = FocusNode();

  bool _ageConfirmed = false;
  bool _ageError = false;

  @override
  void dispose() {
    for (final c in [_nameCtrl, _emailCtrl, _passCtrl, _pass2Ctrl]) {
      c.dispose();
    }
    for (final f in [_emailFocus, _passFocus]) {
      f.dispose();
    }
    super.dispose();
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  /// Sekme değişince formu sıfırla.
  ///
  /// Eskiden şifre alanı ve hata mesajları geçişte duruyordu; kullanıcı
  /// "Üye ol"a geçtiğinde giriş denemesinden kalan şifreyi görüyordu.
  void _changeSegment(int index) {
    if (index == _segment) return;
    setState(() {
      _segment = index;
      _passCtrl.clear();
      _pass2Ctrl.clear();
      _ageError = false;
      _formKey.currentState?.reset();
    });
  }

  // Hata haritası core/auth_service.authErrorText'e taşındı (OT2):
  // şifre panosu da aynı haritayı kullanıyor; iki kopya ayrışırdı.
  String _authErrorMessage(FirebaseAuthException e) =>
      authErrorText(AppLocalizations.of(context), e);

  Future<void> _runSocial(
      Future<void> Function() action, void Function(bool) setBusy) async {
    final l10n = AppLocalizations.of(context);
    setState(() => setBusy(true));
    try {
      await action();
    } catch (e) {
      switch (socialHataSonucu(e)) {
        case AuthHataSonucu.iptal:
          // Kullanıcı vazgeçti: hiçbir şey olmadı ve bunu kendisi biliyor.
          // Mesaj basmak azarlamak, Crashlytics'e yazmak sayacı şişirmek olur.
          break;
        case AuthHataSonucu.reauth:
          _showSnack(l10n.authReauthNeeded);
        case AuthHataSonucu.genel:
          if (e is FirebaseAuthException) {
            if (!kDebugMode && sosyalGirisHatasiKaydedilir(e.code)) {
              // Mesaj da yazılır: arızanın sebebi orada ("Invalid OAuth
              // response from apple.com"); bu kodların mesajı e-posta
              // taşımıyor (hesap çakışması bilerek kümede değil).
              FirebaseCrashlytics.instance.recordError(
                  'social-signin-firebase: ${e.code} ${e.message}',
                  StackTrace.current,
                  fatal: false);
            }
            _showSnack(sosyalGirisHataMetni(l10n, e));
            break;
          }
          if (!kDebugMode) {
            FirebaseCrashlytics.instance.recordError(
                'social-signin: $e', StackTrace.current,
                fatal: false);
          }
          _showSnack(l10n.authFailed);
      }
    } finally {
      if (mounted) setState(() => setBusy(false));
    }
  }

  Future<void> _submitEmail() async {
    final l10n = AppLocalizations.of(context);
    FocusScope.of(context).unfocus();

    final isRegister = _segment == 1;
    // Yaş beyanı form doğrulamasının dışında (onay kutusu), ayrıca kontrol.
    if (isRegister && !_ageConfirmed) {
      setState(() => _ageError = true);
      _showSnack(l10n.ageRequired);
      return;
    }
    // Kayıt şifresi kuralı (`validatePassword`) `SifreAlanlari`nin
    // doğrulayıcısında koşar; `validate()` onu da kapsar.
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() => _emailBusy = true);
    final email = _emailCtrl.text.trim();
    try {
      if (isRegister) {
        await registerWithEmail(
          email: email,
          password: _passCtrl.text,
          displayName: _nameCtrl.text.trim(),
        );
        _showSnack(l10n.verificationSent(email));
      } else {
        await signInWithEmail(email, _passCtrl.text);
      }
      // Yönlendirme _Gate üzerinden otomatik olur.
    } on FirebaseAuthException catch (e) {
      // Google/Apple ile açılmış bir hesaba şifreyle girilmeye çalışılıyorsa
      // Firebase yalnızca "geçersiz kimlik" diyor ve kullanıcı çıkmaza
      // giriyordu. Hangi sağlayıcının kullanıldığını sormak mümkün değil
      // (bkz. core/auth_service.dart) — bu yüzden her iki olasılığı birden
      // söylüyoruz. Bilgi sızdırmadan çıkmazı çözer.
      if (!isRegister && e.code == 'invalid-credential') {
        _showSnack(l10n.useGoogleInstead);
        return;
      }
      _showSnack(_authErrorMessage(e));
    } catch (_) {
      _showSnack(l10n.authFailed);
    } finally {
      if (mounted) setState(() => _emailBusy = false);
    }
  }

  /// Şifre sıfırlama — ayrı panoya gider (OT2, kullanıcı isteği).
  ///
  /// Eski akış e-postanın burada yazılı olmasını şart koşuyor ve her
  /// sonucu "gönderildi" snackbar'ıyla kapatıyordu; pano gerçek hataları
  /// anlatır, başarıyı tekrar-gönder seçeneğiyle gösterir.
  void _resetPassword() {
    Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => ForgotPasswordScreen(
            initialEmail: _emailCtrl.text.trim())));
  }

  Widget _buildEmailForm() {
    final l10n = AppLocalizations.of(context);
    final isRegister = _segment == 1;

    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (isRegister) ...[
            TextFormField(
              controller: _nameCtrl,
              style: RythoText.body(15),
              textCapitalization: TextCapitalization.words,
              keyboardType: TextInputType.name,
              textInputAction: TextInputAction.next,
              // Şifre yöneticilerinin alanları tanıması için; olmadan
              // otomatik doldurma ve "güçlü şifre öner" hiç çalışmıyordu.
              autofillHints: const [AutofillHints.name],
              onFieldSubmitted: (_) => _emailFocus.requestFocus(),
              decoration: InputDecoration(labelText: l10n.nameLabel),
              validator: (v) => (v == null || v.trim().isEmpty)
                  ? l10n.authNameRequired
                  : null,
            ),
            const SizedBox(height: 12),
          ],
          TextFormField(
            controller: _emailCtrl,
            focusNode: _emailFocus,
            style: RythoText.body(15),
            keyboardType: TextInputType.emailAddress,
            autocorrect: false,
            textInputAction: TextInputAction.next,
            autofillHints: const [AutofillHints.email],
            onFieldSubmitted: (_) => _passFocus.requestFocus(),
            decoration: InputDecoration(labelText: l10n.email),
            validator: (v) {
              final value = v?.trim() ?? '';
              if (value.isEmpty || !value.contains('@')) {
                return l10n.authInvalidEmail;
              }
              return null;
            },
          ),
          const SizedBox(height: 12),
          // Şifre alanları tek bileşenden (D3): kayıtta tekrar + kural,
          // girişte TEK alan ve kural YOK — eski hesapların şifresi daha
          // zayıf olabilir ve kendi kuralımız yüzünden kimseyi kendi
          // hesabından dışarıda bırakamayız (sahip uyarısı, D3 kapanışı).
          SifreAlanlari(
            sifre: _passCtrl,
            tekrar: _pass2Ctrl,
            tekrarIste: isRegister,
            kuralDayat: isRegister,
            odak: _passFocus,
            onSubmitted: _submitEmail,
          ),
          if (isRegister) ...[
            const SizedBox(height: 6),
            // Yaş beyanı — kullanım şartlarındaki 13 yaş sınırının karşılığı.
            CheckboxListTile(
              value: _ageConfirmed,
              onChanged: (v) => setState(() {
                _ageConfirmed = v ?? false;
                if (_ageConfirmed) _ageError = false;
              }),
              contentPadding: EdgeInsets.zero,
              dense: true,
              controlAffinity: ListTileControlAffinity.leading,
              activeColor: RythoColors.magenta,
              title: Text(l10n.ageConfirm,
                  style: RythoText.body(13,
                      color: _ageError
                          ? RythoColors.copper
                          : RythoColors.parchment)),
            ),
          ],
          const SizedBox(height: 12),
          GoldButton(
            text: isRegister ? l10n.signUp : l10n.signIn,
            busy: _emailBusy,
            onPressed: _busy ? null : _submitEmail,
          ),
          if (!isRegister) ...[
            const SizedBox(height: 8),
            Center(
              child: TextButton(
                onPressed: _busy ? null : _resetPassword,
                child: Text(
                  l10n.forgotPassword,
                  style: RythoText.body(13, color: RythoColors.parchmentDim)
                      .copyWith(
                          decoration: TextDecoration.underline,
                          decorationColor: RythoColors.parchmentDim),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Hukuki onay — metinler TIKLANABİLİR.
  ///
  /// Kullanıcının kabul ettiği şeyi okuyamaması hem hukuki bir boşluk hem
  /// mağaza incelemesinde sorulan bir madde.
  Widget _buildConsent() {
    final l10n = AppLocalizations.of(context);
    final normal = RythoText.body(11, color: RythoColors.parchmentDim);
    final link = normal.copyWith(
      color: RythoColors.lilac,
      decoration: TextDecoration.underline,
      decorationColor: RythoColors.lilac,
    );

    return Column(children: [
      Text.rich(
        TextSpan(children: [
          TextSpan(text: l10n.consentPrefix, style: normal),
          WidgetSpan(
            alignment: PlaceholderAlignment.baseline,
            baseline: TextBaseline.alphabetic,
            child: GestureDetector(
              // Hukuk sayfası tek kapıdan (D3 `openLegal`): bu ekran son
              // kopyaydı, sihirbazla ayrı dil seçimi yapıyordu.
              onTap: () => openLegal(context, LegalDoc.terms),
              child: Text(l10n.termsOfUse, style: link),
            ),
          ),
          TextSpan(text: l10n.consentAnd, style: normal),
          WidgetSpan(
            alignment: PlaceholderAlignment.baseline,
            baseline: TextBaseline.alphabetic,
            child: GestureDetector(
              onTap: () => openLegal(context, LegalDoc.privacy),
              child: Text(l10n.privacyPolicy, style: link),
            ),
          ),
          TextSpan(text: l10n.consentSuffix, style: normal),
        ]),
        textAlign: TextAlign.center,
      ),
      const SizedBox(height: 8),
      // Sorumluluk reddi ayrı bir cümle: hukuki onayla aynı paragrafta
      // olduğunda ikisi de okunmuyordu.
      Text(l10n.insightNote, textAlign: TextAlign.center, style: normal),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    // Giriş hareketi tek yoldan (D2 hareket disiplini): beş blok
    // `RythoReveal(index:)` ile tek stagger'da belirir. Eski yerel sayaç
    // (`next()`) yedi ekranın kopyaladığı desendi; logonun "nefes"i ise
    // kapısız sonsuz döngüydü ve beyaz listede değildi — kaldırıldı, logo
    // sabit durur.
    return CosmicScaffold(
      body: SafeArea(
        // AutofillGroup olmadan şifre yöneticileri alanları tek bir form
        // olarak görmüyor ve kaydetmeyi önermiyor.
        child: AutofillGroup(
          child: ListView(
            padding: const EdgeInsets.symmetric(
                horizontal: RythoSpace.xl, vertical: RythoSpace.lg),
            children: [
              // ---------- MARKA BLOĞU ----------
              //
              // Eskiden dikey bir kule idi: 92 px rozet, altında RYTHO, altında
              // 30 punto başlık, altında slogan — aralarında 26/8/12 px. Tek
              // başına ~250 px, yani ekranın üçte biri, klavye açılmadan.
              //
              // Rozet ve ad artık YAN YANA. Aynı bilgi, ~140 px daha az yer.
              // Gerçek logo (Revize R7): beyaz hilal + takımyıldız,
              // assets/brand.
              RythoReveal(
                index: 0,
                slide: 0,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Image.asset(
                      'assets/brand/rytho_logo_512.png',
                      width: 56,
                      height: 56,
                      filterQuality: FilterQuality.medium,
                    ),
                    const SizedBox(width: RythoSpace.md),
                    // Marka yazısı esnemiyordu: 22 punto + büyük yazı ölçeği
                    // + 56 px logo dar ekranda satırı taşırıyordu.
                    Flexible(
                      child: Text(kMarkaAdi,
                          style:
                              RythoText.label(22, color: RythoColors.lilac)),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: RythoSpace.lg),
              RythoReveal(
                index: 1,
                child: Center(
                  child: Text(l10n.appHeadline,
                      textAlign: TextAlign.center,
                      style: RythoText.display(24)),
                ),
              ),
              const SizedBox(height: RythoSpace.sm),
              RythoReveal(
                index: 2,
                slide: 0,
                child: Text(
                  l10n.appTagline,
                  textAlign: TextAlign.center,
                  style: RythoType.bodyDim,
                ),
              ),
              const SizedBox(height: RythoSpace.xl),

              // Form önce.
              RythoReveal(
                index: 3,
                child: GlassPanel(
                  margin: EdgeInsets.zero,
                  padding: const EdgeInsets.fromLTRB(0, 16, 0, 18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      GlassSegments(
                        labels: [l10n.signIn, l10n.signUp],
                        index: _segment,
                        onChanged: _changeSegment,
                      ),
                      const SizedBox(height: 18),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: _buildEmailForm(),
                      ),
                    ],
                  ),
                ),
              ),

              Padding(
                padding:
                    const EdgeInsets.symmetric(vertical: RythoSpace.md),
                child: Row(children: [
                  const Expanded(child: Divider()),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: RythoSpace.md),
                    child: Text(l10n.orDivider, style: RythoType.caption),
                  ),
                  const Expanded(child: Divider()),
                ]),
              ),

              // ---------- SOSYAL GİRİŞ ----------
              //
              // Üçü de (e-posta, Apple, Google) birebir aynı degradede alt
              // alta duruyordu. Bir ekranda birden fazla "birincil" varsa
              // hiçbiri birincil değildir; kullanıcı hangisinin asıl yol
              // olduğunu okuyamıyordu. Tek degrade buton formun içindeki
              // gönder butonu.
              //
              // Apple (yalnız iOS) kendi HIG düğmesiyle çizilir (U04):
              // App Review Apple ile Giriş düğmesini logo, başlık ve
              // siyah/beyaz stil üzerinden denetler; eski altın çerçeveli,
              // logosuz metin düğmesi 4.0/4.8 reddi riskiydi. Apple'ın kuralı
              // bu düğmenin diğer üçüncü taraf seçeneklerden daha az görünür
              // olmamasını istiyor; beyaz dolgu ve üstteki yeri bunu karşılar.
              //
              // Google'da marka işareti YOK: Google logosunun yalnız resmi
              // varlıkla kullanılmasını şart koşuyor ve depoda o varlık yok;
              // yaklaştırılmış bir logo çizmek marka kuralını çiğner.
              if (appleSignInAvailable) ...[
                _AppleGirisDugmesi(
                  baslik: l10n.signInWithApple,
                  mesgul: _appleBusy,
                  kilitli: _busy,
                  onPressed: () => _runSocial(
                      widget.appleSignIn ?? signInWithApple,
                      (v) => _appleBusy = v),
                ),
                const SizedBox(height: RythoSpace.sm),
              ],
              GoldButton(
                text: l10n.signInWithGoogle,
                busy: _googleBusy,
                filled: false,
                onPressed: _busy
                    ? null
                    : () => _runSocial(
                        widget.googleSignIn ?? signInWithGoogle,
                        (v) => _googleBusy = v),
              ),

              const SizedBox(height: RythoSpace.lg),
              RythoReveal(index: 4, slide: 0, child: _buildConsent()),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}

/// Apple ile Giriş — `sign_in_with_apple`'ın HIG düğmesi (U04).
///
/// Stil BEYAZ, çerçevesiz: zemin koyu mürekkep ve HIG beyaz-çerçeveli
/// varyantı koyu/doygun zeminde açıkça yasaklıyor (denetimde ilk öneri
/// `whiteOutlined`'dı, doğrulayıcı düzeltti). Logo paketin
/// `AppleLogoPainter`'ıyla çizilir — elle yaklaştırılmış logo değil.
///
/// Yükseklik ve köşe yarıçapı [GoldButton]'la eş (52 / 18): Google
/// düğmesinin hemen üstünde duruyor ve farklı boyda bir ikili dağınık
/// görünüyordu. 52, HIG'in önerdiği 44 pt'nin üstünde.
///
/// Paket düğmesinin meşgul durumu yok. `onPressed: null` vermek de çözüm
/// değil: `CupertinoButton` o zaman dolguyu gri "devre dışı" rengine
/// boyuyor ve düğme HIG stilinden çıkıyor. Bu yüzden kilit
/// `IgnorePointer` + soluklaştırmayla, meşguliyet sağ kenarda bir
/// göstergeyle verilir — ortadaki logo ve başlığın üstüne binmesin.
class _AppleGirisDugmesi extends StatelessWidget {
  const _AppleGirisDugmesi({
    required this.baslik,
    required this.mesgul,
    required this.kilitli,
    required this.onPressed,
  });

  final String baslik;

  /// Apple girişi sürüyor: gösterge görünür.
  final bool mesgul;

  /// Herhangi bir giriş sürüyor: dokunuş geçmez (ikinci bir OAuth akışı
  /// başlamasın).
  final bool kilitli;

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Stack(alignment: Alignment.center, children: [
      IgnorePointer(
        ignoring: kilitli,
        child: Opacity(
          opacity: kilitli ? 0.6 : 1,
          // Apple'ın ölçüsünde başlık puntosu düğme yüksekliğinin %43'ü
          // (paket bunu uyguluyor). Sistem yazı ölçeği bunun üstüne binerse
          // o oran bozulur ve başlık sabit yükseklikli düğmeye sığmayabilir;
          // büyüklüğü yükseklik belirler.
          child: MediaQuery.withNoTextScaling(
            child: SignInWithAppleButton(
              text: baslik,
              style: SignInWithAppleButtonStyle.white,
              height: 52,
              borderRadius: BorderRadius.circular(RythoRadius.button),
              onPressed: onPressed,
            ),
          ),
        ),
      ),
      if (mesgul)
        const Positioned(
          right: 18,
          child: CupertinoActivityIndicator(color: Colors.black54),
        ),
    ]);
  }
}
