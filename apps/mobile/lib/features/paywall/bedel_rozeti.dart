/// Bedel rozeti — bir özelliğin jeton bedelini HARCAMADAN ÖNCE söyler.
///
/// ## Neden var
/// Bedeli harcamadan önce gösteren tek yüzey İ Ching sekmesiydi ve o rozet
/// `/reports/iching/status`un `token_cost` alanından okuyordu. Öteki jetonlu
/// yüzeyler (natal, BaZi, yıl haritası, iç takvim, doğum kapısı, yüz okuma,
/// ikili) bedeli yalnız 402'de ya da mağazadaki toplu cümlede söylüyordu.
/// Cüzdan yanıtı `costs` haritasını zaten taşıyor (`WalletStatus.costs`);
/// bu rozet onu katalog anahtarıyla okur.
///
/// Kural (İ Ching rozetiyle aynı): cüzdan yükleniyor, okunamadı ya da bedel
/// yoksa rozet HİÇ çizilmez — ölçülmeyen söylenmez, uydurma sayı bayat
/// sayıdan kötü.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/wallet.dart';
import '../../l10n/app_localizations.dart';
import '../../theme/rytho_theme.dart';
import '../../theme/rytho_tokens.dart';
import 'ozellik_katalogu.dart';

/// Rozetin söyleyeceği sayı — ya da hiçbir şey.
///
/// Saf işlev: ekran kararı burada, widget yalnız çizer (`ichingBedeli`
/// emsali). `null` dönen her dal "rozet çizilmez" demek:
/// * cüzdan henüz yok ya da [WalletStatus.bilinmiyor] — okunamayan bakiyeyle
///   gelen `costs` da güvenilmez (o yanıt hiç gelmedi, harita boş);
/// * özelliğin bedel anahtarı yok (günlük okuma, çevre, takvim);
/// * sunucu o anahtarı göndermedi;
/// * sıfır/negatif — "bedava" sözü bozuk gövdeden üretilmez.
int? bedelOku(WalletStatus? cuzdan, PlusOzellik ozellik) {
  if (cuzdan == null || cuzdan.bilinmiyor) return null;
  final anahtar = ozellik.sunucuAdi;
  if (anahtar == null) return null;
  final bedel = cuzdan.costs[anahtar];
  if (bedel == null || bedel <= 0) return null;
  return bedel;
}

class BedelRozeti extends ConsumerWidget {
  const BedelRozeti(this.ozellik, {super.key, this.kucuk = false});

  final PlusOzellik ozellik;

  /// Karo köşesi: ikonsuz, yalnız sayı + birim. Karo ~110 px; ikon + hap
  /// dolgusu başlığın yerini yerdi.
  final bool kucuk;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // `.value`: tazeleme turunda (harcama sonrası) önceki cüzdan korunur,
    // rozet yanıp sönmez.
    final bedel = bedelOku(ref.watch(walletProvider).value, ozellik);
    if (bedel == null) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context);
    // Bedele özel ARB anahtarı yok (`tokenPackAmount` paket, `tokenBalanceChip`
    // bakiye anlamı taşıyor); birim sözcüğü + sayı. Çoğul farkı olan dilde
    // ayrı anahtar D7'de.
    final metin = '$bedel ${l10n.tokenUnit}';
    final stil = RythoType.dataSmall.copyWith(color: RythoColors.goldBright);
    if (kucuk) return Text(metin, style: stil);
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: RythoSpace.sm, vertical: RythoSpace.xxs),
      decoration: BoxDecoration(
        color: RythoColors.gold.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(RythoRadius.pill),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        // Jeton ikonu `TokenChip` ile aynı: kredi dili tek simgeyle konuşur.
        const Icon(Icons.toll_rounded,
            size: 11, color: RythoColors.goldBright),
        const SizedBox(width: RythoSpace.xs),
        Text(metin, style: stil),
      ]),
    );
  }
}
