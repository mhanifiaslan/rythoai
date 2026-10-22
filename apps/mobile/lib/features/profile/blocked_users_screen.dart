import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/safety.dart';
import '../../l10n/app_localizations.dart';
import '../../theme/rytho_theme.dart';
import '../../theme/rytho_tokens.dart';
import '../../widgets/common.dart' show AsyncBolum;
import '../../widgets/glass.dart';
import '../../widgets/onay.dart' show onayla;
import 'profile_sections.dart' show SettingsPage;

/// ENGELLENENLER — Profil > Gizlilik altında (U17, App Store 1.2).
///
/// Engel kaydı eskiden yazılıyor ama hiçbir ekranda görünmüyordu:
/// yanlışlıkla engellenen birinin engelini kaldırmanın yolu yoktu. Liste
/// kaydın kendisinden okunur ([engellenenlerProvider]); arkadaşlık listesi
/// burada işe yaramaz, çünkü engelleme o kenarları siliyor.
class EngellenenlerEkrani extends ConsumerWidget {
  const EngellenenlerEkrani({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);

    return SettingsPage(
      title: l10n.blockedUsersTitle,
      children: [
        GlassPanel(
          child: Text(l10n.blockedUsersNote, style: RythoType.bodyDim),
        ),
        // `bosMu` VERİLMEDİ: boş liste bölümü gizlemez, "kimse yok" der —
        // gizlenseydi engellediği kimse olmayan kullanıcıya sayfa (notun
        // altında) hiçbir şey söylemezdi.
        AsyncBolum<List<EngellenenKullanici>>(
          durum: ref.watch(engellenenlerProvider),
          onRetry: () => ref.invalidate(engellenenlerProvider),
          veri: (kisiler) => kisiler.isEmpty
              ? Padding(
                  padding: const EdgeInsets.fromLTRB(
                      RythoSpace.xl, RythoSpace.xl, RythoSpace.xl, 0),
                  child: Text(l10n.blockedUsersEmpty,
                      textAlign: TextAlign.center, style: RythoType.bodyDim),
                )
              : GlassPanel(
                  padding: const EdgeInsets.symmetric(vertical: RythoSpace.xs),
                  child: Column(children: [
                    for (final (i, kisi) in kisiler.indexed) ...[
                      if (i > 0)
                        const Divider(height: 1, indent: RythoSpace.lg),
                      _EngelliSatiri(kisi: kisi),
                    ],
                  ]),
                ),
        ),
      ],
    );
  }
}

class _EngelliSatiri extends ConsumerWidget {
  const _EngelliSatiri({required this.kisi});

  final EngellenenKullanici kisi;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final kullaniciAdi = kisi.username == null ? null : '@${kisi.username}';
    final ad = kisi.displayName ?? kullaniciAdi ?? l10n.blockedUnknownUser;

    final altYazi = kisi.displayName != null ? kullaniciAdi : null;

    // `SettingsRow` KULLANILMADI: `trailing` yuvası esnemiyor ve "Engeli
    // kaldır" 320 dp × 1,3'te satırı taşırıyordu (engelleme_test dar ekran
    // bekçisi ölçtü). Görünüm aynı: ikon + başlık + alt yazı ve
    // SettingsRow'un dolguları (yatay lg, dikey md); `Wrap` sığmayınca
    // düğmeyi alt satıra indirir.
    return Padding(
      padding: const EdgeInsets.symmetric(
          horizontal: RythoSpace.lg, vertical: RythoSpace.md),
      child: SizedBox(
        width: double.infinity,
        child: Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: RythoSpace.sm,
          children: [
            Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.block_rounded,
                  size: 19, color: RythoColors.lilac),
              const SizedBox(width: RythoSpace.md),
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(ad, style: RythoType.body),
                    if (altYazi != null) ...[
                      const SizedBox(height: 2),
                      Text(altYazi, style: RythoType.caption),
                    ],
                  ],
                ),
              ),
            ]),
            TextButton(
              onPressed: () => _engeliKaldir(context, ref, ad),
              child: Text(l10n.unblockUser,
                  style: RythoType.button.copyWith(color: RythoColors.lilac)),
            ),
          ],
        ),
      ),
    );
  }

  /// Onay neden var: engelleme de onaylı, ama kaldırmanın bedeli ayrı —
  /// yanlış bir dokunuş, engellenen kişiye yeniden istek atma kapısını
  /// açar. Yıkıcı DEĞİL (`destructive: false`): geri dönüşü var, kişi
  /// yeniden engellenebilir. İşlev ve mesajcı İLK `await`ten önce alınır:
  /// engel kalkınca bu satır listeden düşer ve `ref` kullanılamaz.
  Future<void> _engeliKaldir(
      BuildContext context, WidgetRef ref, String ad) async {
    final l10n = AppLocalizations.of(context);
    final mesajci = ScaffoldMessenger.of(context);
    final kaldir = ref.read(engelKaldiriciProvider);
    final tamam = await onayla(
      context,
      title: l10n.unblockConfirmTitle(ad),
      body: l10n.unblockConfirmBody,
      confirmLabel: l10n.unblockUser,
    );
    if (!tamam) return;
    try {
      await kaldir(kisi.uid);
      mesajci.showSnackBar(
          SnackBar(content: Text(l10n.userUnblockedSnack(ad))));
    } catch (_) {
      mesajci.showSnackBar(SnackBar(content: Text(l10n.unblockFailed)));
    }
  }
}
