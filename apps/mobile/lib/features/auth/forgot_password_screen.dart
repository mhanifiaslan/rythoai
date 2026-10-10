/// Şifre sıfırlama panosu (OT2) — kullanıcı isteği: "şifre unutma boardı".
///
/// Eski akış login ekranındaki tek TextButton'du: e-postanın orada yazılı
/// olmasını şart koşuyor, TÜM hataları yutup (offline, kota, yapılandırma)
/// her durumda "gönderildi" diyordu — kullanıcı e-postayı hiç alamıyordu.
///
/// Bu pano: e-posta alanı (login'den önceden dolu gelir) → gönder →
/// GERÇEK hata haritası (yalnız `user-not-found` başarı gibi gösterilir —
/// "bu adres kayıtlı mı" bilgisi sızmaz) → başarı görünümünde spam ipucu
/// ve bekleme süreli "tekrar gönder".
library;

import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../core/auth_service.dart';
import '../../l10n/app_localizations.dart';
import '../../theme/rytho_theme.dart';
import '../../theme/rytho_tokens.dart';
import '../../widgets/atlas_widgets.dart';
import '../../widgets/cosmic_scaffold.dart';
import '../../widgets/glass.dart';

/// "Tekrar gönder" bekleme süresi — hızlı art arda istekler Firebase'in
/// `too-many-requests` duvarına çarpıyor; duvara çarptırmamak, hatayı
/// açıklamaktan iyidir.
const int kResendCooldownSeconds = 30;

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key, this.initialEmail, this.sender});

  /// Login ekranındaki e-posta alanından taşınır; kullanıcı yeniden yazmaz.
  final String? initialEmail;

  /// Test dikişi: üretimde [sendPasswordReset] (FirebaseAuth), testte
  /// sahte gönderici — ekranın hata/başarı davranışı Firebase olmadan
  /// sabitlenebilsin.
  final Future<void> Function(String email)? sender;

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  late final TextEditingController _emailCtrl =
      TextEditingController(text: widget.initialEmail ?? '');
  bool _busy = false;
  bool _sent = false;
  String? _error;
  int _cooldown = 0;
  Timer? _timer;

  @override
  void dispose() {
    _timer?.cancel();
    _emailCtrl.dispose();
    super.dispose();
  }

  void _startCooldown() {
    _timer?.cancel();
    setState(() => _cooldown = kResendCooldownSeconds);
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return t.cancel();
      setState(() => _cooldown -= 1);
      if (_cooldown <= 0) t.cancel();
    });
  }

  Future<void> _send() async {
    final l10n = AppLocalizations.of(context);
    final email = _emailCtrl.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      setState(() => _error = l10n.authInvalidEmail);
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await (widget.sender ?? sendPasswordReset)(email);
      if (!mounted) return;
      setState(() => _sent = true);
      _startCooldown();
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      if (e.code == 'user-not-found') {
        // Kullanıcı sayımı koruması: kayıtsız adres de "gönderildi"
        // görür — ama yalnız BU durumda; gerçek hatalar anlatılır.
        setState(() => _sent = true);
        _startCooldown();
      } else {
        setState(() => _error = authErrorText(l10n, e));
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error = AppLocalizations.of(context).authFailed);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return CosmicScaffold(
      appBar: AppBar(title: Text(l10n.forgotPasswordTitle)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
              RythoSpace.xl, RythoSpace.lg, RythoSpace.xl, RythoSpace.xxl),
          children: [
            GlassPanel(
              child: _sent ? _basari(l10n) : _form(l10n),
            ),
          ],
        ),
      ),
    );
  }

  Widget _form(AppLocalizations l10n) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(l10n.forgotPasswordBody, style: RythoType.bodyDim),
      const SizedBox(height: RythoSpace.lg),
      TextField(
        controller: _emailCtrl,
        autofocus: _emailCtrl.text.isEmpty,
        keyboardType: TextInputType.emailAddress,
        autofillHints: const [AutofillHints.email],
        autocorrect: false,
        style: RythoText.body(15),
        onSubmitted: (_) => _busy ? null : _send(),
        decoration: InputDecoration(
          // Sabit 'ornek@eposta.com' İngilizce arayüzde Türkçe kalıyordu;
          // örnek adres de kullanıcıya görünen metin, sözlükten gelir.
          hintText: l10n.emailHint,
          errorText: _error,
          hintStyle: RythoText.body(15, color: RythoColors.parchmentDim),
        ),
      ),
      const SizedBox(height: RythoSpace.xl),
      GoldButton(
        text: l10n.forgotPasswordSend,
        busy: _busy,
        onPressed: _send,
      ),
    ]);
  }

  Widget _basari(AppLocalizations l10n) {
    final beklemede = _cooldown > 0;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        const Icon(Icons.mark_email_read_outlined,
            size: 22, color: RythoColors.celadon),
        const SizedBox(width: RythoSpace.sm),
        Expanded(
          child: Text(l10n.forgotPasswordSentTitle,
              style: RythoText.display(17)),
        ),
      ]),
      const SizedBox(height: RythoSpace.md),
      Text(l10n.forgotPasswordSentBody(_maskele(_emailCtrl.text.trim())),
          style: RythoType.bodyDim),
      const SizedBox(height: RythoSpace.md),
      Text(l10n.forgotPasswordSpamHint,
          style: RythoText.body(12.5, color: RythoColors.parchmentDim)),
      const SizedBox(height: RythoSpace.xl),
      GoldButton(
        text: beklemede
            ? l10n.forgotPasswordResendWait(_cooldown)
            : l10n.forgotPasswordResend,
        filled: false,
        busy: _busy,
        onPressed: beklemede ? null : _send,
      ),
    ]);
  }
}

/// E-postayı kısmen gizler: "aslan.mh@gmail.com" → "as•••@gmail.com".
/// Ekranı omuz üstünden gören biri tam adresi okuyamasın.
String _maskele(String email) {
  final at = email.indexOf('@');
  if (at <= 2) return email;
  return '${email.substring(0, 2)}•••${email.substring(at)}';
}
