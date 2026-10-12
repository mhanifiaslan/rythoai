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
///
/// ## Ortak rozet
/// Satış ekranının bir satırı birden çok özelliği anıyor ("Yıl Haritası,
/// İç Takvim ve Doğum Kapısı"; "BaZi ve sinastri"). O satıra tek sayı
/// ancak ÜÇÜ DE aynı bedeldeyse yazılabilir — biri farklıysa cümle
/// kurulamaz ve rozet susar (`bedelNotu`nun "derin raporlar" özetiyle aynı
/// kural). [BedelRozeti.ortak] bunun için.
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

/// Birden çok özelliğin ORTAK bedeli — ya da hiçbir şey.
///
/// Hepsi okunabildi ve hepsi aynıysa o sayı; biri okunamadıysa ya da
/// sayılar ayrışıyorsa `null`. Boş liste de `null`: hiçbir şeyin bedeli
/// "bir sayı" değildir.
int? ortakBedel(WalletStatus? cuzdan, List<PlusOzellik> ozellikler) {
  if (ozellikler.isEmpty) return null;
  int? ortak;
  for (final o in ozellikler) {
    final b = bedelOku(cuzdan, o);
    if (b == null) return null;
    if (ortak != null && b != ortak) return null;
    ortak = b;
  }
  return ortak;
}

class BedelRozeti extends ConsumerWidget {
  /// Tek özelliğin bedeli.
  const BedelRozeti(PlusOzellik this.ozellik, {super.key, this.kucuk = false})
      : ozellikler = null;

  /// Birden çok özelliğin ORTAK bedeli (bkz. [ortakBedel]).
  const BedelRozeti.ortak(List<PlusOzellik> this.ozellikler,
      {super.key, this.kucuk = false})
      : ozellik = null;

  /// İki kurucu, iki alan: `const` kurucunun başlatıcısında liste literali
  /// kurulamıyor (`[ozellik]` sabit ifade değil), o yüzden tek liste alanı
  /// yerine ikisi — [liste] birleştirir.
  final PlusOzellik? ozellik;
  final List<PlusOzellik>? ozellikler;

  List<PlusOzellik> get liste => ozellikler ?? [ozellik!];

  /// Karo köşesi: ikonsuz, yalnız sayı + birim. Karo ~110 px; ikon + hap
  /// dolgusu başlığın yerini yerdi.
  final bool kucuk;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // `.value`: tazeleme turunda (harcama sonrası) önceki cüzdan korunur,
    // rozet yanıp sönmez.
    final bedel = ortakBedel(ref.watch(walletProvider).value, liste);
    if (bedel == null) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context);
    // `tokenCost` bedele özel anahtar: İngilizce tekil/çoğul ayrımı orada
    // (`tokenPackAmount` paket, `tokenBalanceChip` bakiye anlamı taşıyor).
    final metin = l10n.tokenCost(bedel);
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
