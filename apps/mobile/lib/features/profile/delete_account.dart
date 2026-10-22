import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/analytics.dart';
import '../../core/auth_service.dart'
    show AppleIptalSonucu, appleYetkisiniIptalEt, signOutEverywhere;
import '../../core/api.dart';
import '../../core/tr_metin.dart' show onayKelimesiEslesiyor;
import '../../l10n/app_localizations.dart';
import '../../theme/rytho_theme.dart';
import '../../widgets/alt_sayfa.dart' show showRythoSheet;
import '../../widgets/atlas_widgets.dart';
import '../../widgets/onay.dart' show onayliCikis;

/// Hesap silme akışı.
///
/// Apple 5.1.1(v) ve Google Play, hesap oluşturmaya izin veren her uygulamada
/// uygulama içinden silmeyi zorunlu tutuyor. Tek başına red sebebi.
///
/// Tasarım kararları:
/// - **Ne silineceği tek tek yazılır.** "Hesabını sil?" diye sorup detay
///   vermemek, kullanıcının doğum verisinin ve sohbet notlarının gideceğini
///   bilmeden onaylaması demek.
/// - **Ne silinmeyeceği de yazılır.** Şikayet kayıtları kalır; bunu gizlemek
///   dürüst olmaz.
/// - **Abonelik uyarısı ayrı.** Hesabı silmek mağazadaki aboneliği durdurmaz;
///   bunu söylememek kullanıcıya para kaybettirir.
/// - **Yazarak onay.** Tek dokunuşla geri alınamaz bir işlem yaptırmak yanlış.
/// - **Apple yetkisi de iptal edilir** (U15, yalnız iOS + Apple bağlı
///   hesap): bkz. [appleYetkisiniIptalEt].
class DeleteAccountSheet extends ConsumerStatefulWidget {
  const DeleteAccountSheet(
      {super.key, this.appleIptali, this.cikis = signOutEverywhere});

  /// Apple yetkisi iptali — TEST DİKİŞİ; varsayılan [appleYetkisiniIptalEt].
  final Future<AppleIptalSonucu> Function()? appleIptali;

  /// Oturum kapatma yolu — TEST DİKİŞİ (`onayliCikis` ile aynı gerekçe).
  /// Üretimde `signOutEverywhere`: cihaz kilidi, push jetonu ve çakışma
  /// bayrağı orada sırayla iner, buradan tek tek çağrılmaz.
  @visibleForTesting
  final Future<void> Function() cikis;

  @override
  ConsumerState<DeleteAccountSheet> createState() => _DeleteAccountSheetState();
}

class _DeleteAccountSheetState extends ConsumerState<DeleteAccountSheet> {
  final _controller = TextEditingController();
  bool _busy = false;
  String? _error;

  /// 401: sunucu oturum jetonunu kabul etmedi (core/auth.py). Silme ucu
  /// yakın zamanda giriş ŞARTI koymuyor — kullanıcıyı Admin SDK siliyor —
  /// ama geçersiz jetonun tek çaresi yeniden giriş. Metin tek başına
  /// yetmiyordu (ölçüldü 2026-10-10): "çıkış yapıp yeniden gir" diyordu ama
  /// çıkışın kapısı bu sayfada yoktu — kullanıcı sayfayı kapatıp profilde o
  /// satırı aramak zorundaydı. Eylem metnin yanında.
  bool _yenidenGiris = false;

