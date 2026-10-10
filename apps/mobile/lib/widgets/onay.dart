/// Onay diyaloğu ve onaylı çıkış — geri dönüşü olan/olmayan eylemlerin TEK
/// kapısı.
///
/// ## Neden var
/// Ölçüldü (2026-10-10): profildeki "Oturumu kapat" onaysızdı ve dock'un
/// hemen üstünde duruyordu — sekme değiştirmek isteyen başparmak bir
/// dokunuşla oturumu kapatıyordu. Arkadaş çıkarma/engelleme de onaysızdı;
/// yüz rızası geri alma ise kendi `AlertDialog`ını kuruyordu
/// (profile_sections). Üç kopya üç ayrı düğme diline gidiyordu; onay
/// sorusu bir kez yazılır, yıkıcı olanı `GoldButton(destructive)` giyer.
library;

import 'package:flutter/material.dart';

import '../core/auth_service.dart' show signOutEverywhere;
import '../l10n/app_localizations.dart';
import 'atlas_widgets.dart' show GoldButton;

/// Onay sorar; `true` yalnız kullanıcı onay düğmesine bastığında.
///
/// Dışarı dokunma, geri tuşu ve "Vazgeç" hepsi `false` — belirsiz kapanış
/// asla onay sayılmaz. [body] isteğe bağlı: tek satırlık soruya ikinci bir
/// cümle uydurulmaz. [destructive] yıkıcı eylem: onay düğmesi düz madder
/// dolgulu `GoldButton`, vazgeç metin düğmesi — iki düğme aynı ağırlıkta
/// olursa göz hangisinin geri dönüşsüz olduğunu okuyamaz.
Future<bool> onayla(
  BuildContext context, {
  required String title,
  String? body,
  required String confirmLabel,
  bool destructive = false,
}) async {
  final l10n = AppLocalizations.of(context);
  final sonuc = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(title),
      content: body == null ? null : Text(body),
      // Yıkıcı düğme tam genişlik ister; OverflowBar sığmayınca düğmeleri
      // alt alta dizer ve ortalar — "Vazgeç" üstte, yıkıcı eylem altta.
      actionsOverflowAlignment: OverflowBarAlignment.center,
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(c, false),
          child: Text(l10n.cancel),
        ),
        if (destructive)
          GoldButton(
            text: confirmLabel,
            destructive: true,
            onPressed: () => Navigator.pop(c, true),
          )
        else
          TextButton(
            onPressed: () => Navigator.pop(c, true),
            child: Text(confirmLabel),
          ),
      ],
    ),
  );
  return sonuc ?? false;
}

/// Onay alıp oturumu kapatır; [onay] false ise doğrudan (cihaz çakışma
/// ekranı gibi kullanıcının zaten "çıkış" dediği yerler).
///
/// [cikis] test dikişi; üretimde `signOutEverywhere` (core/auth_service.dart)
/// — cihaz kilidi, push jetonu ve çakışma bayrağı orada sırayla iner,
/// buradan tek tek çağrılmaz.
///
/// [body] sorunun gövdesi; verilmezse `signOutConfirmBody` (bildirimler
/// bu cihazda durur, yeniden girince kaldığın yerden). Gövde ŞART çünkü
/// "Oturumu kapat?" tek başına çıkışın bedelini söylemiyor; kullanıcı
/// "verim gider mi?" sorusuyla ya vazgeçiyor ya korkarak basıyordu.
Future<void> onayliCikis(
  BuildContext context, {
  bool onay = true,
  String? body,
  Future<void> Function() cikis = signOutEverywhere,
}) async {
  if (onay) {
    final l10n = AppLocalizations.of(context);
    // Başlık ve onay düğmesi aynı sözcük: "Oturumu kapat". Eskiden düğme
    // cihaz çakışma ekranının "Çıkış yap"ını ödünç alıyordu — aynı eylem
    // iki ekranda iki adla anılıyordu (D4: TEK anahtar `signOut`).
    final tamam = await onayla(
      context,
      title: l10n.signOut,
      body: body ?? l10n.signOutConfirmBody,
      confirmLabel: l10n.signOut,
    );
    if (!tamam) return;
  }
  await cikis();
}
