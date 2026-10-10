/// Liste satırı — solda öncü (emoji/avatar/ikon), ortada başlık + alt
/// satır, sağda ek öğe ya da chevron; kart kabında, basınca küçülür.
///
/// NEDEN: aynı satır beş ayrı sınıfta yaşıyordu (`_AtlasRow`,
/// `_EylemSatiri`, friend_detail'in GlassPanel satırı, `_FriendTile` /
/// `_PersonTile`, `_DivinationTile`) ve her biri bir şeyi farklı
/// yapıyordu: biri başlığı tek satıra kırpıp ellipsis koyuyor, biri alt
/// satırı esnetmiyor, birinin kilidi emoji birinin ikon. Kullanıcının
/// "dağınık" dediği his tam olarak bu küçük farkların toplamı.
library;

import 'package:flutter/material.dart';

import '../theme/rytho_theme.dart';
import '../theme/rytho_tokens.dart';
import 'nebula_widgets.dart' show Pressable;

class ListeSatiri extends StatelessWidget {
  const ListeSatiri({
    super.key,
    required this.leading,
    required this.title,
    this.subtitle,
    this.subtitleLines = 1,
    this.trailing,
    this.onTap,
    this.locked = false,
    this.margin = const EdgeInsets.symmetric(vertical: RythoSpace.xs),
  });

  /// Soldaki öncü: emoji, avatar, ikon. Boyutu çağıran verir.
  final Widget leading;

  final String title;
  final String? subtitle;

  /// Alt satırın tavanı. Varsayılan 1: liste tek bakışta taranır. Hata
  /// dalında 3 — "harcanan jeton iade edildi" cümlesi tek satıra sığmıyor
  /// ve ellipsis tam da söylenmesi gereken yeri kesiyordu (gz-2).
  final int subtitleLines;

  /// Sağ uç; verilmezse dokunulabilir satırda chevron.
  final Widget? trailing;

  final VoidCallback? onTap;

  /// Rytho+ kilidi: sağda kilit işareti; dokunuş çağıranın kararı
  /// (paywall). Şimdilik düz ikon — D6'da `KilitRozeti`ne geçer.
  final bool locked;

  /// Dış boşluk; liste yatay dolgusunu kendisi veriyorsa varsayılan
  /// yalnız dikeydir.
  final EdgeInsets margin;

  @override
  Widget build(BuildContext context) {
    final dokunulur = onTap != null;
    final sag = <Widget>[
      if (locked) ...[
        const SizedBox(width: RythoSpace.sm),
        // Ekran okuyucu "kilit" değil ürünün adını duyar: kilit neyin
        // kilidi, sorusu cevapsız kalmasın.
        Semantics(
          label: kPlusAdi,
          child: const Icon(Icons.lock_rounded,
              size: 14, color: RythoColors.goldBright),
        ),
      ],
      if (trailing != null) ...[
        const SizedBox(width: RythoSpace.sm),
        trailing!,
      ] else if (dokunulur) ...[
        const SizedBox(width: RythoSpace.xs),
        const Icon(Icons.chevron_right_rounded,
            size: 18, color: RythoColors.parchmentDim),
      ],
    ];

    // Tek semantik düğüm `Pressable`dan gelir (MergeSemantics + düğme
    // bayrağı, yalnız onTap varken): ekran okuyucu "başlık, alt satır,
    // Rytho+, düğme" diye BİR öğe duyar; ayrıca sarmak düğümü ikiye
    // bölüyordu (ölçüldü: dış düğüm etiketsiz, iç düğüm "merged up").
    return Pressable(
      onTap: onTap,
      child: Container(
        margin: margin,
        // Alt satırsız kısa başlıkta kutu 48 dp'nin altına iniyordu;
        // dokunma hedefi tabanı Material'ın kendi sabiti.
        constraints:
            const BoxConstraints(minHeight: kMinInteractiveDimension),
        padding: const EdgeInsets.symmetric(
            horizontal: RythoSpace.md, vertical: RythoSpace.md),
        decoration: BoxDecoration(
          color: RythoColors.glassFill,
          borderRadius: BorderRadius.circular(RythoRadius.card),
          border: Border.all(color: RythoColors.glassStroke),
        ),
        child: Row(children: [
          leading,
          const SizedBox(width: RythoSpace.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Başlıkta ellipsis YOK (design-system §9b): kullanıcı
                // adı/konuyu OKUMAK ister, "…" tam da ayırt edici kısmı
                // keser. İki satır: 320 dp × 1,3'te en uzun başlıklar için
                // ölçülen tavan; dar ekranda sarar.
                Text(title, maxLines: 2, style: RythoType.cardTitle),
                if (subtitle != null) ...[
                  const SizedBox(height: RythoSpace.xxs),
                  // Alt satır tekrar eden veridir (burç, tarih, durum) —
                  // burada kısaltma serbest.
                  Text(subtitle!,
                      maxLines: subtitleLines,
                      overflow: TextOverflow.ellipsis,
                      style: RythoType.caption),
                ],
              ],
            ),
          ),
          ...sag,
        ]),
      ),
    );
  }
}
