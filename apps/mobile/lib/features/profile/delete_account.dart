import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/analytics.dart';
import '../../core/auth_service.dart'
    show
        AppleIptalSonucu,
        appleHesabaBagli,
        appleYetkisiniIptalEt,
        signOutEverywhere;
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
      {super.key,
      this.appleIptali,
      this.saglayicilar,
      this.cikis = signOutEverywhere});

  /// Apple yetkisi iptali — TEST DİKİŞİ; varsayılan [appleYetkisiniIptalEt].
  /// Aldığı geri çağrı, kullanıcı Apple sayfasını onayladığı an çağrılır.
  final Future<AppleIptalSonucu> Function(void Function() onayVerildi)?
      appleIptali;

  /// Oturumun sağlayıcıları — TEST DİKİŞİ; varsayılan oturumdakiler. Hem
  /// Apple uyarısı hem iptal adımı [appleHesabaBagli]'yı BU girdiyle
  /// hesaplar; ayrı girdiyle hesaplasalar uyarı ile adım ayrışabilirdi.
  @visibleForTesting
  final Iterable<String>? saglayicilar;

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

  /// Sunucudaki silme (ya da ona giden Apple iptali) sürüyor. [_busy]'den
  /// AYRI: Apple bağlı hesapta düğmeye basıldığı an henüz hiçbir şey
  /// silinmiyor, Apple'ın onayı bekleniyor — "siliniyor" o an yanlış olurdu.
  bool _siliniyor = false;

  /// Silmeden önce Apple'ın kendi onay sayfası açılacak mı (U15). Önceden
  /// söylenmesi şart: iPad'de (2026-10-28, onarım öncesi paket) sayfa
  /// Apple Kimliğinin e-postasını (bir Gmail adresi) gösterdiği için
  /// sahibi onu "Gmail ile giriş" sandı ve reddetti. O denemede hesap
  /// silinmedi; ama günlükte `canceled` değil `unknown` (1000) vardı ve
  /// kod onu `basarisiz` sayıp silmeyi SÜRDÜRÜR — neden silinmediği
  /// ölçülmedi. Uyarı bu yüzden kapatmanın sonucuna dair söz vermez.
  late final bool _appleOnayiGelecek = appleHesabaBagli(widget.saglayicilar);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _delete(AppLocalizations l10n) async {
    final gezgin = Navigator.of(context);
    setState(() {
      _busy = true;
      _siliniyor = !_appleOnayiGelecek;
      _error = null;
      _appleVazgecildi = false;
    });
    void siliniyor() {
      if (mounted && !_siliniyor) setState(() => _siliniyor = true);
    }

    final dio = ref.read(apiProvider);
    try {
      // U15: Apple yetkisi Firebase kullanıcısı HÂLÂ varken iptal edilir —
      // backend sildikten sonra yeniden doğrulayacak kullanıcı kalmaz.
      // Yalnız kullanıcının Apple sayfasını kapatması silmeyi durdurur;
      // iptalin kendisi başarısız olursa silme sürer (gerekçe orada).
      final apple = await (widget.appleIptali ??
          (onay) => appleYetkisiniIptalEt(
              saglayicilar: widget.saglayicilar, onayVerildi: onay))(siliniyor);
      if (apple == AppleIptalSonucu.vazgecildi) {
        if (mounted) setState(() => _appleVazgecildi = true);
        return;
      }
      // Apple sayfası arızayla (onaysız) düştüyse de silme sürüyor.
      siliniyor();

      await dio.delete('/api/v1/account/me');
      // Kayip analizinde en anlamli sinyal; oturum kapanmadan once gonderilir.
      Analytics.accountDeleted();

      // Sunucu kimliği de sildi; yerel oturumu temizle. Sıra önemli:
      // Firebase oturumu açık kalırsa uygulama silinmiş bir hesapla
      // açılmaya çalışır. (KT4: ortak yol — devralma bayrağı da sıfırlanır.)
      await widget.cikis();

      // Yalnız bu sayfayı kapatmak YETMİYORDU: altında basılı Hesap sayfası
      // giriş sayfasının üstünde kalıyordu (iPad, 2026-10-28). Köke kadar
      // inilir — `GateRootGuard` oturum kapanınca aynısını kare sonrasında
      // yapar; `popUntil(isFirst)` iki kez koşsa da kökü asla atmaz. Düz
      // `pop()` bekçiden SONRA koşarsa kök rotayı atıp ekranı boş
      // bırakırdı. `mounted` aranmaz: bekçi yığını bu satırdan önce
      // indirmiş olabilir; yakalanmış navigatörle çağrı yine güvenli.
      gezgin.popUntil((r) => r.isFirst);
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
      if (mounted) {
        setState(() {
          _busy = false;
          _siliniyor = false;
        });
      }
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
      // Çıkış kök ekranı giriş sayfasına çevirir; bu sayfa ve altındaki
      // Hesap sayfası onun üstünde kalmasın (gerekçe [_delete]'te).
      gezgin.popUntil((r) => r.isFirst);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Silme uçarken sayfa kapanmaz (dışarı dokunma, geri hareketi): kapansa
    // `mounted` düşer ve hata metni de 401'in çıkış çaresi de kullanıcıya
    // hiç gösterilmezdi — "silindi mi düştü mü" bilinmez kalırdı.
    // Sürükleme `PopScope`a sormadığı için kabukta ayrıca kapalı.
    return PopScope(canPop: !_busy, child: _govde(context));
  }

  Widget _govde(BuildContext context) {
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
        if (_appleOnayiGelecek && !_appleVazgecildi) ...[
          const SizedBox(height: 10),
          _Paragraph(l10n.deleteAccountAppleNotice),
        ],
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
        // Silme sürerken sayfa aynı kalıyordu, yalnız düğmede küçük bir
        // dönen işaret vardı; iPad'de "donmuş" okundu (2026-10-28). Apple
        // onayı beklenirken görünmez: o an uyarı paragrafı konuşur.
        if (_siliniyor) ...[
          const SizedBox(height: 10),
          Semantics(
            liveRegion: true,
            child: Text(l10n.deleteAccountInProgress,
                textAlign: TextAlign.center,
                style: RythoText.body(12.5,
                    color: RythoColors.parchmentDim, height: 1.5)),
          ),
        ],
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
  // Silme BAŞLAMADAN dışarı dokunmayla kapanma açık: işlem yazarak onay
  // istediği için başlatma kazası yok. Silme uçarken sayfa kendini
  // `PopScope` ile kilitler; sürükleme o kilide sormadığı için burada hep
  // kapalı. Kabuk tek (`showRythoSheet`, D3): zemin, köşe, tutamak,
  // kaydırma ve klavye dolgusu burada yeniden yazılmaz.
  return showRythoSheet<void>(
    context,
    klavyeyeUy: true,
    enableDrag: false,
    builder: (_) => const DeleteAccountSheet(),
  );
}
