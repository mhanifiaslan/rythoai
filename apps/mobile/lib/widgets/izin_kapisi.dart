/// Bildirim izni kapısı (sihirbaz adımı) ve "izin sistemde kapalı" bandı.
///
/// ## Neden var
/// Sihirbazın bildirim adımı tek düğmeyle ("Haber ver") soruyordu; "şimdi
/// değil" diyen kullanıcının kararı hiçbir yerde durmuyor, alt düğme "Sonra"
/// ile adım atlanıyordu — iki yol aynı şeyi iki dilde söylüyordu. İki
/// seçenekli segment kararı GÖRÜNÜR tutar ve `null` ile "henüz seçilmedi"
/// hâlini ayırır (ölçülmeyen söylenmez).
///
/// Band: notification_settings'teki `_PermissionBanner` yol tarifi veriyordu
/// ("Ayarlar → Uygulamalar → Rytho → Bildirimler") çünkü derin bağlantı
/// bağımlılığı yoktu. `app_settings` artık pakette; tarif yerine düğme.
library;

import 'package:app_settings/app_settings.dart';
import 'package:firebase_messaging/firebase_messaging.dart'
    show AuthorizationStatus;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/notifications.dart' show osBildirimDurumuProvider;
import '../l10n/app_localizations.dart';
import '../theme/rytho_theme.dart';
import '../theme/rytho_tokens.dart';
import 'glass.dart' show GlassSegments;

/// İki seçenekli izin sorusu: "Haber ver" / "Şimdi değil".
///
/// İkinci etiket "Sonra" DEĞİL: "Sonra" alt düğmenin, yani adımı ATLAMANIN
/// diliydi. Burada atlama yok, görünür bir karar var — "şimdi değil"
/// kullanıcının kendi kararı; OS'a sorulmaz, bayrak yazılmaz ve ana
/// ekrandaki ikinci şans yaşar (`wizardNotifyNotNow`, D4).
class IzinKapisi extends StatelessWidget {
  const IzinKapisi({
    super.key,
    required this.secim,
    required this.onSec,
    this.aciklama,
  });

  /// true = haber ver, false = şimdi değil, null = henüz seçilmedi.
  final bool? secim;
  final ValueChanged<bool> onSec;

  /// Segmentin üstündeki açıklama; verilmezse günlük bildirimin ne
  /// olduğunu söyleyen cümle (`notifyDailyBody`) — sihirbaz gövdesini
  /// tekrarlamaz, kararın NESNESİNİ söyler.
  final String? aciklama;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final s = secim;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(aciklama ?? l10n.notifyDailyBody, style: RythoType.bodyDim),
        const SizedBox(height: RythoSpace.md),
        GlassSegments(
          labels: [l10n.wizardNotifyAllow, l10n.wizardNotifyNotNow],
          index: s == null ? null : (s ? 0 : 1),
          onChanged: (i) => onSec(i == 0),
        ),
      ],
    );
  }
}

/// OS izni REDDEDİLMİŞSE dürüst band + ayarlara giden düğme; aksi hâlde
/// hiçbir şey.
///
/// Android'de izin yokken bile `getToken()` başarılı olduğu için sunucu
/// gönderiyor, sistem sessizce düşürüyor — kullanıcı uygulamadaki
/// anahtarları açık görüp "bildirim gelmiyor" diyordu. Sorun uygulamada
/// değil sistemde; düğme tam oraya götürür.
class IzinKapaliBandi extends ConsumerWidget {
  const IzinKapaliBandi({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final durum = ref.watch(osBildirimDurumuProvider).value;
    if (durum != AuthorizationStatus.denied) return const SizedBox.shrink();

    final l10n = AppLocalizations.of(context);
    return Container(
      margin: const EdgeInsets.only(top: RythoSpace.xs, bottom: RythoSpace.sm),
      padding: const EdgeInsets.all(RythoSpace.md),
      decoration: BoxDecoration(
        color: RythoColors.madder.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(RythoRadius.sm),
        border: Border.all(color: RythoColors.madder.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.notifications_off_outlined,
                  size: 18, color: RythoColors.madder),
              const SizedBox(width: RythoSpace.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(l10n.notifPermissionOffTitle, style: RythoType.body),
                    const SizedBox(height: RythoSpace.xxs),
                    Text(l10n.notifPermissionOffBody,
                        style: RythoType.caption),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: RythoSpace.sm),
          Align(
            alignment: Alignment.centerRight,
            // Düğme metni `settings` ("Ayarlar"): "Ayarları aç" anahtarı
            // ARB'de yok (ölçüldü 2026-10-10); ikon yönü söylüyor.
            child: OutlinedButton.icon(
              onPressed: () => AppSettings.openAppSettings(
                  type: AppSettingsType.notification),
              icon: const Icon(Icons.settings_outlined, size: 16),
              label: Text(l10n.settings),
            ),
          ),
        ],
      ),
    );
  }
}
