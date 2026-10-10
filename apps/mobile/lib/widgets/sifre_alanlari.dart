/// Şifre + tekrar + kural ipucu + göz düğmesi — şifre isteyen her formun
/// TEK alan çifti.
///
/// ## Neden var
/// Ölçüldü (2026-10-10): kayıt formu (login_screen) şifreyi kuralla, tekrar
/// alanıyla ve ipucuyla alıyordu; şifre değiştirme (sign_in_methods) aynı
/// şifreyi tek alanda, kuralsız ve tekrarsız alıyordu. Yani zayıf ya da
/// yanlış yazılmış bir şifre KAYITTA yakalanıyor, DEĞİŞTİRMEDE
/// yakalanmıyordu — kullanıcı yeni şifresini bir kez yanlış yazınca
/// hesabından düşüyordu. Kural `validatePassword` (core/auth_service.dart)
/// ile tek yerde; burada yalnız görünümü var.
library;

import 'package:flutter/material.dart';

import '../core/auth_service.dart' show PasswordIssue, validatePassword;
import '../l10n/app_localizations.dart';
import '../theme/rytho_theme.dart';
import '../theme/rytho_tokens.dart';

class SifreAlanlari extends StatefulWidget {
  const SifreAlanlari({
    super.key,
    required this.sifre,
    this.tekrar,
    this.tekrarIste = true,
    this.onSubmitted,
  });

  final TextEditingController sifre;

  /// Tekrar alanının denetleyicisi; verilmezse widget kendi kurar ve
  /// kapatır.
  final TextEditingController? tekrar;

  /// `false` → yalnız tek alan (giriş gibi tekrar istemeyen yerler).
  final bool tekrarIste;

  /// Son alanda klavyeden "bitti" basılınca.
  final VoidCallback? onSubmitted;

  @override
  State<SifreAlanlari> createState() => _SifreAlanlariState();
}

class _SifreAlanlariState extends State<SifreAlanlari> {
  bool _gizli = true;
  bool _tekrarGizli = true;
  final _tekrarOdak = FocusNode();
  TextEditingController? _icTekrar;

  TextEditingController get _tekrar =>
      widget.tekrar ?? (_icTekrar ??= TextEditingController());

  @override
  void dispose() {
    _tekrarOdak.dispose();
    _icTekrar?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextFormField(
          controller: widget.sifre,
          style: RythoType.body,
          obscureText: _gizli,
          autocorrect: false,
          enableSuggestions: false,
          textInputAction:
              widget.tekrarIste ? TextInputAction.next : TextInputAction.done,
          autofillHints: const [AutofillHints.newPassword],
          onFieldSubmitted: (_) => widget.tekrarIste
              ? _tekrarOdak.requestFocus()
              : widget.onSubmitted?.call(),
          decoration: InputDecoration(
            labelText: l10n.password,
            helperText: l10n.passwordRuleHint,
            helperStyle: RythoType.caption,
            suffixIcon: _GozDugmesi(
              gizli: _gizli,
              label: l10n.password,
              onTap: () => setState(() => _gizli = !_gizli),
            ),
          ),
          validator: (v) => switch (validatePassword(v ?? '')) {
            PasswordIssue.tooShort => l10n.passwordTooShort,
            PasswordIssue.tooSimple => l10n.passwordTooSimple,
            null => null,
          },
        ),
        if (widget.tekrarIste) ...[
          const SizedBox(height: RythoSpace.md),
          TextFormField(
            controller: _tekrar,
            focusNode: _tekrarOdak,
            style: RythoType.body,
            obscureText: _tekrarGizli,
            autocorrect: false,
            enableSuggestions: false,
            textInputAction: TextInputAction.done,
            autofillHints: const [AutofillHints.newPassword],
            onFieldSubmitted: (_) => widget.onSubmitted?.call(),
            decoration: InputDecoration(
              labelText: l10n.passwordRepeat,
              suffixIcon: _GozDugmesi(
                gizli: _tekrarGizli,
                label: l10n.passwordRepeat,
                onTap: () => setState(() => _tekrarGizli = !_tekrarGizli),
              ),
            ),
            // Tekrar alanı KENDİ kuralını koşturmaz; yalnız eşleşmeye
            // bakar — iki alanda iki ayrı hata aynı anda okunmaz.
            validator: (v) =>
                v != widget.sifre.text ? l10n.passwordsDoNotMatch : null,
          ),
        ],
      ],
    );
  }
}

/// Göz düğmesi: gizle/göster. Tooltip alan adını taşır ki ekran okuyucu
/// "düğme" yerine hangi alanın gözü olduğunu duysun.
class _GozDugmesi extends StatelessWidget {
  const _GozDugmesi(
      {required this.gizli, required this.label, required this.onTap});

  final bool gizli;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onTap,
      tooltip: label,
      icon: Icon(
        gizli ? Icons.visibility_outlined : Icons.visibility_off_outlined,
        size: 18,
        color: RythoColors.parchmentDim,
      ),
    );
  }
}