  /// Kullanıcı Apple onayını kapattı ve silme durdu (U15, yalnız iOS).
  /// `errorText` yerine ayrı paragraf: alanın hata satırı tek satıra
  /// kısaltılıyor, bu metin ise nedenini de anlatmak zorunda.
  bool _appleVazgecildi = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _delete(AppLocalizations l10n) async {
    setState(() {
      _busy = true;
      _error = null;
      _appleVazgecildi = false;
    });

    final dio = ref.read(apiProvider);
    try {
      // U15: Apple yetkisi Firebase kullanıcısı HÂLÂ varken iptal edilir —
      // backend sildikten sonra yeniden doğrulayacak kullanıcı kalmaz.
      // Yalnız kullanıcının Apple sayfasını kapatması silmeyi durdurur;
      // iptalin kendisi başarısız olursa silme sürer (gerekçe orada).
      final apple = await (widget.appleIptali ?? appleYetkisiniIptalEt)();
      if (apple == AppleIptalSonucu.vazgecildi) {
        if (mounted) setState(() => _appleVazgecildi = true);
        return;
      }

      await dio.delete('/api/v1/account/me');
      // Kayip analizinde en anlamli sinyal; oturum kapanmadan once gonderilir.
      Analytics.accountDeleted();

      // Sunucu kimliği de sildi; yerel oturumu temizle. Sıra önemli:
      // Firebase oturumu açık kalırsa uygulama silinmiş bir hesapla
      // açılmaya çalışır. (KT4: ortak yol — devralma bayrağı da sıfırlanır.)
      await widget.cikis();

      if (mounted) Navigator.of(context).pop();
    } on DioException catch (e) {
      final yeniden = e.response?.statusCode == 401;
      if (mounted) {
        setState(() {
          _yenidenGiris = yeniden;
          _error =
              yeniden ? l10n.deleteAccountReauth : l10n.deleteAccountFailed;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _error = l10n.deleteAccountFailed);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// 401 sonrası çıkış — ONAYSIZ. Kullanıcı bu sayfada hesabını silmek için
  /// onay sözcüğünü yazdı ve ekrandaki metin çıkışı zaten söylüyor; ikinci
  /// bir soru eylemi geciktirir, korumaz (cihaz çakışma ekranıyla aynı
  /// kural: `onayliCikis(onay: false)`).
  Future<void> _cikisYap() async {
    final gezgin = Navigator.of(context);
    setState(() => _busy = true);
    try {
      await onayliCikis(context, onay: false, cikis: widget.cikis);
      // Çıkış kök ekranı giriş sayfasına çevirir; bu sayfa onun üstünde
      // kalmasın.
      if (mounted) gezgin.pop();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    // `onayKelimesiEslesiyor`: eski karşılaştırma `toUpperCase()` idi ve
    // Türkçe bilmiyordu — "sil" → "SIL" ≠ "SİL", onay düğmesi açıklamasız
    // kapalı kalıyordu (ölçüldü; D2 Türkçe harf).
    final onayli = onayKelimesiEslesiyor(
        _controller.text, l10n.deleteAccountConfirmWord);

    // Kaydırma, güvenli alan ve klavye dolgusu KABUKTAN (`showRythoSheet`)
    // gelir; burada ikinci bir kaydırıcı kurulmaz — iç içe iki kaydırıcı
    // dıştakini kilitler.
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(l10n.deleteAccountTitle,
            style: RythoText.display(20), textAlign: TextAlign.center),
        const SizedBox(height: 14),
        _Paragraph(l10n.deleteAccountBody),
        const SizedBox(height: 10),
        _Paragraph(l10n.deleteAccountKeeps),
        const SizedBox(height: 10),
        _Paragraph(l10n.deleteAccountSubscription, vurgu: true),
        const SizedBox(height: 18),
        TextField(
          controller: _controller,
          autocorrect: false,
          enableSuggestions: false,
          textCapitalization: TextCapitalization.characters,
          style: RythoText.body(15),
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            hintText: l10n.deleteAccountConfirmHint,
            errorText: _error,
            hintStyle:
                RythoText.body(14, color: RythoColors.parchmentDim),
          ),
        ),
        if (_appleVazgecildi) ...[
          const SizedBox(height: 10),
          _Paragraph(l10n.deleteAccountAppleCanceled, vurgu: true),
        ],
        const SizedBox(height: 16),
        if (_yenidenGiris)
          // Silme düğmesi bu hâlde anlamsız (ikinci deneme yine 401 alır);
          // yerini tek işe yarar eylem alır.
          GoldButton(
            text: l10n.signOut,
            busy: _busy,
            onPressed: _busy ? null : _cikisYap,
          )
        else
          GoldButton(
            text: l10n.deleteAccountAction,
            busy: _busy,
            // Yıkıcı: düz madder, degrade ve glow YOK — parıltı davet eder,
            // bu eylem davet edilmez (gold_button_test).
            destructive: true,
            // Onay yazılmadan düğme çalışmaz.
            onPressed: onayli ? () => _delete(l10n) : null,
          ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: Text(l10n.cancel, style: RythoText.label(12)),
        ),
      ]),
    );
  }
}

class _Paragraph extends StatelessWidget {
  const _Paragraph(this.text, {this.vurgu = false});

  final String text;
  final bool vurgu;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: RythoText.body(12.5,
          color: vurgu ? RythoColors.copper : RythoColors.parchmentDim,
          height: 1.5),
    );
  }
}

Future<void> showDeleteAccountSheet(BuildContext context) {
  // Dışarı dokunmayla kapanma açık (kabuk varsayılanı): işlem yazarak onay
  // istediği için kaza riski yok. Kabuk tek (`showRythoSheet`, D3): zemin,
  // köşe, tutamak, kaydırma ve klavye dolgusu burada yeniden yazılmaz.
  return showRythoSheet<void>(
    context,
    klavyeyeUy: true,
    builder: (_) => const DeleteAccountSheet(),
  );
}
